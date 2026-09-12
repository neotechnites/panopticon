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
##
## [b]The slide is a pose, not a cycle.[/b] A third clip, [member slide_clip], is
## synthesised the same way the idle is -- one static key per bone, no motion --
## and the body snaps into it over [member slide_blend_time], a tenth of the
## ordinary [member blend_time], because a slide is an event and easing into it
## reads as sinking rather than dropping. It is driven off [method
## PlayerController.is_sliding], never off velocity: the slide state has a real
## duration, a cooldown and three separate exits, and only the controller knows
## which one fired. That is also what makes a bot's slide animate identically to
## a human's -- neither this node nor [PlayerController] ever reads [Input], so
## whatever moved the body is what the costume follows.
##
## [b]The crouch is a pose too, and a slower one.[/b] A fourth clip,
## [member crouch_clip], is built the same way from the same bind pose and
## driven off [method PlayerController.is_crouching]. It blends over the
## ordinary [member blend_time] rather than the slide's snap, because a crouch is
## a stance a player settles into and holds, not a thing that happens to them.
## The slide outranks it in [method _process] for the same reason it outranks the
## speed clips: it is the more specific state, and the controller never reports
## both.
##
## Unlike the slide, this pose has a real capsule behind it -- the controller
## drops the collision height to [member MovementProfile.crouch_height] -- so
## getting the silhouette roughly right is not decoration. A crouched prisoner
## drawn standing would be a body the guard cannot hit at a height he can see.
##
## [b]The jump is airborne rather than jumping.[/b] A fifth clip, [member
## jump_clip], is authored in [code]assets/models/runner.glb[/code] -- unlike
## idle, slide and crouch, there is no bind-pose fallback for it -- and shown
## whenever the body is off the floor, however it got there: a jump, a fall off
## a ledge, a ramp taken fast enough to leave it. There is only the one clip for
## all three, because there is only one thing wrong with the alternative: a
## prisoner in mid-air was running on the spot, and a body with no ground under
## it should not be taking strides on it.
##
## It is driven off [method CharacterBody3D.is_on_floor] on the body, plus the
## [signal PlayerController.jumped] signal, and off velocity never. Which is not
## fussiness: [member PlayerController.velocity]'s y is zeroed on the floor every
## tick and is a large negative number a fifth of a second into a fall, so
## "moving up or down" cannot tell a hop from a ramp descent, whereas the floor
## flag is the same thing [method PlayerController._try_jump] and
## [method PlayerController._update_crouch] themselves rule on. And, as with the
## slide, that is what makes a bot's jump animate identically to a human's --
## [RingRunner] sets [member MoveIntent.jump_pressed] and a keyboard sets
## [member MoveIntent.jump_pressed], and neither this node nor [PlayerController]
## can tell which one did.
##
## The two sources do different jobs. [signal PlayerController.jumped] ARMS the
## pose on the launch tick, so a deliberate hop snaps into it with no delay. The
## floor flag alone has to wait out [member air_pose_delay] first, because
## [method CharacterBody3D.is_on_floor] genuinely flickers false for a tick or
## two over a seam, a kerb lip or the join between one deck and a ramp, and a
## prisoner running up a ramp must not strobe between running and airborne all
## the way up it. Landing is not debounced at either end: the pose is dropped the
## first tick there is floor again.
##
## [b]Death outranks everything, and Aim is the guard's stance.[/b] Both,
## like Jump, are authored clips in the glTF. [signal PlayerController.died]
## arms [member death_clip], which holds -- nothing below it is checked again
## -- until the body's speed crosses [member run_resume_speed], which is what a
## respawned ghost does the moment it starts moving. [member aim_clip] is
## simpler: it plays for as long as [member PlayerController.is_guard] is
## true, one seat's whole occupancy, so it sits above slide/crouch/airborne too
## -- a body in the tower does not do any of those.
##
## [b]The order the seven clips are chosen in[/b], highest first, is death,
## aim, slide, crouch, airborne, run, idle -- and the middle three are the only
## ones worth arguing about. Slide is top of that group because it is the most
## specific state the
## controller reports and the only one it will not report at the same time as
## anything else ([method PlayerController._try_begin_slide] needs the floor,
## and [method PlayerController._update_slide_exit] closes a slide the tick the
## body leaves it, so slide and airborne cannot both be true anyway).
##
## Crouch sits ABOVE airborne, which is worth saying out loud because it is the
## one place the two really can overlap: [method PlayerController._update_crouch]
## refuses to stand a body up with no headroom, so a prisoner who jumps under a
## low ceiling stays crouched in the air. It is drawn crouched, because in that
## state the collision capsule really is [member MovementProfile.crouch_height]
## and the silhouette has to be the volume a shooter hits -- the same argument
## that gives the crouch pose its own exports. Airborne changes no capsule at
## all, so where the two disagree the one with the capsule behind it wins.

## The body this costume belongs to. Set from the scene that owns both -- see
## [code]scenes/player/player.tscn[/code], which points it at the
## [CharacterBody3D] this node hangs under.
## The head-collapsing modifier, by path rather than by class name so that a
## headless run does not depend on a global class cache having been built.
const FirstPersonHead: GDScript = preload("res://scripts/player/first_person_head.gd")

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

