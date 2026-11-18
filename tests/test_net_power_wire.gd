extends NetPowerRig

## The wire under the powers: button levels on the wire, the host's [CommandStream] turning them
## into edges, and the transport three machines share. A press is never sent; it is the level going
## down on one command, and every command is resent until the host has run it.

## Only the transport tests need machines; the rest are plain unit tests.
var _machines_up: bool = false


func before_each() -> void:
	pass


func after_each() -> void:
	if _machines_up:
		super()


## Counts what the engine logs as an error while it is registered.
class ErrorLog extends Logger:
	var lines: PackedStringArray = PackedStringArray()
	var _lock: Mutex = Mutex.new()

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		lines.append("%s %s (%s:%d in %s)" % [code, rationale, file, line, function])
		_lock.unlock()

	func count() -> int:
		_lock.lock()
		var total: int = lines.size()
		_lock.unlock()
		return total


# --- Codec --------------------------------------------------------------------

func test_every_button_level_survives_the_command_round_trip() -> void:
	var sent: Array[MoveIntent] = []
	for bit: int in 14:
		var command: MoveIntent = MoveIntent.new()
		command.buttons = 1 << bit
		sent.append(command)
	var out: Array[MoveIntent] = _decoded()
	assert_eq_int(NetCodec.unpack_commands(NetCodec.pack_commands(7, 900, -1, sent, 14), out, -1), 14, "fourteen commands")
	for bit: int in 14:
		assert_eq_int(out[bit].buttons, 1 << bit, "button %d alone, not mixed with its neighbours" % bit)


func test_shove_counter_and_boost_survive_the_snapshot_round_trip() -> void:
	var left: Array[float] = [0.0, 0.04, 3.26, 7.0, 30.0, 0.1]
	var scale: Array[float] = [1.0, 3.0, 3.0, 1.5, 2.0, 3.0]
	var sent: WorldSnapshot = WorldSnapshot.new()
	sent.tick = 900
	for seat: int in left.size():
		var state: PlayerState = sent.slot(seat)
		# Swings 0..5: the wire keeps them modulo 4.
		state.shove_counter = seat
		state.boost_end_tick = NetCodec.end_tick(900, left[seat])
		state.boost_multiplier = scale[seat]
		state.emoting = seat % 2 == 0
		state.emote_alt = seat % 3 == 0
		NetCodec.quantise_state(state, 900)
	var none: Array[NetEvents.Entry] = []
	var packed: PackedByteArray = NetCodec.pack_snapshot(sent, null, -1, none, NetCodec.SnapshotInfo.new())
	var got: WorldSnapshot = WorldSnapshot.new()
	if not assert_true(NetCodec.unpack_snapshot(packed, null, got, NetCodec.SnapshotInfo.new(), none), "the snapshot decodes"):
		return
	assert_eq_int(got.get_count(), left.size(), "six bodies came back")
	for seat: int in left.size():
		var state: PlayerState = got.find_seat(seat)
		if not assert_not_null(state, "seat %d is in the snapshot" % seat):
			continue
		assert_eq_int(state.shove_counter, seat % 4, "seat %d shove counter" % seat)
		assert_true(state.emoting == (seat % 2 == 0), "seat %d emoting is not disturbed by the counter" % seat)
		assert_true(state.emote_alt == (seat % 3 == 0), "seat %d emote_alt is not disturbed by the counter" % seat)
		var boost: float = state.boost_remaining()
		var expected: float = float(roundi(left[seat] * 60.0)) / 60.0
		assert_almost_eq(boost, expected, 1.0 / 60.0 + 1e-4, "seat %d boost left, to the tick" % seat)
		if roundi(left[seat] * 60.0) > 0:
			assert_gt(boost, 0.0, "seat %d: a boost still running is never sent as none" % seat)
			assert_almost_eq(state.boost_multiplier, scale[seat], 0.051, "seat %d boost multiplier" % seat)
		else:
			assert_almost_eq(boost, 0.0, 0.0001, "seat %d: no boost is sent as none" % seat)
			assert_almost_eq(state.boost_multiplier, 1.0, 0.0001, "seat %d: and plain speed" % seat)


# --- The host's edges ------------------------------------------------------------

func test_the_first_command_is_pressed_against_nothing() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([SHOVE, COOK])])
	assert_eq_int(
		_run(stream, 3)[0], MoveIntent.SHOVE | MoveIntent.COOK,
		"keys down on the stream's first command are pressed, as the client's new source pressed them",
	)


func test_a_press_whose_packet_was_lost_is_run_once_from_the_next() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	# Commands 1 (shove down) and 2 (still down) went in packets that were lost; 3 carries all three.
	_send(stream, 3, [_keys([SHOVE]), _keys([SHOVE]), _keys([])])
	var pressed: Array[int] = _run(stream, 6)
	assert_eq_int(_count(pressed, MoveIntent.SHOVE), 1, "the shove is run once: %s" % str(pressed))


