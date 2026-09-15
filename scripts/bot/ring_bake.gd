class_name RingBake
extends NavigationRegion3D

## What a map is to a bot, baked once from its geometry and markers: a walkable
## mesh with every lethal volume carved out, jump and pad links, and cover points.
## Nothing here is told what a section is. One per level root; see [method ensure].

const NODE_NAME: StringName = &"RingBake"
## Every baked region joins this group, so [PhaseGate] can ask for a rebake.
const GROUP: StringName = &"ring_navigation"
const AGENT_RADIUS: float = 0.5
const AGENT_HEIGHT: float = 2.0
const AGENT_MAX_CLIMB: float = 0.5
const AGENT_MAX_SLOPE_DEGREES: float = 40.0
const CELL_SIZE: float = 0.25
const CELL_HEIGHT: float = 0.25
const STATIC_COLLIDER_MASK: int = 1
## Metres a trap's carve reaches past its box, and past a lava surface upward.
const LETHAL_INFLATION_METRES: float = 0.8
const LETHAL_VERTICAL_MARGIN_METRES: float = 1.0
const SURFACE_CARVE_MARGIN_METRES: float = 0.25
## A mesh edge with no floor this far beyond it is a drop; the strip carved inboard of one.
const DROP_PROBE_METRES: float = 0.4
const DROP_PROBES: int = 5
const DROP_PROBE_DEPTH_METRES: float = 2.0
const DROP_MARGIN_METRES: float = 1.0
## Jump envelope: run speed, jump speed and gravity come from the movement profile.
const JUMP_MIN_METRES: float = 1.5
const JUMP_MAX_METRES: float = 9.5
const JUMP_STEP_METRES: float = 0.25
const JUMP_MIN_SPEED: float = 2.5
const JUMP_SLOW_FRACTION: float = 0.6
const EDGE_SAMPLE_METRES: float = 1.5
const TAKEOFF_INSET_METRES: float = 0.35
const LAND_MARGIN_METRES: float = 0.45
const LAND_HEIGHT_TOLERANCE_METRES: float = 2.5
const LINK_DEDUPE_METRES: float = 1.2
const LINK_MAX: int = 400
const BODY_RADIUS_METRES: float = 0.4
const BODY_HEIGHT_METRES: float = 1.8
const ARC_LIFT_METRES: float = 0.15
const ARC_SAMPLES: int = 12
const GAP_SAMPLES: int = 6
const JUMP_TRAVEL_COST: float = 1.5
const HARD_JUMP_TRAVEL_COST: float = 2.5
const PAD_TRAVEL_COST: float = 0.5
const PAD_LAND_SEARCH_METRES: float = 5.0
const PAD_LAND_REACH_METRES: float = 1.5
const PAD_LAND_MARGIN_METRES: float = 1.2
const PAD_MAX_FLIGHT_SECONDS: float = 6.0
const PAD_CARVE_MARGIN_METRES: float = 0.5
const PAD_CLEARANCE_METRES: float = 0.8
## Cover points: sampled every this many metres; discarded this close to a lethal volume.
const COVER_SPACING_METRES: float = 1.5
const COVER_LETHAL_CLEARANCE_METRES: float = 1.0
const COVER_CHEST_METRES: float = 0.9
const COVER_HEAD_METRES: float = 1.5
const COVER_CELL_METRES: float = 4.0
const COVER_TAKEN_METRES: float = 1.5
const EYE_HEIGHT_METRES: float = 1.6
const EYE_MARKER_PATH: NodePath = ^"Tower/TowerSpawn"
## Path results are reused for this many physics ticks per half-metre cell pair.
const PATH_CACHE_TICKS: int = 6
const PATH_CACHE_CELL_METRES: float = 0.5
const PATH_CACHE_MAX: int = 192
const REACH_TOLERANCE_METRES: float = 1.5
const POLY_CELL_METRES: float = 2.0
const DEFAULT_GRAVITY: float = 22.0
const DEFAULT_RUN_SPEED: float = 11.0
const DEFAULT_JUMP_SPEED: float = 7.0

## Navigation layer bits: the mesh, easy jumps, hard jumps, pads.
const LAYER_WALK: int = 1
const LAYER_EASY_JUMP: int = 2
const LAYER_HARD_JUMP: int = 4
const LAYER_PAD: int = 8

enum LinkKind { JUMP, PAD }

## One jump or pad flight the mesh path can take.
class Link extends RefCounted:
	var kind: LinkKind = LinkKind.JUMP
	var start: Vector3 = Vector3.ZERO
	var end: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.FORWARD
	## Horizontal speed the take-off wants; a pad sets it.
	var speed: float = 0.0
	var node: NavigationLink3D = null
	var pad: BoostPad = null

## One lethal volume in its own space: a trap's box, or a kill volume's cylinder.
class Lethal extends RefCounted:
	var inverse: Transform3D = Transform3D.IDENTITY
	var centre: Vector3 = Vector3.ZERO
	var half: Vector3 = Vector3.ZERO
	var reach_squared: float = 0.0
	var feet_only: bool = false
	var round: bool = false

## Microseconds spent this tick, by kind ("cover", "path", "bake"); the harness reads and clears it.
static var cost_usec: Dictionary = {}
## Regions by level-root instance id; the tree cannot be asked while the root is still readying.
static var _by_root: Dictionary = {}

var _polygons: int = 0
var _bake_ms: int = 0
var _synced: bool = false
var _bake_root: Node = null
var _movement: MovementProfile = null
var _gravity: float = DEFAULT_GRAVITY
var _run_speed: float = DEFAULT_RUN_SPEED
var _jump_speed: float = DEFAULT_JUMP_SPEED
var _root_transform: Transform3D = Transform3D.IDENTITY
var _space: PhysicsDirectSpaceState3D = null
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _sight: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _body: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()

var _lethal: Array[Lethal] = []
var _links: Array[Link] = []
var _link_by_owner: Dictionary = {}
var _dead_pads: Array[BoostPad] = []
var _all_pads: Array[BoostPad] = []
var _cover: PackedVector3Array = PackedVector3Array()
var _cover_facing: PackedVector3Array = PackedVector3Array()
var _cover_cells: Dictionary = {}
var _eye: Vector3 = Vector3.ZERO