## The slide pose's name inside [member animation]. Like [member idle_clip] it
## is not in the glTF -- [method _build_slide_animation] builds it once per
## instance from the skeleton's rest pose.
@export var slide_clip: StringName = &"Slide"

## Cross-fade duration, in seconds, into the slide pose. Deliberately far
## shorter than [member blend_time]: the brief for a slide is a snap, and a
## quarter-second ease into it looks like the prisoner is sinking through the
## floor rather than throwing themselves at it. Leaving the slide uses the
## ordinary [member blend_time], because standing back up is not an event.
@export var slide_blend_time: float = 0.06

## How far the hips pitch backwards out of the rest pose in the slide, in
## degrees. This one number does most of the work: every other bone in the rig
## hangs off Hips, so pitching it swings the legs forward and the torso back in
## a single rotation, which is the whole silhouette of a slide.
@export var slide_lean_degrees: float = 55.0

## How far the body rolls onto one hip in the slide, in degrees. A flourish, not
## structure -- set it to zero for a square-on baseball slide.
@export var slide_roll_degrees: float = 8.0

## The hips' height above the feet during the slide, in metres, against a rest
## height of 0.9. Chosen so the extended leg's ankle lands just above the floor
## at [member slide_lean_degrees]: the legs are 0.765 m of bone, and at a 55
## degree lean they drop 0.765 * cos(55) = 0.44 m below the hip joint. Lower
## this without lowering the lean and the heel goes through the ground.
@export var slide_hip_height: float = 0.5

## The crouch pose's name inside [member animation]. Like [member idle_clip] and
## [member slide_clip] it is not in the glTF; [method _build_crouch_animation]
## builds it once per instance from the skeleton's rest pose.
@export var crouch_clip: StringName = &"Crouch"

## How far the pelvis pitches FORWARD out of the rest pose in the crouch, in
## degrees.
##
## Note the sign: this is the opposite convention to [member slide_lean_degrees],
## which is named for a backwards lean and is negated where it is used. Here a
## positive number leans into the crouch, the same way a positive entry in
## [constant CROUCH_POSE_DEGREES] does, because everything about this pose reads
## as forward and a lean that had to be authored negative would be a trap.
@export var crouch_lean_degrees: float = 12.0

## The hips' height above the feet while crouched, in metres, against a rest
## height of 0.9 and the slide's 0.5.
##
## It is the number that decides whether the model fits the capsule: at 0.48,
## with the spine curl in [constant CROUCH_POSE_DEGREES], the skull finishes at
## roughly 1.2 m -- which is [member MovementProfile.crouch_height], the height
## the collision capsule really is. Raise this without raising that and the
## prisoner's head is drawn in space a bullet passes straight through.
@export var crouch_hip_height: float = 0.48

## The airborne clip's name inside [member animation]. Authored in
## [code]assets/models/runner.glb[/code], unlike idle/slide/crouch.
@export var jump_clip: StringName = &"Jump"

## Cross-fade duration, in seconds, into the airborne pose.
##
## Between the slide's snap and the ordinary [member blend_time], and for a
## reason: leaving the ground is an event, so easing into it over a quarter of a
## second would have the legs still mid-stride at the apex of a hop that only
## lasts 0.64 s at the shipped [member MovementProfile.jump_velocity] -- but it
## is not the impact a slide is, and the slide's 0.06 reads as a twitch here.
## Coming back down uses the ordinary [member blend_time], because the clip that
## takes over on landing is the run cycle and cutting hard to it looks like a
## skipped frame.
@export var jump_blend_time: float = 0.1

## How long the body must be off the floor, in seconds, before the airborne pose
## takes over -- when nothing told this node a jump had happened.
##
## A debounce, and only a debounce. [method CharacterBody3D.is_on_floor] reports
## false for a tick or two over a seam in the deck, the lip of a kerb, or the
## join between a deck and a ramp, and without this a prisoner running up a ramp
## flickers between the run cycle and the airborne pose the whole way up it. A
## real jump never pays it: [signal PlayerController.jumped] arms the pose on the
## launch tick, so this delay is only ever spent by a body that FELL, where a
## twelfth of a second is under 3 cm of drop and nobody sees it.
##
## Landing has no equivalent and must not grow one. The tick there is floor
## again, the body is running.
@export var air_pose_delay: float = 0.08

## The death clip's name inside [member animation]. Authored in the glTF,
## non-looping, and arms on [signal PlayerController.died].
@export var death_clip: StringName = &"Death"

## The guard's stance clip's name inside [member animation]. Authored in the
## glTF, looping, and shown for as long as [member PlayerController.is_guard].
@export var aim_clip: StringName = &"Aim"

## The shove clip's name inside [member animation]. Authored in the glTF,
## non-looping, and played as a one-shot on [signal PlayerController.shoved].
@export var shove_clip: StringName = &"Shove"

## Seconds blended into and out of [member shove_clip]. Short: a shove that
## eases in is a shove that has already missed.
@export var shove_blend_time: float = 0.06

## Which visual layer the mesh draws on, authored per body.
##
## Layer 2 is the owner-hidden layer: every [Camera3D] in the game inherits the
## cull_mask on [code]scenes/player/player.tscn[/code], which clears bit 2, so a
## mesh left here is never drawn from a player's viewpoint. It is where a body
## sits while nobody is looking out of it. Layer 3, the value 4, is where every
## body that is NOT the local viewpoint goes, and the two AI scenes set it. The
## body the human IS looking out of adds [member first_person_layers].
@export_flags_3d_render var visual_layers: int = 2

