class_name HostPlaceholderScreen
extends Control

## Stands in for Host until the net lobby UI exists. Back closes it.

signal closed()

@onready var _back_button: Button = %Back


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: closed.emit())


## Focus Back, the only control on the screen.
func focus_start() -> void:
	_back_button.grab_focus()
