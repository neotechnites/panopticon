class_name OpticsActions
extends RefCounted

## Canonical name of the input action [ZoomInput] reads, plus a fallback
## registration for it.
##
## Same contract as [PlayerActions] and [WeaponActions]: the project's action
## list belongs in project.godot, and [method ensure_registered] only fills in
## the action if it is missing, so anything defined there always wins and this
## becomes a no-op. It exists so an optic is runnable on its own -- dropping it
## into a bare test scene or a headless harness must not require editing project
## settings first.

const ZOOM: StringName = &"zoom"

## Matches Godot's default action deadzone.
const DEADZONE: float = 0.2


## Register the zoom action if the project has not already defined it, bound to
## the right mouse button -- the aim button in every shooter the player has ever
## used, and the one button [WeaponActions.FIRE] leaves free.
static func ensure_registered() -> void:
	if InputMap.has_action(ZOOM):
		return
	InputMap.add_action(ZOOM, DEADZONE)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event(ZOOM, event)
