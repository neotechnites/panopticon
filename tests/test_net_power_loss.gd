extends "res://tests/support/net_power_wired_rig.gd"

## A client's key presses on a bad line: every press reaches the host exactly once, whatever
## the wire dropped, delayed or the host refused, and the presser is never left drawing a lie.

const NONE: int = MatchRules.RunnerAbility.NONE
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const ALL_POWERS: Array[int] = [SHIELD, HOLOGRAM, ARMOR, CAMO, CAT]
## Ticks between presses in the random-loss run: longer than the power's one second.
const PRESS_SPACING_TICKS: int = 100
## The loss pattern of the random-loss run, fixed so every run drops the same packets.
const LOSS_SEED: int = 11


func test_shield_pressed_inside_a_blackout_still_runs() -> void:
	await _press_inside_blackout(SHIELD)


func test_hologram_pressed_inside_a_blackout_still_runs() -> void:
	await _press_inside_blackout(HOLOGRAM)


func test_armor_lock_pressed_inside_a_blackout_still_runs() -> void:
	await _press_inside_blackout(ARMOR)


func test_camo_pressed_inside_a_blackout_still_runs() -> void:
	await _press_inside_blackout(CAMO)


func test_cat_pressed_inside_a_blackout_still_runs() -> void:
	await _press_inside_blackout(CAT)


func test_every_power_pressed_while_the_host_is_stalled_runs_when_it_resumes() -> void:
	if not await stand_up(0.0, 1):
		return
	for which: int in ALL_POWERS:
		await step_ticks(1)
		a_keys.held.ability_held = which == ARMOR
		@warning_ignore("missing_await")
		stall_host(20)
		await step_ticks(10)
		a_keys.tap_slot(which)
		await step_ticks(1)
		assert_eq_int(
			drawn(A_SEAT)[0], NONE, "%s: the stalled host has run nothing yet" % _title(which)
		)
		var up: bool = await until(func() -> bool: return all_draw(A_SEAT, which))
		assert_true(
			up,
			"%s pressed during a host stall is up on host, A and B: %s"
			% [_title(which), str(drawn(A_SEAT))],
		)
		await _finish(which)


func test_twelve_shield_presses_under_random_loss_all_run() -> void:
	if not await stand_up(0.3, 0):
		return
	await step_ticks(1)
	(a_wire.get("_rng") as RandomNumberGenerator).seed = LOSS_SEED
	var host_power: RunnerPower = power_of(host_links, A_SEAT)
	var a_power: RunnerPower = power_of(a_links, A_SEAT)
	var starts: int = 0
	var was_up: bool = false
	var left_drawing: int = 0
	for press: int in 12:
		a_keys.tap_slot(SHIELD)
		for _tick: int in PRESS_SPACING_TICKS:
			await step_ticks(1)
			var up: bool = int(host_power.get_active()) != NONE
			if up and not was_up:
				starts += 1
			was_up = up
		if int(host_power.get_active()) == NONE and int(a_power.get_shown()) != NONE:
			left_drawing += 1
	assert_gt(float(a_wire.dropped), 100.0, "the wire dropped packets: this run was lossy")
	assert_eq_int(starts, 12, "the host started one shield per press at 30% loss")
	assert_eq_int(
		left_drawing, 0, "presses after which A still drew a power the host was not running"
	)


func test_a_predicted_power_never_flickers_at_80ms() -> void:
	if not await stand_up(0.0, 80):
		return
	var host_power: RunnerPower = power_of(host_links, A_SEAT)
	var a_power: RunnerPower = power_of(a_links, A_SEAT)
	for which: int in [SHIELD, HOLOGRAM, ARMOR, CAMO]:
		await step_ticks(1)
		a_keys.held.ability_held = which == ARMOR
		a_keys.tap_slot(which)
		await step_ticks(2)
		assert_eq_int(
			int(a_power.get_shown()), which, "%s is drawn on A before the host answers" % _title(which)
		)
		var host_ran: bool = false
		var host_ended: bool = false
		var blank_ticks: int = 0
		for _tick: int in 300:
			await step_ticks(1)
			var on_host: int = int(host_power.get_active())
			if on_host == which:
				host_ran = true
			elif host_ran:
				host_ended = true
				break
			if int(a_power.get_shown()) != which:
				blank_ticks += 1
		assert_true(host_ran, "%s ran on the host at 80 ms" % _title(which))
		assert_true(host_ended, "%s ended on the host at 80 ms" % _title(which))
		assert_eq_int(
			blank_ticks, 0,
			"%s: ticks A stopped drawing it before the host's had ended" % _title(which),
		)
		a_keys.held.ability_held = false
		var gone: bool = await until(func() -> bool: return all_draw(A_SEAT, NONE))
		assert_true(gone, "%s ended on host, A and B: %s" % [_title(which), str(drawn(A_SEAT))])
		await step_ticks(4)