## World-space copy of the baked polygons, indexed by 2 m cell.
var _verts: PackedVector3Array = PackedVector3Array()
var _polys: Array[PackedInt32Array] = []
var _poly_cells: Dictionary = {}
var _edge_a: PackedVector3Array = PackedVector3Array()
var _edge_b: PackedVector3Array = PackedVector3Array()
var _edge_normal: PackedVector3Array = PackedVector3Array()
var _edge_island: PackedInt32Array = PackedInt32Array()
var _edge_cells: Dictionary = {}

var _path_cache: Dictionary = {}
var _path_cache_tick: int = -1
var _query: NavigationPathQueryParameters3D = NavigationPathQueryParameters3D.new()
var _result: NavigationPathQueryResult3D = NavigationPathQueryResult3D.new()

var _drops: int = 0
var _jumps: int = 0
var _pads: int = 0


static func charge(kind: String, since_usec: int) -> void:
	cost_usec[kind] = int(cost_usec.get(kind, 0)) + (Time.get_ticks_usec() - since_usec)


## The bake under [param level_root], made now if this is the first ask.
static func ensure(level_root: Node, movement: MovementProfile = null) -> RingBake:
	if level_root == null:
		return null
	var key: int = level_root.get_instance_id()
	var cached: RingBake = _by_root.get(key, null) as RingBake
	if cached != null and is_instance_valid(cached):
		return cached
	var existing: RingBake = level_root.get_node_or_null(NodePath(NODE_NAME)) as RingBake
	if existing != null:
		_by_root[key] = existing
		return existing
	var region: RingBake = RingBake.new()
	region.name = NODE_NAME
	region._movement = movement
	_by_root[key] = region
	region.bake_from(level_root)
	level_root.add_child.call_deferred(region)
	return region


## The topmost [Node3D] above [param node], or the tree root when there is none.
static func level_root_of(node: Node) -> Node:
	var best: Node = null
	var cursor: Node = node.get_parent() if node != null else null
	while cursor != null:
		if cursor is Node3D:
			best = cursor
		cursor = cursor.get_parent()
	if best == null and node != null and node.is_inside_tree():
		return node.get_tree().root
	return best


func _ready() -> void:
	add_to_group(GROUP)
	var map: RID = get_navigation_map()
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.region_set_use_async_iterations(get_rid(), false)
	if _polygons <= 0 and _bake_root != null:
		bake_from(_bake_root)
	NavigationServer3D.map_force_update(map)


## Re-bakes with the last root. [PhaseGate] asks for this once gated geometry has swapped.
func phase_geometry_changed() -> void:
	if _bake_root != null:
		bake_from(_bake_root)


# --- Baking -------------------------------------------------------------------

## Parse [param root]'s static colliders, carve what kills, bake, then find links and cover.
func bake_from(root: Node) -> void:
	_bake_root = root
	_synced = false
	_path_cache.clear()
	var started_usec: int = Time.get_ticks_usec()
	var started: int = Time.get_ticks_msec()
	var root_3d: Node3D = root as Node3D
	_root_transform = root_3d.global_transform if root_3d != null else Transform3D.IDENTITY
	var into_root: Transform3D = _root_transform.affine_inverse()
	_space = null
	if root_3d != null and root_3d.is_inside_tree() and root_3d.get_world_3d() != null:
		_space = root_3d.get_world_3d().direct_space_state
	_ray.collision_mask = STATIC_COLLIDER_MASK
	_ray.collide_with_areas = false
	_ray.hit_from_inside = true
	_sight.collision_mask = STATIC_COLLIDER_MASK
	_sight.collide_with_areas = false
	if _body.shape == null:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = BODY_RADIUS_METRES
		capsule.height = BODY_HEIGHT_METRES
		_body.shape = capsule
		_body.collision_mask = STATIC_COLLIDER_MASK
		_body.collide_with_areas = false
	if _movement != null:
		_gravity = maxf(_movement.get_effective_gravity(), 0.1)
		_run_speed = maxf(_movement.ground_speed, 0.1)
		_jump_speed = maxf(_movement.jump_velocity, 0.1)
	_eye = _find_eye(root)

	var mesh: NavigationMesh = _new_mesh()
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	_lethal.clear()
	_collect_lethal(root)
	_all_pads.clear()
	_collect_pads(root, _all_pads)
	var carved: int = _carve_lethal(root, source, into_root)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_index_mesh(mesh)
	_drops = _carve_drops(source, into_root)
	_dead_pads.clear()
	var dead: int = _carve_dead_pads(root, source, into_root)
	if _drops > 0 or dead > 0:
		mesh = _new_mesh()
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		_index_mesh(mesh)
	navigation_mesh = mesh
	_polygons = mesh.get_polygon_count()
	_build_links(root)
	_sample_cover()
	if is_inside_tree():
		NavigationServer3D.map_force_update(get_navigation_map())
	_bake_ms = Time.get_ticks_msec() - started
	charge("bake", started_usec)
	print("RingBake: %d polygons, %d lethal carved, %d drop edges, %d dead pads, %d jump links, %d pad links, %d cover points, in %d ms" % [
		_polygons, carved, _drops, dead, _jumps, _pads, _cover.size(), _bake_ms,
	])


func _new_mesh() -> NavigationMesh:
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = STATIC_COLLIDER_MASK
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_HEIGHT
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = AGENT_MAX_CLIMB
	mesh.agent_max_slope = AGENT_MAX_SLOPE_DEGREES
	return mesh


## The guard's eye: the tower spawn marker plus an eye height, or the root's origin.
func _find_eye(root: Node) -> Vector3:
	var marker: Node3D = root.get_node_or_null(EYE_MARKER_PATH) as Node3D
	if marker == null:
		marker = root.find_child("TowerSpawn", true, false) as Node3D
	var base: Vector3 = marker.global_position if marker != null else _root_transform.origin
	return base + Vector3.UP * EYE_HEIGHT_METRES


func get_polygon_count() -> int:
	return _polygons


func get_bake_milliseconds() -> int:
	return _bake_ms


