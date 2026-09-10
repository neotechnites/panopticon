class_name PlayerActions
extends RefCounted

## Canonical names of the input actions [HumanIntentSource] reads, plus a
## fallback registration for them.
##
## The project's action list belongs in project.godot; [method ensure_registered]
## only fills in actions that are missing, so anything defined there always wins
## and this becomes a no-op. It exists so the player scene is runnable on its
## own -- dropping player.tscn into an empty test scene or a headless bot
## harness must not require editing project settings first.

const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACK: StringName = &"move_back"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const JUMP: StringName = &"jump"
const SPRINT: StringName = &"sprint"

## Crouch/slide. Held, not tapped: releasing it ends a slide early, which is the
## only way a player has to leave one on their own terms.
const SLIDE: StringName = &"slide"

## Matches Godot's default action deadzone.
const DEADZONE: float = 0.2


## Register any of the movement actions that the project has not already
## defined, with WASD / Space / Shift defaults.
static func ensure_registered() -> void:
	_ensure(MOVE_FORWARD, [KEY_W, KEY_UP])
	_ensure(MOVE_BACK, [KEY_S, KEY_DOWN])
	_ensure(MOVE_LEFT, [KEY_A, KEY_LEFT])
	_ensure(MOVE_RIGHT, [KEY_D, KEY_RIGHT])
	_ensure(JUMP, [KEY_SPACE])
	_ensure(SPRINT, [KEY_SHIFT])
	_ensure(SLIDE, [KEY_CTRL, KEY_C])


static func _ensure(action: StringName, physical_keycodes: Array[int]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, DEADZONE)
	for keycode: int in physical_keycodes:
		var event: InputEventKey = InputEventKey.new()
		# Physical, so the bindings stay under the same fingers on AZERTY.
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)
