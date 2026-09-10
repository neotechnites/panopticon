class_name KeybindPanel
extends MarginContainer

## The rebinding UI: one row per action, two binding slots each, plus the
## capture overlay.
##
## Greybox by instruction -- default theme, no colours, no icons. Every control
## here is a stock [Button] or [Label], and all of them are authored in
## [code]scenes/ui/keybind_panel.tscn[/code]. This file binds them to the store
## and to the capture; it does not build them.
##
## [b]The table is a [GridContainer].[/b] It replaced eight independent
## [HBoxContainer] rows, each of which reserved the same guessed pixel width for
## its name column. That arrangement only looked like a table while every label
## happened to fit inside the guess: the moment one did not -- a longer action
## name, a translation, a theme whose font measures wider -- that row's columns
## slid out of step with the rest and the list read as garbage. A grid
## shares one set of column widths across every row, so the columns cannot
## disagree.
##
## [b]The rows are authored, not generated.[/b] One row per action in the scene,
## in the order a player reads them: movement, then jump/crouch, then fire/aim.
## Walking the [InputMap] instead would list Godot's own [code]ui_*[/code]
## actions in hash order, which is neither the project's input list nor an order
## anybody chose. [method _ready] checks the scene against
## [constant KeybindMap.ACTIONS] so the two cannot drift apart in silence.
##
## [b]The capture.[/b] Pressing a slot button arms a capture and raises a
## full-rect overlay. From that moment this node reads [method Node._input],
## which runs ahead of GUI handling, and swallows every key and button event it
## sees. That is what makes the capture honest: the click that lands on the
## overlay is a bind attempt, not a button press, and there is no control
## underneath that can steal the very input the player is trying to bind. Escape
## cancels, Backspace clears the slot.
##
## The mouse [i]release[/i] that follows a bound mouse button is swallowed too.
## Without that, the release arrives after the overlay is gone and activates
## whatever [Button] happens to be under the cursor -- which, since the player
## just clicked on a rebind row, is usually the row they were editing.
##
## [b]Conflicts are refused, not merged.[/b] Binding a key that another action
## already holds leaves both bindings untouched and says which action holds it.
## The alternative -- stealing the key and leaving the other action unbound --
## is how players end up with an unbound jump and no idea why.

## Emitted after a binding is changed, cleared or reset. [SettingsScreen] saves
## on it.
signal binding_changed()

## Emitted when a capture starts and ends, so an owner can stop competing for
## Escape while one is in flight.
signal capture_state_changed(capturing: bool)

## Suffixes on the four cells that make up one authored row. An action's cells
## are named for the action in PascalCase -- [code]move_forward[/code] becomes
## [code]MoveForwardName[/code], [code]MoveForwardSlot1[/code] and so on -- which
## is what lets [constant KeybindMap.ACTIONS] address the scene without a second
## list of node names to keep in step with it.
const _NAME_SUFFIX: String = "Name"
const _SLOT_SUFFIX: String = "Slot"
const _RESET_SUFFIX: String = "Reset"

@onready var _table: GridContainer = $Layout/Scroll/Table
@onready var _status_label: Label = $Layout/Footer/Status
@onready var _reset_all_button: Button = $Layout/Footer/ResetAll
@onready var _overlay: PanelContainer = $CaptureOverlay
@onready var _overlay_label: Label = $CaptureOverlay/CaptureLabel

var _store: SettingsStore = null

## Action -> Array of [Button], one per slot, in slot order.
var _slot_buttons: Dictionary[StringName, Array] = {}

## Action currently being rebound, or [code]&""[/code] when idle.
var _capture_action: StringName = &""
var _capture_slot: int = -1

## Set when a mouse button has just been bound, so its release can be eaten.
var _swallow_mouse_release: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	_bind_rows()
	_reset_all_button.pressed.connect(_on_reset_all_pressed)
	refresh()


## True while waiting for the player to press the key they want bound.
func is_capturing() -> bool:
	return _capture_action != &""


## Redraw every slot button from the store.
func refresh() -> void:
	for action: StringName in KeybindMap.ACTIONS:
		if not _slot_buttons.has(action):
			continue
		var buttons: Array = _slot_buttons[action]
		for slot: int in range(buttons.size()):
			var entry: Variant = buttons[slot]
			if not (entry is Button):
				continue
			var button: Button = entry
			button.text = KeybindMap.describe(_store.keybinds.get_binding(action, slot))


## Abort a capture in flight, leaving the binding alone.
func cancel_capture() -> void:
	if is_capturing():
		_end_capture("Rebind cancelled.")


## The actions this panel shows, in the order the scene lays them out.
##
## Read off the authored rows rather than restated, so a test that asks what the
## player will see is answering from the scene itself.
func get_displayed_actions() -> Array[StringName]:
	var shown: Array[StringName] = []
	for action: StringName in KeybindMap.ACTIONS:
		if _slot_buttons.has(action):
			shown.append(action)
	return shown


## The label the scene puts in the name column for [param action].
func get_row_name(action: StringName) -> String:
	var label: Label = _table.get_node_or_null(_row_prefix(action) + _NAME_SUFFIX) as Label
	return label.text if label != null else ""


