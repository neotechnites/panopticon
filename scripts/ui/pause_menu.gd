class_name PauseMenu
extends CanvasLayer

## Escape, and everything behind it: pause, mouse release, settings, leaving
## the match. Resume / Settings / Leave Match -- quitting the app is a main
## menu decision, not one made mid-match.
##
## Drop it into any scene as a child of the root. It finds nothing, is wired to
## nothing, and exports the two things a scene might reasonably want to hand it.
##
## [b]It owns Escape.[/b] [HumanIntentSource] also watches
## [code]ui_cancel[/code], to drop the captured mouse, and two nodes racing for
## the same key is how a pause menu ends up opening with the mouse still
## captured -- or not opening at all. So this node listens in
## [method Node._input], which runs before [method Node._unhandled_input], and
## marks the event handled. The player's own handler is then never reached and
## the two cannot disagree. Nothing in [code]scripts/player[/code] had to change
## for that to be true.
##
## [b]The mouse is restored, not assumed.[/b] Opening records
## [member Input.mouse_mode] and forces it visible; closing puts back exactly
## what was there. A menu scene that was already showing a cursor keeps showing
## one, and a match that had the mouse captured gets it captured again --
## without this file knowing which case it is in.
##
## [b]Leaving for the menu is a teardown, not a scene change.[/b]
## [method return_to_main_menu] unpauses the tree and frees the mouse
## [i]before[/i] asking for the new scene. Both matter and both are easy to
## forget: a scene loaded into a paused tree arrives with every node's
## [member Node.process_mode] inherited from a paused root and its buttons dead,
## and a mouse left in [constant Input.MOUSE_MODE_CAPTURED] leaves the player
## with no cursor to click them with. Together they are the classic frozen menu.
## The match itself is freed by [method SceneTree.change_scene_to_file], which
## releases the whole previous scene -- this node included -- at the end of the
## frame.
##
## [b]Pausing does the rest of the work.[/b] [member Node.process_mode] is
## [constant Node.PROCESS_MODE_ALWAYS] here and inherited everywhere else, so
## while [member SceneTree.paused] is true the player, the weapon and the bots
## stop processing input entirely. That is why clicking Resume cannot also fire
## the rifle, and why [HumanIntentSource]'s "click to re-capture the mouse" does
## not fight the menu: it is not running.

## Emitted when the menu opens and when it closes.
signal opened()
signal closed()

## Emitted when the player chooses Main Menu, after the tree is unpaused and the
## mouse released but before the scene change is requested.
signal main_menu_requested()

## The settings screen, loaded rather than constructed.
##
## Its layout lives in the scene, so [code]SettingsScreen.new()[/code] would
## hand back a bare [Control] with none of its controls in it.
const SETTINGS_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/settings_screen.tscn")


## The action that toggles the menu. Left as an export so a scene can move it
## without touching this file.
@export var toggle_action: StringName = &"ui_cancel"

## Start with the menu up. For a scene that opens on a menu rather than in play.
@export var open_on_ready: bool = false

## Optional. When set, the saved mouse sensitivity and invert-Y are written into
## this profile every time settings are applied.
@export var movement_profile: MovementProfile

## Optional. When set, the saved field of view is written into this camera.
@export var camera: Camera3D

## The scene [method return_to_main_menu] switches to. A path rather than a
## [PackedScene] on purpose: the menu names the match and the match carries this
## node, so a [PackedScene] export here would close the resource graph into a
## cycle -- main menu, match, pause menu, main menu. A path has no such edge and
## is resolved only when the player asks.
@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/ui/main_menu.tscn"

var _store: SettingsStore = null
var _root: Control = null
var _main_panel: PanelContainer = null
var _settings_screen: SettingsScreen = null
var _resume_button: Button = null

var _is_open: bool = false

## Mouse mode in force before the menu opened, restored on close.
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	_store = SettingsStore.instance()
	_store.applied.connect(_on_settings_applied)
	_build()
	_on_settings_applied()
	if open_on_ready:
		open()
	else:
		_apply_visibility(false)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(toggle_action):
		return
	# A rebind in flight owns every key, Escape included -- it uses it to
	# cancel. Stand back rather than closing the screen out from under it.
	if _settings_screen != null and _settings_screen.is_capturing_input():
		return

	get_viewport().set_input_as_handled()

	if not _is_open:
		open()
	elif _settings_screen != null and _settings_screen.visible:
		_close_settings()
	else:
		close()


