class_name RewindSpace
extends RefCounted
## A private physics space holding stand-ins of bodies where they stood earlier, for a lag-compensated
## ray. The live bodies are never moved: a kinematic body moved inside a tick is not moved for a query.

var _space: RID = PhysicsServer3D.space_create()
## Stand-in static bodies by entity index, made on first use with shapes of their own.
var _stand_ins: Dictionary[int, RID] = {}
## The sizes each stand-in's shapes were last given: radius, then standing and crouched height.
var _sizes: Dictionary[int, Vector3] = {}
var _shapes: Array[RID] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for stand_in: RID in _stand_ins.values():
			PhysicsServer3D.free_rid(stand_in)
		for shape: RID in _shapes:
			PhysicsServer3D.free_rid(shape)
		PhysicsServer3D.free_rid(_space)


## Take every stand-in out of the way of the next ray.
func clear() -> void:
	for stand_in: RID in _stand_ins.values():
		PhysicsServer3D.body_set_collision_layer(stand_in, 0)


## Stand [param index]'s stand-in at [param origin] as [param body] in the [param crouched] stance:
## its capsule sized for that stance, with the body's present layer and facing. A body with no capsule has none.
func place_body(index: int, body: PlayerController, origin: Vector3, crouched: bool) -> void:
	var capsule: CapsuleShape3D = body.collision.shape as CapsuleShape3D if body.collision != null else null
	if capsule == null:
		return
	var stand_in: RID = _stand_in(index, 2)
	var size: Vector3 = Vector3(capsule.radius, body.stance_capsule_height(false), body.stance_capsule_height(true))
	if not _sizes.has(index) or _sizes[index] != size:
		_sizes[index] = size
		for stance: int in 2:
			PhysicsServer3D.shape_set_data(
				PhysicsServer3D.body_get_shape(stand_in, stance), {"radius": size.x, "height": size[1 + stance]}
			)
	var off: bool = _is_shape_off(body)
	for stance: int in 2:
		PhysicsServer3D.body_set_shape_transform(stand_in, stance, body.stance_capsule_transform(stance == 1))
		PhysicsServer3D.body_set_shape_disabled(stand_in, stance, off or crouched != (stance == 1))
	_stand(stand_in, Transform3D(body.global_basis, origin), body, body.collision_layer)


## Stand [param index]'s stand-in as a sphere of [param radius] at [param centre] on [param layer]: a
## shield. A ray meeting it reports [param live] as collider while that still stands, else none.
func place_sphere(index: int, centre: Vector3, radius: float, layer: int, live: CollisionObject3D) -> void:
	var stand_in: RID = _stand_in(index, 1)
	var size: Vector3 = Vector3(radius, 0.0, 0.0)
	if not _sizes.has(index) or _sizes[index] != size:
		_sizes[index] = size
		PhysicsServer3D.shape_set_data(PhysicsServer3D.body_get_shape(stand_in, 0), radius)
	_stand(stand_in, Transform3D(Basis.IDENTITY, centre), live if is_instance_valid(live) else null, layer)


## The first stand-in [param query]'s ray meets, as [method PhysicsDirectSpaceState3D.intersect_ray]
## reports it with the live object as collider and rid; empty for none.
func intersect_ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit: Dictionary = PhysicsServer3D.space_get_direct_state(_space).intersect_ray(query)
	if hit.is_empty():
		return hit
	var live: CollisionObject3D = hit.get("collider") as CollisionObject3D
	hit["rid"] = live.get_rid() if live != null else RID()
	return hit


## The stand-in for [param index], made with [param shapes] shapes of its own: two capsules (standing,
## crouched) or one sphere. An index keeps the kind it was first made as.
func _stand_in(index: int, shapes: int) -> RID:
	if _stand_ins.has(index):
		return _stand_ins[index]
	var made: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(made, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(made, _space)
	PhysicsServer3D.body_set_collision_mask(made, 0)
	PhysicsServer3D.body_set_collision_layer(made, 0)
	for _shape: int in shapes:
		var shape: RID = PhysicsServer3D.capsule_shape_create() if shapes == 2 else PhysicsServer3D.sphere_shape_create()
		_shapes.append(shape)
		PhysicsServer3D.body_add_shape(made, shape)
	_stand_ins[index] = made
	return made


func _stand(stand_in: RID, at: Transform3D, live: Object, layer: int) -> void:
	PhysicsServer3D.body_set_state(stand_in, PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	PhysicsServer3D.body_attach_object_instance_id(stand_in, live.get_instance_id() if live != null else 0)
	# Last: it is this call that puts the shapes just placed in front of a ray.
	PhysicsServer3D.body_set_collision_layer(stand_in, layer)


## True when [param body]'s capsule is switched off now: it has no shape to be hit with, then or now.
static func _is_shape_off(body: PlayerController) -> bool:
	for owner: int in body.get_shape_owners():
		if body.shape_owner_get_owner(owner) == body.collision:
			return body.is_shape_owner_disabled(owner) or body.collision.disabled
	return true
