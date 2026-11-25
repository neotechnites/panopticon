extends NetPowerRig

## Review suspects (presses on a bad line), each run here to prove or clear it.

const NONE: int = MatchRules.RunnerAbility.NONE
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD


## Two presses of the power key inside one burst of loss: the host runs the first, as A did, once.
func test_two_power_presses_inside_one_blackout_run_the_first() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(1)
	@warning_ignore("missing_await")
	black_out(a_wire, 12)
	await step_ticks(2)
	a_keys.tap_power(SHIELD)
	await step_ticks(6)
	a_keys.tap_power(SHIELD)
	await step_ticks(1)
	var predicted: int = int(power_of(a_links, A_SEAT).get_active())
	await step_ticks(5)
	var settled: bool = await until(func() -> bool: return drawn(A_SEAT)[0] != NONE)
	await step_ticks(20)
	print("PROOF two-presses: A predicted %d; after the blackout host/A/B draw %s (shield=%d)" % [
		predicted, str(drawn(A_SEAT)), SHIELD])
	assert_true(settled, "the host ran a power")
	assert_eq_int(predicted, SHIELD, "A's own machine ran the first press")
	assert_eq_int(drawn(A_SEAT)[0], SHIELD, "and so did the host")
	assert_eq_int(drawn(A_SEAT)[1], SHIELD, "which A still draws")


## The emote toggled on then off inside one burst of loss: the host runs both presses late, as A
## ran them, so it ends down everywhere and A's own body is never put back up.
func test_an_emote_put_up_and_down_inside_a_blackout_ends_down_everywhere() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	@warning_ignore("missing_await")
	black_out(a_wire, 14)
	await step_ticks(2)
	a_keys.tap(&"emote_pressed")
	await step_ticks(6)
	assert_true(mine.is_emoting(), "A's own emote is up on its own machine")
	a_keys.tap(&"emote_pressed")
	await step_ticks(2)
	assert_false(mine.is_emoting(), "and down again on the second tap")
	var came_back: int = 0
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var host_up: int = 0
	for _tick: int in 60:
		await step_ticks(1)
		if mine.is_emoting():
			came_back += 1
		if copy.is_emoting():
			host_up += 1
	print("PROOF emote-flicker: in the second after, A's own emote was up on %d ticks; the host's copy on %d" % [came_back, host_up])
	# Every command rides every packet, so the host runs the up and the down it was sent, late.
	assert_gt(float(host_up), 0.0, "the host's copy runs the emote the lost packets carried")
	assert_le(float(host_up), 6.0, "for no more commands than A had it up")
	assert_eq_int(came_back, 0, "and A's own body is never put back up")
	assert_false(mine.is_emoting(), "and it ends down on A's machine")
	assert_false(copy.is_emoting(), "and on the host")


## Jump, land, mash the emote key, again and again, at a real delay: once the keys stop the emote
## stands still on every machine. Nothing but a press may move the host's copy.
func _mashing_settles(delay_ms: int, rounds: int, gap: int) -> void:
	if not await stand_up(0.0, delay_ms):
		return
	await step_ticks(30)
	for round: int in rounds:
		a_keys.tap(&"jump_pressed")
		await step_ticks(34 + round)
		for i: int in 6:
			a_keys.tap(&"emote_pressed")
			await step_ticks(gap + (i % 3))
	await step_ticks(180)
	var bodies: Array[PlayerController] = [body_of(a_links, A_SEAT), body_of(host_links, A_SEAT), body_of(b_links, A_SEAT)]
	var flips: int = 0
	var was: Array[bool] = [bodies[0].is_emoting(), bodies[1].is_emoting(), bodies[2].is_emoting()]
	for _tick: int in 300:
		await step_ticks(1)
		for k: int in 3:
			if bodies[k].is_emoting() != was[k]:
				flips += 1
				was[k] = bodies[k].is_emoting()
	print("PROOF emote-echo %d ms: three seconds after the last key the emote flipped %d times in the next 300 ticks; A/host/B emoting %s" % [delay_ms, flips, str(was)])
	assert_eq_int(flips, 0, "the emote stands still once the keys stop")
	assert_true(was[0] == was[1] and was[1] == was[2], "and every machine agrees whether it is up: %s" % str(was))


func test_an_emote_mashed_through_jumps_settles_at_40_ms() -> void:
	await _mashing_settles(40, 6, 2)


func test_an_emote_mashed_through_jumps_settles_at_60_ms() -> void:
	await _mashing_settles(60, 6, 2)


func test_an_emote_mashed_through_jumps_settles_at_100_ms() -> void:
	await _mashing_settles(100, 4, 4)


## One emote tap inside a burst of loss: once up on A's machine it stays up while the host catches up.
func test_an_emote_put_up_inside_a_blackout_does_not_drop() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	@warning_ignore("missing_await")
	black_out(a_wire, 8)
	await step_ticks(2)
	a_keys.tap(&"emote_pressed")
	await step_ticks(2)
	assert_true(mine.is_emoting(), "A's own emote is up on its own machine")
	var dropped: int = 0
	for _tick: int in 60:
		await step_ticks(1)
		if not mine.is_emoting():
			dropped += 1
	var copy: PlayerController = body_of(host_links, A_SEAT)
	print("PROOF emote-drop: in the second after, A's own emote was down on %d ticks; host copy emoting=%s" % [dropped, str(copy.is_emoting())])
	assert_eq_int(dropped, 0, "the emote never drops on the machine that started it")
	assert_true(copy.is_emoting(), "and the host has it up")


## Two power presses in one packet ride the wire as their own levels, each on its command.
func test_two_power_presses_in_one_packet_stay_two_presses() -> void:
	var two: MoveIntent = MoveIntent.new()
	two.buttons = MoveIntent.POWER
	var five: MoveIntent = MoveIntent.new()
	five.buttons = MoveIntent.POWER | MoveIntent.SHOVE | MoveIntent.AIM | MoveIntent.COOK
	var sent: Array[MoveIntent] = [two, MoveIntent.new(), five]
	var out: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_COMMANDS:
		out.append(MoveIntent.new())
	assert_eq_int(NetCodec.unpack_commands(NetCodec.pack_commands(1, 8, -1, sent, 3), out, -1), 3, "it decodes")
	var edges: Array[int] = []
	var last: int = 0
	for i: int in 3:
		out[i].derive_edges(last)
		last = out[i].buttons
		edges.append(int(out[i].ability_pressed))
	assert_eq_string(str(edges), str([1, 0, 1]), "a press on the first command and on the third")
	assert_true(out[2].shove_pressed and out[2].aim_held and out[2].cook_pressed, "and the keys pressed with it")