func test_two_presses_inside_lost_packets_are_two_edges() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	_send(stream, 4, [_keys([COOK]), _keys([]), _keys([COOK]), _keys([])])
	assert_eq_int(_count(_run(stream, 8), MoveIntent.COOK), 2, "down, up, down is two presses")


func test_a_resent_press_is_not_run_twice() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	_send(stream, 1, [_keys([]), _keys([POWER])])
	var first: Array[int] = _run(stream, 4)
	# The same commands again, as every packet repeats what the host has not acknowledged.
	_send(stream, 2, [_keys([]), _keys([POWER]), _keys([POWER])])
	_send(stream, 2, [_keys([]), _keys([POWER]), _keys([POWER])])
	var after: Array[int] = _run(stream, 4)
	assert_eq_int(_count(first, MoveIntent.POWER) + _count(after, MoveIntent.POWER), 1, "one press, once")


func test_a_power_key_press_runs_as_that_key() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	var four: MoveIntent = MoveIntent.new()
	four.buttons = MoveIntent.POWER_1 << 3
	_send(stream, 2, [_keys([]), four, _keys([])])
	var slots: Array[int] = []
	for _tick: int in 5:
		for _i: int in stream.commands_due():
			slots.append(stream.next_command(SIM_DELTA).ability_slot)
	assert_eq_int(slots.count(4), 1, "power key 4 is run once, as slot 4: %s" % str(slots))


func test_after_a_reset_the_next_command_starts_from_nothing() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([JUMP])])
	_run(stream, 1)
	stream.reset()
	_send(stream, 50, [_keys([JUMP])])
	assert_eq_int(_run(stream, 2)[0], MoveIntent.JUMP, "the new scene's first jump is a press, not the old scene's held key")
	_send(stream, 52, [_keys([JUMP]), _keys([]), _keys([JUMP])])
	assert_eq_int(_count(_run(stream, 4), MoveIntent.JUMP), 1, "and the next press is taken once")


func test_a_press_the_full_ring_could_not_hold_is_run_when_resent() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	var commands: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_COMMANDS:
		commands.append(_keys([]))
	_send(stream, 32, commands)
	_send(stream, 64, commands)
	commands[5] = _keys([COOK])
	_send(stream, 96, commands)
	assert_eq_int(stream.get_backlog(), CommandStream.RING, "the ring holds 64 ahead and stores nothing past it")
	var pressed: Array[int] = _run(stream, 40)
	# Command 70 is not acknowledged, so the client's next packets carry it again; 65 they no longer do.
	_send(stream, 97, commands.slice(1) + [_keys([])])
	pressed.append_array(_run(stream, 30))
	assert_eq_int(stream.get_ack(), 64, "the stream ran what it held and waits at the gap past its ring")
	_send(stream, 98, commands.slice(2) + [_keys([]), _keys([])])
	pressed.append_array(_run(stream, 80))
	assert_eq_int(_count(pressed, MoveIntent.COOK), 1, "the cook on command 70 is run once, off the resend")
	assert_eq_int(stream.get_ack(), 98, "and the next packet resyncs it past the gap, on to the newest")


func test_a_press_made_while_the_stream_was_paused_is_run_when_it_comes_back() -> void:
	var stream: CommandStream = _stream()
	var walking: MoveIntent = _keys([])
	walking.move_direction = Vector2(0.0, 1.0)
	_send(stream, 0, [walking])
	_run(stream, stream.stale_after_ticks + 4)
	assert_eq_int(stream.get_state(), CommandStream.State.PAUSED, "starved past the limit, the stream paused")
	var released: MoveIntent = stream.next_command(SIM_DELTA)
	assert_true(released.move_direction == Vector2.ZERO and released.buttons == 0, "and runs the body on released keys")
	_send(stream, 2, [walking, _keys([SHOVE])])
	assert_eq_int(_count(_run(stream, 4), MoveIntent.SHOVE), 1, "the shove pressed in the silence is run once")
	assert_eq_int(stream.get_state(), CommandStream.State.RUNNING, "and the stream runs again")


func test_a_key_pressed_on_the_last_command_is_one_edge() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	_send(stream, 1, [_keys([]), _keys([POWER, COOK, SHOVE, EMOTE])])
	var pressed: Array[int] = _run(stream, 6)
	for key: int in [MoveIntent.POWER, MoveIntent.COOK, MoveIntent.SHOVE, MoveIntent.EMOTE]:
		assert_eq_int(_count(pressed, key), 1, "key %d: one edge, however long nothing follows" % key)


