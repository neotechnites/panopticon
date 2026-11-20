extends TestCase

## [NetCodec], [WorldSnapshot] and [PlayerState]: the wire format, checked
## against the two things a wire format has to survive.
##
## [b]Round trips[/b] -- what goes in comes out, for every field, so a flag
## packed into the wrong bit is caught here and not as a player who cannot
## sprint.
##
## [b)Hostile input[/b] -- a peer's packet is not a friendly one. Every decoder
## is handed rubbish of the shapes rubbish actually arrives in: too short, too
## long, a body count that does not match the payload, an enum value from a
## build that does not exist, and NaN. The decoder must refuse, and refuse
## without leaving half a packet behind for the game to draw.
##
## No sockets here. This file is pure functions and runs in microseconds; the
## socket tests are in [code]tests/test_net_session.gd[/code].

## Names are capped in bytes, and the cap is exercised with multi-byte
## characters, so a truncation that cuts through a code point shows up.
const NAME_CAP: int = 8
## The host tick the snapshots here are sampled on.
const TICK: int = 900


func _make_intent() -> MoveIntent:
	var intent: MoveIntent = MoveIntent.new()
	intent.move_direction = Vector2(0.6, -0.8)
	intent.view_angles = Vector2(0.125, -0.0625)
	intent.slide_held = true
	intent.buttons |= MoveIntent.SHOVE | (MoveIntent.POWER_1 << 2)
	intent.view_time = 1000.5
	return intent


func _decoded() -> Array[MoveIntent]:
	var out: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_COMMANDS:
		out.append(MoveIntent.new())
	return out


func _make_state(seat: int, offset: float) -> PlayerState:
	var state: PlayerState = PlayerState.new()
	state.seat_index = seat
	state.position = Vector3(offset, offset + 1.0, offset + 2.0)
	state.velocity = Vector3(-offset, 0.5, offset)
	state.yaw = 0.25 * offset
	state.pitch = -0.125 * offset
	state.on_floor = seat % 2 == 0
	state.ability = seat % 5
	state.power_active = seat % 5 != 0
	state.ability_end_tick = TICK + 30 * seat
	state.cooldown_end_tick = TICK + 18 * seat
	state.is_finisher = seat == 1
	state.is_armed = seat == 1
	state.health = 3 + seat
	state.jump_counter = seat
	state.sliding = seat == 2
	state.crouching = seat == 0
	return state


# --- Commands -----------------------------------------------------------------

func test_a_command_survives_the_round_trip() -> void:
	var sent: MoveIntent = _make_intent()
	var packed: PackedByteArray = NetCodec.pack_commands(9, 4242, 1002, [sent], 1)
	assert_eq_int(NetCodec.command_epoch(packed), 9, "the epoch comes back")
	assert_eq_int(NetCodec.command_newest(packed), 4242, "the newest sequence comes back")
	assert_eq_int(NetCodec.command_snap_ack(packed), 1002, "the snap ack comes back")
	var out: Array[MoveIntent] = _decoded()
	assert_eq_int(NetCodec.unpack_commands(packed, out, 1002), 1, "one command")
	var got: MoveIntent = out[0]
	assert_eq_int(got.buttons, sent.buttons, "the levels, every bit")
	assert_eq_int(got.pressed | got.released, 0, "no edge is sent: the receiver derives them")
	assert_almost_eq(got.move_direction.x, 0.6, 1.0 / 127.0, "move x, to a 127th")
	assert_almost_eq(got.move_direction.y, -0.8, 1.0 / 127.0, "move y, to a 127th")
	assert_almost_eq(got.view_angles.x, 0.125, TAU / 65536.0, "yaw, to a 65536th of a turn")
	assert_almost_eq(got.view_angles.y, -0.0625, 0.0001, "pitch, to a ten-thousandth")
	assert_true(got.view_absolute, "the view is absolute")
	assert_almost_eq(got.view_time, 1000.5, 1.0 / 64.0, "the view time, on the receiver's own tick")