func test_one_tick_keys_pressed_inside_a_blackout_arrive_as_one_edge() -> void:
	if not await stand_up(0.0, 1):
		return
	var keys: Array[StringName] = [
		&"cook_pressed", &"shove_pressed", &"emote_pressed", &"emote_alt_pressed",
	]
	for key: StringName in keys:
		await step_ticks(1)
		var dropped_before: int = a_wire.dropped
		@warning_ignore("missing_await")
		black_out(a_wire, 4)
		await step_ticks(2)
		a_keys.tap(key)
		var edges: int = await _count_ticks_set(key, 40)
		assert_ge(
			float(a_wire.dropped - dropped_before), 3.0,
			"%s: the blackout dropped the press and its repeat" % key,
		)
		assert_eq_int(edges, 1, "%s pressed in a blackout: ticks the host's body read it" % key)


func test_emote_alt_is_one_edge_on_a_clean_line() -> void:
	if not await stand_up():
		return
	await step_ticks(1)
	a_keys.tap(&"emote_alt_pressed")
	var edges: int = await _count_ticks_set(&"emote_alt_pressed", 60)
	assert_eq_int(edges, 1, "one N press: ticks the host's body read it in the next 60")


func test_power_slot_is_one_edge_on_a_clean_line() -> void:
	if not await stand_up():
		return
	await step_ticks(1)
	a_keys.tap_slot(SHIELD)
	var edges: int = await _count_ticks_set(&"ability_slot", 60)
	assert_eq_int(edges, 1, "one press of 1: ticks the host's body read a slot in the next 60")


func test_emote_alt_is_one_edge_when_no_packet_follows_it() -> void:
	var edges: int = await _edges_when_the_line_goes_quiet(&"emote_alt_pressed")
	if edges >= 0:
		assert_eq_int(edges, 1, "one N press, then silence: ticks the host's body read it")


func test_power_slot_is_one_edge_when_no_packet_follows_it() -> void:
	var edges: int = await _edges_when_the_line_goes_quiet(&"ability_slot")
	if edges >= 0:
		assert_eq_int(edges, 1, "one press of 1, then silence: ticks the host's body read a slot")


func test_a_shield_the_host_refuses_is_cancelled_on_the_presser() -> void:
	if not await stand_up():
		return
	await step_ticks(1)
	power_of(host_links, A_SEAT).rules = null
	a_keys.tap_slot(SHIELD)
	await step_ticks(2)
	assert_eq_int(drawn(A_SEAT)[1], SHIELD, "A drew its shield before the host refused it")
	await step_ticks(30)
	assert_eq_int(drawn(A_SEAT)[0], NONE, "the host refused the shield")
	assert_eq_int(drawn(A_SEAT)[1], NONE, "A stopped drawing the refused shield within 30 ticks")
	assert_eq_int(
		_live_nodes(a.get_parent(), "BubbleShield"), 0, "shields left standing on A's machine"
	)
	assert_eq_int(
		_live_nodes(b.get_parent(), "BubbleShield"), 0, "shields drawn on B for a refused press"
	)


