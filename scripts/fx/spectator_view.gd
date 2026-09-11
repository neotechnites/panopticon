class_name FxSpectatorView
extends Node3D

## What a dead player looks at, and the reason being dead is not being frozen.
##
## [b]The problem this exists to solve[/b]
##
## The author, on the three second respawn hold: [i]"when someone gets shot, they
## jsut stop animating and sit there for 3 secdson, let give them a reload
## screen, or make them a free camera or something. same with if they die durring
## the initial race."[/i]
##
## A held body is inert by design -- see [method MatchController._hold_body] --
## and the human's camera is a child of that body, so the player was left inside
## a statue, unable even to turn their head, staring at whatever direction the
## rifle happened to leave them facing. That is the correct thing for the BODY to
## do and the wrong thing for the VIEW to do, and this node is the seam between
## the two.
##
## [b]It is a camera of its own, not the player's camera moved[/b]
##
## The player's [Camera3D] is spoken for three times over -- [WeaponOptic] owns
## its [member Camera3D.fov], [FxCameraKick] owns its local transform, and
## [PauseMenu] writes the display FOV setting into it -- so reparenting or
## driving it would put this node into a fight with all three. Instead this node
## carries its OWN camera, makes it [member Camera3D.current] while the player is
## dead, and hands the view back by making the player's camera current again. The
## player's camera is never written to at all.
##
## [b]Two views, because there are two kinds of dead[/b]
##
## [codeblock]
## RESPAWNING  -> a fixed over-the-shoulder cut on the body you just lost.
##                Three seconds. You see where you were taken from.
## ELIMINATED  -> the overlook: high, outside the ring, watching the race
##                finish. A racer who fell is out for the rest of the race, so
##                this one can last a while -- and the corpse is buried a
##                hundred metres under the deck, so there is nothing to orbit.
## [/codeblock]
##
## [b]Why it polls[/b]
##
## [method MatchController.get_spectating_state] is asked every frame rather than
## subscribed to. A view built on signal edges is wrong for a player who died
## before this node was ready, wrong after [method MatchController.restart], and
## wrong for a match loaded mid-round; a poll is right in all three and costs an
## integer compare.
##
## Strictly additive. It subscribes to nothing, is subscribed to by nothing, and
## deleting it leaves the match exactly as it was.

## Emitted when the view takes over, and when it hands back. The hook for a UI
## that wants to know without polling too.
signal spectating_changed(active: bool)

## The match to ask. Without one this node does nothing at all.
@export var controller: MatchController

## This node's own camera. Normally a [Camera3D] child of it. Never the player's.
@export var camera: Camera3D

## The camera to give the view back to when the player is playing again --
## normally [code]Player/Head/Camera[/code].
##
## Held as a reference rather than discovered, and restored EXPLICITLY: Godot
## does not promise which camera becomes current when the current one steps
## down, and a match that came back from a death with no camera at all would be
## a black screen.
@export var player_camera: Camera3D

## The human's input device, muted while the view is out.
##
## [b]Not optional politeness -- a bug fix.[/b] [HumanIntentSource] accumulates
## mouse motion in pixels and drains it when [PlayerController] polls, and a held
## body is not being polled. Three seconds of mouse motion would therefore land
## on the body in one frame the instant it woke, and spin the player's aim.
## [method HumanIntentSource.set_active] both stops the reading and drops what
## was already banked, which is exactly right: the mouse belongs to this camera
## while the player is dead.
@export var human_input: HumanIntentSource

## Tunables. Without one this node does nothing and says so.
@export var profile: SpectatorProfile

## Go inert when there is no display server. A headless sweep has no view to
## take over and no mouse to borrow.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

var _inert: bool = false
var _active: bool = false

## Degrees of automatic drift accumulated since the view came up. Reset on every
## entry, so two deaths in a row do not start from a different bearing each time.
var _drift_degrees: float = 0.0

## The player's own contribution, in radians, on top of the drift.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0

## What the view is showing right now.
var _state: MatchController.Spectating = MatchController.Spectating.NONE

## Seconds the match has wanted this view for, before it was granted. See
## [member SpectatorProfile.enter_delay_seconds] -- the hit reaction whips the
## PLAYER's camera, so cutting to this one on the frame of the kill would throw
## the hit away.
var _pending_seconds: float = 0.0

## Whether this node currently has the human's input device switched off.
var _input_muted: bool = false


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		set_process_unhandled_input(false)
		return
	if profile == null:
		push_error("FxSpectatorView has no SpectatorProfile; a dead player will stay frozen.")
		_inert = true
		set_process(false)
		return
	if camera == null:
		push_error("FxSpectatorView has no Camera3D of its own to switch to.")
		_inert = true
		set_process(false)
		return
	if controller == null:
		push_error("FxSpectatorView has no MatchController to ask who is dead.")
		_inert = true
		set_process(false)
		return
	camera.current = false
	camera.fov = profile.field_of_view_degrees


