class_name KeybindMap
extends RefCounted

## The player's keyboard, mouse and gamepad bindings: the defaults the project
## shipped, the overrides the player made, and the rules for moving between
## them.
##
## [b]Physical keycodes, everywhere.[/b] Every keyboard binding is stored and
## matched by [member InputEventKey.physical_keycode] -- the position of the key
## on the board -- and never by [member InputEventKey.keycode], the letter
## printed on it. On AZERTY the WASD block is at ZQSD and on QWERTZ the Z and Y
## keys swap; bind by letter and those players get defaults that are not merely
## unfamiliar but physically impossible to hold together. Bind by position and
## every layout gets the same shape under the same fingers. The existing
## bindings in project.godot are already physical (see [PlayerActions]); this
## class is what keeps them that way through a rebind.
##
## Keys are still [i]displayed[/i] by label, via
## [method DisplayServer.keyboard_get_keycode_from_physical], so the AZERTY
## player sees "Z" on the button that Godot matches as physical W. Stored one
## way, shown the other: that is the whole trick, and getting it backwards is
## the single most common way keybinding ships broken.
##
## [b]Slots.[/b] Each action carries up to [constant MAX_BINDINGS] bindings,
## which is what preserves the shipped arrow-key alternates for movement. A
## rebind writes one slot; it does not wipe the action. An empty slot is an
## empty [Dictionary], not a null, so the array is always
## [constant MAX_BINDINGS] long and a slot index is always addressable.
##
## [b]Defaults.[/b] [method capture_defaults] snapshots the live [InputMap],
## which at engine start is exactly what project.godot declared. It must run
## before any override is applied -- [SettingsStore] guarantees the order -- or
## "reset to default" would restore the player's last override instead.

## Bindings per action. Two, so movement keeps both its WASD and its arrow-key
## binding and rebinding one does not silently destroy the other.
const MAX_BINDINGS: int = 2

## The zoom action, named by string rather than taken from [code]OpticsActions[/code].
##
## Deliberate. [code]scripts/optics[/code] is another domain, and this file
## already reaches into [PlayerActions] and [WeaponActions] because those are the
## player's own input layer; adding a third import would make the settings screen
## fail to compile the day the optic is removed or refactored, for the sake of
## one string that is fixed by project.godot anyway. An action name IS the
## contract between domains -- it is what the [InputMap] is keyed by -- so
## quoting it is the loosest coupling available, not a shortcut.
const ZOOM: StringName = &"zoom"

## Every action the settings screen will let the player rebind, in the order it
## displays them. Matches the project's action list; [PlayerActions] and
## [WeaponActions] own their names and this list quotes them rather than
## inventing parallel strings.
const ACTIONS: Array[StringName] = [
	PlayerActions.MOVE_FORWARD,
	PlayerActions.MOVE_BACK,
	PlayerActions.MOVE_LEFT,
	PlayerActions.MOVE_RIGHT,
	PlayerActions.JUMP,
	PlayerActions.SLIDE,
	PlayerActions.ABILITY,
	WeaponActions.FIRE,
	ZOOM,
]

## ConfigFile section the bindings are written to.
const SECTION_KEYBINDS: String = "keybinds"

# --- Serialised event tags ----------------------------------------------------
#
# The saved form of an InputEvent is a small Dictionary with a "type" tag, not a
# serialised object. Storing objects in a player-writable file would be both a
# code-execution surface and a format that breaks on any engine change to those
# classes; a tag plus two ints survives both.

const TYPE_KEY: String = "key"
const TYPE_MOUSE_BUTTON: String = "mouse_button"
const TYPE_JOY_BUTTON: String = "joy_button"
const TYPE_JOY_AXIS: String = "joy_axis"

const KEY_FIELD_TYPE: String = "type"
const KEY_FIELD_CODE: String = "code"
const KEY_FIELD_INDEX: String = "index"
const KEY_FIELD_AXIS: String = "axis"
const KEY_FIELD_VALUE: String = "value"

## Shipped bindings, snapshotted off the [InputMap] at start. Action -> Array of
## [constant MAX_BINDINGS] serialised events.
var _defaults: Dictionary[StringName, Array] = {}

## Bindings currently in force. Same shape as [member _defaults].
var _bindings: Dictionary[StringName, Array] = {}


