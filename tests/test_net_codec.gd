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
	intent.look_delta = Vector2(0.125, -0.0625)
	intent.jump_pressed = true
	intent.jump_held = false
	intent.slide_pressed = false
	intent.slide_held = true
	return intent


func _make_state(seat: int, offset: float) -> PlayerState:
	var state: PlayerState = PlayerState.new()
	state.seat_index = seat
	state.position = Vector3(offset, offset + 1.0, offset + 2.0)
	state.velocity = Vector3(-offset, 0.5, offset)
	state.yaw = 0.25 * offset
	state.pitch = -0.125 * offset
	state.on_floor = seat % 2 == 0
	return state


# --- Intent -------------------------------------------------------------------

func test_an_intent_survives_the_round_trip() -> void:
	var sent: MoveIntent = _make_intent()
	var packed: PackedByteArray = NetCodec.pack_intent(4242, sent)
	assert_eq_int(packed.size(), NetCodec.INTENT_SIZE, "an intent is a fixed size")

	var got: MoveIntent = MoveIntent.new()
	assert_eq_int(NetCodec.unpack_intent(packed, got), 4242, "the tick comes back")
	assert_vec2_eq(got.move_direction, sent.move_direction, "move direction")
	assert_vec2_eq(got.look_delta, sent.look_delta, "look delta")
	assert_true(got.jump_pressed, "jump_pressed")
	assert_false(got.jump_held, "jump_held")
	assert_false(got.slide_pressed, "slide_pressed")
	assert_true(got.slide_held, "slide_held")


func test_a_malformed_intent_is_refused_without_touching_the_output() -> void:
	var untouched: MoveIntent = MoveIntent.new()
	untouched.move_direction = Vector2(1.0, 0.0)

	assert_eq_int(
		NetCodec.unpack_intent(PackedByteArray(), untouched), -1, "an empty payload is refused"
	)
	var short_payload: PackedByteArray = NetCodec.pack_intent(1, _make_intent())
	short_payload.resize(NetCodec.INTENT_SIZE - 1)
	assert_eq_int(NetCodec.unpack_intent(short_payload, untouched), -1, "a short payload is refused")

	var long_payload: PackedByteArray = NetCodec.pack_intent(1, _make_intent())
	long_payload.append(0)
	assert_eq_int(NetCodec.unpack_intent(long_payload, untouched), -1, "a long payload is refused")

	assert_vec2_eq(untouched.move_direction, Vector2(1.0, 0.0), "the output was never written")


func test_an_intent_carrying_nan_is_refused() -> void:
	# NaN survives a float round trip and poisons a body on contact, so it has
	# to die at the decoder rather than be clamped to something invented.
	var poisoned: MoveIntent = MoveIntent.new()
	poisoned.move_direction = Vector2(NAN, 0.0)
	var packed: PackedByteArray = NetCodec.pack_intent(7, poisoned)
	assert_eq_int(packed.size(), NetCodec.INTENT_SIZE, "a NaN intent still packs to full size")

	var got: MoveIntent = MoveIntent.new()
	assert_eq_int(NetCodec.unpack_intent(packed, got), -1, "NaN is refused")
	assert_vec2_eq(got.move_direction, Vector2.ZERO, "nothing reached the output")


# --- Snapshot -----------------------------------------------------------------

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
		assert_vec3_almost_eq(state.position, expected.position, 0.001, "seat %d position" % seat)
		assert_vec3_almost_eq(state.velocity, expected.velocity, 0.001, "seat %d velocity" % seat)
		assert_almost_eq(state.yaw, expected.yaw, 0.001, "seat %d yaw" % seat)
		assert_almost_eq(state.pitch, expected.pitch, 0.001, "seat %d pitch" % seat)
		assert_true(state.on_floor == expected.on_floor, "seat %d on_floor" % seat)
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
	forged.encode_u8(4, NetTransport.MAX_PLAYERS + 1)

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
