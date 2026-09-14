class_name RingNavigation
extends NavigationRegion3D

## A navmesh baked at match start from the level's static colliders, with every
## [TrapVolume] carved out. One per level root; see [method ensure].

const NODE_NAME: StringName = &"RingNavigation"
## Every baked region joins this group, so [PhaseGate] can ask for a rebake
## without a [NodePath] to it.
const GROUP: StringName = &"ring_navigation"
## The body's own capsule is 0.4 m; this is that plus a tenth.
##
## It was 0.75, which erodes 1.5 m of mesh out of every gap. Map 1's stalactite
## forest guarantees 1.2 m of clear air between fixture feet and 1.6 m between
## cover pieces, so at 0.75 the whole of S1 baked as disconnected scraps: every
## waypoint through it failed its detour check, the route skipped to the finish,
## and the field turned round and ran backwards into the bars. A navmesh that
## refuses ground the body walks through is not a conservative navmesh, it is a
## wrong one.
const AGENT_RADIUS: float = 0.5
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
const HAZARD_INFLATION_METRES: float = 0.8
const HAZARD_VERTICAL_MARGIN_METRES: float = 1.0
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
## A flight landing this near another pad is aimed at THAT pad's run-in instead.
##
## The demon run is four pads over three rocks, and a rock is three metres wide.
## Aimed at the bare landing point, a body comes down wherever the arc puts it,
## walks onto the next plate from the side, and throws the next arc off by its
## own sideways error -- which is how the third flight of every crossing ended in
## the lava. Aimed at the next pad's back edge, each flight sets the next one up
## square.
const PAD_CHAIN_METRES: float = 4.0
## How near a plate a body must be for [method pad_landing_from] to call it thrown by it.
const PAD_AIM_METRES: float = 3.0
const DEFAULT_GRAVITY: float = 22.0

## Platform tops standing in a carved trap (a lava lake's blocks) and the shores either side
## are joined by NavigationLink3Ds a bot FLIES, exactly as it flies a boost pad.
const LAKE_LINK_MAX_SPAN_METRES: float = 6.0
## Shortest hop worth flying. Under this the two footholds are a stride apart and
## a launch is a vertical pop that stops the body dead for most of a second.
const LAKE_LINK_MIN_SPAN_METRES: float = 2.0
## How far a take-off may stand off the navmesh and still be one.
const LAKE_TAKEOFF_SNAP_METRES: float = 0.75
const LAKE_LINK_MAX_RISE_METRES: float = 1.6
## Metres a take-off sits back from its edge, and a landing sits in past the far one.
const LAKE_LINK_INSET_METRES: float = 0.2
const LAKE_FLIGHT_MIN_SECONDS: float = 0.6
const LAKE_FLIGHT_MAX_SECONDS: float = 0.9
## Metres a foothold must stand above the lake's surface; a bank sloping into the lava is not one.
const LAKE_STAND_CLEARANCE_METRES: float = 0.2
## A shore foothold is walked back from the lip in these steps until it stands on real deck.
const LAKE_FOOTHOLD_STEP_METRES: float = 0.25
const LAKE_FOOTHOLD_STEPS: int = 8
## Rays that find the middle of a stepping stone's top: spacing, and rings out from the centre.
const LAKE_STONE_PROBE_METRES: float = 0.4
const LAKE_STONE_PROBE_RINGS: int = 4
const LAKE_LINK_MATCH_METRES: float = 1.2
const LAKE_LINK_MAX: int = 64
## Take-off points tried per island pair, and how far apart two of them must stand.
const LAKE_HOP_CANDIDATES: int = 8
const LAKE_HOP_SPACING_METRES: float = 0.75
const LAKE_LINK_TRAVEL_COST: float = 0.5
## Degrees of ring either side of a lava span's traps that count as being in it,
## and metres either side of it radially. The radial bound is what keeps the lava
## shelf's own inner LANE out of its span: that lane is real deck with the cover
## game to play on it, and a span bounded only by bearing would swallow it.
const LAKE_SPAN_PAD_DEGREES: float = 8.0
const LAKE_SPAN_PAD_METRES: float = 1.5
## Metres of clear deck inside a lava span that make it something to run PAST
## rather than something to cross. Under this there is no lane and the only way
## on is a chain of footholds; over it there is a lane, and a navmesh offered
## links as well would price the lane against them and send bodies at the water's
## edge for no reason. See [method _blocks_the_deck].
const LAKE_LANE_METRES: float = 2.0
## Metres above a lava surface a body can stand and still be over it.
const LAKE_ISLAND_HEAD_METRES: float = 4.0
## Samples along a hop that decide whether it really crosses lava.
const LAKE_LAVA_SAMPLES: int = 6
## A map declares its lava lake with a Marker3D of this name; the TrapVolumes beside it are it.
const LAKE_SURFACE_MARKER: StringName = &"LavaSurface"
## Metres a lake trap's carve reaches past its lethal surface, so the surface's own navmesh goes
## while the platforms standing clear of it keep theirs.
const LAKE_SURFACE_CARVE_MARGIN: float = 0.25

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
var _pads: Array[BoostPad] = []
var _links_refined: bool = false
var _lake_links: Array[NavigationLink3D] = []
var _lake_plans: Array[Dictionary] = []
var _trap_boxes: Array[Dictionary] = []
var _root_transform: Transform3D = Transform3D.IDENTITY
## Every stretch of lava with footholds in it, as {"from", "to", "height"} in
## radians of bearing and metres of surface. A map has as many as it has: Map 1
## alone has a declared lake at the wall run and a river through the lava shelf,
## and a single span could only ever serve one of them.
var _lake_spans: Array[Dictionary] = []
## How many of those came from the map's own markers rather than from the baked islands.
var _declared_spans: int = 0

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
	_hazard_volumes.clear()
	_collect_hazard_volumes(root)
	_declare_lake(root)
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
	var lake: int = _build_lake_links()
	_polygons = mesh.get_polygon_count()
	_bake_ms = Time.get_ticks_msec() - started
	charge("bake", started_usec)
	print("RingNavigation: baked %d polygons, %d traps, %d deck edges, %d dead pads carved, %d pad links, %d lake links, in %d ms" % [_polygons, carved, edges, dead, _links.size(), lake, _bake_ms])


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
		_refine_lake_links()
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
		# The carve stops at the trap's own lethal top -- its box, or the surface a feet_only trap
		# converts at -- so a platform standing IN a trap keeps the navmesh on top of it.
		var top: float = (into_root * (world * Vector3(0.0, half.y, 0.0))).y
		if trap.feet_only:
			# The lava's own surface must go, or a body walks across it; the margin keeps
			# whatever stands clear of it -- a stepping stone, a boulder in the river, a
			# landing rock in the demon run -- as an island to fly to.
			top = (into_root * world.origin).y + LAKE_SURFACE_CARVE_MARGIN
		var floor_level: float = bottom - HAZARD_VERTICAL_MARGIN_METRES
		source.add_projected_obstruction(corners, floor_level, maxf(top - floor_level, 0.1), true)
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


