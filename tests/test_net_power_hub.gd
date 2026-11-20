extends "res://tests/support/net_hub_rig.gd"

## Powers, shoves, the power cat and the hub cats in the shipped hub, across three machines:
## what the authority decides, what the presser's machine draws and what a third peer draws.

const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const NONE: int = MatchRules.RunnerAbility.NONE
## Ticks for a swing that was going to be drawn twice to show its second.
const ECHO_TICKS: int = 60


# --- 1. Bring-up ----------------------------------------------------------------

func test_three_machines_stand_in_one_hub() -> void:
	if not await stand_up():
		return
	for machine: int in 3:
		assert_eq_int(
			ctrl(machine).get_participants().size(), 3,
			"machine %d has a participant per seat" % machine,
		)
		assert_true(ctrl(machine).is_mirror() == (machine != HOST), "only the host decides (machine %d)" % machine)
		for seat: int in 3:
			assert_not_null(body(machine, seat), "machine %d has a body for seat %d" % [machine, seat])
		assert_eq_int(cats(machine).size(), 6, "machine %d has the six hub cats" % machine)
	# A second of nothing: three hubs exchanging snapshots raise no engine error.
	await step_ticks(60)
	for seat: int in 3:
		var truth: Vector3 = body(HOST, seat).global_position
		for machine: int in [A, B]:
			assert_le(
				body(machine, seat).global_position.distance_to(truth), 0.5,
				"machine %d draws seat %d where the host has it" % [machine, seat],
			)


# --- 2. A late joiner -----------------------------------------------------------

func test_a_late_joiner_does_not_freeze_a_client_on_a_clean_line() -> void:
	await _walk_join_walk(0)


func test_a_late_joiner_does_not_freeze_a_client_at_40_ms() -> void:
	await _walk_join_walk(40)


func _walk_join_walk(delay_ms: int) -> void:
	if not await stand_up(0.0, delay_ms, 2):
		return
	var before: Vector3 = body(HOST, A).global_position
	keys[A].held.move_direction = Vector2(0.0, 1.0)
	await step_ticks(120)
	keys[A].held.move_direction = Vector2.ZERO
	assert_gt(
		flat_distance(body(HOST, A).global_position, before), 1.0,
		"before anyone joins, the host's copy of A follows A's walk",
	)
	if not await join_late():
		return
	for machine: int in 3:
		assert_eq_int(
			ctrl(machine).get_participants().size(), 3,
			"machine %d seated three in its hub" % machine,
		)
	await step_ticks(10)
	var rebuilt: Vector3 = body(HOST, A).global_position
	var seen_by_b: Vector3 = body(B, A).global_position
	keys[A].held.move_direction = Vector2(0.0, 1.0)
	var ticks: int = 0
	while ticks < 600 and flat_distance(body(HOST, A).global_position, rebuilt) < 1.0:
		await step_ticks(1)
		ticks += 1
	print("    late join at %d ms: the host's copy of A moved 1 m after %d ticks" % [delay_ms, ticks])
	assert_le(
		float(ticks), 90.0,
		"after B joined, the host's copy of A moved 1 m (ticks until it did; 600 = never)",
	)
	var followed: bool = await until(
		func() -> bool: return flat_distance(body(B, A).global_position, seen_by_b) >= 1.0
	)
	assert_true(followed, "and the late joiner's copy of A walks with it")


# --- 3. A power in the hub ------------------------------------------------------

func test_a_clients_shield_runs_in_the_hub_and_is_drawn_on_all_three() -> void:
	if not await stand_up():
		return
	keys[A].tap_slot(SHIELD)
	var up: bool = await until(func() -> bool: return all_draw(A, SHIELD))
	assert_true(up, "A's shield is up on host, A and B: %s" % str(drawn(A)))
	var gone: bool = await until(func() -> bool: return all_draw(A, NONE))
	assert_true(gone, "and ended on host, A and B: %s" % str(drawn(A)))


# --- 4-6. The shove -------------------------------------------------------------

