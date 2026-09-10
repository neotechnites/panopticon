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
## [b]The animation is the body's speed, not a clock.[/b] The glTF carries one
## clip, [code]Run[/code], twenty frames at 30 fps, looping. Its playback rate
## is set every frame from [method PlayerController.get_horizontal_speed]
## divided by the profile's [member MovementProfile.ground_speed], so a
## prisoner at their normal pace plays it as authored, an air-strafed prisoner
## at double speed plays it twice as fast, and a ghost on a [member
## GhostProfile.speed_multiplier] gets the faster cycle for free without
## anything having to tell this node about ghosts.
##
## Below [member idle_speed] a second clip, [member idle_clip], plays instead
## -- a slow breathing sway synthesised at runtime by [method
## _build_idle_animation] from the skeleton's own rest pose, since the glTF
## ships no idle of its own. A standing body used to be the [code]Run[/code]
## clip parked on frame 0 (a mid-stride freeze); now it is a body that
## breathes. [member run_resume_speed], set above [member idle_speed], is the
## other edge of a hysteresis band: crossing down into idle and back up into
## running each has its own threshold so a prisoner hovering right at the line
## does not flicker between clips every frame. Both transitions cross-fade
## over [member blend_time] rather than popping.
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

## The standing clip's name inside [member animation]. Not present in the
## glTF -- built once per instance by [method _build_idle_animation] and
## registered into [member animation]'s default library under this name.
@export var idle_clip: StringName = &"Idle"

## How long the synthesised idle takes to loop, in seconds. One full slow
## in-and-out breath.
@export var idle_period: float = 3.2

## How far the spine pitches off its rest pose at the peak of a breath, in
## degrees. Neck, head and both arms are children of Spine in the rig, so
## they ride along rigidly -- this one number is the whole idle's amplitude.
@export var idle_sway_degrees: float = 3.0

## Horizontal speed, in m/s, at or above which a standing body resumes
## [member run_clip]. Kept above [member idle_speed] on purpose: the gap
## between the two is a hysteresis band, so a body loitering right at the
## boundary does not flicker between idle and run every frame.
@export var run_resume_speed: float = 0.75

## Cross-fade duration, in seconds, used for both the idle-to-run and
## run-to-idle transitions.
@export var blend_time: float = 0.25

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

## Whether [member run_clip] is the one currently playing. False means the
## body is either idling on [member idle_clip] or, if that failed to build,
## parked on [member run_clip]'s first frame -- see [member _has_idle].
var _running: bool = false

## Whether [method _build_idle_animation] produced a usable [member
## idle_clip]. If it did not, [method _go_idle] falls back to the old
## park-on-frame-0 behaviour rather than calling [method AnimationPlayer.play]
## on a clip that does not exist.
var _has_idle: bool = false


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

	if not animation.has_animation(idle_clip):
		_build_idle_animation()
	_has_idle = animation.has_animation(idle_clip)
	if not _has_idle:
		push_error("PrisonerAvatar could not synthesise \"%s\"; a standing body will freeze mid-stride." % idle_clip)

	# Bootstrap into the parked pose, then let the first _process tick pick
	# the correct clip for the body's actual speed. Never left showing: a
	# spawn is at worst one frame of frame-0 before _go_idle or the run path
	# below takes over.
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

	if _running and speed < idle_speed:
		_go_idle()
		return

	if not _running:
		if speed < run_resume_speed:
			return
		_running = true
		animation.play(run_clip, blend_time)

	animation.speed_scale = minf(speed / reference, max_playback_scale)


## Switch to the standing idle, cross-fading in over [member blend_time]. Only
## does anything on the tick the body newly stops -- called every tick while
## idle would otherwise restart the cross-fade against itself.
func _go_idle() -> void:
	_running = false
	if not _has_idle:
		_park()
		return
	animation.speed_scale = 1.0
	if animation.current_animation != idle_clip:
		animation.play(idle_clip, blend_time)


## Freeze the run cycle on its first frame. The fallback for a body with no
## idle clip, and the bootstrap pose in [method _ready] before the first
## [method _process] tick decides which clip actually belongs.
func _park() -> void:
	animation.speed_scale = 0.0
	animation.seek(0.0, true)


