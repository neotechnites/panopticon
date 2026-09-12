class_name RingNavigation
extends NavigationRegion3D

## A navmesh baked at match start from the level's static colliders, with every
## [TrapVolume] carved out. One per level root; see [method ensure].

const NODE_NAME: StringName = &"RingNavigation"
## Every baked region joins this group, so [PhaseGate] can ask for a rebake
## without a [NodePath] to it.
const GROUP: StringName = &"ring_navigation"
const AGENT_RADIUS: float = 0.75
## Whole cell_height multiples: the baker rounds them anyway and warns otherwise.
const AGENT_HEIGHT: float = 2.0
const AGENT_MAX_CLIMB: float = 0.25
const AGENT_MAX_SLOPE_DEGREES: float = 40.0
const CELL_SIZE: float = 0.25
const CELL_HEIGHT: float = 0.25
## Widened from 0.6: the demon-run stretch's lava bands leave only ~6 m of clear
## lane, and the baked path there funnelled a corner tight enough (r ~50.4,
## against the inner band's raw edge at r ~50.1) that a runner's own steering
## overshoot walked it straight into the lava. 1.1 keeps the lane open while
## pushing the funnel's corner-cut clear of the raw hazard box.
const HAZARD_INFLATION_METRES: float = 0.8
const HAZARD_VERTICAL_MARGIN_METRES: float = 1.0
## How far above a trap's own base the carve reaches. A trap poisons the floor it sits on;
## anything standing higher than this is a platform in it, and keeps its navmesh.
const HAZARD_CARVE_ABOVE_METRES: float = 0.4
## Deck edges are carved this far inboard of a level's authored inner/outer radius.
const EDGE_MARGIN_METRES: float = 1.0
const EDGE_SEGMENTS: int = 48
const EDGE_REACH_METRES: float = 8.0
## How far a path's last point may stop short of the asked-for point and still count as reaching it.
const REACH_TOLERANCE_METRES: float = 1.5
const STATIC_COLLIDER_MASK: int = 1

## Boost pads become NavigationLink3Ds to their ballistic landing point.
const LINK_TRAVEL_COST: float = 0.5
const LINK_SAMPLE_SECONDS: float = 0.05
const LINK_MAX_FLIGHT_SECONDS: float = 6.0
const LINK_SNAP_METRES: float = 4.0
const LINK_LAND_TOLERANCE_METRES: float = 0.4
const PAD_CARVE_MARGIN_METRES: float = 0.5
const DEFAULT_GRAVITY: float = 22.0

## Islands the carve leaves over a hazard -- platform tops in a lava lake, and the shores
## either side -- are joined by a NavigationLink3D wherever the body's jump reaches.
const JUMP_LINK_MAX: int = 48
const JUMP_MIN_METRES: float = 1.2
const JUMP_MAX_DROP_METRES: float = 2.5
## Fraction of the ballistic reach a link may ask for, and metres of apex kept in hand.
const JUMP_REACH_SAFETY: float = 0.85
const JUMP_RISE_CLEARANCE_METRES: float = 0.15
## A link end sits this far inside its polygon, so a landing aims at the platform, not its lip.
const JUMP_LINK_INSET_METRES: float = 0.5
## Boundary edges further than this from a carved trap footprint are never linked.
const JUMP_HAZARD_REACH_METRES: float = 6.0
const JUMP_HAZARD_HEIGHT_METRES: float = 4.0
const JUMP_LINK_TRAVEL_COST: float = 1.0
const JUMP_LINK_MATCH_METRES: float = 1.2

var _polygons: int = 0
var _bake_ms: int = 0
var _synced: bool = false