func test_an_armor_lock_the_host_refuses_is_cancelled_on_the_presser() -> void:
	if not await stand_up():
		return
	await step_ticks(1)
	power_of(host_links, A_SEAT).rules = null
	a_keys.held.ability_held = true
	a_keys.tap_slot(ARMOR)
	await step_ticks(2)
	assert_eq_int(drawn(A_SEAT)[1], ARMOR, "A drew its lock before the host refused it")
	assert_true(body_of(a_links, A_SEAT).movement_locked, "A's predicted lock held its body")
	await step_ticks(30)
	assert_eq_int(drawn(A_SEAT)[0], NONE, "the host refused the armor lock")
	assert_eq_int(drawn(A_SEAT)[1], NONE, "A stopped drawing the refused lock within 30 ticks")
	assert_false(
		body_of(a_links, A_SEAT).movement_locked, "A's body is free again after the refusal"
	)
	assert_eq_int(
		_live_nodes(body_of(a_links, A_SEAT), "ArmorShell"), 0, "shells left on A's own body"
	)


func test_every_refused_power_leaves_the_presser_drawing_nothing() -> void:
	if not await stand_up():
		return
	power_of(host_links, A_SEAT).rules = null
	for which: int in ALL_POWERS:
		await step_ticks(1)
		a_keys.tap_slot(which)
		await step_ticks(30)
		assert_eq_int(
			drawn(A_SEAT)[1], NONE, "%s refused by the host: what A draws" % _title(which)
		)
		assert_eq_int(drawn(A_SEAT)[2], NONE, "%s refused by the host: what B draws" % _title(which))
	assert_eq_int(
		_live_nodes(a.get_parent(), "Hologram"), 0, "holograms left on A's machine after refusals"
	)


## Press [param which] two ticks into a four-tick blackout of A's sends, and require it everywhere.
func _press_inside_blackout(which: int) -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(1)
	a_keys.held.ability_held = which == ARMOR
	var dropped_before: int = a_wire.dropped
	@warning_ignore("missing_await")
	black_out(a_wire, 4)
	await step_ticks(2)
	a_keys.tap_slot(which)
	await step_ticks(3)
	assert_ge(
		float(a_wire.dropped - dropped_before), 3.0,
		"the blackout dropped the press and the packet that repeats it",
	)
	var up: bool = await until(func() -> bool: return all_draw(A_SEAT, which))
	assert_true(
		up,
		"%s pressed inside a blackout is up on host, A and B: %s"
		% [_title(which), str(drawn(A_SEAT))],
	)
	await _finish(which)


## Let [param which] end, by whatever ends it, and require it gone from all three.
func _finish(which: int) -> void:
	a_keys.held.ability_held = false
	if which == CAT and drawn(A_SEAT)[0] == CAT:
		a_keys.tap(&"cook_pressed")
	var gone: bool = await until(func() -> bool: return all_draw(A_SEAT, NONE), 8000)
	assert_true(gone, "%s ended on host, A and B: %s" % [_title(which), str(drawn(A_SEAT))])
	await step_ticks(4)


## Tap [param flag] once, cut A's line the tick after, and count the host ticks that read it.
func _edges_when_the_line_goes_quiet(flag: StringName) -> int:
	if not await stand_up(0.0, 1):
		return -1
	await step_ticks(1)
	if flag == &"ability_slot":
		# Refused on the host, so nothing but the key itself can stop a second read.
		power_of(host_links, A_SEAT).rules = null
		a_keys.tap_slot(SHIELD)
	else:
		a_keys.tap(flag)
	await step_ticks(1)
	@warning_ignore("missing_await")
	black_out(a_wire, 8)
	return await _count_ticks_set(flag, 30)


## How many of the next [param ticks] ticks the host's copy of A's body read [param flag] as set.
func _count_ticks_set(flag: StringName, ticks: int) -> int:
	var body: PlayerController = body_of(host_links, A_SEAT)
	var seen: int = 0
	for _tick: int in ticks:
		await step_ticks(1)
		if int(body.get_intent().get(flag)) != 0:
			seen += 1
	return seen


## Nodes under [param root] whose name carries [param fragment] and that are not on their way out.
func _live_nodes(root: Node, fragment: String) -> int:
	var found: int = 0
	for node: Node in root.find_children("*%s*" % fragment, "", true, false):
		if not node.is_queued_for_deletion():
			found += 1
	return found


func _title(which: int) -> String:
	return MatchRules.runner_ability_title(which)
