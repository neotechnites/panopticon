extends TestCase

## A shoved runner flops: limp, pelvis pinned to the capsule, up again once down. Looks only.

const DeathRagdoll: GDScript = preload("res://scripts/player/death_ragdoll.gd")
## The drawn pelvis and chest stay this close to the capsule's centre line, metres.
const PINNED_METRES: float = 0.3
const THROW: Vector3 = Vector3(16.0, 7.0, 0.0)

var _floor: StaticBody3D
var _body: PlayerController
var _avatar: PrisonerAvatar
var _ragdoll: Node


func before_each() -> void:
	_floor = TestFixtures.make_floor(0.0)
	add_child(_floor)
	_body = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	add_child(_body)
	_body.global_position = Vector3(0.0, 0.05, 0.0)
	await step_ticks(20)
	_avatar = _body.get_node(^"Avatar") as PrisonerAvatar
	_ragdoll = _avatar.get_node(^"Ragdoll")


func after_each() -> void:
	_body.queue_free()
	_floor.queue_free()


func _shove() -> void:
	_body.launch(THROW, 1.4)
	PrisonerAvatar.shove_landed(_body.global_position)


## Distance from a point to the capsule's centre line (0.4 to 1.4 m over the feet).
func _off_capsule(point: Vector3) -> float:
	var feet: Vector3 = _body.global_position
	var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(point, feet + Vector3.UP * 0.4, feet + Vector3.UP * 1.4)
	return point.distance_to(nearest)


func test_a_shove_flops_the_body_pinned_to_its_capsule_and_it_gets_up() -> void:
	_shove()
	var seen: bool = false
	var worst: float = 0.0
	var limbs: float = 0.0
	for _i: int in 240:
		await step_ticks(1)
		if not _ragdoll.is_flopping():
			if seen:
				break
			continue
		seen = true
		var parts: PackedVector3Array = _ragdoll.part_positions()
		worst = maxf(worst, maxf(_off_capsule(parts[0]), _off_capsule(parts[1])))
		for point: Vector3 in parts:
			limbs = maxf(limbs, _off_capsule(point))
	print("shove flop: pelvis/chest off the capsule line at most %.3f m, any part %.3f m" % [worst, limbs])
	assert_true(seen, "the shoved body went limp")
	assert_lt(worst, PINNED_METRES, "the drawn torso stays with the capsule")
	assert_lt(limbs, 1.5, "and no limb flies off it")
	assert_false(_ragdoll.is_flopping(), "and he is back on the clip within four seconds")
	assert_false(_ragdoll.is_active(), "with no corpse left behind")


func test_a_kill_mid_flop_hands_over_to_the_corpse() -> void:
	_shove()
	await step_ticks(20)
	assert_true(_ragdoll.is_flopping(), "limp in the air")
	_ragdoll.start(_body.velocity, Vector3.ZERO, Vector3.ZERO)
	assert_true(_ragdoll.is_active(), "the corpse takes the limp body")
	assert_false(_ragdoll.is_flopping(), "and the flop is over without getting up")
	_ragdoll.stop()


func test_off_leaves_the_reel() -> void:
	_ragdoll.flop_enabled = false
	_shove()
	await step_ticks(20)
	assert_false(_avatar.is_flopping(), "a flop that is off never starts")
