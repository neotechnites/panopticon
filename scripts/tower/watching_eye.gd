class_name WatchingEye
extends Node3D

## The eyeball over the tower, and the one thing in PANOPTICON that moves because
## of where [b]you[/b] are standing.
##
## [code]assets/models/eye.glb[/code] -- a 1,078-triangle ball with a glowing red
## iris and a black pupil -- floats in the gap between the top of
## [PanopticonEye]'s box (y=4.15) and the light over the tower
## ([code]KeyLight[/code], y=20), and turns so that its pupil points at whoever is
## looking at it. Ryan, on 2026-09-10: [i]"take that eye
## model you made, and stick it between the box of eyes, and the light source, and
## have the view of each player other than the shooter, look like the eye is
## always following it."[/i] The game is called PANOPTICON; this is its title
## rendered literally.
##
## [b]How "each player sees it looking at them" is expressed[/b]
##
## By orienting the eyeball toward [method Viewport.get_camera_3d] every process
## frame, and by nothing else.
##
## That reads like the naive option and it is in fact the exact one, because of a
## property of the engine rather than of this file: [b]a viewport's current camera
## is already a per-viewer quantity[/b]. Each client runs its own copy of the
## scene tree with its own camera in it, so the same line of code resolves to a
## different player on every machine and the eye is, without any further
## machinery, looking at each of them at once. Nothing about the orientation is
## sent anywhere -- see [method _process], which writes a [Basis] and emits
## nothing -- so there is no state to replicate, no authority to decide, and
## nothing for a later netcode pass to have to unpick. Deleting the whole node
## changes no other client's simulation by a single bit.
##
## The alternative considered was a shader that skews the pupil in view space, so
## that one world-space orientation appears to face every camera. It buys exactly
## one thing this does not -- a split-screen or spectator-grid frame with two live
## cameras in [b]one[/b] viewport, where a single node cannot hold two
## orientations -- and costs a hand-written shader on an imported [glTF] material
## under GL Compatibility, plus a pupil that is a painted lie rather than a ball
## that has turned. The model is a real sphere with a real iris on one side, so
## turning it is both cheaper and more honest. [b]The known limit is written down
## rather than solved:[/b] two cameras in one viewport would need the shader.
## One camera per viewport, which is what a networked client is, needs this.
##
## [b]Why this cannot leak where the guard is looking[/b]
##
## This is the constraint that outranks the feature, so it is worth being exact.
## The eye's orientation on your screen is a pure function of one input: the
## position of your own camera. Not its direction -- its [i]position[/i]. Follow
## every path into this file and there is nothing else: no reference to the guard,
## to the tower's occupant, to a rifle, a seat, a match or a network peer, and
## [code]tests/test_watching_eye.gd[/code] reads this source and asserts that.
##
## So consider what a prisoner can learn by staring at it. It points at them.
## It always points at them, from the moment they spawn to the moment they die,
## whatever the guard does, whether the guard is aiming at them or at the far side
## of the ring or has walked off the platform entirely. Its bearing carries
## exactly zero bits about anybody except the observer, who already knew where
## they were standing. That is a stronger guarantee than the box next door
## manages: [PanopticonEye] is inert because it never moves, and this thing moves
## constantly while still being unable to say anything, because the only fact it
## has access to is a fact the viewer already holds.
##
## The two must stay strictly apart, and the file boundary is how. An eye that
## tracked the guard's camera instead of the viewer's would look almost identical
## in a diff and would hand the prisoners the entire game. Nothing here may ever
## reach for a camera other than [method Viewport.get_camera_3d], because that one
## is by construction the local viewer's.
##
## [b]The guard is excluded, and geometry does it[/b]
##
## Ryan's instruction excludes the shooter: they are inside the box and must not
## have the thing above them staring down. The obvious implementation -- ask
## [MatchController] whether the local player holds the seat -- is exactly the
## coupling this file must not have, so it is not used. Instead the exclusion is
## positional: if the local camera is inside the tower's own column of space (see
## [method is_on_the_tower]) the eye stops watching and rests looking straight up
## at the light. That is answered entirely from the viewer's own coordinates, it
## needs no match state at all, and it is automatically right for anyone who is
## ever up there. A prisoner who falls into the courtyard 12.5 m below is still
## watched, because the column has a floor.
##
## [b]It rides the tower[/b]
##
## The node places itself at (0, [member WatchingEyeProfile.height_metres], 0) in
## its parent's space on ready, the same way [TowerLight] does, and never reads or
## writes a world coordinate. Parented under Tower in
## [code]scenes/ring/bentham_ring.tscn[/code], it therefore follows the tower
## wherever the tower goes. See the report and the scene's editor_description for
## what that assumes if the ring is rebuilt.
##
## [b]Renderer[/b]
##
## GL Compatibility, pinned. The model ships lit [StandardMaterial3D]s with an
## emissive iris straight from the glTF, which is the point -- it hangs a metre
## under the tower's own light and is meant to be lit by it. There is no custom
## shader here to fail to compile.

