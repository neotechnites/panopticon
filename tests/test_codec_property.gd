extends TestCase

## The codec property harness (DESIGN.md Phase T, over Phase 3's format): 10,000 ticks across the tick
## wrap of random world, owner, match, prop and event changes, coded against the world each client
## acknowledged, through a wire that loses, bursts, duplicates and reorders, with epochs changing. Whatever
## a client decodes equals, bit for bit, the host's world at that tick; every packet stays under 1200 B.

const TICKS: int = 10000
const SNAPSHOT_EVERY: int = 2
const TICK_MS: float = 1000.0 / 60.0
const MTU_BUDGET: int = 1200
const SEED: int = 794
## The run starts this close to the tick wrap so it crosses it: the order rule must survive the wrap.
const FIRST_TICK: int = NetCodec.TICK_MODULUS - 5000
## The receiving client's seat: its owner block is the one compared.
const OWN_SEAT: int = 3

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = SEED


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


func test_every_decoded_snapshot_is_the_host_world_of_its_tick() -> void:
	var counts: Dictionary[String, int] = _snapshots(_wire(1), _wire(4), false, 0.0, 0)
	assert_eq_int(counts["malformed"], 0, "every packet the host built decodes on the baseline it names")
	assert_eq_int(counts["missing_baseline"], 0, "a client always holds the baseline the host chose: it acked it")
	assert_eq_int(counts["mismatch"], 0, "every decoded world is bit for bit the host's at its tick, owner block included")
	assert_eq_int(counts["backwards"], 0, "a decoded snapshot is never older than one decoded before it")
	assert_eq_int(counts["oversize"], 0, "no snapshot reaches %d bytes" % MTU_BUDGET)
	assert_eq_int(counts["event_twice"], 0, "no event is presented twice")
	assert_eq_int(counts["event_order"], 0, "events are presented in the order they were made")
	assert_eq_int(counts["event_wrong"], 0, "an event's payload is the one made under its id")
	assert_eq_int(counts["event_lost_young"], 0, "an event is lost only once it is older than its TTL")
	assert_gt(float(counts["events_in"]), float(counts["events_out"]) * 0.9, "most events arrive")
	assert_gt(float(counts["stale"]), 0.0, "the wire did reorder and duplicate: stale packets were refused")
	assert_gt(float(counts["old_epoch"]), 0.0, "and packets from a gone epoch arrived and were refused")
	assert_gt(float(counts["full"]), float(counts["epochs"]), "every epoch began with a full update, and outages forced more")
	assert_gt(float(counts["delta"]), float(counts["full"]) * 10.0, "while most snapshots were deltas")
	assert_gt(float(counts["accepted"]), float(counts["sent"]) * 0.5, "and most snapshots still got through")
	assert_gt(float(counts["epochs"]), 8.0, "across many epoch changes")


func test_losing_one_snapshot_in_three_never_desynchronises() -> void:
	var clean: NetConditions = NetConditions.new(5)
	clean.delay_ms = 50.0
	var back: NetConditions = NetConditions.new(6)
	back.delay_ms = 50.0
	var counts: Dictionary[String, int] = _snapshots(clean, back, false, 0.0, 3)
	assert_eq_int(counts["dropped"], counts["sent"] / 3, "every third snapshot was dropped")
	assert_eq_int(counts["malformed"] + counts["missing_baseline"], 0, "and every other one decoded on its baseline")
	assert_eq_int(counts["mismatch"], 0, "into the host's world, bit for bit")
	assert_eq_int(counts["accepted"], counts["arrived"] - counts["old_epoch"], "every one that arrived in its epoch was taken")
	assert_ge(float(counts["arrived"]), float(counts["sent"] - counts["dropped"] - 2), "and every one not dropped arrived")


func test_the_harness_sees_a_receiver_that_takes_stale_packets_and_a_wire_that_corrupts() -> void:
	assert_gt(float(_snapshots(_wire(1), _wire(4), true, 0.0, 0)["backwards"]), 0.0, "taking every packet goes back in time")
	var corrupted: Dictionary[String, int] = _snapshots(_wire(1), _wire(4), false, 0.02, 0)
	assert_gt(float(corrupted["mismatch"] + corrupted["malformed"]), 0.0, "a flipped bit is refused or is a world that is not the host's")


