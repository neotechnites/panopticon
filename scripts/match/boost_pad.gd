class_name BoostPad
extends Area3D

## A Halo-style launch pad: walk onto it and leave along a fixed 45-degree arc,
## in the direction the pad is facing.
##
## Canon, in the author's words: [i]"lets also add the halo 45 degree boost
## pad... you can make the boost pad before putting it in the level, it should
## just be a game object we can use to make maps, same as the trap."[/i]
##
## [b]This is a movement toy, not a level feature.[/b] Explicitly not how
## players travel between levels -- Ryan has ruled that ramps behind cover do
## that. It is a reusable prop under [code]scenes/props/[/code], instanced into
## a map the same way [TrapVolume] is, and it is placed in no map by this
## change.
##
## [b]It never asks who touched it and never reports anywhere.[/b] Unlike
## [TrapVolume] this node has no [MatchController] to find and no death to
## route: it only reads and writes [member PlayerController.velocity], exactly
## the seam [method PlayerController._try_jump] itself uses
## ([code]velocity.y = profile.jump_velocity[/code], assigned directly, never
## requested through a [MoveIntent]). A body that is not a [PlayerController]
## is left alone, in the same spirit as [TrapVolume] doing nothing to a body
## that is not a recognised participant -- deciding what such a thing is is not
## this node's job.
##
## [b]It does not add a movement mode.[/b] The tick after a launch is an
## ordinary AIR tick as far as [PlayerController] is concerned -- indistinguishable
## from one that started with a jump. Every existing air rule (Quake air-strafe,
## gravity, [member MovementProfile.auto_bunny_hop] on landing) applies to it
## untouched, because nothing here tells the controller it was launched at all.
##
## [b]Facing, not placement, aims it.[/b] The launch direction is built from
## this node's OWN basis: local -Z (forward -- the same axis
## [method PlayerController._get_wish_vector] treats as forward) tilted towards
## local +Y (up) by [member launch_angle_degrees]. Rotating the node is the
## whole interface; if a placement ever tilts pitch or roll too (mounted askew
## on a built structure) that tilt rides along, because the pad reads its own
## orientation and never the world's.
##
## [b]Fixed arc, not added momentum -- this is the deliberate answer to "walked
## on slowly vs. sprinted on."[/b] Touching the pad OVERWRITES velocity rather
## than adding to it, so a body that shuffled on and a body that sprinted on
## leave on exactly the same vector. That is the Halo reference and it is what
## makes this usable as a MAP-MAKING piece: a level author can place one knowing
## exactly where a player who touches it lands, rather than tuning it against
## however fast people happen to arrive. Adding launch velocity to whatever the
## body already had would make the same pad throw a walker three metres and a
## bunny-hopper across the whole map -- a trap for a level designer, not a tool.
##
## [b]Landing is not this node's business.[/b] No new landing state, no fall
## damage (the game has none), no special catch. The same
## [signal PlayerController.landed] a jump's landing fires drives the same
## landing audio ([code]scripts/audio/movement_audio_*.gd[/code], scaled by
## impact speed), and the body regains ordinary ground control on the tick it
## settles, same as after any fall. Anything bespoke here would be exactly the
## "special launched movement mode" the brief rules out.
##
## [b]Bots and ghosts hit it exactly as a human does, because there is no
## branch that could tell them apart.[/b] A [PlayerController] driven by a
## [HumanIntentSource], one driven by a [BotIntentSource] (see [RingRunner]),
## and a ghost's body under [MatchController] are the identical script, and
## this node only ever touches [member PlayerController.velocity], never an
## intent. A bot brain with no obstacle avoidance and no notion of "airborne"
## (RingRunner has neither) simply keeps issuing whatever wish direction it
## already had while the assigned velocity carries the body -- nothing to
## error on. A GHOST is the same body with
## [member PlayerController.speed_scale] raised (3.0 in the shipped
## [GhostProfile]); that multiplier scales only the WISH speed the ground and
## air accelerate routines chase (see [method PlayerController._air_accelerate]),
## never the velocity this node assigns, so a ghost leaves a pad on exactly the
## vector a human would and only out-accelerates them afterwards -- exactly how
## a ghost out-paces a human everywhere else in the game. [member collision_mask]
## is widened past the default living-body layer to include
## [constant MatchController.GHOST_HAZARD_LAYER] for exactly this reason; see
## [TrapVolume] for why that is the bit a ghost's body stands on.
##
## [b]It is a floor object, and unlike [TrapVolume] it lifts its own geometry to
## say so.[/b] [TrapVolume] centres its box on the node's own origin and leaves
## the half-height offset to whoever places it. A boost pad is something you
## WALK ONTO, so this node instead lifts both the detection shape and the drawn
## plate by half of [member footprint_metres.y], so the node's origin IS the
## walkable surface: drop it at floor height and the plate sits ON the floor,
## not half-buried in it.

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


func _ready() -> void:
	_build_shape()
	_size_the_plate()
	body_entered.connect(_on_body_entered)


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


func _on_body_entered(body: Node3D) -> void:
	var player: PlayerController = body as PlayerController
	if player == null:
		# Something that is not a player touched it. This node has no opinion
		# on what that is or what should happen to it -- see the class doc.
		return
	player.velocity = _launch_direction() * launch_speed


## The unit vector a body leaves along: this node's own forward, tilted
## [member launch_angle_degrees] towards this node's own up. Both basis columns
## are normalised individually before combining, so a pad instanced with any
## accidental non-uniform scale still launches along a true unit direction
## rather than a distorted one.
func _launch_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var up: Vector3 = global_transform.basis.y.normalized()
	var angle: float = deg_to_rad(launch_angle_degrees)
	return (forward * cos(angle) + up * sin(angle)).normalized()