## Where a body running onto [param pad] along its own axis first trips it: the
## back edge of the plate, not the centre.
##
## A pad fires on CONTACT, so its centre is a launch point no body can ever take
## off from, and a flight solved from the centre lands a plate's half-width past
## wherever the body really comes down -- a metre and a half, on a landing rock
## four metres long, in a lava field. Air control cannot buy that back: it
## strafes, and the speed cap means it cannot add range.
func _pad_takeoff(pad: BoostPad) -> Vector3:
	var flat: Vector3 = pad.get_launch_velocity()
	flat.y = 0.0
	if flat.length() < 0.001:
		return pad.global_position
	return pad.global_position - flat.normalized() * pad.footprint_metres.z * 0.5


## Where a body launched from [param pad] meets the baked mesh, in mesh space, or Vector3.INF.
## The nearest polygon within LINK_SNAP_METRES counts: air control curves the flight onto it.
func _pad_landing(pad: BoostPad, into_root: Transform3D) -> Vector3:
	var arc: PackedVector3Array = simulate_flight(_pad_takeoff(pad), pad.get_launch_velocity())
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
	_pads.clear()
	_collect_pads(root, _pads)
	for pad: BoostPad in _pads:
		var landing: Vector3 = _pad_landing(pad, into_root)
		if not is_finite(landing.x):
			continue
		var link: NavigationLink3D = NavigationLink3D.new()
		link.name = "PadLink_%s" % pad.name
		link.bidirectional = false
		link.travel_cost = LINK_TRAVEL_COST
		link.start_position = into_root * _pad_takeoff(pad)
		link.end_position = landing
		link.set_meta(&"pad", pad)
		add_child(link)
		_links.append(link)


## The run-in of the pad whose plate is within PAD_CHAIN_METRES of [param point],
## or Vector3.INF. See [constant PAD_CHAIN_METRES].
func _pad_run_in_near(point: Vector3, exclude: BoostPad) -> Vector3:
	for pad: BoostPad in _pads:
		if pad == exclude or not is_instance_valid(pad):
			continue
		var plate: Vector3 = pad.global_position
		if absf(point.y - plate.y) > 2.0:
			continue
		if Vector2(point.x - plate.x, point.z - plate.z).length() > PAD_CHAIN_METRES:
			continue
		return _pad_takeoff(pad)
	return Vector3.INF