func get_link_count() -> int:
	return _links.size()


func get_cover_count() -> int:
	return _cover.size()


func get_drop_edge_count() -> int:
	return _drops


func get_eye() -> Vector3:
	return _eye


## True once the baked mesh answers map queries: a known vertex must snap to itself.
func is_ready() -> bool:
	if _synced:
		return true
	if _polygons <= 0 or not is_inside_tree():
		return false
	var map: RID = get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) <= 0:
		return false
	var vertex: Vector3 = _root_transform * navigation_mesh.get_vertices()[0]
	_synced = NavigationServer3D.map_get_closest_point(map, vertex).distance_to(vertex) < 0.05
	return _synced


# --- Lethal volumes -----------------------------------------------------------

func _collect_lethal(node: Node) -> void:
	var trap: TrapVolume = node as TrapVolume
	var pit: KillVolume = node as KillVolume
	if trap != null:
		var box: Lethal = Lethal.new()
		box.inverse = trap.global_transform.affine_inverse()
		box.centre = trap.global_position
		box.half = trap.size_metres * 0.5
		box.reach_squared = (box.half + Vector3.ONE * (LETHAL_INFLATION_METRES + 1.0)).length_squared()
		box.feet_only = trap.feet_only
		_lethal.append(box)
	elif pit != null:
		var drum: Lethal = Lethal.new()
		var depth: float = pit.roof_depth_metres + pit.depth_metres * 0.5
		drum.inverse = (pit.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, -depth, 0.0))).affine_inverse()
		drum.centre = pit.global_transform * Vector3(0.0, -depth, 0.0)
		drum.half = Vector3(pit.radius_metres, pit.depth_metres * 0.5, pit.radius_metres)
		drum.reach_squared = (drum.half + Vector3.ONE * (LETHAL_INFLATION_METRES + 1.0)).length_squared()
		drum.round = true
		_lethal.append(drum)
	for child: Node in node.get_children():
		_collect_lethal(child)


## True when standing at [param point] would trip a trap: inside its box, or at or
## below the surface a feet_only trap converts at, plus [param margin] metres.
func is_lethal(point: Vector3, margin: float = 0.0) -> bool:
	for box: Lethal in _lethal:
		if point.distance_squared_to(box.centre) > box.reach_squared:
			continue
		var local: Vector3 = box.inverse * point
		if box.round:
			if Vector2(local.x, local.z).length() > box.half.x + margin:
				continue
		elif absf(local.x) > box.half.x + margin or absf(local.z) > box.half.z + margin:
			continue
		var top: float = 0.05 + margin if box.feet_only else box.half.y + margin
		if local.y <= top and local.y >= -box.half.y - margin:
			return true
	return false


func _carve_lethal(node: Node, source: NavigationMeshSourceGeometryData3D, into_root: Transform3D) -> int:
	var carved: int = 0
	var trap: TrapVolume = node as TrapVolume
	var pit: KillVolume = node as KillVolume
	if pit != null:
		var disc: PackedVector3Array = PackedVector3Array()
		var reach: float = pit.radius_metres + LETHAL_INFLATION_METRES
		for index: int in 24:
			var angle: float = TAU * float(index) / 24.0
			disc.append(into_root * (pit.global_transform * Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)))
		var bottom: float = (into_root * (pit.global_transform * Vector3(0.0, -pit.roof_depth_metres - pit.depth_metres, 0.0))).y
		var roof: float = (into_root * (pit.global_transform * Vector3(0.0, -pit.roof_depth_metres, 0.0))).y
		source.add_projected_obstruction(disc, bottom - LETHAL_VERTICAL_MARGIN_METRES, roof - bottom + LETHAL_VERTICAL_MARGIN_METRES, true)
		carved += 1
	if trap != null:
		var half: Vector3 = trap.size_metres * 0.5
		var hx: float = half.x + LETHAL_INFLATION_METRES
		var hz: float = half.z + LETHAL_INFLATION_METRES
		var world: Transform3D = trap.global_transform
		var corners: PackedVector3Array = PackedVector3Array()
		for corner: Vector3 in [
			Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz)
		]:
			corners.append(into_root * (world * corner))
		var bottom: float = (into_root * (world * Vector3(0.0, -half.y, 0.0))).y
		# The carve stops at the lethal top, so a platform standing IN a trap keeps its mesh.
		var top: float = (into_root * (world * Vector3(0.0, half.y, 0.0))).y
		if trap.feet_only:
			top = (into_root * world.origin).y + SURFACE_CARVE_MARGIN_METRES
		var floor_level: float = bottom - LETHAL_VERTICAL_MARGIN_METRES
		source.add_projected_obstruction(corners, floor_level, maxf(top - floor_level, 0.1), true)
		carved += 1
	for child: Node in node.get_children():
		carved += _carve_lethal(child, source, into_root)
	return carved


# --- The mesh, indexed --------------------------------------------------------

