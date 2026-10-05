class_name DebugMenu
extends Control

## Developer tools kept out of the player's menus. In play: live control of the running match.
## From the main menu: Quick match and the rules screen. F1 or backtick, or the Debug buttons.

## Emitted when Back or Escape leaves the menu.
signal closed()
## Emitted when Quick match is chosen; the main menu owns the setup screen.
signal quick_match_requested()

## In-match debug actions and the key naming each.
const HOTKEYS: Array[Array] = [
	[PlayerActions.TURBO, "MENU_DEBUG_KEY_TURBO"],
	[PlayerActions.GODMODE, "MENU_DEBUG_KEY_GODMODE"],
	[PlayerActions.HUD_TOGGLE, "MENU_DEBUG_KEY_HUD"],
	[PlayerActions.FREE_CAMERA, "MENU_DEBUG_KEY_FREE_CAMERA"],
	[PlayerActions.FREECAM_UP, "MENU_DEBUG_KEY_FREECAM_UP"],
	[PlayerActions.FREECAM_DOWN, "MENU_DEBUG_KEY_FREECAM_DOWN"],
]

## The readout's name for each match phase, by Phase key.
const PHASE_KEYS: Dictionary = {
	"IDLE": "DEBUG_PHASE_IDLE", "RACE": "DEBUG_PHASE_RACE", "ROUND": "DEBUG_PHASE_ROUND",
	"MATCH_OVER": "DEBUG_PHASE_MATCH_OVER", "HUB": "DEBUG_PHASE_HUB",
}

## Seconds the Extend button adds to the siege clock.
const EXTEND_SECONDS: float = 30.0

## Set by the pause menu: the menu drives the running match rather than the setup.
var in_match: bool = false

var _controller: MatchController = null
var _readout: Label = null
var _first: Control = null

@onready var _frame: Control = $Frame
@onready var _body: VBoxContainer = %Body
@onready var _back: Button = %Back
@onready var _rules_screen: SettingsScreen = %RulesScreen


func _ready() -> void:
	_back.pressed.connect(close)
	_rules_screen.closed.connect(_close_rules)
	_rules_screen.visible = false


## Build the menu for where it was opened and show it.
func open() -> void:
	PlayerActions.ensure_registered()
	_controller = _find_controller() if in_match else null
	_rebuild()
	visible = true
	_rules_screen.visible = false
	_frame.visible = true
	if _first != null:
		_first.grab_focus()


## Back one step: out of the rules screen, else out of the menu.
func back() -> void:
	if _rules_screen.is_capturing_input():
		return
	if _rules_screen.visible:
		_rules_screen.close()
	else:
		close()


func close() -> void:
	SettingsStore.instance().save_to_disk()
	visible = false
	closed.emit()


func _find_controller() -> MatchController:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	for found: Node in scene.find_children("*", "MatchController", true, false):
		var controller: MatchController = found as MatchController
		if controller != null and not controller.hub_mode:
			return controller
	return null


# --- Building ------------------------------------------------------------------

func _rebuild() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_first = null
	_readout = null
	if not in_match:
		_build_setup()
	elif _controller == null:
		_note("MENU_DEBUG_NO_MATCH")
	else:
		_build_phase()
		_build_sniper()
		_build_runners()
		_build_health()
	_heading("MENU_DEBUG_HOTKEYS")
	_note(_hotkey_text())


func _build_setup() -> void:
	_heading("MENU_DEBUG_MATCH")
	_button(_body, "MENU_QUICK_MATCH", func() -> void: quick_match_requested.emit())
	_button(_body, "MENU_DEBUG_RULES", _open_rules)
	_toggle("MENU_DEBUG_FULL_RULES", MatchSetupScreen.show_all_rules_everywhere,
			func(on: bool) -> void: MatchSetupScreen.show_all_rules_everywhere = on)


