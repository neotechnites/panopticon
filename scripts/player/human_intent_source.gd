class_name HumanIntentSource
extends IntentSource

## Turns keyboard and mouse into a [MoveIntent].
##
## This is the only script in the player that is allowed to touch [Input]. Swap
## it for a [BotIntentSource] and the same body moves under AI with identical
## physics.

## Grab the mouse as soon as this source is ready. Turn it off for scenes that
## own the cursor themselves (menus, spectator views, replay viewers).
@export var capture_mouse_on_ready: bool = true

## Mouse motion since the last poll, in pixels. Accumulated rather than applied
## immediately because mouse events arrive at the display refresh rate while
## movement runs on the physics tick; applying per event would couple aim speed
## to framerate.
var _look_pixels: Vector2 = Vector2.ZERO


func _ready() -> void:
	PlayerActions.ensure_registered()
	if capture_mouse_on_ready:
		_set_mouse_captured(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			_look_pixels += motion.relative
		return
	if event.is_action_pressed(&"ui_cancel"):
		_set_mouse_captured(false)
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed:
			_set_mouse_captured(true)


func poll(_delta: float) -> MoveIntent:
	_intent.clear()
	if profile == null:
		# Sensitivity is a profile number; without one there is nothing to
		# scale mouse motion by, so report no intent rather than invent a value.
		_look_pixels = Vector2.ZERO
		return _intent

	_intent.move_direction = Input.get_vector(
		PlayerActions.MOVE_LEFT,
		PlayerActions.MOVE_RIGHT,
		PlayerActions.MOVE_BACK,
		PlayerActions.MOVE_FORWARD,
	)
	_intent.jump_pressed = Input.is_action_just_pressed(PlayerActions.JUMP)
	_intent.jump_held = Input.is_action_pressed(PlayerActions.JUMP)
	_intent.sprint_held = Input.is_action_pressed(PlayerActions.SPRINT)
	_intent.look_delta = _look_pixels * profile.mouse_sensitivity
	_look_pixels = Vector2.ZERO
	return _intent


## Enable or disable reading this device. Disabled sources report an empty
## intent, which brings the body to a stop under friction rather than freezing
## it mid-stride.
func set_active(active: bool) -> void:
	set_process_unhandled_input(active)
	if not active:
		_look_pixels = Vector2.ZERO


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
