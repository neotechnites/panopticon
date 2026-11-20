class_name BoostPad
extends Area3D

## A Halo-style launch pad: a body that steps onto its box leaves along this node's own forward
## (-Z) tilted [member launch_angle_degrees] up, at [member launch_speed] whatever it arrived with.
##
## The pad is data, not a physics monitor: each body tests its own move against the pads of its world
## ([method PlayerController._touch_pads]) and launches itself, so a client's replay throws it again.
## A pad takes the bodies on the layers its [member collision_mask] holds, while [member armed].
## Its origin is the floor: the box and the plate are lifted to stand on it.

## Metres a body must overlap to trigger the pad. X is the footprint's width
## (across the direction of travel), Y is how tall the trigger volume stands
## above the floor -- tall enough to catch a body whether it arrives standing or
## crouched -- and Z is the footprint's depth (along the direction the pad
## faces). The [CollisionShape3D] that detects is sized from this on ready,
## exactly as [member TrapVolume.size_metres] sizes its own detection shape, so
## the area you can walk into is never a guess.
@export var footprint_metres: Vector3 = Vector3(3.0, 1.0, 3.0)

## Speed a launched body leaves at, in m/s, measured along the resulting
## launch vector as a whole (not a horizontal or a vertical component alone).
## This is the one number a map wants two of: duplicate the pad and turn this
## down for a short hop between nearby platforms, or up for a launch across the
## arena. At the shipped 18 and the shipped 45 degrees, a body leaves at
## roughly 12.7 m/s horizontally and 12.7 m/s vertically, which carries it
## roughly 14-15 m under this game's tuned gravity (22 m/s^2 effective,
## [member MovementProfile.gravity] * [member MovementProfile.gravity_scale])
## -- well past the ~7 m a standing jump can reach, which is the entire point of
## a pad existing.
@export_range(1.0, 60.0, 0.1, "or_greater") var launch_speed: float = 18.0

## Degrees the launch vector is tilted from this node's own local -Z (forward)
## towards this node's own local +Y (up). Halo's reference pad is 45, and that
## is the shipped default; exported rather than hard-coded so a map that wants
## a shallower or steeper pad can have one without a second script.
@export_range(0.0, 90.0, 0.5) var launch_angle_degrees: float = 45.0

## Visual thickness of the drawn plate, in metres. Deliberately independent of
## [member footprint_metres.y]: that field sizes the DETECTION volume, which
## wants to stand tall enough to reliably catch a passing capsule, while the
## plate wants to read as a flat panel underfoot -- like Halo's -- rather than a
## knee-high slab. The plate's X and Z still come from [member footprint_metres]
## directly, so the area you SEE is still the area that triggers it; only the
## height each uses is allowed to differ, and only because one is a floor decal
## and the other is a query volume.
const PLATE_THICKNESS_METRES: float = 0.2

## How far above the plate's top surface the chevron stripes float, in metres,
## so they never z-fight with the plate underneath them.
const CHEVRON_LIFT_METRES: float = 0.02

## Thickness (Y) and depth (Z, along the direction of travel) of each chevron
## stripe, in metres.
const CHEVRON_THICKNESS_METRES: float = 0.08
const CHEVRON_DEPTH_METRES: float = 0.18

## Each chevron's width as a fraction of the plate's own width, back to front.
## Narrowing towards the front is what reads as an arrow at a glance: the
## authored scene lists its three [CSGBox3D] stripes under a "Chevrons" node in
## exactly this order, largest first.
const CHEVRON_WIDTH_FRACTIONS: PackedFloat32Array = [0.75, 0.5, 0.25]


## Ternary-search steps for a segment's distance to the box: (2/3)^24 of the segment, under 0.1 mm.
const SEARCH_STEPS: int = 24

## The pads in each world, as Area3D binds to its space; keyed by [World3D].
static var _by_world: Dictionary[World3D, Array] = {}
static var _none: Array[BoostPad] = []

## Whether the pad launches. The one switch: the Area3D itself never monitors.
var armed: bool = true

var _world: World3D = null
var _box: CollisionShape3D = null
var _half: Vector3 = Vector3.ZERO
var _reach: float = 0.0


func _ready() -> void:
	_build_shape()
	_size_the_plate()
	var holder: CollisionShape3D = _find_shape_holder()
	if holder != null and holder.shape is BoxShape3D:
		_box = holder
		_half = (holder.shape as BoxShape3D).size * 0.5
		_reach = (holder.global_position - global_position).length() \
			+ (_half * holder.global_basis.get_scale().abs()).length()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_WORLD:
		_world = get_world_3d()
		if not _by_world.has(_world):
			var pads: Array[BoostPad] = []
			_by_world[_world] = pads
		_by_world[_world].append(self)
	elif what == NOTIFICATION_EXIT_WORLD and _world != null:
		var pads: Array = _by_world[_world]
		pads.erase(self)
		if pads.is_empty():
			_by_world.erase(_world)
		_world = null


## The pads in [param world] now, for the bodies there that test themselves against them.
static func in_world(world: World3D) -> Array[BoostPad]:
	return _by_world.get(world, _none)