func test_commands_are_delta_coded_against_the_one_before() -> void:
	var a: MoveIntent = _make_intent()
	var b: MoveIntent = MoveIntent.new()
	b.copy_from(a)
	var c: MoveIntent = MoveIntent.new()
	c.copy_from(a)
	c.jump_held = true
	var packed: PackedByteArray = NetCodec.pack_commands(1, 12, 1002, [a, b, c], 3)
	var first_alone: int = NetCodec.pack_commands(1, 10, 1002, [a], 1).size()
	assert_eq_int(packed.size(), first_alone + 1 + 3, "a repeat costs its mask byte; a new level 3 bytes")
	var out: Array[MoveIntent] = _decoded()
	assert_eq_int(NetCodec.unpack_commands(packed, out, 1002), 3, "three commands")
	assert_eq_int(out[1].buttons, a.buttons, "the repeat carries the levels it did not resend")
	assert_true(out[2].jump_held, "the third has its new level")
	assert_almost_eq(out[2].view_angles.x, 0.125, TAU / 65536.0, "and the view it did not resend")


func test_a_malformed_command_packet_is_refused_and_writes_nothing() -> void:
	var good: PackedByteArray = NetCodec.pack_commands(1, 5, 100, [_make_intent(), _make_intent()], 2)
	var cases: Dictionary = {
		"empty": PackedByteArray(),
		"a header alone": good.slice(0, NetCodec.COMMAND_HEADER_SIZE),
		"truncated": good.slice(0, good.size() - 1),
		"trailing bytes": good + PackedByteArray([0]),
	}
	var zero: PackedByteArray = good.duplicate()
	zero.encode_u8(6, 0)
	cases["no commands"] = zero
	var many: PackedByteArray = good.duplicate()
	many.encode_u8(6, NetCodec.MAX_COMMANDS + 1)
	cases["more than the cap"] = many
	var bits: PackedByteArray = good.duplicate()
	bits.encode_u8(NetCodec.COMMAND_HEADER_SIZE, 0x10)
	cases["an unknown field bit"] = bits
	for name: String in cases:
		var out: Array[MoveIntent] = _decoded()
		out[0].buttons = 7
		assert_eq_int(NetCodec.unpack_commands(cases[name], out, 100), 0, "%s is refused" % name)
		assert_true(out[0].buttons != _make_intent().buttons, "%s leaves nothing half-written" % name)


func test_a_command_carrying_nan_reaches_the_host_as_numbers() -> void:
	var poisoned: MoveIntent = _make_intent()
	poisoned.move_direction = Vector2(NAN, 0.5)
	poisoned.view_angles = Vector2(INF, NAN)
	poisoned.view_time = NAN
	var out: Array[MoveIntent] = _decoded()
	assert_eq_int(NetCodec.unpack_commands(NetCodec.pack_commands(1, 1, 10, [poisoned], 1), out, 10), 1, "it decodes")
	assert_true(out[0].move_direction.is_finite() and out[0].view_angles.is_finite(), "every float is finite")
	assert_true(out[0].view_time == MoveIntent.LIVE_WORLD, "a view time that was not a number is none")


## [param seats] bodies at [constant TICK], snapped to the wire as the host keeps them.
func _world(seats: int, offset: float = 0.0) -> WorldSnapshot:
	var world: WorldSnapshot = WorldSnapshot.new()
	world.tick = TICK
	world.epoch = 3
	for seat: int in seats:
		world.slot(seat).copy_from(_make_state(seat, float(seat) * 3.0 + offset))
		NetCodec.quantise_state(world.states[seat], TICK)
	return world


func _pack(world: WorldSnapshot, base: WorldSnapshot, owner_seat: int = -1) -> PackedByteArray:
	var info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	info.cmd_ack = 77
	return NetCodec.pack_snapshot(world, base, owner_seat, [] as Array[NetEvents.Entry], info)


