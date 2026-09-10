class_name SettingsScreen
extends Control

## Every setting the player can change, on four tabs.
##
## The layout lives in [code]scenes/ui/settings_screen.tscn[/code] and this file
## drives data into it. It used to build the whole screen in code, on the theory
## that a scene full of default-themed controls was an unreadable diff. The
## trade was worse than it looked: nothing was laid out where a person could see
## it, every column width was a number guessed twice in two different functions,
## and the result only lined up as long as the guesses held. Structure in the
## scene, values in the script; when the game gets a visual identity the scene is
## where the theme goes and nothing here has to change.
##
## [b]Instantiate the scene -- do not construct this class.[/b] [MainMenu] and
## [PauseMenu] both load the scene, so there is one settings screen rather than
## two that can disagree. [code]SettingsScreen.new()[/code] would hand back a
## bare [Control] with none of its controls.
##
## [b]Apply live, save on close.[/b] Every control writes its value into the
## store and applies it the moment it moves, so a volume slider is audible while
## dragging and a resolution change is visible immediately. The file is written
## once, on [method close] -- except for rebinds, which [KeybindPanel] saves
## itself because they are rare and losing one is maddening.

## Emitted when the player leaves the screen, after the file is written.
signal closed()

## Mirrors [signal KeybindPanel.capture_state_changed], so an owner can stand
## back from Escape while a rebind is in flight.
signal capture_state_changed(capturing: bool)

@onready var _keybind_panel: KeybindPanel = %KeybindPanel

@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _invert_check: CheckBox = %InvertCheck
@onready var _fov_slider: HSlider = %FovSlider
@onready var _fov_value: Label = %FovValue

@onready var _master_slider: HSlider = %MasterSlider
@onready var _master_value: Label = %MasterValue
@onready var _effects_slider: HSlider = %EffectsSlider
@onready var _effects_value: Label = %EffectsValue
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue

@onready var _display_mode_option: OptionButton = %DisplayModeOption
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _vsync_option: OptionButton = %VsyncOption
@onready var _audio_note: Label = %Note

var _store: SettingsStore = null

## Set while the controls are being written from the store, so the change
## signals they emit do not bounce straight back into the store.
var _syncing: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	_configure_ranges()
	_fill_choices()
	_connect_controls()
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


# --- Wiring -------------------------------------------------------------------

## Slider bounds come from [GameSettings], not from the scene, so the range the
## player can drag to and the range [method GameSettings.clamp_all] enforces are
## the same numbers rather than two copies that can drift.
func _configure_ranges() -> void:
	_sensitivity_slider.min_value = GameSettings.MIN_MOUSE_SENSITIVITY
	_sensitivity_slider.max_value = GameSettings.MAX_MOUSE_SENSITIVITY
	_sensitivity_slider.step = 0.0001

	_fov_slider.min_value = GameSettings.MIN_FIELD_OF_VIEW
	_fov_slider.max_value = GameSettings.MAX_FIELD_OF_VIEW
	_fov_slider.step = 1.0

	for slider: HSlider in [_master_slider, _effects_slider, _music_slider]:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01


## Option lists are data, so they are filled from the enums and the shipped
## choice list rather than typed into the scene where they could fall out of
## step with the values they select.
func _fill_choices() -> void:
	_display_mode_option.clear()
	_display_mode_option.add_item("Windowed", int(GameSettings.DisplayMode.WINDOWED))
	_display_mode_option.add_item("Fullscreen", int(GameSettings.DisplayMode.FULLSCREEN))
	_display_mode_option.add_item("Borderless Fullscreen", int(GameSettings.DisplayMode.BORDERLESS))

	_resolution_option.clear()
	for choice: Vector2i in GameSettings.RESOLUTION_CHOICES:
		_resolution_option.add_item("%d x %d" % [choice.x, choice.y])

	_vsync_option.clear()
	_vsync_option.add_item("Off", int(GameSettings.VSyncMode.DISABLED))
	_vsync_option.add_item("On", int(GameSettings.VSyncMode.ENABLED))
	_vsync_option.add_item("Adaptive", int(GameSettings.VSyncMode.ADAPTIVE))


func _connect_controls() -> void:
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_invert_check.toggled.connect(_on_invert_toggled)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_master_slider.value_changed.connect(_on_master_changed)
	_effects_slider.value_changed.connect(_on_effects_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_vsync_option.item_selected.connect(_on_vsync_selected)
	_keybind_panel.capture_state_changed.connect(_on_capture_state_changed)

	($Frame/Dialog/Padding/Layout/Footer/Back as Button).pressed.connect(close)
	($Frame/Dialog/Padding/Layout/Footer/ResetAll as Button).pressed.connect(_on_reset_all_pressed)


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
