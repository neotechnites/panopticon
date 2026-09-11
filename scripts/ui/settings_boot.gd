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

## The [MatchRules] the scene's match is about to be played under, for the
## preferences that are rules rather than presentation -- today, whether ghosts
## are on. Optional; leave it unset in scenes that start no match.
##
## Point it at the SAME resource the [MatchController] in the scene exports, not
## at a second copy: Godot hands back one cached object per resource path, so
## naming res://resources/rules/default_match_rules.tres in both places is one
## object and the setting lands on the rules the match actually runs. Point it
## anywhere else and the toggle appears to save and does nothing -- the identical
## trap [member movement_profile] carries, and the reason both are named in the
## scene rather than looked up here.
@export var match_rules: MatchRules


func _enter_tree() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.applied.connect(_on_settings_applied)
	_on_settings_applied()


func _on_settings_applied() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.apply_to_movement_profile(movement_profile)
	store.settings.apply_to_camera(camera)
	var hosted: MatchRules = _host_rules()
	if hosted != null:
		NetCodec.copy_rules(hosted, match_rules)
	else:
		store.settings.apply_to_match_rules(match_rules)


## The host's rules when this machine is a client in a networked lobby, else null.
func _host_rules() -> MatchRules:
	if match_rules == null or not is_inside_tree():
		return null
	var session: NetSession = get_tree().root.get_node_or_null(^"NetSession") as NetSession
	if session == null or not session.is_established() or session.is_authority() or session.lobby == null:
		return null
	return session.lobby.get_rules()
