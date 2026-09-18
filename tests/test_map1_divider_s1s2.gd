extends TestCase

## Map 1's S1|S2 divider (bearing 66.5, r 46.8-58.3) lets a runner through its
## mouth, and nowhere else.
##
## The wall is map_base.glb's own rock: one mouth cut through at the lane
## (r 50.2-53.8, 3.6 m wide, 3.7 m high) and a spur gripping the pit lip. It
## replaced the pocket slab this test used to run past (a mirrored placement
## whose inside-out trimesh held a body in the wall). Every run through the
## mouth must clear it at full speed and never end a tick inside a collider;
## a run along the inner deck must be stopped by the spur, short of the wall's
## own plane, and never end inside it either.

const START_BEARING_DEG: float = 60.0
const END_BEARING_DEG: float = 74.0
const WALL_BEARING_DEG: float = 66.5
## Radii inside the mouth; every one of these runs holds its radius.
const MOUTH_RADII: Array[float] = [50.8, 52.0, 53.2]
## The inner deck, under the spur: the run is let drift so the rock can deflect it.
const SPUR_RADIUS: float = 48.3
const DECK_Y: float = 23.0
const MAX_TICKS: int = 600

var _arena: Node3D
var _body: PlayerController
var _input: BotIntentSource
var _probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()


func before_each() -> void:
	_arena = TestFixtures.make_arena()
	add_child(_arena)
	_body = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	add_child(_body)
	_input = TestFixtures.bot_input_of(_body)
	await step_ticks(3)
	# Slightly inside the body's own capsule, so resting on the floor is not a hit.
	var capsule: CapsuleShape3D = (_body.collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius -= 0.05
	capsule.height -= 0.1
	_probe.shape = capsule
	_probe.collision_mask = _body.collision_mask
	_probe.exclude = [_body.get_rid()]


func test_full_speed_through_the_mouth_clears_it_and_never_ends_inside_a_collider() -> void:
	for radius: float in MOUTH_RADII:
		var run: Dictionary = await _run_the_lane(radius, true)
		assert_true(String(run["inside"]).is_empty(), "r %.1f: %s" % [radius, run["inside"]])
		assert_true(bool(run["passed"]), "r %.1f: held at bearing %.1f, r %.1f; never passed bearing %.0f" % [
			radius, run["bearing"], run["radius"], END_BEARING_DEG
		])


func test_the_spur_stops_a_run_along_the_inner_deck_short_of_the_wall() -> void:
	var run: Dictionary = await _run_the_lane(SPUR_RADIUS, false)
	assert_true(String(run["inside"]).is_empty(), "r %.1f: %s" % [SPUR_RADIUS, run["inside"]])
	assert_false(bool(run["passed"]), "the spur is a wall: the run never reaches bearing %.0f" % END_BEARING_DEG)
	assert_lt(float(run["bearing"]), WALL_BEARING_DEG, "and it is held on the near side of the wall's plane")
	assert_gt(float(run["bearing"]), START_BEARING_DEG + 1.0, "having run, not stood still")


## Run from START_BEARING_DEG toward END_BEARING_DEG at [param radius], facing along
## the lane every tick. Returns {passed, inside, bearing, radius}: whether the run got
## past the end bearing, what collider it ended a tick inside (or ""), and where it
## finished.
func _run_the_lane(radius: float, hold_radius: bool) -> Dictionary:
	var bearing: float = deg_to_rad(START_BEARING_DEG)
	_body.global_position = Vector3(cos(bearing) * radius, DECK_Y + 0.1, sin(bearing) * radius)
	_body.velocity = Vector3.ZERO
	_input.command.clear()
	await step_ticks(5)
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var result: Dictionary = {"passed": false, "inside": "", "bearing": 0.0, "radius": 0.0}
	for tick: int in MAX_TICKS:
		var here: Vector3 = _body.global_position
		var angle: float = atan2(here.z, here.x)
		result["bearing"] = rad_to_deg(angle)
		result["radius"] = Vector2(here.x, here.z).length()
		if angle >= deg_to_rad(END_BEARING_DEG):
			result["passed"] = true
			return result
		var wish: Vector3 = Vector3(-sin(angle), 0.0, cos(angle))
		if hold_radius:
			var drift: float = Vector2(here.x, here.z).length() - radius
			wish = (wish - Vector3(cos(angle), 0.0, sin(angle)) * clampf(drift, -0.3, 0.3)).normalized()
		_body.rotation.y = atan2(-wish.x, -wish.z)
		_input.command.move_direction = Vector2(0.0, 1.0)
		await step_ticks(1)
		_probe.transform = _body.collision.global_transform
		var hits: Array[Dictionary] = space.intersect_shape(_probe, 4)
		if not hits.is_empty():
			var collider: Node = hits[0].get("collider") as Node
			result["inside"] = "inside %s at tick %d, bearing %.1f" % [
				collider.get_path() if collider != null else "?", tick, rad_to_deg(angle)
			]
			return result
	return result
