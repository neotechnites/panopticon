class_name RifleClearance
extends Node
## Keeps the drawn rifle out of the world: a barrel that would reach into a wall, a column or a body
## slides back toward the eye until its muzzle is clear. Picture only; the shot is the eye's.

## How far short of what it meets the muzzle stops: the barrel's radius at the muzzle, metres
## (rifle_n64_trace.py BARREL at the ViewModel's 0.75 scale).
const MARGIN: float = 0.0075

## The rifle whose holder, origin and muzzle are read: its ViewModel hangs off its origin, the eye.
@export var rifle: Rifle

var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []


func _init() -> void:
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true


## [param pose], a ViewModel transform in the rifle's space, moved back along the eye-to-muzzle line just
## far enough that the line from the eye to the muzzle meets nothing the shot would.
func clear(pose: Transform3D) -> Transform3D:
	if rifle == null or rifle.profile == null or rifle.muzzle == null or not rifle.is_inside_tree():
		return pose
	var holder: CollisionObject3D = rifle.shooter_body as CollisionObject3D
	if holder == null or not holder.is_inside_tree():
		return pose
	var space: PhysicsDirectSpaceState3D = rifle.get_world_3d().direct_space_state
	if space == null:
		return pose
	# The rifle's origin is the eye it is drawn from: the camera, or in third person the drawn eye.
	# A ray, as the shot is: a thin swept shape is not reliable against the maps' trimesh faces.
	var tip: Vector3 = pose * rifle.muzzle.transform.origin
	var frame: Transform3D = rifle.global_transform
	_ray.from = frame.origin
	_ray.to = frame * tip
	_ray.collision_mask = rifle.profile.hit_mask
	if _exclude.is_empty() or _exclude[0] != holder.get_rid():
		_exclude.clear()
		_exclude.append(holder.get_rid())
		_ray.exclude = _exclude
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty():
		return pose
	var reach: float = _ray.from.distance_to(_ray.to)
	var room: float = maxf(_ray.from.distance_to(hit["position"] as Vector3) - MARGIN, 0.0)
	return Transform3D(pose.basis, pose.origin - tip * (1.0 - room / reach))
