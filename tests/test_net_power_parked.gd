extends NetPowerRig

## A body the match has parked (held: a round break, a kill beat): keys pressed at it are consumed
## by commands that move nothing, and none of them runs when it is let go.

const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD


func test_a_press_made_while_parked_does_not_fire_on_the_way_back() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	# The host has parked it and the client has not heard yet: the key still goes out.
	copy.set_held(true)
	await step_ticks(3)
	a_keys.tap_power(SHIELD)
	a_keys.tap(&"emote_pressed")
	await step_ticks(10)
	copy.set_held(false)
	var started: bool = false
	for _tick: int in 40:
		await step_ticks(1)
		started = started or drawn(A_SEAT)[0] != MatchRules.RunnerAbility.NONE or copy.is_emoting()
	assert_false(started, "nothing pressed at a parked body runs when it is let go: %s" % str(drawn(A_SEAT)))
	await until(func() -> bool: return all_draw(A_SEAT, MatchRules.RunnerAbility.NONE))
	a_keys.tap_power(SHIELD)
	var up: bool = await until(func() -> bool: return all_draw(A_SEAT, SHIELD))
	assert_true(up, "and the next real press runs: %s" % str(drawn(A_SEAT)))


func test_an_edge_on_the_last_intent_before_parking_is_one_press() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var edges: Array[int] = [0]
	var watch: Callable = func() -> void:
		if copy.get_intent().shove_pressed:
			edges[0] += 1
	get_tree().physics_frame.connect(watch)
	a_keys.tap(&"shove_pressed")
	await step_ticks(1)
	# Parked on its own machine with the tap just sent; the host's copy keeps running.
	mine.set_held(true)
	await step_ticks(12)
	mine.set_held(false)
	await step_ticks(20)
	get_tree().physics_frame.disconnect(watch)
	assert_eq_int(edges[0], 1, "one tap before a park is one shove on the host")