## Which way the pupil points in the model's own space.
##
## [code]eye.glb[/code] puts the iris at +Z (translation z=0.798) and the pupil
## disc in front of it at z=1.054, so the gaze axis is [constant Vector3.BACK] --
## the [b]opposite[/b] of Godot's conventional -Z forward. That is why this file
## builds its own basis in [method gaze_basis_for] rather than calling
## [method Node3D.look_at], which would point the model's back of the head at the
## viewer and look, from the ring, like an eye pointedly ignoring everyone.
const MODEL_GAZE_AXIS: Vector3 = Vector3.BACK

## Where the eye looks when it is not watching anybody: straight up, at the light
## above it, in this node's own space.
##
## Chosen so the exclusion reads as a fact rather than a glitch. The guard, inside
## the box and looking up through its culled lid, sees the underside of a ball
## whose pupil is turned away toward the lamp. There is no pose that means "the
## eye is off", and a frozen forward stare would look like a tracking bug.
const REST_GAZE: Vector3 = Vector3.UP

## How parallel a gaze direction has to be to world up before the basis in
## [method gaze_basis_for] has to pick a different reference for "up".
const PARALLEL_LIMIT: float = 0.9999

## The node that turns. Named rather than found by walking children, the same way
## [member PanopticonEye.box_path] is, so this script never has to guess which
## node is which.
##
## It exists as a separate node from this one for a reason that matters: this
## node's own basis is the [b]tower's[/b] basis, unrotated and unscaled, and
## [method gaze_direction_for] inverts it to measure where a viewer is relative to
## the tower axis. If the rig root turned, that measurement would turn with it.
@export var gaze_path: NodePath = ^"Gaze"

## The imported [code]eye.glb[/code], under the gaze node. Scaled from
## [member WatchingEyeProfile.radius_metres] on ready.
##
## The scale lives here and not on the rig root or the gaze node for the same
## reason the rotation lives on the gaze node: a scaled root would make the
## metre-denominated column test in [method is_on_the_tower] mean something other
## than metres, and a scaled gaze node would have its scale wiped every frame by
## the basis this script writes onto it.
@export var model_path: NodePath = ^"Gaze/Model"

## Size, height, tracking speed and the excluded column. Falls back to a
## default-constructed [WatchingEyeProfile] with a warning rather than to nothing,
## because an eye that silently ended up 0 m across at y=0 reads as "the eyeball
## never got added".
@export var profile: WatchingEyeProfile


func _ready() -> void:
	if profile == null:
		push_warning("WatchingEye has no WatchingEyeProfile; falling back to defaults.")
		profile = WatchingEyeProfile.new()

	position = Vector3(0.0, profile.height_metres, 0.0)

	var model: Node3D = get_node_or_null(model_path) as Node3D
	if model == null:
		push_error("WatchingEye.model_path does not point at a Node3D; there is no eyeball to turn.")
	else:
		model.scale = Vector3.ONE * profile.radius_metres
		_stop_casting_shadows(model)

	if get_node_or_null(gaze_path) == null:
		push_error("WatchingEye.gaze_path does not point at a Node3D; the eye cannot turn.")
		return

	turn_toward(gaze_direction_for(viewer_position()), 0.0)


## Turn onto whoever is looking, once a frame.
##
## Deliberately [method Node._process] and not [method Node._physics_process]:
## this is presentation, it has no bearing on the simulation, and it must be
## smooth at the frame rate the viewer actually sees rather than at 60 Hz.
##
## The whole per-viewer mechanism is the one call below. Everything else in this
## file is arithmetic on its result.
func _process(delta: float) -> void:
	turn_toward(gaze_direction_for(viewer_position()), delta)


## Where the local viewer's eye is, in world space.
##
## [method Viewport.get_camera_3d] and nothing else -- the local viewport's own
## current camera, which is the local player on their own machine, the local
## spectator when they are dead, and a different person on every other machine in
## the game. There is no other camera this file is allowed to know about.
##
## Falls back to this node's own centre when there is no camera at all (a headless
## run, or a frame before anything is current), which resolves to a zero offset
## and so rests the eye rather than pointing it at the origin.
func viewer_position() -> Vector3:
	var view: Viewport = get_viewport()
	if view == null:
		return global_position
	var eyes: Camera3D = view.get_camera_3d()
	if eyes == null:
		return global_position
	return eyes.global_position


## The direction the eye wants its pupil to face for a viewer at
## [param viewer_point], in world space.
##
## Pure, given the node's placement: the same viewer position always produces the
## same answer, and the only property of [param viewer_point] that is read is the
## point itself.
func gaze_direction_for(viewer_point: Vector3) -> Vector3:
	var rested: Vector3 = (global_basis * REST_GAZE).normalized()
	if profile == null:
		return rested

	var local: Vector3 = global_transform.affine_inverse() * viewer_point
	var above_platform: Vector3 = local + Vector3(0.0, profile.height_metres, 0.0)
	if is_on_the_tower(above_platform, profile.tower_radius_metres,
			profile.tower_band_low_metres, profile.tower_band_high_metres):
		return rested

	var offset: Vector3 = viewer_point - global_position
	if offset.is_zero_approx():
		return rested
	return offset.normalized()