func _unpack(payload: PackedByteArray, base: WorldSnapshot, out: WorldSnapshot) -> bool:
	return NetCodec.unpack_snapshot(payload, base, out, NetCodec.SnapshotInfo.new(), [] as Array[NetEvents.Entry])


func test_a_full_snapshot_survives_the_round_trip() -> void:
	var sent: WorldSnapshot = _world(3)
	var packed: PackedByteArray = _pack(sent, null)
	assert_eq_int(NetCodec.snapshot_baseline(packed), -1, "with no baseline it is a full update")
	var got: WorldSnapshot = WorldSnapshot.new()
	var info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	assert_true(NetCodec.unpack_snapshot(packed, null, got, info, [] as Array[NetEvents.Entry]), "it decodes")
	assert_eq_int(got.tick, TICK, "the tick is shared by every body in the packet")
	assert_eq_int(info.cmd_ack, 77, "the acknowledgement is in the header")
	assert_eq_int(got.get_count(), 3, "three bodies came back")
	for seat: int in 3:
		var state: PlayerState = got.find_seat(seat)
		if not assert_not_null(state, "seat %d is in the snapshot" % seat):
			continue
		var expected: PlayerState = _make_state(seat, float(seat) * 3.0)
		assert_true(state.equals(sent.states[seat]), "seat %d is the host's record, bit for bit" % seat)
		assert_vec3_almost_eq(state.position, expected.position, 0.006, "seat %d position, to the centimetre" % seat)
		assert_almost_eq(state.yaw, expected.yaw, 0.0001, "seat %d yaw" % seat)
		assert_almost_eq(state.ability_remaining(), 0.5 * float(seat), 0.001, "seat %d power timer, exact in ticks" % seat)
		assert_almost_eq(state.cooldown_remaining(), 0.3 * float(seat), 0.001, "seat %d cooldown" % seat)
		assert_eq_int(state.jump_counter, expected.jump_counter, "seat %d jump count, an edge counted" % seat)
	assert_null(got.find_seat(3), "a seat with no body stays empty")


func test_a_delta_carries_only_what_changed() -> void:
	var base: WorldSnapshot = _world(8)
	var full: int = _pack(base, null).size()
	var now: WorldSnapshot = WorldSnapshot.new()
	now.copy_from(base)
	now.tick = TICK + 2
	now.states[5].position += Vector3(0.25, 0.0, 0.0)
	var delta: PackedByteArray = _pack(now, base)
	assert_eq_int(NetCodec.snapshot_baseline(delta), TICK, "coded against the acknowledged tick")
	assert_eq_int(delta.size(), NetCodec.SNAPSHOT_HEADER_SIZE + 2 + 2 + 6, "one body's mask and position")
	assert_lt(float(delta.size()), float(full), "smaller than the whole world")
	var got: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(delta, base, got), "it decodes on its baseline")
	for seat: int in 8:
		assert_true(got.states[seat].equals(now.states[seat]), "seat %d is the host's" % seat)
	var quiet: WorldSnapshot = WorldSnapshot.new()
	quiet.copy_from(base)
	quiet.tick = TICK + 4
	assert_eq_int(_pack(quiet, base).size(), NetCodec.SNAPSHOT_HEADER_SIZE, "nothing changed costs a header")


func test_a_body_leaving_and_arriving_is_carried() -> void:
	var base: WorldSnapshot = _world(3)
	var now: WorldSnapshot = _world(2)
	now.tick = TICK + 2
	now.slot(6).copy_from(_make_state(6, 1.0))
	NetCodec.quantise_state(now.states[6], now.tick)
	var got: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(_pack(now, base), base, got), "it decodes")
	assert_null(got.find_seat(2), "the body that left is gone")
	assert_not_null(got.find_seat(6), "the body that arrived is there")
	assert_true(got.states[6].equals(now.states[6]), "whole, coded against nothing")


