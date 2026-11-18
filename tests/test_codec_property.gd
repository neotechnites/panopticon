extends TestCase

## The codec property harness (DESIGN.md Phase T): 10,000 ticks across the tick wrap, of random world and
## input changes through a wire that loses, bursts, duplicates and reorders, with scene epochs changing.
## Each packet carries its source within each field's quantum, decodes to a fixed point, and stays under
## 1200 bytes; whatever a receiver accepts equals, bit for bit, what the sender recorded for that tick.

const TICKS: int = 10000
const SNAPSHOT_EVERY: int = 2
const TICK_MS: float = 1000.0 / 60.0
const MTU_BUDGET: int = 1200
const SEED: int = 794
## The run starts this close to the tick wrap so it crosses it: the order rule must survive the wrap.
const FIRST_TICK: int = NetCodec.TICK_MODULUS - 5000

## Properties the base codec breaks, found by this harness (FINDINGS/phaseT.md); none is game-visible
## today, all matter once a delta codec keeps decoded worlds as baselines. A fix must take its line out.
const KNOWN_DEFECTS: PackedStringArray = [
	"fixed point: boost_remaining",  # ceil of tenths read back as n*0.1 ceils one tenth higher
	"fixed point: yaw",  # quantise_turn truncates, and k/65536 of a turn truncates to k-1
	"fixed point: view_base",  # the same
	"sentinel: cmd_ack",  # sequence 0xFFFFFFFF is NO_ACK on the wire
]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Codec properties broken this run, by name, with how often.
var _defects: Dictionary[String, int] = {}
var _state_fields: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_rng.seed = SEED
	_defects.clear()
	_state_fields = _script_fields(PlayerState.new())


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
	assert_eq_int(counts["unfaithful"], 0, "every body field arrives within its quantum of the host's value")
	assert_eq_int(counts["mismatch"], 0, "every accepted snapshot is bit for bit the host's world at its tick, in its epoch")
	assert_eq_int(counts["backwards"], 0, "an accepted snapshot is never older than one accepted before it")
	assert_eq_int(counts["oversize"], 0, "no snapshot reaches %d bytes" % MTU_BUDGET)
	assert_gt(float(counts["stale"]), 0.0, "the wire did reorder and duplicate: stale packets were refused")
	assert_gt(float(counts["old_epoch"]), 0.0, "and packets from a gone epoch arrived and were refused")
	assert_gt(float(counts["accepted"]), float(counts["sent"]) * 0.5, "while most snapshots still got through")
	assert_gt(float(counts["epochs"]), 8.0, "across many epoch changes")


func test_the_codec_breaks_only_the_properties_already_known() -> void:
	_snapshots(false, 0.0)
	_commands()
	var unknown: PackedStringArray = PackedStringArray()
	for defect: String in _defects:
		if not KNOWN_DEFECTS.has(defect):
			unknown.append("%s (x%d)" % [defect, _defects[defect]])
	var mended: PackedStringArray = PackedStringArray()
	for defect: String in KNOWN_DEFECTS:
		if not _defects.has(defect):
			mended.append(defect)
	assert_eq_string(", ".join(unknown), "", "no codec property breaks that is not already known")
	assert_eq_string(", ".join(mended), "", "every known defect still shows (one that is mended leaves the list)")
	if unknown.is_empty() and mended.is_empty():
		skip("base codec defects, carried until the wire format is rebuilt (DESIGN.md Phase 3): %s" % str(_defects))


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
		"mismatch": 0, "malformed": 0, "oversize": 0, "epochs": 1, "backwards": 0, "unfaithful": 0}
	var largest: int = 0
	for step: int in TICKS:
		var tick: int = (FIRST_TICK + step) % NetCodec.TICK_MODULUS
		var now: float = float(step) * TICK_MS
		if step == next_bump:
			# A launch, rematch or return to the hub: the host's epoch moves now, the client's when the
			# reliable roster carrying it lands.
			host_epoch = (host_epoch + 1) % NetCodec.EPOCH_MODULUS
			epoch_due = step + _rng.randi_range(2, 20)
			next_bump = step + _rng.randi_range(300, 1200)
			counts["epochs"] += 1
			world = _bodies(_rng.randi_range(1, 8))
		if step == epoch_due:
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
			counts["unfaithful"] += _unfaithful(snapshot, fresh)
			var again: WorldSnapshot = WorldSnapshot.new()
			NetCodec.unpack_snapshot(NetCodec.pack_snapshot(fresh), again)
			for i: int in fresh.count:
				for field: String in _state_fields:
					if fresh.states[i].get(field) != again.states[i].get(field):
						_defect("fixed point: " + field)
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
			counts["backwards"] += int(newest >= 0 and NetCodec.tick_delta(newest, received.tick) <= 0)
			newest = received.tick
			counts["accepted"] += 1
			if _world_bytes(received) != recorded.get(received.tick, PackedByteArray()) \
					or epoch_of_tick.get(received.tick, -1) != client_epoch:
				counts["mismatch"] += 1
	print("          SNAPSHOTS over %d ticks%s: %s; largest %d B" % [TICKS,
		" (taking stale)" if take_stale else (" (corrupting %.0f%%)" % (corrupt * 100.0) if corrupt > 0.0 else ""),
		str(counts), largest])
	return counts