## Host and client for [constant TICKS], snapshots down [param down], acks up [param up]; [param take_stale]
## drops the order rule, [param corrupt] flips a bit in that share, [param drop_every] drops every nth.
func _snapshots(
	down: NetConditions, up: NetConditions, take_stale: bool, corrupt: float, drop_every: int
) -> Dictionary[String, int]:
	_rng.seed = SEED
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = SEED + 1
	var world: WorldSnapshot = WorldSnapshot.new()
	_populate(world, 8)
	var host_ring: Array[WorldSnapshot] = []
	var client_ring: Array[WorldSnapshot] = []
	var recorded: Dictionary[int, WorldSnapshot] = {}
	var events: NetEvents = NetEvents.new()
	var made: Dictionary[int, PackedByteArray] = {}
	var made_tick: Dictionary[int, int] = {}
	var recipient: NetReplicator.Recipient = NetReplicator.Recipient.new(events.newest())
	var carry: Array[NetEvents.Entry] = []
	var info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	var read: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	var read_events: Array[NetEvents.Entry] = []
	var host_epoch: int = 1
	var client_epoch: int = 1
	var epoch_due: int = -1
	var next_bump: int = _rng.randi_range(300, 1200)
	var newest: int = -1
	var event_seen: int = -1
	var event_full: int = -1
	var counts: Dictionary[String, int] = {"sent": 0, "arrived": 0, "accepted": 0, "stale": 0, "old_epoch": 0,
		"mismatch": 0, "malformed": 0, "missing_baseline": 0, "oversize": 0, "epochs": 1, "backwards": 0,
		"full": 0, "delta": 0, "dropped": 0, "events_out": 0, "events_in": 0, "event_twice": 0,
		"event_order": 0, "event_wrong": 0, "event_lost_young": 0}
	var largest: int = 0
	for step: int in TICKS:
		var tick: int = (FIRST_TICK + step) % NetCodec.TICK_MODULUS
		var now: float = float(step) * TICK_MS
		if step == next_bump:
			# A launch, rematch or return to the hub: the host's epoch moves now and both rings flush
			# with it, the client's when the reliable roster carrying it lands.
			host_epoch = host_epoch % (NetCodec.EPOCH_MODULUS - 1) + 1
			host_ring.clear()
			recipient = NetReplicator.Recipient.new(events.newest())
			epoch_due = step + _rng.randi_range(2, 20)
			next_bump = step + _rng.randi_range(300, 1200)
			counts["epochs"] += 1
			_populate(world, _rng.randi_range(1, 8))
		if step == epoch_due:
			client_epoch = host_epoch
			client_ring.clear()
			newest = -1
			event_seen = -1
			event_full = -1
		_change(world, tick)
		if _rng.randf() < 0.15:
			var payload: PackedByteArray = NetCodec.pack_point(_rng.randi_range(0, 255), _random_point())
			var seq: int = events.push(NetEvents.Type.MISS, payload, (tick + 1) % NetCodec.TICK_MODULUS)
			made[seq] = payload
			made_tick[seq] = (tick + 1) % NetCodec.TICK_MODULUS
			counts["events_out"] += 1
		if tick % SNAPSHOT_EVERY == 0:
			world.tick = tick
			world.epoch = host_epoch
			var kept: WorldSnapshot = WorldSnapshot.new()
			kept.copy_from(world)
			host_ring.append(kept)
			if host_ring.size() > NetReplicator.RING:
				host_ring.pop_front()
			recorded[tick] = kept
			var base: WorldSnapshot = _find(host_ring, recipient.acked)
			var passed: int = events.collect(1, recipient.event_acked, tick, MTU_BUDGET, carry, recipient.event_counted)
			info.cmd_ack = -1 if _rng.randf() < 0.01 else (0xFFFFFFFF if _rng.randf() < 0.01 else posmod(tick - 7, NetCodec.TICK_MODULUS))
			var bytes: PackedByteArray = NetCodec.pack_snapshot(kept, base, OWN_SEAT, carry, info)
			if info.event_count < carry.size():
				passed = carry[info.event_count].seq - 1
			recipient.note_sent(tick, passed)
			largest = maxi(largest, bytes.size())
			counts["oversize"] += int(bytes.size() >= MTU_BUDGET)
			counts["full" if base == null else "delta"] += 1
			counts["sent"] += 1
			if drop_every > 0 and counts["sent"] % drop_every == 0:
				counts["dropped"] += 1
			else:
				down.push(1, false, bytes, now)
		for bytes: PackedByteArray in down.pop_due(now):
			counts["arrived"] += 1
			if corrupt > 0.0 and noise.randf() < corrupt:
				bytes = bytes.duplicate()
				var at: int = noise.randi_range(0, bytes.size() - 1)
				bytes[at] = bytes[at] ^ (1 << noise.randi_range(0, 7))
			if NetCodec.snapshot_epoch(bytes) != client_epoch:
				counts["old_epoch"] += 1
				continue
			var at_tick: int = NetCodec.snapshot_tick(bytes)
			if newest >= 0 and not NetCodec.is_newer_tick(at_tick, newest) and not take_stale:
				counts["stale"] += 1
				continue
			var baseline: int = NetCodec.snapshot_baseline(bytes)
			var base: WorldSnapshot = _find(client_ring, baseline)
			if baseline >= 0 and base == null:
				counts["missing_baseline"] += 1
				continue
			var decoded: WorldSnapshot = WorldSnapshot.new()
			if not NetCodec.unpack_snapshot(bytes, base, decoded, read, read_events):
				counts["malformed"] += 1
				continue
			counts["backwards"] += int(newest >= 0 and NetCodec.tick_delta(newest, at_tick) <= 0)
			newest = at_tick
			counts["accepted"] += 1
			client_ring.append(decoded)
			if client_ring.size() > NetReplicator.RING:
				client_ring.pop_front()
			counts["mismatch"] += int(not _same(decoded, recorded.get(at_tick, null)))
			for i: int in read.event_count:
				var entry: NetEvents.Entry = read_events[i]
				if event_seen >= 0 and not NetReplicator._newer_u16(entry.seq, event_seen):
					continue
				var seq: int = _full_seq(entry.seq, events.newest())
				if event_full >= 0:
					for skipped: int in range(event_full + 1, seq):
						counts["event_lost_young"] += int(NetCodec.tick_delta(made_tick.get(skipped, tick), tick) <= NetEvents.TTL_TICKS)
				counts["event_twice"] += int(event_full >= 0 and seq <= event_full)
				counts["event_order"] += int(event_full >= 0 and seq < event_full)
				counts["event_wrong"] += int(made.get(seq, PackedByteArray()) != entry.payload)
				event_seen = entry.seq
				event_full = seq
				counts["events_in"] += 1
			up.push(1, false, _ack(at_tick), now)
		for packet: PackedByteArray in up.pop_due(now):
			recipient.take_ack(packet.decode_u32(0))
	print("          SNAPSHOTS over %d ticks%s: %s; largest %d B" % [TICKS,
		" (taking stale)" if take_stale else (" (corrupting %.0f%%)" % (corrupt * 100.0) if corrupt > 0.0 else ""),
		str(counts), largest])
	return counts


