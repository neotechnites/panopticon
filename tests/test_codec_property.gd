extends TestCase

## The codec property harness (DESIGN.md Phase T): 10,000 ticks of random world and input changes
## through a wire that loses, bursts, duplicates and reorders, with scene epochs changing under it.
## Whatever a receiver accepts must equal, bit for bit, what the sender recorded for that tick, and
## no packet may reach 1200 bytes. Run on each wire format as it lands.

const TICKS: int = 10000
const SNAPSHOT_EVERY: int = 2
const TICK_MS: float = 1000.0 / 60.0
const MTU_BUDGET: int = 1200
const INTENT_REDUNDANCY: int = 3
const SEED: int = 794

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state_fields: PackedStringArray = PackedStringArray()
var _intent_fields: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_rng.seed = SEED
	_state_fields = _script_fields(PlayerState.new())
	_intent_fields = _script_fields(MoveIntent.new())


## A wire as bad as any the design claims to survive, in both directions.
func _wire(rng_seed: int) -> NetConditions:
	var wire: NetConditions = NetConditions.new(rng_seed)
	wire.delay_ms = 40.0
	wire.jitter_ms = 30.0
	wire.jitter_reorders = true
	wire.loss = 0.1
	wire.burst_ms = 120.0
	wire.burst_gap_ms = 1500.0
	wire.duplicate = 0.1
	wire.reorder = 0.1
	wire.reorder_ms = 80.0
	return wire


func test_every_accepted_snapshot_is_the_host_world_of_its_tick() -> void:
	var counts: Dictionary[String, int] = _snapshots(false, 0.0)
	assert_eq_int(counts["malformed"], 0, "every packet the host built decodes")
	assert_eq_int(counts["mismatch"], 0, "every accepted snapshot is bit for bit the host's world at its tick, in its epoch")
	assert_eq_int(counts["backwards"], 0, "an accepted snapshot is never older than one accepted before it")
	assert_eq_int(counts["oversize"], 0, "no snapshot reaches %d bytes" % MTU_BUDGET)
	assert_gt(float(counts["stale"]), 0.0, "the wire did reorder and duplicate: stale packets were refused")
	assert_gt(float(counts["old_epoch"]), 0.0, "and packets from a gone epoch arrived and were refused")
	assert_gt(float(counts["accepted"]), float(counts["sent"]) * 0.5, "while most snapshots still got through")
	assert_gt(float(counts["epochs"]), 8.0, "across many epoch changes")


func test_the_harness_sees_a_receiver_that_takes_stale_packets_and_a_wire_that_corrupts() -> void:
	assert_gt(float(_snapshots(true, 0.0)["backwards"]), 0.0, "taking every packet goes back in time")
	assert_gt(float(_snapshots(false, 0.02)["mismatch"]), 0.0, "a flipped bit is a world that is not the host's")