## Where the pad a body at [param point] has just been thrown by lands it, or
## Vector3.INF when there is no pad under it.
##
## A pad fires on CONTACT, so a body is launched whether or not the path it was
## following meant to use the link. An unaimed flight gets no air steering and
## comes down wherever the plate happened to be crossed -- which, over a lava
## field with three-metre rocks in it, is the lava. This is how a runner finds
## out where it is going after it has already left the ground.
func pad_landing_from(point: Vector3) -> Vector3:
	for link: NavigationLink3D in _links:
		if not link.enabled:
			continue
		var pad: BoostPad = link.get_meta(&"pad", null) as BoostPad
		if pad == null or not is_instance_valid(pad):
			continue
		var plate: Vector3 = pad.global_position
		if absf(point.y - plate.y) > PAD_AIM_METRES:
			continue
		if Vector2(point.x - plate.x, point.z - plate.z).length() > PAD_AIM_METRES:
			continue
		return link.get_global_end_position()
	return Vector3.INF


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
		var start: Vector3 = _pad_takeoff(pad)
		var end: Vector3 = link.global_transform * link.end_position
		if space != null:
			var blocked: Vector3 = _first_blocking_floor(space, start, pad.get_launch_velocity(), end)
			if is_finite(blocked.x):
				end = blocked
		var chained: Vector3 = _pad_run_in_near(end, pad)
		if is_finite(chained.x):
			end = chained
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


# --- Lake links ---------------------------------------------------------------
#
# A lava lake is carved wall to wall, so the only navmesh left inside it is the tops of the
# platforms standing in it. Those islands and the two shores are joined by NavigationLink3Ds
# carrying the launch velocity that lands a body on the far end, and a runner FLIES them the
# way it flies a boost pad. Nothing outside the lake's angular span is touched.

## True when [param world_point] is inside the lake's angular span at its height.
func is_in_lake_span(world_point: Vector3) -> bool:
	return not _span_at(world_point).is_empty()


## True when [param world_point] stands on a foothold INSIDE lava: a stepping
## stone, a boulder in the river, a landing rock in the demon run.
##
## Not the same question as [method is_in_lake_span], and the difference is the
## whole of the river: a span covers the water AND its banks, and the lava
## shelf's inner bank is ordinary deck with a lane on it and a cover game to
## play. A body there is not committed to anything. A body on a rock in the
## middle is -- the only way off is a flight -- and that is what this asks.
func is_on_lava_island(world_point: Vector3) -> bool:
	if _span_at(world_point).is_empty():
		return false
	for box: Dictionary in _trap_boxes:
		var centre: Vector3 = box["centre"]
		if Vector2(world_point.x - centre.x, world_point.z - centre.z).length_squared() > float(box["reach_squared"]):
			continue
		var local: Vector3 = (box["inverse"] as Transform3D) * world_point
		var half: Vector3 = box["kill_half"]
		if absf(local.x) <= half.x and absf(local.z) <= half.z \
			and local.y >= -half.y and local.y <= LAKE_ISLAND_HEAD_METRES:
			return true
	return false


## The lava span [param world_point] stands in, or {}.
func _span_at(world_point: Vector3) -> Dictionary:
	var pad: float = deg_to_rad(LAKE_SPAN_PAD_DEGREES)
	var radius: float = Vector2(world_point.x - _bake_centre.x, world_point.z - _bake_centre.z).length()
	for span: Dictionary in _lake_spans:
		if absf(world_point.y - float(span["height"])) > 6.0:
			continue
		if radius < float(span["near"]) - LAKE_SPAN_PAD_METRES \
			or radius > float(span["far"]) + LAKE_SPAN_PAD_METRES:
			continue
		var from: float = span["from"]
		var bearing: float = from + wrapf(_bearing_of(world_point) - from, -PI, PI)
		if bearing >= from - pad and bearing <= float(span["to"]) + pad:
			return span
	return {}


## One lava span, and whether it blocks the deck.
func _span(from: float, to: float, height: float, band: Vector2) -> Dictionary:
	return {
		"from": from, "to": to, "height": height, "near": band.x, "far": band.y,
		"blocking": _blocks_the_deck(band.x),
	}


## True when a span reaching in to [param near] leaves no lane inside it.
##
## The wall run's lake goes bank to bank and has to be hopped. The lava shelf's
## river does not: there is deck inside it the whole way, which is the section's
## own choice -- open lane or covered chain -- and a runner that took the chain
## because the navmesh priced it cheaper took it for the wrong reason and jammed
## against the cave wall's foot getting there.
func _blocks_the_deck(near: float) -> bool:
	var inner: float = 0.0
	if _bake_route != null:
		for level: RingLevel in _bake_route.get_levels():
			inner = maxf(inner, level.inner_radius)
	return near <= inner + LAKE_LANE_METRES


## The radii [param corners] reach, folded into [param band] as (near, far).
func _widen_band(band: Vector2, corners: PackedVector3Array) -> Vector2:
	for corner: Vector3 in corners:
		var radius: float = Vector2(corner.x - _bake_centre.x, corner.z - _bake_centre.z).length()
		band = Vector2(minf(band.x, radius), maxf(band.y, radius))
	return band


## The launch that carries a body from [param from] onto [param to]: a ledge inside the lake
## the body cannot walk up is flown on the same solver a link is.
func lake_launch_to(from: Vector3, to: Vector3) -> Vector3:
	return _lake_launch(from, to)