func test_a_clients_shove_launches_the_host_and_swings_once_on_every_machine() -> void:
	await _shove_the_host(0)


func test_a_clients_shove_launches_the_host_and_swings_once_on_every_machine_at_40_ms() -> void:
	await _shove_the_host(40)


func _shove_the_host(delay_ms: int) -> void:
	if not await stand_up(0.0, delay_ms):
		return
	var victim_at: Vector3 = await _stand_a_behind_the_host()
	var swings: Array = _count_a_swings()
	keys[A].tap(&"shove_pressed")
	var launched: bool = await until(
		func() -> bool: return flat_distance(body(HOST, HOST).global_position, victim_at) > 2.0
	)
	assert_true(launched, "the host's body was thrown by A's shove")
	await until(func() -> bool: return swings[B][0] > 0)
	await step_ticks(ECHO_TICKS)
	assert_eq_int(swings[HOST][0], 1, "the host's copy of A swung once")
	assert_eq_int(swings[A][0], 1, "A's own body swung once, not again on the host's word")
	assert_eq_int(swings[B][0], 1, "B's copy of A swung once")


func test_a_shove_that_misses_still_swings_on_every_machine() -> void:
	if not await stand_up():
		return
	var host_at: Vector3 = body(HOST, HOST).global_position
	var b_at: Vector3 = body(HOST, B).global_position
	var swings: Array = _count_a_swings()
	await step_ticks(20)
	keys[A].tap(&"shove_pressed")
	var seen: bool = await until(func() -> bool: return swings[B][0] > 0)
	assert_true(seen, "B's copy of A swung at nobody")
	await step_ticks(ECHO_TICKS)
	assert_eq_int(swings[B][0], 1, "B's copy of A swung once")
	assert_eq_int(swings[A][0], 1, "A's own body swung once")
	assert_eq_int(swings[HOST][0], 1, "the host's copy of A swung once")
	assert_le(flat_distance(body(HOST, HOST).global_position, host_at), 0.2, "the host was out of reach")
	assert_le(flat_distance(body(HOST, B).global_position, b_at), 0.2, "and so was B")


func test_a_shove_pressed_inside_a_blackout_still_lands() -> void:
	if not await stand_up(0.0, 1):
		return
	var victim_at: Vector3 = await _stand_a_behind_the_host()
	keys[A].tap(&"shove_pressed")
	await black_out(a_wire, 4)
	var launched: bool = await until(
		func() -> bool: return flat_distance(body(HOST, HOST).global_position, victim_at) > 2.0,
		3000,
	)
	assert_true(launched, "a shove pressed on four dropped intents still threw the host")


# --- 7-9. The power cat ---------------------------------------------------------

func test_a_thrown_power_cat_goes_off_and_throws_a_client() -> void:
	await _throw_the_power_cat(0)


func test_a_thrown_power_cat_goes_off_and_throws_a_client_at_40_ms() -> void:
	await _throw_the_power_cat(40)


