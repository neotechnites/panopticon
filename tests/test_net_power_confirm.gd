extends NetPowerRig

## Every power, pressed by a client and pressed by the host, on a clean line: it runs on the
## authority, is drawn on the presser's machine and on a third peer's, and ends on all three.

const POWERS: Array[int] = [
	MatchRules.RunnerAbility.BUBBLE_SHIELD,
	MatchRules.RunnerAbility.HOLOGRAM,
	MatchRules.RunnerAbility.ARMOR_LOCK,
	MatchRules.RunnerAbility.ACTIVE_CAMO,
]


func test_a_clients_press_runs_on_the_host_and_is_drawn_on_all_three() -> void:
	if not await stand_up():
		return
	for which: int in POWERS:
		await _press_and_watch(a_keys, A_SEAT, which)


func test_the_hosts_press_is_drawn_on_both_clients() -> void:
	if not await stand_up():
		return
	for which: int in POWERS:
		await _press_and_watch(host_keys, HOST_SEAT, which)


func test_a_client_sees_its_own_power_on_the_tick_it_presses() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(MatchRules.RunnerAbility.BUBBLE_SHIELD)
	await step_ticks(2)
	assert_eq_int(
		int(power_of(a_links, A_SEAT).get_shown()), MatchRules.RunnerAbility.BUBBLE_SHIELD,
		"the presser's own machine draws the shield without waiting for the host",
	)


func test_the_power_key_runs_the_power_a_client_holds() -> void:
	if not await stand_up():
		return
	hold(MatchRules.RunnerAbility.ACTIVE_CAMO, A_SEAT)
	a_keys.tap(&"ability_pressed")
	var up: bool = await until(
		func() -> bool: return all_draw(A_SEAT, MatchRules.RunnerAbility.ACTIVE_CAMO)
	)
	assert_true(up, "Q ran the picked power on every machine: %s" % str(drawn(A_SEAT)))


func test_the_cooldown_reaches_the_client_that_owns_the_power() -> void:
	TestFixtures.set_power_cooldown(3.0)
	if not await stand_up():
		return
	a_keys.tap_power(MatchRules.RunnerAbility.BUBBLE_SHIELD)
	await until(func() -> bool: return all_draw(A_SEAT, MatchRules.RunnerAbility.BUBBLE_SHIELD))
	await until(func() -> bool: return all_draw(A_SEAT, MatchRules.RunnerAbility.NONE))
	var cooling: bool = await until(
		func() -> bool: return power_of(a_links, A_SEAT).get_cooldown_remaining() > 1.0
	)
	assert_true(cooling, "the owner's machine is told the cooldown the host is counting")
	a_keys.tap_power(MatchRules.RunnerAbility.BUBBLE_SHIELD)
	await step_ticks(30)
	assert_eq_int(
		drawn(A_SEAT)[0], MatchRules.RunnerAbility.NONE, "a press inside the cooldown starts nothing"
	)
	assert_eq_int(
		drawn(A_SEAT)[1], MatchRules.RunnerAbility.NONE,
		"and the presser's machine is not left drawing a power the host refused",
	)


## Press [param which] on [param keys], and require it up on all three and then gone from all three.
func _press_and_watch(keys: PressSource, seat: int, which: int) -> void:
	var title: String = MatchRules.runner_ability_title(which as MatchRules.RunnerAbility)
	keys.held.ability_held = true
	keys.tap_power(which)
	var up: bool = await until(func() -> bool: return all_draw(seat, which))
	assert_true(up, "%s is up on host, A and B: %s" % [title, str(drawn(seat))])
	var gone: bool = await until(
		func() -> bool: return all_draw(seat, MatchRules.RunnerAbility.NONE)
	)
	assert_true(gone, "%s ended on host, A and B: %s" % [title, str(drawn(seat))])
	keys.held.ability_held = false
	await step_ticks(4)
