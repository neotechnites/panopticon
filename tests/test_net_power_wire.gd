extends NetPowerRig

## The wire under the powers: the codec's new fields, the host's press accounting in
## [RemoteIntentSource], and the transport three machines share. Fields a build may lack are
## reached by name, so this file loads on a build without them and says what is missing.

const KEYS: PackedStringArray = ["POWER", "COOK", "SHOVE"]
const POWER: int = 0
const COOK: int = 1
const SHOVE: int = 2
## The intent flag each counted key is pressed with.
const FLAG: PackedStringArray = ["ability_pressed", "cook_pressed", "shove_pressed"]


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

func test_press_counts_and_press_slot_survive_the_intent_round_trip() -> void:
	if not _has(MoveIntent.new(), &"press_counts", "MoveIntent.press_counts"):
		return
	var sent: Array[MoveIntent] = []
	var all_at_most: int = 0
	var mixed: int = 0
	for key: int in KEYS.size():
		for _n: int in 7:
			all_at_most = _press_added(all_at_most, key)
		for _n: int in key + 1:
			mixed = _press_added(mixed, key)
	var counts: Array[int] = [0, all_at_most, mixed]
	var slots: Array[int] = [3, 0, 5]
	var press_slots: Array[int] = [5, 2, 0]
	var emotes: Array[int] = [-1, 2, 0]
	for i: int in 3:
		var intent: MoveIntent = MoveIntent.new()
		intent.ability_slot = slots[i]
		intent.emote_alt_pressed = i == 1
		intent.emote_state = emotes[i]
		intent.set(&"press_counts", counts[i])
		intent.set(&"press_slot", press_slots[i])
		sent.append(intent)
	var packed: PackedByteArray = NetCodec.pack_intents(900, sent, 3, 7)
	assert_eq_int(
		packed.size(), NetCodec.INTENT_HEADER_SIZE + 3 * NetCodec.INTENT_BODY_SIZE,
		"three intents are a header and three bodies",
	)
	assert_eq_int(NetCodec.intent_count(packed), 3, "three intents came back")
	for i: int in 3:
		var got: MoveIntent = MoveIntent.new()
		assert_eq_int(NetCodec.unpack_intent_at(packed, i, got), 898 + i, "intent %d carries its tick" % i)
		assert_eq_int(int(got.get(&"press_counts")), counts[i], "intent %d press_counts" % i)
		assert_eq_int(int(got.get(&"press_slot")), press_slots[i], "intent %d press_slot" % i)
		assert_eq_int(got.ability_slot, slots[i], "intent %d ability_slot is not mixed with press_slot" % i)
		assert_true(got.emote_alt_pressed == (i == 1), "intent %d emote_alt_pressed" % i)
		assert_eq_int(got.emote_state, emotes[i], "intent %d emote_state is not mixed with the press counts" % i)
		for key: int in KEYS.size():
			var expected: int = [0, 7, key + 1][i]
			assert_eq_int(
				int(_intent_script().call(&"press_count", int(got.get(&"press_counts")), key)), expected,
				"intent %d: %s was pressed %d times" % [i, KEYS[key], expected],
			)


func test_a_press_count_wraps_at_eight_without_touching_its_neighbours() -> void:
	if not _has(MoveIntent.new(), &"press_counts", "MoveIntent.press_counts"):
		return
	for key: int in KEYS.size():
		var counts: int = 0
		for _n: int in 8:
			counts = _press_added(counts, key)
		assert_eq_int(counts, 0, "eight presses of %s wrap its count to 0 and carry into no other key" % KEYS[key])


