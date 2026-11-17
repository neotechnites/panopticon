class_name RifleClearance
extends Node
## Keeps the drawn rifle out of the world: a gun that would reach into a wall, a column or a body slides back
## toward the eye, at once, and eases back out once clear. Picture only; the shot is the eye's.

## The furthest the gun slides back, metres: its stock comes to the shoulder. Past it the gun stays there.
const MAX_SLIDE: float = 0.3
## Roughly how long the gun takes to ease back out once the way is clear, seconds.
const EASE_OUT_SECONDS: float = 0.15
## Halvings of the slide searched for the least that clears: 0.3 m / 2^6, about 5 mm.
const SEARCH_STEPS: int = 6
## The twelve edges of a box, as pairs of [method AABB.get_endpoint] indices that differ in one bit.
const BOX_EDGES: PackedInt32Array = [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]

## The rifle whose holder, origin and muzzle are read: its ViewModel hangs off its origin, the eye.
@export var rifle: Rifle
## The drawn gun, under ViewModel: its bounds are the volume kept clear.
@export var model: Node3D

var _slide: float = 0.0
## The corners of the model's bounds in ViewModel space, read once it is in the tree.
var _corners: PackedVector3Array = PackedVector3Array()
var _drawn: PackedVector3Array = PackedVector3Array()
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []


func _init() -> void:
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_drawn.resize(8)


## How far the gun is slid back right now, metres.
func get_slide() -> float:
	return _slide


## [param pose], a ViewModel transform in the rifle's space, slid back as far as the world needs this frame (at
## once), or eased toward it over [param delta] when it needs less, and never past [constant MAX_SLIDE].
func place(pose: Transform3D, delta: float) -> Transform3D:
	var wanted: float = _wanted_slide(pose)
	if wanted >= _slide:
		_slide = wanted
	else:
		_slide = wanted + (_slide - wanted) * exp(-3.0 * delta / EASE_OUT_SECONDS)
	return slid(pose)


## [param pose] slid back by the current slide, along the line from the rifle's origin to its muzzle.
func slid(pose: Transform3D) -> Transform3D:
	if _slide <= 0.0 or rifle == null or rifle.muzzle == null:
		return pose
	var tip: Vector3 = pose * rifle.muzzle.transform.origin
	var reach: float = (rifle.global_transform.basis * tip).length()
	if reach <= 0.0:
		return pose
	return Transform3D(pose.basis, pose.origin - tip * (_slide / reach))


## The least slide that keeps the gun's bounds clear of everything the shot would meet, to within
## [constant SEARCH_STEPS] halvings of [constant MAX_SLIDE]; [constant MAX_SLIDE] when even that does not clear.
func _wanted_slide(pose: Transform3D) -> float:
	if rifle == null or rifle.profile == null or rifle.muzzle == null or model == null or not rifle.is_inside_tree():
		return 0.0
	var holder: CollisionObject3D = rifle.shooter_body as CollisionObject3D
	if holder == null or not holder.is_inside_tree():
		return 0.0
	var space: PhysicsDirectSpaceState3D = rifle.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	if _corners.is_empty():
		_read_corners()
		if _corners.is_empty():
			return 0.0
	_ray.collision_mask = rifle.profile.hit_mask
	if _exclude.is_empty() or _exclude[0] != holder.get_rid():
		_exclude.clear()
		_exclude.append(holder.get_rid())
		_ray.exclude = _exclude
	var drawn: Transform3D = rifle.global_transform * pose
	for i: int in 8:
		_drawn[i] = drawn * _corners[i]
	var back: Vector3 = (rifle.global_transform.basis * (pose * rifle.muzzle.transform.origin)).normalized()
	if not _blocked(space, Vector3.ZERO):
		return 0.0
	if _blocked(space, back * MAX_SLIDE):
		return MAX_SLIDE
	var clear: float = MAX_SLIDE
	var blocked: float = 0.0
	for _step: int in SEARCH_STEPS:
		var middle: float = 0.5 * (clear + blocked)
		if _blocked(space, back * middle):
			blocked = middle
		else:
			clear = middle
	return clear


## Whether the bounds' edges, moved back by [param shift], cross anything. Rays, cast both ways: the maps'
## faces are one-sided trimesh, which shape overlaps and sweeps miss from behind and a ray meets only from the front.
func _blocked(space: PhysicsDirectSpaceState3D, shift: Vector3) -> bool:
	for edge: int in range(0, BOX_EDGES.size(), 2):
		var a: Vector3 = _drawn[BOX_EDGES[edge]] - shift
		var b: Vector3 = _drawn[BOX_EDGES[edge + 1]] - shift
		_ray.from = a
		_ray.to = b
		if not space.intersect_ray(_ray).is_empty():
			return true
		_ray.from = b
		_ray.to = a
		if not space.intersect_ray(_ray).is_empty():
			return true
	return false


func _read_corners() -> void:
	var view_model: Node3D = model.get_parent() as Node3D
	var bounds: AABB = AABB()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = (view_model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = box if not bounds.has_volume() else bounds.merge(box)
	if not bounds.has_volume():
		return
	for i: int in 8:
		_corners.append(bounds.get_endpoint(i))