func _process(delta: float) -> void:
	tick(delta)


## Never hand a scene back with somebody else's camera current, or with the
## human's input still muted.
func _exit_tree() -> void:
	if _active:
		_deactivate()
	_mute_input(false)


## Poll the match and drive the view. Public so a harness may step it, the same
## seam [method FxCameraKick.tick] offers.
func tick(delta: float) -> void:
	if _inert or controller == null or profile == null:
		return
	if not profile.enabled:
		if _active:
			_deactivate()
		return

	var wanted: MatchController.Spectating = controller.get_spectating_state(
		controller.get_human_participant()
	)
	if wanted == MatchController.Spectating.NONE:
		_pending_seconds = 0.0
		if _active:
			_deactivate()
		_mute_input(false)
		return

	# The mouse is taken away the INSTANT the match says this player is dead, and
	# not when the camera changes -- those are up to
	# [member SpectatorProfile.enter_delay_seconds] apart, and every millisecond
	# of that gap would otherwise be banked pixels waiting to spin the aim on
	# respawn. See [member human_input].
	_mute_input(true)

	if not _active:
		_pending_seconds += delta
		# An elimination has no hit reaction behind it -- a racer fell, nobody
		# shot them -- so there is nothing to wait for and the view is immediate.
		if (
			wanted == MatchController.Spectating.RESPAWNING
			and _pending_seconds < profile.enter_delay_seconds
		):
			return

	if not _active or wanted != _state:
		_activate(wanted)
	_state = wanted
	_drift_degrees += _drift_rate() * delta
	_place(delta)


# --- Public API ---------------------------------------------------------------

## True while this node owns the view.
func is_active() -> bool:
	return _active


## Seconds this node has been waiting out
## [member SpectatorProfile.enter_delay_seconds] before taking the view. Zero
## whenever it is not waiting.
func get_pending_seconds() -> float:
	return 0.0 if _active else _pending_seconds


## What the view is showing, or [constant MatchController.Spectating.NONE].
func get_state() -> MatchController.Spectating:
	return _state


## Give the view back now, whatever the match says. For a teardown, a scene
## change, and a test that must not leave a camera current or a mouse muted.
func stand_down() -> void:
	if _active:
		_deactivate()
	_pending_seconds = 0.0
	_mute_input(false)


func is_inert() -> bool:
	return _inert


## The point the camera is currently looking at. The readout a test asserts
## against, since a camera effect cannot be judged headless.
func get_focus_point() -> Vector3:
	return _focus_point()


# --- Internals ----------------------------------------------------------------

func _activate(state: MatchController.Spectating) -> void:
	var was_active: bool = _active
	_state = state
	if not was_active:
		_drift_degrees = 0.0
		_look_yaw = 0.0
		_look_pitch = deg_to_rad(profile.start_pitch_degrees)
		_active = true
		set_process_unhandled_input(profile.free_look_enabled)
	camera.fov = profile.field_of_view_degrees
	camera.current = true
	if not was_active:
		spectating_changed.emit(true)


func _deactivate() -> void:
	_active = false
	_pending_seconds = 0.0
	_state = MatchController.Spectating.NONE
	camera.current = false
	# Explicitly, and in this order: the player's camera is made current before
	# the input device is given back, so a frame can never exist in which the
	# body is being aimed by a mouse whose view has not been restored.
	if player_camera != null and is_instance_valid(player_camera):
		player_camera.current = true
	_mute_input(false)
	spectating_changed.emit(false)


## Take the mouse off the body, or give it back. Idempotent, because it is driven
## from a per-frame poll rather than from an edge.
##
## [method HumanIntentSource.set_active] both stops the device reading and drops
## the pixels it had already banked, which is exactly the pair of things needed:
## a held body is not polling, so anything banked would land in one frame the
## instant it woke.
func _mute_input(muted: bool) -> void:
	if _input_muted == muted:
		return
	_input_muted = muted
	if human_input != null and is_instance_valid(human_input):
		human_input.set_active(not muted)


func _drift_rate() -> float:
	if _state == MatchController.Spectating.ELIMINATED:
		return profile.overlook_orbit_degrees_per_second
	return profile.death_orbit_degrees_per_second


## Where the camera goes and where it points, this frame.
func _place(_delta: float) -> void:
	if _state == MatchController.Spectating.ELIMINATED:
		_place_overlook()
	else:
		_place_death_shot()