## The layer the mesh is ALSO drawn on while this body is the local viewpoint,
## so its owner can see their own legs and arms. Layer 1, which no camera
## clears; the head is collapsed instead -- see [member head_bone].
@export_flags_3d_render var first_person_layers: int = 1

## The bone collapsed while this body is the local viewpoint. Its geometry is
## what the eye at 1.65 m would otherwise be inside of.
@export var head_bone: StringName = &"Head"

## The bone collapsed in first person alongside [member head_bone], taking the
## torso and the arms with it. Restored while [member shove_clip] plays.
@export var spine_bone: StringName = &"Spine"

## The bones collapsed in first person while this body holds a rifle, so the aim
## pose's raised arms are not drawn across the camera.
@export var arm_bones: Array[StringName] = [&"UpperArm.L", &"UpperArm.R"]

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

## Whether [method _build_slide_animation] produced a usable [member
## slide_clip]. False disables the slide branch entirely, leaving a sliding
## prisoner on the run cycle -- the pre-slide behaviour, not a crash.
var _has_slide: bool = false

## Whether the body was in the slide pose last tick. The edge, not the state:
## [method AnimationPlayer.play] is called once on the tick the slide opens, and
## calling it again while the slide is still open would restart the snap against
## itself every frame.
var _in_slide: bool = false

## Whether [method _build_crouch_animation] produced a usable
## [member crouch_clip]. False disables the crouch branch entirely, leaving a
## crouched prisoner on whichever speed clip its pace calls for -- wrong, but
## still animating, which is the same fallback the slide takes.
var _has_crouch: bool = false

## Whether the body was in the crouch pose last tick. The edge, for the same
## reason [member _in_slide] is one.
var _in_crouch: bool = false

## Whether [member jump_clip] was found in the glTF. False leaves a jumping
## prisoner running on the spot in mid-air, the pre-jump behaviour.
var _has_jump: bool = false

## Whether the body was in the airborne pose last tick. The edge, for the same
## reason [member _in_slide] is one.
var _in_air: bool = false

## Seconds the body has been off the floor, reset to zero the moment there is
## floor again. Compared against [member air_pose_delay]; see there for why a
## fall is debounced and a jump is not.
var _air_seconds: float = 0.0

## Set by [signal PlayerController.jumped] and cleared on the next touchdown.
## The whole of what the signal is for: it says "this body is airborne ON
## PURPOSE", which is the case that skips [member air_pose_delay].
var _jump_armed: bool = false

## Whether [member death_clip] was found in the glTF.
var _has_death: bool = false

## Set by [signal PlayerController.died], cleared once the body's speed
## crosses [member run_resume_speed] again -- a respawned ghost moving under
## its own power, the only way this body gets a second act.
var _dead: bool = false

## Whether the body was in the death pose last tick. The edge, for the same
## reason [member _in_slide] is one.
var _in_death: bool = false

## Whether [member aim_clip] was found in the glTF.
var _has_aim: bool = false

## Whether the body was in the guard's stance last tick. The edge, for the
## same reason [member _in_slide] is one.
var _in_aim: bool = false

## Whether [member shove_clip] was found in the glTF.
var _has_shove: bool = false

## Seconds of [member shove_clip] left to play. Above zero the shove owns the
## body and every other pose waits, which is the whole of its state.
var _shove_remaining: float = 0.0

## This body's own camera, or null. Non-null and current means the human is
## looking out of this body and must be shown their own legs.
var _camera: Camera3D = null

## Collapses [member head_bone] while this body is the local viewpoint. Null
## when the skeleton could not be resolved, which keeps the body hidden.
var _head_hider: FirstPersonHead = null

## Collapses [member spine_bone], and the arm bones, on the same terms. Null
## when the rig has no such bone.
var _spine_hider: FirstPersonHead = null
var _arm_hiders: Array[FirstPersonHead] = []

## Whether each of those is collapsed right now. Edges, like [member _in_slide].
var _spine_hidden: bool = false
var _arms_hidden: bool = false

## Whether the mesh is currently drawn in first person. The edge, for the same
## reason [member _in_slide] is one.
var _first_person: bool = false