## The LANDING of the enabled lava link whose take-off stands nearest [param from],
## within [param reach] metres and ahead round the ring, or Vector3.INF.
##
## The landing and not the take-off, deliberately: a point on the near bank is
## somewhere the mesh reaches by walking, so a path aimed at one never uses the
## link and the runner arrives at the water's edge and carries on down the lane.
## A point on a boulder in the middle of the lava can only be reached by flying,
## so aiming at one IS choosing the chain.
func covered_step_ahead(from: Vector3, reach: float) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_gap: float = reach
	var here: float = _bearing_of(from)
	for link: NavigationLink3D in _lake_links:
		if not link.enabled:
			continue
		var start: Vector3 = link.get_global_start_position()
		if wrapf(_bearing_of(start) - here, -PI, PI) < 0.0:
			continue
		var gap: float = Vector2(start.x - from.x, start.z - from.z).length()
		if gap < best_gap:
			best_gap = gap
			best = link.get_global_end_position()
	return best


## The launch velocity and landing point of the lake link between two path points, or {}.
func lake_link_between(entry: Vector3, exit: Vector3) -> Dictionary:
	for index: int in _lake_links.size():
		var link: NavigationLink3D = _lake_links[index]
		if not link.enabled:
			continue
		var plan: Dictionary = _lake_plans[index]
		if not plan.has("velocity"):
			continue
		var start: Vector3 = link.get_global_start_position()
		if _pair_matches(entry, exit, start, link.get_global_end_position()):
			return {"velocity": plan["velocity"], "landing": plan["landing"], "start": start}
	return {}


static func _pair_matches(entry: Vector3, exit: Vector3, start: Vector3, end: Vector3) -> bool:
	return Vector2(entry.x - start.x, entry.z - start.z).length() <= LAKE_LINK_MATCH_METRES \
		and Vector2(exit.x - end.x, exit.z - end.z).length() <= LAKE_LINK_MATCH_METRES


func _bearing_of(world_point: Vector3) -> float:
	return atan2(world_point.z - _bake_centre.z, world_point.x - _bake_centre.x)


func _free_lake_links() -> void:
	for link: NavigationLink3D in _lake_links:
		link.queue_free()
	_lake_links.clear()
	_lake_plans.clear()


## One directed link per island pair inside the lake whose nearest edge points are within the
## jump envelope, ordered the way the lap runs. Positions are refined once the map is live.
func _build_lake_links() -> int:
	_free_lake_links()
	_lake_spans.resize(_declared_spans)
	if navigation_mesh == null:
		return 0
	_build_trap_boxes()
	if _trap_boxes.is_empty():
		return 0
	var islands: Array[Dictionary] = _mesh_islands()
	_find_lake_spans(islands)
	if _lake_spans.is_empty():
		return 0
	var live: Array[Dictionary] = []
	for island: Dictionary in islands:
		var edges: Array = _edges_in_span(island)
		if edges.is_empty():
			continue
		island["span_edges"] = edges
		live.append(island)
	for a: int in live.size():
		for b: int in live.size():
			if a == b or _lake_links.size() >= LAKE_LINK_MAX:
				continue
			var hops: Array[Dictionary] = _lake_hops(live[a], live[b])
			if hops.is_empty():
				continue
			var link: NavigationLink3D = NavigationLink3D.new()
			link.name = "LakeLink_%d" % _lake_links.size()
			link.bidirectional = false
			link.travel_cost = LAKE_LINK_TRAVEL_COST
			link.enabled = false
			link.start_position = (hops[0] as Dictionary)["start"]
			link.end_position = (hops[0] as Dictionary)["end"]
			add_child(link)
			_lake_links.append(link)
			_lake_plans.append({"hops": hops})
	return _lake_links.size()


## The forward hops from island [param a] to island [param b] that are in envelope, shortest
## first, one per distinct take-off point. Which of them has real floor at both ends is settled
## in [method _refine_lake_links], where the body can be raycast against.
func _lake_hops(a: Dictionary, b: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for left: Dictionary in a["span_edges"] as Array:
		for right: Dictionary in b["span_edges"] as Array:
			var near: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
				left["a"], left["b"], right["a"], right["b"]
			)
			var span: float = Vector2(near[1].x - near[0].x, near[1].z - near[0].z).length()
			if span >= LAKE_LINK_MAX_SPAN_METRES or span < LAKE_LINK_MIN_SPAN_METRES:
				continue
			if wrapf(_bearing_of(_root_transform * near[1]) - _bearing_of(_root_transform * near[0]), -PI, PI) <= 0.0:
				continue
			found.append({"span": span, "from": near[0], "to": near[1]})
	found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["span"]) < float(y["span"]))
	var hops: Array[Dictionary] = []
	for candidate: Dictionary in found:
		if hops.size() >= LAKE_HOP_CANDIDATES:
			break
		var from: Vector3 = candidate["from"]
		var apart: bool = true
		for held: Dictionary in hops:
			apart = apart and Vector2(
				from.x - (held["from"] as Vector3).x, from.z - (held["from"] as Vector3).z
			).length() > LAKE_HOP_SPACING_METRES
		if apart:
			hops.append(_lake_hop(a, b, from, candidate["to"]))
	return hops