## The arguments of the last [method bake_from] call, kept so [method
## phase_geometry_changed] can repeat it.
var _bake_root: Node = null
var _bake_bounds: AABB = AABB()
var _bake_route: RingRoute = null
var _bake_centre: Vector3 = Vector3.ZERO
var _gravity: float = DEFAULT_GRAVITY
var _movement: MovementProfile = null
var _links: Array[NavigationLink3D] = []
var _dead_pads: Array[BoostPad] = []
var _links_refined: bool = false
var _jump_nodes: Array[NavigationLink3D] = []
var _jump_plans: Array[Dictionary] = []
var _hazard_boxes: Array[Dictionary] = []
var _jump_options: Array[Dictionary] = []
var _root_transform: Transform3D = Transform3D.IDENTITY

## Regions by level-root instance id; the tree cannot be asked while the root is still readying.
static var _by_root: Dictionary = {}

## Microseconds spent this tick, by kind ("cover", "path", "bake"); the harness reads and clears it.
static var cost_usec: Dictionary = {}

static func charge(kind: String, since_usec: int) -> void:
	cost_usec[kind] = int(cost_usec.get(kind, 0)) + (Time.get_ticks_usec() - since_usec)


## The navmesh under [param level_root], baked now if this is the first ask.
static func ensure(
	level_root: Node, bounds: AABB = AABB(), route: RingRoute = null, centre: Vector3 = Vector3.ZERO,
	movement: MovementProfile = null,
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
	region._movement = movement
	region._gravity = maxf(movement.get_effective_gravity(), 0.1) if movement != null else DEFAULT_GRAVITY
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


func _ready() -> void:
	add_to_group(GROUP)


## Re-bakes with the arguments of the last [method bake_from] call. [PhaseGate]
## asks for this, deferred, once gated geometry has finished swapping.
func phase_geometry_changed() -> void:
	if _bake_root != null:
		bake_from(_bake_root, _bake_bounds, _bake_route, _bake_centre)


## Parse [param root]'s static colliders, carve traps and deck edges, bake synchronously.
func bake_from(
	root: Node, bounds: AABB = AABB(), route: RingRoute = null, centre: Vector3 = Vector3.ZERO
) -> void:
	_bake_root = root
	_bake_bounds = bounds
	_bake_route = route
	_bake_centre = centre
	_synced = false
	var started_usec: int = Time.get_ticks_usec()
	var started: int = Time.get_ticks_msec()
	var into_root: Transform3D = Transform3D.IDENTITY
	var root_3d: Node3D = root as Node3D
	if root_3d != null:
		into_root = root_3d.global_transform.affine_inverse()
	_root_transform = into_root.affine_inverse()

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
	## No filter_baking_aabb: it was clipping deck-adjacent colliders at the
	## Demon Run and skewing Recast's voxelization into a choke there. The
	## static-collider mask already keeps the parsed set small; bake stayed fast.

	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	var carved: int = _carve_traps(root, source, into_root)
	var edges: int = _carve_edges(route, centre, source, into_root)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navigation_mesh = mesh
	# Pads whose flight lands off the mesh are obstacles: carve them and bake again.
	var dead: int = _carve_dead_pads(root, source, into_root)
	if dead > 0:
		mesh = mesh.duplicate() as NavigationMesh
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		navigation_mesh = mesh
	_build_pad_links(root, into_root)
	var jumps: int = _build_jump_links()
	_polygons = mesh.get_polygon_count()
	_bake_ms = Time.get_ticks_msec() - started
	charge("bake", started_usec)
	print("RingNavigation: baked %d polygons, %d traps, %d deck edges, %d dead pads carved, %d pad links, %d jump links, in %d ms" % [_polygons, carved, edges, dead, _links.size(), jumps, _bake_ms])


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
	if _synced and not _links_refined:
		_links_refined = true
		_refine_pad_links()
		_refine_jump_links()
	return _synced


## The nearest point on the mesh to [param point].
func snap(point: Vector3) -> Vector3:
	var since: int = Time.get_ticks_usec()
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(get_navigation_map(), point)
	charge("path", since)
	return closest


## The path from [param from] to [param to], or empty when the mesh does not reach [param to].
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var since: int = Time.get_ticks_usec()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_navigation_map(), from, to, true)
	charge("path", since)
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
			HAZARD_VERTICAL_MARGIN_METRES + HAZARD_CARVE_ABOVE_METRES,
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