## Copy [param mesh] into world space with a cell index over polygons and boundary edges.
func _index_mesh(mesh: NavigationMesh) -> void:
	var local: PackedVector3Array = mesh.get_vertices()
	_verts.resize(local.size())
	for index: int in local.size():
		_verts[index] = _root_transform * local[index]
	_polys.clear()
	_poly_cells.clear()
	var count: int = mesh.get_polygon_count()
	var stride: int = maxi(local.size(), 1)
	var seen: Dictionary = {}
	var shared: Dictionary = {}
	for index: int in count:
		var polygon: PackedInt32Array = mesh.get_polygon(index)
		_polys.append(polygon)
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		for corner: int in polygon.size():
			var vertex: Vector3 = _verts[polygon[corner]]
			low = Vector2(minf(low.x, vertex.x), minf(low.y, vertex.z))
			high = Vector2(maxf(high.x, vertex.x), maxf(high.y, vertex.z))
			var key: int = _edge_key(polygon[corner], polygon[(corner + 1) % polygon.size()], stride)
			if seen.has(key):
				shared[key] = true
			else:
				seen[key] = true
		_cells_insert(_poly_cells, low, high, POLY_CELL_METRES, index)
	var owner: PackedInt32Array = PackedInt32Array()
	owner.resize(count)
	for index: int in count:
		owner[index] = index
	var first: Dictionary = {}
	for index: int in count:
		var polygon: PackedInt32Array = _polys[index]
		for corner: int in polygon.size():
			var key: int = _edge_key(polygon[corner], polygon[(corner + 1) % polygon.size()], stride)
			if first.has(key):
				_join(owner, index, int(first[key]))
			else:
				first[key] = index
	_edge_a.clear()
	_edge_b.clear()
	_edge_normal.clear()
	_edge_island.clear()
	_edge_cells.clear()
	for index: int in count:
		var polygon: PackedInt32Array = _polys[index]
		var island: int = _join_root(owner, index)
		var centre: Vector3 = Vector3.ZERO
		for corner: int in polygon:
			centre += _verts[corner]
		centre /= float(polygon.size())
		for corner: int in polygon.size():
			var ia: int = polygon[corner]
			var ib: int = polygon[(corner + 1) % polygon.size()]
			if shared.has(_edge_key(ia, ib, stride)):
				continue
			var a: Vector3 = _verts[ia]
			var b: Vector3 = _verts[ib]
			var along: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
			if along.length_squared() < 0.0001:
				continue
			var normal: Vector3 = Vector3(along.z, 0.0, -along.x).normalized()
			var mid: Vector3 = (a + b) * 0.5
			if normal.dot(centre - mid) > 0.0:
				normal = -normal
			var edge: int = _edge_a.size()
			_edge_a.append(a)
			_edge_b.append(b)
			_edge_normal.append(normal)
			_edge_island.append(island)
			_cells_insert(
				_edge_cells,
				Vector2(minf(a.x, b.x), minf(a.z, b.z)),
				Vector2(maxf(a.x, b.x), maxf(a.z, b.z)),
				POLY_CELL_METRES,
				edge,
			)


static func _edge_key(a: int, b: int, stride: int) -> int:
	return mini(a, b) * stride + maxi(a, b)


static func _join_root(owner: PackedInt32Array, node: int) -> int:
	var cursor: int = node
	while owner[cursor] != cursor:
		owner[cursor] = owner[owner[cursor]]
		cursor = owner[cursor]
	return cursor


static func _join(owner: PackedInt32Array, a: int, b: int) -> void:
	var left: int = _join_root(owner, a)
	var right: int = _join_root(owner, b)
	if left != right:
		owner[right] = left


static func _cells_insert(cells: Dictionary, low: Vector2, high: Vector2, size: float, item: int) -> void:
	for cx: int in range(floori(low.x / size), floori(high.x / size) + 1):
		for cz: int in range(floori(low.y / size), floori(high.y / size) + 1):
			var cell: Vector2i = Vector2i(cx, cz)
			if not cells.has(cell):
				cells[cell] = PackedInt32Array()
			var list: PackedInt32Array = cells[cell]
			list.append(item)
			cells[cell] = list


## Mesh height under [param point]'s XZ nearest [param point].y, or NAN when no polygon is there.
func height_at(point: Vector3) -> float:
	var cell: Vector2i = Vector2i(floori(point.x / POLY_CELL_METRES), floori(point.z / POLY_CELL_METRES))
	if not _poly_cells.has(cell):
		return NAN
	var best: float = NAN
	var best_gap: float = LAND_HEIGHT_TOLERANCE_METRES
	for index: int in _poly_cells[cell] as PackedInt32Array:
		var polygon: PackedInt32Array = _polys[index]
		if not _inside_polygon(polygon, point.x, point.z):
			continue
		var height: float = _plane_height(polygon, point.x, point.z)
		var gap: float = absf(height - point.y)
		if gap < best_gap:
			best_gap = gap
			best = height
	return best


func _inside_polygon(polygon: PackedInt32Array, x: float, z: float) -> bool:
	var sign_seen: float = 0.0
	for corner: int in polygon.size():
		var a: Vector3 = _verts[polygon[corner]]
		var b: Vector3 = _verts[polygon[(corner + 1) % polygon.size()]]
		var cross: float = (b.x - a.x) * (z - a.z) - (b.z - a.z) * (x - a.x)
		if absf(cross) <= 0.000001:
			continue
		if sign_seen == 0.0:
			sign_seen = signf(cross)
		elif signf(cross) != sign_seen:
			return false
	return true


func _plane_height(polygon: PackedInt32Array, x: float, z: float) -> float:
	var a: Vector3 = _verts[polygon[0]]
	var b: Vector3 = _verts[polygon[1]]
	var c: Vector3 = _verts[polygon[2]]
	var normal: Vector3 = (b - a).cross(c - a)
	if absf(normal.y) < 0.0001:
		return a.y
	return a.y - (normal.x * (x - a.x) + normal.z * (z - a.z)) / normal.y


## Metres from [param point] to the nearest mesh boundary edge in XZ, capped at [param cap].
func boundary_distance(point: Vector3, cap: float = 4.0) -> float:
	var best: float = cap
	var flat: Vector2 = Vector2(point.x, point.z)
	var reach: int = ceili(cap / POLY_CELL_METRES)
	var cx: int = floori(point.x / POLY_CELL_METRES)
	var cz: int = floori(point.z / POLY_CELL_METRES)
	for dx: int in range(-reach, reach + 1):
		for dz: int in range(-reach, reach + 1):
			var cell: Vector2i = Vector2i(cx + dx, cz + dz)
			if not _edge_cells.has(cell):
				continue
			for edge: int in _edge_cells[cell] as PackedInt32Array:
				var a: Vector3 = _edge_a[edge]
				var b: Vector3 = _edge_b[edge]
				if absf(a.y - point.y) > LAND_HEIGHT_TOLERANCE_METRES:
					continue
				var near: Vector2 = Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
				best = minf(best, near.distance_to(flat))
	return best


# --- Drops --------------------------------------------------------------------

## True when a static floor lies under [param point] within the probe depth.
func _floor_under(point: Vector3) -> Vector3:
	if _space == null:
		return point
	_ray.from = point + Vector3.UP * (AGENT_MAX_CLIMB + 0.1)
	_ray.to = point + Vector3.DOWN * DROP_PROBE_DEPTH_METRES
	var hit: Dictionary = _space.intersect_ray(_ray)
	return hit.get("position", Vector3.INF) if not hit.is_empty() else Vector3.INF


