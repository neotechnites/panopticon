extends "res://tests/support/net_hub_rig.gd"

## A peer joins or leaves the hub while a cat is in somebody's hands: every machine rebuilds
## its bodies, and no machine is left with a cat the host does not have.

## Ticks a joiner is connected before its own hub stands: a scene takes time to load.
const LOAD_TICKS: int = 240
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const NONE: int = MatchRules.RunnerAbility.NONE


func test_a_joiner_arriving_while_a_client_holds_the_power_cat_leaves_no_cat_behind() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if await hold_power_cat([0, 1, 0]) == null:
		return
	if not await join_late(B, LOAD_TICKS):
		return
	var cleared: bool = await until(
		func() -> bool: return grenade(A) == null and cats_drawn() == [0, 0, 0]
	)
	assert_true(cleared, "the rebuilt hub has no power cat on any machine: %s" % str(cats_drawn()))
	var ended: bool = await until(func() -> bool: return all_draw(A, NONE))
	assert_true(ended, "and no machine runs the cat power for A: %s" % str(drawn(A)))
	assert_eq_int(pet_offer(A), 0, "A's machine offers no pet for a cat that is gone")
	keys[A].tap_slot(CAT)
	var again: bool = await until(
		func() -> bool: return grenade(A) != null and cats_drawn() == [0, 1, 1]
	)
	assert_true(again, "A's next 5 holds a new cat, drawn on A and on the joiner: %s" % str(cats_drawn()))


func test_a_joiner_arriving_while_a_client_carries_a_hub_cat_sees_it_where_the_host_has_it() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await lift_hub_cat(A):
		return
	if not await join_late(B, LOAD_TICKS):
		return
	await _assert_the_hub_cat_is_down([A, B])


func test_a_shove_landing_while_a_joiner_loads_is_seen_by_those_in_the_hub() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await connect_late(B):
		return
	# The host and A were stood back on their spawns for the new roster; B has no hub yet.
	var rebuilt: bool = await until(
		func() -> bool:
			return ctrl(HOST).get_participants().size() == 3 and ctrl(A).get_participants().size() == 3
	)
	if not assert_true(rebuilt, "the host and A rebuilt their hubs for three"):
		return
	await until(func() -> bool: return net(A).get_local_link() != null and net(A).get_local_link().is_predicting())
	var victim_at: Vector3 = body(HOST, HOST).global_position
	var toward: Vector3 = victim_at - body(HOST, A).global_position
	toward.y = 0.0
	toward = toward.normalized()
	assert_true(await stand(A, victim_at - toward * 1.5, yaw_towards(toward)), "A stands behind the host")
	var seen: Array[int] = count(body(A, HOST).shoved)
	var swung: Array[int] = count(body(A, A).shoved)
	keys[A].tap(&"shove_pressed")
	var launched: bool = await until(
		func() -> bool: return flat_distance(body(HOST, HOST).global_position, victim_at) > 2.0
	)
	assert_true(launched, "A's shove threw the host while B was loading")
	await step_ticks(30)
	assert_eq_int(swung[0], 1, "A's own body swung once")
	assert_eq_int(seen[0], 0, "the host, who was thrown, did not swing on A's machine")
	if not await load_hub(B):
		return
	for seat: int in 3:
		assert_le(
			body(B, seat).global_position.distance_to(body(HOST, seat).global_position), 1.0,
			"the joiner draws seat %d where the host has it" % seat,
		)


func test_a_client_leaving_with_the_power_cat_in_hand_takes_it_along() -> void:
	if not await stand_up():
		return
	if await hold_power_cat() == null:
		return
	leave(A)
	var rebuilt: bool = await until(
		func() -> bool:
			return ctrl(HOST).get_participants().size() == 2 and ctrl(B).get_participants().size() == 2
	)
	if not assert_true(rebuilt, "the host and B rebuilt their hubs for two"):
		return
	var cleared: bool = await until(
		func() -> bool:
			var shown: Dictionary = relay(B).get("_shown")
			return shown.is_empty() and _live_grenades() == 0
	)
	assert_true(cleared, "the leaver's cat is gone from the host and from B's screen")
	keys[B].tap_slot(SHIELD)
	var up: bool = await until(
		func() -> bool:
			return int(power(HOST, B).get_active()) == SHIELD and int(power(B, B).get_shown()) == SHIELD
	)
	assert_true(up, "and B's powers still run on the host")


func test_a_client_leaving_with_a_hub_cat_in_hand_puts_it_down_for_the_others() -> void:
	if not await stand_up():
		return
	if not await lift_hub_cat(A):
		return
	leave(A)
	var rebuilt: bool = await until(
		func() -> bool:
			return ctrl(HOST).get_participants().size() == 2 and ctrl(B).get_participants().size() == 2
	)
	if not assert_true(rebuilt, "the host and B rebuilt their hubs for two"):
		return
	await _assert_the_hub_cat_is_down([B])
	if not await lift_hub_cat(B):
		return
	var offered: bool = await until(func() -> bool: return holds_locally(B))
	assert_true(offered, "B can lift the cat the leaver dropped, and is offered the pet")


## The carried hub cat was put down on the host, and [param clients] draw it where it lies.
func _assert_the_hub_cat_is_down(clients: Array[int]) -> void:
	var truth: HubCat = cat(HOST, HUB_CAT)
	var down: bool = await until(
		func() -> bool:
			return truth.get("_carrier") == null and int(truth.get("_state")) == HubCat.State.REST
	)
	assert_true(down, "the host's cat is in nobody's hands and at rest")
	await step_ticks(30)
	assert_true(truth.visible, "the host draws it")
	assert_false(holds_locally(HOST), "the host's machine offers no pet for it")
	for machine: int in clients:
		assert_le(
			cat(machine, HUB_CAT).global_position.distance_to(truth.global_position), 0.5,
			"machine %d draws the cat where the host has it" % machine,
		)
		assert_true(cat(machine, HUB_CAT).visible, "machine %d draws it at all" % machine)
		assert_false(holds_locally(machine), "machine %d offers no pet for it" % machine)


## Power cats alive in the host's hub.
func _live_grenades() -> int:
	var alive: int = 0
	for node: Node in hubs[HOST].find_children("*", "RigidBody3D", true, false):
		if node is CatGrenade and not node.is_queued_for_deletion():
			alive += 1
	return alive
