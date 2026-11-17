extends NetPowerRig

## Review proofs: what a client's parked body re-sends, and what its own body replays when it is parked.


## One jump tap on the last tick before the CLIENT parks its body; the host's copy keeps running
## (the host wakes a body before the client hears of it, and parks it before too).
func test_rv_jump_tap_before_park_is_one_jump_on_host() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var edges: Array[int] = [0, 0]
	var watch: Callable = func() -> void:
		if copy.get_intent().jump_pressed:
			edges[0] += 1
		if copy.get_intent().fire_pressed:
			edges[1] += 1
	get_tree().physics_frame.connect(watch)
	var jumps: Array[int] = [0]
	copy.jumped.connect(func() -> void: jumps[0] += 1)
	a_keys.tap(&"jump_pressed")
	a_keys.tap(&"fire_pressed")
	await step_ticks(1)
	mine.set_physics_process(false)
	await step_ticks(40)
	mine.set_physics_process(true)
	await step_ticks(20)
	get_tree().physics_frame.disconnect(watch)
	print("PROOF parked-edges: host saw jump_pressed on %d ticks, fire_pressed on %d ticks, jumped %d times" % [edges[0], edges[1], jumps[0]])
	assert_eq_int(edges[0], 1, "one jump tap before a park is one jump edge on the host")
	assert_eq_int(edges[1], 1, "one fire click before a park is one fire edge on the host")
	assert_eq_int(jumps[0], 1, "and the host's copy jumps once")


## The fire latch the host's trigger reads: one click before a park must be one pull.
func test_rv_fire_click_before_park_is_one_trigger_pull() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	var source: RemoteIntentSource = host_links[A_SEAT].get_remote_source()
	var pulls: Array[int] = [0]
	var watch: Callable = func() -> void:
		if source.take_fire():
			pulls[0] += 1
	get_tree().physics_frame.connect(watch)
	a_keys.tap(&"fire_pressed")
	await step_ticks(1)
	mine.set_physics_process(false)
	await step_ticks(40)
	mine.set_physics_process(true)
	await step_ticks(20)
	get_tree().physics_frame.disconnect(watch)
	print("PROOF parked-fire: host trigger pulled %d times for one click" % pulls[0])
	assert_eq_int(pulls[0], 1, "one click is one trigger pull")


## A predicting client jumps three times, then the match parks its body (death, round break).
## Its own body must not replay those jumps as the mirror takes over.
func test_rv_own_jumps_are_not_replayed_when_parked() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	for _i: int in 3:
		a_keys.tap(&"jump_pressed")
		await step_ticks(50)
	await step_ticks(30)
	var heard: Array[int] = [0]
	mine.jumped.connect(func() -> void: heard[0] += 1)
	mine.set_physics_process(false)
	await step_ticks(30)
	print("PROOF parked-own-jumps: own body emitted jumped %d times after being parked" % heard[0])
	assert_eq_int(heard[0], 0, "a parked body replays none of the jumps it already made")