func test_a_snapshot_on_the_wrong_baseline_is_refused() -> void:
	var base: WorldSnapshot = _world(3)
	var now: WorldSnapshot = _world(3, 1.0)
	now.tick = TICK + 2
	var delta: PackedByteArray = _pack(now, base)
	var other: WorldSnapshot = _world(3)
	other.tick = TICK - 2
	var got: WorldSnapshot = WorldSnapshot.new()
	assert_false(_unpack(delta, other, got), "a baseline of another tick is refused")
	assert_false(_unpack(delta, null, got), "a delta read as a full update is refused")
	assert_false(_unpack(_pack(now, null), base, got), "a full update read on a baseline is refused")


func test_a_malformed_snapshot_is_refused() -> void:
	var base: WorldSnapshot = _world(4)
	var now: WorldSnapshot = _world(4, 2.0)
	now.tick = TICK + 2
	var good: PackedByteArray = _pack(now, base, 1)
	var got: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(good, base, got), "the untouched packet decodes")
	for length: int in good.size():
		assert_false(_unpack(good.slice(0, length), base, got), "cut to %d bytes it is refused" % length)
	assert_false(_unpack(good + PackedByteArray([0]), base, got), "a trailing byte is refused")
	var flags: PackedByteArray = good.duplicate()
	flags[15] = flags[15] | 0x80
	assert_false(_unpack(flags, base, got), "an unknown section bit is refused")
	var seats: PackedByteArray = good.duplicate()
	seats[NetCodec.SNAPSHOT_HEADER_SIZE + 1] = 0x80
	assert_false(_unpack(seats, base, got), "a changed seat that is not present is refused")


func test_the_owner_block_is_exact() -> void:
	var base: WorldSnapshot = _world(2)
	var now: WorldSnapshot = _world(2)
	now.tick = TICK + 2
	for i: int in PredictedState.SIZE:
		now.owners[1].values[i] = 0.1 * float(i) + 1.0 / 3.0
	var got: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(_pack(now, base, 1), base, got), "it decodes")
	assert_not_null(got.find_owner(1), "the receiving client's seat has its predicted state")
	assert_null(got.find_owner(0), "and nobody else's")
	assert_true(got.owners[1].equals(now.owners[1]), "every float is the host's f32, exactly")


func test_an_owner_block_leaves_and_returns_with_its_body() -> void:
	var first: WorldSnapshot = _world(2)
	first.owners[1].values[PredictedState.LOCKED] = 1.0
	first.owner_valid = 0b11
	var got_first: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(_pack(first, null, 1), null, got_first), "the full update decodes")
	# The body leaves the tree: the host's world has no seat 1, and zeroes its owner with it.
	var gone: WorldSnapshot = _world(1)
	gone.tick = TICK + 2
	var got_gone: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(_pack(gone, first, 1), got_first, got_gone), "the leaving delta decodes")
	assert_null(got_gone.find_owner(1), "a seat with no body has no owner block")
	var back: WorldSnapshot = _world(2)
	back.tick = TICK + 4
	back.owners[1].values[PredictedState.POSITION] = 2.5
	back.owner_valid = 0b11
	var got_back: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(_pack(back, gone, 1), got_gone, got_back), "the returning delta decodes")
	assert_true(got_back.owners[1].equals(back.owners[1]), "the returned owner block is the host's, its old lock gone")