## Synthesises a standing idle from the skeleton's own rest pose -- no new
## asset, no Blender pass. [member run_clip]'s own tracks are read only to
## learn the [Skeleton3D]'s path relative to [member animation]'s root node;
## every bone is then pinned to [method Skeleton3D.get_bone_rest], which is
## already a standing pose with the arms hanging at the sides -- it is the
## pose [member run_clip] was itself animated away from, not a T-pose (see
## [code]assets/models/runner.glb[/code]: every bone's rest translation and
## scale is constant across every [code]Run[/code] frame; only rotation, and
## for Hips also position, ever move).
##
## Spine is the only bone given motion: a slow pitch about the X axis,
## amplitude [member idle_sway_degrees], composed as [code]sway * rest[/code]
## -- the sway applied in the [i]parent's[/i] space, after the rest
## orientation, never [code]rest * sway[/code] in the bone's own local space.
## That ordering is what keeps this safe to write blind: Spine, like Hips,
## Neck and Head, has an identity rest rotation in the glTF, so parent space
## and bone space already agree there and no bone-roll reasoning is needed at
## all. It is exactly the limb bones -- shoulders, elbows, hips, knees --
## where rest rotation is not identity and local X stops meaning world X, and
## this function never rotates any of those; it only pins them back to rest.
## Because Neck, Head and both arms are children of Spine in the rig, they
## ride along rigidly when it pitches, which is what reads as the whole
## ribcage breathing rather than a chest twitching on its own while a frozen
## upper body hangs off it.
func _build_idle_animation() -> void:
	var run_anim: Animation = animation.get_animation(run_clip)
	if run_anim.get_track_count() == 0:
		push_error("PrisonerAvatar's \"%s\" clip has no tracks; cannot derive the skeleton path." % run_clip)
		return

	var sample_path: String = String(run_anim.track_get_path(0))
	var colon: int = sample_path.find(":")
	if colon == -1:
		push_error("PrisonerAvatar cannot derive the skeleton path from \"%s\"'s tracks; idle will not be built." % run_clip)
		return
	var skeleton_rel_path: String = sample_path.substr(0, colon)

	var anim_root: Node = animation.get_node(animation.root_node)
	var skeleton: Skeleton3D = anim_root.get_node_or_null(NodePath(skeleton_rel_path)) as Skeleton3D
	if skeleton == null:
		push_error("PrisonerAvatar could not resolve a Skeleton3D at \"%s\"; idle will not be built." % skeleton_rel_path)
		return

	var idle_anim := Animation.new()
	idle_anim.length = idle_period
	idle_anim.loop_mode = Animation.LOOP_LINEAR

	var sway_steps: int = 16
	var sway_radians: float = deg_to_rad(idle_sway_degrees)

	for bone_idx in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(bone_idx)
		var rest: Transform3D = skeleton.get_bone_rest(bone_idx)
		var rest_quat: Quaternion = rest.basis.get_rotation_quaternion()
		var track_path := NodePath(skeleton_rel_path + ":" + bone_name)

		var rot_track: int = idle_anim.add_track(Animation.TYPE_ROTATION_3D)
		idle_anim.track_set_path(rot_track, track_path)

		if bone_name == "Spine":
			for step in range(sway_steps + 1):
				var t: float = idle_period * float(step) / float(sway_steps)
				var angle: float = sway_radians * sin(TAU * t / idle_period)
				var sway: Quaternion = Quaternion(Vector3.RIGHT, angle)
				idle_anim.rotation_track_insert_key(rot_track, t, sway * rest_quat)
		else:
			idle_anim.rotation_track_insert_key(rot_track, 0.0, rest_quat)

		if bone_name == "Hips":
			var pos_track: int = idle_anim.add_track(Animation.TYPE_POSITION_3D)
			idle_anim.track_set_path(pos_track, track_path)
			idle_anim.position_track_insert_key(pos_track, 0.0, rest.origin)

	var library: AnimationLibrary
	if animation.has_animation_library(&""):
		library = animation.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		animation.add_animation_library(&"", library)
	library.add_animation(idle_clip, idle_anim)
