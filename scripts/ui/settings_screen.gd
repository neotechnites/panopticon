class_name SettingsScreen
extends Control

## Every setting the player can change, on four tabs, built entirely in code.
##
## Built in code rather than laid out in a [code].tscn[/code] on purpose. There
## is no art direction yet, the instruction is maximum simplicity, and a scene
## file full of hand-placed default-themed controls is a merge conflict that
## nobody can read a diff of. When the game has a visual identity this file is
## where the theme goes, or it is replaced wholesale by a designed scene talking
## to the same [SettingsStore]. Nothing outside this file knows how it looks.
##
## [b]Apply live, save on close.[/b] Every control writes its value into the
## store and applies it the moment it moves, so a volume slider is audible while
## dragging and a resolution change is visible immediately. The file is written
## once, on [method close] -- except for rebinds, which [KeybindPanel] saves
## itself because they are rare and losing one is maddening.
##
## Drop it anywhere: as a child of [PauseMenu], as the root of
## [code]scenes/ui/settings_screen.tscn[/code] for a main menu, or into a test.
## Its only dependency is the store, which it fetches for itself.

## Emitted when the player leaves the screen, after the file is written.
signal closed()

## Mirrors [signal KeybindPanel.capture_state_changed], so an owner can stand
## back from Escape while a rebind is in flight.
signal capture_state_changed(capturing: bool)

var _store: SettingsStore = null
var _keybind_panel: KeybindPanel = null

var _sensitivity_slider: HSlider = null
var _sensitivity_value: Label = null
var _invert_check: CheckBox = null
var _fov_slider: HSlider = null
var _fov_value: Label = null

var _master_slider: HSlider = null
var _master_value: Label = null
var _effects_slider: HSlider = null
var _effects_value: Label = null
var _music_slider: HSlider = null
var _music_value: Label = null

var _display_mode_option: OptionButton = null
var _resolution_option: OptionButton = null
var _vsync_option: OptionButton = null
var _audio_note: Label = null

## Set while the controls are being written from the store, so the change
## signals they emit do not bounce straight back into the store.
var _syncing: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	refresh()


## True while [KeybindPanel] is waiting for a key.
func is_capturing_input() -> bool:
	return _keybind_panel != null and _keybind_panel.is_capturing()


## Write the file and report the screen closed. The owner decides what to show
## next; this node does not hide itself, so it works equally as a child that is
## toggled and as a scene that is freed.
func close() -> void:
	if is_capturing_input():
		_keybind_panel.cancel_capture()
	_store.save_to_disk()
	closed.emit()


## Pull every control's value from the store.
func refresh() -> void:
	_syncing = true

	var settings: GameSettings = _store.settings
	_sensitivity_slider.value = settings.mouse_sensitivity
	_invert_check.button_pressed = settings.invert_look_y
	_fov_slider.value = settings.field_of_view
	_master_slider.value = settings.master_volume
	_effects_slider.value = settings.effects_volume
	_music_slider.value = settings.music_volume
	_display_mode_option.selected = int(settings.display_mode)
	_vsync_option.selected = int(settings.vsync_mode)
	_resolution_option.selected = _resolution_index(settings.resolution)

	_syncing = false

	_update_value_labels()
	_update_audio_note()
	if _keybind_panel != null:
		_keybind_panel.refresh()


# --- Construction -------------------------------------------------------------

func _build() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_right = 0.0
	margin.offset_bottom = 0.0
	margin.add_theme_constant_override(&"margin_left", 24)
	margin.add_theme_constant_override(&"margin_right", 24)
	margin.add_theme_constant_override(&"margin_top", 24)
	margin.add_theme_constant_override(&"margin_bottom", 24)
	add_child(margin)

	var panel: PanelContainer = PanelContainer.new()
	margin.add_child(panel)

	var inner: MarginContainer = MarginContainer.new()
	inner.add_theme_constant_override(&"margin_left", 12)
	inner.add_theme_constant_override(&"margin_right", 12)
	inner.add_theme_constant_override(&"margin_top", 12)
	inner.add_theme_constant_override(&"margin_bottom", 12)
	panel.add_child(inner)

	var layout: VBoxContainer = VBoxContainer.new()
	inner.add_child(layout)

	var title: Label = Label.new()
	title.text = "SETTINGS"
	layout.add_child(title)

	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)

	tabs.add_child(_build_game_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_video_tab())
	tabs.add_child(_build_controls_tab())

	var footer: HBoxContainer = HBoxContainer.new()
	layout.add_child(footer)

	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(close)
	footer.add_child(back)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var reset: Button = Button.new()
	reset.text = "Reset All Settings"
	reset.pressed.connect(_on_reset_all_pressed)
	footer.add_child(reset)