func test_shove_counter_and_boost_survive_the_snapshot_round_trip() -> void:
	if not _has(PlayerState.new(), &"shove_counter", "PlayerState.shove_counter"):
		return
	if not _has(PlayerState.new(), &"boost_remaining", "PlayerState.boost_remaining"):
		return
	var left: Array[float] = [0.0, 0.04, 3.26, 7.0, 30.0, 0.1]
	var scale: Array[float] = [1.0, 3.0, 3.0, 1.5, 2.0, 3.0]
	var sent: WorldSnapshot = WorldSnapshot.new()
	sent.tick = 900
	for seat: int in left.size():
		var state: PlayerState = PlayerState.new()
		state.seat_index = seat
		# Swings 0..5: the wire keeps them modulo 4.
		state.set(&"shove_counter", seat)
		state.set(&"boost_remaining", left[seat])
		state.set(&"boost_multiplier", scale[seat])
		state.emoting = seat % 2 == 0
		state.emote_alt = seat % 3 == 0
		assert_true(sent.append(state), "seat %d fits" % seat)
	var packed: PackedByteArray = NetCodec.pack_snapshot(sent)
	assert_eq_int(
		packed.size(), NetCodec.SNAPSHOT_HEADER_SIZE + left.size() * NetCodec.SNAPSHOT_BODY_SIZE,
		"six bodies are a header and six records",
	)
	var got: WorldSnapshot = WorldSnapshot.new()
	if not assert_true(NetCodec.unpack_snapshot(packed, got), "the snapshot decodes"):
		return
	assert_eq_int(got.count, left.size(), "six bodies came back")
	for seat: int in left.size():
		var state: PlayerState = got.find_seat(seat)
		if not assert_not_null(state, "seat %d is in the snapshot" % seat):
			continue
		assert_eq_int(int(state.get(&"shove_counter")), seat % 4, "seat %d shove counter" % seat)
		assert_true(state.emoting == (seat % 2 == 0), "seat %d emoting is not disturbed by the counter" % seat)
		assert_true(state.emote_alt == (seat % 3 == 0), "seat %d emote_alt is not disturbed by the counter" % seat)
		var boost: float = float(state.get(&"boost_remaining"))
		var expected: float = minf(left[seat], 25.5)
		assert_almost_eq(boost, expected, 0.1001, "seat %d boost left, to a tenth" % seat)
		if left[seat] > 0.0:
			assert_gt(boost, 0.0, "seat %d: a boost still running is never sent as none" % seat)
			assert_almost_eq(
				float(state.get(&"boost_multiplier")), scale[seat], 0.051, "seat %d boost multiplier" % seat
			)
		else:
			assert_almost_eq(boost, 0.0, 0.0001, "seat %d: no boost is sent as none" % seat)
			assert_almost_eq(float(state.get(&"boost_multiplier")), 1.0, 0.0001, "seat %d: and plain speed" % seat)


# --- The host's press accounting ----------------------------------------------

func test_the_first_command_is_taken_at_its_own_word() -> void:
	var source: RemoteIntentSource = _source()
	# Counts already running, as from a client that has been pressing since before this link.
	source.accept(1, _command(_counts_of({SHOVE: 5, COOK: 2}), [SHOVE]))
	var first: MoveIntent = source.poll(SIM_DELTA)
	assert_true(first.shove_pressed, "the first command's shove press is run")
	assert_false(first.cook_pressed, "its cook count, with no press on it, starts nothing")
	assert_eq_int(_edges(source, SHOVE, 5), 0, "and the shove is run once")


func test_a_press_on_a_command_that_never_arrived_is_run_once() -> void:
	var source: RemoteIntentSource = _source()
	var before: int = 0
	var after: int = _press_added(before, SHOVE)
	source.accept(1, _command(before))
	source.accept(2, _command(before))
	assert_eq_int(_edges(source, SHOVE, 2), 0, "no shove before one is pressed")
	# Tick 3 carried the press and tick 4 repeated its count; neither arrived.
	source.accept(5, _command(after))
	assert_eq_int(_edges(source, SHOVE, 6), 1, "the shove pressed on the lost tick 3 is run exactly once")


func test_two_presses_on_lost_commands_are_two_edges_on_two_ticks() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	source.accept(6, _command(_counts_of({COOK: 2})))
	var first: bool = source.poll(SIM_DELTA).cook_pressed
	var second: bool = source.poll(SIM_DELTA).cook_pressed
	var third: bool = source.poll(SIM_DELTA).cook_pressed
	assert_true(first, "the first missed cook press is run on the tick the count arrives")
	assert_true(second, "the second on the tick after")
	assert_false(third, "and there is no third")


func test_a_delivered_press_is_not_counted_twice() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	for key: int in KEYS.size():
		var counts: int = _counts_of({key: 1})
		source.accept(2 + key * 2, _command(counts, [key]))
		source.accept(3 + key * 2, _command(counts))
		assert_eq_int(_edges(source, key, 6), 1, "%s pressed on a command that arrived is run once" % KEYS[key])
		# Each key starts from its own baseline.
		source.reset()
		source.accept(1, _command(0))
		source.poll(SIM_DELTA)


func test_a_lost_power_press_is_run_with_the_slot_it_named() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	source.accept(4, _command(_counts_of({POWER: 1}), [], 4))
	var got: MoveIntent = source.poll(SIM_DELTA)
	assert_eq_int(got.ability_slot, 4, "a lost press of power key 4 is run as slot 4")
	assert_false(got.ability_pressed, "and not as the picked power")
	assert_eq_int(source.poll(SIM_DELTA).ability_slot, 0, "for one tick")


func test_a_lost_press_of_the_picked_power_is_run_as_the_picked_power() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	source.accept(4, _command(_counts_of({POWER: 1}), [], 0))
	var got: MoveIntent = source.poll(SIM_DELTA)
	assert_true(got.ability_pressed, "a lost press of the picked power is run as ability_pressed")
	assert_eq_int(got.ability_slot, 0, "with no slot")
	assert_false(source.poll(SIM_DELTA).ability_pressed, "for one tick")