func _ready() -> void:
	if mesh == null or animation == null:
		push_error("PrisonerAvatar is missing its mesh or its AnimationPlayer; the body has no visible form.")
		set_process(false)
		return

	mesh.layers = visual_layers
	_self_light_skin()
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

	if not animation.has_animation(slide_clip):
		_build_slide_animation()
	_has_slide = animation.has_animation(slide_clip)
	if not _has_slide:
		push_error("PrisonerAvatar could not synthesise \"%s\"; a sliding body will keep running along the floor." % slide_clip)

	if not animation.has_animation(crouch_clip):
		_build_crouch_animation()
	_has_crouch = animation.has_animation(crouch_clip)
	if not _has_crouch:
		push_error("PrisonerAvatar could not synthesise \"%s\"; a crouched body will be drawn standing up." % crouch_clip)

	_has_jump = animation.has_animation(jump_clip)
	if not _has_jump:
		push_error("PrisonerAvatar cannot find \"%s\"; an airborne body will run on the spot in mid-air." % jump_clip)

	_has_death = animation.has_animation(death_clip)
	if not _has_death:
		push_error("PrisonerAvatar cannot find \"%s\"; a killed body will not visibly react." % death_clip)

	_has_aim = animation.has_animation(aim_clip)
	if not _has_aim:
		push_error("PrisonerAvatar cannot find \"%s\"; the guard will be drawn running or standing idle." % aim_clip)

	_has_shove = animation.has_animation(shove_clip)
	if not _has_shove:
		push_error("PrisonerAvatar cannot find \"%s\"; a shove will not be visible on the body making it." % shove_clip)

	if body != null:
		_camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	_build_head_hider()

	# The signal is the fast path into the airborne pose, not the only one --
	# see _tick_air. Connected rather than polled because a jump is an event
	# with a tick attached to it, and _process runs on the render clock: at a
	# high enough frame rate polling would see the launch tick more than once,
	# and at a low enough one it could miss a short hop's rise entirely.
	if body != null and not body.jumped.is_connected(_on_body_jumped):
		body.jumped.connect(_on_body_jumped)

	if body != null and not body.died.is_connected(_on_body_died):
		body.died.connect(_on_body_died)

	if body != null and not body.shoved.is_connected(_on_body_shoved):
		body.shoved.connect(_on_body_shoved)

	# Bootstrap into the parked pose, then let the first _process tick pick
	# the correct clip for the body's actual speed. Never left showing: a
	# spawn is at worst one frame of frame-0 before _go_idle or the run path
	# below takes over.
	animation.play(run_clip)
	_running = true
	_park()


func _process(delta: float) -> void:
	if body == null:
		return

	# Before any branch below can return: the airborne clock has to keep running
	# under the slide and the crouch as well, or a body that slid off a ledge
	# would start counting its fall from whenever the slide happened to close.
	_tick_air(delta)
	_tick_first_person()

	# Death outranks everything: whatever the body was doing when it was shot
	# is no longer happening. It holds until the body moves under its own power
	# again -- a respawned ghost picking the chase back up -- rather than on a
	# timer, because nothing else here knows how long the respawn hold lasts.
	if _has_death and _dead:
		if body.get_horizontal_speed() >= run_resume_speed:
			_dead = false
			_in_death = false
		else:
			if not _in_death:
				_in_death = true
				_in_slide = false
				_in_crouch = false
				_in_air = false
				_in_aim = false
				_running = false
				animation.speed_scale = 1.0
				animation.play(death_clip, blend_time)
			return

	# The guard's stance, asked for rather than inferred exactly like the slide
	# and the crouch: it is whatever MatchController._place_in_tower says, for
	# as long as it says it, which is a whole seat's occupancy rather than an
	# event.
	# Above death, below nothing else: a shove is short enough that whatever the
	# body was doing can wait, and the flags _on_body_shoved cleared make every
	# pose below re-play itself on the tick it runs out.
	if _shove_remaining > 0.0:
		_shove_remaining -= delta
		if _shove_remaining > 0.0:
			return

	if _has_aim and body.is_guard:
		if not _in_aim:
			_in_aim = true
			_in_slide = false
			_in_crouch = false
			_in_air = false
			_running = false
			animation.speed_scale = 1.0
			animation.play(aim_clip, blend_time)
		return

	var leaving_aim: bool = _in_aim
	_in_aim = false

	# The slide outranks both speed clips, and it is asked for rather than
	# inferred: a slide runs at run speed, so velocity alone cannot tell the two
	# apart, and the state's exits (the timer, the speed floor, the released
	# key) are the controller's to decide.
	if _has_slide and body.is_sliding():
		if not _in_slide:
			_in_slide = true
			# Whatever pose was showing is gone, and its edge flag has to go
			# with it or the tick that pose is next asked for will decide it is
			# already playing and never call play(). The controller will not
			# report two of these at once, but it does hand them straight to
			# each other -- a crouch re-pressed into a slide, a slide that ends
			# with the key still down, a slide off the edge of the deck -- and
			# every one of those is a handover this clear is what survives.
			_in_crouch = false
			_in_air = false
			_running = false
			# The pose holds no motion, so the rate only governs how fast the
			# cross-fade into it runs; a scale left over from the run cycle
			# would make the snap arrive at a speed-dependent moment.
			animation.speed_scale = 1.0
			animation.play(slide_clip, slide_blend_time)
		return

	# The tick a slide closes. _running is already false, so the ordinary
	# selection below picks the clip up again -- except in the one case it
	# cannot, a slide that ended below run_resume_speed, which would otherwise
	# leave the body frozen in the pose.
	var leaving_slide: bool = _in_slide
	_in_slide = false

	# The crouch sits directly under the slide and above both speed clips, and
	# is asked for rather than inferred for the same reason: a crouched prisoner
	# may be walking at crouch_speed or standing perfectly still, and only the
	# controller knows the key is down. It blends over the ordinary blend_time,
	# not the slide's snap -- a stance, not an impact.
	if _has_crouch and body.is_crouching():
		if not _in_crouch:
			_in_crouch = true
			# The airborne edge, for the reason the slide branch clears both of
			# its neighbours. This one is reachable: a body jumped under a low
			# ceiling comes down still crouched, because
			# PlayerController._update_crouch will not stand it up without the
			# headroom to do it in.
			_in_air = false
			_running = false
			# The pose holds no motion, so a speed_scale left over from the run
			# cycle would only make the cross-fade arrive at a speed-dependent
			# moment.
			animation.speed_scale = 1.0
			animation.play(crouch_clip, blend_time)
		return

	# The tick a crouch ends. Folded into leaving_slide because both leave the
	# body on a static pose with _running false, and both have the same failure
	# if nothing picks a clip up: a prisoner standing up out of a crouch is
	# usually below run_resume_speed, which is exactly the case that would leave
	# them frozen mid-squat.
	var leaving_pose: bool = leaving_slide or _in_crouch or leaving_aim
	_in_crouch = false

	# Airborne sits directly above the speed clips and below both stances. See
	# the class docs for the whole order; the short of it is that this is the
	# only one of the three special poses that does not change the collision
	# capsule, so where it disagrees with one that does, it loses. Like them it
	# is asked for and never inferred -- from the floor flag and the jump
	# signal, both of which read the same way whether a keyboard or a RingRunner
	# raised MoveIntent.jump_pressed.
	if _has_jump and _is_airborne():
		if not _in_air:
			_in_air = true
			_running = false
			# The pose holds no motion, so a scale left over from the run cycle
			# would only make the cross-fade arrive at a speed-dependent moment.
			animation.speed_scale = 1.0
			animation.play(jump_clip, jump_blend_time)
		return

	# The tick a body lands, folded into leaving_pose for exactly the reason the
	# crouch is: a prisoner who drops onto a spot and stops is below
	# run_resume_speed on the landing tick, and without this would be left
	# holding the airborne pose with both feet on the floor.
	leaving_pose = leaving_pose or _in_air
	_in_air = false

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
			if leaving_pose:
				_go_idle()
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


