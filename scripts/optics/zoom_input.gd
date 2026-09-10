class_name ZoomInput
extends Node

## Turns a device into calls to [method WeaponOptic.zoom_in] and
## [method WeaponOptic.zoom_out].
##
## This is the only script in scripts/optics/ that is allowed to touch [Input],
## and it is deliberately the thinnest thing in the directory: it holds no zoom
## state of its own, decides nothing about whether aiming is a good idea, and
## has no fallback behaviour. Delete it and the optic still works; a bot drives
## the identical methods with no input layer at all, which is what makes
## headless bot matches exercise the real optic.
##
## Mirrors [WeaponInput]'s role on the weapon side and [HumanIntentSource]'s on
## the movement side.

## The optic this device drives.
@export var optic: WeaponOptic


func _ready() -> void:
	OpticsActions.ensure_registered()
	if optic == null:
		push_error("ZoomInput has no WeaponOptic to drive; input will be ignored.")
		set_process(false)


## Polled rather than event-driven, matching [WeaponInput] and
## [HumanIntentSource]. Hold mode is a question about the button's CURRENT
## state, which polling answers with no memory at all; an event handler would
## have to mirror the button and could desynchronise from the device the first
## time a press was swallowed by a menu.
func _process(_delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		# The cursor is loose, so the player is in a menu or has released the
		# window. Unlike a click, a HELD button has a lasting effect, so this
		# must actively let go rather than merely ignore the frame -- otherwise
		# opening a menu mid-aim leaves the player zoomed in with nothing
		# holding it.
		if _is_hold_mode():
			optic.zoom_out()
		return

	if _is_hold_mode():
		optic.set_zoomed(Input.is_action_pressed(OpticsActions.ZOOM))
	elif Input.is_action_just_pressed(OpticsActions.ZOOM):
		optic.toggle_zoom()


## Enable or disable reading this device. A disabled source stops asking; it
## does not touch the optic's state, so a transition already in flight still
## completes rather than freezing mid-FOV.
func set_active(active: bool) -> void:
	set_process(active and optic != null)


## Hold unless the profile says toggle. A missing profile reads as hold, which
## is the default and the safer of the two: it cannot strand the player zoomed.
func _is_hold_mode() -> bool:
	if optic.profile == null:
		return true
	return optic.profile.activation == ZoomProfile.Activation.HOLD
