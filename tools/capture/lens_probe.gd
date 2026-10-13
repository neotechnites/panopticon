extends RefCounted

## The lens against what it films: the map's VISUAL meshes baked into a private physics space,
## plus every body but the ridden one, measured per frame as [lens] near and cover (expect.py).

## Meshes the lens passes through by design (portals, sky, effects); matched on node name.
const SKIP := ["haze", "portal", "swirl", "shimmer", "sky", "water", "fog", "ray", "beam", "glow", "particle", "dust", "ember"]
const SPHERE_METRES: float = 0.35
const FORWARD_METRES: float = 1.5
const COVER_METRES: float = 2.0
const COVER_GRID: int = 5

var _space: RID
var _bodies: Array[RID] = []
var _shapes: Array[Shape3D] = []
var _sphere := SphereShape3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _ray_query := PhysicsRayQueryParameters3D.new()
var _world_shape := PhysicsShapeQueryParameters3D.new()
var _world_ray := PhysicsRayQueryParameters3D.new()
var _exclude_owner: Node = null
var meshes: int = 0
var triangles: int = 0


## Bake every visible mesh under [param world_root] (bodies aside: they move) into the probe space.
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
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.is_visible_in_tree() or _skipped(mesh_node):
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
		meshes += 1
		triangles += faces.size() / 3
	_sphere.radius = SPHERE_METRES
	_shape_query.shape = _sphere
	_world_shape.shape = _sphere
	_ray_query.hit_back_faces = true


func _skipped(mesh_node: MeshInstance3D) -> bool:
	var name: String = String(mesh_node.name).to_lower()
	for word: String in SKIP:
		if name.contains(word):
			return true
	return false


## This frame's [code]{near, cover}[/code]: metres to the nearest thing at the lens (sphere, then a
## FORWARD_METRES ray; FORWARD_METRES when clear) and the share of a 5x5 frustum grid hitting within COVER_METRES.
func measure(camera: Camera3D, ridden: Node) -> Dictionary:
	var near: float = FORWARD_METRES
	var cover: float = 0.0
	if not _space.is_valid():
		return {"near": near, "cover": cover}
	var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(_space)
	var world: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	_exclude(ridden)
	var at: Vector3 = camera.global_position
	_shape_query.transform = Transform3D(Basis(), at)
	_world_shape.transform = _shape_query.transform
	var rest: Dictionary = state.get_rest_info(_shape_query)
	if not rest.is_empty():
		near = minf(near, at.distance_to(rest["point"]))
	elif not state.intersect_shape(_shape_query, 1).is_empty():
		near = SPHERE_METRES
	for hit: Dictionary in world.intersect_shape(_world_shape, 4):
		if hit.get("collider") is PlayerController:
			near = minf(near, SPHERE_METRES)
	near = minf(near, _ray(state, world, at, -camera.global_transform.basis.z, FORWARD_METRES))
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var hits: int = 0
	for gx: int in COVER_GRID:
		for gy: int in COVER_GRID:
			var pixel := Vector2((gx + 0.5) / COVER_GRID * size.x, (gy + 0.5) / COVER_GRID * size.y)
			if _ray(state, world, at, camera.project_ray_normal(pixel), COVER_METRES) < COVER_METRES:
				hits += 1
	cover = float(hits) / float(COVER_GRID * COVER_GRID)
	return {"near": maxf(near, 0.0), "cover": cover}


## Metres to the first mesh or body along [param direction], or [param reach] when none.
func _ray(state: PhysicsDirectSpaceState3D, world: PhysicsDirectSpaceState3D, at: Vector3, direction: Vector3, reach: float) -> float:
	var best: float = reach
	_ray_query.from = at
	_ray_query.to = at + direction * reach
	var hit: Dictionary = state.intersect_ray(_ray_query)
	if not hit.is_empty():
		best = at.distance_to(hit["position"])
	_world_ray.from = at
	_world_ray.to = _ray_query.to
	hit = world.intersect_ray(_world_ray)
	if not hit.is_empty() and hit.get("collider") is PlayerController:
		best = minf(best, at.distance_to(hit["position"]))
	return best


## The ridden body (and its colliders) is never at its own lens.
func _exclude(ridden: Node) -> void:
	if ridden == _exclude_owner:
		return
	_exclude_owner = ridden
	var rids: Array[RID] = []
	if ridden != null and is_instance_valid(ridden):
		for node: Node in [ridden] + ridden.find_children("*", "CollisionObject3D", true, false):
			if node is CollisionObject3D:
				rids.append((node as CollisionObject3D).get_rid())
	_world_shape.exclude = rids
	_world_ray.exclude = rids


func free_space() -> void:
	for body: RID in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()
	_shapes.clear()
	if _space.is_valid():
		PhysicsServer3D.free_rid(_space)
		_space = RID()
