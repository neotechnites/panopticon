extends RefCounted

## The lens against the geometry it films: a private physics space holding the map's
## VISUAL meshes as trimeshes, so a camera in rock is caught even where the collider is not.

## Meshes the lens passes through by design (portals, sky, effects); matched on node name.
const SKIP := ["portal", "swirl", "shimmer", "sky", "water", "fog", "ray", "beam", "glow", "particle", "dust", "ember"]
## The probe sphere: twice the lens's near plane, never under the shipped 0.3 m near plane
## (clip cameras run at 0.05 m, where twice that would only catch a lens already in the rock).
const NEAR_FLOOR_METRES: float = 0.3
## Inside test: a ray this long whose first hit is a back face means the lens is in the mesh.
const INSIDE_RAY_METRES: float = 3.0

var _space: RID
var _bodies: Array[RID] = []
var _shapes: Array[Shape3D] = []
var _names: Dictionary = {}        # body RID id -> mesh node name
var _sphere := SphereShape3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _ray_query := PhysicsRayQueryParameters3D.new()
var _exclude_owner: Node = null
var meshes: int = 0
var triangles: int = 0


## Bake every visible mesh under [param world_root] into the probe space.
func build(world_root: Node) -> void:
	_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_space, true)
	var pending: Array[Node] = [world_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is PlayerController:
			continue
		for child: Node in node.get_children():
			pending.append(child)
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		if _skipped(mesh_node):
			continue
		var faces: PackedVector3Array = mesh_node.mesh.get_faces()
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var body: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape.get_rid())
		PhysicsServer3D.body_set_space(body, _space)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, mesh_node.global_transform)
		_bodies.append(body)
		_shapes.append(shape)
		_names[body.get_id()] = String(mesh_node.name)
		meshes += 1
		triangles += faces.size() / 3
	_shape_query.shape = _sphere
	_shape_query.collide_with_bodies = true
	_ray_query.hit_back_faces = true


func _skipped(mesh_node: MeshInstance3D) -> bool:
	var name: String = String(mesh_node.name).to_lower()
	for word: String in SKIP:
		if name.contains(word):
			return true
	return false


## What the lens is in or against this frame, or "" when it is clear.
func probe(camera: Camera3D, ridden: Node) -> String:
	if not _space.is_valid():
		return ""
	var at: Vector3 = camera.global_position
	var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(_space)
	if state == null:
		return ""
	_sphere.radius = maxf(camera.near * 2.0, NEAR_FLOOR_METRES)
	_shape_query.transform = Transform3D(Basis(), at)
	var hits: Array[Dictionary] = state.intersect_shape(_shape_query, 1)
	if not hits.is_empty():
		return "near " + String(_names.get((hits[0]["rid"] as RID).get_id(), "mesh"))
	for direction: Vector3 in [Vector3.UP, -camera.global_transform.basis.z]:
		_ray_query.from = at
		_ray_query.to = at + direction * INSIDE_RAY_METRES
		var hit: Dictionary = state.intersect_ray(_ray_query)
		if not hit.is_empty() and (hit["normal"] as Vector3).dot(direction) > 0.0:
			return "inside " + String(_names.get((hit["rid"] as RID).get_id(), "mesh"))
	return _against_bodies(camera, ridden)


## Another body inside the near plane: the lens is in somebody's head.
func _against_bodies(camera: Camera3D, ridden: Node) -> String:
	var world: World3D = camera.get_world_3d()
	if world == null:
		return ""
	if ridden != _exclude_owner:
		_exclude_owner = ridden
		var rids: Array[RID] = []
		if ridden != null:
			for node: Node in [ridden] + ridden.find_children("*", "CollisionObject3D", true, false):
				if node is CollisionObject3D:
					rids.append((node as CollisionObject3D).get_rid())
		_shape_query.exclude = rids
	_sphere.radius = maxf(camera.near, NEAR_FLOOR_METRES * 0.5)
	_shape_query.transform = Transform3D(Basis(), camera.global_position)
	var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(_shape_query, 4)
	for hit: Dictionary in hits:
		var body: Node = hit.get("collider") as Node
		if body is PlayerController:
			return "inside " + String(body.name)
	return ""


func free_space() -> void:
	for body: RID in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()
	_shapes.clear()
	if _space.is_valid():
		PhysicsServer3D.free_rid(_space)
		_space = RID()
