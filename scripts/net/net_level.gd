class_name NetLevel
extends Node

## Loads the scene the host's lobby names on every new epoch, on every machine (Quake's
## gamestate): a launch loads the match, the host's return to the hub brings a match back.

const MATCH_SCENE_PATH: String = "res://match/match.tscn"
const HUB_SCENE_PATH: String = "res://hub/hub.tscn"

@export var session: NetSession

## Off for a harness or test that stands its own scenes up instead of changing the tree's.
@export var follows: bool = true

var _epoch: int = 0


func _ready() -> void:
	if session != null and session.lobby != null:
		session.lobby.roster_changed.connect(_on_roster_changed)


func _on_roster_changed() -> void:
	var lobby: NetLobby = session.lobby
	if lobby.get_epoch() == _epoch:
		return
	_epoch = lobby.get_epoch()
	var path: String = _scene_for(lobby.get_phase())
	if not follows or path.is_empty():
		return
	_load.call_deferred(path)


## The scene a new epoch in [param phase] puts this machine in, or empty to stay put.
func _scene_for(phase: NetLobby.Phase) -> String:
	match phase:
		NetLobby.Phase.LAUNCHING, NetLobby.Phase.IN_MATCH, NetLobby.Phase.POST_MATCH:
			return MATCH_SCENE_PATH
		NetLobby.Phase.GATHERING:
			# Back from a match; a lobby screen that opened the session keeps it until it leaves.
			return HUB_SCENE_PATH if _current_path() == MATCH_SCENE_PATH else ""
	return ""


func _current_path() -> String:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	return scene.scene_file_path if scene != null else ""


func _load(path: String) -> void:
	if not is_inside_tree() or _current_path() == path:
		return
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("NetLevel could not load %s: %s" % [path, error_string(error)])
