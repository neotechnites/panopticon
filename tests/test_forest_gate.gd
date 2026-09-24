extends TestCase

## The forest's one barrier, and the colliders that make it one.
##
## Map 3 closes the walk-back the way Map 1 and Map 2 do: a single stand of
## saplings across the lane in the gap between the finish (bearing 345) and the
## start (bearing 5), so a prisoner can SEE the portal from the line but cannot
## stroll backwards into it. This file is about the count. One barrier, one
## collider, and nothing else in that gap that a body can be stopped by.
##
## [b]Why counting is the assertion.[/b] Every way this has gone wrong has been
## a second thing in the gap rather than a wrong thing: a fence baked into the
## map mesh as well as instanced as a prop, an old gate left behind next to its
## replacement, a barrier whose concave import wraps every sapling separately so
## a runner is held by geometry nobody meant to be solid. None of those are
## visible in a screenshot of the lane; all of them are visible as a count.
##
## [b]The barrier is a BOX.[/b] [code]forest_bars.glb[/code] keeps
## [code]rock_bars.glb[/code]'s 10.6 x 8.5 m envelope, and what stops a body is
## that envelope -- one box, 1.2 m thick -- not the saplings' own silhouette. A
## trimesh hull of a stand of trunks is a collider with gaps in it, and a gap in
## a barrier is a barrier that does not exist.

## The scene under test. Instanced, walked, and freed; nothing here simulates.
const SCENE_PATH: String = "res://maps/forest/forest.tscn"

## What makes a node a candidate barrier, lower-cased and matched as a
## substring. Deliberately generous: the point is to catch a second barrier
## somebody named their own way, not to look up the one we already know about.
const BARRIER_WORDS: Array[String] = ["bars", "gate", "fence", "portcullis"]

## The finish gap, in degrees of bearing about the ring axis, as two arcs
## because it straddles 0: the portal sits at 345 and the start line at 5.
const GAP_START_DEG: float = 345.0
const GAP_END_DEG: float = 5.0

## The band a thing has to be in to be ON the lane rather than under it or out
## past the wall. The walkable grass is r 46.7..57.3.
const RADIUS_MIN_METRES: float = 40.0
const RADIUS_MAX_METRES: float = 62.0

## Where the one barrier stands, and how far off that it may be. 353 deg is the
## middle of the gap -- clear of the portal's own mouth and clear of the line.
const BARS_BEARING_DEG: float = 353.0
const BARS_BEARING_TOLERANCE_DEG: float = 1.0

## The envelope the barrier is imported as: radially across the lane (x), tall
## enough not to be jumped (y), and thin along the lane (z).
const BARS_BOX_SIZE: Vector3 = Vector3(10.6, 8.5, 1.2)
const BOX_TOLERANCE: float = 0.01

## The portal's own trigger volume. It is named Gate, it sits at 345 inside the
## band, and it is not a barrier -- it is the finish line itself. Matched on the
## tail of the node path so a Gate anywhere ELSE still counts.
const PORTAL_GATE_PATH_SUFFIX: String = "Portal/Gate"

## The barrier's own node, and the one node under it that is allowed to keep the
## word: its imported collision body is called ForestBarsCollision, and counting
## the parts of a barrier as barriers would make any barrier fail.
const BARS_NODE: String = "Bars"

## The map mesh and the single trimesh body it ships (ForestCollision-colonly).
const MAP_NODE: String = "ForestMap"
const MAP_COLLISION_NODE: String = "ForestCollision"

var _forest: Node3D


func before_each() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "the forest scene loads")
	if packed == null:
		return
	_forest = packed.instantiate() as Node3D
	assert_not_null(_forest, "and instances as a Node3D")
	if _forest == null:
		return
	# In the tree before anything is measured: global_position reads back as the
	# origin for a node that is not, and every bearing below would be 0.
	add_child(_forest)
	await step_ticks(1)


func after_each() -> void:
	if _forest != null and is_instance_valid(_forest):
		remove_child(_forest)
		_forest.free()
	_forest = null


# --- The count ----------------------------------------------------------------