func test_every_command_the_host_runs_is_the_one_the_client_numbered() -> void:
	var counts: Dictionary[String, int] = _commands()
	assert_eq_int(counts["malformed"], 0, "every packet the client built decodes")
	assert_eq_int(counts["mismatch"], 0, "every command the host runs is, on the wire's quantum, the one sent as its number")
	assert_eq_int(counts["out_of_order"], 0, "and runs once, after the one before it")
	assert_eq_int(counts["epoch_mixed"], 0, "and no command of one epoch is run in another")
	assert_eq_int(counts["oversize"], 0, "no command packet reaches %d bytes" % MTU_BUDGET)
	assert_gt(float(counts["old_epoch"]), 0.0, "packets from the client's old epoch arrived and were refused")
	assert_eq_int(counts["skipped_unforced"], 0, "resent until acknowledged, no command is skipped but one the client had moved 32 past")
	assert_gt(float(counts["ran"]), float(counts["made"]) * 0.9, "and the stream ran the commands it was sent")


## The client's commands over [constant TICKS] through the wire to a real [CommandStream] that runs them
## at its ticks, and its acknowledgements back the other way. Host ticks cross the u32 wrap.
func _commands() -> Dictionary[String, int]:
	_rng.seed = SEED
	var up: NetConditions = _wire(2)
	var down: NetConditions = _wire(3)
	var outbox: CommandStream.Outbox = CommandStream.Outbox.new()
	var stream: CommandStream = CommandStream.new()
	var scratch: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_COMMANDS:
		scratch.append(MoveIntent.new())
	var recorded: Dictionary[int, PackedInt64Array] = {}
	var epoch_of: Dictionary[int, int] = {}
	var host_epoch: int = 1
	var client_epoch: int = 1
	var client_due: int = -1
	var next_bump: int = _rng.randi_range(300, 1200)
	# The newest snapshot tick the client has heard, as the wire carries it and on the host's own clock.
	var snap_wire: int = -1
	var snap_host: int = -1
	var last_ran: int = -1
	var counts: Dictionary[String, int] = {"made": 0, "ran": 0, "old_epoch": 0, "mismatch": 0, "out_of_order": 0,
		"epoch_mixed": 0, "malformed": 0, "oversize": 0, "epochs": 1, "skipped_resync": 0, "skipped_unforced": 0}
	# A new epoch's first run follows the old epoch's last without a skip: that tail is discarded by design.
	var epoch_began: bool = true
	for step: int in TICKS:
		var host_tick: int = FIRST_TICK + step
		var now: float = float(step) * TICK_MS
		if step == next_bump:
			host_epoch = (host_epoch + 1) % NetCodec.EPOCH_MODULUS
			stream.reset()
			epoch_began = true
			client_due = step + _rng.randi_range(2, 20)
			next_bump = step + _rng.randi_range(300, 1200)
			counts["epochs"] += 1
		if step == client_due:
			client_epoch = host_epoch
			outbox.flush()
		var command: MoveIntent = MoveIntent.new()
		command.move_direction = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).limit_length(1.0)
		command.view_angles = Vector2(_rng.randf_range(-PI, PI), _rng.randf_range(-1.5, 1.5))
		command.view_absolute = true
		command.buttons = _rng.randi() & MoveIntent.BUTTON_MASK if _rng.randf() < 0.2 else 0
		# Drawn a little behind the newest snapshot heard, in 64ths, as a client's playout clock is.
		var behind: int = _rng.randi_range(0, 30 * 64)
		command.view_time = MoveIntent.LIVE_WORLD if snap_wire < 0 else float(snap_wire) - float(behind) / 64.0
		var seq: int = outbox.push(command)
		var move: Vector2i = NetCodec.quantise_move(command.move_direction)
		recorded[seq] = PackedInt64Array([command.buttons, move.x, move.y, NetCodec.quantise_turn(command.view_angles.x),
			NetCodec.quantise_pitch(command.view_angles.y), -1 if snap_wire < 0 else snap_host * 64 - behind])
		epoch_of[seq] = client_epoch
		# A command made before the client has heard of the host's new epoch can never run.
		counts["made"] += int(client_epoch == host_epoch)
		var bytes: PackedByteArray = outbox.pack(client_epoch, snap_wire)
		counts["oversize"] += int(bytes.size() >= MTU_BUDGET)
		up.push(1, false, bytes, now)
		for packet: PackedByteArray in up.pop_due(now):
			if NetCodec.unpack_commands(packet, scratch, 0) == 0:
				counts["malformed"] += 1
				continue
			if NetCodec.command_epoch(packet) != host_epoch:
				counts["old_epoch"] += 1
				continue
			stream.receive(packet, host_tick)
		for _i: int in stream.commands_due():
			var ran: MoveIntent = stream.next_command(TICK_MS / 1000.0)
			if stream.get_ack() == last_ran:
				continue
			if last_ran >= 0 and not epoch_began and stream.get_ack() > last_ran + 1:
				counts["skipped_resync"] += stream.get_ack() - last_ran - 1
				counts["skipped_unforced"] += int(outbox.next_seq() - 1 - last_ran < NetCodec.MAX_COMMANDS)
			epoch_began = false
			counts["out_of_order"] += int(last_ran >= 0 and stream.get_ack() <= last_ran)
			last_ran = stream.get_ack()
			counts["ran"] += 1
			counts["epoch_mixed"] += int(epoch_of.get(last_ran, -1) != host_epoch)
			var got: Vector2i = NetCodec.quantise_move(ran.move_direction)
			var carried: PackedInt64Array = PackedInt64Array([ran.buttons, got.x, got.y,
				_turn_step(ran.view_angles.x), NetCodec.quantise_pitch(ran.view_angles.y),
				-1 if not is_finite(ran.view_time) else roundi(ran.view_time * NetCodec.VIEW_TIME_STEPS)])
			counts["mismatch"] += int(carried != recorded.get(last_ran, PackedInt64Array()))
		stream.end_tick()
		if step % SNAPSHOT_EVERY == 0:
			var ack: PackedByteArray = PackedByteArray()
			ack.resize(12)
			ack.encode_s64(0, stream.get_ack())
			ack.encode_u32(8, host_tick % NetCodec.TICK_MODULUS)
			down.push(1, false, ack, now)
		for packet: PackedByteArray in down.pop_due(now):
			outbox.acknowledge(packet.decode_s64(0))
			var heard: int = packet.decode_u32(8)
			if snap_wire < 0 or NetCodec.is_newer_tick(heard, snap_wire):
				snap_host += NetCodec.tick_delta(snap_wire, heard) if snap_wire >= 0 else 0
				if snap_wire < 0:
					snap_host = host_tick - NetCodec.tick_delta(heard, host_tick % NetCodec.TICK_MODULUS)
				snap_wire = heard
	stream.free()
	print("          COMMANDS over %d ticks: %s" % [TICKS, str(counts)])
	return counts