## Run the host and a receiver for [constant TICKS]; [param take_stale] drops the receiver's order rule and
## [param corrupt] flips one bit in that share of packets, to show the checks bite.
func _snapshots(take_stale: bool, corrupt: float) -> Dictionary[String, int]:
	_rng.seed = SEED
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = SEED + 1
	var wire: NetConditions = _wire(1)
	var world: Array[PlayerState] = _bodies(8)
	var recorded: Dictionary[int, PackedByteArray] = {}
	var epoch_of_tick: Dictionary[int, int] = {}
	var host_epoch: int = 1
	var client_epoch: int = 1
	var epoch_due: int = -1
	var next_bump: int = _rng.randi_range(300, 1200)
	var received: WorldSnapshot = WorldSnapshot.new()
	var fresh: WorldSnapshot = WorldSnapshot.new()
	var newest: int = -1
	var counts: Dictionary[String, int] = {"sent": 0, "arrived": 0, "accepted": 0, "stale": 0, "old_epoch": 0,
		"mismatch": 0, "malformed": 0, "oversize": 0, "epochs": 1, "backwards": 0}
	var largest: int = 0
	for tick: int in TICKS:
		var now: float = float(tick) * TICK_MS
		if tick == next_bump:
			# A launch, rematch or return to the hub: the host's epoch moves now, the client's when the
			# reliable roster carrying it lands.
			host_epoch = (host_epoch + 1) % NetCodec.EPOCH_MODULUS
			epoch_due = tick + _rng.randi_range(2, 20)
			next_bump = tick + _rng.randi_range(300, 1200)
			counts["epochs"] += 1
			world = _bodies(_rng.randi_range(1, 8))
		if tick == epoch_due:
			client_epoch = host_epoch
			newest = -1
		for body: PlayerState in world:
			_change(body, tick)
		if tick % SNAPSHOT_EVERY == 0:
			var snapshot: WorldSnapshot = WorldSnapshot.new()
			snapshot.tick = tick
			snapshot.scene = host_epoch
			for body: PlayerState in world:
				snapshot.append(body)
			var bytes: PackedByteArray = NetCodec.pack_snapshot(snapshot)
			largest = maxi(largest, bytes.size())
			counts["oversize"] += int(bytes.size() >= MTU_BUDGET)
			# What the host knows it said for this tick: the world as the wire carries it.
			NetCodec.unpack_snapshot(bytes, fresh)
			recorded[tick] = _world_bytes(fresh)
			epoch_of_tick[tick] = host_epoch
			wire.push(1, false, bytes, now)
			counts["sent"] += 1
		for bytes: PackedByteArray in wire.pop_due(now):
			counts["arrived"] += 1
			if corrupt > 0.0 and noise.randf() < corrupt:
				bytes = bytes.duplicate()
				var at: int = noise.randi_range(NetCodec.SNAPSHOT_HEADER_SIZE, bytes.size() - 1)
				bytes[at] = bytes[at] ^ (1 << noise.randi_range(0, 7))
			if not NetCodec.unpack_snapshot(bytes, received):
				counts["malformed"] += 1
				continue
			if received.scene != client_epoch:
				counts["old_epoch"] += 1
				continue
			if newest >= 0 and not NetCodec.is_newer_tick(received.tick, newest) and not take_stale:
				counts["stale"] += 1
				continue
			counts["backwards"] += int(newest >= 0 and received.tick < newest)
			newest = received.tick
			counts["accepted"] += 1
			if _world_bytes(received) != recorded.get(received.tick, PackedByteArray()) \
					or epoch_of_tick.get(received.tick, -1) != client_epoch:
				counts["mismatch"] += 1
	print("          SNAPSHOTS over %d ticks%s: %s; largest %d B" % [TICKS,
		" (taking stale)" if take_stale else (" (corrupting %.0f%%)" % (corrupt * 100.0) if corrupt > 0.0 else ""),
		str(counts), largest])
	return counts