## One hop's take-off and landing. A stepping stone is used at its centre -- a 2.4 m block is not
## something to leave or land on the rim of -- and a shore at its lip, backed off it.
func _lake_hop(a: Dictionary, b: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	var travel: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	travel = travel.normalized() if travel.length() > 0.001 else Vector3.ZERO
	var take_stone: bool = _is_stepping_stone(a)
	var land_stone: bool = _is_stepping_stone(b)
	var start: Vector3 = a["centre"] if take_stone else from - travel * LAKE_LINK_INSET_METRES
	var end: Vector3 = b["centre"] if land_stone else to + travel * LAKE_LINK_INSET_METRES
	return {
		"from": from,
		"start": Vector3(start.x, from.y, start.z),
		"end": Vector3(end.x, to.y, end.z),
		"travel": travel,
		"start_stone": take_stone,
		"end_stone": land_stone,
	}


## True when every polygon of [param island] stands over a trap: a block in the lake, not a shore.
static func _is_stepping_stone(island: Dictionary) -> bool:
	return int(island["over"]) >= int(island["polygons"])


## Boundary edges of [param island] that lie inside the lake's span, at the lake's height.
func _edges_in_span(island: Dictionary) -> Array:
	var kept: Array = []
	for edge: Dictionary in island["edges"] as Array:
		var middle: Vector3 = _root_transform * (((edge["a"] as Vector3) + (edge["b"] as Vector3)) * 0.5)
		var span: Dictionary = _span_at(middle)
		if span.is_empty() or not bool(span["blocking"]):
			continue
		kept.append(edge)
	return kept


## Stand each link on the floor its ends really have, work out the launch, and turn it on.
func _refine_lake_links() -> void:
	var world: World3D = get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	if space == null:
		return
	var map: RID = get_navigation_map()
	for index: int in _lake_links.size():
		var link: NavigationLink3D = _lake_links[index]
		var plan: Dictionary = _lake_plans[index]
		for hop: Dictionary in plan["hops"] as Array:
			var travel: Vector3 = hop["travel"]
			var start: Vector3 = _walkable(map, _lake_foothold(
				space, _root_transform * (hop["start"] as Vector3), -travel, bool(hop["start_stone"])
			))
			var end: Vector3 = _lake_foothold(
				space, _root_transform * (hop["end"] as Vector3), travel, bool(hop["end_stone"])
			)
			if not is_finite(start.x) or not is_finite(end.x):
				continue
			if absf(end.y - start.y) > LAKE_LINK_MAX_RISE_METRES:
				continue
			# The span that matters is the one between the points the body really
			# leaves and lands on, not between the mesh edges they were found from:
			# a shore take-off is walked back off its lip and a stone's is its
			# middle, and the two can close to a stride. Flying a stride is a
			# launch with no forward speed in it -- straight up, straight down, a
			# second of the body stopped dead, which was the commonest stall on
			# the map and is exactly what it looks like from inside the head.
			if Vector2(end.x - start.x, end.z - start.z).length() < LAKE_LINK_MIN_SPAN_METRES:
				continue
			if not _crosses_lava(start, end):
				continue
			link.set_global_start_position(start)
			link.set_global_end_position(end)
			plan["velocity"] = _lake_launch(start, end)
			plan["landing"] = end
			_lake_plans[index] = plan
			link.enabled = true
			break


## [param point] moved onto the navmesh, or Vector3.INF when the mesh is further
## than [constant LAKE_TAKEOFF_SNAP_METRES] away.
##
## A take-off is a place a runner has to WALK to before it can leave, and the
## foothold search only asks for floor that stands clear of the lava. On the lava
## shelf that is the round-over of the bank's own lip: real floor, half a metre
## above the lane, off the mesh, and a body sent at it runs up the slope, stops
## dead and slides back down. That was the commonest stall on the map.
func _walkable(map: RID, point: Vector3) -> Vector3:
	if not is_finite(point.x):
		return point
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, point)
	return on_mesh if on_mesh.distance_to(point) <= LAKE_TAKEOFF_SNAP_METRES else Vector3.INF


## True when the straight line from [param start] to [param end] passes over lava.
##
## A link exists to fly a gap that cannot be walked. Two footholds on the same
## bank, a stride apart with a ledge between them, are not that: flying one
## throws the body a metre straight up, stops it dead for most of a second, and
## puts it back down where a step would have taken it. Measured at the lava's own
## surface, because that is the thing in the way.
func _crosses_lava(start: Vector3, end: Vector3) -> bool:
	var span: Dictionary = _span_at(start)
	if span.is_empty():
		span = _span_at(end)
	if span.is_empty():
		return false
	var height: float = span["height"]
	for index: int in range(1, LAKE_LAVA_SAMPLES):
		var along: Vector3 = start.lerp(end, float(index) / float(LAKE_LAVA_SAMPLES))
		if _floor_is_lethal(Vector3(along.x, height, along.z)):
			return true
	return false