func _build_phase() -> void:
	var rules: MatchRules = _controller.get_rules()
	_heading("DEBUG_SECTION_PHASE")
	_readout = Label.new()
	_readout.theme_type_variation = &"Note"
	_body.add_child(_readout)
	_refresh_readout()
	var row: HBoxContainer = _row()
	_button(row, "DEBUG_SKIP_PHASE", _act.bind(_controller.debug_skip_phase))
	_button(row, "DEBUG_RESTART_ROUND", _act.bind(_controller.debug_restart_round))
	_button(row, "DEBUG_NEXT_ROUND", _act.bind(_controller.debug_next_round))
	_button(row, "DEBUG_RESTART_MATCH", _act.bind(_controller.restart))
	var clock: HBoxContainer = _row()
	_toggle("DEBUG_PAUSE_CLOCK", _controller.debug_clock_paused, _pause_clock, clock)
	_button(clock, "DEBUG_EXTEND_CLOCK", _extend_clock)
	var win_titles: PackedStringArray = ["SETUP_TOWER_WIN_TOTAL", "SETUP_TOWER_WIN_SHUTOUT", "SETUP_TOWER_WIN_HOLD"]
	_choice("DEBUG_TOWER_WIN", win_titles, int(rules.shooter_win_condition), _set_win_condition)
	_slider("DEBUG_SIEGE_SECONDS", GameSettings.MIN_HOLD_DURATION_SECONDS, GameSettings.MAX_HOLD_DURATION_SECONDS,
			5.0, "DEBUG_UNIT_SECONDS", rules.hold_duration_seconds,
			func(value: float) -> void: _rule(&"hold_duration_seconds", value, &"hold_duration_seconds"))
	_slider("DEBUG_SHUTOUT_COUNT", GameSettings.MIN_SHUTOUT_COUNT, GameSettings.MAX_PRISONER_COUNT,
			1.0, "", rules.shutout_count,
			func(value: float) -> void: _rule(&"shutout_count", int(value), &"shutout_count"))
	_slider("DEBUG_ROUNDS_TO_WIN", GameSettings.MIN_ROUNDS_TO_WIN_MATCH, GameSettings.MAX_ROUNDS_TO_WIN_MATCH,
			1.0, "", rules.rounds_to_win_match,
			func(value: float) -> void: _rule(&"rounds_to_win_match", int(value), &"rounds_to_win_match"))
	_slider("DEBUG_KILL_BEAT", 0.0, 10.0, 0.1, "DEBUG_UNIT_SECONDS", rules.kill_beat_seconds,
			func(value: float) -> void: rules.kill_beat_seconds = value)
	var ghosts: GhostProfile = _controller.get_ghost_profile()
	_slider("DEBUG_GHOST_RESPAWN", 0.0, 10.0, 0.1, "DEBUG_UNIT_SECONDS", ghosts.respawn_delay_seconds,
			func(value: float) -> void: ghosts.respawn_delay_seconds = value)
	for screen: Node in get_tree().current_scene.find_children("*", "RoundTransitionScreen", true, false):
		var card: MatchAnnouncementProfile = (screen as RoundTransitionScreen).announcements
		if card != null:
			_slider("DEBUG_ROUND_CARD", 0.0, 10.0, 0.1, "DEBUG_UNIT_SECONDS", card.round_card_seconds,
					func(value: float) -> void: card.round_card_seconds = value)
			break