## Metres from this node's origin to the far corner of its box, at ready's scale: nothing farther touches it.
func get_reach() -> float:
	return _reach


## Least distance, metres, from the world segment [param from]-[param to] to this pad's box, scale and all;
## INF before ready. A sheared box is read as its nearest oriented box.
func distance_to_segment(from: Vector3, to: Vector3) -> float:
	if _box == null:
		return INF
	var basis: Basis = _box.global_basis
	var to_box: Transform3D = Transform3D(basis.orthonormalized(), _box.global_position).inverse()
	return _segment_to_box(to_box * from, to_box * to, _half * basis.get_scale().abs())


## Least distance from segment [param from]-[param to] to the box of half-size [param half] at the origin:
## the distance along the segment is convex, so a ternary search finds its least.
static func _segment_to_box(from: Vector3, to: Vector3, half: Vector3) -> float:
	var lo: float = 0.0
	var hi: float = 1.0
	for _i: int in SEARCH_STEPS:
		var a: float = lerpf(lo, hi, 1.0 / 3.0)
		var b: float = lerpf(lo, hi, 2.0 / 3.0)
		if _point_to_box(from.lerp(to, a), half) <= _point_to_box(from.lerp(to, b), half):
			hi = b
		else:
			lo = a
	return _point_to_box(from.lerp(to, (lo + hi) * 0.5), half)


static func _point_to_box(point: Vector3, half: Vector3) -> float:
	return (point - point.clamp(-half, half)).length()


# --- Geometry -----------------------------------------------------------------


## Write [member footprint_metres] over the detection shape, and lift it so its
## bottom face sits at this node's own origin -- see the class doc for why a
## boost pad, unlike a trap, does that lifting itself.
func _build_shape() -> void:
	var holder: CollisionShape3D = _find_shape_holder()
	if holder == null:
		push_warning(
			"BoostPad at %s has no CollisionShape3D child; it will launch nobody."
			% get_path()
		)
		return
	var box: BoxShape3D = BoxShape3D.new()
	box.size = footprint_metres
	holder.shape = box
	holder.position = Vector3(0.0, footprint_metres.y * 0.5, 0.0)


## Write [member footprint_metres]'s X and Z, and the fixed
## [constant PLATE_THICKNESS_METRES], over the drawn plate, floor-anchored the
## same way [method _build_shape] anchors the detection box. Then sizes the
## chevron stripes off the plate, so the whole visible pad comes from one
## export plus the two small constants above it.
func _size_the_plate() -> void:
	var plate: CSGBox3D = _find_plate()
	if plate == null:
		return
	var plate_size: Vector3 = Vector3(footprint_metres.x, PLATE_THICKNESS_METRES, footprint_metres.z)
	plate.size = plate_size
	plate.position = Vector3(0.0, plate_size.y * 0.5, 0.0)
	_size_the_chevrons(plate_size)


## Narrowing stripes across the plate's top, back (largest) to front
## (smallest, towards local -Z, the direction the pad launches towards) -- the
## same convention Quake and Halo's own jump-pad decals use to read as an arrow
## without needing a real arrow mesh.
func _size_the_chevrons(plate_size: Vector3) -> void:
	var bars: Array[CSGBox3D] = _find_chevrons()
	if bars.is_empty():
		return
	var top_y: float = plate_size.y + CHEVRON_LIFT_METRES
	var count: int = bars.size()
	var spacing: float = plate_size.z / float(count + 1)
	for i: int in range(count):
		var bar: CSGBox3D = bars[i]
		var fraction: float = CHEVRON_WIDTH_FRACTIONS[i] if i < CHEVRON_WIDTH_FRACTIONS.size() else 0.25
		bar.size = Vector3(plate_size.x * fraction, CHEVRON_THICKNESS_METRES, CHEVRON_DEPTH_METRES)
		# Back of the plate is +Z; front (the way it launches) is -Z. Stripe 0
		# is the back (largest), the last stripe is the front (smallest).
		var z: float = plate_size.z * 0.5 - spacing * float(i + 1)
		bar.position = Vector3(0.0, top_y, z)


func _find_shape_holder() -> CollisionShape3D:
	for child: Node in get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


func _find_plate() -> CSGBox3D:
	for child: Node in get_children():
		var plate: CSGBox3D = child as CSGBox3D
		if plate != null:
			return plate
	return null


func _find_chevrons() -> Array[CSGBox3D]:
	var container: Node = get_node_or_null(^"Chevrons")
	var found: Array[CSGBox3D] = []
	if container == null:
		return found
	for child: Node in container.get_children():
		var bar: CSGBox3D = child as CSGBox3D
		if bar != null:
			found.append(bar)
	return found


# --- Launch ---------------------------------------------------------------


## The velocity a body leaves this pad with, in world space.
func get_launch_velocity() -> Vector3:
	return _launch_direction() * launch_speed


## This node's forward tilted [member launch_angle_degrees] towards its up, each axis normalised so
## any scale still gives a unit direction.
func _launch_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var up: Vector3 = global_transform.basis.y.normalized()
	var angle: float = deg_to_rad(launch_angle_degrees)
	return (forward * cos(angle) + up * sin(angle)).normalized()