func _input(event: InputEvent) -> void:
	# Eat the release half of a click that was consumed as a binding, before
	# anything else looks at it.
	if _swallow_mouse_release and event is InputEventMouseButton:
		var released: InputEventMouseButton = event
		if not released.pressed:
			_swallow_mouse_release = false
			get_viewport().set_input_as_handled()
		return

	if not is_capturing():
		return

	if event is InputEventKey:
		var key: InputEventKey = event
		get_viewport().set_input_as_handled()
		if not key.pressed or key.echo:
			return
		var code: int = key.physical_keycode
		if code == 0:
			code = key.keycode
		match code:
			KEY_ESCAPE:
				_end_capture("Rebind cancelled.")
			KEY_BACKSPACE, KEY_DELETE:
				_clear_captured_slot()
			_:
				_commit({KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_KEY, KeybindMap.KEY_FIELD_CODE: code})
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		get_viewport().set_input_as_handled()
		if not button.pressed:
			return
		_swallow_mouse_release = true
		_commit({
			KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_MOUSE_BUTTON,
			KeybindMap.KEY_FIELD_INDEX: int(button.button_index),
		})
		return

	if event is InputEventJoypadButton:
		var pad_button: InputEventJoypadButton = event
		get_viewport().set_input_as_handled()
		if not pad_button.pressed:
			return
		_commit({
			KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_JOY_BUTTON,
			KeybindMap.KEY_FIELD_INDEX: int(pad_button.button_index),
		})
		return

	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		# Sticks idle around zero and drift is normal, so only a decisive push
		# counts as a deliberate bind.
		if absf(motion.axis_value) < 0.7:
			return
		get_viewport().set_input_as_handled()
		_commit({
			KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_JOY_AXIS,
			KeybindMap.KEY_FIELD_AXIS: int(motion.axis),
			KeybindMap.KEY_FIELD_VALUE: signf(motion.axis_value),
		})


# --- Wiring -------------------------------------------------------------------

## Connect the authored cells to the actions they belong to.
##
## An action whose row is missing from the scene is a hard error rather than a
## quietly skipped line: it means somebody added an action and did not add the
## row, and the player would simply never be offered the binding.
func _bind_rows() -> void:
	for action: StringName in KeybindMap.ACTIONS:
		var prefix: String = _row_prefix(action)
		var name_label: Label = _table.get_node_or_null(prefix + _NAME_SUFFIX) as Label
		var reset: Button = _table.get_node_or_null(prefix + _RESET_SUFFIX) as Button
		if name_label == null or reset == null:
			push_error("keybind_panel.tscn has no row for action '%s' (expected %s* cells)" % [action, prefix])
			continue

		var buttons: Array = []
		for slot: int in range(KeybindMap.MAX_BINDINGS):
			var button: Button = _table.get_node_or_null("%s%s%d" % [prefix, _SLOT_SUFFIX, slot + 1]) as Button
			if button == null:
				push_error("keybind_panel.tscn has no slot %d for action '%s'" % [slot + 1, action])
				continue
			button.pressed.connect(_on_slot_pressed.bind(action, slot))
			buttons.append(button)

		reset.pressed.connect(_on_reset_action_pressed.bind(action))
		_slot_buttons[action] = buttons


## The node-name prefix the scene uses for [param action]'s four cells.
static func _row_prefix(action: StringName) -> String:
	return String(action).to_pascal_case()


# --- Capture ------------------------------------------------------------------

func _on_slot_pressed(action: StringName, slot: int) -> void:
	_capture_action = action
	_capture_slot = slot
	_overlay_label.text = "Press an input for %s (slot %d).\nEscape cancels. Backspace clears." % [
		KeybindMap.display_name(action),
		slot + 1,
	]
	_overlay.visible = true
	_set_status("")
	capture_state_changed.emit(true)


func _commit(binding: Dictionary) -> void:
	var action: StringName = _capture_action
	var slot: int = _capture_slot
	var conflict: StringName = _store.keybinds.find_conflict(action, slot, binding)
	if conflict != &"":
		# Refused. Both bindings survive, and the message names the thief.
		_end_capture("%s is already bound to %s. Binding unchanged." % [
			KeybindMap.describe(binding),
			KeybindMap.display_name(conflict),
		])
		return

	_store.keybinds.set_binding(action, slot, binding)
	_store.keybinds.apply_to_input_map()
	_store.save_to_disk()
	refresh()
	_end_capture("%s bound to %s." % [KeybindMap.display_name(action), KeybindMap.describe(binding)])
	binding_changed.emit()


func _clear_captured_slot() -> void:
	var action: StringName = _capture_action
	var slot: int = _capture_slot
	_store.keybinds.clear_binding(action, slot)
	_store.keybinds.apply_to_input_map()
	_store.save_to_disk()
	refresh()
	_end_capture("%s slot %d cleared." % [KeybindMap.display_name(action), slot + 1])
	binding_changed.emit()


func _end_capture(message: String) -> void:
	_capture_action = &""
	_capture_slot = -1
	_overlay.visible = false
	_set_status(message)
	capture_state_changed.emit(false)


func _on_reset_action_pressed(action: StringName) -> void:
	if is_capturing():
		return
	_store.keybinds.reset_action(action)
	_store.keybinds.apply_to_input_map()
	_store.save_to_disk()
	refresh()
	_set_status("%s reset to default." % KeybindMap.display_name(action))
	binding_changed.emit()


func _on_reset_all_pressed() -> void:
	if is_capturing():
		return
	_store.keybinds.reset_to_defaults()
	_store.keybinds.apply_to_input_map()
	_store.save_to_disk()
	refresh()
	_set_status("All bindings reset to default.")
	binding_changed.emit()


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
