@tool
class_name TowerVariant
extends Node3D

## Pick which tower model is live, and how many of its eight openings are open.
##
## The plugs are built here rather than modelled: the two .glb files are Ryan's
## and are rebuilt on the PC, so a rule that closes a window has to be geometry
## this node adds. One [StaticBody3D] with a box collider and a box mesh per
## plugged opening, parented to a [code]Plugs[/code] child, shown and hidden
## rather than rebuilt when the count changes.

## Openings the drum carries, on one 45 degree grid.
const WINDOW_COUNT: int = MatchRules.TOWER_WINDOW_COUNT

## Bearing of opening 0, in degrees about +X toward +Z. Measured off both models'
## own colliders: the arches sit at exactly 25 + 45k, the carved ones wander
## about a degree either side of the same grid.
const WINDOW_PHASE_DEGREES: float = 25.0

## Angular width a plug covers, in degrees. The openings measure 38.5 to 41.5
## across; this is the wider of them plus a margin into the piers.
const PLUG_SPAN_DEGREES: float = 43.0

## Where a plug starts and stops in this node's space -- the drum's room floor is
## at y=1.70, the sill at 2.35 and the arch crown at 7.00, so this clears the
## opening at both ends.
const PLUG_BOTTOM: float = 2.10
const PLUG_TOP: float = 7.20

## Inner skin of the drum, in metres, and how thick a plug is. The plug is
## centred so it stands proud of the skin inside: a chord across 43 degrees sags
## half a metre off the arc, and a plug that did not stand proud would leave a
## gap at each jamb.
const DRUM_INNER_RADIUS: float = 6.86
const PLUG_THICKNESS: float = 2.0

## The child the plugs hang off, created on demand.
const PLUGS_NODE: StringName = &"Plugs"

@export_enum("carved", "arches") var variant: int = 1:
	set(value):
		variant = value
		_apply()

## How many openings stay open. [constant WINDOW_COUNT] is every one of them,
## which is the tower as modelled; the rest are plugged.
@export_range(0, 8, 1) var open_windows: int = WINDOW_COUNT:
	set(value):
		open_windows = clampi(value, 0, WINDOW_COUNT)
		_apply_plugs()


func _ready() -> void:
	_apply()
	_apply_plugs()


## True when opening [param index] is left open at [param open_count].
##
## Bresenham, so the open windows stay spread round the drum instead of all
## coming off one side: at four open it is every other opening, at one it is
## opening 0 alone.
static func is_window_open(index: int, open_count: int) -> bool:
	if open_count >= WINDOW_COUNT:
		return true
	if open_count <= 0:
		return false
	return (index * open_count) % WINDOW_COUNT < open_count


## How many plugs are currently standing. For tests and for the harness.
func get_plugged_count() -> int:
	var plugged: int = 0
	for index: int in WINDOW_COUNT:
		var plug: Node3D = _plug(index, false)
		if plug != null and plug.visible:
			plugged += 1
	return plugged


func _apply() -> void:
	var rocks: Array[Node] = [get_node_or_null("Rock"), get_node_or_null("RockArches")]
	for i: int in rocks.size():
		var rock: Node3D = rocks[i] as Node3D
		if rock == null:
			continue
		var live: bool = i == variant
		rock.visible = live
		for body: Node in rock.find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = 1 if live else 0


func _apply_plugs() -> void:
	for index: int in WINDOW_COUNT:
		var open: bool = is_window_open(index, open_windows)
		var plug: Node3D = _plug(index, not open)
		if plug == null:
			continue
		plug.visible = not open
		var body: StaticBody3D = plug as StaticBody3D
		if body != null:
			body.collision_layer = 1 if not open else 0


## The plug for [param index], built if [param build] and it does not exist yet.
func _plug(index: int, build: bool) -> Node3D:
	var plugs: Node3D = get_node_or_null(NodePath(PLUGS_NODE)) as Node3D
	if plugs == null:
		if not build:
			return null
		plugs = Node3D.new()
		plugs.name = PLUGS_NODE
		add_child(plugs)
	var plug_name: String = "Plug%d" % index
	var existing: Node3D = plugs.get_node_or_null(NodePath(plug_name)) as Node3D
	if existing != null or not build:
		return existing
	return _build_plug(plugs, index, plug_name)


func _build_plug(plugs: Node3D, index: int, plug_name: String) -> StaticBody3D:
	var height: float = PLUG_TOP - PLUG_BOTTOM
	var width: float = 2.0 * DRUM_INNER_RADIUS * sin(deg_to_rad(PLUG_SPAN_DEGREES) * 0.5)
	var size: Vector3 = Vector3(width, height, PLUG_THICKNESS)

	var body: StaticBody3D = StaticBody3D.new()
	body.name = plug_name
	var bearing: float = deg_to_rad(WINDOW_PHASE_DEGREES + 360.0 / float(WINDOW_COUNT) * index)
	var radius: float = DRUM_INNER_RADIUS + PLUG_THICKNESS * 0.5
	body.position = Vector3(
		cos(bearing) * radius, PLUG_BOTTOM + height * 0.5, sin(bearing) * radius
	)
	# -Z of the box faces the drum's centre, so the slab lies across the opening
	# rather than along it.
	body.rotation.y = -bearing + PI * 0.5

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	body.add_child(mesh)

	plugs.add_child(body)
	return body