# --- Boost pads ---------------------------------------------------------------

static func _collect_pads(node: Node, pads: Array[BoostPad]) -> void:
	var pad: BoostPad = node as BoostPad
	if pad != null:
		pads.append(pad)
	for child: Node in node.get_children():
		_collect_pads(child, pads)


## The flight from [param start] at [param velocity], one point per physics tick, pushing forward
## the way the runner does: air friction, air acceleration up to max_air_speed, gravity.
func simulate_flight(start: Vector3, velocity: Vector3) -> PackedVector3Array:
	var dt: float = 1.0 / 60.0
	var friction: float = _movement.air_friction if _movement != null else 0.0
	var stop_speed: float = _movement.friction_stop_speed if _movement != null else 0.0
	var max_air: float = _movement.max_air_speed if _movement != null else 0.0
	var air_accel: float = _movement.air_acceleration if _movement != null else 0.0
	var arc: PackedVector3Array = PackedVector3Array()
	var point: Vector3 = start
	var v: Vector3 = velocity
	for tick: int in int(LINK_MAX_FLIGHT_SECONDS * 60.0):
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


## Where a body launched from [param pad] meets the baked mesh, in mesh space, or Vector3.INF.
## The nearest polygon within LINK_SNAP_METRES counts: air control curves the flight onto it.
func _pad_landing(pad: BoostPad, into_root: Transform3D) -> Vector3:
	var arc: PackedVector3Array = simulate_flight(pad.global_position, pad.get_launch_velocity())
	var previous_y: float = -INF
	for world_point: Vector3 in arc:
		var point: Vector3 = into_root * world_point
		var descending: bool = point.y < previous_y
		previous_y = point.y
		if not descending:
			continue
		var nearest: Dictionary = _mesh_nearest(point)
		if not nearest.is_empty() and point.y <= float(nearest["height"]) + LINK_LAND_TOLERANCE_METRES:
			var landing: Vector3 = Vector3(point.x, float(nearest["height"]), point.z)
			if _in_hazard_volume(world_point):
				return Vector3.INF
			return landing
		if point.y < _mesh_lowest() - 5.0:
			break
	return Vector3.INF


var _mesh_low: float = INF

func _mesh_lowest() -> float:
	if is_finite(_mesh_low):
		return _mesh_low
	_mesh_low = INF
	for vertex: Vector3 in navigation_mesh.get_vertices():
		_mesh_low = minf(_mesh_low, vertex.y)
	return _mesh_low


## The mesh polygon nearest [param point] on the XZ plane, within LINK_SNAP_METRES and 1.5 m of height.
func _mesh_nearest(point: Vector3) -> Dictionary:
	var vertices: PackedVector3Array = navigation_mesh.get_vertices()
	var flat: Vector2 = Vector2(point.x, point.z)
	var best: float = LINK_SNAP_METRES
	var best_height: float = NAN
	for index: int in navigation_mesh.get_polygon_count():
		var polygon: PackedInt32Array = navigation_mesh.get_polygon(index)
		if polygon.size() < 3:
			continue
		var height: float = 0.0
		for corner: int in polygon.size():
			height += vertices[polygon[corner]].y
		height /= float(polygon.size())
		if absf(height - point.y) > 1.5:
			continue
		var inside: bool = true
		var sign_seen: float = 0.0
		var edge_distance: float = INF
		for corner: int in polygon.size():
			var a: Vector3 = vertices[polygon[corner]]
			var b: Vector3 = vertices[polygon[(corner + 1) % polygon.size()]]
			var a2: Vector2 = Vector2(a.x, a.z)
			var b2: Vector2 = Vector2(b.x, b.z)
			edge_distance = minf(edge_distance, Geometry2D.get_closest_point_to_segment(flat, a2, b2).distance_to(flat))
			var cross: float = (b2.x - a2.x) * (flat.y - a2.y) - (b2.y - a2.y) * (flat.x - a2.x)
			if absf(cross) > 0.000001:
				if sign_seen == 0.0:
					sign_seen = signf(cross)
				elif signf(cross) != sign_seen:
					inside = false
		var distance: float = 0.0 if inside else edge_distance
		if distance < best or (distance == best and is_nan(best_height)):
			best = distance
			best_height = height
			if inside:
				break
	if is_nan(best_height):
		return {}
	return {"distance": best, "height": best_height}