## The overlook: an orbit in the open pit between the tower and the deck,
## looking outward through the gallery's open inner side. Radius and height
## are clamped into the pit's own band -- see
## [member SpectatorProfile.overlook_min_radius_metres] -- so this never sits
## in the rock the way the old outside-the-ring orbit now would.
func _place_overlook() -> void:
	var centre: Vector3 = (
		controller.arena.global_position if controller.arena != null else Vector3.ZERO
	)
	var bearing: float = deg_to_rad(_drift_degrees) + _look_yaw
	var cam_radius: float = clampf(
		profile.overlook_orbit_radius_metres,
		profile.overlook_min_radius_metres,
		profile.overlook_max_radius_metres,
	)
	var cam_height: float = clampf(
		centre.y + profile.overlook_orbit_height_metres,
		profile.overlook_min_height_metres,
		profile.overlook_max_height_metres,
	)
	camera.global_position = Vector3(
		centre.x + cos(bearing) * cam_radius,
		cam_height,
		centre.z + sin(bearing) * cam_radius,
	)
	var focus: Vector3 = _focus_point()
	if camera.global_position.distance_squared_to(focus) > 1e-6:
		camera.look_at(focus, Vector3.UP)


## The death shot: a fixed over-the-shoulder cut on the held body, built
## outward from the body instead of from an orbit arm, then clamped onto the
## gallery's own radius and height band -- see
## [member SpectatorProfile.death_gallery_min_radius_metres] -- so it is never
## in the rock, even for a body the kill volume caught out over the void.
func _place_death_shot() -> void:
	var centre: Vector3 = (
		controller.arena.global_position if controller.arena != null else Vector3.ZERO
	)
	var participant: MatchParticipant = controller.get_human_participant()
	var body_pos: Vector3 = centre
	var facing: Vector3 = Vector3.FORWARD
	if participant != null and participant.body != null:
		body_pos = participant.body.global_position
		var forward: Vector3 = -participant.body.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 1e-6:
			facing = forward.normalized()

	var behind: Vector2 = (
		Vector2(body_pos.x, body_pos.z)
		- Vector2(facing.x, facing.z) * profile.death_over_shoulder_distance_metres
	)
	var radial: Vector2 = behind - Vector2(centre.x, centre.z)
	if radial.length_squared() < 1e-6:
		radial = Vector2(1.0, 0.0)
	radial = radial.normalized() * clampf(
		radial.length(),
		profile.death_gallery_min_radius_metres,
		profile.death_gallery_max_radius_metres,
	)
	var height: float = clampf(
		centre.y + profile.death_over_shoulder_height_metres,
		profile.death_gallery_min_height_metres,
		profile.death_gallery_max_height_metres,
	)
	camera.global_position = Vector3(centre.x + radial.x, height, centre.z + radial.y)

	var focus: Vector3 = _focus_point()
	if camera.global_position.distance_squared_to(focus) > 1e-6:
		camera.look_at(focus, Vector3.UP)


## What the camera is looking at.
##
## The body while it is being held -- it is frozen exactly where it died, which
## is the whole reason that view is worth showing. A point out on the DECK,
## in the direction the overlook is currently orbiting, once the player is
## eliminated -- an eliminated racer's body has been parked a hundred metres
## under the deck and there is nothing down there to watch, so the overlook
## looks past the pit and out through the gallery's open inner side instead.
func _focus_point() -> Vector3:
	var arena_centre: Vector3 = (
		controller.arena.global_position if controller.arena != null else Vector3.ZERO
	)
	if _state == MatchController.Spectating.ELIMINATED:
		var bearing: float = deg_to_rad(_drift_degrees) + _look_yaw
		return arena_centre + Vector3(
			cos(bearing) * profile.overlook_focus_radius_metres,
			profile.overlook_focus_height_metres,
			sin(bearing) * profile.overlook_focus_radius_metres,
		)

	var participant: MatchParticipant = controller.get_human_participant()
	if participant == null or participant.body == null:
		return arena_centre + Vector3(0.0, profile.overlook_focus_height_metres, 0.0)
	return participant.body.global_position + Vector3(
		0.0, profile.death_focus_height_metres, 0.0
	)


## Free look. Reads the mouse directly, because while this view is up the mouse
## is not the body's: [member human_input] has been switched off.
func _unhandled_input(event: InputEvent) -> void:
	if not _active or profile == null or not profile.free_look_enabled:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_look_yaw -= motion.relative.x * profile.look_sensitivity
	_look_pitch -= motion.relative.y * profile.look_sensitivity
	# Not marked handled: [PauseMenu] and the settings screen are entitled to see
	# input while somebody is dead, and neither of them wants mouse motion.