## The host sequence whose low 16 bits are [param wire], nearest [param near].
static func _full_seq(wire: int, near: int) -> int:
	var back: int = ((near & 0xFFFF) - wire + 0x10000) % 0x10000
	return near - back


static func _ack(tick: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, tick)
	return bytes


static func _find(ring: Array[WorldSnapshot], tick: int) -> WorldSnapshot:
	if tick < 0:
		return null
	for world: WorldSnapshot in ring:
		if world.tick == tick:
			return world
	return null


## Whether [param decoded] is [param sent] as the client is told it: every body, the client's own owner
## block, the match record and every prop, bit for bit.
static func _same(decoded: WorldSnapshot, sent: WorldSnapshot) -> bool:
	if sent == null or decoded.tick != sent.tick or decoded.present != sent.present:
		return false
	for seat: int in NetTransport.MAX_PLAYERS:
		if sent.has_seat(seat) and not decoded.states[seat].equals(sent.states[seat]):
			return false
	if sent.has_seat(OWN_SEAT) and not decoded.owners[OWN_SEAT].equals(sent.owners[OWN_SEAT]):
		return false
	return decoded.match_record == sent.match_record and decoded.prop_ids == sent.prop_ids \
		and decoded.prop_records == sent.prop_records


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
				NetCodec.quantise_turn(ran.view_angles.x), NetCodec.quantise_pitch(ran.view_angles.y),
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


# --- Random state -------------------------------------------------------------

## [param count] bodies on random seats, [constant OWN_SEAT] among them, a match record and two props.
func _populate(world: WorldSnapshot, count: int) -> void:
	world.clear()
	var seats: Array[int] = []
	for seat: int in NetTransport.MAX_PLAYERS:
		if seat != OWN_SEAT:
			seats.append(seat)
	var chosen: Array[int] = [OWN_SEAT]
	for i: int in count - 1:
		chosen.append(seats.pop_at(_rng.randi_range(0, seats.size() - 1)))
	for seat: int in chosen:
		var body: PlayerState = world.slot(seat)
		body.position = Vector3(_rng.randf_range(-300.0, 300.0), _rng.randf_range(-50.0, 100.0), _rng.randf_range(-300.0, 300.0))
		body.health = _rng.randi_range(0, 255)
	world.owner_valid = world.present
	world.match_record = PackedByteArray([1, 2, 0, 255, 0, 255, 0])
	world.set_prop(0x1234, PackedByteArray([1]))
	world.set_prop(0x0042, PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8]))