## Carve a strip inboard of every mesh edge with nothing beyond it, so a body
## steering along the mesh never runs off a deck. Returns the edges carved.
func _carve_drops(source: NavigationMeshSourceGeometryData3D, into_root: Transform3D) -> int:
	if _space == null:
		return 0
	var carved: int = 0
	for edge: int in _edge_a.size():
		var a: Vector3 = _edge_a[edge]
		var b: Vector3 = _edge_b[edge]
		var normal: Vector3 = _edge_normal[edge]
		var mid: Vector3 = (a + b) * 0.5
		if not _is_drop_beyond(mid, normal):
			continue
		var quad: PackedVector3Array = PackedVector3Array([
			into_root * (a - normal * DROP_MARGIN_METRES),
			into_root * (b - normal * DROP_MARGIN_METRES),
			into_root * (b + normal * AGENT_RADIUS),
			into_root * (a + normal * AGENT_RADIUS),
		])
		source.add_projected_obstruction(quad, (into_root * mid).y - 1.0, 3.0, true)
		carved += 1
	return carved


# --- Links --------------------------------------------------------------------

func _build_links(root: Node) -> void:
	for link: Link in _links:
		if link.node != null:
			link.node.queue_free()
	_links.clear()
	_link_by_owner.clear()
	_jumps = 0
	_pads = 0
	_build_pad_links(root)
	_build_jump_links()


static func _collect_pads(node: Node, pads: Array[BoostPad]) -> void:
	var pad: BoostPad = node as BoostPad
	if pad != null:
		pads.append(pad)
	for child: Node in node.get_children():
		_collect_pads(child, pads)


## Where a body running onto [param pad] along its axis first trips it: the plate's back edge.
static func pad_takeoff(pad: BoostPad) -> Vector3:
	var flat: Vector3 = pad.get_launch_velocity()
	flat.y = 0.0
	if flat.length() < 0.001:
		return pad.global_position
	return pad.global_position - flat.normalized() * pad.footprint_metres.z * 0.5


## The flight from [param start] at [param velocity], one point per physics tick,
## pushing forward the way a runner does: air friction, air acceleration, gravity.
func simulate_flight(start: Vector3, velocity: Vector3) -> PackedVector3Array:
	var dt: float = 1.0 / 60.0
	var friction: float = _movement.air_friction if _movement != null else 0.0
	var stop_speed: float = _movement.friction_stop_speed if _movement != null else 0.0
	var max_air: float = _movement.max_air_speed if _movement != null else 0.0
	var air_accel: float = _movement.air_acceleration if _movement != null else 0.0
	var arc: PackedVector3Array = PackedVector3Array()
	var point: Vector3 = start
	var v: Vector3 = velocity
	for tick: int in int(PAD_MAX_FLIGHT_SECONDS * 60.0):
		var flat: Vector3 = Vector3(v.x, 0.0, v.z)
		var speed: float = flat.length()
		if friction > 0.0 and speed > 0.001:
			var control: float = maxf(speed, stop_speed)
			var scale: float = maxf(speed - control * friction * dt, 0.0) / speed
			flat *= scale
			speed *= scale
		if speed > 0.001 and max_air > speed:
			flat += flat / speed * minf(air_accel * max_air * dt, max_air - speed)
		v = Vector3(flat.x, v.y - _gravity * dt, flat.z)
		point += v * dt
		arc.append(point)
	return arc


## Where a pad's ballistic arc first meets the world, or Vector3.INF when it hits nothing.
func _pad_ballistic_landing(pad: BoostPad) -> Vector3:
	if _space == null:
		return Vector3.INF
	var start: Vector3 = pad_takeoff(pad)
	var previous: Vector3 = start + Vector3.UP * 0.2
	var lowest: float = start.y - 40.0
	for point: Vector3 in simulate_flight(start, pad.get_launch_velocity()):
		var lifted: Vector3 = point + Vector3.UP * 0.2
		_ray.from = previous
		_ray.to = lifted
		var hit: Dictionary = _space.intersect_ray(_ray)
		if not hit.is_empty():
			return hit["position"]
		if point.y < lowest:
			break
		previous = lifted
	return Vector3.INF


## True when [param point] stands on a pad's plate, plus [param margin]: a landing there fires it.
func _on_pad(point: Vector3, margin: float) -> bool:
	for pad: BoostPad in _all_pads:
		if not is_instance_valid(pad):
			continue
		var local: Vector3 = pad.global_transform.affine_inverse() * point
		var half: Vector3 = pad.footprint_metres * 0.5
		if absf(local.x) <= half.x + margin and absf(local.z) <= half.z + margin and absf(local.y) <= half.y + 1.0:
			return true
	return false


## A mesh point the flight can be steered onto near [param landing] along
## [param direction]: not lethal, clear of every mesh edge, and short of the
## ballistic point rather than past it, since air control brakes better than it adds.
func _steerable_landing(landing: Vector3, direction: Vector3) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_cost: float = INF
	var back: int = int(PAD_LAND_SEARCH_METRES / JUMP_STEP_METRES)
	var forward: int = int(PAD_LAND_REACH_METRES / JUMP_STEP_METRES)
	for index: int in range(-back, forward + 1):
		var along: float = float(index) * JUMP_STEP_METRES
		var probe: Vector3 = landing + direction * along
		var height: float = height_at(probe)
		if is_nan(height):
			continue
		var point: Vector3 = Vector3(probe.x, height, probe.z)
		if is_lethal(point, 0.3):
			continue
		var margin: float = boundary_distance(point, PAD_LAND_MARGIN_METRES)
		if margin < LAND_MARGIN_METRES:
			continue
		var cost: float = absf(along) * (3.0 if along > 0.0 else 1.0) + (PAD_LAND_MARGIN_METRES - margin) * 2.0
		if cost < best_cost:
			best_cost = cost
			best = point
	return best


