extends NetPowerRig

## The two emotes (B: cat dribble, N: REPO bot dribble) across three machines: the presser's own
## body, the host's copy and a third peer's mirror agree on whether it is up and which one it is.

const EMOTE: StringName = &"emote_pressed"
const EMOTE_ALT: StringName = &"emote_alt_pressed"
## Ticks let pass after connecting, so a press is not made while a new connection is still settling.
const SETTLE_TICKS: int = 180


func test_a_clients_b_emote_toggles_on_all_three() -> void:
	if not await _stand_up_settled():
		return
	await _toggle_and_watch(a_keys, A_SEAT, EMOTE, false, "A's B emote")


func test_a_clients_n_emote_toggles_on_all_three() -> void:
	if not await _stand_up_settled():
		return
	await _toggle_and_watch(a_keys, A_SEAT, EMOTE_ALT, true, "A's N emote")


func test_the_hosts_b_emote_toggles_on_both_clients() -> void:
	if not await _stand_up_settled():
		return
	await _toggle_and_watch(host_keys, HOST_SEAT, EMOTE, false, "the host's B emote")


func test_the_hosts_n_emote_toggles_on_both_clients() -> void:
	if not await _stand_up_settled():
		return
	await _toggle_and_watch(host_keys, HOST_SEAT, EMOTE_ALT, true, "the host's N emote")


func test_n_over_b_swaps_the_object_and_keeps_the_emote_on_all_three() -> void:
	if not await _stand_up_settled():
		return
	a_keys.tap(EMOTE)
	var cat: bool = await until(func() -> bool: return _all(A_SEAT, true, false))
	assert_true(cat, "B is up on host, A and B: %s" % _emotes(A_SEAT))
	a_keys.tap(EMOTE_ALT)
	var bot: bool = await until(func() -> bool: return _all(A_SEAT, true, true))
	assert_true(bot, "N over B is the alternate emote on host, A and B: %s" % _emotes(A_SEAT))
	await step_ticks(20)
	assert_true(_all(A_SEAT, true, true), "and it stays: %s" % _emotes(A_SEAT))


func test_moving_ends_a_clients_emote_on_all_three() -> void:
	if not await _stand_up_settled():
		return
	await _move_ends_it(a_keys, A_SEAT, "A's")


func test_moving_ends_the_hosts_emote_on_all_three() -> void:
	if not await _stand_up_settled():
		return
	await _move_ends_it(host_keys, HOST_SEAT, "the host's")


func test_one_n_tap_stays_up_on_the_host_on_a_clean_line() -> void:
	if not await _stand_up_settled():
		return
	await _one_n_tap_stays_up("clean line")


func test_one_n_tap_stays_up_on_the_host_at_40_ms() -> void:
	if not await _stand_up_settled(0.0, 40):
		return
	await _one_n_tap_stays_up("40 ms each way")


func test_one_n_tap_stays_up_on_the_host_through_a_gap_in_the_clients_packets() -> void:
	if not await _stand_up_settled(0.0, 1):
		return
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var seen: Array[bool] = [copy.is_emoting()]
	var watch: Callable = func() -> void: seen.append(copy.is_emoting())
	get_tree().physics_frame.connect(watch)
	a_keys.tap(EMOTE_ALT)
	# The press goes out on this tick; the packets of the four after it never arrive.
	await step_ticks(1)
	await black_out(a_wire, 4)
	await step_ticks(60)
	get_tree().physics_frame.disconnect(watch)
	assert_eq_int(_flips(seen), 1, "the host's copy changed its emote once for one N tap")
	assert_true(copy.is_emoting() and copy.is_emote_alt(), "and is still in the N emote: %s" % _emotes(A_SEAT))
	assert_true(_all(A_SEAT, true, true), "on all three: %s" % _emotes(A_SEAT))


func test_the_host_turning_an_emote_off_reaches_the_client_that_owns_it() -> void:
	if not await _stand_up_settled():
		return
	a_keys.tap(EMOTE)
	var up: bool = await until(func() -> bool: return _all(A_SEAT, true, false))
	assert_true(up, "B is up on host, A and B: %s" % _emotes(A_SEAT))
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var motion: PackedFloat32Array = PackedFloat32Array()
	copy.capture_motion_state(motion)
	motion[20] = 0.0
	motion[21] = 0.0
	copy.restore_motion_state(motion)
	assert_false(copy.is_emoting(), "the host's copy was taken out of the emote")
	var own: PlayerController = body_of(a_links, A_SEAT)
	var stopped: bool = await _within_ticks(func() -> bool: return not own.is_emoting(), 30)
	assert_true(stopped, "A's own body stops emoting within 30 ticks of the host's copy stopping")
	await step_ticks(20)
	assert_true(_all(A_SEAT, false, false), "and all three stay out of it: %s" % _emotes(A_SEAT))


func test_a_b_press_made_inside_a_burst_of_loss_still_reaches_the_host() -> void:
	if not await _stand_up_settled(0.0, 1):
		return
	a_keys.tap(EMOTE)
	await black_out(a_wire, 4)
	await step_ticks(30)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var own: PlayerController = body_of(a_links, A_SEAT)
	assert_true(copy.is_emoting(), "the host's copy is emoting 30 ticks after the burst")
	assert_true(own.is_emoting(), "A's own body is emoting 30 ticks after the burst")
	assert_true(
		copy.is_emoting() == own.is_emoting(), "the host and A agree: %s" % _emotes(A_SEAT)
	)
	var mirrored: bool = await until(func() -> bool: return _all(A_SEAT, true, false))
	assert_true(mirrored, "and B's mirror shows it: %s" % _emotes(A_SEAT))


