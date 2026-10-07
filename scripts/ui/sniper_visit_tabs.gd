class_name SniperVisitTabs
extends TabContainer

## Five tabs, 1st to 5th tower visit, each the same sniper controls, editing a [GameSettings].
## Writes the settings on every edit and emits [signal changed]; the owner carries it further.

signal changed()

const TAB_KEYS: Array[String] = [
	"SETTINGS_TURN_1", "SETTINGS_TURN_2", "SETTINGS_TURN_3", "SETTINGS_TURN_4", "SETTINGS_TURN_5",
]

## Rows per tab: reload, then every [SniperKnobs.Knob].
const ROWS: int = SniperKnobs.COUNT + 1

const RELOAD_STEP: float = 0.05

var _settings: GameSettings = null
## Visit-major, [constant ROWS] per visit: an [HSlider], or a [CheckBox] for a switch.
var _controls: Array[Control] = []
var _readouts: Array[Label] = []
var _syncing: bool = false


## Build the five tabs over [param settings], opened on [param visit] (zero-based).
func setup(settings: GameSettings, visit: int = 0) -> void:
	_settings = settings
	for visit_index: int in SniperKnobs.VISITS:
		var page: GridContainer = GridContainer.new()
		page.name = TAB_KEYS[visit_index]
		page.columns = 3
		page.add_theme_constant_override(&"h_separation", 8)
		page.add_theme_constant_override(&"v_separation", 4)
		add_child(page)
		set_tab_title(visit_index, TAB_KEYS[visit_index])
		_add_row(page, visit_index, -1)
		for knob: int in SniperKnobs.COUNT:
			_add_row(page, visit_index, knob)
	current_tab = clampi(visit, 0, SniperKnobs.VISITS - 1)
	refresh()


## Pull every control's value from the settings.
func refresh() -> void:
	if _settings == null:
		return
	_syncing = true
	for visit: int in SniperKnobs.VISITS:
		for row: int in ROWS:
			var value: float = _value_of(visit, row - 1)
			var control: Control = _controls[visit * ROWS + row]
			if control is CheckBox:
				(control as CheckBox).button_pressed = value > 0.5
			else:
				(control as HSlider).value = value
				_readouts[visit * ROWS + row].text = _format(row - 1, value)
	_syncing = false


## One labelled row; [param knob] -1 is the reload.
func _add_row(page: GridContainer, visit: int, knob: int) -> void:
	var spec: Array = SniperKnobs.SPECS[knob] if knob >= 0 else []
	var label: Label = Label.new()
	label.text = String(spec[1]) if knob >= 0 else "DEBUG_RELOAD"
	label.custom_minimum_size = Vector2(260.0, 0.0)
	page.add_child(label)
	var readout: Label = Label.new()
	readout.custom_minimum_size = Vector2(110.0, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if knob >= 0 and String(spec[6]) == "toggle":
		var check: CheckBox = CheckBox.new()
		check.toggled.connect(func(on: bool) -> void: _write(visit, knob, 1.0 if on else 0.0))
		page.add_child(check)
		_controls.append(check)
	else:
		var slider: HSlider = HSlider.new()
		slider.min_value = float(spec[2]) if knob >= 0 else GameSettings.MIN_RELOAD_BY_TURN
		slider.max_value = float(spec[3]) if knob >= 0 else GameSettings.MAX_RELOAD_BY_TURN
		slider.step = float(spec[4]) if knob >= 0 else RELOAD_STEP
		slider.custom_minimum_size = Vector2(320.0, 0.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			readout.text = _format(knob, value)
			_write(visit, knob, value))
		page.add_child(slider)
		_controls.append(slider)
	page.add_child(readout)
	_readouts.append(readout)


func _value_of(visit: int, knob: int) -> float:
	if knob < 0:
		return _settings.reload_by_turn[visit]
	return _settings.sniper_by_visit[SniperKnobs.index(visit, knob)]


func _write(visit: int, knob: int, value: float) -> void:
	if _syncing or _settings == null:
		return
	if knob < 0:
		var reloads: PackedFloat32Array = _settings.reload_by_turn.duplicate()
		reloads[visit] = value
		_settings.reload_by_turn = reloads
	else:
		var values: PackedFloat32Array = _settings.sniper_by_visit.duplicate()
		values[SniperKnobs.index(visit, knob)] = value
		_settings.sniper_by_visit = values
	changed.emit()


func _format(knob: int, value: float) -> String:
	var unit: String = String(SniperKnobs.SPECS[knob][6]) if knob >= 0 else "DEBUG_UNIT_SECONDS"
	var step: float = float(SniperKnobs.SPECS[knob][4]) if knob >= 0 else RELOAD_STEP
	if unit == "DEBUG_UNIT_SPEED" and value <= 0.0:
		return tr("DEBUG_SPEED_WEAPON")
	var number: String = String.num(value, 0 if step >= 1.0 else (1 if step >= 0.1 else 2))
	return number if unit.is_empty() else tr(unit) % number
