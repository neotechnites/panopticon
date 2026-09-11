class_name RingNavigation
extends NavigationRegion3D

## A navmesh baked at match start from the level's static colliders, with every
## [TrapVolume] carved out. One per level root; see [method ensure].

const NODE_NAME: StringName = &"RingNavigation"
const AGENT_RADIUS: float = 0.75
## Whole cell_height multiples: the baker rounds them anyway and warns otherwise.
const AGENT_HEIGHT: float = 2.0
const AGENT_MAX_CLIMB: float = 0.5
const AGENT_MAX_SLOPE_DEGREES: float = 40.0
const CELL_SIZE: float = 0.25
const CELL_HEIGHT: float = 0.25
## Widened from 0.6: the demon-run stretch's lava bands leave only ~6 m of clear
## lane, and the baked path there funnelled a corner tight enough (r ~50.4,
## against the inner band's raw edge at r ~50.1) that a runner's own steering
## overshoot walked it straight into the lava. 1.1 keeps the lane open while
## pushing the funnel's corner-cut clear of the raw hazard box.
const HAZARD_INFLATION_METRES: float = 1.1
const HAZARD_VERTICAL_MARGIN_METRES: float = 1.0
## Deck edges are carved this far inboard of a level's authored inner/outer radius.
const EDGE_MARGIN_METRES: float = 1.0
const EDGE_SEGMENTS: int = 48
const EDGE_REACH_METRES: float = 8.0
## How far a path's last point may stop short of the asked-for point and still count as reaching it.
const REACH_TOLERANCE_METRES: float = 1.5
const STATIC_COLLIDER_MASK: int = 1

var _polygons: int = 0
var _bake_ms: int = 0
var _synced: bool = false

## Regions by level-root instance id; the tree cannot be asked while the root is still readying.
static var _by_root: Dictionary = {}


## The navmesh under [param level_root], baked now if this is the first ask.
static func ensure(
	level_root: Node, bounds: AABB = AABB(), route: RingRoute = null, centre: Vector3 = Vector3.ZERO
) -> RingNavigation:
	if level_root == null:
		return null
	var key: int = level_root.get_instance_id()
	var cached: RingNavigation = _by_root.get(key, null) as RingNavigation
	if cached != null and is_instance_valid(cached):
		return cached
	var existing: RingNavigation = level_root.get_node_or_null(NodePath(NODE_NAME)) as RingNavigation
	if existing != null:
		_by_root[key] = existing
		return existing
	var region: RingNavigation = RingNavigation.new()
	region.name = NODE_NAME
	_by_root[key] = region
	region.bake_from(level_root, bounds, route, centre)
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


## Parse [param root]'s static colliders, carve traps and deck edges, bake synchronously.
func bake_from(
	root: Node, bounds: AABB = AABB(), route: RingRoute = null, centre: Vector3 = Vector3.ZERO
) -> void:
	var started: int = Time.get_ticks_msec()
	var into_root: Transform3D = Transform3D.IDENTITY
	var root_3d: Node3D = root as Node3D
	if root_3d != null:
		into_root = root_3d.global_transform.affine_inverse()

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
	if bounds.has_volume():
		mesh.filter_baking_aabb = into_root * bounds

	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	var carved: int = _carve_traps(root, source, into_root)
	var edges: int = _carve_edges(route, centre, source, into_root)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navigation_mesh = mesh
	_polygons = mesh.get_polygon_count()
	_bake_ms = Time.get_ticks_msec() - started
	print("RingNavigation: baked %d polygons, %d traps and %d deck edges carved, in %d ms" % [_polygons, carved, edges, _bake_ms])


func get_polygon_count() -> int:
	return _polygons


func get_bake_milliseconds() -> int:
	return _bake_ms


