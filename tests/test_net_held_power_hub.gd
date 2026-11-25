extends "res://tests/support/net_hub_rig.gd"

## The held power is a player's (one or none): picked at a hub stand on the host, kept in the seat,
## and the same on every machine, a late joiner's included.

const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const NONE: int = MatchRules.RunnerAbility.NONE


## [param machine]'s hub stand for [param which].
func _stand_of(machine: int, which: int) -> PowerStand:
	for child: Node in hubs[machine].get_node("HubWorld/PowerStands").get_children():
		var stand: PowerStand = child as PowerStand
		if stand != null and int(stand.power) == which:
			return stand
	return null


## [param seat] walks up to the stand for [param which] and presses interact.
func _pick_at_stand(seat: int, which: int) -> bool:
	var stand: PowerStand = _stand_of(HOST, which)
	if not assert_not_null(stand, "the hub has a stand for power %d" % which):
		return false
	var out: Vector3 = Vector3(stand.global_position.x, 0.0, stand.global_position.z).normalized()
	var at: Vector3 = stand.global_position + out
	if not assert_true(await stand(seat, at, yaw_towards(-out)), "seat %d stands at the stand" % seat):
		return false
	keys[seat].tap(&"cook_pressed")
	return true


## True once every standing machine has [param seat] holding [param which].
func _everyone_has(seat: int, which: int, machines: int = 3) -> bool:
	for machine: int in machines:
		if hubs[machine] == null or body(machine, seat) == null or int(power(machine, seat).get_held()) != which:
			return false
	return true


func test_a_stand_gives_its_power_to_whoever_uses_it_and_to_nobody_else() -> void:
	if not await stand_up():
		return
	for seat: int in 3:
		assert_eq_int(int(power(HOST, seat).get_held()), NONE, "seat %d holds nothing before a pick" % seat)
	if not await _pick_at_stand(A, HOLOGRAM):
		return
	var picked: bool = await until(func() -> bool: return _everyone_has(A, HOLOGRAM))
	assert_true(picked, "A holds the hologram on every machine")
	assert_eq_int(sessions[HOST].lobby.get_seat(A).power, HOLOGRAM, "and the host's seat table keeps it")
	assert_true(_everyone_has(HOST, NONE) and _everyone_has(B, NONE), "nobody else's power moved")
	if not await _pick_at_stand(HOST, CAMO):
		return
	assert_true(await until(func() -> bool: return _everyone_has(HOST, CAMO)), "the host holds camo everywhere")
	assert_true(_everyone_has(A, HOLOGRAM), "and A still holds the hologram: one each, not one for all")
	# The empty stand takes it away: one or none.
	if not await _pick_at_stand(A, NONE):
		return
	assert_true(await until(func() -> bool: return _everyone_has(A, NONE)), "the empty stand leaves A holding nothing")


func test_a_pick_replaces_the_power_held_and_stops_the_one_running() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	hold(SHIELD, A)
	keys[A].tap(&"ability_pressed")
	if not assert_true(await until(func() -> bool: return int(power(HOST, A).get_active()) == SHIELD), "A's shield is up"):
		return
	if not await _pick_at_stand(A, CAMO):
		return
	assert_true(await until(func() -> bool: return _everyone_has(A, CAMO, 2)), "A holds camo now")
	assert_eq_int(int(power(HOST, A).get_active()), NONE, "the shield stopped with the pick")
	assert_eq_int(power(HOST, A).state.cooldown_ticks, 0, "and the new power is ready")


func test_a_late_joiner_sees_the_power_everyone_holds() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	hold(HOLOGRAM, A)
	hold(CAMO, HOST)
	# One process: the static pick the others' lobbies kept is not B's own; B joins holding none.
	sessions[B].lobby.local_power = NONE
	if not await join_late(B):
		return
	assert_true(await until(func() -> bool: return _everyone_has(A, HOLOGRAM) and _everyone_has(HOST, CAMO)),
			"the joiner has A holding the hologram and the host camo")
	assert_eq_int(int(power(B, B).get_held()), NONE, "and holds nothing itself")


func test_interact_away_from_every_stand_picks_nothing() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	keys[A].tap(&"cook_pressed")
	await step_ticks(30)
	assert_eq_int(sessions[HOST].lobby.get_seat(A).power, NONE, "the seat holds nothing")
	assert_true(_everyone_has(A, NONE, 2), "and nobody's copy of A does")


## The host rules a pick from where its own copy of the body stands, not from where the client says.
func test_a_client_beside_a_stand_only_on_its_own_screen_picks_nothing() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var stand: PowerStand = _stand_of(A, HOLOGRAM)
	var out: Vector3 = Vector3(stand.global_position.x, 0.0, stand.global_position.z).normalized()
	body(A, A).global_position = stand.global_position + out
	keys[A].tap(&"cook_pressed")
	await step_ticks(30)
	assert_gt(flat_distance(body(HOST, A).global_position, stand.global_position), PowerStand.REACH,
			"the host's copy of A never stood at the stand")
	assert_eq_int(sessions[HOST].lobby.get_seat(A).power, NONE, "so A's seat holds nothing")


func test_a_players_own_pick_comes_with_them_into_a_session() -> void:
	RunnerPower.solo_held = CAMO as MatchRules.RunnerAbility
	if not await stand_up(0.0, 0, 2):
		return
	assert_true(await until(func() -> bool: return _everyone_has(A, CAMO, 2) and _everyone_has(HOST, CAMO, 2)),
			"the host's and the joining client's own picks are their seats'")
