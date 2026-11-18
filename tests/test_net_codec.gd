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
	state.ability_remaining = 0.5 * float(seat)
	state.cooldown_remaining = 0.3 * float(seat)
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


func test_a_snapshot_survives_the_round_trip() -> void:
	var sent: WorldSnapshot = WorldSnapshot.new()
	sent.tick = 900
	for seat: int in 3:
		assert_true(sent.append(_make_state(seat, float(seat) * 3.0)), "seat %d fits" % seat)

	var packed: PackedByteArray = NetCodec.pack_snapshot(sent)
	assert_eq_int(
		packed.size(),
		NetCodec.SNAPSHOT_HEADER_SIZE + 3 * NetCodec.SNAPSHOT_BODY_SIZE,
		"three bodies is a header and three records",
	)

	var got: WorldSnapshot = WorldSnapshot.new()
	assert_true(NetCodec.unpack_snapshot(packed, got), "a well-formed snapshot decodes")
	assert_eq_int(got.tick, 900, "the tick is shared by every body in the packet")
	assert_eq_int(got.count, 3, "three bodies came back")
	for seat: int in 3:
		var state: PlayerState = got.find_seat(seat)
		assert_not_null(state, "seat %d is in the snapshot" % seat)
		if state == null:
			continue
		var expected: PlayerState = _make_state(seat, float(seat) * 3.0)
		# Half a centimetre: position and velocity are quantised to the
		# centimetre on the wire, and that is the whole of the error.
		assert_vec3_almost_eq(state.position, expected.position, 0.006, "seat %d position" % seat)
		assert_vec3_almost_eq(state.velocity, expected.velocity, 0.006, "seat %d velocity" % seat)
		assert_almost_eq(state.yaw, expected.yaw, 0.001, "seat %d yaw" % seat)
		assert_almost_eq(state.pitch, expected.pitch, 0.001, "seat %d pitch" % seat)
		assert_true(state.on_floor == expected.on_floor, "seat %d on_floor" % seat)
		assert_eq_int(state.ability, expected.ability, "seat %d ability" % seat)
		assert_almost_eq(
			state.ability_remaining,
			expected.ability_remaining,
			0.05,
			"seat %d ability_remaining, quantised to a tenth" % seat,
		)
		assert_almost_eq(
			state.cooldown_remaining,
			expected.cooldown_remaining,
			0.05,
			"seat %d cooldown_remaining, quantised to a tenth" % seat,
		)
		assert_true(state.is_finisher == expected.is_finisher, "seat %d is_finisher" % seat)
		assert_true(state.is_armed == expected.is_armed, "seat %d is_armed" % seat)
		assert_eq_int(state.health, expected.health, "seat %d health" % seat)
		assert_eq_int(
			state.jump_counter, expected.jump_counter, "seat %d jump count, an edge counted" % seat
		)
		assert_true(state.sliding == expected.sliding, "seat %d sliding" % seat)
		assert_true(state.crouching == expected.crouching, "seat %d crouching" % seat)
		assert_eq_int(state.tick, 900, "seat %d carries the snapshot's tick" % seat)


func test_a_truncated_snapshot_leaves_nothing_behind() -> void:
	# The failure this guards is a client drawing three of five bodies and
	# leaving the other two parked, which reads as two players who stopped
	# moving rather than as a dropped packet.
	var sent: WorldSnapshot = WorldSnapshot.new()
	sent.tick = 5
	for seat: int in 4:
		sent.append(_make_state(seat, float(seat)))

	var truncated: PackedByteArray = NetCodec.pack_snapshot(sent)
	truncated.resize(truncated.size() - NetCodec.SNAPSHOT_BODY_SIZE)

	var got: WorldSnapshot = WorldSnapshot.new()
	assert_false(NetCodec.unpack_snapshot(truncated, got), "a count that outruns the payload is refused")
	assert_eq_int(got.count, 0, "the output holds no half-decoded bodies")


func test_a_snapshot_claiming_more_bodies_than_a_session_holds_is_refused() -> void:
	var forged: PackedByteArray = PackedByteArray()
	forged.resize(NetCodec.SNAPSHOT_HEADER_SIZE)
	forged.encode_u32(0, 1)
	# Count sits after the u32 tick and the u32 scene epoch.
	forged.encode_u8(8, NetTransport.MAX_PLAYERS + 1)

	var got: WorldSnapshot = WorldSnapshot.new()
	assert_false(NetCodec.unpack_snapshot(forged, got), "more bodies than seats is refused")
	assert_eq_int(got.count, 0, "and nothing was written")


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
