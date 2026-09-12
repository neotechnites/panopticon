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

## The optic whose zoom this device's aim must be compensated for, if the body
## has one. Optional: a null optic reads as a multiplier of 1.0, so a body
## without an optic behaves exactly as it did before there was one.
##
## It is consumed HERE, in the one place a device's look delta is built, and
## deliberately not in [method PlayerController._apply_look]. The multiplier is
## a property of the DEVICE's mapping, not of the body: a [BotIntentSource]'s
## look delta is computed from a world-space aim target and must not be scaled
## at all, and scaling in the controller would scale both. See
## [member WeaponOptic.sensitivity_multiplier].
@export var optic: WeaponOptic

## Mouse motion since the last poll, in pixels. Accumulated rather than applied
## immediately because mouse events arrive at the display refresh rate while
## movement runs on the physics tick; applying per event would couple aim speed
## to framerate.
var _look_pixels: Vector2 = Vector2.ZERO


func _ready() -> void:
	PlayerActions.ensure_registered()
	WeaponActions.ensure_registered()
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


## Dev turbo, toggled by T.
var _turbo: bool = false

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
	_intent.slide_pressed = Input.is_action_just_pressed(PlayerActions.SLIDE)
	_intent.slide_held = Input.is_action_pressed(PlayerActions.SLIDE)
	_intent.fire_pressed = Input.is_action_just_pressed(WeaponActions.FIRE)
	_intent.fire_held = Input.is_action_pressed(WeaponActions.FIRE)
	_intent.ability_pressed = Input.is_action_just_pressed(PlayerActions.ABILITY)
	_intent.shove_pressed = Input.is_action_just_pressed(PlayerActions.SHOVE)
	if Input.is_action_just_pressed(PlayerActions.TURBO):
		_turbo = not _turbo
	_intent.turbo_held = _turbo
	_intent.ability_held = Input.is_action_pressed(PlayerActions.ABILITY)
	for i: int in PlayerActions.ABILITY_SLOTS.size():
		var slot: StringName = PlayerActions.ABILITY_SLOTS[i]
		if Input.is_action_just_pressed(slot):
			_intent.ability_slot = i + 1
		if Input.is_action_pressed(slot):
			_intent.ability_held = true
	# Dimensionless, and the delta is already in radians, so the order of the
	# two scalars does not matter. Null optic == 1.0: see the export above.
	var aim_scale: float = profile.mouse_sensitivity
	if optic != null:
		aim_scale *= optic.sensitivity_multiplier
	_intent.look_delta = _look_pixels * aim_scale
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
