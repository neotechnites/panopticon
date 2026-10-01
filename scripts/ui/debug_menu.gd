class_name DebugMenu
extends Control

## Developer tools kept out of the player's menus: quick match, rules and balance, test scenes, hotkeys.
## Opened by F1 or backtick from the main menu or in play, or a Debug button in debug builds.

## Emitted when Back or Escape leaves the menu.
signal closed()
## Emitted when Quick match is chosen; the main menu owns the setup screen.
signal quick_match_requested()

## Scenes with no way back of their own get one of these on launch.
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/pause_menu.tscn")

## Test scenes by button node name. Paths, not PackedScenes, so nothing loads until asked.
const SCENES: Dictionary = {
	&"Playground": "res://characters/player/movement_playground.tscn",
	&"HubTest": "res://hub/hub_test.tscn",
	&"TowerInterior": "res://tower/tower_interior_test.tscn",
	&"ShirtLineup": "res://tools/capture/shirt_lineup.tscn",
}

## In-match debug actions and the key naming each.
const HOTKEYS: Array[Array] = [
	[PlayerActions.TURBO, "MENU_DEBUG_KEY_TURBO"],
	[PlayerActions.GODMODE, "MENU_DEBUG_KEY_GODMODE"],
	[PlayerActions.HUD_TOGGLE, "MENU_DEBUG_KEY_HUD"],
	[PlayerActions.FREE_CAMERA, "MENU_DEBUG_KEY_FREE_CAMERA"],
	[PlayerActions.FREECAM_UP, "MENU_DEBUG_KEY_FREECAM_UP"],
	[PlayerActions.FREECAM_DOWN, "MENU_DEBUG_KEY_FREECAM_DOWN"],
]

## Set by the pause menu: match-start rules are labelled "next match", Quick match is hidden.
var in_match: bool = false

@onready var _frame: Control = $Frame
@onready var _quick_match: Button = %QuickMatch
@onready var _rules: Button = %Rules
@onready var _full_rules: CheckBox = %FullRulesCheck
@onready var _hotkeys: Label = %Hotkeys
@onready var _back: Button = %Back
@onready var _rules_screen: SettingsScreen = %RulesScreen


func _ready() -> void:
	_quick_match.pressed.connect(func() -> void: quick_match_requested.emit())
	_rules.pressed.connect(_open_rules)
	_full_rules.button_pressed = MatchSetupScreen.show_all_rules_everywhere
	_full_rules.toggled.connect(func(on: bool) -> void: MatchSetupScreen.show_all_rules_everywhere = on)
	_back.pressed.connect(close)
	_rules_screen.closed.connect(_close_rules)
	for button_name: StringName in SCENES:
		var button: Button = get_node("%" + String(button_name)) as Button
		button.pressed.connect(launch.bind(SCENES[button_name]))
	_rules_screen.visible = false


## Show the menu with focus on its first button.
func open() -> void:
	PlayerActions.ensure_registered()
	_hotkeys.text = _hotkey_text()
	visible = true
	_rules_screen.visible = false
	_frame.visible = true
	_quick_match.visible = not in_match
	_rules.text = tr("MENU_DEBUG_RULES_NEXT") if in_match else tr("MENU_DEBUG_RULES")
	(_quick_match if not in_match else _rules).grab_focus()


## Back one step: out of the rules screen, else out of the menu.
func back() -> void:
	if _rules_screen.is_capturing_input():
		return
	if _rules_screen.visible:
		_rules_screen.close()
	else:
		close()


func close() -> void:
	visible = false
	closed.emit()


## Switch to a test scene, adding a pause menu when it has none so Leave Match comes back here.
func launch(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("DebugMenu could not load %s" % path)
		return
	SettingsStore.instance().save_to_disk()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var scene: Node = packed.instantiate()
	if scene.find_children("*", "PauseMenu", true, false).is_empty():
		scene.add_child(PAUSE_MENU_SCENE.instantiate())
	get_tree().change_scene_to_node(scene)


func _open_rules() -> void:
	_frame.visible = false
	_rules_screen.refresh()
	_rules_screen.visible = true
	_rules_screen.focus_start()


func _close_rules() -> void:
	_rules_screen.visible = false
	SettingsStore.instance().save_to_disk()
	_frame.visible = true
	_rules.grab_focus()


func _hotkey_text() -> String:
	var lines: PackedStringArray = []
	for row: Array in HOTKEYS:
		var key: String = "-"
		if InputMap.has_action(row[0]) and not InputMap.action_get_events(row[0]).is_empty():
			key = InputMap.action_get_events(row[0])[0].as_text().trim_suffix(" (Physical)")
		lines.append("%s    %s" % [key, tr(row[1])])
	return "\n".join(lines)