func _build_pad_links(root: Node) -> void:
	var pads: Array[BoostPad] = []
	_collect_pads(root, pads)
	for pad: BoostPad in pads:
		if _dead_pads.has(pad):
			continue
		var start: Vector3 = pad_takeoff(pad)
		var ballistic: Vector3 = _pad_ballistic_landing(pad)
		if not is_finite(ballistic.x):
			continue
		var flat: Vector3 = pad.get_launch_velocity()
		flat.y = 0.0
		var direction: Vector3 = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
		var end: Vector3 = _steerable_landing(ballistic, direction)
		if not is_finite(end.x):
			continue
		var link: Link = _add_link(LinkKind.PAD, start, end, flat.length(), LAYER_PAD, PAD_TRAVEL_COST)
		link.pad = pad
		_pads += 1


## Pads whose flight lands nowhere are obstacles: carve the plate out of the mesh.
func _carve_dead_pads(root: Node, source: NavigationMeshSourceGeometryData3D, into_root: Transform3D) -> int:
	var pads: Array[BoostPad] = []
	_collect_pads(root, pads)
	var dead: int = 0
	for pad: BoostPad in pads:
		var ballistic: Vector3 = _pad_ballistic_landing(pad)
		var flat: Vector3 = pad.get_launch_velocity()
		flat.y = 0.0
		var direction: Vector3 = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
		if is_finite(ballistic.x) and is_finite(_steerable_landing(ballistic, direction).x):
			continue
		_dead_pads.append(pad)
		var half: Vector3 = pad.footprint_metres * 0.5 + Vector3.ONE * PAD_CARVE_MARGIN_METRES
		var world: Transform3D = pad.global_transform
		var corners: PackedVector3Array = PackedVector3Array()
		for corner: Vector3 in [
			Vector3(-half.x, 0.0, -half.z), Vector3(half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, half.z), Vector3(-half.x, 0.0, half.z),
		]:
			corners.append(into_root * (world * corner))
		source.add_projected_obstruction(corners, (into_root * pad.global_position).y - 1.0, 3.0, true)
		dead += 1
	return dead


## Seconds a jump from [param from] spends in the air before landing at [param to]'s height,
## or -1 when the landing is higher than the jump reaches.
func _flight_seconds(from_y: float, to_y: float) -> float:
	var under: float = _jump_speed * _jump_speed - 2.0 * _gravity * (to_y - from_y)
	if under < 0.0:
		return -1.0
	return (_jump_speed + sqrt(under)) / _gravity


## True when the parabola from [param start] at [param speed] towards [param end] hits static geometry.
func _jump_blocked(start: Vector3, end: Vector3, seconds: float) -> bool:
	var previous: Vector3 = start
	for index: int in range(1, ARC_SAMPLES + 1):
		var t: float = seconds * float(index) / float(ARC_SAMPLES)
		var point: Vector3 = start.lerp(end, t / seconds)
		point.y = start.y + _jump_speed * t - 0.5 * _gravity * t * t
		if index < ARC_SAMPLES and is_lethal(point):
			return true
		if _arc_blocked(previous, point):
			return true
		previous = point
	return false


## True when a body flying the leg [param a]→[param b] (feet positions) would strike static geometry.
func _arc_blocked(a: Vector3, b: Vector3) -> bool:
	if _space == null:
		return false
	_body.transform = Transform3D(Basis.IDENTITY, a + Vector3.UP * (BODY_HEIGHT_METRES * 0.5 + ARC_LIFT_METRES))
	_body.motion = b - a
	var motion: PackedFloat32Array = _space.cast_motion(_body)
	return motion.size() >= 2 and motion[1] < 1.0


## One jump link per mesh edge sample that has a drop or lava beyond it and mesh in reach.
func _build_jump_links() -> void:
	for edge: int in _edge_a.size():
		if _links.size() >= LINK_MAX:
			break
		var a: Vector3 = _edge_a[edge]
		var b: Vector3 = _edge_b[edge]
		var normal: Vector3 = _edge_normal[edge]
		var length: float = Vector2(b.x - a.x, b.z - a.z).length()
		var samples: int = maxi(int(length / EDGE_SAMPLE_METRES), 1)
		for sample: int in samples:
			var mid: Vector3 = a.lerp(b, (float(sample) + 0.5) / float(samples))
			if not _is_gap_beyond(mid, normal):
				continue
			var takeoff: Vector3 = mid - normal * TAKEOFF_INSET_METRES
			var height: float = height_at(takeoff)
			if is_nan(height):
				continue
			takeoff.y = height
			_try_jump(takeoff, normal)
			for target: Vector3 in _foreign_edges_near(mid, _edge_island[edge], normal):
				var direction: Vector3 = Vector3(target.x - mid.x, 0.0, target.z - mid.z).normalized()
				_try_jump(takeoff, direction)


## Midpoints of other islands' boundary edges within jump reach in front of [param normal].
func _foreign_edges_near(from: Vector3, island: int, normal: Vector3) -> PackedVector3Array:
	var found: PackedVector3Array = PackedVector3Array()
	var span: int = ceili(JUMP_MAX_METRES / POLY_CELL_METRES)
	var cx: int = floori(from.x / POLY_CELL_METRES)
	var cz: int = floori(from.z / POLY_CELL_METRES)
	for dx: int in range(-span, span + 1):
		for dz: int in range(-span, span + 1):
			var cell: Vector2i = Vector2i(cx + dx, cz + dz)
			if not _edge_cells.has(cell):
				continue
			for edge: int in _edge_cells[cell] as PackedInt32Array:
				if _edge_island[edge] == island:
					continue
				var mid: Vector3 = (_edge_a[edge] + _edge_b[edge]) * 0.5
				var offset: Vector3 = Vector3(mid.x - from.x, 0.0, mid.z - from.z)
				if absf(mid.y - from.y) > LAND_HEIGHT_TOLERANCE_METRES or offset.length() > JUMP_MAX_METRES:
					continue
				if offset.normalized().dot(normal) < 0.3:
					continue
				found.append(mid)
	return found


