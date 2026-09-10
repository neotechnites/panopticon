class_name PauseMenu
extends CanvasLayer

## Escape, and everything behind it: pause, mouse release, settings, quit.
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
## [b]Pausing does the rest of the work.[/b] [member Node.process_mode] is
## [constant Node.PROCESS_MODE_ALWAYS] here and inherited everywhere else, so
## while [member SceneTree.paused] is true the player, the weapon and the bots
## stop processing input entirely. That is why clicking Resume cannot also fire
## the rifle, and why [HumanIntentSource]'s "click to re-capture the mouse" does
## not fight the menu: it is not running.

## Emitted when the menu opens and when it closes.
signal opened()
signal closed()

## Emitted when the player chooses Quit, immediately before the tree quits, for
## anything that must flush first.
signal quit_requested()

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
	_add_button(column, "Quit", _quit)

	_settings_screen = SettingsScreen.new()
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


## Called both by the screen's Back button (which has already saved) and by
## Escape (which has not), so it saves defensively; writing the same file twice
## is cheap and losing a setting is not.
func _close_settings() -> void:
	if not _settings_screen.visible:
		return
	_settings_screen.visible = false
	_store.save_to_disk()
	_show_main()


func _quit() -> void:
	quit_requested.emit()
	_store.save_to_disk()
	get_tree().quit()


func _apply_visibility(visible_now: bool) -> void:
	if _root != null:
		_root.visible = visible_now


## Settings that need a target node rather than a server -- look sensitivity and
## field of view -- are pushed here, whenever anything applies settings.
func _on_settings_applied() -> void:
	_store.settings.apply_to_movement_profile(movement_profile)
	_store.settings.apply_to_camera(camera)