var _hazard_volumes: Array[Node3D] = []

func _collect_hazard_volumes(node: Node) -> void:
	if node is TrapVolume or node is KillVolume:
		_hazard_volumes.append(node as Node3D)
	for child: Node in node.get_children():
		_collect_hazard_volumes(child)


## True when a world point is inside a TrapVolume box or a KillVolume cylinder (with a small margin).
func _in_hazard_volume(world_point: Vector3) -> bool:
	for volume: Node3D in _hazard_volumes:
		var trap: TrapVolume = volume as TrapVolume
		if trap != null:
			var local: Vector3 = trap.global_transform.affine_inverse() * world_point
			var half: Vector3 = trap.size_metres * 0.5 + Vector3(0.3, 0.5, 0.3)
			if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
				return true
			continue
		var pit: KillVolume = volume as KillVolume
		if pit != null:
			var local: Vector3 = pit.global_transform.affine_inverse() * world_point
			var top: float = -pit.roof_depth_metres + 1.0
			var bottom: float = -pit.roof_depth_metres - pit.depth_metres
			if Vector2(local.x, local.z).length() <= pit.radius_metres and local.y <= top and local.y >= bottom:
				return true
	return false


func _carve_dead_pads(root: Node, source: NavigationMeshSourceGeometryData3D, into_root: Transform3D) -> int:
	_mesh_low = INF
	_hazard_volumes.clear()
	_collect_hazard_volumes(root)
	var pads: Array[BoostPad] = []
	_collect_pads(root, pads)
	var dead: int = 0
	_dead_pads.clear()
	for pad: BoostPad in pads:
		if is_finite(_pad_landing(pad, into_root).x):
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
		var base: float = (into_root * pad.global_position).y
		source.add_projected_obstruction(corners, base - 1.0, 3.0, true)
		dead += 1
	return dead


## Dead pads as hazard boxes in [RunnerCoverFinder]'s shape, so cover play and crossings avoid them.
func dead_pad_hazards() -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	for pad: BoostPad in _dead_pads:
		if not is_instance_valid(pad):
			continue
		var half: Vector3 = pad.footprint_metres * 0.5 + Vector3(1.0, 1.0, 1.0)
		hazards.append({
			"inverse": pad.global_transform.affine_inverse(),
			"half": half,
			"centre": pad.global_position,
			"reach_squared": half.length_squared(),
		})
	return hazards


func _build_pad_links(root: Node, into_root: Transform3D) -> void:
	for link: NavigationLink3D in _links:
		link.queue_free()
	_links.clear()
	_links_refined = false
	_mesh_low = INF
	var pads: Array[BoostPad] = []
	_collect_pads(root, pads)
	for pad: BoostPad in pads:
		var landing: Vector3 = _pad_landing(pad, into_root)
		if not is_finite(landing.x):
			continue
		var link: NavigationLink3D = NavigationLink3D.new()
		link.name = "PadLink_%s" % pad.name
		link.bidirectional = false
		link.travel_cost = LINK_TRAVEL_COST
		link.start_position = into_root * pad.global_position
		link.end_position = landing
		link.set_meta(&"pad", pad)
		add_child(link)
		_links.append(link)


