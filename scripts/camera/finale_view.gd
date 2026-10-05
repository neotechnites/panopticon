class_name FinaleView
extends Node3D
## The finale shove's cinematic: on the hit, a cut to a camera outside the tower, side-on
## to the throw, that pans and zooms to keep the thrown guard framed until the next round.

## The match to listen to. Without one this node does nothing.
@export var controller: MatchController
## This node's own camera. Never the player's.
@export var camera: Camera3D
## How fast the lens pans and zooms onto the thrown body: higher is tighter.
@export_range(1.0, 40.0, 0.5) var follow_rate: float = 30.0
## Metres off the arc, side-on, the camera stands; tried nearest first.
@export var side_distances: PackedFloat32Array = PackedFloat32Array([14.0, 20.0, 9.0])
## Metres above the arc and back toward the tower the side-on camera sits.
@export_range(0.0, 20.0, 0.1) var side_height: float = 2.0
@export_range(0.0, 20.0, 0.1) var side_back: float = 4.0
## The fallback when every side-on spot is blocked: this high over the arc.
@export_range(2.0, 60.0, 0.5) var wide_height: float = 14.0
## Share of the frame's height the guard is kept at, and the lens limits that may take.
@export_range(0.05, 0.9, 0.01) var subject_share: float = 0.3
@export_range(10.0, 120.0, 1.0) var min_fov: float = 12.0
@export_range(10.0, 120.0, 1.0) var max_fov: float = 70.0
## Where along the predicted arc (0 the hit, 1 the end of the beat) the camera is set against.
@export_range(0.0, 1.0, 0.01) var anchor_share: float = 0.4
## Metres a body is tall, for the zoom.
const SUBJECT_METRES: float = 1.9
## Points the predicted arc is sampled at.
const ARC_SAMPLES: int = 8
## Metres the camera keeps off any surface, checked along each sight line.
const CLEARANCE_METRES: float = 0.6
## The tower's room is measured from its collider this far below and above the guard's spawn.
const ROOM_BELOW: float = 2.0
const ROOM_ABOVE: float = 9.0
## Points each sight line is sampled at against the tower's room.
const SIGHT_SAMPLES: int = 24

var _avatar: PrisonerAvatar = null
var _guard: PlayerController = null
## The camera that was current when the shot began, given the view back after.
var _previous: Camera3D = null
var _remaining: float = 0.0
var _gravity: float = 9.8
var _arc: PackedVector3Array = PackedVector3Array()
## The first arc point clear of the tower: the camera need not see him inside it.
var _clear_index: int = 1
## The tower's room as a solid drum: its axis point at the spawn and its radius, measured once per tower.
var _room_centre: Vector3 = Vector3.ZERO
var _room_radius: float = 0.0
var _room_of: int = 0


func _ready() -> void:
	set_process(false)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if controller == null or camera == null:
		return
	camera.current = false
	controller.kill_beat_started.connect(_on_guard_thrown)
	controller.round_started.connect(stand_down)
	controller.match_started.connect(func(_count: int) -> void: stand_down())


## True while the shot holds the view.
func is_active() -> bool:
	return _remaining > 0.0


## The point the shot is following, world space.
func get_focus_point() -> Vector3:
	if _avatar != null and is_instance_valid(_avatar):
		return _avatar.drawn_centre()
	if _guard != null and is_instance_valid(_guard):
		return _guard.global_position + Vector3.UP
	return camera.global_position - camera.global_basis.z


## The arc the guard was predicted to fly, cut where it meets the map. For tests.
func get_predicted_arc() -> PackedVector3Array:
	return _arc


func _on_guard_thrown(guard: MatchParticipant, seconds: float, throw: Vector3) -> void:
	if guard == null or guard.body == null or seconds <= 0.0:
		return
	_guard = guard.body
	_avatar = PrisonerAvatar.of(guard.body)
	_previous = get_viewport().get_camera_3d()
	var focus: Vector3 = get_focus_point()
	_measure_room()
	_arc = _predict_arc(focus, throw, seconds)
	camera.global_position = _place(throw)
	_aim(focus, 1.0, 1.0)
	# Ended by the next round; the clock is only a backstop for a lost round start.
	_remaining = seconds + 1.0
	camera.current = true
	set_process(true)


func _process(delta: float) -> void:
	tick(delta)