func _throw_the_power_cat(delay_ms: int) -> void:
	if not await stand_up(0.0, delay_ms):
		return
	var live: CatGrenade = await hold_power_cat()
	if live == null:
		return
	var blast: Array[Vector3] = _watch_blast(live)
	var swings: Array = _count_a_swings()
	keys[A].tap(&"shove_pressed")
	var thrown: bool = await until(
		func() -> bool:
			return blast.is_empty() and live.carrier == null and live.linear_velocity.length() > 1.0
	)
	assert_true(thrown, "A's shove threw the cat: it left the hand and is moving")
	var let_go: bool = await until(func() -> bool: return pet_offer(A) == 0, 1000)
	assert_true(let_go, "A's machine stops offering the pet for a cat in the air")
	# B's own body walks up to the lit cat.
	await until(func() -> bool: return not blast.is_empty() or power(HOST, A).get_remaining() <= 0.5)
	if not blast.is_empty():
		fail("the cat went off before its fuse was nearly out")
		return
	var back: Vector3 = body(HOST, A).global_position - live.global_position
	back.y = 0.0
	var b_at: Vector3 = live.global_position + back.normalized() * 1.5
	b_at.y = body(HOST, A).global_position.y
	for machine: int in [HOST, B]:
		body(machine, B).global_position = b_at
		body(machine, B).velocity = Vector3.ZERO
	var went_off: bool = await until(func() -> bool: return not blast.is_empty(), 3000)
	if not assert_true(went_off, "the thrown cat went off within its fuse"):
		return
	assert_le(blast[0].distance_to(b_at), 3.0, "B stood within 3 m of the blast")
	var host_copy: bool = await until(
		func() -> bool: return flat_distance(body(HOST, B).global_position, b_at) >= 1.0
	)
	assert_true(host_copy, "the blast launched B's body on the host")
	var own: bool = await until(
		func() -> bool: return flat_distance(body(B, B).global_position, b_at) >= 1.0
	)
	assert_true(own, "and B's own machine was moved by it")
	var cleared: bool = await until(func() -> bool: return cats_drawn() == [0, 0, 0])
	assert_true(cleared, "no machine still draws the cat: %s" % str(cats_drawn()))
	var ended: bool = await until(func() -> bool: return all_draw(A, NONE))
	assert_true(ended, "the cat power ended on host, A and B: %s" % str(drawn(A)))
	_assert_swings(swings, 1, "the throw")


func test_a_power_cat_cooked_in_the_hand_pushes_its_holder_and_hurts_nobody() -> void:
	if not await stand_up():
		return
	var live: CatGrenade = await hold_power_cat()
	if live == null:
		return
	var a_at: Vector3 = body(HOST, A).global_position
	var forward: Vector3 = -body(HOST, A).global_transform.basis.z
	var blast: Array[Vector3] = _watch_blast(live)
	keys[A].tap(&"cook_pressed")
	var lit: bool = await until(func() -> bool: return not blast.is_empty() or power(HOST, A).state.cooking)
	assert_true(lit, "E lit the fuse on the host")
	var went_off: bool = await until(func() -> bool: return not blast.is_empty(), 5000)
	if not assert_true(went_off, "the cooked cat went off in the hand"):
		return
	assert_le(blast[0].distance_to(a_at + Vector3.UP * 1.2), 1.5, "it went off where A held it")
	var host_copy: bool = await until(
		func() -> bool: return flat_distance(body(HOST, A).global_position, a_at) >= 1.0
	)
	assert_true(host_copy, "the blast pushed A on the host")
	var own: bool = await until(
		func() -> bool: return flat_distance(body(A, A).global_position, a_at) >= 1.0
	)
	assert_true(own, "and on A's own machine")
	assert_lt((body(HOST, A).global_position - a_at).dot(forward), 0.0, "A was pushed back, away from the cat")
	await until(func() -> bool: return all_draw(A, NONE))
	for machine: int in 3:
		var roster: Array[MatchParticipant] = ctrl(machine).get_participants()
		assert_eq_int(roster.size(), 3, "machine %d still has three players" % machine)
		for who: MatchParticipant in roster:
			assert_true(who.is_running, "machine %d: seat %d is still in the world" % [machine, who.index])
			assert_eq_int(who.health, 1, "machine %d: seat %d lost no health" % [machine, who.index])
			assert_eq_int(who.lives, 1, "machine %d: seat %d lost no life" % [machine, who.index])


func test_only_the_holders_machine_is_offered_the_pet_while_a_client_holds_the_power_cat() -> void:
	if not await stand_up():
		return
	if await hold_power_cat() == null:
		return
	var offered: bool = await until(func() -> bool: return pet_offer(A) != 0)
	assert_true(offered, "A's machine offers the pet for the cat A holds")
	assert_eq_int(pet_offer(HOST), 0, "the host's machine does not")
	assert_eq_int(pet_offer(B), 0, "B's machine does not")
	assert_eq_string(str(cats_drawn()), str([1, 1, 1]), "every machine draws the one cat the host owns")