## The yaw step a decoded angle came from: the decoder's exact inverse ([method NetCodec.quantise_turn]
## truncates, a known defect above, and would read k/65536 of a turn back as k - 1).
func _turn_step(radians: float) -> int:
	return posmod(roundi(fposmod(radians, TAU) / TAU * 65536.0), 65536)


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
		body.boost_multiplier = 1.0
		body.health = _rng.randi_range(0, 255)
		bodies.append(body)
	return bodies


## Every field the snapshot carries takes a random step, some each tick and some rarely.
func _change(body: PlayerState, tick: int) -> void:
	body.tick = tick
	var step: Vector3 = Vector3(_rng.randfn(0.0, 0.2), _rng.randfn(0.0, 0.1), _rng.randfn(0.0, 0.2))
	body.position = (body.position + step).clamp(Vector3.ONE * -320.0, Vector3.ONE * 320.0)
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
	body.cmd_ack = -1 if _rng.randf() < 0.01 else posmod(tick - _rng.randi_range(0, 12), NetCodec.TICK_MODULUS)


func _flip(value: bool, chance: float) -> bool:
	return not value if _rng.randf() < chance else value


# --- Faithful to the source ---------------------------------------------------

## How many bodies of [param decoded] are not [param source] within each field's quantum: centimetres,
## a 65536th of a turn, 1e-4 rad, tenths of a second (floored; boost ceiled), counters modulo their bits.
func _unfaithful(source: WorldSnapshot, decoded: WorldSnapshot) -> int:
	if decoded.count != source.count or decoded.tick != source.tick or decoded.scene != source.scene:
		return maxi(source.count, 1)
	var off: int = 0
	var turn: float = TAU / 65536.0
	for i: int in source.count:
		var a: PlayerState = source.states[i]
		var b: PlayerState = decoded.states[i]
		if a.cmd_ack == NetCodec.NO_ACK:
			_defect("sentinel: cmd_ack")
			continue
		var ok: bool = a.seat_index == b.seat_index and a.cmd_ack == b.cmd_ack \
			and _within(a.position, b.position, 0.0051) and _within(a.velocity, b.velocity, 0.0051) \
			and absf(angle_difference(a.yaw, b.yaw)) <= turn and absf(angle_difference(a.view_base, b.view_base)) <= turn \
			and absf(a.pitch - b.pitch) <= 0.51e-4 \
			and a.on_floor == b.on_floor and a.sliding == b.sliding and a.crouching == b.crouching \
			and a.emoting == b.emoting and a.emote_alt == b.emote_alt and a.is_finisher == b.is_finisher \
			and a.is_armed == b.is_armed and a.health == b.health and a.ability == b.ability \
			and a.jump_counter % NetCodec.JUMP_COUNTER_MODULUS == b.jump_counter \
			and a.shove_counter % NetCodec.SHOVE_COUNTER_MODULUS == b.shove_counter \
			and _tenths_floor(a.ability_remaining, b.ability_remaining) and _tenths_floor(a.cooldown_remaining, b.cooldown_remaining) \
			and b.boost_remaining >= a.boost_remaining - 1e-4 and b.boost_remaining < a.boost_remaining + 0.1 + 1e-4 \
			and (absf(b.boost_multiplier - a.boost_multiplier) <= 0.05 + 1e-4 if b.boost_remaining > 0.0 else b.boost_multiplier == 1.0)
		off += int(not ok)
	return off


func _defect(name: String) -> void:
	_defects[name] = _defects.get(name, 0) + 1


func _within(a: Vector3, b: Vector3, quantum: float) -> bool:
	var gap: Vector3 = (a - b).abs()
	return gap.x <= quantum and gap.y <= quantum and gap.z <= quantum


func _tenths_floor(source: float, decoded: float) -> bool:
	return decoded <= source + 1e-4 and decoded > source - 0.1 - 1e-4


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