## Somewhere in the lake a body can actually stand: a stepping stone at the middle of its top,
## a shore walked [param away] from the lip until the floor clears the lava. Vector3.INF when none.
func _lake_foothold(
	space: PhysicsDirectSpaceState3D, point: Vector3, away: Vector3, stone: bool
) -> Vector3:
	if stone:
		return _stone_centre(space, point)
	for step: int in LAKE_FOOTHOLD_STEPS:
		var probe: Vector3 = point + away * (float(step) * LAKE_FOOTHOLD_STEP_METRES)
		var floor_point: Vector3 = _floor_point(space, probe)
		if _stands_clear_of_lava(floor_point):
			return floor_point
	return Vector3.INF


## The middle of the stone top under [param point], found by probing out from it. Averaging the
## hits at that height puts the take-off and the landing on the block, not on its rim.
func _stone_centre(space: PhysicsDirectSpaceState3D, point: Vector3) -> Vector3:
	var seed_point: Vector3 = _floor_point(space, point)
	if not _stands_clear_of_lava(seed_point):
		return Vector3.INF
	var sum: Vector3 = Vector3.ZERO
	var hits: int = 0
	for row: int in range(-LAKE_STONE_PROBE_RINGS, LAKE_STONE_PROBE_RINGS + 1):
		for column: int in range(-LAKE_STONE_PROBE_RINGS, LAKE_STONE_PROBE_RINGS + 1):
			var probe: Vector3 = seed_point + Vector3(
				float(column) * LAKE_STONE_PROBE_METRES, 0.0, float(row) * LAKE_STONE_PROBE_METRES
			)
			var floor_point: Vector3 = _floor_point(space, probe)
			if not _stands_clear_of_lava(floor_point) or absf(floor_point.y - seed_point.y) > 0.15:
				continue
			sum += floor_point
			hits += 1
	return seed_point if hits == 0 else Vector3(sum.x / float(hits), seed_point.y, sum.z / float(hits))


## True when [param floor_point] is real floor standing clear of the lake's surface.
func _stands_clear_of_lava(floor_point: Vector3) -> bool:
	if not is_finite(floor_point.x):
		return false
	var span: Dictionary = _span_at(floor_point)
	return span.is_empty() \
		or floor_point.y >= float(span["height"]) + LAKE_STAND_CLEARANCE_METRES


## The static floor under [param point], or Vector3.INF when there is none or it is a hazard.
func _floor_point(space: PhysicsDirectSpaceState3D, point: Vector3) -> Vector3:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 2.0, point + Vector3.DOWN * 3.0
	)
	query.collision_mask = STATIC_COLLIDER_MASK
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var floor_point: Vector3 = hit["position"]
	return Vector3.INF if _floor_is_lethal(floor_point) else floor_point


## True when standing at [param world_point] would trip a trap: inside its box, or at or below
## the surface a feet_only trap converts at. No margin -- a platform top clears a trap by little.
func _floor_is_lethal(world_point: Vector3) -> bool:
	for box: Dictionary in _trap_boxes:
		var centre: Vector3 = box["centre"]
		if Vector2(world_point.x - centre.x, world_point.z - centre.z).length_squared() > float(box["reach_squared"]):
			continue
		var local: Vector3 = (box["inverse"] as Transform3D) * world_point
		var half: Vector3 = box["kill_half"]
		if absf(local.x) > half.x or absf(local.z) > half.z:
			continue
		if local.y <= (0.05 if bool(box["feet"]) else half.y) and local.y >= -half.y:
			return true
	return false


## The velocity that drops a launched body from [param start] onto [param end]. The launch tick
## is still a ground tick, so its one helping of ground friction is paid for here.
func _lake_launch(start: Vector3, end: Vector3) -> Vector3:
	var dt: float = 1.0 / 60.0
	var flat: Vector2 = Vector2(end.x - start.x, end.z - start.z)
	var rise: float = end.y - start.y
	var seconds: float = lerpf(
		LAKE_FLIGHT_MIN_SECONDS,
		LAKE_FLIGHT_MAX_SECONDS,
		clampf(flat.length() / LAKE_LINK_MAX_SPAN_METRES, 0.0, 1.0),
	)
	var up: float = rise / seconds + 0.5 * _gravity * seconds
	var height: float = up * dt
	var speed: float = up
	var ticks: int = 1
	for tick: int in int(LAKE_FLIGHT_MAX_SECONDS * 4.0 * 60.0):
		speed -= _gravity * dt
		height += speed * dt
		ticks += 1
		if speed < 0.0 and height <= rise:
			break
	var ground: float = flat.length() / maxf(float(ticks) * dt, 0.001)
	for attempt: int in 6:
		var reach: float = _lake_reach(ground, ticks)
		if reach <= 0.001:
			break
		ground *= flat.length() / reach
	var direction: Vector2 = flat.normalized() if flat.length() > 0.001 else Vector2.ZERO
	return Vector3(direction.x * ground, up, direction.y * ground)