func test_only_the_host_is_offered_the_pet_while_the_host_holds_the_power_cat() -> void:
	if not await stand_up():
		return
	keys[HOST].tap_slot(CAT)
	var offered: bool = await until(func() -> bool: return pet_offer(HOST) != 0)
	assert_true(offered, "the host's machine offers the pet for the cat the host holds")
	await until(func() -> bool: return cats_drawn() == [1, 1, 1])
	await step_ticks(10)
	assert_eq_int(pet_offer(A), 0, "A's machine does not")
	assert_eq_int(pet_offer(B), 0, "B's machine does not")


## Where the host's cat [param live] is when its power goes off: one entry per blast.
func _watch_blast(live: CatGrenade) -> Array[Vector3]:
	var blast: Array[Vector3] = []
	power(HOST, A).ended.connect(func(_which: MatchRules.RunnerAbility, reason: StringName) -> void:
		if reason == &"spent" and is_instance_valid(live):
			blast.append(live.global_position))
	return blast


# --- 10-12. The hub cats --------------------------------------------------------

func test_a_client_lifting_a_hub_cat_holds_it_on_the_host_and_is_offered_the_pet() -> void:
	if not await stand_up():
		return
	var swings: Array = _count_a_swings()
	if not await lift_hub_cat(A):
		return
	var offered: bool = await until(func() -> bool: return holds_locally(A))
	assert_true(offered, "A's machine offers the pet for the hub cat A carries")
	assert_false(holds_locally(HOST), "the host's machine does not")
	assert_false(holds_locally(B), "B's machine does not")
	var carried: Vector3 = cat(HOST, HUB_CAT).global_position
	var follows: bool = await until(
		func() -> bool:
			return (
				cat(A, HUB_CAT).global_position.distance_to(carried) < 0.5
				and cat(B, HUB_CAT).global_position.distance_to(carried) < 0.5
			)
	)
	assert_true(follows, "A and B draw the cat in A's hands")
	await until(func() -> bool: return swings[B][0] > 0)
	await step_ticks(ECHO_TICKS)
	_assert_swings(swings, 1, "the lift")


func test_a_clients_thrown_hub_cat_goes_off_and_returns_on_every_machine() -> void:
	await _lift_and_throw_the_hub_cat(0)


func test_a_clients_thrown_hub_cat_goes_off_and_returns_on_every_machine_at_40_ms() -> void:
	await _lift_and_throw_the_hub_cat(40)


func _lift_and_throw_the_hub_cat(delay_ms: int) -> void:
	if not await stand_up(0.0, delay_ms):
		return
	var swings: Array = _count_a_swings()
	if not await lift_hub_cat(A):
		return
	await _throw_and_watch(A)
	_assert_swings(swings, 2, "the lift and the throw")


func test_a_hub_cat_that_returned_can_be_lifted_again() -> void:
	if not await stand_up():
		return
	if not await lift_hub_cat(A):
		return
	await _throw_and_watch(A)
	if not await lift_hub_cat(A):
		return
	var offered: bool = await until(func() -> bool: return holds_locally(A))
	assert_true(offered, "A's machine offers the pet for the cat it lifted a second time")
	var carried: Vector3 = cat(HOST, HUB_CAT).global_position
	var follows: bool = await until(
		func() -> bool:
			return (
				cat(A, HUB_CAT).visible and cat(B, HUB_CAT).visible
				and cat(A, HUB_CAT).global_position.distance_to(carried) < 0.5
				and cat(B, HUB_CAT).global_position.distance_to(carried) < 0.5
			)
	)
	assert_true(follows, "A and B draw the cat in A's hands again")


