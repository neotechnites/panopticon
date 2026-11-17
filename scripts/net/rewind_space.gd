class_name RewindSpace
extends RefCounted
## A private physics space holding stand-ins of bodies where they stood earlier, for a lag-compensated
## ray. The live bodies are never moved: a kinematic body moved inside a tick is not moved for a query.

var _space: RID = PhysicsServer3D.space_create()
## Stand-in static bodies by seat, made on first use.
var _stand_ins: Dictionary[int, RID] = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for stand_in: RID in _stand_ins.values():
			PhysicsServer3D.free_rid(stand_in)
		PhysicsServer3D.free_rid(_space)


## Take every stand-in out of the way of the next ray.
func clear() -> void:
	for stand_in: RID in _stand_ins.values():
		PhysicsServer3D.body_set_collision_layer(stand_in, 0)


## Stand [param seat]'s stand-in at [param origin] with [param body]'s shapes, layer and facing as they are now.
func place(seat: int, body: CollisionObject3D, origin: Vector3) -> void:
	if not _stand_ins.has(seat):
		var made: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(made, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(made, _space)
		PhysicsServer3D.body_set_collision_mask(made, 0)
		_stand_ins[seat] = made
	var stand_in: RID = _stand_ins[seat]
	PhysicsServer3D.body_clear_shapes(stand_in)
	PhysicsServer3D.body_set_state(
		stand_in, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(body.global_basis, origin)
	)
	for owner: int in body.get_shape_owners():
		var local: Transform3D = body.shape_owner_get_transform(owner)
		var disabled: bool = body.is_shape_owner_disabled(owner)
		for index: int in body.shape_owner_get_shape_count(owner):
			PhysicsServer3D.body_add_shape(stand_in, body.shape_owner_get_shape(owner, index).get_rid(), local, disabled)
	PhysicsServer3D.body_attach_object_instance_id(stand_in, body.get_instance_id())
	PhysicsServer3D.body_set_collision_layer(stand_in, body.collision_layer)


## The first stand-in [param query]'s ray meets, as [method PhysicsDirectSpaceState3D.intersect_ray]
## reports it with the live body as collider and rid; empty for none.
func intersect_ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit: Dictionary = PhysicsServer3D.space_get_direct_state(_space).intersect_ray(query)
	var body: CollisionObject3D = hit.get("collider") as CollisionObject3D
	if body != null:
		hit["rid"] = body.get_rid()
	return hit