## Exactly one thing in the finish gap can stop a body, and it is the Bars.
##
## Every node in the scene is walked -- not just the ones this file knows the
## names of -- and anything whose name reads as a barrier is measured by where
## it actually is. Two exclusions, both of them named rather than inferred: the
## portal's Gate area, which is the finish and not a wall, and the parts INSIDE
## the barrier, which are the barrier.
func test_one_barrier_between_start_and_portal() -> void:
	if _forest == null:
		fail("no scene to walk")
		return

	var found: Array[Node3D] = []
	var described: PackedStringArray = PackedStringArray()
	for node: Node in _descendants(_forest):
		if not _reads_as_a_barrier(node.name):
			continue
		if String(node.get_path()).ends_with(PORTAL_GATE_PATH_SUFFIX):
			continue
		if _is_inside_the_barrier(node):
			continue
		var spatial: Node3D = node as Node3D
		if spatial == null:
			# Nothing without a transform can be standing in the gap, but say so
			# rather than swallow it: a barrier that is not a Node3D is a bug of
			# a different kind.
			described.append("%s (not a Node3D)" % node.get_path())
			continue
		var here: Vector3 = spatial.global_position
		var bearing: float = _bearing_deg(here)
		var radius: float = Vector2(here.x, here.z).length()
		if not _in_the_finish_gap(bearing):
			continue
		if radius < RADIUS_MIN_METRES or radius > RADIUS_MAX_METRES:
			continue
		found.append(spatial)
		described.append("%s at %.1f deg, r %.1f" % [node.get_path(), bearing, radius])

	assert_eq_int(
		found.size(), 1,
		"exactly one barrier stands between the start and the portal -- found [%s]" % (
			", ".join(described)
		),
	)
	if found.size() != 1:
		return

	assert_eq_string(String(found[0].name), BARS_NODE, "and it is the Bars")
	assert_almost_eq(
		_bearing_deg(found[0].global_position), BARS_BEARING_DEG, BARS_BEARING_TOLERANCE_DEG,
		"standing in the middle of the gap, clear of the finish and clear of the line",
	)


# --- What stops the body ------------------------------------------------------

## The barrier is one box on one static body, and nothing else.
##
## The saplings are a silhouette. What a runner hits is a single 10.6 x 8.5 x
## 1.2 m envelope -- the one Map 1's rock bars use, so swapping the model swaps
## nothing else -- and a concave import of the trunks would be a collider full
## of the gaps the barrier exists to close.
func test_bars_collider_is_one_box() -> void:
	if _forest == null:
		fail("no scene to walk")
		return
	var bars: Node = _forest.get_node_or_null(NodePath(BARS_NODE))
	assert_not_null(bars, "the forest ships a Bars node")
	if bars == null:
		return

	var shapes: Array[CollisionShape3D] = []
	var bodies: Array[CollisionObject3D] = []
	for node: Node in _descendants(bars):
		var shape_holder: CollisionShape3D = node as CollisionShape3D
		if shape_holder != null:
			shapes.append(shape_holder)
		var body: CollisionObject3D = node as CollisionObject3D
		if body != null:
			bodies.append(body)

	assert_eq_int(shapes.size(), 1, "the barrier is exactly one collision shape, not a stand of them")
	if shapes.size() != 1:
		return

	var box: BoxShape3D = shapes[0].shape as BoxShape3D
	assert_not_null(
		box,
		"and that shape is a box -- got %s" % _shape_name(shapes[0].shape),
	)
	if box == null:
		return
	assert_vec3_almost_eq(
		box.size, BARS_BOX_SIZE, BOX_TOLERANCE,
		"sized to the lane: %.1f m across, %.1f m tall, %.1f m thick" % [
			BARS_BOX_SIZE.x, BARS_BOX_SIZE.y, BARS_BOX_SIZE.z
		],
	)

	var owner_body: CollisionObject3D = _owning_body(shapes[0])
	assert_not_null(owner_body, "the box hangs on a collision body")
	if owner_body == null:
		return
	assert_not_null(
		owner_body as StaticBody3D,
		"and that body is static -- the barrier does not move, it is grown into the ground",
	)
	assert_eq_int(bodies.size(), 1, "and it is the only collision body under the Bars")
	if bodies.size() == 1:
		assert_same(bodies[0], owner_body, "the one the box is on")