## True while the menu is up.
func is_open() -> bool:
	return _is_open


## Pause, release the mouse and show the menu.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _is_networked():
		get_tree().paused = true
	_apply_visibility(true)
	_show_main()
	opened.emit()


## Unpause, restore the mouse mode and hide the menu.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if _settings_screen != null and _settings_screen.visible:
		# Leaving by Escape from the settings screen must still write the file.
		_settings_screen.close()
	_apply_visibility(false)
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before_open
	closed.emit()


## Open the menu if it is closed, close it if it is open.
## True inside a networked match, where the world keeps running under the menu.
func _is_networked() -> bool:
	var session: NetSession = get_tree().root.get_node_or_null(^"NetSession") as NetSession
	return session != null and session.is_established()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


# --- Construction -------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_right = 0.0
	_root.offset_bottom = 0.0
	# STOP, so a click on the menu's empty space does not fall through to the
	# game underneath.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_main_panel = PanelContainer.new()
	_main_panel.set_anchors_preset(Control.PRESET_CENTER)
	_main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_main_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 24)
	margin.add_theme_constant_override(&"margin_right", 24)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	_main_panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_resume_button = _add_button(column, "Resume", close)
	_add_button(column, "Settings", _open_settings)
	_add_button(column, "Leave Match", return_to_main_menu)

	_settings_screen = SETTINGS_SCREEN_SCENE.instantiate()
	_settings_screen.visible = false
	_settings_screen.closed.connect(_close_settings)
	_root.add_child(_settings_screen)


func _add_button(parent: Container, text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220.0, 0.0)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


# --- Navigation ---------------------------------------------------------------

func _show_main() -> void:
	if _settings_screen != null:
		_settings_screen.visible = false
	_main_panel.visible = true
	if _resume_button != null:
		_resume_button.grab_focus()


func _open_settings() -> void:
	_main_panel.visible = false
	_settings_screen.refresh()
	_settings_screen.visible = true
	_settings_screen.focus_start()


## Called both by the screen's Back button (which has already saved) and by
## Escape (which has not), so it saves defensively; writing the same file twice
## is cheap and losing a setting is not.
func _close_settings() -> void:
	if not _settings_screen.visible:
		return
	_settings_screen.visible = false
	_store.save_to_disk()
	_show_main()


## Tear the match down and go back to the main menu.
##
## The order is the whole point:
## [codeblock]
##   1. write the settings file   -- the match is about to stop existing
##   2. unpause the tree          -- or the menu loads into a paused tree
##   3. release the mouse         -- or the menu loads with no cursor
##   4. change scene              -- frees the match at the end of the frame
## [/codeblock]
## The mouse is forced visible rather than restored to
## [member _mouse_mode_before_open], because that value is whatever the match
## was using -- normally [constant Input.MOUSE_MODE_CAPTURED] -- and a menu is
## not a match. [method close] is not reused for the same reason.
func return_to_main_menu() -> void:
	if main_menu_scene_path.is_empty():
		push_error("PauseMenu has no main_menu_scene_path; staying in the match.")
		return

	if _settings_screen != null and _settings_screen.visible:
		# Leaving by this route must still write the file.
		_settings_screen.close()
		_settings_screen.visible = false
	_store.save_to_disk()

	_is_open = false
	_apply_visibility(false)

	var tree: SceneTree = get_tree()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	closed.emit()
	main_menu_requested.emit()

	var error: Error = tree.change_scene_to_file(main_menu_scene_path)
	if error != OK:
		# The tree is already unpaused and the mouse already free, so the player
		# is left standing in the match with a working cursor rather than in a
		# half-torn-down state.
		push_error("PauseMenu could not load %s: %s" % [main_menu_scene_path, error_string(error)])


func _apply_visibility(visible_now: bool) -> void:
	if _root != null:
		_root.visible = visible_now


## Settings that need a target node rather than a server -- look sensitivity and
## field of view -- are pushed here, whenever anything applies settings.
func _on_settings_applied() -> void:
	_store.settings.apply_to_movement_profile(movement_profile)
	_store.settings.apply_to_camera(camera)