func _build_game_tab() -> Control:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Game"

	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = GameSettings.MIN_MOUSE_SENSITIVITY
	_sensitivity_slider.max_value = GameSettings.MAX_MOUSE_SENSITIVITY
	_sensitivity_slider.step = 0.0001
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_sensitivity_value = Label.new()
	tab.add_child(_labelled_row("Mouse Sensitivity", _sensitivity_slider, _sensitivity_value))

	_invert_check = CheckBox.new()
	_invert_check.text = "Invert Y"
	_invert_check.toggled.connect(_on_invert_toggled)
	tab.add_child(_invert_check)

	_fov_slider = HSlider.new()
	_fov_slider.min_value = GameSettings.MIN_FIELD_OF_VIEW
	_fov_slider.max_value = GameSettings.MAX_FIELD_OF_VIEW
	_fov_slider.step = 1.0
	_fov_slider.value_changed.connect(_on_fov_changed)
	_fov_value = Label.new()
	tab.add_child(_labelled_row("Field of View", _fov_slider, _fov_value))

	var note: Label = Label.new()
	note.text = "Sensitivity and invert-Y are written into the active MovementProfile; field of view into the player camera."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)

	return tab


func _build_audio_tab() -> Control:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Audio"

	_master_slider = _make_volume_slider(_on_master_changed)
	_master_value = Label.new()
	tab.add_child(_labelled_row("Master", _master_slider, _master_value))

	_effects_slider = _make_volume_slider(_on_effects_changed)
	_effects_value = Label.new()
	tab.add_child(_labelled_row("Effects", _effects_slider, _effects_value))

	_music_slider = _make_volume_slider(_on_music_changed)
	_music_value = Label.new()
	tab.add_child(_labelled_row("Music", _music_slider, _music_value))

	_audio_note = Label.new()
	_audio_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(_audio_note)
	_update_audio_note()

	return tab


func _build_video_tab() -> Control:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.name = "Video"

	_display_mode_option = OptionButton.new()
	_display_mode_option.add_item("Windowed", int(GameSettings.DisplayMode.WINDOWED))
	_display_mode_option.add_item("Fullscreen", int(GameSettings.DisplayMode.FULLSCREEN))
	_display_mode_option.add_item("Borderless Fullscreen", int(GameSettings.DisplayMode.BORDERLESS))
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	tab.add_child(_labelled_row("Display Mode", _display_mode_option, null))

	_resolution_option = OptionButton.new()
	for choice: Vector2i in GameSettings.RESOLUTION_CHOICES:
		_resolution_option.add_item("%d x %d" % [choice.x, choice.y])
	_resolution_option.item_selected.connect(_on_resolution_selected)
	tab.add_child(_labelled_row("Resolution", _resolution_option, null))

	_vsync_option = OptionButton.new()
	_vsync_option.add_item("Off", int(GameSettings.VSyncMode.DISABLED))
	_vsync_option.add_item("On", int(GameSettings.VSyncMode.ENABLED))
	_vsync_option.add_item("Adaptive", int(GameSettings.VSyncMode.ADAPTIVE))
	_vsync_option.item_selected.connect(_on_vsync_selected)
	tab.add_child(_labelled_row("V-Sync", _vsync_option, null))

	var note: Label = Label.new()
	note.text = "Resolution applies to the window; in either fullscreen mode the display's own resolution is used."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)

	return tab