func _build_sniper() -> void:
	var rules: MatchRules = _controller.get_rules()
	var rifle: Rifle = _controller.rifle
	_heading("DEBUG_SECTION_SNIPER")
	if rifle != null:
		_slider("DEBUG_RELOAD", maxf(rifle.get_reload_floor_seconds(), GameSettings.MIN_RELOAD_BY_TURN),
				GameSettings.MAX_RELOAD_BY_TURN, 0.05, "DEBUG_UNIT_SECONDS", rifle.reload_seconds, _set_reload)
	_slider("DEBUG_MISS_PENALTY", GameSettings.MIN_GUARD_MISS_PENALTY_SECONDS, GameSettings.MAX_GUARD_MISS_PENALTY_SECONDS,
			0.1, "DEBUG_UNIT_SECONDS", rules.guard_miss_penalty_seconds,
			func(value: float) -> void: _rule(&"guard_miss_penalty_seconds", value, &"guard_miss_penalty_seconds"))
	_slider("DEBUG_SHOT_SPEED", GameSettings.MIN_GUARD_PROJECTILE_SPEED, GameSettings.MAX_GUARD_PROJECTILE_SPEED,
			5.0, "DEBUG_UNIT_SPEED", rules.guard_projectile_speed,
			func(value: float) -> void: _rule(&"guard_projectile_speed", value, &"guard_projectile_speed"))
	var weapons: Array[WeaponProfile] = _controller.debug_weapon_profiles()
	if not weapons.is_empty():
		var set_drop: Callable = func(value: float) -> void:
			for weapon: WeaponProfile in weapons:
				weapon.projectile_gravity = value
		_slider("DEBUG_BULLET_DROP", 0.0, 60.0, 0.5, "DEBUG_UNIT_ACCEL", weapons[0].projectile_gravity, set_drop)
	_slider("DEBUG_SWAY", GameSettings.MIN_SCOPE_SWAY_DEGREES, GameSettings.MAX_SCOPE_SWAY_DEGREES, 0.05,
			"DEBUG_UNIT_DEGREES", rules.scope_sway_degrees,
			func(value: float) -> void: _rule(&"scope_sway_degrees", value, &"scope_sway_degrees"))
	_slider("DEBUG_SWAY_RATE", GameSettings.MIN_SCOPE_SWAY_HZ, GameSettings.MAX_SCOPE_SWAY_HZ, 0.01,
			"DEBUG_UNIT_HZ", rules.scope_sway_hz,
			func(value: float) -> void: _rule(&"scope_sway_hz", value, &"scope_sway_hz"))
	_slider("DEBUG_SWAY_SETTLE", GameSettings.MIN_SCOPE_SWAY_SETTLE_SECONDS, GameSettings.MAX_SCOPE_SWAY_SETTLE_SECONDS,
			0.5, "DEBUG_UNIT_SECONDS", rules.scope_sway_settle_seconds,
			func(value: float) -> void: _rule(&"scope_sway_settle_seconds", value, &"scope_sway_settle_seconds"))
	var zooms: Array[ZoomProfile] = []
	for optic: Node in get_tree().current_scene.find_children("*", "WeaponOptic", true, false):
		var zoom: ZoomProfile = (optic as WeaponOptic).profile
		if zoom != null and not zooms.has(zoom):
			zooms.append(zoom)
	if not zooms.is_empty():
		var set_zoom: Callable = func(value: float) -> void:
			for zoom: ZoomProfile in zooms:
				zoom.zoom_factor = 1.0 / value
		var set_zoom_in: Callable = func(value: float) -> void:
			for zoom: ZoomProfile in zooms:
				zoom.zoom_in_seconds = value
		_slider("DEBUG_ZOOM", 1.0, 10.0, 0.25, "DEBUG_UNIT_TIMES", 1.0 / maxf(zooms[0].zoom_factor, 0.05), set_zoom)
		_slider("DEBUG_ZOOM_IN", 0.0, 1.0, 0.01, "DEBUG_UNIT_SECONDS", zooms[0].zoom_in_seconds, set_zoom_in)
	_slider("DEBUG_GUARD_SKILL", GameSettings.MIN_GUARD_SKILL, GameSettings.MAX_GUARD_SKILL, 0.05,
			"DEBUG_UNIT_FRACTION", rules.guard_skill,
			func(value: float) -> void: _rule(&"guard_skill", value, &"guard_skill"))
	_toggle("DEBUG_HIT_MARKER", rules.guard_hit_marker,
			func(on: bool) -> void: _rule(&"guard_hit_marker", on, &"guard_hit_marker"))