## The map mesh ships one trimesh body and no barrier of its own.
##
## The failure this guards is a fence baked into [code]forest.glb[/code]: a
## second wall across the lane that no node in the scene names, that cannot be
## moved without a rebuild, and that the count above would never see because it
## has no node to be found by.
func test_forest_map_has_no_fence_collider() -> void:
	if _forest == null:
		fail("no scene to walk")
		return
	var map: Node = _forest.get_node_or_null(NodePath(MAP_NODE))
	assert_not_null(map, "the forest ships the map mesh")
	if map == null:
		return

	var bodies: Array[CollisionObject3D] = []
	for node: Node in _descendants(map):
		var body: CollisionObject3D = node as CollisionObject3D
		if body != null:
			bodies.append(body)
	assert_eq_int(
		bodies.size(), 1,
		"the map mesh has exactly one collision body -- found [%s]" % ", ".join(_paths_of(bodies)),
	)

	var collision: Node = map.get_node_or_null(NodePath(MAP_COLLISION_NODE))
	assert_not_null(collision, "and it is %s, the glb's own colonly body" % MAP_COLLISION_NODE)
	if collision == null:
		return
	if bodies.size() == 1:
		assert_same(bodies[0], collision, "the same body the walk found")

	var shapes: Array[CollisionShape3D] = []
	for node: Node in _descendants(collision):
		var shape_holder: CollisionShape3D = node as CollisionShape3D
		if shape_holder != null:
			shapes.append(shape_holder)
	assert_eq_int(shapes.size(), 1, "carrying exactly one shape")
	if shapes.size() != 1:
		return
	assert_not_null(
		shapes[0].shape as ConcavePolygonShape3D,
		"the trimesh of the map itself -- got %s" % _shape_name(shapes[0].shape),
	)


# --- Helpers ------------------------------------------------------------------

## Every node under [param root], [param root] itself included.
func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var index: int = 0
	while index < out.size():
		for child: Node in out[index].get_children():
			out.append(child)
		index += 1
	return out


## Does [param node_name] read as something that blocks a lane?
func _reads_as_a_barrier(node_name: StringName) -> bool:
	var lowered: String = String(node_name).to_lower()
	for word: String in BARRIER_WORDS:
		if lowered.contains(word):
			return true
	return false


## True for the barrier's own parts -- its imported body, its shape, its mesh --
## and false for the barrier itself.
func _is_inside_the_barrier(node: Node) -> bool:
	var walker: Node = node.get_parent()
	while walker != null and walker != _forest:
		if String(walker.name) == BARS_NODE:
			return true
		walker = walker.get_parent()
	return false


## Bearing of [param point] about the ring axis, in degrees wrapped to 0..360.
func _bearing_deg(point: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(point.z, point.x)), 360.0)


## Is [param bearing] in the arc between the finish and the start? Two arcs,
## because the gap straddles 0.
func _in_the_finish_gap(bearing: float) -> bool:
	return bearing >= GAP_START_DEG or bearing <= GAP_END_DEG


## The collision body [param shape_holder] actually belongs to: the nearest one
## above it, which is the node whose collider it is.
func _owning_body(shape_holder: CollisionShape3D) -> CollisionObject3D:
	var walker: Node = shape_holder.get_parent()
	while walker != null:
		var body: CollisionObject3D = walker as CollisionObject3D
		if body != null:
			return body
		walker = walker.get_parent()
	return null


## Class name of [param shape], for a failure message that says what was there
## instead of what was wanted.
func _shape_name(shape: Shape3D) -> String:
	if shape == null:
		return "nothing"
	return shape.get_class()


func _paths_of(nodes: Array[CollisionObject3D]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: CollisionObject3D in nodes:
		out.append(String(node.get_path()))
	return out