func test_after_a_reset_the_next_command_is_a_new_baseline() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	source.reset()
	var jumped: int = _counts_of({SHOVE: 3, POWER: 2, COOK: 5})
	source.accept(1, _command(jumped))
	var total: int = 0
	for key: int in KEYS.size():
		total += _edges(source, key, 1)
	for _i: int in 6:
		var got: MoveIntent = source.poll(SIM_DELTA)
		total += int(got.shove_pressed) + int(got.ability_pressed) + int(got.cook_pressed)
		total += 1 if got.ability_slot > 0 else 0
	assert_eq_int(total, 0, "counts that jumped across a reset press nothing")
	source.accept(2, _command(_press_added(jumped, SHOVE)))
	assert_eq_int(_edges(source, SHOVE, 4), 1, "and a press counted after it is run once")


func test_a_press_on_a_command_the_full_queue_threw_away_is_still_run() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	var pressed: int = _counts_of({COOK: 1})
	# Six arrive before one is run: the queue holds four, so ticks 2 and 3 are thrown away.
	source.accept(2, _command(pressed, [COOK]))
	for tick: int in range(3, 8):
		source.accept(tick, _command(pressed))
	assert_eq_int(_edges(source, COOK, 6), 1, "the cook press on the discarded tick 2 is run exactly once")
	assert_eq_int(source.applied_tick, 7, "and the newest command was reached")


func test_a_press_made_while_the_source_was_stale_is_run_when_it_comes_back() -> void:
	var source: RemoteIntentSource = _source()
	var held: MoveIntent = _command(0)
	held.move_direction = Vector2(0.0, 1.0)
	source.accept(1, held)
	source.poll(SIM_DELTA)
	for _i: int in source.stale_after_ticks + 3:
		source.poll(SIM_DELTA)
	assert_true(source.is_stale(), "the source went stale with nothing arriving")
	source.accept(40, _command(_counts_of({SHOVE: 1})))
	assert_eq_int(_edges(source, SHOVE, 4), 1, "the shove pressed while it was stale is run once")
	assert_false(source.is_stale(), "and the source is live again")


func test_every_one_tick_key_is_an_edge_when_no_command_follows_it() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _command(0))
	source.poll(SIM_DELTA)
	var pressed: MoveIntent = _command(_counts_of({POWER: 1, COOK: 1, SHOVE: 1}))
	pressed.ability_slot = 2
	pressed.cook_pressed = true
	pressed.shove_pressed = true
	pressed.emote_pressed = true
	pressed.emote_alt_pressed = true
	pressed.set(&"press_slot", 2)
	source.accept(2, pressed)
	var first: MoveIntent = source.poll(SIM_DELTA)
	assert_eq_int(first.ability_slot, 2, "the power key is run on its tick")
	assert_true(
		first.cook_pressed and first.shove_pressed and first.emote_pressed and first.emote_alt_pressed,
		"and cook, shove and both emote keys with it",
	)
	# The ticks after it, with no new command: what the body is handed again.
	var again: PackedStringArray = PackedStringArray()
	for _i: int in 3:
		var got: MoveIntent = source.poll(SIM_DELTA)
		if got.ability_slot > 0:
			again.append("ability_slot")
		for key: int in KEYS.size():
			if bool(got.get(FLAG[key])):
				again.append(FLAG[key])
		if got.emote_pressed or got.emote_alt_pressed:
			again.append("emote")
	assert_eq_string(", ".join(again), "", "one-tick keys handed to the body again on a tick with no new command")


# --- The sender's emote, as a state ---------------------------------------------

## A command that says where its sender's emote stands.
func _emote_command(state: int) -> MoveIntent:
	var command: MoveIntent = _command(0)
	command.emote_state = state
	return command


func test_an_emote_state_is_handed_to_the_body_on_the_tick_it_changes() -> void:
	var source: RemoteIntentSource = _source()
	var handed: Array[int] = []
	for tick: int in 6:
		source.accept(tick + 1, _emote_command([0, 0, 1, 1, 2, 0][tick]))
		handed.append(source.poll(SIM_DELTA).emote_state)
	assert_eq_string(str(handed), str([-1, -1, 1, -1, 2, 0]), "the first word is a baseline; each change after is handed on once")


func test_an_emote_put_up_and_down_on_lost_commands_is_handed_to_nobody() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _emote_command(0))
	source.poll(SIM_DELTA)
	# Ticks 2 to 8 said it was up and never arrived; by tick 9 it was down again.
	source.accept(9, _emote_command(0))
	var handed: Array[int] = []
	for _i: int in 4:
		var got: MoveIntent = source.poll(SIM_DELTA)
		handed.append(got.emote_state)
		assert_false(got.emote_pressed or got.emote_alt_pressed, "and no tap is made of it")
	assert_eq_string(str(handed), str([-1, -1, -1, -1]), "the host's body is told nothing")