## Advance the airborne clock, or clear it because there is floor again.
##
## Called before any of the pose branches can return, so the clock is a property
## of the body rather than of whichever clip happened to be playing.
func _tick_air(delta: float) -> void:
	if body.is_grounded():
		_air_seconds = 0.0
		_jump_armed = false
		return
	_air_seconds += delta


## Whether the body should be drawn in the air. Floor first and always: a
## grounded body is never airborne, whatever the clock or the arm flag say --
## which is what keeps an [member air_pose_delay] of 0.0 from reading as "always
## airborne" through the [code]>=[/code] below.
func _is_airborne() -> bool:
	if body.is_grounded():
		return false
	return _jump_armed or _air_seconds >= air_pose_delay


## A jump left the ground this tick, so skip [member air_pose_delay]. Cleared by
## [method _tick_air] on the next touchdown, which is also what re-arms it for
## the next hop -- including the next hop of a bunny-hop chain, where
## [member MovementProfile.auto_bunny_hop] re-launches on the landing tick and
## this fires again immediately.
func _on_body_jumped() -> void:
	_jump_armed = true


## The body was shot out. Arms the death pose; see [member _dead] for how it
## is cleared.
func _on_body_died() -> void:
	_dead = true
	_shove_remaining = 0.0


## This body just shoved somebody. Take the clip over whatever was playing and
## clear the pose flags, so each one re-plays itself when the shove runs out.
func _on_body_shoved() -> void:
	if not _has_shove or _dead:
		return
	_shove_remaining = animation.get_animation(shove_clip).length
	_in_slide = false
	_in_crouch = false
	_in_air = false
	_in_aim = false
	_running = false
	animation.speed_scale = 1.0
	animation.play(shove_clip, shove_blend_time)


## Draw this body for its own owner, or stop. One bool per frame: the camera is
## current only on the body the human is looking out of, and bots never are.
func _tick_first_person() -> void:
	var want: bool = _head_hider != null and _camera != null and _camera.is_current()
	if want != _first_person:
		_first_person = want
		_head_hider.set_hidden(want)
		mesh.layers = (visual_layers | first_person_layers) if want else visual_layers

	# The torso goes with the head: in first person the body is in the way. The
	# shove is the one clip whose point is seeing your own arms, so it gets them
	# back -- the head stays collapsed throughout, on its own modifier.
	var hide_spine: bool = want and _shove_remaining <= 0.0
	if _spine_hider != null and hide_spine != _spine_hidden:
		_spine_hidden = hide_spine
		_spine_hider.set_hidden(hide_spine)

	# Redundant while the spine is down, and not while the shove has it back.
	var hide_arms: bool = hide_spine and (body.is_guard or body.is_armed)
	if hide_arms != _arms_hidden:
		_arms_hidden = hide_arms
		for hider: FirstPersonHead in _arm_hiders:
			hider.set_hidden(hide_arms)


## Hang a [FirstPersonHead] off the skeleton for each bone first person hides,
## all inactive. Left null when there is no skeleton, which keeps the body
## owner-hidden.
func _build_head_hider() -> void:
	var found: Array = _resolve_skeleton()
	if found.is_empty():
		return
	var skeleton: Skeleton3D = found[1]
	_head_hider = _add_hider(skeleton, head_bone, "FirstPersonHead")
	_spine_hider = _add_hider(skeleton, spine_bone, "FirstPersonSpine")
	for bone_name: StringName in arm_bones:
		var arm: FirstPersonHead = _add_hider(
			skeleton, bone_name, "FirstPersonArm%d" % _arm_hiders.size()
		)
		if arm != null:
			_arm_hiders.append(arm)