## Make sure every action in [constant ACTIONS] exists in the [InputMap] before
## anything tries to read or write it.
##
## In a normal run project.godot has already defined them all and both calls are
## no-ops. It matters for a bare harness or a scene run on its own, where the
## settings screen must still have something to bind against rather than
## erroring on a missing action.
static func ensure_actions_registered() -> void:
	PlayerActions.ensure_registered()
	WeaponActions.ensure_registered()
	# Zoom's fallback is spelled out here rather than delegated, for the same
	# reason its name is: see [constant ZOOM]. Right mouse button, matching what
	# project.godot declares and what the optic's own fallback would register,
	# so whichever of the three runs first the result is identical.
	if not InputMap.has_action(ZOOM):
		InputMap.add_action(ZOOM, PlayerActions.DEADZONE)
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(ZOOM, event)


## Snapshot the live [InputMap] as the default binding set.
##
## Call once, at startup, [b]before[/b] applying anything loaded from disk.
func capture_defaults() -> void:
	_defaults.clear()
	for action: StringName in ACTIONS:
		_defaults[action] = _read_action_from_input_map(action)
	reset_to_defaults()


## Discard every override and return to the shipped bindings. Does not apply
## them to the [InputMap]; call [method apply_to_input_map].
func reset_to_defaults() -> void:
	_bindings.clear()
	for action: StringName in ACTIONS:
		_bindings[action] = _duplicate_slots(_default_slots(action))


## Return one action to its shipped bindings.
func reset_action(action: StringName) -> void:
	if not _bindings.has(action):
		return
	_bindings[action] = _duplicate_slots(_default_slots(action))