## Every field the snapshot carries takes a random step at [param tick], some each tick and some
## rarely, snapped to the wire as the host keeps it.
func _change(world: WorldSnapshot, tick: int) -> void:
	for seat: int in NetTransport.MAX_PLAYERS:
		if not world.has_seat(seat):
			continue
		var body: PlayerState = world.states[seat]
		var step: Vector3 = Vector3(_rng.randfn(0.0, 0.2), _rng.randfn(0.0, 0.1), _rng.randfn(0.0, 0.2))
		body.position = (body.position + step).clamp(Vector3.ONE * -320.0, Vector3.ONE * 320.0)
		if _rng.randf() < 0.3:
			body.velocity = Vector3(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-40.0, 20.0), _rng.randf_range(-14.0, 14.0))
		body.yaw = wrapf(body.yaw + _rng.randfn(0.0, 0.3), -PI, PI)
		body.pitch = clampf(body.pitch + _rng.randfn(0.0, 0.1), -1.55, 1.55)
		if _rng.randf() < 0.02:
			body.view_base = _rng.randf_range(-PI, PI)
			body.placed_counter += 1
		body.on_floor = _flip(body.on_floor, 0.1)
		body.sliding = _flip(body.sliding, 0.05)
		body.crouching = _flip(body.crouching, 0.05)
		body.emoting = _flip(body.emoting, 0.01)
		body.emote_alt = _flip(body.emote_alt, 0.01)
		body.is_finisher = _flip(body.is_finisher, 0.002)
		body.is_armed = _flip(body.is_armed, 0.002)
		if _rng.randf() < 0.05:
			body.jump_counter += 1
		if _rng.randf() < 0.03:
			body.shove_counter += 1
		if _rng.randf() < 0.01:
			body.ability = _rng.randi_range(0, 5)
			body.ability_end_tick = NetCodec.end_tick(tick, _rng.randf_range(0.0, 25.0))
			body.cooldown_end_tick = NetCodec.end_tick(tick, _rng.randf_range(0.0, 600.0))
			body.power_active = _rng.randf() < 0.5
			body.power_out = _rng.randf() < 0.5
			body.power_cooking = _rng.randf() < 0.5
			body.power_serial = _rng.randi_range(0, PowerState.SERIAL_MODULUS - 1)
		if body.power_active and _rng.randf() < 0.5:
			body.anchor_position = Vector3(_rng.randf_range(-300.0, 300.0), 1.0, _rng.randf_range(-300.0, 300.0))
			body.anchor_yaw = _rng.randf_range(-PI, PI)
		if _rng.randf() < 0.01:
			body.health = _rng.randi_range(0, 255)
		if _rng.randf() < 0.01:
			body.boost_end_tick = NetCodec.end_tick(tick, _rng.randf_range(0.0, 25.0))
			body.boost_multiplier = _rng.randf_range(0.5, 3.0)
		if _rng.randf() < 0.02:
			body.weapon_state = _rng.randi_range(0, 2)
			body.weapon_scoped = _rng.randf() < 0.5
			body.weapon_end_tick = NetCodec.end_tick(tick, _rng.randf_range(0.0, 3.0))
			body.weapon_charge = _rng.randi_range(0, 255)
		NetCodec.quantise_state(body, tick)
		var owner: PackedFloat32Array = world.owners[seat].values
		for i: int in 6:
			owner[i] = _rng.randf_range(-300.0, 300.0)
		if _rng.randf() < 0.05:
			owner[_rng.randi_range(6, PredictedState.SIZE - 1)] = _rng.randfn(0.0, 10.0)
	if _rng.randf() < 0.005:
		world.match_record = PackedByteArray([_rng.randi_range(0, 5), _rng.randi_range(0, 9), 1, 255, 0, 255, 0])
	if _rng.randf() < 0.01:
		world.set_prop(0x1234, PackedByteArray([_rng.randi_range(0, 1)]))


func _random_point() -> Vector3:
	return Vector3(_rng.randf_range(-300.0, 300.0), _rng.randf_range(-50.0, 50.0), _rng.randf_range(-300.0, 300.0))


func _flip(value: bool, chance: float) -> bool:
	return not value if _rng.randf() < chance else value