## One inactive [FirstPersonHead] on [param bone_name], or null if the rig has
## no bone by that name.
func _add_hider(
	skeleton: Skeleton3D, bone_name: StringName, node_name: String
) -> FirstPersonHead:
	var bone: int = skeleton.find_bone(String(bone_name))
	if bone < 0:
		push_error("PrisonerAvatar cannot find the bone \"%s\"; the local body will show it." % bone_name)
		return null
	var hider: FirstPersonHead = FirstPersonHead.new()
	hider.name = node_name
	hider.bone = bone
	hider.active = false
	skeleton.add_child(hider)
	return hider


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
	var found: Array = _resolve_skeleton()
	if found.is_empty():
		return
	var skeleton_rel_path: String = found[0]
	var skeleton: Skeleton3D = found[1]

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


## Resolves the [Skeleton3D] that [member run_clip] animates, together with its
## node path relative to [member animation]'s root node -- the prefix every bone
## track's path has to carry, spelled [code]<path>:<bone name>[/code]. Returned
## as [code][path, skeleton][/code], or an empty array if any link in that chain
## is missing, having already pushed the error naming which one.
##
## The glTF's own clip is used as the map because it is the one thing guaranteed
## to point at the right skeleton: hard-coding [code]"Armature/Skeleton3D"[/code]
## here would silently desync the day the model is re-exported under a different
## node name, whereas reading it off a track cannot.
func _resolve_skeleton() -> Array:
	var run_anim: Animation = animation.get_animation(run_clip)
	if run_anim.get_track_count() == 0:
		push_error("PrisonerAvatar's \"%s\" clip has no tracks; cannot derive the skeleton path." % run_clip)
		return []

	var sample_path: String = String(run_anim.track_get_path(0))
	var colon: int = sample_path.find(":")
	if colon == -1:
		push_error("PrisonerAvatar cannot derive the skeleton path from \"%s\"'s tracks; synthesised clips will not be built." % run_clip)
		return []
	var skeleton_rel_path: String = sample_path.substr(0, colon)

	var anim_root: Node = animation.get_node(animation.root_node)
	var skeleton: Skeleton3D = anim_root.get_node_or_null(NodePath(skeleton_rel_path)) as Skeleton3D
	if skeleton == null:
		push_error("PrisonerAvatar could not resolve a Skeleton3D at \"%s\"; synthesised clips will not be built." % skeleton_rel_path)
		return []

	return [skeleton_rel_path, skeleton]


## The rest orientation of [param bone]'s parent in model space, accumulated by
## walking [method Skeleton3D.get_bone_parent] to the skeleton root. Identity for
## Hips, which is parented to nothing.
func _parent_rest_rotation(skeleton: Skeleton3D, bone: int) -> Quaternion:
	var accumulated := Quaternion.IDENTITY
	var walker: int = skeleton.get_bone_parent(bone)
	while walker >= 0:
		accumulated = skeleton.get_bone_rest(walker).basis.get_rotation_quaternion() * accumulated
		walker = skeleton.get_bone_parent(walker)
	return accumulated


## A bone's local pose after [param model_rotation] -- expressed in [b]model[/b]
## space, where +Y is up and +Z is the way the toes point -- is applied on top of
## its rest orientation.
##
## [b]This is the whole answer to the rig's bone-roll trap.[/b] A bone pose is
## written in its parent's space, and in this rig a parent's space is nothing
## like model space: [code]Thigh.L[/code] rests 178 degrees around Z so that its
## local +Y runs [i]down[/i] the leg, which means a knee bent about the shin's
## own local X bends about the wrong axis by an amount nobody can eyeball. So
## nothing here reasons about a bone's local axes at all. Given the parent's
## accumulated rest rotation [code]P[/code] and the bone's own rest [code]R[/code],
## the pose that rotates the bone by [code]M[/code] in model space is
## [code]P.inverse() * M * P * R[/code] -- read right to left, that is: sit in the
## rest pose, step out into model space, rotate about a model axis, step back.
##
## [method _build_idle_animation] gets away without it only because Spine's
## parents are all identity, so [code]P[/code] is identity and the conjugation
## collapses to the [code]sway * rest[/code] it writes. Every limb the slide
## poses needs the full form.
func _pose_bone(skeleton: Skeleton3D, bone: int, model_rotation: Quaternion) -> Quaternion:
	var parent: Quaternion = _parent_rest_rotation(skeleton, bone)
	var rest: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	return parent.inverse() * model_rotation * parent * rest