func test_every_intent_the_host_reads_is_the_one_the_client_sent_for_that_tick() -> void:
	var wire: NetConditions = _wire(2)
	var recorded: Dictionary[int, PackedByteArray] = {}
	var epoch_of_tick: Dictionary[int, int] = {}
	var history: Array[MoveIntent] = []
	var host_epoch: int = 1
	var client_epoch: int = 1
	var client_due: int = -1
	var next_bump: int = _rng.randi_range(300, 1200)
	var decoded: MoveIntent = MoveIntent.new()
	var fresh: MoveIntent = MoveIntent.new()
	var heard: Dictionary[int, bool] = {}
	var counts: Dictionary[String, int] = {"sent": 0, "arrived": 0, "intents": 0, "old_epoch": 0, "mismatch": 0,
		"epoch_mixed": 0, "malformed": 0, "oversize": 0, "epochs": 1}
	for tick: int in TICKS:
		var now: float = float(tick) * TICK_MS
		if tick == next_bump:
			host_epoch = (host_epoch + 1) % NetCodec.EPOCH_MODULUS
			client_due = tick + _rng.randi_range(2, 20)
			next_bump = tick + _rng.randi_range(300, 1200)
			counts["epochs"] += 1
		if tick == client_due:
			# The client's links belong to the scene: a new epoch starts their history afresh.
			client_epoch = host_epoch
			history.clear()
		var intent: MoveIntent = _intent(tick)
		NetCodec.unpack_intent(NetCodec.pack_intent(tick, intent, client_epoch), fresh)
		recorded[tick] = _object_bytes(fresh, _intent_fields)
		epoch_of_tick[tick] = client_epoch
		history.append(intent)
		if history.size() > INTENT_REDUNDANCY:
			history.pop_front()
		var bytes: PackedByteArray = NetCodec.pack_intents(tick, history, history.size(), client_epoch)
		counts["oversize"] += int(bytes.size() >= MTU_BUDGET)
		wire.push(1, false, bytes, now)
		counts["sent"] += 1
		for packet: PackedByteArray in wire.pop_due(now):
			counts["arrived"] += 1
			var carried: int = NetCodec.intent_count(packet)
			if carried == 0:
				counts["malformed"] += 1
				continue
			if NetCodec.intent_epoch(packet) != host_epoch:
				counts["old_epoch"] += 1
				continue
			for i: int in carried:
				var at: int = NetCodec.unpack_intent_at(packet, i, decoded)
				counts["intents"] += 1
				heard[at] = true
				if _object_bytes(decoded, _intent_fields) != recorded.get(at, PackedByteArray()):
					counts["mismatch"] += 1
				counts["epoch_mixed"] += int(epoch_of_tick.get(at, -1) != host_epoch)
	print("          INTENTS over %d ticks: %s; %.4f of ticks reached the host at least once" % [
		TICKS, str(counts), float(heard.size()) / TICKS])
	assert_eq_int(counts["malformed"], 0, "every packet the client built decodes")
	assert_eq_int(counts["mismatch"], 0, "every intent the host reads is bit for bit the one sent for its tick")
	assert_eq_int(counts["epoch_mixed"], 0, "and no intent of one epoch is read in another")
	assert_eq_int(counts["oversize"], 0, "no intent packet reaches %d bytes" % MTU_BUDGET)
	assert_gt(float(counts["old_epoch"]), 0.0, "packets from the client's old epoch arrived and were refused")
	assert_gt(float(heard.size()) / TICKS, 0.8, "the redundancy carried most ticks through the loss")


# --- Random state -------------------------------------------------------------

func _bodies(count: int) -> Array[PlayerState]:
	var bodies: Array[PlayerState] = []
	var seats: Array[int] = []
	for seat: int in NetTransport.MAX_PLAYERS:
		seats.append(seat)
	for i: int in count:
		var body: PlayerState = PlayerState.new()
		body.seat_index = seats.pop_at(_rng.randi_range(0, seats.size() - 1))
		body.position = Vector3(_rng.randf_range(-300.0, 300.0), _rng.randf_range(-50.0, 100.0), _rng.randf_range(-300.0, 300.0))
		body.health = _rng.randi_range(0, 255)
		bodies.append(body)
	return bodies