## Metres a launch at [param speed] covers in [param ticks]: one ground tick of friction --
## the launch tick is still on the floor -- and then the profile's air friction.
func _lake_reach(speed: float, ticks: int) -> float:
	var dt: float = 1.0 / 60.0
	var stop_speed: float = _movement.friction_stop_speed if _movement != null else 0.0
	var on_ground: float = _movement.friction if _movement != null else 0.0
	var in_air: float = _movement.air_friction if _movement != null else 0.0
	var travelled: float = 0.0
	var v: float = speed
	for tick: int in ticks:
		var drag: float = on_ground if tick == 0 else in_air
		if drag > 0.0 and v > 0.001:
			v = maxf(v - maxf(v, stop_speed) * drag * dt, 0.0)
		travelled += v * dt
	return travelled


## Trap footprints in the shape the carve used, so "standing in a trap" and "carved" agree.
func _build_trap_boxes() -> void:
	_trap_boxes.clear()
	for volume: Node3D in _hazard_volumes:
		var trap: TrapVolume = volume as TrapVolume
		if trap == null:
			continue
		var half: Vector3 = trap.size_metres * 0.5
		var world: Transform3D = trap.global_transform
		var reach: float = Vector2(
			(half.x + HAZARD_INFLATION_METRES) * world.basis.x.length(),
			(half.z + HAZARD_INFLATION_METRES) * world.basis.z.length(),
		).length()
		_trap_boxes.append({
			"inverse": world.affine_inverse(),
			"centre": world.origin,
			"reach_squared": reach * reach,
			"half": Vector3(half.x + HAZARD_INFLATION_METRES, half.y, half.z + HAZARD_INFLATION_METRES),
			"kill_half": half,
			"feet": trap.feet_only,
		})


## The trap [param world_point] stands in the footprint of, or -1.
func _trap_under(world_point: Vector3) -> int:
	for index: int in _trap_boxes.size():
		var box: Dictionary = _trap_boxes[index]
		var centre: Vector3 = box["centre"]
		if Vector2(world_point.x - centre.x, world_point.z - centre.z).length_squared() > float(box["reach_squared"]):
			continue
		var local: Vector3 = (box["inverse"] as Transform3D) * world_point
		var half: Vector3 = box["half"]
		if absf(local.x) <= half.x and absf(local.z) <= half.z and absf(local.y) <= half.y + 4.0:
			return index
	return -1


## The lava the map DECLARES: every [Marker3D] named [constant LAKE_SURFACE_MARKER]
## gives one span's surface height, and the [TrapVolume]s beside it give the
## bearings it covers.
func _declare_lake(root: Node) -> void:
	_lake_spans.clear()
	var markers: Array[Node3D] = []
	_collect_lake_markers(root, markers)
	for marker: Node3D in markers:
		if marker.get_parent() == null:
			continue
		var reference: float = _bearing_of(marker.global_position)
		var low: float = 0.0
		var high: float = 0.0
		var band: Vector2 = Vector2(INF, -INF)
		for sibling: Node in marker.get_parent().get_children():
			var trap: TrapVolume = sibling as TrapVolume
			if trap == null:
				continue
			var half: Vector3 = trap.size_metres * 0.5
			var corners: PackedVector3Array = PackedVector3Array()
			for corner: Vector3 in [
				Vector3(-half.x, 0.0, -half.z), Vector3(half.x, 0.0, -half.z),
				Vector3(half.x, 0.0, half.z), Vector3(-half.x, 0.0, half.z),
			]:
				var world: Vector3 = trap.global_transform * corner
				corners.append(world)
				var relative: float = wrapf(_bearing_of(world) - reference, -PI, PI)
				low = minf(low, relative)
				high = maxf(high, relative)
			band = _widen_band(band, corners)
		if is_finite(band.x):
			_lake_spans.append(_span(reference + low, reference + high, marker.global_position.y, band))
	_declared_spans = _lake_spans.size()


static func _collect_lake_markers(node: Node, found: Array[Node3D]) -> void:
	if node.name == LAKE_SURFACE_MARKER and node is Node3D:
		found.append(node as Node3D)
	for child: Node in node.get_children():
		_collect_lake_markers(child, found)