func _build_runners() -> void:
	var rules: MatchRules = _controller.get_rules()
	_heading("DEBUG_SECTION_RUNNERS")
	_slider("DEBUG_RUN_SPEED", GameSettings.MIN_RUNNER_SPEED_MULTIPLIER, GameSettings.MAX_RUNNER_SPEED_MULTIPLIER,
			0.05, "DEBUG_UNIT_TIMES", rules.runner_speed_multiplier,
			_rule_then.bind(&"runner_speed_multiplier", false, _controller.debug_refresh_pace))
	_slider("DEBUG_JUMP", GameSettings.MIN_RUNNER_JUMP_MULTIPLIER, GameSettings.MAX_RUNNER_JUMP_MULTIPLIER,
			0.05, "DEBUG_UNIT_TIMES", rules.runner_jump_multiplier,
			_rule_then.bind(&"runner_jump_multiplier", false, _controller.debug_refresh_pace))
	_slider("DEBUG_POWER_COOLDOWN", 0.0, 60.0, 0.5, "DEBUG_UNIT_SECONDS", rules.ability_cooldown_seconds,
			func(value: float) -> void: rules.ability_cooldown_seconds = value)
	_slider("DEBUG_POWER_COOLDOWN_SCALE", GameSettings.MIN_ABILITY_COOLDOWN_MULTIPLIER,
			GameSettings.MAX_ABILITY_COOLDOWN_MULTIPLIER, 0.05, "DEBUG_UNIT_TIMES", rules.ability_cooldown_multiplier,
			func(value: float) -> void: _rule(&"ability_cooldown_multiplier", value, &"ability_cooldown_multiplier"))
	_slider("DEBUG_SHOVE_COOLDOWN", 0.0, 30.0, 0.1, "DEBUG_UNIT_SECONDS", rules.shove_cooldown_seconds,
			func(value: float) -> void: rules.shove_cooldown_seconds = value)
	_slider("DEBUG_LIVES", GameSettings.MIN_PRISONER_LIVES, GameSettings.MAX_PRISONER_LIVES, 1.0, "",
			rules.prisoner_lives, _rule_then.bind(&"prisoner_lives", true, _controller.debug_refresh_health))


func _build_health() -> void:
	var rules: MatchRules = _controller.get_rules()
	_heading("DEBUG_SECTION_HEALTH")
	_slider("DEBUG_GUARD_HEALTH", GameSettings.MIN_GUARD_HEALTH, GameSettings.MAX_GUARD_HEALTH, 1.0, "",
			rules.guard_health, _rule_then.bind(&"guard_health", true, _controller.debug_refresh_health))
	_slider("DEBUG_FINISHER_HEALTH", GameSettings.MIN_FINISHER_HEALTH, GameSettings.MAX_FINISHER_HEALTH, 1.0, "",
			rules.finisher_health, _rule_then.bind(&"finisher_health", true, _controller.debug_refresh_health))
	_toggle("DEBUG_FINISHER_HUNTS", rules.finisher_hunts_guard,
			func(on: bool) -> void: rules.finisher_hunts_guard = on)
	_toggle("DEBUG_GHOSTS", rules.ghost_behaviour != MatchRules.GhostBehaviour.NONE, _set_ghosts)
	var ghosts: GhostProfile = _controller.get_ghost_profile()
	var set_ghost_speed: Callable = func(value: float) -> void:
		ghosts.speed_multiplier = value
		_controller.debug_refresh_pace()
	_slider("DEBUG_GHOST_SPEED", 0.5, 4.0, 0.05, "DEBUG_UNIT_TIMES", ghosts.speed_multiplier, set_ghost_speed)


# --- Live writes ---------------------------------------------------------------

## Write a rule into the running match and, when the player's saved settings carry it, there too.
func _rule(property: StringName, value: Variant, setting: StringName) -> void:
	_controller.get_rules().set(property, value)
	if setting != &"":
		SettingsStore.instance().settings.set(setting, value)


## [method _rule] for a rule the saved settings share by name, then [param refresh] the bodies.
func _rule_then(value: float, property: StringName, whole: bool, refresh: Callable) -> void:
	_rule(property, int(value) if whole else value, property)
	refresh.call()


func _pause_clock(on: bool) -> void:
	_controller.debug_clock_paused = on
	_refresh_readout()


func _extend_clock() -> void:
	_controller.debug_extend_clock(EXTEND_SECONDS)
	_refresh_readout()


func _set_win_condition(index: int) -> void:
	_rule(&"shooter_win_condition", index, &"shooter_win_condition")
	_refresh_readout()


func _set_ghosts(on: bool) -> void:
	_controller.get_rules().ghost_behaviour = (
		MatchRules.GhostBehaviour.CATCH_AND_SWAP if on else MatchRules.GhostBehaviour.NONE
	)
	SettingsStore.instance().settings.ghosts_enabled = on