## True when any of the probes past [param mid] along [param normal] finds no floor.
func _is_drop_beyond(mid: Vector3, normal: Vector3) -> bool:
	for step: int in range(1, DROP_PROBES + 1):
		var probe: Vector3 = mid + normal * (DROP_PROBE_METRES * float(step))
		if not is_finite(_floor_under(probe).x):
			return true
	return false


## True when the ground past [param mid] along [param normal] is missing or lethal.
func _is_gap_beyond(mid: Vector3, normal: Vector3) -> bool:
	for step: int in range(1, DROP_PROBES + 1):
		var probe: Vector3 = mid + normal * (DROP_PROBE_METRES * float(step))
		var floor_point: Vector3 = _floor_under(probe)
		if not is_finite(floor_point.x):
			return true
		if is_lethal(floor_point):
			return true
	return false


## Find the first mesh past the gap along [param direction] and link a jump onto it.
func _try_jump(takeoff: Vector3, direction: Vector3) -> void:
	var run_from: float = -1.0
	var run_to: float = -1.0
	var run_height: float = 0.0
	var along: float = JUMP_MIN_METRES
	while along <= JUMP_MAX_METRES:
		var probe: Vector3 = takeoff + direction * along
		var height: float = height_at(probe)
		if not is_nan(height) and not is_lethal(Vector3(probe.x, height, probe.z), 0.3):
			if run_from < 0.0:
				run_from = along
				run_height = height
			run_to = along
		elif run_from >= 0.0:
			break
		along += JUMP_STEP_METRES
	if run_from < 0.0:
		return
	var landing: Vector3 = Vector3.INF
	for candidate: float in [run_from + LAND_MARGIN_METRES + 0.1, (run_from + run_to) * 0.5]:
		var probe: Vector3 = takeoff + direction * candidate
		var height: float = height_at(Vector3(probe.x, run_height, probe.z))
		if is_nan(height):
			continue
		var point: Vector3 = Vector3(probe.x, height, probe.z)
		if boundary_distance(point, 1.0) >= LAND_MARGIN_METRES and not _on_pad(point, PAD_CLEARANCE_METRES):
			landing = point
			break
	if not is_finite(landing.x):
		return
	var takeoff_floor: Vector3 = _floor_under(takeoff)
	var landing_floor: Vector3 = _floor_under(landing)
	if is_finite(takeoff_floor.x):
		takeoff.y = takeoff_floor.y
	if is_finite(landing_floor.x):
		landing.y = landing_floor.y
	var seconds: float = _flight_seconds(takeoff.y, landing.y)
	if seconds <= 0.0:
		return
	var distance: float = Vector2(landing.x - takeoff.x, landing.z - takeoff.z).length()
	var speed: float = distance / seconds
	if speed > _run_speed or speed < JUMP_MIN_SPEED:
		return
	if _duplicate_link(takeoff, landing) or not _crosses_gap(takeoff, landing) or _jump_blocked(takeoff, landing, seconds):
		return
	var hard: bool = speed > _run_speed * JUMP_SLOW_FRACTION
	_add_link(
		LinkKind.JUMP, takeoff, landing, speed,
		LAYER_HARD_JUMP if hard else LAYER_EASY_JUMP,
		HARD_JUMP_TRAVEL_COST if hard else JUMP_TRAVEL_COST,
	)
	_jumps += 1


## True when the straight line between the ends passes over ground with no mesh and no safe floor.
func _crosses_gap(start: Vector3, end: Vector3) -> bool:
	for index: int in range(1, GAP_SAMPLES):
		var point: Vector3 = start.lerp(end, float(index) / float(GAP_SAMPLES))
		if not is_nan(height_at(point)):
			continue
		var floor_point: Vector3 = _floor_under(point)
		if not is_finite(floor_point.x) or is_lethal(floor_point):
			return true
	return false


func _duplicate_link(start: Vector3, end: Vector3) -> bool:
	for link: Link in _links:
		if Vector2(link.start.x - start.x, link.start.z - start.z).length() <= LINK_DEDUPE_METRES \
			and Vector2(link.end.x - end.x, link.end.z - end.z).length() <= LINK_DEDUPE_METRES:
			return true
	return false


func _add_link(kind: LinkKind, start: Vector3, end: Vector3, speed: float, layers: int, cost: float) -> Link:
	var link: Link = Link.new()
	link.kind = kind
	link.start = start
	link.end = end
	link.speed = speed
	link.direction = Vector3(end.x - start.x, 0.0, end.z - start.z).normalized()
	var node: NavigationLink3D = NavigationLink3D.new()
	node.name = "Link%d" % _links.size()
	node.bidirectional = false
	node.travel_cost = cost
	node.navigation_layers = layers
	var into_root: Transform3D = _root_transform.affine_inverse()
	node.start_position = into_root * start
	node.end_position = into_root * end
	add_child(node)
	link.node = node
	_links.append(link)
	_link_by_owner[node.get_instance_id()] = _links.size() - 1
	return link


## The pad link whose plate a body at [param point] stands on or has just left, or null.
func pad_link_near(point: Vector3, reach: float = 3.0) -> Link:
	for link: Link in _links:
		if link.kind != LinkKind.PAD or link.pad == null or not is_instance_valid(link.pad):
			continue
		var plate: Vector3 = link.pad.global_position
		if absf(point.y - plate.y) <= reach and Vector2(point.x - plate.x, point.z - plate.z).length() <= reach:
			return link
	return null


# --- Cover --------------------------------------------------------------------

