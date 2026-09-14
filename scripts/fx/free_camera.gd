class_name FxFreeCamera
extends Node3D

## Dev only: C detaches a flying camera from the local body, mid match, alive.
##
## [b]What moves and what does not.[/b] The body stays in the match and keeps
## being simulated and replicated; only the VIEW and the INPUT leave it.
## [member human_input] is frozen -- see [method HumanIntentSource.set_frozen] --
## so nothing the pilot presses reaches the body, and the intent this machine
## sends is that empty one. Nothing here touches the wire: no packet, no codec
## field, no snapshot. A client in free camera still receives every snapshot it
## did before.
##
## [b]Shaped like [FxSpectatorView].[/b] It carries its OWN [Camera3D], writes
## the player camera's [code]current[/code] flag and nothing else, and is inert
## with no display server. Unlike that node it works while the pilot is alive,
## and stands down the moment the match says they are dead, because the death
## cam outranks it.

## Emitted when the view detaches, and when it comes home.
signal detached_changed(detached: bool)

## This node's own camera. Normally a [Camera3D] child of it. Never the body's.
@export var camera: Camera3D

## The camera to give the view back to -- normally [code]Player/Head/Camera[/code].
@export var player_camera: Camera3D

## The local device, frozen while the view is out.
@export var human_input: HumanIntentSource

## Asked whether the pilot is dead, so this node can get out of the death cam's
## way. Optional: without one it simply never stands down on its own.
@export var controller: MatchController

## Go inert with no display server. A headless sweep has no view to detach.
@export var headless_inert: bool = true

## Fly speed, in metres per second, before the wheel and the modifiers.
@export var metres_per_second: float = 8.0

## Shift multiplies the speed, Alt divides it.
@export var fast_multiplier: float = 4.0
@export var slow_multiplier: float = 0.25

## Radians of turn per pixel of mouse motion.
@export var look_sensitivity: float = 0.003

const HEADLESS_DISPLAY: String = "headless"

## What the wheel may pull the speed down to and push it up to, in m/s, and the
## factor one notch applies.
const SPEED_MIN: float = 0.5
const SPEED_MAX: float = 120.0
const SPEED_STEP: float = 1.2

## How far the camera may look up or down. Short of the pole, where a yaw-pitch
## basis rolls.
const PITCH_LIMIT: float = 1.5

var _inert: bool = false
var _detached: bool = false

## Mouse motion since the last tick, in pixels. Banked for the same reason
## [HumanIntentSource] banks it: events arrive at the refresh rate.
var _look_pixels: Vector2 = Vector2.ZERO

var _yaw: float = 0.0
var _pitch: float = 0.0
var _speed: float = 0.0


func _ready() -> void:
	PlayerActions.ensure_registered()
	_speed = metres_per_second
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		set_process_unhandled_input(false)
		return
	if camera == null:
		push_error("FxFreeCamera has no Camera3D of its own to fly.")
		_inert = true
		set_process(false)
		set_process_unhandled_input(false)
		return
	camera.current = false


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(PlayerActions.FREE_CAMERA):
		toggle()
	tick(delta)


## Never hand a scene back with this camera current or the device still frozen.
func _exit_tree() -> void:
	set_detached(false)


# --- Public API ---------------------------------------------------------------

## Detach the view, or bring it home. Public so a harness may drive it.
func set_detached(detached: bool) -> void:
	if _detached == detached or camera == null:
		return
	_detached = detached
	if detached:
		_take_view()
	else:
		_give_view_back()
	detached_changed.emit(detached)


func toggle() -> void:
	set_detached(not _detached)


func is_detached() -> bool:
	return _detached


func is_inert() -> bool:
	return _inert


## Metres per second the wheel is currently holding, before the modifiers.
func get_speed() -> float:
	return _speed


## Fly one frame. Public so a test may step it without waiting on a frame.
func tick(delta: float) -> void:
	if not _detached:
		return
	if _stand_down_for_death():
		return
	_apply_look()
	_fly(delta)


# --- Internals ----------------------------------------------------------------

func _take_view() -> void:
	_look_pixels = Vector2.ZERO
	_speed = metres_per_second
	if player_camera != null and is_instance_valid(player_camera):
		camera.global_transform = player_camera.global_transform
		camera.fov = player_camera.fov
	var facing: Vector3 = camera.global_basis.get_euler()
	_yaw = facing.y
	_pitch = clampf(facing.x, -PITCH_LIMIT, PITCH_LIMIT)
	camera.current = true
	# Nobody is being looked out of now, so every body -- the pilot's included
	# -- goes third person. PrisonerAvatar applies that itself, per body.
	PrisonerAvatar.set_viewed_body(null)
	if human_input != null and is_instance_valid(human_input):
		human_input.set_frozen(true)


## Give the claim up before the flags move: with none standing, the view goes
## back to whichever head camera is current, which is the one set below.
func _give_view_back() -> void:
	PrisonerAvatar.release_viewed_body()
	camera.current = false
	if player_camera != null and is_instance_valid(player_camera):
		player_camera.current = true
	if human_input != null and is_instance_valid(human_input):
		human_input.set_frozen(false)


## The death cam outranks this node; it also mutes the same device.
func _stand_down_for_death() -> bool:
	if controller == null or not is_instance_valid(controller):
		return false
	var state: MatchController.Spectating = controller.get_spectating_state(
		controller.get_human_participant()
	)
	if state == MatchController.Spectating.NONE:
		return false
	set_detached(false)
	return true


func _apply_look() -> void:
	if _look_pixels == Vector2.ZERO:
		return
	_yaw -= _look_pixels.x * look_sensitivity
	_pitch = clampf(_pitch - _look_pixels.y * look_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	_look_pixels = Vector2.ZERO
	camera.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))


## WASD along the camera's own axes, E up and Q down, Shift fast and Alt slow.
func _fly(delta: float) -> void:
	var move: Vector2 = Input.get_vector(
		PlayerActions.MOVE_LEFT,
		PlayerActions.MOVE_RIGHT,
		PlayerActions.MOVE_BACK,
		PlayerActions.MOVE_FORWARD,
	)
	var lift: float = (
		(1.0 if Input.is_action_pressed(PlayerActions.FREECAM_UP) else 0.0)
		- (1.0 if Input.is_action_pressed(PlayerActions.FREECAM_DOWN) else 0.0)
	)
	if move == Vector2.ZERO and is_zero_approx(lift):
		return
	var facing: Basis = camera.global_basis
	var direction: Vector3 = facing.x * move.x - facing.z * move.y + Vector3.UP * lift
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	camera.global_position += direction * current_speed() * delta


## Metres per second this frame: the wheel's speed under the modifiers.
func current_speed() -> float:
	var speed: float = _speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
	if Input.is_physical_key_pressed(KEY_ALT):
		speed *= slow_multiplier
	return speed


## Mouse look and the wheel. Read directly, because while this view is out the
## mouse is not the body's: [member human_input] has been frozen.
func _unhandled_input(event: InputEvent) -> void:
	if not _detached:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = clampf(_speed * SPEED_STEP, SPEED_MIN, SPEED_MAX)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = clampf(_speed / SPEED_STEP, SPEED_MIN, SPEED_MAX)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_look_pixels += motion.relative