## Whether a point is inside the tower's own column of space, and so belongs to
## the person the eye must not watch.
##
## [param platform_local] is measured in the tower's frame, from the platform
## surface: X and Z from the tower axis, Y above the platform. Static and pure so
## the suite can assert the shape of the exclusion without building an eye or a
## tower.
##
## Note what is [b]not[/b] an argument here. This asks a question about a region
## of space, and it is called with the local viewer's own coordinates. It has no
## way of being told about anybody else, which is the entire reason the exclusion
## is done this way rather than by asking who holds the seat.
static func is_on_the_tower(platform_local: Vector3, radius: float, low: float, high: float) -> bool:
	if platform_local.y < low or platform_local.y > high:
		return false
	return Vector2(platform_local.x, platform_local.z).length() <= radius


## A basis whose [constant MODEL_GAZE_AXIS] points along [param direction].
##
## Built by hand rather than with [method Node3D.look_at] or
## [method Basis.looking_at] because the model's gaze axis is +Z and both of those
## default to Godot's -Z, so the convenient call produces an eye facing exactly
## backwards -- a mistake that looks like a deliberate design decision from the
## ring and is invisible in a diff.
##
## The reference up flips to [constant Vector3.BACK] when the gaze is within
## [constant PARALLEL_LIMIT] of vertical, which is not a rare edge case here: the
## rest pose is straight up, so the degenerate case is the one the eye sits in
## whenever the guard is looking at it.
static func gaze_basis_for(direction: Vector3) -> Basis:
	var forward: Vector3 = direction.normalized()
	if forward.is_zero_approx():
		forward = MODEL_GAZE_AXIS
	var reference: Vector3 = Vector3.UP
	if absf(forward.dot(reference)) > PARALLEL_LIMIT:
		reference = Vector3.BACK
	var right: Vector3 = reference.cross(forward).normalized()
	return Basis(right, forward.cross(right), forward)


## Swing the gaze toward [param direction] by one frame's worth of turn.
##
## The weight is [code]1 - exp(-rate * delta)[/code], which is the frame-rate
## independent form of an exponential approach: the same wall-clock half-life on
## every machine. A [code]rate * delta[/code] weight is not, and produces a gaze
## that visibly lags further behind on a slower computer.
##
## [b]The lag is the point[/b], not a concession. A sphere aimed exactly at you
## looks the same from every bearing and so reads as a flat decal; being caught
## part-way through the turn is the only depth cue a bare ball has. See
## [member WatchingEyeProfile.track_rate] for the whole argument and the
## arithmetic.
##
## [method Quaternion.slerp] moves along the single shortest arc to the target and
## the weight is always in 0..1, so the gaze approaches monotonically and cannot
## overshoot, ring or wobble. That is a deliberate choice over a spring: an eye
## that rocks back past you reads as a servo with slack in it.
##
## Separated from [method _process] so the suite can drive it with an exact delta
## instead of waiting on the renderer.
func turn_toward(direction: Vector3, delta: float) -> void:
	var gaze: Node3D = get_node_or_null(gaze_path) as Node3D
	if gaze == null:
		return

	var target: Quaternion = Quaternion(gaze_basis_for(direction))
	var rate: float = 0.0 if profile == null else profile.track_rate
	if rate <= 0.0 or delta <= 0.0:
		gaze.global_basis = Basis(target)
		return

	var current: Quaternion = Quaternion(gaze.global_basis.orthonormalized())
	gaze.global_basis = Basis(current.slerp(target, 1.0 - exp(-rate * delta)))


## Where the pupil is actually pointing right now, in world space. Read by the
## suite; the eye itself never needs it.
func gaze_direction() -> Vector3:
	var gaze: Node3D = get_node_or_null(gaze_path) as Node3D
	if gaze == null:
		return Vector3.ZERO
	return (gaze.global_basis * MODEL_GAZE_AXIS).normalized()


## Takes every mesh in the eyeball off shadow casting.
##
## The eyeball hangs a couple of metres under the tower's omni light, so a
## shadow-casting ball would drop a hard disc of darkness over the guard's box and
## the inner deck -- and, because the iris bulges four centimetres proud of the
## sclera, that disc would have a faint lump on it that turned as the eye turned.
## Harmless in fact (it turns with the local viewer, so it can only ever indicate
## where the viewer already is) but it is a moving patch of light on the deck,
## which is the shape of a tell, and switching it off is free. Matches
## [code]cast_shadow = 0[/code] on the box next door.
func _stop_casting_shadows(root: Node) -> void:
	var surface: GeometryInstance3D = root as GeometryInstance3D
	if surface != null:
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in root.get_children():
		_stop_casting_shadows(child)
