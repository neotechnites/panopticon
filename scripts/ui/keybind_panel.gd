class_name KeybindPanel
extends Control

## The rebinding UI: one row per action, two binding slots each, plus the
## capture overlay.
##
## Greybox by instruction -- default theme, no colours, no icons. Every control
## here is a stock [Button] or [Label].
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

const _ACTION_COLUMN_WIDTH: float = 160.0
const _SLOT_COLUMN_WIDTH: float = 150.0

var _store: SettingsStore = null
var _status_label: Label = null
var _overlay: PanelContainer = null
var _overlay_label: Label = null

## Action -> Array of [Button], one per slot, in slot order.
var _slot_buttons: Dictionary[StringName, Array] = {}

## Action currently being rebound, or [code]&""[/code] when idle.
var _capture_action: StringName = &""
var _capture_slot: int = -1

## Set when a mouse button has just been bound, so its release can be eaten.
var _swallow_mouse_release: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	_build()
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


# --- Construction -------------------------------------------------------------

func _build() -> void:
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_right = 0.0
	layout.offset_bottom = 0.0
	add_child(layout)

	var hint: Label = Label.new()
	hint.text = "Two bindings per action. Escape cancels a rebind, Backspace clears the slot."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for action: StringName in KeybindMap.ACTIONS:
		rows.add_child(_build_row(action))

	var footer: HBoxContainer = HBoxContainer.new()
	layout.add_child(footer)

	var reset_all: Button = Button.new()
	reset_all.text = "Reset All Bindings"
	reset_all.pressed.connect(_on_reset_all_pressed)
	footer.add_child(reset_all)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status_label)

	_build_overlay()


func _build_row(action: StringName) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()

	var name_label: Label = Label.new()
	name_label.text = KeybindMap.display_name(action)
	name_label.custom_minimum_size = Vector2(_ACTION_COLUMN_WIDTH, 0.0)
	row.add_child(name_label)

	var buttons: Array = []
	for slot: int in range(KeybindMap.MAX_BINDINGS):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(_SLOT_COLUMN_WIDTH, 0.0)
		button.clip_text = true
		button.tooltip_text = "Rebind %s (slot %d)" % [KeybindMap.display_name(action), slot + 1]
		button.pressed.connect(_on_slot_pressed.bind(action, slot))
		row.add_child(button)
		buttons.append(button)
	_slot_buttons[action] = buttons

	var reset: Button = Button.new()
	reset.text = "Reset"
	reset.pressed.connect(_on_reset_action_pressed.bind(action))
	row.add_child(reset)

	return row


func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.offset_right = 0.0
	_overlay.offset_bottom = 0.0
	# STOP, so a click that misses this node's own _input still cannot reach a
	# control underneath while a capture is armed.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_child(_overlay_label)


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