## Once the map is live: shorten a link blocked by a wall or ceiling, and snap both ends to the mesh.
func _refine_pad_links() -> void:
	var world: World3D = get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	var map: RID = get_navigation_map()
	for link: NavigationLink3D in _links:
		var pad: BoostPad = link.get_meta(&"pad", null) as BoostPad
		if pad == null or not is_instance_valid(pad):
			link.enabled = false
			continue
		var start: Vector3 = pad.global_position
		var end: Vector3 = link.global_transform * link.end_position
		if space != null:
			var blocked: Vector3 = _first_blocking_floor(space, start, pad.get_launch_velocity(), end)
			if is_finite(blocked.x):
				end = blocked
		var snapped_end: Vector3 = NavigationServer3D.map_get_closest_point(map, end)
		if snapped_end.distance_to(end) > LINK_SNAP_METRES:
			link.enabled = false
			continue
		link.set_global_start_position(NavigationServer3D.map_get_closest_point(map, start))
		link.set_global_end_position(snapped_end)


## The floor under the first static hit along the arc from [param start], or Vector3.INF if the arc is clear.
func _first_blocking_floor(
	space: PhysicsDirectSpaceState3D, start: Vector3, velocity: Vector3, landing: Vector3
) -> Vector3:
	var flat_reach: float = Vector2(landing.x - start.x, landing.z - start.z).length()
	var lift: Vector3 = Vector3.UP * 0.9
	var previous: Vector3 = start + lift
	for point: Vector3 in simulate_flight(start, velocity):
		if Vector2(point.x - start.x, point.z - start.z).length() >= flat_reach - 0.5:
			return Vector3.INF
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(previous, point + lift)
		query.collision_mask = STATIC_COLLIDER_MASK
		query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			var back: Vector3 = previous - (point + lift - previous).normalized() * 0.5
			var down: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(back, back + Vector3.DOWN * 40.0)
			down.collision_mask = STATIC_COLLIDER_MASK
			down.collide_with_areas = false
			var floor_hit: Dictionary = space.intersect_ray(down)
			return floor_hit.get("position", Vector3.INF) if not floor_hit.is_empty() else Vector3.INF
		previous = point + lift
	return Vector3.INF


static func _ring_point(centre: Vector3, angle: float, radius: float, height: float) -> Vector3:
	return Vector3(centre.x + cos(angle) * radius, height, centre.z + sin(angle) * radius)


# --- Jump links ---------------------------------------------------------------

## True when [param world_point] stands over a carved trap footprint widened by [param margin].
func point_over_hazard(world_point: Vector3, margin: float = 0.0) -> bool:
	return _hazard_footprint_distance(world_point) <= margin


## Every jump a body could take, both ways round a two-way link: where it leaves from,
## where it lands, the ground speed it wants and the seconds it spends in the air.
func jump_link_options() -> Array[Dictionary]:
	return _jump_options


## What a runner needs from the link between two path points -- the ground speed to take off
## at -- or {} when the pair is not a jump of ours.
func jump_link_between(entry: Vector3, exit: Vector3) -> Dictionary:
	for index: int in _jump_nodes.size():
		var link: NavigationLink3D = _jump_nodes[index]
		if not link.enabled:
			continue
		var plan: Dictionary = _jump_plans[index]
		var start: Vector3 = link.get_global_start_position()
		var end: Vector3 = link.get_global_end_position()
		if _pair_matches(entry, exit, start, end):
			return {"speed": float(plan["speed"]), "air": float(plan["air"])}
		if bool(plan["both"]) and _pair_matches(entry, exit, end, start):
			return {"speed": float(plan["back"]), "air": float(plan["air_back"])}
	return {}


static func _pair_matches(entry: Vector3, exit: Vector3, start: Vector3, end: Vector3) -> bool:
	return Vector2(entry.x - start.x, entry.z - start.z).length() <= JUMP_LINK_MATCH_METRES \
		and Vector2(exit.x - end.x, exit.z - end.z).length() <= JUMP_LINK_MATCH_METRES


func _free_jump_links() -> void:
	for link: NavigationLink3D in _jump_nodes:
		link.queue_free()
	_jump_nodes.clear()
	_jump_plans.clear()


