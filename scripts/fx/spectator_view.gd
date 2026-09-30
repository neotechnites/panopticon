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
## [b]One view for every kind of dead[/b]
## Respawning or eliminated: just outside the tower's arcade at guard eye height,
## sliding round the tower to keep the leading runner in view.
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

## Gap between the tower's outer extent and the camera, metres.
const ARCADE_CLEARANCE_METRES: float = 1.5
## Vertical band around eye height whose mesh vertices set the tower's radius, metres.
const RADIUS_BAND_METRES: float = 2.0
## Eye height used when no body can report one, metres.
const FALLBACK_EYE_METRES: float = 1.6
## Death-shot turn easing, per second.
const AIM_SMOOTHING: float = 4.0
## Death-shot orbit easing round the tower, per second.
const ORBIT_SMOOTHING: float = 2.0

var _inert: bool = false
var _active: bool = false

## Smoothed death-shot aim; zero until the first frame snaps it.
var _aim_dir: Vector3 = Vector3.ZERO
## Tower axis at guard eye height, measured on each activation.
var _orbit_centre: Vector3 = Vector3.ZERO
## Camera distance from [member _orbit_centre], measured on each activation.
var _orbit_radius: float = ARCADE_CLEARANCE_METRES
## Smoothed bearing round the tower, radians; NAN until the first frame snaps it.
var _bearing: float = NAN

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
	_place_death_shot(delta)


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


## What the camera's position is anchored on. The readout a test asserts
## against, since a camera effect cannot be judged headless.
func get_focus_point() -> Vector3:
	return _focus_point()


# --- Internals ----------------------------------------------------------------

func _activate(state: MatchController.Spectating) -> void:
	var was_active: bool = _active
	_state = state
	if not was_active:
		_aim_dir = Vector3.ZERO
		_bearing = NAN
		_measure_orbit()
		_active = true
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


## The death shot: orbits outside the arcade on the bearing to the leading runner,
## easing by [constant ORBIT_SMOOTHING], aim easing by [constant AIM_SMOOTHING].
func _place_death_shot(delta: float) -> void:
	var runner: MatchParticipant = _leading_runner()
	if runner != null and runner.body != null:
		var flat: Vector3 = runner.body.global_position - _orbit_centre
		if Vector2(flat.x, flat.z).length_squared() > 1e-4:
			var wanted: float = atan2(flat.z, flat.x)
			if is_nan(_bearing):
				_bearing = wanted
			else:
				_bearing = lerp_angle(_bearing, wanted, 1.0 - exp(-ORBIT_SMOOTHING * delta))
	if is_nan(_bearing):
		_bearing = 0.0
	camera.global_position = _focus_point()
	var outward: Vector3 = Vector3(cos(_bearing), 0.0, sin(_bearing))
	var target: Vector3 = _look_target()
	if runner == null or runner.body == null:
		target = camera.global_position + outward
	var to_target: Vector3 = target - camera.global_position
	if to_target.length_squared() < 1e-6:
		return
	var aim: Vector3 = to_target.normalized()
	if _aim_dir.length_squared() < 0.5:
		_aim_dir = aim
	else:
		_aim_dir = _aim_dir.slerp(aim, 1.0 - exp(-AIM_SMOOTHING * delta)).normalized()
	camera.look_at(camera.global_position + _aim_dir, Vector3.UP)


## The tower the guard is placed in: the spawn marker's parent, else the arena's TowerVariant.
func _tower() -> Node3D:
	if controller == null or controller.arena == null:
		return null
	var marker: Node = controller.arena.get_node_or_null(controller.spawn_marker_path)
	if marker != null and marker.get_parent() is Node3D and marker.get_parent() != controller.arena:
		return marker.get_parent() as Node3D
	for node: Node in controller.arena.find_children("*", "Node3D", true, false):
		if node is TowerVariant:
			return node as Node3D
	return marker as Node3D


## Sets the orbit centre (tower axis at spawn marker + guard eye height) and radius
## (furthest tower vertex within the eye band, else mesh AABB) + clearance.
func _measure_orbit() -> void:
	var tower: Node3D = _tower()
	var marker: Node3D = null
	if controller != null and controller.arena != null:
		marker = controller.arena.get_node_or_null(controller.spawn_marker_path) as Node3D
	var axis: Vector3 = tower.global_position if tower != null else Vector3.ZERO
	var base_y: float = marker.global_position.y if marker != null else axis.y
	_orbit_centre = Vector3(axis.x, base_y + _guard_eye_height(), axis.z)
	_orbit_radius = _tower_radius(tower, _orbit_centre) + ARCADE_CLEARANCE_METRES


## The eye height the guard's body reports, else any body's, else the fallback.
func _guard_eye_height() -> float:
	var any_eye: float = -1.0
	for participant: MatchParticipant in controller.get_participants_ref():
		if participant.body == null:
			continue
		if participant.is_shooter:
			return participant.body.get_eye_height()
		if any_eye < 0.0:
			any_eye = participant.body.get_eye_height()
	return any_eye if any_eye > 0.0 else FALLBACK_EYE_METRES


## Horizontal reach of the tower's visible meshes from [param centre]'s axis, near its height.
func _tower_radius(tower: Node3D, centre: Vector3) -> float:
	if tower == null:
		return 0.0
	var band_best: float = 0.0
	var box_best: float = 0.0
	for node: Node in tower.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if box.end.y < centre.y - RADIUS_BAND_METRES or box.position.y > centre.y + RADIUS_BAND_METRES:
			continue
		box_best = maxf(box_best, maxf(
			maxf(absf(box.position.x - centre.x), absf(box.end.x - centre.x)),
			maxf(absf(box.position.z - centre.z), absf(box.end.z - centre.z))
		))
		var xform: Transform3D = mi.global_transform
		for surface: int in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var w: Vector3 = xform * v
				if absf(w.y - centre.y) <= RADIUS_BAND_METRES:
					band_best = maxf(band_best, Vector2(w.x - centre.x, w.z - centre.z).length())
	return band_best if band_best > 0.0 else box_best


## What the camera is anchored on: its spot on the orbit round the tower.
func _focus_point() -> Vector3:
	if not _active:
		_measure_orbit()
	var bearing: float = 0.0 if is_nan(_bearing) else _bearing
	return _orbit_centre + Vector3(cos(bearing), 0.0, sin(bearing)) * _orbit_radius


## Where the camera turns to look: the living prisoner furthest along the
## route, by [method MatchLapTracker.get_progress] -- eye height, not feet.
## Falls back to [method _focus_point] once nobody is still running.
func _look_target() -> Vector3:
	var runner: MatchParticipant = _leading_runner()
	if runner == null or runner.body == null:
		return _focus_point()
	return runner.body.global_position + Vector3(0.0, runner.body.get_eye_height(), 0.0)


## The living prisoner with the most route progress, or null if none is
## running. No mouse look any more -- this is what the camera follows instead.
func _leading_runner() -> MatchParticipant:
	var best: MatchParticipant = null
	var best_progress: float = -1.0
	for participant: MatchParticipant in controller.get_participants_ref():
		if not participant.is_running or participant.body == null or participant.tracker == null:
			continue
		var progress: float = participant.tracker.get_progress()
		if progress > best_progress:
			best_progress = progress
			best = participant
	return best