## True once the baked mesh answers map queries. Map iterations build asynchronously,
## so the iteration id alone lies for a few ticks; a known vertex must snap to itself.
func is_ready() -> bool:
	if _synced:
		return true
	if _polygons <= 0 or not is_inside_tree():
		return false
	var map: RID = get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) <= 0:
		return false
	var vertex: Vector3 = navigation_mesh.get_vertices()[0]
	_synced = NavigationServer3D.map_get_closest_point(map, vertex).distance_to(vertex) < 0.05
	return _synced


## The nearest point on the mesh to [param point].
func snap(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_navigation_map(), point)


## The path from [param from] to [param to], or empty when the mesh does not reach [param to].
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_navigation_map(), from, to, true)
	if path.is_empty():
		return path
	var last: Vector3 = path[path.size() - 1]
	if Vector2(last.x - to.x, last.z - to.z).length() > REACH_TOLERANCE_METRES:
		return PackedVector3Array()
	return path


## Metres along [param path] in the horizontal plane.
static func path_length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for index: int in range(1, path.size()):
		var a: Vector3 = path[index - 1]
		var b: Vector3 = path[index]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total


func _carve_traps(node: Node, source: NavigationMeshSourceGeometryData3D, into_root: Transform3D) -> int:
	var carved: int = 0
	var trap: TrapVolume = node as TrapVolume
	if trap != null:
		var half: Vector3 = trap.size_metres * 0.5
		var hx: float = half.x + HAZARD_INFLATION_METRES
		var hz: float = half.z + HAZARD_INFLATION_METRES
		var world: Transform3D = trap.global_transform
		var corners: PackedVector3Array = PackedVector3Array()
		for corner: Vector3 in [
			Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz)
		]:
			corners.append(into_root * (world * corner))
		var bottom: float = (into_root * (world * Vector3(0.0, -half.y, 0.0))).y
		source.add_projected_obstruction(
			corners,
			bottom - HAZARD_VERTICAL_MARGIN_METRES,
			trap.size_metres.y + 2.0 * HAZARD_VERTICAL_MARGIN_METRES,
			true,
		)
		carved += 1
	for child: Node in node.get_children():
		carved += _carve_traps(child, source, into_root)
	return carved


## Carve the pit inside each level's inner radius and the drop past its outer one.
func _carve_edges(
	route: RingRoute, centre: Vector3, source: NavigationMeshSourceGeometryData3D, into_root: Transform3D
) -> int:
	if route == null:
		return 0
	var carved: int = 0
	for level: RingLevel in route.get_levels():
		var elevation: float = (into_root * Vector3(centre.x, level.deck_height, centre.z)).y - 1.0
		if level.inner_radius > 0.0:
			var disc: PackedVector3Array = PackedVector3Array()
			for index: int in EDGE_SEGMENTS:
				var angle: float = TAU * float(index) / float(EDGE_SEGMENTS)
				disc.append(into_root * _ring_point(centre, angle, level.inner_radius + EDGE_MARGIN_METRES, level.deck_height))
			source.add_projected_obstruction(disc, elevation, 3.0, true)
			carved += 1
		if level.outer_radius > 0.0 and level.outer_radius < level.lane_radius * 2.5:
			var near: float = level.outer_radius - EDGE_MARGIN_METRES
			var far: float = level.outer_radius + EDGE_REACH_METRES
			for index: int in EDGE_SEGMENTS:
				var a: float = TAU * float(index) / float(EDGE_SEGMENTS)
				var b: float = TAU * float(index + 1) / float(EDGE_SEGMENTS)
				var wedge: PackedVector3Array = PackedVector3Array([
					into_root * _ring_point(centre, a, near, level.deck_height),
					into_root * _ring_point(centre, b, near, level.deck_height),
					into_root * _ring_point(centre, b, far, level.deck_height),
					into_root * _ring_point(centre, a, far, level.deck_height),
				])
				source.add_projected_obstruction(wedge, elevation, 3.0, true)
			carved += 1
	return carved


static func _ring_point(centre: Vector3, angle: float, radius: float, height: float) -> Vector3:
	return Vector3(centre.x + cos(angle) * radius, height, centre.z + sin(angle) * radius)