# --- Helpers ------------------------------------------------------------------

func _stand_up_settled(loss: float = 0.0, delay_ms: int = 0) -> bool:
	if not await stand_up(loss, delay_ms):
		return false
	await step_ticks(SETTLE_TICKS)
	return true


## [param seat]'s body on the host, on A and on B.
func _bodies(seat: int) -> Array[PlayerController]:
	return [body_of(host_links, seat), body_of(a_links, seat), body_of(b_links, seat)]


## True when all three machines have [param seat] emoting (or not) with the object [param alt] names.
func _all(seat: int, emoting: bool, alt: bool) -> bool:
	for body: PlayerController in _bodies(seat):
		if body.is_emoting() != emoting:
			return false
		if emoting and body.is_emote_alt() != alt:
			return false
	return true


func _emotes(seat: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var names: PackedStringArray = PackedStringArray(["host", "A", "B"])
	var bodies: Array[PlayerController] = _bodies(seat)
	for i: int in bodies.size():
		var state: String = "off"
		if bodies[i].is_emoting():
			state = "N" if bodies[i].is_emote_alt() else "B"
		parts.append("%s=%s" % [names[i], state])
	return ", ".join(parts)


## Check [param predicate] at every tick boundary for up to [param ticks] ticks.
func _within_ticks(predicate: Callable, ticks: int) -> bool:
	for _i: int in ticks:
		if bool(predicate.call()):
			return true
		await step_ticks(1)
	return bool(predicate.call())


## How many times a per-tick record changed value.
func _flips(seen: Array[bool]) -> int:
	var flips: int = 0
	for i: int in range(1, seen.size()):
		if seen[i] != seen[i - 1]:
			flips += 1
	return flips


func _toggle_and_watch(keys: PressSource, seat: int, key: StringName, alt: bool, what: String) -> void:
	keys.tap(key)
	var up: bool = await until(func() -> bool: return _all(seat, true, alt))
	assert_true(up, "%s is up on host, A and B: %s" % [what, _emotes(seat)])
	await step_ticks(20)
	assert_true(_all(seat, true, alt), "%s is still up 20 ticks on: %s" % [what, _emotes(seat)])
	keys.tap(key)
	var down: bool = await until(func() -> bool: return _all(seat, false, false))
	assert_true(down, "a second tap ends %s on host, A and B: %s" % [what, _emotes(seat)])
	await step_ticks(20)
	assert_true(_all(seat, false, false), "%s stays ended: %s" % [what, _emotes(seat)])


func _move_ends_it(keys: PressSource, seat: int, whose: String) -> void:
	keys.tap(EMOTE)
	var up: bool = await until(func() -> bool: return _all(seat, true, false))
	assert_true(up, "%s emote is up on host, A and B: %s" % [whose, _emotes(seat)])
	keys.held.move_direction = Vector2(0.0, 1.0)
	var down: bool = await until(func() -> bool: return _all(seat, false, false))
	assert_true(down, "moving ends %s emote on host, A and B: %s" % [whose, _emotes(seat)])
	keys.held.move_direction = Vector2.ZERO
	await step_ticks(30)
	assert_true(_all(seat, false, false), "and stopping does not bring it back: %s" % _emotes(seat))


## One N tap from A: the host's copy is up 10 ticks on, still up 60 ticks on, and changed once.
func _one_n_tap_stays_up(line: String) -> void:
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var seen: Array[bool] = [copy.is_emoting()]
	var watch: Callable = func() -> void: seen.append(copy.is_emoting())
	get_tree().physics_frame.connect(watch)
	a_keys.tap(EMOTE_ALT)
	await step_ticks(11)
	assert_true(copy.is_emoting() and copy.is_emote_alt(), "%s: the host's copy is in the N emote 10 ticks after the tap" % line)
	await step_ticks(50)
	get_tree().physics_frame.disconnect(watch)
	assert_true(copy.is_emoting() and copy.is_emote_alt(), "%s: and still in it 60 ticks after: %s" % [line, _emotes(A_SEAT)])
	assert_eq_int(_flips(seen), 1, "%s: the host's copy changed its emote once for one N tap" % line)
	assert_true(_all(A_SEAT, true, true), "%s: all three show it: %s" % [line, _emotes(A_SEAT)])


# --- Wire shim: the rig swaps the peer after the handshake, which empties the API's peer list ---

func _condition(session: NetSession, loss: float, rng_seed: int, delay_ms: int) -> LossyPeer:
	var known: PackedInt32Array = session.multiplayer.get_peers()
	var wire: LossyPeer = super(session, loss, rng_seed, delay_ms)
	for id: int in known:
		if not session.multiplayer.get_peers().has(id):
			wire.peer_connected.emit(id)
	return wire


func after_each() -> void:
	super()
	# The wire's forwarding lambdas hold it alive past exit; let go of them.
	for wire: LossyPeer in [a_wire, host_wire]:
		if wire == null:
			continue
		var real: MultiplayerPeer = wire.get("_real") as MultiplayerPeer
		for forwarded: Signal in [real.peer_connected, real.peer_disconnected]:
			for link: Dictionary in forwarded.get_connections():
				forwarded.disconnect(link["callable"] as Callable)
