extends TestCase

## Map 1's pocket slab (bearing 63-72 deg, r 47.4-49.2) lets a runner past.
##
## Its placement was mirrored (a negative-determinant basis), which turns the
## trimesh collider inside out: a body pushed along it was slid into the wall
## and held there. Every run below must clear the pocket at full speed and
## never end a tick inside a collider.

const START_BEARING_DEG: float = 54.0
const END_BEARING_DEG: float = 74.0
## Radius, and whether the run holds it (the lane) or lets the wall deflect it.
const RUNS: Array[Array] = [[48.3, false], [49.0, false], [50.0, true], [52.0, true]]
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


func test_full_speed_past_the_pocket_slab_clears_it_and_never_ends_inside_a_collider() -> void:
	for run: Array in RUNS:
		var radius: float = run[0]
		var verdict: String = await _run_the_lane(radius, bool(run[1]))
		assert_true(verdict.is_empty(), "r %.1f: %s" % [radius, verdict])


## Run from START_BEARING_DEG past END_BEARING_DEG at [param radius], facing along
## the lane every tick. Returns "" or what went wrong first.
func _run_the_lane(radius: float, hold_radius: bool) -> String:
	var bearing: float = deg_to_rad(START_BEARING_DEG)
	_body.global_position = Vector3(cos(bearing) * radius, DECK_Y + 0.1, sin(bearing) * radius)
	_body.velocity = Vector3.ZERO
	_input.command.clear()
	await step_ticks(5)
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	for tick: int in MAX_TICKS:
		var here: Vector3 = _body.global_position
		var angle: float = atan2(here.z, here.x)
		if angle >= deg_to_rad(END_BEARING_DEG):
			return ""
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
			return "inside %s at tick %d, bearing %.1f" % [
				collider.get_path() if collider != null else "?", tick, rad_to_deg(angle)
			]
	var last: Vector3 = _body.global_position
	return "held at bearing %.1f, r %.1f; never passed bearing %.0f" % [
		rad_to_deg(atan2(last.z, last.x)), Vector2(last.x, last.z).length(), END_BEARING_DEG
	]
