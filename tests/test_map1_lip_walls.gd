extends TestCase

## Map 1's five lip walls: a wall of map_base.glb's own rock on the runner's
## right (the pit lip, r 46.9-48.2; 204 and 286 are thinner, 46.9-47.5) at each
## section boundary and across the start, ~8 m long and 3 m tall (the
## start's 22 deg and 4.6 m), no mouth.
##
## Two things each must be. Cover: a standing body on the lane directly
## behind it is hidden from the guard's eye at (0, 28.90, 0). A wall and not a
## gate: a runner at full speed along the lane passes it on the outer side,
## never held and never ending a tick inside a collider.

## Name, first and last bearing of the full-height run (LIP_WALLS less the
## taper), then where the run past it starts and ends: on plain lane, clear of
## the neighbours' own rock (S1's columns end at 61, S3's last pad plate at
## 199.8, the bars across the lane at 350).
const WALLS: Array[Array] = [
	["013", -6.0, 12.0, -4.0, 14.0],
	["066", 63.2, 69.8, 61.2, 71.8],
	["139", 135.7, 142.3, 133.7, 144.3],
	["204", 200.7, 207.3, 200.2, 209.3],
	["286", 282.7, 289.3, 280.7, 291.3],
]
const GUARD_EYE: Vector3 = Vector3(0.0, 28.90, 0.0)
const LANE_RADII: Array[float] = [50.2, 52.0, 53.8]
const BODY_POINTS: Array[float] = [0.4, 1.0, 1.65, 1.8]
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


func test_a_standing_body_on_the_lane_behind_each_wall_is_hidden_from_the_guard() -> void:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	for wall: Array in WALLS:
		var seen: int = 0
		var points: int = 0
		for step: int in 8:
			var bearing: float = deg_to_rad(lerpf(float(wall[1]), float(wall[2]), float(step) / 7.0))
			for radius: float in LANE_RADII:
				for z: float in BODY_POINTS:
					var point: Vector3 = Vector3(cos(bearing) * radius, DECK_Y + z, sin(bearing) * radius)
					var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
						GUARD_EYE, point, RingBake.STATIC_COLLIDER_MASK
					)
					query.exclude = [_body.get_rid()]
					points += 1
					if space.intersect_ray(query).is_empty():
						seen += 1
		assert_eq_int(seen, 0, "wall %s: every one of %d body points on the lane behind it is blocked" % [wall[0], points])


func test_a_runner_at_full_speed_passes_every_wall_on_the_outer_side() -> void:
	for wall: Array in WALLS:
		for radius: float in LANE_RADII:
			var run: Dictionary = await _run_the_lane(float(wall[3]), float(wall[4]), radius)
			assert_true(String(run["inside"]).is_empty(), "wall %s r %.1f: %s" % [wall[0], radius, run["inside"]])
			assert_true(bool(run["passed"]), "wall %s r %.1f: held at bearing %.1f, r %.1f" % [
				wall[0], radius, run["bearing"], run["radius"]
			])


## Run from [param start_deg] toward [param end_deg] holding [param radius], facing
## along the lane every tick. Returns {passed, inside, bearing, radius}.
func _run_the_lane(start_deg: float, end_deg: float, radius: float) -> Dictionary:
	var bearing: float = deg_to_rad(start_deg)
	_body.global_position = Vector3(cos(bearing) * radius, DECK_Y + 0.1, sin(bearing) * radius)
	_body.velocity = Vector3.ZERO
	_input.command.clear()
	await step_ticks(5)
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var result: Dictionary = {"passed": false, "inside": "", "bearing": 0.0, "radius": 0.0}
	var end_rad: float = deg_to_rad(end_deg)
	for tick: int in MAX_TICKS:
		var here: Vector3 = _body.global_position
		var angle: float = atan2(here.z, here.x)
		# Unwrap against the run's own end, so a wall that straddles 0 deg still measures.
		angle = end_rad + wrapf(angle - end_rad, -PI, PI)
		result["bearing"] = rad_to_deg(angle)
		result["radius"] = Vector2(here.x, here.z).length()
		if angle >= end_rad:
			result["passed"] = true
			return result
		var wish: Vector3 = Vector3(-sin(angle), 0.0, cos(angle))
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
