class_name SettingsBoot
extends Node

## Applies the saved settings as early as a node can.
##
## The store loads lazily on first use, which is fine for a menu but too late
## for a scene that starts a match immediately: without this, the first frame
## runs at the default volume and the default window mode until something asks
## for settings. Drop this node at the top of a scene -- or register the script
## as an autoload -- and the file is read and applied before anything else is
## ready.
##
## It is deliberately dependency-free so it works in either position.

## A [MovementProfile] to write mouse sensitivity and invert-Y into. Optional;
## leave it unset in scenes that have no player.
@export var movement_profile: MovementProfile

## The player's camera, for the saved field of view. Optional.
@export var camera: Camera3D


func _enter_tree() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.applied.connect(_on_settings_applied)
	_on_settings_applied()


func _on_settings_applied() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.apply_to_movement_profile(movement_profile)
	store.settings.apply_to_camera(camera)