## The slide pose, bone by bone, as a pitch in degrees about the model's X axis
## applied on top of that bone's rest orientation (see [method _pose_bone]).
##
## Sign convention: a positive angle tips an upright bone forwards, towards the
## toes, and therefore swings a bone that hangs [i]down[/i] -- every limb in this
## rig -- backwards. Hips is absent because it is not a pitch: it carries the
## lean, the roll and the drop, all three from exports.
##
## The reading, from the hips out. Thigh.L is untouched, so the left leg simply
## rides the hips' lean and comes out straight and forward -- the leg you slide
## on. The right leg counter-rotates 40 degrees back towards vertical and then
## folds 95 at the knee, which tucks the shin underneath and behind: that
## asymmetry is the difference between a slide and a man lying down. The spine,
## neck and head add up to 45 degrees of forward curl against 55 of backward
## lean, so the skull finishes very nearly upright and still facing where the
## body is going. The left arm trails back past the hip, the right reaches
## forward, and both elbows carry a little bend so the arms are not poles.
const SLIDE_POSE_DEGREES: Dictionary = {
	"Spine": 15.0,
	"Neck": 18.0,
	"Head": 12.0,
	"UpperArm.L": 80.0,
	"LowerArm.L": -30.0,
	"UpperArm.R": -30.0,
	"LowerArm.R": -25.0,
	"Thigh.L": 0.0,
	"Shin.L": -8.0,
	"Foot.L": -25.0,
	"Thigh.R": 40.0,
	"Shin.R": 95.0,
	"Foot.R": 10.0,
}


## Synthesises the slide as a single static pose -- one key per bone, no motion
## between them -- for the same reason the idle is synthesised rather than
## downloaded: [code]assets/models/runner.glb[/code] carries a bespoke 16-joint
## skeleton with no shoulders, no chest and no toe bones, under names
## ([code]UpperArm.L[/code]) that are not the ones Godot's humanoid
## [SkeletonProfile] retargeter expects ([code]LeftUpperArm[/code]). A free clip
## from Mixamo or Quaternius arrives bound to its own skeleton in its own bind
## pose, and getting one onto this rig means authoring a [BoneMap] and a retarget
## pass -- more work, and more that can silently go wrong, than the eleven
## numbers in [constant SLIDE_POSE_DEGREES].
##
## The clip is a pose and not an animation on purpose. The brief was a snap, the
## snap is [member slide_blend_time], and everything that gives a slide its sense
## of speed already exists elsewhere: the body is really moving at up to
## [member MovementProfile.slide_boost_speed_cap], and the camera is really
## dropping by [member MovementProfile.slide_camera_drop]. A pose is what those
## two were missing, and adding entry and recovery phases on top would only fight
## the cross-fade that already blends this in and out.
func _build_slide_animation() -> void:
	var found: Array = _resolve_skeleton()
	if found.is_empty():
		return
	var skeleton_rel_path: String = found[0]
	var skeleton: Skeleton3D = found[1]

	var slide_anim := Animation.new()
	# Nothing moves, so the length is arbitrary; it is non-zero only because a
	# zero-length clip has nowhere to hang a key, and it loops so that holding
	# the pose past the end does not fall off into whatever plays next.
	slide_anim.length = 0.5
	slide_anim.loop_mode = Animation.LOOP_LINEAR

	# Composed roll-then-lean, so the lean is a pitch about the model's own X and
	# the roll then tips that whole leaning body onto one hip. The other order
	# would pitch about an axis the roll had already moved, and the lean would
	# stop being a clean backwards pitch.
	var lean := Quaternion(Vector3.RIGHT, deg_to_rad(-slide_lean_degrees))
	var roll := Quaternion(Vector3.BACK, deg_to_rad(slide_roll_degrees))
	var hips_rotation: Quaternion = roll * lean

	for bone_idx in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(bone_idx)
		var rest: Transform3D = skeleton.get_bone_rest(bone_idx)
		var track_path := NodePath(skeleton_rel_path + ":" + bone_name)

		var rot_track: int = slide_anim.add_track(Animation.TYPE_ROTATION_3D)
		slide_anim.track_set_path(rot_track, track_path)

		var model_rotation := Quaternion.IDENTITY
		if bone_name == "Hips":
			model_rotation = hips_rotation
		elif SLIDE_POSE_DEGREES.has(bone_name):
			model_rotation = Quaternion(Vector3.RIGHT, deg_to_rad(float(SLIDE_POSE_DEGREES[bone_name])))
		# A bone in neither case is still keyed, at its rest orientation. Every
		# bone must appear in every clip: a track the slide omits would not hold
		# still during the cross-fade, it would keep whatever the run cycle had
		# left it doing, and the pose would be a slide from the waist down with
		# a running man on top.
		slide_anim.rotation_track_insert_key(rot_track, 0.0, _pose_bone(skeleton, bone_idx, model_rotation))

		if bone_name == "Hips":
			# The only position track in the clip, and the only bone that has one
			# in the glTF's own Run either. Dropping the hips is what puts the
			# body on the floor; the lean alone would leave it standing up and
			# tipped over backwards.
			var pos_track: int = slide_anim.add_track(Animation.TYPE_POSITION_3D)
			slide_anim.track_set_path(pos_track, track_path)
			slide_anim.position_track_insert_key(pos_track, 0.0, Vector3(rest.origin.x, slide_hip_height, rest.origin.z))

	var library: AnimationLibrary
	if animation.has_animation_library(&""):
		library = animation.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		animation.add_animation_library(&"", library)
	library.add_animation(slide_clip, slide_anim)