## Pan and zoom onto the thrown body for one frame. Public so a test may step it.
func tick(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		stand_down()
		return
	_aim(get_focus_point(), 1.0 - exp(-follow_rate * delta), delta)


## Give the view back to the camera that had it. Idempotent.
func stand_down() -> void:
	_remaining = 0.0
	set_process(false)
	_avatar = null
	_guard = null
	if camera == null or not camera.current:
		_previous = null
		return
	camera.current = false
	if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
		_previous.current = true
	_previous = null


func _exit_tree() -> void:
	stand_down()


## Turn toward [param focus] by [param weight] and zoom to keep it [member subject_share] of the frame.
func _aim(focus: Vector3, weight: float, _delta: float) -> void:
	var to_focus: Vector3 = focus - camera.global_position
	var distance: float = to_focus.length()
	if distance < 0.01 or absf(to_focus.y / distance) > 0.999:
		return
	var aim: Basis = Basis.looking_at(to_focus / distance, Vector3.UP)
	camera.global_basis = camera.global_basis.orthonormalized().slerp(aim, weight)
	var fov: float = rad_to_deg(2.0 * atan(SUBJECT_METRES / (2.0 * distance * subject_share)))
	camera.fov = lerpf(camera.fov, clampf(fov, min_fov, max_fov), weight)


## The ballistic arc from [param from] at [param throw] for [param seconds], cut where it hits the map.
func _predict_arc(from: Vector3, throw: Vector3, seconds: float) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array([from])
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_clear_index = 1
	for i: int in range(1, ARC_SAMPLES + 1):
		var t: float = seconds * float(i) / float(ARC_SAMPLES)
		var next: Vector3 = from + throw * t + Vector3.DOWN * (0.5 * _gravity * t * t)
		# The open tower is on a parked layer, so the map alone stops the arc.
		var last: Vector3 = points[points.size() - 1]
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(last, next, 1))
		if not hit.is_empty():
			points.append(hit["position"] as Vector3)
			break
		points.append(next)
	# The camera need not see him while he is still inside the tower's room.
	_clear_index = points.size() - 1
	for i: int in range(1, points.size()):
		if not _in_room(points[i]):
			_clear_index = i
			break
	return points


## The camera point for this throw: side-on to the arc, else high and wide, never in or behind geometry.
func _place(throw: Vector3) -> Vector3:
	var away: Vector3 = Vector3(throw.x, 0.0, throw.z)
	away = away.normalized() if away.length_squared() > 1e-6 else Vector3.FORWARD
	var side: Vector3 = Vector3.UP.cross(away).normalized()
	var at: int = maxi(roundi(anchor_share * float(_arc.size() - 1)), _clear_index)
	var anchor: Vector3 = _arc[clampi(at, 0, _arc.size() - 1)]
	var candidates: PackedVector3Array = PackedVector3Array()
	for distance: float in side_distances:
		for hand: float in [1.0, -1.0]:
			candidates.append(anchor + side * distance * hand + Vector3.UP * side_height - away * side_back)
	for hand: float in [1.0, -1.0]:
		candidates.append(anchor + Vector3.UP * wide_height + side * side_distances[0] * 0.6 * hand - away * side_back)
	candidates.append(anchor + Vector3.UP * wide_height * 1.5 - away * side_back * 2.0)
	for candidate: Vector3 in candidates:
		if _sees_the_arc(candidate, anchor):
			return candidate
	return candidates[candidates.size() - 1]


## True when [param point] is reached from open air at [param anchor] and sees the arc out of the tower.
func _sees_the_arc(point: Vector3, anchor: Vector3) -> bool:
	if _in_room(point):
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var solid: int = 1 | MatchController.OPEN_TOWER_LAYER
	# From the arc out to the camera and a little past it: a point inside rock is reached through a face.
	var reach: Vector3 = point - anchor
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(anchor, point + reach.normalized() * CLEARANCE_METRES, solid)).is_empty():
		return false
	if _clear_index >= _arc.size():
		return true
	for i: int in range(_clear_index, _arc.size()):
		var target: Vector3 = _arc[i]
		var line: Vector3 = target - point
		if line.length() < CLEARANCE_METRES * 2.0:
			return false
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point, target - line.normalized() * CLEARANCE_METRES, solid)
		query.hit_from_inside = true
		if not space.intersect_ray(query).is_empty() or _crosses_room(point, target):
			return false
	return true


## Measure the tower's room from its own collider: the farthest wall from the spawn's axis
## within the guard's height. The tower's faces only stop rays from inside, so it is held as a drum.
func _measure_room() -> void:
	var spawn: Node3D = controller.arena.get_node_or_null(controller.spawn_marker_path) as Node3D if controller.arena != null else null
	if spawn == null:
		_room_radius = 0.0
		return
	var tower: Node = spawn.get_parent()
	if tower.get_instance_id() == _room_of:
		return
	_room_of = tower.get_instance_id()
	_room_centre = spawn.global_position
	_room_radius = 0.0
	for node: Node in tower.find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = node as CollisionShape3D
		var faces: ConcavePolygonShape3D = shape.shape as ConcavePolygonShape3D
		if faces == null or shape.disabled:
			continue
		var frame: Transform3D = shape.global_transform
		for vertex: Vector3 in faces.get_faces():
			var at: Vector3 = frame * vertex
			if at.y < _room_centre.y - ROOM_BELOW or at.y > _room_centre.y + ROOM_ABOVE:
				continue
			_room_radius = maxf(_room_radius, Vector2(at.x - _room_centre.x, at.z - _room_centre.z).length())


func _in_room(point: Vector3) -> bool:
	if _room_radius <= 0.0 or point.y < _room_centre.y - ROOM_BELOW or point.y > _room_centre.y + ROOM_ABOVE:
		return false
	return Vector2(point.x - _room_centre.x, point.z - _room_centre.z).length() < _room_radius + CLEARANCE_METRES


## True when the sight line from [param from] to [param to] passes through the tower's room.
func _crosses_room(from: Vector3, to: Vector3) -> bool:
	for i: int in range(1, SIGHT_SAMPLES):
		if _in_room(from.lerp(to, float(i) / float(SIGHT_SAMPLES))):
			return true
	return false
