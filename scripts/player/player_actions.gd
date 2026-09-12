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

## Crouch/slide -- one key, two states, which is why the keybind row has always
## been labelled with both and is now literally true.
##
## Held, not tapped, and doubly so. The PRESS is what opens a slide, if the body
## is moving forward fast enough to be allowed one; releasing ends that slide
## early, which is the only way a player has to leave one on their own terms.
## The HOLD is what keeps a crouch, which is what the same key does in every
## other circumstance and which lasts exactly as long as the key is down. The
## two are told apart in [method PlayerController._press_asks_for_a_slide], on
## speed and forward intent alone -- nothing here, and nothing that reads a
## device, gets a say.
##
## [b]Shift, by the author's ruling[/b] ("make shift crouch then not c"). Shift
## is safe to default to where Control is not: it is a shift-level modifier
## rather than a chord prefix, and no desktop OS builds its own shortcuts out of
## it. It was sprint's key until the same author retired sprint ("for now we
## dont need sprint"), which is what left it free.
##
## [b]Not Control, on purpose.[/b] Control is the genre's usual crouch key and
## this project shipped it until it was found to break the slide-jump on macOS.
## Control+Space is a live macOS system shortcut ("Select the previous input
## source", symbolic hotkey 60, on by default whenever more than one input
## source is installed) and Ctrl+Space is likewise the default input-method
## toggle under IBus and fcitx on Linux. The WindowServer claims the chord
## before any application sees it, so the [b]Space[/b] press is swallowed while
## Control is held: the slide opens and the jump out of it never arrives. The
## key does reach Godot on its own, which is what makes the failure look like a
## movement bug rather than a binding one. A default the OS eats is not a
## default, so the shipped bindings avoid the chord entirely and a player who
## wants Control can bind it themselves through [KeybindMap].
const SLIDE: StringName = &"slide"

## The runner's power: Q, or the left shoulder button on a pad.
const ABILITY: StringName = &"ability"
const ABILITY_PAD_BUTTON: JoyButton = JOY_BUTTON_LEFT_SHOULDER
## Direct picks: 1 shield, 2 hologram, 3 armor lock, 4 camo.
const ABILITY_SLOTS: Array[StringName] = [&"ability_1", &"ability_2", &"ability_3", &"ability_4"]

## Prisoner on prisoner: F, or the B button on a pad. Tapped, never held.
const SHOVE: StringName = &"shove"
## Dev turbo: T held = 300% speed.
const TURBO: StringName = &"debug_turbo"
## Dev godmode: Y toggles rifle immunity.
const GODMODE: StringName = &"debug_godmode"
const SHOVE_PAD_BUTTON: JoyButton = JOY_BUTTON_B

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
	# Must stay in step with project.godot; test_keybind_defaults.gd pins them
	# to each other so the fallback cannot drift back to Control.
	_ensure(SLIDE, [KEY_SHIFT, KEY_Z])
	if not InputMap.has_action(ABILITY):
		_ensure(ABILITY, [KEY_Q])
		var pad: InputEventJoypadButton = InputEventJoypadButton.new()
		pad.button_index = ABILITY_PAD_BUTTON
		InputMap.action_add_event(ABILITY, pad)
	if not InputMap.has_action(SHOVE):
		_ensure(SHOVE, [KEY_F])
		var shove_pad: InputEventJoypadButton = InputEventJoypadButton.new()
		shove_pad.button_index = SHOVE_PAD_BUTTON
		InputMap.action_add_event(SHOVE, shove_pad)
	_ensure(TURBO, [KEY_T])
	_ensure(GODMODE, [KEY_Y])
	var slot_keys: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4]
	for i: int in ABILITY_SLOTS.size():
		_ensure(ABILITY_SLOTS[i], [slot_keys[i]])


static func _ensure(action: StringName, physical_keycodes: Array[int]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, DEADZONE)
	for keycode: int in physical_keycodes:
		var event: InputEventKey = InputEventKey.new()
		# Physical, so the bindings stay under the same fingers on AZERTY.
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)