func test_an_emote_put_up_and_down_inside_lost_packets_toggles_twice() -> void:
	var stream: CommandStream = _stream()
	_send(stream, 0, [_keys([])])
	_run(stream, 1)
	_send(stream, 4, [_keys([EMOTE]), _keys([]), _keys([EMOTE]), _keys([])])
	assert_eq_int(_count(_run(stream, 6), MoveIntent.EMOTE), 2, "two taps, two toggles: the emote ends where it began")


# --- Transport ----------------------------------------------------------------

func test_a_clients_intents_all_arrive_in_its_first_five_seconds() -> void:
	# Past the engine's first second, so the count below spans the connection's first seconds.
	await until(func() -> bool: return Time.get_ticks_msec() > 2500, 3000)
	if not await _machines():
		return
	var arrived: Array[int] = [0]
	host_links[A_SEAT].intent_received.connect(func(_peer: int, _tick: int) -> void: arrived[0] += 1)
	await step_ticks(300)
	assert_ge(float(arrived[0]), 295.0, "of 300 ticks of A's input, the host received")


func test_three_connected_machines_log_no_engine_error() -> void:
	var log: ErrorLog = ErrorLog.new()
	OS.add_logger(log)
	var up: bool = await _machines()
	if up:
		a_keys.tap_slot(MatchRules.RunnerAbility.BUBBLE_SHIELD)
		host_keys.tap(&"emote_pressed")
		await step_ticks(120)
	OS.remove_logger(log)
	if not up:
		return
	var first: String = log.lines[0] if log.count() > 0 else ""
	assert_eq_int(log.count(), 0, "engine errors with host, A and B connected (first: %s)" % first)


func test_a_rebuilt_link_carries_on_the_command_sequence() -> void:
	if not await _machines():
		return
	# A machine numbers nothing before it has heard the host's world.
	await until(func() -> bool: return a.replicator.get_latest_tick() >= 0)
	await step_ticks(1)
	var heard: int = a.replicator.outbox.next_seq()
	await step_ticks(60)
	var reached: int = a.replicator.outbox.next_seq()
	assert_ge(float(reached - heard), 60.0, "after 60 ticks of sending, the connection numbered every one")
	a_links[A_SEAT].queue_free()
	await step_ticks(1)
	var rebuilt: PlayerNetLink = NetFixtures.add_seat_body(a, A_SEAT + 2, a.get_local_peer_id(), profile, true)
	await step_ticks(3)
	assert_ge(float(a.replicator.outbox.next_seq()), float(reached), "a new link for this machine carries on the sequence")
	assert_true(rebuilt != null, "the rebuilt link stood up")


# --- Helpers ------------------------------------------------------------------

## Build the rig's three machines and connect them.
func _machines() -> bool:
	_machines_up = true
	super.before_each()
	return await stand_up()


## Keys by index into [constant BITS].
const POWER: int = 0
const COOK: int = 1
const SHOVE: int = 2
const EMOTE: int = 3
const JUMP: int = 4
const BITS: Array[int] = [MoveIntent.POWER, MoveIntent.COOK, MoveIntent.SHOVE, MoveIntent.EMOTE, MoveIntent.JUMP]


## True when [param object] has [param property]; fails naming the missing API otherwise.
func _has(object: Object, property: StringName, title: String) -> bool:
	if property in object:
		return true
	fail("API absent: %s" % title)
	return false


func _decoded() -> Array[MoveIntent]:
	var out: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_COMMANDS:
		out.append(MoveIntent.new())
	return out


## A command holding [param keys] down (indices into [constant BITS]).
func _keys(keys: Array) -> MoveIntent:
	var command: MoveIntent = MoveIntent.new()
	for key: int in keys:
		command.buttons |= BITS[key]
	return command


func _stream() -> CommandStream:
	var stream: CommandStream = CommandStream.new()
	add_child(stream)
	return stream


## [param commands] as one packet whose newest is [param newest], taken at tick 0.
func _send(stream: CommandStream, newest: int, commands: Array) -> void:
	var typed: Array[MoveIntent] = []
	typed.assign(commands)
	stream.receive(NetCodec.pack_commands(1, newest, -1, typed, typed.size()), 0)


## Run [param ticks] ticks of [param stream] as a body would; the edges of each command run.
func _run(stream: CommandStream, ticks: int) -> Array[int]:
	var pressed: Array[int] = []
	for _tick: int in ticks:
		for _i: int in stream.commands_due():
			pressed.append(stream.next_command(SIM_DELTA).pressed)
		stream.end_tick()
	if pressed.is_empty():
		pressed.append(0)
	return pressed


func _count(pressed: Array[int], bit: int) -> int:
	var total: int = 0
	for mask: int in pressed:
		total += int((mask & bit) != 0)
	return total