## One link per pair of islands whose boundaries meet over a carved trap, carrying the
## crossings that pair offers. [method _refine_jump_links] picks which one it flies.
func _build_jump_links() -> int:
	_free_jump_links()
	if _movement == null or navigation_mesh == null:
		return 0
	_build_hazard_boxes()
	if _hazard_boxes.is_empty():
		return 0
	var edges: Array[Dictionary] = _hazard_boundary_edges()
	if edges.size() < 2:
		return 0

	var cell: float = maxf(_jump_max_span(), 1.0) + 1.0
	var grid: Dictionary = {}
	for index: int in edges.size():
		var home: Vector2i = _edge_cell(edges[index], cell)
		var bucket: Array = grid.get(home, [])
		bucket.append(index)
		grid[home] = bucket

	var best: Dictionary = {}
	for index: int in edges.size():
		var home: Vector2i = _edge_cell(edges[index], cell)
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for other: int in grid.get(home + Vector2i(dx, dz), []) as Array:
					if other > index:
						_consider_jump(edges[index], edges[other], best)

	var ranked: Array = []
	for pair: Vector2i in best:
		var options: Array = (best[pair] as Dictionary).values()
		options.sort_custom(
			func(x: Dictionary, y: Dictionary) -> bool: return float(x["span"]) < float(y["span"])
		)
		ranked.append(options)
	ranked.sort_custom(func(x: Array, y: Array) -> bool:
		return float((x[0] as Dictionary)["span"]) < float((y[0] as Dictionary)["span"]))

	for options: Array in ranked:
		if _jump_nodes.size() >= JUMP_LINK_MAX:
			break
		var first: Dictionary = options[0]
		var link: NavigationLink3D = NavigationLink3D.new()
		link.name = "JumpLink_%d" % _jump_nodes.size()
		link.travel_cost = JUMP_LINK_TRAVEL_COST
		link.enabled = false
		link.start_position = first["start"]
		link.end_position = first["end"]
		add_child(link)
		_jump_nodes.append(link)
		_jump_plans.append({
			"options": options, "speed": 0.0, "back": 0.0, "air": 0.0, "air_back": 0.0, "both": false,
		})
	return _jump_nodes.size()


static func _edge_cell(edge: Dictionary, cell: float) -> Vector2i:
	var from: Vector3 = edge["from"]
	var to: Vector3 = edge["to"]
	return Vector2i(int(floor((from.x + to.x) * 0.5 / cell)), int(floor((from.z + to.z) * 0.5 / cell)))


## Keep the shortest crossing this island pair has in each metre of span, so a landing the
## baked heights misjudge does not hide a longer one onto the same platform.
func _consider_jump(a: Dictionary, b: Dictionary, best: Dictionary) -> void:
	if int(a["island"]) == int(b["island"]):
		return
	if not bool(a["inside"]) and not bool(b["inside"]):
		return
	var near: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
		a["from"], a["to"], b["from"], b["to"]
	)
	var start: Vector3 = _nudge_inwards(near[0], a["centre"])
	var end: Vector3 = _nudge_inwards(near[1], b["centre"])
	var span: float = Vector2(end.x - start.x, end.z - start.z).length()
	if span < JUMP_MIN_METRES or span > _jump_max_span():
		return
	var pair: Vector2i = Vector2i(mini(a["island"], b["island"]), maxi(a["island"], b["island"]))
	var options: Dictionary = best.get(pair, {})
	var slot: int = int(span)
	var held: Dictionary = options.get(slot, {})
	if held.is_empty() or span < float(held["span"]):
		options[slot] = {"start": start, "end": end, "span": span}
	best[pair] = options