## Every field the snapshot carries takes a random step, some each tick and some rarely.
func _change(body: PlayerState, tick: int) -> void:
	body.tick = tick
	var step: Vector3 = Vector3(_rng.randfn(0.0, 0.2), _rng.randfn(0.0, 0.1), _rng.randfn(0.0, 0.2))
	body.position = (body.position + step).clamp(Vector3.ONE * -330.0, Vector3.ONE * 330.0)
	body.velocity = Vector3(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-40.0, 20.0), _rng.randf_range(-14.0, 14.0))
	body.yaw = wrapf(body.yaw + _rng.randfn(0.0, 0.3), -PI, PI)
	body.pitch = clampf(body.pitch + _rng.randfn(0.0, 0.1), -1.55, 1.55)
	if _rng.randf() < 0.02:
		body.view_base = _rng.randf_range(-PI, PI)
	body.on_floor = _flip(body.on_floor, 0.1)
	body.sliding = _flip(body.sliding, 0.05)
	body.crouching = _flip(body.crouching, 0.05)
	body.emoting = _flip(body.emoting, 0.01)
	body.emote_alt = _flip(body.emote_alt, 0.01)
	body.is_finisher = _flip(body.is_finisher, 0.002)
	body.is_armed = _flip(body.is_armed, 0.002)
	if _rng.randf() < 0.05:
		body.jump_counter = (body.jump_counter + 1) % NetCodec.JUMP_COUNTER_MODULUS
	if _rng.randf() < 0.03:
		body.shove_counter = (body.shove_counter + 1) % NetCodec.SHOVE_COUNTER_MODULUS
	if _rng.randf() < 0.01:
		body.ability = _rng.randi_range(0, 5)
		body.ability_remaining = _rng.randf_range(0.0, 25.0)
		body.cooldown_remaining = _rng.randf_range(0.0, 25.0)
	body.ability_remaining = maxf(body.ability_remaining - 1.0 / 60.0, 0.0)
	body.cooldown_remaining = maxf(body.cooldown_remaining - 1.0 / 60.0, 0.0)
	if _rng.randf() < 0.01:
		body.health = _rng.randi_range(0, 255)
	if _rng.randf() < 0.01:
		body.boost_remaining = _rng.randf_range(0.0, 25.0)
		body.boost_multiplier = _rng.randf_range(0.5, 3.0)
	body.boost_remaining = maxf(body.boost_remaining - 1.0 / 60.0, 0.0)
	body.last_intent_tick = -1 if _rng.randf() < 0.01 else maxi(tick - _rng.randi_range(0, 12), 0)


func _intent(tick: int) -> MoveIntent:
	var intent: MoveIntent = MoveIntent.new()
	intent.move_direction = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).limit_length(1.0)
	intent.view_angles = Vector2(_rng.randf_range(-PI, PI), _rng.randf_range(-1.5, 1.5))
	intent.view_absolute = true
	intent.view_tick = -1 if _rng.randf() < 0.05 else maxi(tick - _rng.randi_range(0, 10), 0)
	for field: String in ["jump_pressed", "jump_held", "slide_pressed", "slide_held", "fire_pressed", "fire_held",
			"ability_pressed", "ability_held", "cook_pressed", "shove_pressed", "emote_pressed", "emote_alt_pressed",
			"aim_held"]:
		intent.set(field, _rng.randf() < 0.2)
	intent.ability_slot = _rng.randi_range(0, 5)
	intent.press_slot = _rng.randi_range(0, 5)
	intent.press_slot_prior = _rng.randi_range(0, 5)
	intent.press_counts = _rng.randi_range(0, MoveIntent.PRESS_COUNTS_MASK)
	intent.emote_state = _rng.randi_range(-1, 1)
	return intent


func _flip(value: bool, chance: float) -> bool:
	return not value if _rng.randf() < chance else value


# --- Bit-for-bit comparison ---------------------------------------------------

## Every script variable of [param object]'s class: a field added later is compared without a change here.
func _script_fields(object: Object) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for property: Dictionary in object.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(String(property["name"]))
	return names


func _object_bytes(object: Object, fields: PackedStringArray) -> PackedByteArray:
	var values: Array = []
	for field: String in fields:
		values.append(object.get(field))
	return var_to_bytes(values)


func _world_bytes(snapshot: WorldSnapshot) -> PackedByteArray:
	var out: PackedByteArray = var_to_bytes([snapshot.tick, snapshot.scene, snapshot.count])
	for i: int in snapshot.count:
		out.append_array(_object_bytes(snapshot.states[i], _state_fields))
	return out
