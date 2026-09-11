class_name MainMenu
extends Control

## The game's entry point: Play, Settings, Quit.
##
## [b]The layout is in the scene.[/b] This file used to build every control in
## code, on the theory that a [code].tscn[/code] full of default-themed buttons
## was an unreadable diff. That theory was retired on the settings screen for
## good reasons -- nothing was laid out where a person could see it, and every
## size was a number guessed twice -- and this file now follows it: structure in
## [code]scenes/ui/main_menu.tscn[/code], binding and navigation here.
##
## [b]It owns four views and shows exactly one.[/b]
## [codeblock]
##   MainPanel          Play / Multiplayer / Settings / Quit
##   MatchSetupScreen   Play  -> the rules of the round, then Start
##   MultiplayerScreen  Multiplayer -> host/join lobby
##   SettingsScreen     Settings -> the same screen the pause menu opens
## [/codeblock]
## Play does NOT start a match. It opens [MatchSetupScreen], whose Start button
## calls [method play]; that is the whole reason the setup screen exists, and it
## is why [signal MatchSetupScreen.start_requested] is connected to a method on
## this node rather than the setup screen changing scene itself.
##
## [b]Scenes are named by path, never by [PackedScene].[/b] The menu starts the
## match and [PauseMenu] comes back to the menu, so exporting a [PackedScene] at
## either end would put [code]main_menu.tscn -> match.tscn -> pause_menu.tscn ->
## main_menu.tscn[/code] in the resource graph -- a load-time cycle. A [String]
## path resolved by [method SceneTree.change_scene_to_file] has no such edge. The
## two screens instanced in the scene file are safe by the same test: neither of
## them names the main menu.
##
## [b]It runs while paused.[/b] [member Node.process_mode] is
## [constant Node.PROCESS_MODE_ALWAYS]. Nothing here should ever be loaded into a
## paused tree -- [method PauseMenu.return_to_main_menu] unpauses first -- but a
## menu whose buttons are dead is indistinguishable from a hung game.

## Emitted immediately before the match scene is requested.
signal play_requested()

## Emitted when the player chooses Quit, immediately before the tree quits, for
## anything that must flush first.
signal quit_requested()

## The scene [method play] switches to. A path rather than a [PackedScene]; see
## the note on cycles above.
@export_file("*.tscn") var match_scene_path: String = "res://scenes/match/match.tscn"

## The action that backs out of a screen. Matches [member PauseMenu.toggle_action]
## so Escape means the same thing everywhere.
@export var back_action: StringName = &"ui_cancel"

@onready var _main_panel: Control = %MenuList
@onready var _play_button: Button = %Play
@onready var _multiplayer_button: Button = %Multiplayer
@onready var _settings_button: Button = %Settings
@onready var _quit_button: Button = %Quit
@onready var _setup_screen: MatchSetupScreen = %MatchSetupScreen
@onready var _multiplayer_screen: MultiplayerScreen = %MultiplayerScreen
@onready var _settings_screen: SettingsScreen = %SettingsScreen

var _store: SettingsStore = null


func _ready() -> void:
	# Restated even though the scene sets it, because a menu that silently stops
	# responding when somebody clears the flag in the inspector is a bug nobody
	# would think to look for here.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_store = SettingsStore.instance()
	# A menu always wants a cursor. Coming back from a match the mouse has
	# already been released by PauseMenu, but a menu that depends on the scene
	# before it having been polite is a menu that one day opens with no pointer.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_play_button.pressed.connect(open_match_setup)
	_multiplayer_button.pressed.connect(open_multiplayer)
	_settings_button.pressed.connect(open_settings)
	_quit_button.pressed.connect(quit)

	_setup_screen.start_requested.connect(play)
	_setup_screen.closed.connect(_close_match_setup)
	_multiplayer_screen.closed.connect(_close_multiplayer)
	_settings_screen.closed.connect(_close_settings)

	_show_main()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(back_action):
		return
	# A rebind in flight owns every key, Escape included.
	if _settings_screen.is_capturing_input():
		return
	if _settings_screen.visible:
		get_viewport().set_input_as_handled()
		_close_settings()
		return
	if _setup_screen.visible:
		get_viewport().set_input_as_handled()
		_close_match_setup()
		return
	if _multiplayer_screen.visible:
		get_viewport().set_input_as_handled()
		_close_multiplayer()


# --- Actions ------------------------------------------------------------------

## Show the match setup screen. What the Play button does.
func open_match_setup() -> void:
	_main_panel.visible = false
	_settings_screen.visible = false
	_multiplayer_screen.visible = false
	_setup_screen.refresh()
	_setup_screen.visible = true
	_setup_screen.focus_start()


## Write the settings file and switch to the match. Called by
## [signal MatchSetupScreen.start_requested], not by a button on this node.
##
## The settings are saved first so the rules the player just chose are on disk
## before a scene change; the in-process [SettingsStore] is a static singleton
## and survives the change either way, but a crash during the match must not cost
## the player their choices. [MatchSetupScreen.start] has already written the
## file; saving again is idempotent and costs one write, and it means this method
## is correct however it is reached.
func play() -> void:
	_setup_screen.visible = false
	_settings_screen.visible = false
	_store.save_to_disk()
	play_requested.emit()
	var error: Error = get_tree().change_scene_to_file(match_scene_path)
	if error != OK:
		push_error("MainMenu could not load %s: %s" % [match_scene_path, error_string(error)])


## Show the settings screen.
func open_settings() -> void:
	_main_panel.visible = false
	_setup_screen.visible = false
	_multiplayer_screen.visible = false
	_settings_screen.refresh()
	_settings_screen.visible = true


## Show the multiplayer screen. What the Multiplayer button does.
func open_multiplayer() -> void:
	_main_panel.visible = false
	_setup_screen.visible = false
	_settings_screen.visible = false
	_multiplayer_screen.refresh()
	_multiplayer_screen.visible = true
	_multiplayer_screen.focus_start()


## Write the settings file and exit.
func quit() -> void:
	quit_requested.emit()
	_store.save_to_disk()
	get_tree().quit()


## True while the settings screen is up.
func is_showing_settings() -> bool:
	return _settings_screen.visible


## True while the match setup screen is up.
func is_showing_match_setup() -> bool:
	return _setup_screen.visible


## True while the multiplayer screen is up.
func is_showing_multiplayer() -> bool:
	return _multiplayer_screen.visible


# --- Navigation ---------------------------------------------------------------

func _show_main() -> void:
	_setup_screen.visible = false
	_settings_screen.visible = false
	_multiplayer_screen.visible = false
	_main_panel.visible = true
	_play_button.grab_focus()


## Called both by the screen's Back button (which has already saved) and by
## Escape (which has not), so it saves defensively.
func _close_settings() -> void:
	if not _settings_screen.visible:
		return
	_settings_screen.visible = false
	_store.save_to_disk()
	_show_main()


## Same contract as [method _close_settings]: reached from the Back button and
## from Escape, and saves defensively because only one of those has.
func _close_match_setup() -> void:
	if not _setup_screen.visible:
		return
	_setup_screen.visible = false
	_store.save_to_disk()
	_show_main()


## No settings to save; the placeholder has none.
func _close_multiplayer() -> void:
	if not _multiplayer_screen.visible:
		return
	_multiplayer_screen.leave()
	_multiplayer_screen.visible = false
	_show_main()
