class_name PrisonerAvatar
extends Node3D

## The humanoid a prisoner is seen as: [code]assets/models/runner.glb[/code]
## hung on a [PlayerController] and driven by that body's own speed.
##
## [b]It is a costume, not a body.[/b] Nothing here is read by physics, by the
## rifle's raycast or by the kill volume -- those all use the capsule on the
## [CharacterBody3D] this node is parented to, and the capsule is unchanged. The
## model is authored 1.80 m tall with its origin between the feet, which is
## exactly the capsule ([code]radius 0.4, height 1.8[/code], centred at
## [code]y = 0.9[/code]), so it sits at the body's origin at identity scale and
## the silhouette a shooter leads is the volume they hit.
##
## The one transform it does carry is a half turn about Y, authored on the node
## in [code]scenes/player/prisoner_avatar.tscn[/code]. The glTF is modelled with
## its toes towards +Z -- see the foot vertices, which run from -0.05 to +0.15 --
## and [PlayerController] takes -Z as forward, so without the flip every prisoner
## in the game runs backwards.
##
## [b]The animation is the body's speed, not a clock.[/b] There is one clip,
## [code]Run[/code], twenty frames at 30 fps, looping. Its playback rate is set
## every frame from [method PlayerController.get_horizontal_speed] divided by the
## profile's [member MovementProfile.ground_speed], so a prisoner at their normal
## pace plays it as authored, an air-strafed prisoner at double speed plays it
## twice as fast, and a ghost on a [member GhostProfile.speed_multiplier] gets the
## faster cycle for free without anything having to tell this node about ghosts.
## Below [member idle_speed] the clip is parked on its first frame instead, so a
## body standing in the tower is standing rather than running on the spot.
##
## Dividing by the LIVE profile rather than a constant matters: [method
## PlayerController.set_profile] can swap the tunables mid-stride, and a movement
## sweep that doubles ground_speed must not also double how fast every prisoner's
## legs appear to move relative to the ground.

## The body this costume belongs to. Set from the scene that owns both -- see
## [code]scenes/player/player.tscn[/code], which points it at the
## [CharacterBody3D] this node hangs under.
@export var body: PlayerController

## The skinned mesh inside the imported model. Named here rather than found by
## searching, so a rename in the glTF is a load error with a path in it instead
## of a prisoner who is silently invisible.
@export var mesh: MeshInstance3D

## The [AnimationPlayer] the glTF imported, holding [member run_clip].
@export var animation: AnimationPlayer

## The run cycle's name inside [member animation].
@export var run_clip: StringName = &"Run"

## Which visual layer the mesh draws on, authored per body.
##
## Layer 2 is the owner-hidden layer: every [Camera3D] in the game inherits the
## cull_mask on [code]scenes/player/player.tscn[/code], which clears bit 2, so a
## mesh left here is never drawn from a player's viewpoint -- which is what stops
## the human from looking at the inside of their own head, since their eye sits
## at 1.65 m and the model's skull is around it. Layer 3 is where every body that
## is NOT the local viewpoint goes, and the two AI scenes that inherit the player
## set it. This is a flag field, so layer 3 is the value 4.
@export_flags_3d_render var visual_layers: int = 2

## The material the whole body wears, or null to keep the flat grey the model was
## imported with.
##
## It is written to the mesh's [member GeometryInstance3D.material_override], and
## that is deliberate: [method MatchController._tint_body] reads and writes the
## same field to turn a prisoner into a ghost and back, so the authored colour
## set here is exactly the colour a ghost is restored to.
@export var body_material: Material

## Horizontal speed, in m/s, below which the body is treated as standing still
## and the run cycle is parked rather than played.
@export var idle_speed: float = 0.5

## Ceiling on the playback rate, as a multiple of the authored rate. Air strafing
## has no speed limit, and without this a fast enough prisoner's legs become a
## strobe.
@export var max_playback_scale: float = 2.5

## Ground speed used when the body has no [MovementProfile] to divide by. Only a
## body that is already broken can reach it -- [PlayerController] refuses to move
## without a profile -- so it exists to keep this node from dividing by zero
## rather than to be tuned.
@export var fallback_ground_speed: float = 11.0

## Whether the clip is currently being played rather than parked, so the seek
## back to the first frame happens on the tick the body stops and not on every
## tick it spends standing.
var _running: bool = false


func _ready() -> void:
	if mesh == null or animation == null:
		push_error("PrisonerAvatar is missing its mesh or its AnimationPlayer; the body has no visible form.")
		set_process(false)
		return

	mesh.layers = visual_layers
	if body_material != null:
		mesh.material_override = body_material

	if not animation.has_animation(run_clip):
		push_error("PrisonerAvatar cannot find the animation \"%s\"; the body will not move." % run_clip)
		set_process(false)
		return

	# Started once and never stopped. Standing still is speed_scale 0 parked on
	# frame one, not a stopped player: restarting a clip every time a prisoner
	# steps off would pop the pose on every single footfall.
	animation.play(run_clip)
	_running = true
	_park()


func _process(_delta: float) -> void:
	if body == null:
		return

	var reference: float = fallback_ground_speed
	if body.profile != null:
		reference = body.profile.ground_speed
	if reference <= 0.0:
		reference = fallback_ground_speed

	var speed: float = body.get_horizontal_speed()
	if speed < idle_speed:
		_park()
		return

	_running = true
	animation.speed_scale = minf(speed / reference, max_playback_scale)


## Freeze the run cycle on its first frame. Cheap to call every tick: only the
## tick that finds the body newly stopped does any work.
func _park() -> void:
	animation.speed_scale = 0.0
	if not _running:
		return
	animation.seek(0.0, true)
	_running = false