## The serialised event in [param slot], or an empty [Dictionary] if that slot
## is unbound or the action is unknown.
func get_binding(action: StringName, slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_BINDINGS or not _bindings.has(action):
		return {}
	var slots: Array = _bindings[action]
	var entry: Variant = slots[slot]
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var binding: Dictionary = entry
	return binding


## The shipped event for [param slot], for showing what a reset would restore.
func get_default_binding(action: StringName, slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_BINDINGS or not _defaults.has(action):
		return {}
	var slots: Array = _defaults[action]
	var entry: Variant = slots[slot]
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var binding: Dictionary = entry
	return binding


## Write [param binding] into [param slot]. Pass an empty [Dictionary] to clear
## the slot. Does not check for conflicts -- callers ask
## [method find_conflict] first and decide -- and does not apply to the
## [InputMap].
func set_binding(action: StringName, slot: int, binding: Dictionary) -> void:
	if slot < 0 or slot >= MAX_BINDINGS or not _bindings.has(action):
		return
	var slots: Array = _bindings[action]
	slots[slot] = binding.duplicate(true)


## Clear one slot.
func clear_binding(action: StringName, slot: int) -> void:
	set_binding(action, slot, {})


## The action [param binding] is already bound to, or [code]&""[/code] if it is
## free.
##
## The slot being rebound is excluded, so re-binding a key to the place it
## already sits is not reported as a conflict with itself. Every other slot of
## the [i]same[/i] action is checked, because binding W to both of an action's
## two slots wastes the alternate and is worth refusing too.
func find_conflict(action: StringName, slot: int, binding: Dictionary) -> StringName:
	if binding.is_empty():
		return &""
	for other: StringName in ACTIONS:
		for other_slot: int in range(MAX_BINDINGS):
			if other == action and other_slot == slot:
				continue
			if bindings_equal(get_binding(other, other_slot), binding):
				return other
	return &""


## Push the current bindings into the live [InputMap], replacing whatever each
## action held.
##
## Erase-then-add rather than add-only: a rebind that left the old event in
## place would leave the old key working, which reads as the rebind having
## silently failed.
func apply_to_input_map() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, PlayerActions.DEADZONE)
		InputMap.action_erase_events(action)
		for slot: int in range(MAX_BINDINGS):
			var event: InputEvent = binding_to_event(get_binding(action, slot))
			if event != null:
				InputMap.action_add_event(action, event)


# --- Serialisation ------------------------------------------------------------

## Write the bindings into [param config].
func write_to(config: ConfigFile) -> void:
	for action: StringName in ACTIONS:
		config.set_value(SECTION_KEYBINDS, String(action), _bindings[action])


## Read the bindings out of [param config].
##
## Per action, and then per slot: a section that is missing, an action whose
## value is not an array, a slot holding a malformed dictionary -- each falls
## back to the default for exactly that slot rather than discarding the file.
## A player who corrupts one line keeps the rest of their bindings.
func read_from(config: ConfigFile) -> void:
	for action: StringName in ACTIONS:
		var stored: Array = GameSettings.read_array(config, SECTION_KEYBINDS, String(action))
		var slots: Array = _duplicate_slots(_default_slots(action))
		for slot: int in range(MAX_BINDINGS):
			if slot >= stored.size():
				continue
			var entry: Variant = stored[slot]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = entry
			# An explicitly empty entry is a slot the player cleared on purpose,
			# and must stay cleared -- restoring the default there would be the
			# game quietly re-binding a key they removed.
			if candidate.is_empty():
				slots[slot] = {}
				continue
			# Anything else is validated by round-tripping it through the event
			# constructor. A malformed entry is corruption rather than intent,
			# so that one slot keeps its default and the rest of the file still
			# loads.
			var event: InputEvent = binding_to_event(candidate)
			if event != null:
				slots[slot] = event_to_binding(event)
		_bindings[action] = slots


# --- Event <-> Dictionary -----------------------------------------------------

## Serialise an [InputEvent]. Returns an empty [Dictionary] for event types the
## settings screen does not bind (mouse motion, gestures, actions).
static func event_to_binding(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key: InputEventKey = event
		# physical_keycode is the field that survives a layout change. Events
		# authored with only a keycode -- from an older config, or from the
		# editor's non-physical mode -- are converted here rather than stored
		# in the broken form.
		var code: int = key.physical_keycode
		if code == 0:
			code = key.keycode
		if code == 0:
			return {}
		return {KEY_FIELD_TYPE: TYPE_KEY, KEY_FIELD_CODE: code}

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_NONE:
			return {}
		return {KEY_FIELD_TYPE: TYPE_MOUSE_BUTTON, KEY_FIELD_INDEX: int(button.button_index)}

	if event is InputEventJoypadButton:
		var pad_button: InputEventJoypadButton = event
		return {KEY_FIELD_TYPE: TYPE_JOY_BUTTON, KEY_FIELD_INDEX: int(pad_button.button_index)}

	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		return {
			KEY_FIELD_TYPE: TYPE_JOY_AXIS,
			KEY_FIELD_AXIS: int(motion.axis),
			KEY_FIELD_VALUE: signf(motion.axis_value),
		}

	return {}


## Rebuild an [InputEvent] from its serialised form, or null if [param binding]
## is empty or malformed. This doubles as the validator for anything read off
## disk.
static func binding_to_event(binding: Dictionary) -> InputEvent:
	if binding.is_empty():
		return null

	var tag: Variant = binding.get(KEY_FIELD_TYPE, "")
	if typeof(tag) != TYPE_STRING and typeof(tag) != TYPE_STRING_NAME:
		return null
	var kind: String = String(tag)

	match kind:
		TYPE_KEY:
			var code: int = _field_int(binding, KEY_FIELD_CODE)
			if code == 0:
				return null
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = code
			key.pressed = true
			return key
		TYPE_MOUSE_BUTTON:
			var index: int = _field_int(binding, KEY_FIELD_INDEX)
			if index <= 0:
				return null
			var button: InputEventMouseButton = InputEventMouseButton.new()
			button.button_index = index as MouseButton
			button.pressed = true
			return button
		TYPE_JOY_BUTTON:
			var pad_index: int = _field_int(binding, KEY_FIELD_INDEX)
			if pad_index < 0:
				return null
			var pad_button: InputEventJoypadButton = InputEventJoypadButton.new()
			pad_button.button_index = pad_index as JoyButton
			pad_button.pressed = true
			return pad_button
		TYPE_JOY_AXIS:
			var axis: int = _field_int(binding, KEY_FIELD_AXIS)
			if axis < 0:
				return null
			var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
			motion.axis = axis as JoyAxis
			motion.axis_value = _field_float(binding, KEY_FIELD_VALUE, 1.0)
			return motion

	return null


## True when two serialised bindings mean the same input.
static func bindings_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return false
	return left == right


## Human-readable label for a serialised binding.
##
## Keyboard bindings are translated from physical position back to the label
## printed on the player's own keyboard, so the AZERTY player reads "Z" for the
## key this class matches as physical W.
static func describe(binding: Dictionary) -> String:
	if binding.is_empty():
		return "Unbound"

	var tag: Variant = binding.get(KEY_FIELD_TYPE, "")
	var kind: String = String(tag) if typeof(tag) == TYPE_STRING or typeof(tag) == TYPE_STRING_NAME else ""

	match kind:
		TYPE_KEY:
			return describe_physical_keycode(_field_int(binding, KEY_FIELD_CODE))
		TYPE_MOUSE_BUTTON:
			return describe_mouse_button(_field_int(binding, KEY_FIELD_INDEX))
		TYPE_JOY_BUTTON:
			return "Pad Button %d" % _field_int(binding, KEY_FIELD_INDEX)
		TYPE_JOY_AXIS:
			var direction: String = "+" if _field_float(binding, KEY_FIELD_VALUE, 1.0) >= 0.0 else "-"
			return "Pad Axis %d%s" % [_field_int(binding, KEY_FIELD_AXIS), direction]

	return "Unknown"


## The label printed on this player's keyboard for a physical key position.
static func describe_physical_keycode(physical_keycode: int) -> String:
	if physical_keycode == 0:
		return "Unbound"
	var labelled: int = physical_keycode
	if not GameSettings.is_headless():
		labelled = DisplayServer.keyboard_get_keycode_from_physical(physical_keycode as Key)
	if labelled == 0:
		labelled = physical_keycode
	var text: String = OS.get_keycode_string(labelled as Key)
	return text if not text.is_empty() else "Key %d" % physical_keycode


## Readable name for a mouse button index.
static func describe_mouse_button(index: int) -> String:
	match index:
		MOUSE_BUTTON_LEFT:
			return "Mouse Left"
		MOUSE_BUTTON_RIGHT:
			return "Mouse Right"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse Middle"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "Wheel Right"
	return "Mouse %d" % index


## Display name for an action, for the settings screen's left column.
static func display_name(action: StringName) -> String:
	match action:
		PlayerActions.MOVE_FORWARD:
			return "Move Forward"
		PlayerActions.MOVE_BACK:
			return "Move Back"
		PlayerActions.MOVE_LEFT:
			return "Move Left"
		PlayerActions.MOVE_RIGHT:
			return "Move Right"
		PlayerActions.JUMP:
			return "Jump"
		PlayerActions.SLIDE:
			return "Crouch / Slide"
		PlayerActions.ABILITY:
			return "Ability"
		WeaponActions.FIRE:
			return "Fire"
		ZOOM:
			return "Aim / Zoom"
	return String(action).capitalize()


# --- Internals ----------------------------------------------------------------

func _read_action_from_input_map(action: StringName) -> Array:
	var slots: Array = _empty_slots()
	if not InputMap.has_action(action):
		return slots
	var slot: int = 0
	for event: InputEvent in InputMap.action_get_events(action):
		if slot >= MAX_BINDINGS:
			break
		var binding: Dictionary = event_to_binding(event)
		if binding.is_empty():
			continue
		slots[slot] = binding
		slot += 1
	return slots


func _default_slots(action: StringName) -> Array:
	if not _defaults.has(action):
		return _empty_slots()
	var slots: Array = _defaults[action]
	return slots


static func _empty_slots() -> Array:
	var slots: Array = []
	slots.resize(MAX_BINDINGS)
	for slot: int in range(MAX_BINDINGS):
		slots[slot] = {}
	return slots


static func _duplicate_slots(slots: Array) -> Array:
	var copy: Array = _empty_slots()
	for slot: int in range(MAX_BINDINGS):
		if slot >= slots.size():
			break
		var entry: Variant = slots[slot]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = entry
		copy[slot] = binding.duplicate(true)
	return copy


static func _field_int(binding: Dictionary, field: String) -> int:
	var raw: Variant = binding.get(field, 0)
	var kind: int = typeof(raw)
	if kind == TYPE_INT:
		return int(raw)
	if kind == TYPE_FLOAT:
		return int(float(raw))
	return 0


static func _field_float(binding: Dictionary, field: String, fallback: float) -> float:
	var raw: Variant = binding.get(field, fallback)
	var kind: int = typeof(raw)
	if kind != TYPE_INT and kind != TYPE_FLOAT:
		return fallback
	return float(raw)