## Every run of platform islands -- islands standing wholly in a trap -- that sit within
## LAKE_SPAN_PAD_DEGREES of each other, as one span apiece. A run of one is a rock nothing
## hops to; it is left carved out. Runs already inside a declared span are that span's.
func _find_lake_spans(islands: Array[Dictionary]) -> void:
	var biggest: int = 0
	for island: Dictionary in islands:
		biggest = maxi(biggest, int(island["polygons"]))
	var platforms: Array[Dictionary] = []
	for island: Dictionary in islands:
		if int(island["polygons"]) >= biggest:
			continue
		if int(island["over"]) * 2 < int(island["polygons"]):
			continue
		var centre: Vector3 = _root_transform * (island["centre"] as Vector3)
		if is_in_lake_span(centre):
			continue
		island["bearing"] = _bearing_of(centre)

		platforms.append(island)
	if platforms.is_empty():
		return
	platforms.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["bearing"]) < float(y["bearing"]))
	var gap: float = deg_to_rad(LAKE_SPAN_PAD_DEGREES * 2.0)
	var run_from: int = 0
	for index: int in range(1, platforms.size() + 1):
		var broken: bool = index == platforms.size() \
			or float(platforms[index]["bearing"]) - float(platforms[index - 1]["bearing"]) > gap
		if not broken:
			continue
		if index - run_from > 1:
			_append_span(platforms, run_from, index)
		run_from = index


## One span over platforms [param from, param to), reaching over their traps too.
func _append_span(platforms: Array[Dictionary], from: int, to: int) -> void:
	var reference: float = float(platforms[from]["bearing"])
	var low: float = 0.0
	var high: float = 0.0
	# The span's height is the LAVA's, taken from the traps the platforms stand
	# in, and not the platforms' own: a foothold is a thing that stands clear of
	# the surface, so measuring the surface at the top of a boulder would rule
	# every boulder out of its own lake.
	var height: float = 0.0
	var surfaces: int = 0
	var band: Vector2 = Vector2(INF, -INF)
	for index: int in range(from, to):
		var island: Dictionary = platforms[index]
		var relative: float = wrapf(float(island["bearing"]) - reference, -PI, PI)
		low = minf(low, relative)
		high = maxf(high, relative)
		for trap: int in island["traps"] as Dictionary:
			var box: Dictionary = _trap_boxes[trap]
			var centre: Vector3 = box["centre"]
			var half: Vector3 = box["kill_half"]
			var corners: PackedVector3Array = PackedVector3Array()
			var world: Transform3D = (box["inverse"] as Transform3D).affine_inverse()
			for corner: Vector3 in [
				Vector3(-half.x, 0.0, -half.z), Vector3(half.x, 0.0, -half.z),
				Vector3(half.x, 0.0, half.z), Vector3(-half.x, 0.0, half.z),
			]:
				var point: Vector3 = world * corner
				corners.append(point)
				var bearing: float = wrapf(_bearing_of(point) - reference, -PI, PI)
				low = minf(low, bearing)
				high = maxf(high, bearing)
			band = _widen_band(band, corners)
			height += centre.y if bool(box["feet"]) else centre.y + half.y
			surfaces += 1
	if surfaces == 0:
		return
	_lake_spans.append(_span(reference + low, reference + high, height / float(surfaces), band))


## Mesh polygons joined edge to edge, with each island's boundary edges, centre and how many of
## its polygons stand in a trap.
func _mesh_islands() -> Array[Dictionary]:
	var vertices: PackedVector3Array = navigation_mesh.get_vertices()
	var count: int = navigation_mesh.get_polygon_count()
	var stride: int = maxi(vertices.size(), 1)
	var owner: Array[int] = []
	owner.resize(count)
	for index: int in count:
		owner[index] = index
	var first: Dictionary = {}
	var shared: Dictionary = {}
	for index: int in count:
		var polygon: PackedInt32Array = navigation_mesh.get_polygon(index)
		for corner: int in polygon.size():
			var key: int = _edge_key(polygon[corner], polygon[(corner + 1) % polygon.size()], stride)
			if first.has(key):
				_join(owner, index, int(first[key]))
				shared[key] = true
			else:
				first[key] = index
	var by_root: Dictionary = {}
	for index: int in count:
		var polygon: PackedInt32Array = navigation_mesh.get_polygon(index)
		if polygon.size() < 3:
			continue
		var root: int = _join_root(owner, index)
		var island: Dictionary = by_root.get(root, {
			"polygons": 0, "over": 0, "sum": Vector3.ZERO, "edges": [], "traps": {},
		})
		var middle: Vector3 = Vector3.ZERO
		for corner: int in polygon:
			middle += vertices[corner]
		middle /= float(polygon.size())
		island["polygons"] = int(island["polygons"]) + 1
		island["sum"] = (island["sum"] as Vector3) + middle
		var trap: int = _trap_under(_root_transform * middle)
		if trap >= 0:
			island["over"] = int(island["over"]) + 1
			(island["traps"] as Dictionary)[trap] = true
		for corner: int in polygon.size():
			var a: int = polygon[corner]
			var b: int = polygon[(corner + 1) % polygon.size()]
			if shared.has(_edge_key(a, b, stride)):
				continue
			(island["edges"] as Array).append({"a": vertices[a], "b": vertices[b]})
		by_root[root] = island
	var islands: Array[Dictionary] = []
	for root: int in by_root:
		var island: Dictionary = by_root[root]
		island["centre"] = (island["sum"] as Vector3) / float(island["polygons"])
		islands.append(island)
	return islands


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