func test_events_ride_the_snapshot_until_it_is_full() -> void:
	var world: WorldSnapshot = _world(8)
	var events: Array[NetEvents.Entry] = []
	for i: int in 100:
		var entry: NetEvents.Entry = NetEvents.Entry.new()
		entry.seq = 65530 + i
		entry.tick = TICK - (i % 30)
		entry.type = NetEvents.Type.SHOT
		entry.payload = NetCodec.pack_shot(0, Vector3(1, 2, 3), Vector3(4, 5, 6), 1.5, 80.0, -9.8)
		events.append(entry)
	var info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	var packed: PackedByteArray = NetCodec.pack_snapshot(world, null, 0, events, info)
	assert_lt(float(packed.size()), float(NetCodec.MAX_SNAPSHOT_BYTES), "the packet stays under the cap")
	assert_gt(float(info.event_count), 0.0, "events went")
	assert_lt(float(info.event_count), 100.0, "but not more than fit")
	var got: WorldSnapshot = WorldSnapshot.new()
	var read: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	var out: Array[NetEvents.Entry] = []
	assert_true(NetCodec.unpack_snapshot(packed, null, got, read, out), "it decodes")
	assert_eq_int(read.event_count, info.event_count, "every event sent is read")
	assert_eq_int(out[3].seq, (65533) & 0xFFFF, "the id is its low 16 bits")
	assert_eq_int(out[3].tick, TICK - 3, "and its tick is the header's less its age")
	assert_vec3_almost_eq(NetCodec.event_point(out[3].payload, 13), Vector3(4, 5, 6), 1e-6, "the payload, exact")


func test_an_expired_long_ago_cooldown_reads_as_none_in_a_full_update() -> void:
	# Ten minutes ago, sampled now: the u16 of an old end tick would alias into the future.
	var now: int = TICK + 36000
	var state: PlayerState = PlayerState.new()
	state.cooldown_end_tick = TICK
	state.ability_end_tick = now + 60
	NetCodec.quantise_state(state, now)
	assert_eq_int(state.cooldown_end_tick, 0, "an expired end tick is none in the state itself")
	var world: WorldSnapshot = WorldSnapshot.new()
	world.tick = now
	world.slot(0).copy_from(state)
	var got: WorldSnapshot = WorldSnapshot.new()
	assert_true(_unpack(_pack(world, null), null, got), "it decodes")
	assert_almost_eq(got.states[0].cooldown_remaining(), 0.0, 0.0001, "no cooldown")
	assert_eq_int(got.states[0].ability_end_tick, now + 60, "a live one is resolved to the tick nearest the header")


func test_an_end_tick_is_never_read_as_none() -> void:
	var tick: int = 0x1FFFF - 10
	var end: int = NetCodec.end_tick(tick, 10.0 / 60.0)
	assert_true((end & 0xFFFF) != 0, "an end tick whose low 16 bits are 0 moves a tick: 0 is none")
	assert_eq_int(NetCodec.end_tick(tick, 0.0), 0, "no time left is none")
	assert_eq_int(NetCodec.end_tick(tick, -1.0), 0, "and so is time past")


func test_the_highest_acknowledgement_is_not_none() -> void:
	var world: WorldSnapshot = _world(1)
	var info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	info.cmd_ack = 0xFFFFFFFF
	var read: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
	var packed: PackedByteArray = NetCodec.pack_snapshot(world, null, -1, [] as Array[NetEvents.Entry], info)
	assert_true(NetCodec.unpack_snapshot(packed, null, WorldSnapshot.new(), read, [] as Array[NetEvents.Entry]), "it decodes")
	assert_eq_int(read.cmd_ack, 0xFFFFFFFF, "sequence 0xFFFFFFFF is a sequence")
	info.cmd_ack = -1
	packed = NetCodec.pack_snapshot(world, null, -1, [] as Array[NetEvents.Entry], info)
	NetCodec.unpack_snapshot(packed, null, WorldSnapshot.new(), read, [] as Array[NetEvents.Entry])
	assert_eq_int(read.cmd_ack, -1, "and none is none")
	var command: PackedByteArray = NetCodec.pack_commands(1, 5, 0xFFFFFFFF, [_make_intent()], 1)
	assert_eq_int(NetCodec.command_snap_ack(command), 0xFFFFFFFF, "a snap ack of tick 0xFFFFFFFF too")
	assert_eq_int(NetCodec.command_snap_ack(NetCodec.pack_commands(1, 5, -1, [_make_intent()], 1)), -1, "none")


# --- Roster -------------------------------------------------------------------

