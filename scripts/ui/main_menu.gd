class_name MainMenu
extends Control

## The game's entry point: Play, Settings, Quit.
##
## Built in code, in plain default-themed controls, for the same reason
## [SettingsScreen] is: the project is a greybox with no art direction, and a
## [code].tscn[/code] full of hand-placed [Button]s is a diff nobody can read.
## When there is a visual identity, this file is where the theme goes -- or it
## is replaced wholesale by a designed scene calling the same three methods.
##
## [b]It reuses the settings screen, it does not have one of its own.[/b]
## [method _build] instantiates [code]scenes/ui/settings_screen.tscn[/code],
## exactly as [PauseMenu] does, so the screen the player sees from the menu and
## the screen they see mid-match are one scene talking to one [SettingsStore].
##
## [b]Scenes are named by path, never by [PackedScene].[/b] The menu starts the
## match and [PauseMenu] comes back to the menu, so exporting a [PackedScene] at
## either end would put [code]main_menu.tscn -> match.tscn -> pause_menu.tscn ->
## main_menu.tscn[/code] in the resource graph -- a load-time cycle. A [String]
## path resolved by [method SceneTree.change_scene_to_file] has no such edge.
##
## [b]It runs while paused.[/b] [member Node.process_mode] is
## [constant Node.PROCESS_MODE_ALWAYS]. Nothing here should ever be loaded into
## a paused tree -- [method PauseMenu.return_to_main_menu] unpauses first -- but
## a menu whose buttons are dead is indistinguishable from a hung game, and this
## is one line.

## Emitted immediately before the match scene is requested.
signal play_requested()

## Emitted when the player chooses Quit, immediately before the tree quits, for
## anything that must flush first.
signal quit_requested()

## The settings screen, loaded rather than constructed.
##
## Its layout lives in the scene, so [code]SettingsScreen.new()[/code] would
## hand back a bare [Control] with none of its controls in it.
const SETTINGS_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/settings_screen.tscn")


## The scene [method play] switches to. A path rather than a [PackedScene]; see
## the note on cycles above.
@export_file("*.tscn") var match_scene_path: String = "res://scenes/match/match.tscn"

## The action that backs out of the settings screen. Matches
## [member PauseMenu.toggle_action] so Escape means the same thing in both.
@export var back_action: StringName = &"ui_cancel"

var _store: SettingsStore = null
var _main_panel: PanelContainer = null
var _settings_screen: SettingsScreen = null
var _play_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_store = SettingsStore.instance()
	# A menu always wants a cursor. Coming back from a match the mouse has
	# already been released by PauseMenu, but a menu that depends on the scene
	# before it having been polite is a menu that one day opens with no pointer.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_show_main()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(back_action):
		return
	# A rebind in flight owns every key, Escape included.
	if _settings_screen.is_capturing_input():
		return
	if not _settings_screen.visible:
		return
	get_viewport().set_input_as_handled()
	_close_settings()


# --- Actions ------------------------------------------------------------------

## Write the settings file and switch to the match.
##
## The settings are saved first so the values the player just chose are on disk
## before a scene change; the in-process [SettingsStore] is a static singleton
## and survives the change either way, but a crash during the match must not
## cost the player their sensitivity.
func play() -> void:
	_settings_screen.visible = false
	_store.save_to_disk()
	play_requested.emit()
	var error: Error = get_tree().change_scene_to_file(match_scene_path)
	if error != OK:
		push_error("MainMenu could not load %s: %s" % [match_scene_path, error_string(error)])


## Show the settings screen.
func open_settings() -> void:
	_main_panel.visible = false
	_settings_screen.refresh()
	_settings_screen.visible = true


## Write the settings file and exit.
func quit() -> void:
	quit_requested.emit()
	_store.save_to_disk()
	get_tree().quit()


## True while the settings screen is up.
func is_showing_settings() -> bool:
	return _settings_screen.visible


# --- Construction -------------------------------------------------------------

func _build() -> void:
	_main_panel = PanelContainer.new()
	_main_panel.name = "MainPanel"
	_main_panel.set_anchors_preset(Control.PRESET_CENTER)
	_main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_main_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 24)
	margin.add_theme_constant_override(&"margin_right", 24)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	_main_panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "PANOPTICON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_play_button = _add_button(column, "Play", play)
	_add_button(column, "Settings", open_settings)
	_add_button(column, "Quit", quit)

	_settings_screen = SETTINGS_SCREEN_SCENE.instantiate()
	_settings_screen.name = "SettingsScreen"
	_settings_screen.visible = false
	_settings_screen.closed.connect(_close_settings)
	add_child(_settings_screen)


func _add_button(parent: Container, text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.name = text
	button.text = text
	button.custom_minimum_size = Vector2(220.0, 0.0)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


# --- Navigation ---------------------------------------------------------------

func _show_main() -> void:
	_settings_screen.visible = false
	_main_panel.visible = true
	if _play_button != null:
		_play_button.grab_focus()


## Called both by the screen's Back button (which has already saved) and by
## Escape (which has not), so it saves defensively.
func _close_settings() -> void:
	if not _settings_screen.visible:
		return
	_settings_screen.visible = false
	_store.save_to_disk()
	_show_main()
