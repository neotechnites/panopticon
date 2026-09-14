extends SceneTree

## Does a named camera path ever fly into the map?
##
## [codeblock]
## godot --headless --path . --script res://tools/capture/verify_path.gd -- --shot=teaser_lap
## [/codeblock]
##
## Walks the path by arc length, and at every [constant STEP_METRES] grows a
## sphere at that point until it touches something. The smallest sphere that
## fits anywhere on the route is the clearance, and a route is flyable when that
## is at least [constant WANT_METRES]. Loads the ring alone, so the only things
## it can hit are the map and its fixtures -- no bodies, no camera, no match.

const SHOTS := preload("res://tools/capture/shot_paths.gd")
const RING_SCENE: String = "res://scenes/ring/bentham_ring.tscn"

const STEP_METRES: float = 0.25
const WANT_METRES: float = 0.5
## Radii the search brackets, and how finely it splits between them.
const PROBE_MIN: float = 0.05
const PROBE_MAX: float = 3.0
const PROBE_STEPS: int = 7
## Path time between raw samples, before they are resampled by distance.
const TIME_STEP: float = 0.002
## Frames given to the physics server before it is asked anything.
const SETTLE_FRAMES: int = 3

var _frames: int = 0
var _keys: Array = []


func _initialize() -> void:
	var options: Dictionary = BotHarness.parse_arguments({"shot": ""})
	var shot: Dictionary = SHOTS.get_shot(String(options.get("shot", "")))
	if shot.is_empty():
		printerr("Unknown --shot=%s; the shots are %s." % [
			options.get("shot", ""), ", ".join(SHOTS.names())
		])
		quit(2)
		return
	_keys = shot["keys"]
	var packed: PackedScene = load(RING_SCENE) as PackedScene
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames <= SETTLE_FRAMES:
		return false
	_report()
	quit(0)
	return true


func _report() -> void:
	var points: Array[Vector3] = _walk()
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var shape := SphereShape3D.new()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var worst: float = PROBE_MAX
	var worst_at: Vector3 = Vector3.ZERO
	var tight: int = 0
	for point: Vector3 in points:
		var clearance: float = _clearance(space, query, shape, point)
		if clearance < WANT_METRES:
			tight += 1
		if clearance < worst:
			worst = clearance
			worst_at = point
	print("path: %d samples every %.2f m" % [points.size(), STEP_METRES])
	print("min clearance %.2f m at %v; %d samples under %.2f m" % [
		worst, worst_at, tight, WANT_METRES
	])
	print("VERDICT %s" % ("clear" if tight == 0 else "CLIPS"))
	for point: Vector3 in points:
		var clearance: float = _clearance(space, query, shape, point)
		if clearance < WANT_METRES:
			print("  tight %5.1f deg  r %5.2f  h %5.2f  clear %.2f" % [
				fposmod(rad_to_deg(atan2(point.z, point.x)), 360.0),
				Vector2(point.x, point.z).length(),
				point.y - 23.0,
				clearance,
			])


## The largest sphere that fits at [param point], bracketed to PROBE_STEPS.
func _clearance(
	space: PhysicsDirectSpaceState3D,
	query: PhysicsShapeQueryParameters3D,
	shape: SphereShape3D,
	point: Vector3,
) -> float:
	query.transform = Transform3D(Basis.IDENTITY, point)
	var low: float = PROBE_MIN
	var high: float = PROBE_MAX
	shape.radius = high
	if space.intersect_shape(query, 1).is_empty():
		return high
	shape.radius = low
	if not space.intersect_shape(query, 1).is_empty():
		return 0.0
	for _step: int in PROBE_STEPS:
		var middle: float = (low + high) * 0.5
		shape.radius = middle
		if space.intersect_shape(query, 1).is_empty():
			low = middle
		else:
			high = middle
	return low


## The path resampled to a point every [constant STEP_METRES] of travel.
func _walk() -> Array[Vector3]:
	var first: float = float(_keys[0]["t"])
	var last: float = float(_keys[_keys.size() - 1]["t"])
	var points: Array[Vector3] = []
	var previous: Vector3 = SHOTS.sample(_keys, first)["pos"]
	points.append(previous)
	var carried: float = 0.0
	var time: float = first
	while time < last:
		time = minf(time + TIME_STEP, last)
		var here: Vector3 = SHOTS.sample(_keys, time)["pos"]
		carried += previous.distance_to(here)
		if carried >= STEP_METRES:
			points.append(here)
			carried = 0.0
		previous = here
	return points
