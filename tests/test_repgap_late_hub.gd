extends "res://tests/support/net_hub_rig.gd"

## A joiner whose hub stands while a power runs in it draws that power as those already there do.

const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const NONE: int = MatchRules.RunnerAbility.NONE

## The rules a test lengthened a power on, and the length they shipped with.
var _lengthened: MatchRules = null
var _shipped_seconds: float = 0.0


func after_each() -> void:
	if _lengthened != null:
		_lengthened.ability_duration_seconds = _shipped_seconds
		_lengthened = null
	super()


## What [param machine] has standing in its hub for [param which] on A's body.
func _draws(machine: int, which: int) -> bool:
	var mine: RunnerPower = power(machine, A)
	match which:
		SHIELD:
			return mine.get_shield() != null
		HOLOGRAM:
			return mine.get_decoy() != null
		ARMOR:
			return body(machine, A).get_node_or_null("ArmorShell") != null
		CAMO:
			var mesh: MeshInstance3D = RunnerPower._avatar_mesh(body(machine, A))
			var worn: BaseMaterial3D = mesh.material_override as BaseMaterial3D if mesh != null else null
			return worn != null and worn.albedo_color.is_equal_approx(RunnerPower.CAMO_COLOR)
	return false


## B is seated and still loading; A presses [param which]; B's hub stands under it.
func _a_joiner_draws(which: int) -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await connect_late(B):
		return
	# B's seat rebuilt every body: A predicts its own again before it presses.
	if not await until(func() -> bool:
		return net(A).get_local_link() != null and net(A).get_local_link().is_predicting()):
		fail("A's own body was never placed after the rebuild")
		return
	_lengthened = ctrl(HOST).get_rules()
	_shipped_seconds = _lengthened.ability_duration_seconds
	_lengthened.ability_duration_seconds = 600.0
	await step_ticks(30)
	keys[A].held.ability_held = which == ARMOR
	keys[A].tap_slot(which)
	var up: bool = await until(func() -> bool:
		return int(power(HOST, A).get_active()) == which and _draws(HOST, which) and _draws(A, which))
	if not assert_true(up, "A's power runs on the host and is drawn on A"):
		return
	await step_ticks(30)
	if not await load_hub(B):
		return
	var seen: bool = await until(func() -> bool:
		return int(power(B, A).get_shown()) == which and _draws(B, which))
	assert_eq_int(int(power(HOST, A).get_active()), which, "the power is still running on the host")
	assert_eq_int(int(power(B, A).get_shown()), which, "the joiner shows A's power running")
	assert_true(seen, "and draws what it puts in the hub")
	if seen and which == SHIELD:
		var off: float = power(B, A).get_shield().global_position.distance_to(power(HOST, A).get_shield().global_position)
		assert_lt(off, 0.05, "the joiner's shield stands where the host's does")
	keys[A].held.ability_held = false
	power(HOST, A).cancel()
	var over: bool = await until(func() -> bool:
		for machine: int in 3:
			if int(power(machine, A).get_shown()) != NONE or _draws(machine, which):
				return false
		return true)
	assert_true(over, "every machine let go of it when the host's ended: %s" % str(drawn(A)))


func test_a_joiner_whose_hub_stands_under_a_shield_draws_it() -> void:
	await _a_joiner_draws(SHIELD)


func test_a_joiner_whose_hub_stands_under_a_hologram_draws_it() -> void:
	await _a_joiner_draws(HOLOGRAM)


func test_a_joiner_whose_hub_stands_under_an_armor_lock_draws_it() -> void:
	await _a_joiner_draws(ARMOR)


func test_a_joiner_whose_hub_stands_under_camo_draws_it() -> void:
	await _a_joiner_draws(CAMO)


## The power cat is drawn by the relay beside the session, which a loading machine already has.
func test_a_joiner_whose_hub_stands_while_a_power_cat_is_held_draws_it() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await connect_late(B):
		return
	if not await until(func() -> bool:
		return net(A).get_local_link() != null and net(A).get_local_link().is_predicting()):
		fail("A's own body was never placed after the rebuild")
		return
	await step_ticks(30)
	keys[A].tap_slot(CAT_POWER)
	if not await until(func() -> bool: return grenade(A) != null):
		fail("A's 5 put no cat in the hands of the host's copy of A")
		return
	if not await load_hub(B):
		return
	await step_ticks(20)
	assert_not_null(grenade(A), "the cat is still in A's hands on the host")
	assert_eq_int(int(power(B, A).get_shown()), CAT_POWER, "the joiner shows A's cat power running")
	var shown: Dictionary = relay(B).get("_shown")
	var drawn_cats: int = 0
	for mesh: Variant in shown.values():
		if is_instance_valid(mesh) and (mesh as Node3D).is_inside_tree():
			drawn_cats += 1
			var off: float = (mesh as Node3D).global_position.distance_to(grenade(A).global_position)
			assert_lt(off, 1.0, "the joiner draws the cat where the host has it")
	assert_eq_int(drawn_cats, 1, "the joiner draws the one cat")
	assert_eq_int(pet_offer(B), 0, "and is not offered the pet for a cat it does not hold")
