extends TestCase

## Section 1's measured route is runnable at full speed.
##
## map_base.s1_route.json is the lap-order polyline through S1 -- [bearing_deg,
## r_metres] in rising bearing. A runner driven along it, facing the next
## waypoint every tick, must never end a tick inside a collider, must reach the
## last waypoint, and must do it in no more than PACE_SLACK x the straight-line
## time at ground speed. The plain lane at r 52 is the control: the same drive
## over rock nobody has sculpted.

const ROUTE_PATH: String = "res://tools/modelling/maps/bentham_ring/map_base.s1_route.json"

const DECK_Y: float = 23.0
const SPAWN_LIFT: float = 0.1

## Within this in plan, a waypoint is reached and the next one becomes the aim.
const REACH_RADIUS: float = 0.6

## Ground speed from the movement profile, and the allowance over the ideal
## time the route may cost: acceleration off the mark and any weaving live here.
const GROUND_SPEED: float = 11.0
const PACE_SLACK: float = 1.3

## Control lane: plain rock, same spacing as the placeholder route.
const CONTROL_RADIUS: float = 52.0
const CONTROL_START_DEG: float = 5.0
const CONTROL_END_DEG: float = 15.0
const CONTROL_STEP_DEG: float = 3.0

## Hard stop, well past any budget the assertions allow, so a body wedged in
## rock fails on its pace or its probe rather than hanging the suite.
const MAX_TICKS: int = 1200

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


func test_the_measured_s1_route_runs_clear_at_full_speed() -> void:
	var route: Array[Vector3] = _load_route()
	assert_gt(float(route.size()), 1.0, "%s holds a polyline of at least two waypoints" % ROUTE_PATH)
	if route.size() < 2:
		return
	await _assert_the_run(route, "s1 route")


func test_the_plain_lane_at_r_52_runs_clear_at_full_speed() -> void:
	await _assert_the_run(_arc_route(CONTROL_START_DEG, CONTROL_END_DEG, CONTROL_STEP_DEG, CONTROL_RADIUS), "plain lane")


## Drive [param route] and assert the three things a runnable route must be.
func _assert_the_run(route: Array[Vector3], label: String) -> void:
	var length: float = _plan_length(route)
	var budget_ticks: int = int(ceil(PACE_SLACK * length / GROUND_SPEED * SIM_HZ))
	var run: Dictionary = await _run_the_route(route)
	assert_true(String(run["inside"]).is_empty(), "%s: %s" % [label, run["inside"]])
	assert_true(bool(run["reached"]), "%s: reached the last of %d waypoints; %s" % [
		label, route.size(), run["where"]
	])
	assert_le(float(run["ticks"]), float(budget_ticks), "%s: %.2f s for %.1f m, budget %.2f s (%s)" % [
		label, float(run["ticks"]) / SIM_HZ, length, float(budget_ticks) / SIM_HZ, run["where"]
	])


## Run the polyline from its first waypoint, facing the next one every tick.
## Returns {reached, inside, ticks, where}.
func _run_the_route(route: Array[Vector3]) -> Dictionary:
	_body.global_position = route[0] + Vector3(0.0, SPAWN_LIFT, 0.0)
	_body.velocity = Vector3.ZERO
	_input.command.clear()
	await step_ticks(5)

	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var result: Dictionary = {"reached": false, "inside": "", "ticks": 0, "where": ""}
	var aim: int = 1
	for tick: int in MAX_TICKS:
		var here: Vector3 = _body.global_position
		result["ticks"] = tick
		result["where"] = _where(here, aim)
		var to_aim: Vector3 = route[aim] - here
		to_aim.y = 0.0
		if to_aim.length() <= REACH_RADIUS:
			aim += 1
			if aim >= route.size():
				result["reached"] = true
				return result
			to_aim = route[aim] - here
			to_aim.y = 0.0
		var wish: Vector3 = to_aim.normalized()
		_body.rotation.y = atan2(-wish.x, -wish.z)
		_input.command.move_direction = Vector2(0.0, 1.0)
		await step_ticks(1)
		_probe.transform = _body.collision.global_transform
		var hits: Array[Dictionary] = space.intersect_shape(_probe, 4)
		if not hits.is_empty():
			var collider: Node = hits[0].get("collider") as Node
			result["inside"] = "inside %s at tick %d, %s" % [
				collider.get_path() if collider != null else "?", tick, _where(_body.global_position, aim)
			]
			return result
	result["where"] = _where(_body.global_position, aim)
	return result


## The route as deck-height points, in the file's lap order.
func _load_route() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var text: String = FileAccess.get_file_as_string(ROUTE_PATH)
	if text.is_empty():
		return points
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return points
	for entry: Variant in (parsed as Dictionary).get("route", []):
		var waypoint: Array = entry as Array
		if waypoint == null or waypoint.size() < 2:
			continue
		points.append(_plan_point(float(waypoint[0]), float(waypoint[1])))
	return points


## A constant-radius arc from [param start_deg] to [param end_deg] inclusive,
## stepping [param step_deg]. The control's stand-in for a measured route.
func _arc_route(start_deg: float, end_deg: float, step_deg: float, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var bearing: float = start_deg
	while bearing < end_deg:
		points.append(_plan_point(bearing, radius))
		bearing += step_deg
	points.append(_plan_point(end_deg, radius))
	return points


func _plan_point(bearing_deg: float, radius: float) -> Vector3:
	var bearing: float = deg_to_rad(bearing_deg)
	return Vector3(cos(bearing) * radius, DECK_Y, sin(bearing) * radius)


## Total plan length of [param route], the distance the pace budget is drawn on.
func _plan_length(route: Array[Vector3]) -> float:
	var total: float = 0.0
	for index: int in range(1, route.size()):
		total += Vector2(route[index].x - route[index - 1].x, route[index].z - route[index - 1].z).length()
	return total


## Where the body stands, for a failure a reader can walk to.
func _where(here: Vector3, aim: int) -> String:
	return "bearing %.1f, r %.1f, y %.2f, aiming at waypoint %d" % [
		rad_to_deg(atan2(here.z, here.x)), Vector2(here.x, here.z).length(), here.y, aim
	]