func _build_controls_tab() -> Control:
	var tab: MarginContainer = MarginContainer.new()
	tab.name = "Controls"
	_keybind_panel = KeybindPanel.new()
	_keybind_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_keybind_panel.capture_state_changed.connect(_on_capture_state_changed)
	tab.add_child(_keybind_panel)
	return tab


func _make_volume_slider(handler: Callable) -> HSlider:
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value_changed.connect(handler)
	return slider


## A label, a control that expands, and an optional right-hand readout.
func _labelled_row(text: String, control: Control, value: Label) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()

	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(160.0, 0.0)
	row.add_child(label)

	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(control)

	if value != null:
		value.custom_minimum_size = Vector2(90.0, 0.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)

	return row


# --- Handlers -----------------------------------------------------------------

func _on_sensitivity_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.mouse_sensitivity = value
	_after_change()


func _on_invert_toggled(pressed: bool) -> void:
	if _syncing:
		return
	_store.settings.invert_look_y = pressed
	_after_change()


func _on_fov_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.field_of_view = value
	_after_change()


func _on_master_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.master_volume = value
	_after_change()


func _on_effects_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.effects_volume = value
	_after_change()


func _on_music_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.music_volume = value
	_after_change()


func _on_display_mode_selected(index: int) -> void:
	if _syncing:
		return
	_store.settings.display_mode = index as GameSettings.DisplayMode
	_after_change()


func _on_vsync_selected(index: int) -> void:
	if _syncing:
		return
	_store.settings.vsync_mode = index as GameSettings.VSyncMode
	_after_change()


func _on_resolution_selected(index: int) -> void:
	if _syncing:
		return
	if index < 0 or index >= GameSettings.RESOLUTION_CHOICES.size():
		return
	_store.settings.resolution = GameSettings.RESOLUTION_CHOICES[index]
	_after_change()


func _on_capture_state_changed(capturing: bool) -> void:
	capture_state_changed.emit(capturing)


func _on_reset_all_pressed() -> void:
	if is_capturing_input():
		return
	_store.reset_all()
	refresh()


## Clamp, apply and redraw the readouts. Not saved -- [method close] does that.
func _after_change() -> void:
	_store.settings.clamp_all()
	_store.apply_all()
	_update_value_labels()


func _update_value_labels() -> void:
	_sensitivity_value.text = "%.4f" % _store.settings.mouse_sensitivity
	_fov_value.text = "%d" % int(roundf(_store.settings.field_of_view))
	_master_value.text = _percent(_store.settings.master_volume)
	_effects_value.text = _percent(_store.settings.effects_volume)
	_music_value.text = _percent(_store.settings.music_volume)


static func _percent(value: float) -> String:
	return "%d%%" % int(roundf(value * 100.0))


func _resolution_index(resolution: Vector2i) -> int:
	var index: int = GameSettings.RESOLUTION_CHOICES.find(resolution)
	return index if index >= 0 else 0


## Show the caveat only when it is true.
##
## It used to be permanent, because the project shipped no bus layout and two of
## these three sliders drove nothing. res://default_bus_layout.tres now defines
## Master, Effects and Music, so the normal state is silence -- an explanation of
## a problem that no longer exists is worse than no explanation. The check itself
## stays: if that file is ever deleted or renamed the sliders go quiet again,
## and this is the only place the player would find out.
func _update_audio_note() -> void:
	if _audio_note == null:
		return
	var note: String = _missing_bus_note()
	_audio_note.text = note
	_audio_note.visible = not note.is_empty()


## Names the buses the project does not define, or an empty string when all
## three are present.
static func _missing_bus_note() -> String:
	var missing: PackedStringArray = PackedStringArray()
	for bus_name: StringName in [GameSettings.MASTER_BUS, GameSettings.EFFECTS_BUS, GameSettings.MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) < 0:
			missing.append(String(bus_name))
	if missing.is_empty():
		return ""
	return "No audio bus named %s; that slider is saved but drives nothing until res://default_bus_layout.tres defines it." % ", ".join(missing)
