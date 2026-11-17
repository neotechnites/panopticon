class_name GuardPosts
extends RefCounted

## The places a map lets its guard stand (Marker3D in [constant GROUP]) and the one held. A post is
## scored by its lines of fire to where its known targets can be, as Halo's and Killzone's are.

const GROUP: StringName = &"guard_post"
## Seconds between scorings; each costs one ray per post per place scored.
const RESCORE_SECONDS: float = 0.25
## A line that stops this close to the point it was cast at still reaches it, metres.
const LINE_SLACK_METRES: float = 0.5
## Directions round each known point, at [member reach_metres], where its target may be instead.
const AROUND: int = 4
## A post must reach this many more of those places than the held one to be worth a walk.
const SWITCH_LINES: int = 2
## Inside this of its post the guard stands still; it eases off the stick inside EASE.
const REACHED_METRES: float = 0.25
const EASE_METRES: float = 1.0

var points: PackedVector3Array = PackedVector3Array()
## Index into [member points] of the post held, or -1 before the first choice.
var held: int = -1
## Where a target can stand: walkable mesh of the guard's level. Without it only the gaze is scored.
var bake: RingBake = null
## Eye above the feet at a post; chest above the feet of a target; what a round stops on.
var eye_height: float = 1.6
var aim_height: float = 0.9
var mask: int = 0xFFFFF
## How far from the gaze a target may have got, metres.
var reach_metres: float = 0.0

var _rescore_in: float = 0.0
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []
var _places: PackedVector3Array = PackedVector3Array()


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


## Take the post with lines to the most places its targets can be, round each of [param known]
## (the first is the gaze), keeping the held one unless another reaches clearly more.
func choose(body: PhysicsBody3D, known: PackedVector3Array, delta: float) -> void:
	if known.is_empty():
		return
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
	_places.clear()
	for point: Vector3 in known:
		_add_places(point)
	var gaze: Vector3 = known[0]
	var lift: Vector3 = Vector3.UP * eye_height
	var held_lines: int = _lines(space, points[held] + lift) if held >= 0 else -1
	var best: int = -1
	var best_lines: int = -1
	var best_cost: float = INF
	for index: int in points.size():
		if index == held:
			continue
		var lines: int = _lines(space, points[index] + lift)
		var cost: float = _flat_distance(body.global_position, points[index]) + points[index].distance_to(gaze)
		if lines > best_lines or (lines == best_lines and cost < best_cost):
			best = index
			best_lines = lines
			best_cost = cost
	if best >= 0 and (held < 0 or best_lines >= held_lines + SWITCH_LINES or (held_lines == 0 and best_lines > 0)):
		held = best


## The stick that walks [param body] to its post in a straight line, in the body's own frame.
func steer(body: Node3D) -> Vector2:
	if held < 0:
		return Vector2.ZERO
	var here: Vector3 = body.global_position
	var away: Vector2 = Vector2(points[held].x - here.x, points[held].z - here.z)
	var distance: float = away.length()
	if distance <= REACHED_METRES:
		return Vector2.ZERO
	var frame: Basis = body.global_transform.basis
	var heading: Vector3 = Vector3(away.x, 0.0, away.y) / distance
	return Vector2(heading.dot(frame.x), -heading.dot(frame.z)) * minf(distance / EASE_METRES, 1.0)


## [param point], and the chest of a body standing on walkable mesh [member reach_metres] round it.
func _add_places(point: Vector3) -> void:
	_places.append(point)
	if bake == null or reach_metres <= 0.0:
		return
	var feet: Vector3 = point - Vector3.UP * aim_height
	for index: int in AROUND:
		var angle: float = TAU * float(index) / float(AROUND)
		var place: Vector3 = feet + Vector3(cos(angle), 0.0, sin(angle)) * reach_metres
		var floor_height: float = bake.height_at(place)
		if not is_nan(floor_height):
			_places.append(Vector3(place.x, floor_height + aim_height, place.z))


## Of the places found, how many a round from [param eye] reaches.
func _lines(space: PhysicsDirectSpaceState3D, eye: Vector3) -> int:
	var count: int = 0
	for place: Vector3 in _places:
		if _has_line(space, eye, place):
			count += 1
	return count


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
