class_name WeaponActions
extends RefCounted

## Canonical names of the input actions [WeaponInput] reads, plus a fallback
## registration for them.
##
## Same contract as [PlayerActions]: the project's action list belongs in
## project.godot, and [method ensure_registered] only fills in actions that are
## missing, so anything defined there always wins and this becomes a no-op. It
## exists so the weapon scene is runnable on its own -- dropping rifle.tscn into
## a bare test scene or a headless harness must not require editing project
## settings first.

const FIRE: StringName = &"fire"

## Matches Godot's default action deadzone.
const DEADZONE: float = 0.2


## Register the fire action if the project has not already defined it, bound to
## the left mouse button.
static func ensure_registered() -> void:
	if InputMap.has_action(FIRE):
		return
	InputMap.add_action(FIRE, DEADZONE)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event(FIRE, event)