func test_the_host_lifting_and_throwing_a_hub_cat_is_seen_by_both_clients() -> void:
	if not await stand_up():
		return
	if not await lift_hub_cat(HOST):
		return
	var offered: bool = await until(func() -> bool: return holds_locally(HOST))
	assert_true(offered, "the host's machine offers the pet for the cat the host carries")
	await step_ticks(10)
	assert_false(holds_locally(A), "A's machine does not")
	assert_false(holds_locally(B), "B's machine does not")
	await _throw_and_watch(HOST)


# --- Steps ----------------------------------------------------------------------

## Every machine drew A's body swing [param times] times for [param what].
func _assert_swings(swings: Array, times: int, what: String) -> void:
	assert_eq_int(swings[HOST][0], times, "the host's copy of A swung for %s" % what)
	assert_eq_int(swings[A][0], times, "A's own body swung for %s" % what)
	assert_eq_int(swings[B][0], times, "B's copy of A swung for %s" % what)


## Stand A 1.5 m from the host's body, facing it. Returns where the host stands.
func _stand_a_behind_the_host() -> Vector3:
	var victim_at: Vector3 = body(HOST, HOST).global_position
	var toward: Vector3 = victim_at - body(HOST, A).global_position
	toward.y = 0.0
	toward = toward.normalized()
	var stood: bool = await stand(A, victim_at - toward * 1.5, yaw_towards(toward))
	assert_true(stood, "A stands behind the host, facing it, on the host and on A")
	return victim_at


## Tallies of A's body swinging, by machine.
func _count_a_swings() -> Array:
	return [count(body(HOST, A).shoved), count(body(A, A).shoved), count(body(B, A).shoved)]


## [param seat] shoves again: the cat flies on the host, goes off and hides at home on both
## clients, then is back on its spot on all three.
func _throw_and_watch(seat: int) -> void:
	var homes: Array[Vector3] = []
	for machine: int in 3:
		var home: Transform3D = cat(machine, HUB_CAT).get("_home")
		homes.append(home.origin)
	await step_ticks(10)
	keys[seat].tap(&"shove_pressed")
	var truth: HubCat = cat(HOST, HUB_CAT)
	var flying: bool = await until(
		func() -> bool:
			return not HubCat.is_carrying(body(HOST, seat)) and truth.linear_velocity.length() > 3.0,
		2000,
	)
	assert_true(flying, "the second shove threw the cat on the host")
	var hidden: bool = await until(
		func() -> bool: return not cat(A, HUB_CAT).visible and not cat(B, HUB_CAT).visible,
		3000,
	)
	assert_true(hidden, "the cat went off on A and on B: both hide it")
	assert_false(truth.visible, "and the host hides its own")
	for machine: int in 3:
		assert_le(
			cat(machine, HUB_CAT).global_position.distance_to(homes[machine]), 0.05,
			"machine %d holds the hidden cat at its home spot" % machine,
		)
	var back: bool = await until(
		func() -> bool:
			return truth.visible and cat(A, HUB_CAT).visible and cat(B, HUB_CAT).visible
	)
	assert_true(back, "the cat is drawn again on all three")
	await step_ticks(10)
	for machine: int in 3:
		assert_le(
			cat(machine, HUB_CAT).global_position.distance_to(homes[machine]), 0.05,
			"machine %d has the returned cat on its home spot" % machine,
		)
	assert_false(holds_locally(HOST) or holds_locally(A) or holds_locally(B), "nobody is offered the pet for a cat nobody holds")


func test_a_mirror_that_lost_the_carriers_body_finds_it_again() -> void:
	if not await stand_up():
		return
	if not await lift_hub_cat(A):
		return
	if not assert_true(await until(func() -> bool: return cat(B, HUB_CAT).get(&"_carrier") == body(B, A)), "B draws A carrying it"):
		return
	# B's copy of A's body is gone from under its cat (a rebuilt hub, a late registration): the seat is unchanged.
	cat(B, HUB_CAT).set(&"_carrier", null)
	var follows: bool = await until(
		func() -> bool:
			return cat(B, HUB_CAT).get(&"_carrier") == body(B, A)
	)
	assert_true(follows, "B carries the cat in its copy of A's hands again")
