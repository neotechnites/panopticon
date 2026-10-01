class_name TestScenesMenu
extends Control

## Launchers for the standalone test scenes. Main menu only, debug builds only.

## Emitted when Back or Escape leaves the menu.
signal closed()

## Scenes with no way back of their own get one of these on launch.
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/pause_menu.tscn")

## Label key to scene path. Paths, not PackedScenes, so nothing loads until asked.
const SCENES: Array[Array] = [
	["MENU_TEST_PLAYGROUND", "res://characters/player/movement_playground.tscn"],
	["MENU_TEST_HUB", "res://hub/hub_test.tscn"],
	["MENU_TEST_TOWER_INTERIOR", "res://tower/tower_interior_test.tscn"],
	["MENU_TEST_SHIRT_LINEUP", "res://tools/capture/shirt_lineup.tscn"],
]

@onready var _list: VBoxContainer = %List
@onready var _back: Button = %Back


func _ready() -> void:
	for row: Array in SCENES:
		var button: Button = Button.new()
		button.text = row[0]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(launch.bind(row[1]))
		_list.add_child(button)
	_back.pressed.connect(close)


## Show the menu with focus on its first scene.
func open() -> void:
	visible = true
	(_list.get_child(0) as Button).grab_focus()


func close() -> void:
	visible = false
	closed.emit()


## Switch to a test scene, adding a pause menu when it has none so Leave Match comes back.
func launch(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("TestScenesMenu could not load %s" % path)
		return
	SettingsStore.instance().save_to_disk()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var scene: Node = packed.instantiate()
	if scene.find_children("*", "PauseMenu", true, false).is_empty():
		scene.add_child(PAUSE_MENU_SCENE.instantiate())
	get_tree().change_scene_to_node(scene)