## A point on the mesh every ~1.5 m is cover when the guard's eye cannot see a body there.
func _sample_cover() -> void:
	_cover.clear()
	_cover_facing.clear()
	_cover_cells.clear()
	if _space == null or _verts.is_empty():
		return
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for vertex: Vector3 in _verts:
		low = Vector2(minf(low.x, vertex.x), minf(low.y, vertex.z))
		high = Vector2(maxf(high.x, vertex.x), maxf(high.y, vertex.z))
	var columns: int = int((high.x - low.x) / COVER_SPACING_METRES) + 1
	var rows: int = int((high.y - low.y) / COVER_SPACING_METRES) + 1
	var buckets: Dictionary = {}
	for vertex: Vector3 in _verts:
		buckets[roundi(vertex.y)] = true
	var heights: PackedFloat32Array = PackedFloat32Array()
	for bucket: int in buckets:
		heights.append(float(bucket))
	for column: int in columns:
		for row: int in rows:
			var x: float = low.x + (float(column) + 0.5) * COVER_SPACING_METRES
			var z: float = low.y + (float(row) + 0.5) * COVER_SPACING_METRES
			var used: float = NAN
			for deck: float in heights:
				var height: float = height_at(Vector3(x, deck, z))
				if is_nan(height) or (not is_nan(used) and absf(height - used) < 0.01):
					continue
				used = height
				var point: Vector3 = Vector3(x, height, z)
				if is_lethal(point, COVER_LETHAL_CLEARANCE_METRES):
					continue
				if _sight_clear(point + Vector3.UP * COVER_CHEST_METRES) or _sight_clear(point + Vector3.UP * COVER_HEAD_METRES):
					continue
				var index: int = _cover.size()
				_cover.append(point)
				_cover_facing.append(Vector3(_eye.x - x, 0.0, _eye.z - z).normalized())
				_cells_insert(_cover_cells, Vector2(x, z), Vector2(x, z), COVER_CELL_METRES, index)


func _sight_clear(target: Vector3) -> bool:
	_sight.from = _eye
	_sight.to = target
	return _space.intersect_ray(_sight).is_empty()


## The nearest cover point to [param from] that lies ahead along [param forward]
## within [param reach] metres and is not within a body's width of any point in
## [param taken], as an index into [method cover_point], or -1.
func nearest_cover_ahead(from: Vector3, forward: Vector3, reach: float, taken: PackedVector3Array) -> int:
	var best: int = -1
	var best_distance: float = reach
	var span: int = ceili(reach / COVER_CELL_METRES)
	var cx: int = floori(from.x / COVER_CELL_METRES)
	var cz: int = floori(from.z / COVER_CELL_METRES)
	for dx: int in range(-span, span + 1):
		for dz: int in range(-span, span + 1):
			var cell: Vector2i = Vector2i(cx + dx, cz + dz)
			if not _cover_cells.has(cell):
				continue
			for index: int in _cover_cells[cell] as PackedInt32Array:
				var point: Vector3 = _cover[index]
				var offset: Vector3 = Vector3(point.x - from.x, 0.0, point.z - from.z)
				if absf(point.y - from.y) > LAND_HEIGHT_TOLERANCE_METRES or offset.dot(forward) < 0.0:
					continue
				var distance: float = offset.length()
				if distance >= best_distance or _is_taken(point, taken):
					continue
				best_distance = distance
				best = index
	return best


func _is_taken(point: Vector3, taken: PackedVector3Array) -> bool:
	for other: Vector3 in taken:
		if Vector2(other.x - point.x, other.z - point.z).length() < COVER_TAKEN_METRES:
			return true
	return false


func cover_point(index: int) -> Vector3:
	return _cover[index]


func cover_facing(index: int) -> Vector3:
	return _cover_facing[index]


# --- Queries ------------------------------------------------------------------

## The nearest point on the mesh to [param point].
func snap(point: Vector3) -> Vector3:
	var since: int = Time.get_ticks_usec()
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(get_navigation_map(), point)
	charge("path", since)
	return closest


## The path from [param from] to [param to], or empty when the mesh does not reach [param to].
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var since: int = Time.get_ticks_usec()
	var key: int = _path_key(from, to)
	if key >= 0:
		var tick: int = Engine.get_physics_frames()
		if _path_cache_tick < 0 or tick - _path_cache_tick >= PATH_CACHE_TICKS \
				or _path_cache.size() >= PATH_CACHE_MAX:
			_path_cache.clear()
			_path_cache_tick = tick
		elif _path_cache.has(key):
			charge("path", since)
			return _path_cache[key]
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_navigation_map(), from, to, true)
	if not path.is_empty():
		var last: Vector3 = path[path.size() - 1]
		if Vector2(last.x - to.x, last.z - to.z).length() > REACH_TOLERANCE_METRES:
			path = PackedVector3Array()
	if key >= 0:
		_path_cache[key] = path
	charge("path", since)
	return path


## The path from [param from] to [param to] with its links, written into [param out].
## [param layers] picks which links may be taken. Returns false when nothing reaches.
func plan(from: Vector3, to: Vector3, layers: int, out: RingPath) -> bool:
	var since: int = Time.get_ticks_usec()
	_query.map = get_navigation_map()
	_query.start_position = from
	_query.target_position = to
	_query.navigation_layers = layers
	_query.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES \
		| NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_OWNERS
	NavigationServer3D.query_path(_query, _result)
	var path: PackedVector3Array = _result.path
	out.clear()
	if path.is_empty():
		charge("path", since)
		return false
	var last: Vector3 = path[path.size() - 1]
	if Vector2(last.x - to.x, last.z - to.z).length() > REACH_TOLERANCE_METRES:
		charge("path", since)
		return false
	var types: PackedInt32Array = _result.path_types
	var owners: PackedInt64Array = _result.path_owner_ids
	for index: int in path.size():
		var link: int = -1
		if types[index] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			link = int(_link_by_owner.get(owners[index], -1))
		out.append(path[index], link)
	charge("path", since)
	return true


static func _path_key(from: Vector3, to: Vector3) -> int:
	var a: int = _path_cell(from)
	var b: int = _path_cell(to)
	return -1 if a < 0 or b < 0 else (a << 26) | b


static func _path_cell(point: Vector3) -> int:
	var x: int = int(floor(point.x / PATH_CACHE_CELL_METRES)) + 256
	var y: int = int(floor(point.y / PATH_CACHE_CELL_METRES)) + 128
	var z: int = int(floor(point.z / PATH_CACHE_CELL_METRES)) + 256
	if x < 0 or x > 511 or y < 0 or y > 255 or z < 0 or z > 511:
		return -1
	return (x << 17) | (y << 9) | z


## Metres along [param path] in the horizontal plane.
static func path_length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for index: int in range(1, path.size()):
		var a: Vector3 = path[index - 1]
		var b: Vector3 = path[index]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total


func get_link(index: int) -> Link:
	return _links[index]