## The crouch pose, bone by bone, in the same units and the same sign convention
## as [constant SLIDE_POSE_DEGREES]: degrees of pitch about the model's X axis,
## applied on top of the bone's rest orientation, composing down the chain -- so
## a bone's angle is read against its parent's, not against the world. Positive
## tips an upright bone forwards and therefore swings a hanging bone backwards.
##
## The reading, from the hips out. Hips carry the drop and a small forward lean
## (both exports, see [member crouch_hip_height]); the thighs come up to very
## nearly horizontal at -92, which is the fold that actually lowers the body, and
## the shins swing 115 back under it so the ankles finish beneath the hips rather
## than out in front where the prisoner would be sitting rather than squatting.
## The feet take -35, which is roughly minus the shins' resulting lean, so the
## soles stay flat on the ground instead of standing on their heels. The spine
## adds 13 of forward curl and the neck and head take it straight back off, so a
## crouched prisoner is looking level -- which matters, because that is where
## their camera is pointing. Both arms come forward and both elbows bend, for
## balance and because two straight arms hanging past the knees reads as a man
## who has been switched off.
##
## Symmetric, unlike the slide: a slide is a body thrown at the floor on one hip
## and a crouch is a body held on both feet, and the asymmetry that makes the
## slide legible would make this look like a stumble.
const CROUCH_POSE_DEGREES: Dictionary = {
	"Spine": 13.0,
	"Neck": -13.0,
	"Head": -10.0,
	"UpperArm.L": -45.0,
	"LowerArm.L": -40.0,
	"UpperArm.R": -45.0,
	"LowerArm.R": -40.0,
	"Thigh.L": -92.0,
	"Shin.L": 115.0,
	"Foot.L": -35.0,
	"Thigh.R": -92.0,
	"Shin.R": 115.0,
	"Foot.R": -35.0,
}


## Synthesises the crouch as a single static pose, one key per bone, exactly as
## [method _build_slide_animation] does and for exactly the same reasons -- see
## there for why this rig gets hand-authored numbers instead of a downloaded
## clip.
##
## The only structural difference is that there is no roll: the hips take the
## drop and a forward lean and nothing else. Everything else -- the position
## track on Hips being the only one in the clip, every bone being keyed even when
## it is keyed at rest, the loop on a clip with no motion in it -- is the same
## and is load-bearing for the same reasons.
func _build_crouch_animation() -> void:
	var found: Array = _resolve_skeleton()
	if found.is_empty():
		return
	var skeleton_rel_path: String = found[0]
	var skeleton: Skeleton3D = found[1]

	var crouch_anim := Animation.new()
	crouch_anim.length = 0.5
	crouch_anim.loop_mode = Animation.LOOP_LINEAR

	# Positive is forward here, matching CROUCH_POSE_DEGREES. See
	# crouch_lean_degrees for why this is not the sign slide_lean_degrees uses.
	var hips_rotation := Quaternion(Vector3.RIGHT, deg_to_rad(crouch_lean_degrees))

	for bone_idx in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(bone_idx)
		var rest: Transform3D = skeleton.get_bone_rest(bone_idx)
		var track_path := NodePath(skeleton_rel_path + ":" + bone_name)

		var rot_track: int = crouch_anim.add_track(Animation.TYPE_ROTATION_3D)
		crouch_anim.track_set_path(rot_track, track_path)

		var model_rotation := Quaternion.IDENTITY
		if bone_name == "Hips":
			model_rotation = hips_rotation
		elif CROUCH_POSE_DEGREES.has(bone_name):
			model_rotation = Quaternion(Vector3.RIGHT, deg_to_rad(float(CROUCH_POSE_DEGREES[bone_name])))
		# Every bone is keyed, including the ones keyed at rest: a track this
		# clip omitted would not hold still through the cross-fade, it would go
		# on doing whatever the run cycle had it doing, and the result would be a
		# squat from the waist down with a running man on top.
		crouch_anim.rotation_track_insert_key(rot_track, 0.0, _pose_bone(skeleton, bone_idx, model_rotation))

		if bone_name == "Hips":
			# The drop. The leg fold alone would leave the pelvis at rest height
			# with the feet dangling; this is what puts the body low.
			var pos_track: int = crouch_anim.add_track(Animation.TYPE_POSITION_3D)
			crouch_anim.track_set_path(pos_track, track_path)
			crouch_anim.position_track_insert_key(pos_track, 0.0, Vector3(rest.origin.x, crouch_hip_height, rest.origin.z))

	var library: AnimationLibrary
	if animation.has_animation_library(&""):
		library = animation.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		animation.add_animation_library(&"", library)
	library.add_animation(crouch_clip, crouch_anim)


## Skin and trousers glow faintly with their own texture so the arena's red
## light does not turn the whole body red.
func _self_light_skin() -> void:
	if mesh == null or mesh.mesh == null:
		return
	for index: int in mesh.mesh.get_surface_count():
		var authored: BaseMaterial3D = mesh.mesh.surface_get_material(index) as BaseMaterial3D
		if authored == null or authored.resource_name.begins_with("Shirt"):
			continue
		if mesh.get_surface_override_material(index) != null:
			continue
		var lit: BaseMaterial3D = authored.duplicate() as BaseMaterial3D
		lit.emission_enabled = true
		lit.emission_texture = lit.albedo_texture
		lit.emission = Color.WHITE
		lit.emission_energy_multiplier = 1.1
		mesh.set_surface_override_material(index, lit)
