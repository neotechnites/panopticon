class_name GuardPosts
extends RefCounted

## The places a map lets its guard stand (Marker3D in [constant GROUP]) and the one held.
## A post is scored by its lines of fire across what the guard is looking at, as Killzone's are.

const GROUP: StringName = &"guard_post"
## Seconds between scorings; each costs one ray per post.
const RESCORE_SECONDS: float = 0.25
## A line that stops this close to the point it was cast at still reaches it, metres.
const LINE_SLACK_METRES: float = 0.5
## Where lines are cast: the gaze, and across the view aimed at it, as fractions of the half-view.
## A post must see [constant SWITCH_LINES] more of them to be worth a walk.
const SPREAD: Array[float] = [0.0, -0.5, 0.5, -1.0, 1.0]
const SWITCH_LINES: int = 2
## Inside this of its post the guard stands still, and counts as posted.
const REACHED_METRES: float = 0.25
## It eases off the stick inside this of its post; pushed further off, it is no longer posted.
const EASE_METRES: float = 1.0

var points: PackedVector3Array = PackedVector3Array()
## Index into [member points] of the post held, or -1 before the first choice.
var held: int = -1

var _posted: bool = false
var _rescore_in: float = 0.0
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []
var _spread: PackedVector3Array = PackedVector3Array()


func _init(at: PackedVector3Array = PackedVector3Array()) -> void:
	points = at
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true


## Every post under [param scope], the level root a guard plays in, as world positions.
static func read(scope: Node) -> PackedVector3Array:
	var found: PackedVector3Array = PackedVector3Array()
	if scope == null or not scope.is_inside_tree():
		return found
	for node: Node in scope.get_tree().get_nodes_in_group(GROUP):
		var marker: Marker3D = node as Marker3D
		if marker != null and scope.is_ancestor_of(marker):
			found.append(marker.global_position)
	return found


func is_empty() -> bool:
	return points.is_empty()


## True unless the guard is on its way to a post: a sniper does not fire on the move.
func is_posted() -> bool:
	return points.is_empty() or held < 0 or _posted


## Take the post whose view of [param gaze], [param half_view] radians either side, is most open, keeping
## the held one unless another sees clearly more; ties go to the shortest walk plus sight.
func choose(body: PhysicsBody3D, eye_height: float, half_view: float, gaze: Vector3, mask: int, delta: float) -> void:
	if points.is_empty():
		return
	_rescore_in -= delta
	if held >= 0 and _rescore_in > 0.0:
		return
	_rescore_in = RESCORE_SECONDS
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if space == null:
		return
	_ray.collision_mask = mask
	if _exclude.is_empty() or _exclude[0] != body.get_rid():
		_exclude = [body.get_rid()]
		_ray.exclude = _exclude
	var sight: Vector3 = gaze - body.global_position
	var across: Vector3 = Vector3(-sight.z, 0.0, sight.x).normalized() * Vector2(sight.x, sight.z).length()
	_spread.clear()
	for fraction: float in SPREAD:
		_spread.append(across * tan(half_view * fraction))
	var lift: Vector3 = Vector3.UP * eye_height
	var held_lines: int = _lines(space, points[held] + lift, gaze) if held >= 0 else -1
	var best: int = -1
	var best_lines: int = -1
	var best_cost: float = INF
	for index: int in points.size():
		if index == held:
			continue
		var lines: int = _lines(space, points[index] + lift, gaze)
		var cost: float = _flat_distance(body.global_position, points[index]) + points[index].distance_to(gaze)
		if lines > best_lines or (lines == best_lines and cost < best_cost):
			best = index
			best_lines = lines
			best_cost = cost
	if best >= 0 and (held < 0 or best_lines >= held_lines + SWITCH_LINES or (held_lines == 0 and best_lines > 0)):
		held = best
		_posted = false


## Of the points across the view at [param gaze], how many a round from [param eye] reaches.
func _lines(space: PhysicsDirectSpaceState3D, eye: Vector3, gaze: Vector3) -> int:
	var count: int = 0
	for offset: Vector3 in _spread:
		if _has_line(space, eye, gaze + offset):
			count += 1
	return count


## The stick that walks [param body] to its post in a straight line, in the body's own frame.
func steer(body: Node3D) -> Vector2:
	if held < 0:
		return Vector2.ZERO
	var here: Vector3 = body.global_position
	var away: Vector2 = Vector2(points[held].x - here.x, points[held].z - here.z)
	var distance: float = away.length()
	if distance <= REACHED_METRES:
		_posted = true
		return Vector2.ZERO
	if distance > EASE_METRES:
		_posted = false
	var frame: Basis = body.global_transform.basis
	var heading: Vector3 = Vector3(away.x, 0.0, away.y) / distance
	return Vector2(heading.dot(frame.x), -heading.dot(frame.z)) * minf(distance / EASE_METRES, 1.0)


## A round from [param eye] towards [param point] meets nothing, a body, or something at the point.
func _has_line(space: PhysicsDirectSpaceState3D, eye: Vector3, point: Vector3) -> bool:
	_ray.from = eye
	_ray.to = point
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty() or hit.get("collider", null) is PlayerController:
		return true
	return (hit["position"] as Vector3).distance_to(point) <= LINE_SLACK_METRES


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