func test_a_roster_survives_the_round_trip() -> void:
	var seats: Array[LobbySeat] = []
	for index: int in 3:
		var seat: LobbySeat = LobbySeat.new()
		seat.index = index
		seats.append(seat)
	seats[0].occupancy = LobbySeat.Occupancy.HUMAN
	seats[0].peer_id = 1
	seats[0].display_name = "Ryan"
	seats[0].role = LobbySeat.Role.GUARD
	seats[0].is_ready = true
	seats[0].standing_epoch = 7
	seats[1].occupancy = LobbySeat.Occupancy.BOT
	seats[1].display_name = "Bot 2"
	seats[1].role = LobbySeat.Role.PRISONER
	seats[1].is_ready = true

	var packed: PackedByteArray = NetCodec.pack_roster(
		int(NetLobby.Phase.GATHERING), seats, NetSettings.new().max_name_bytes
	)
	var got: Array[LobbySeat] = []
	assert_eq_int(
		NetCodec.unpack_roster(packed, got, NetSettings.new().max_name_bytes),
		int(NetLobby.Phase.GATHERING),
		"the phase comes back",
	)
	assert_eq_int(got.size(), 3, "three seats came back")
	assert_eq_string(got[0].display_name, "Ryan", "the human's name")
	assert_eq_int(got[0].peer_id, 1, "the human's peer id")
	assert_true(got[0].role == LobbySeat.Role.GUARD, "the human is the guard")
	assert_true(got[0].is_ready, "the human is ready")
	assert_eq_int(got[0].standing_epoch, 7, "the epoch its machine stands in")
	assert_true(got[1].occupancy == LobbySeat.Occupancy.BOT, "the bot is a bot")
	assert_eq_int(got[1].peer_id, 0, "a bot has no peer, and that is the point")
	assert_false(got[2].is_occupied(), "the empty seat is still empty")


func test_a_roster_with_an_impossible_enum_is_refused() -> void:
	# A peer from a build with a fourth occupancy kind, or a peer making things
	# up. Either way this build has nothing to map it to.
	var seats: Array[LobbySeat] = []
	var seat: LobbySeat = LobbySeat.new()
	seat.occupancy = LobbySeat.Occupancy.HUMAN
	seats.append(seat)
	var packed: PackedByteArray = NetCodec.pack_roster(int(NetLobby.Phase.GATHERING), seats, 24)
	# Byte 2 is the first seat's index; byte 3 is its occupancy.
	packed.encode_u8(3, 99)

	var got: Array[LobbySeat] = []
	assert_eq_int(NetCodec.unpack_roster(packed, got, 24), -1, "an unknown occupancy is refused")
	assert_eq_int(got.size(), 0, "and nothing was written")


# --- Match rules ---------------------------------------------------------------

## [member MatchRules.reload_seconds_by_turn] is a [PackedFloat32Array], not a
## scalar export, so it needs its own check that [method NetCodec.pack_rules]
## and [method NetCodec.copy_rules] both carry it rather than silently dropping it.
func test_the_reload_grid_survives_pack_and_copy() -> void:
	var sent: MatchRules = MatchRules.new()
	sent.reload_seconds_by_turn = PackedFloat32Array([2.5, 2.2, 1.9, 1.6, 1.3])

	var got: MatchRules = MatchRules.new()
	assert_true(NetCodec.unpack_rules(NetCodec.pack_rules(sent), got), "the payload decodes")
	assert_eq_int(got.reload_seconds_by_turn.size(), 5, "all five entries came back")
	for i: int in 5:
		assert_almost_eq(
			got.reload_seconds_by_turn[i], sent.reload_seconds_by_turn[i], 1e-6,
			"entry %d survives pack_rules/unpack_rules" % i,
		)

	var copied: MatchRules = MatchRules.new()
	NetCodec.copy_rules(sent, copied)
	assert_eq_int(copied.reload_seconds_by_turn.size(), 5, "all five entries were copied")
	for i: int in 5:
		assert_almost_eq(
			copied.reload_seconds_by_turn[i], sent.reload_seconds_by_turn[i], 1e-6,
			"entry %d survives copy_rules" % i,
		)