## One reload for every turn, written to the rules, the saved settings and the rifle now.
func _set_reload(value: float) -> void:
	var by_turn: PackedFloat32Array = PackedFloat32Array()
	by_turn.resize(GameSettings.RELOAD_BY_TURN_COUNT)
	by_turn.fill(value)
	_controller.get_rules().reload_seconds_by_turn = by_turn
	SettingsStore.instance().settings.reload_by_turn = by_turn.duplicate()
	_controller.debug_refresh_reload()


## Run a phase action and hand the match back.
func _act(action: Callable) -> void:
	action.call()
	close()


func _refresh_readout() -> void:
	if _readout == null or _controller == null:
		return
	var seat: MatchParticipant = _controller.get_seat_participant()
	var clock: float = _controller.get_hold_remaining_seconds()
	_readout.text = tr("DEBUG_READOUT").format({
		"phase": tr(String(PHASE_KEYS.get(_controller.get_phase_name(), "DEBUG_PHASE_IDLE"))),
		"round": _controller.get_round_number(),
		"seat": seat.display_name if seat != null else "-",
		"clock": (tr("DEBUG_UNIT_SECONDS") % String.num(clock, 1)) if clock > 0.0 else "-",
		"paused": tr("DEBUG_CLOCK_PAUSED") if _controller.debug_clock_paused else "",
	})


# --- Widgets -------------------------------------------------------------------

func _heading(key: String) -> void:
	var label: Label = Label.new()
	label.theme_type_variation = &"Heading"
	label.text = key
	_body.add_child(label)


func _note(text: String) -> void:
	var label: Label = Label.new()
	label.theme_type_variation = &"Note"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	_body.add_child(label)


func _row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_body.add_child(row)
	return row


func _button(parent: Control, key: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = key
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(handler)
	parent.add_child(button)
	if _first == null:
		_first = button
	return button


func _toggle(key: String, on: bool, handler: Callable, parent: Control = null) -> void:
	var check: CheckBox = CheckBox.new()
	check.text = key
	check.button_pressed = on
	check.toggled.connect(handler)
	(parent if parent != null else _body).add_child(check)


func _choice(key: String, titles: PackedStringArray, selected: int, handler: Callable) -> void:
	var row: HBoxContainer = _row()
	row.add_child(_row_label(key))
	var option: OptionButton = OptionButton.new()
	for title: String in titles:
		option.add_item(title)
	option.selected = selected
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(handler)
	row.add_child(option)


## A labelled slider whose readout shows the value in [param unit], a format key ("" for a count).
func _slider(key: String, low: float, high: float, step: float, unit: String, value: float,
		handler: Callable) -> void:
	var row: HBoxContainer = _row()
	row.add_child(_row_label(key))
	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout: Label = Label.new()
	readout.custom_minimum_size = Vector2(120.0, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = _format(unit, step, slider.value)
	row.add_child(readout)
	slider.value_changed.connect(func(changed: float) -> void:
		readout.text = _format(unit, step, changed)
		handler.call(changed))


func _row_label(key: String) -> Label:
	var label: Label = Label.new()
	label.text = key
	label.custom_minimum_size = Vector2(300.0, 0.0)
	return label


func _format(unit: String, step: float, value: float) -> String:
	var decimals: int = 0 if step >= 1.0 else (1 if step >= 0.1 else 2)
	var number: String = String.num(value, decimals)
	if unit == "DEBUG_UNIT_SPEED" and value <= 0.0:
		return tr("DEBUG_SPEED_WEAPON")
	return number if unit.is_empty() else tr(unit) % number


func _open_rules() -> void:
	_frame.visible = false
	_rules_screen.refresh()
	_rules_screen.visible = true
	_rules_screen.focus_start()


func _close_rules() -> void:
	_rules_screen.visible = false
	SettingsStore.instance().save_to_disk()
	_frame.visible = true
	if _first != null:
		_first.grab_focus()


func _hotkey_text() -> String:
	var lines: PackedStringArray = []
	for row: Array in HOTKEYS:
		var key: String = "-"
		if InputMap.has_action(row[0]) and not InputMap.action_get_events(row[0]).is_empty():
			key = InputMap.action_get_events(row[0])[0].as_text().trim_suffix(" (Physical)")
		lines.append("%s    %s" % [key, tr(row[1])])
	return "\n".join(lines)