func test_an_emote_put_up_on_a_lost_command_is_handed_on_when_the_next_arrives() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _emote_command(0))
	source.poll(SIM_DELTA)
	source.accept(9, _emote_command(2))
	assert_eq_int(source.poll(SIM_DELTA).emote_state, 2, "the state the sender stands in is taken")
	assert_eq_int(source.poll(SIM_DELTA).emote_state, -1, "once")


func test_the_first_emote_state_after_a_rest_is_a_baseline() -> void:
	var source: RemoteIntentSource = _source()
	source.accept(1, _emote_command(0))
	source.poll(SIM_DELTA)
	source.rest()
	source.accept(2, _emote_command(1))
	assert_eq_int(source.poll(SIM_DELTA).emote_state, -1, "what was put up at a held body is not put up when it is let go")
	source.accept(3, _emote_command(0))
	assert_eq_int(source.poll(SIM_DELTA).emote_state, 0, "and the next change is")


func test_a_sender_that_says_its_emote_state_is_not_also_tapping() -> void:
	var source: RemoteIntentSource = _source()
	var said: MoveIntent = _emote_command(0)
	said.emote_pressed = true
	said.emote_alt_pressed = true
	source.accept(1, said)
	var got: MoveIntent = source.poll(SIM_DELTA)
	assert_false(got.emote_pressed or got.emote_alt_pressed, "its taps are its own to run")
	var tapped: MoveIntent = _command(0)
	tapped.emote_pressed = true
	source.accept(2, tapped)
	assert_true(source.poll(SIM_DELTA).emote_pressed, "a sender that only taps is taken at its tap")
	assert_false(source.poll(SIM_DELTA).emote_pressed, "once")


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


func test_a_rebuilt_link_carries_on_the_intent_sequence() -> void:
	if not await _machines():
		return
	await step_ticks(60)
	if not _has(a.replicator, &"intent_tick", "NetReplicator.intent_tick"):
		return
	var reached: int = int(a.replicator.get(&"intent_tick"))
	assert_eq_int(reached, a_links[A_SEAT].get_intent_tick(), "the connection's sequence is its link's")
	assert_ge(float(reached), 60.0, "after 60 ticks of sending")
	var rebuilt: PlayerNetLink = NetFixtures.add_seat_body(a, 2, a.get_local_peer_id(), profile, true)
	assert_eq_int(rebuilt.get_intent_tick(), reached, "a new link for this machine starts where the last one was")
	var other: PlayerNetLink = NetFixtures.add_seat_body(a, 3, 1, profile, false)
	assert_eq_int(other.get_intent_tick(), 0, "a link for somebody else's body does not take the sequence")


# --- Helpers ------------------------------------------------------------------

## Build the rig's three machines and connect them.
func _machines() -> bool:
	_machines_up = true
	super.before_each()
	return await stand_up()


func _intent_script() -> GDScript:
	return MoveIntent as GDScript


## True when [param object] has [param property]; fails naming the missing API otherwise.
func _has(object: Object, property: StringName, title: String) -> bool:
	if property in object:
		return true
	fail("API absent: %s" % title)
	return false


## [param counts] with one more press of [param key]; unchanged on a build that keeps no counts.
func _press_added(counts: int, key: int) -> int:
	if not (&"press_counts" in MoveIntent.new()):
		return counts
	return int(_intent_script().call(&"press_added", counts, key))


## Press counts with each key of [param presses] pressed that many times.
func _counts_of(presses: Dictionary) -> int:
	var counts: int = 0
	for key: int in presses:
		for _n: int in int(presses[key]):
			counts = _press_added(counts, key)
	return counts


## An intent carrying [param counts], pressing [param keys] on its own tick.
func _command(counts: int, keys: Array = [], press_slot: int = 0) -> MoveIntent:
	var intent: MoveIntent = MoveIntent.new()
	intent.set(&"press_counts", counts)
	intent.set(&"press_slot", press_slot)
	for key: int in keys:
		intent.set(FLAG[key], true)
	return intent


func _source() -> RemoteIntentSource:
	var source: RemoteIntentSource = RemoteIntentSource.new()
	add_child(source)
	return source


## Poll [param source] [param ticks] times; on how many was [param key] pressed.
func _edges(source: RemoteIntentSource, key: int, ticks: int) -> int:
	var edges: int = 0
	for _i: int in ticks:
		var got: MoveIntent = source.poll(SIM_DELTA)
		if bool(got.get(FLAG[key])) or (key == POWER and got.ability_slot > 0):
			edges += 1
	return edges