func test_a_name_is_stripped_and_capped_without_splitting_a_character() -> void:
	assert_eq_string(
		NetCodec.sanitise_name("  Ryan\n\t ", NAME_CAP), "Ryan", "control characters and edges go"
	)
	assert_eq_string(
		NetCodec.sanitise_name("abcdefghijkl", NAME_CAP), "abcdefgh", "a long name is cut to the cap"
	)
	# Four characters, three bytes each: the cap of eight has to land on a
	# character boundary rather than mid-code-point.
	var wide: String = "字字字字"
	var capped: String = NetCodec.sanitise_name(wide, NAME_CAP)
	assert_le(float(capped.to_utf8_buffer().size()), float(NAME_CAP), "the cap is in bytes")
	assert_eq_int(capped.length(), 2, "two whole characters fit in eight bytes")
	assert_eq_string(capped, "字字", "and neither of them is a broken code point")


# --- Tick arithmetic ----------------------------------------------------------

func test_tick_comparison_survives_the_wrap() -> void:
	assert_true(NetCodec.is_newer_tick(5, 4), "5 is newer than 4")
	assert_false(NetCodec.is_newer_tick(4, 5), "4 is not newer than 5")
	assert_false(NetCodec.is_newer_tick(5, 5), "a tick is not newer than itself")
	# The single wrap in a two-year session must not read as every later packet
	# being four billion ticks old.
	assert_true(NetCodec.is_newer_tick(1, NetCodec.TICK_MODULUS - 1), "1 is newer than the last tick")
	assert_false(NetCodec.is_newer_tick(NetCodec.TICK_MODULUS - 1, 1), "and not the other way round")


func test_the_gap_between_two_ticks_survives_the_wrap() -> void:
	assert_eq_int(NetCodec.tick_delta(10, 12), 2, "two ticks apart")
	assert_eq_int(NetCodec.tick_delta(12, 10), -2, "and negative the other way")
	assert_eq_int(
		NetCodec.tick_delta(NetCodec.TICK_MODULUS - 1, 1), 2, "across the wrap it is still two"
	)


# --- Interpolation ------------------------------------------------------------

func test_a_state_blends_towards_the_newer_one() -> void:
	var from: PlayerState = _make_state(2, 0.0)
	from.position = Vector3(0.0, 0.0, 0.0)
	from.yaw = 0.0
	var to: PlayerState = _make_state(2, 0.0)
	to.position = Vector3(10.0, 0.0, 0.0)
	to.yaw = 1.0

	var blend: PlayerState = PlayerState.new()
	blend.interpolate_from(from, to, 0.25)
	assert_vec3_almost_eq(blend.position, Vector3(2.5, 0.0, 0.0), 0.001, "a quarter of the way")
	assert_almost_eq(blend.yaw, 0.25, 0.001, "yaw follows")
	assert_eq_int(blend.seat_index, 2, "the seat is carried, not blended")
	assert_true(blend.sliding == to.sliding, "a pose comes from the newer end, never half of one")
	assert_eq_int(blend.health, to.health, "so do the hit points")

	blend.interpolate_from(from, to, 2.0)
	assert_vec3_almost_eq(blend.position, to.position, 0.001, "weight is clamped, never extrapolated")


func test_a_blended_yaw_takes_the_short_way_round() -> void:
	# A body crossing north with a plain lerp between 3.1 and -3.1 radians
	# spins the long way and reads as a pirouette every lap.
	var from: PlayerState = PlayerState.new()
	from.yaw = 3.1
	var to: PlayerState = PlayerState.new()
	to.yaw = -3.1

	var blend: PlayerState = PlayerState.new()
	blend.interpolate_from(from, to, 0.5)
	assert_true(
		absf(blend.yaw) > 3.0,
		"halfway between 3.1 and -3.1 is past PI, not zero -- got %.4f" % blend.yaw,
	)