## Pick each link's crossing from the floor a body really stands on: the bake rounds a
## surface to the cell height, which is a quarter of the apex the decision turns on.
func _refine_jump_links() -> void:
	var world: World3D = get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	if space == null or _movement == null:
		return
	_jump_options.clear()
	for index: int in _jump_nodes.size():
		var link: NavigationLink3D = _jump_nodes[index]
		var plan: Dictionary = _jump_plans[index]
		link.enabled = false
		# Every crossing this pair offers is measured, not just the shortest: a two-way
		# hop onto a platform beats a one-way drop off it, whatever their spans.
		for option: Dictionary in plan["options"] as Array:
			var span: float = float(option["span"])
			var low: float = _floor_under(space, global_transform * (option["start"] as Vector3))
			var high: float = _floor_under(space, global_transform * (option["end"] as Vector3))
			var out: float = _takeoff_speed(span, high - low)
			var back: float = _takeoff_speed(span, low - high)
			if out < 0.0 and back < 0.0:
				continue
			if link.enabled and not (out >= 0.0 and back >= 0.0 and not bool(plan["both"])):
				continue
			var forward: bool = out >= 0.0
			link.start_position = option["start"] if forward else option["end"]
			link.end_position = option["end"] if forward else option["start"]
			plan["speed"] = out if forward else back
			plan["back"] = back if forward else -1.0
			plan["air"] = _jump_air(high - low) if forward else _jump_air(low - high)
			plan["air_back"] = _jump_air(low - high) if forward else 0.0
			plan["both"] = out >= 0.0 and back >= 0.0
			link.bidirectional = bool(plan["both"])
			link.enabled = true
		_jump_plans[index] = plan
		if link.enabled:
			_jump_options.append({
				"entry": link.get_global_start_position(),
				"exit": link.get_global_end_position(),
				"speed": float(plan["speed"]),
				"air": float(plan["air"]),
			})
			if bool(plan["both"]):
				_jump_options.append({
					"entry": link.get_global_end_position(),
					"exit": link.get_global_start_position(),
					"speed": float(plan["back"]),
					"air": float(plan["air_back"]),
				})


## The static floor under [param point], or its own height when nothing is beneath it.
func _floor_under(space: PhysicsDirectSpaceState3D, point: Vector3) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 1.5, point + Vector3.DOWN * 2.0
	)
	query.collision_mask = STATIC_COLLIDER_MASK
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else point.y


## Ground speed a jump needs to clear [param span] onto ground [param rise] above it, or -1
## when the apex cannot reach that height or the run cannot reach that distance.
## [param slack] forgives the cell height the baked mesh rounds a surface by.
func _takeoff_speed(span: float, rise: float, slack: float = 0.0) -> float:
	if rise - slack > _movement.get_jump_apex_height() - JUMP_RISE_CLEARANCE_METRES:
		return -1.0
	if rise < -JUMP_MAX_DROP_METRES:
		return -1.0
	var speed: float = span / maxf(_jump_air(rise), 0.001)
	return speed if speed <= _movement.ground_speed * JUMP_REACH_SAFETY else -1.0


## Seconds a jump spends in the air before it is back at [param rise] above its take-off.
func _jump_air(rise: float) -> float:
	var launch: float = _movement.jump_velocity
	return (launch + sqrt(maxf(launch * launch - 2.0 * _gravity * rise, 0.0))) / maxf(_gravity, 0.1)


## Longest jump the profile could ever make, used to size the candidate search.
func _jump_max_span() -> float:
	var launch: float = _movement.jump_velocity
	var air: float = (launch + sqrt(launch * launch + 2.0 * _gravity * JUMP_MAX_DROP_METRES)) / maxf(_gravity, 0.1)
	return _movement.ground_speed * JUMP_REACH_SAFETY * air


static func _nudge_inwards(point: Vector3, centre: Vector3) -> Vector3:
	var reach: float = Vector2(centre.x - point.x, centre.z - point.z).length()
	if reach < 0.01:
		return point
	return point.lerp(centre, minf(JUMP_LINK_INSET_METRES, reach) / reach)


## Every mesh edge with one polygon behind it that lies within reach of a carved trap,
## carrying the island (polygons joined edge to edge) it belongs to.
func _hazard_boundary_edges() -> Array[Dictionary]:
	var vertices: PackedVector3Array = navigation_mesh.get_vertices()
	var polygons: int = navigation_mesh.get_polygon_count()
	var stride: int = maxi(vertices.size(), 1)
	var owner: Array[int] = []
	owner.resize(polygons)
	for index: int in polygons:
		owner[index] = index
	var first: Dictionary = {}
	var shared: Dictionary = {}
	for index: int in polygons:
		var polygon: PackedInt32Array = navigation_mesh.get_polygon(index)
		for corner: int in polygon.size():
			var key: int = _edge_key(polygon[corner], polygon[(corner + 1) % polygon.size()], stride)
			if first.has(key):
				_join(owner, index, int(first[key]))
				shared[key] = true
			else:
				first[key] = index

	var edges: Array[Dictionary] = []
	for index: int in polygons:
		var polygon: PackedInt32Array = navigation_mesh.get_polygon(index)
		if polygon.size() < 3:
			continue
		var centre: Vector3 = Vector3.ZERO
		for corner: int in polygon:
			centre += vertices[corner]
		centre /= float(polygon.size())
		for corner: int in polygon.size():
			var a: int = polygon[corner]
			var b: int = polygon[(corner + 1) % polygon.size()]
			if shared.has(_edge_key(a, b, stride)):
				continue
			var reach: float = _hazard_footprint_distance(_root_transform * ((vertices[a] + vertices[b]) * 0.5))
			if reach > JUMP_HAZARD_REACH_METRES:
				continue
			edges.append({
				"from": vertices[a],
				"to": vertices[b],
				"centre": centre,
				"island": _join_root(owner, index),
				"inside": reach <= 0.0,
			})
	return edges


static func _edge_key(a: int, b: int, stride: int) -> int:
	return mini(a, b) * stride + maxi(a, b)


static func _join_root(owner: Array[int], node: int) -> int:
	var cursor: int = node
	while owner[cursor] != cursor:
		owner[cursor] = owner[owner[cursor]]
		cursor = owner[cursor]
	return cursor


static func _join(owner: Array[int], a: int, b: int) -> void:
	var left: int = _join_root(owner, a)
	var right: int = _join_root(owner, b)
	if left != right:
		owner[right] = left


## Trap footprints in the shape the carve used them, so "over a hazard" and "carved" agree.
func _build_hazard_boxes() -> void:
	_hazard_boxes.clear()
	for volume: Node3D in _hazard_volumes:
		var trap: TrapVolume = volume as TrapVolume
		if trap == null:
			continue
		var world: Transform3D = trap.global_transform
		var half: Vector3 = trap.size_metres * 0.5
		var scale_x: float = maxf(world.basis.x.length(), 0.001)
		var scale_z: float = maxf(world.basis.z.length(), 0.001)
		var extent: float = Vector2(
			(half.x + HAZARD_INFLATION_METRES) * scale_x, (half.z + HAZARD_INFLATION_METRES) * scale_z
		).length() + JUMP_HAZARD_REACH_METRES
		_hazard_boxes.append({
			"inverse": world.affine_inverse(),
			"centre": world.origin,
			"reach_squared": extent * extent,
			"half": Vector3(half.x + HAZARD_INFLATION_METRES, half.y, half.z + HAZARD_INFLATION_METRES),
			"scale": Vector2(scale_x, scale_z),
		})


## Metres from [param world_point] to the nearest carved trap footprint, 0.0 inside it, INF
## when no trap stands near enough in height to matter.
func _hazard_footprint_distance(world_point: Vector3) -> float:
	var best: float = INF
	for box: Dictionary in _hazard_boxes:
		var centre: Vector3 = box["centre"]
		if Vector2(world_point.x - centre.x, world_point.z - centre.z).length_squared() > float(box["reach_squared"]):
			continue
		var half: Vector3 = box["half"]
		var local: Vector3 = (box["inverse"] as Transform3D) * world_point
		if absf(local.y) > half.y + JUMP_HAZARD_HEIGHT_METRES:
			continue
		var scale: Vector2 = box["scale"]
		var gap: Vector2 = Vector2(
			maxf(absf(local.x) - half.x, 0.0) * scale.x, maxf(absf(local.z) - half.z, 0.0) * scale.y
		)
		best = minf(best, gap.length())
		if best <= 0.0:
			return 0.0
	return best
