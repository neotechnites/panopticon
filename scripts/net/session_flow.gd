class_name SessionFlow
extends Node

## The one owner of this machine's scene changes and session end: each epoch's scene is loaded, put up,
## bound, warmed and acknowledged (LOADING to STANDING); the UI calls intents here and changes no scene.

## A new epoch wants [param path] standing on this machine; empty keeps the scene already up.
## Emitted whether or not this node places the scene itself (see [member follows]).
signal scene_wanted(path: String)

## The host was lost under a standing match: the match's result screen says so and stays up.
signal host_lost()

const MATCH_SCENE_PATH: String = "res://match/match.tscn"
const HUB_SCENE_PATH: String = "res://hub/hub.tscn"
const MENU_SCENE_PATH: String = "res://ui/main_menu.tscn"
## The reason a session that failed under this machine's hub or load is shown with on the menu.
const HOST_LOST_REASON: StringName = &"RESULT_HOST_LOST_DETAIL"

@export var session: NetSession

## Off for a harness or test that stands its own scenes: [signal scene_wanted] still says which.
@export var follows: bool = true

## The scene a gathering lobby stands in. Empty keeps the screen that opened the session.
@export_file("*.tscn") var hub_scene_path: String = HUB_SCENE_PATH
@export_file("*.tscn") var match_scene_path: String = MATCH_SCENE_PATH
@export_file("*.tscn") var menu_scene_path: String = MENU_SCENE_PATH

## The epoch this machine is loading or standing in, 0 when none.
var _epoch: int = 0
var _standing: bool = false
## The epoch's scene is a match (else the hub).
var _in_match: bool = false
## A session scene has replaced the screen that started the session; ending must take it down.
var _away: bool = false
## The scene the current epoch wants.
var _wanted_path: String = ""
var _warmup: SceneWarmup = null
## Why the last session ended under a session scene; the menu takes it. Empty for a chosen leave.
var _end_reason: StringName = &""


func _ready() -> void:
	if session == null or session.lobby == null:
		push_error("SessionFlow has no session and lobby; it cannot follow one.")
		return
	session.lobby.roster_changed.connect(_on_roster_changed)
	session.session_ended.connect(_on_session_ended)


# --- Intents ------------------------------------------------------------------

## Leave the session; the menu follows from its end.
func leave() -> void:
	session.leave()


## Host: launch [param rules]' map for everyone, the table filled or trimmed with bots to [param occupants]
## and the opening role the rules name. False when the lobby refuses ([method NetLobby.describe_launch_block]).
func start(rules: MatchRules, occupants: int) -> bool:
	var lobby: NetLobby = session.lobby
	lobby.set_rules(rules)
	lobby.fill_with_bots(occupants)
	for i: int in range(lobby.seats.size() - 1, -1, -1):
		if lobby.get_occupant_count() <= occupants:
			break
		if lobby.seats[i].is_bot():
			lobby.remove_occupant(i)
	if rules.open_with_race:
		lobby.clear_roles()
	else:
		var wanted: LobbySeat = lobby.get_seat(rules.opening_seat_index)
		lobby.assign_guard(wanted.index if wanted != null and wanted.is_occupied() else 0)
	return lobby.launch()


## Host: everyone back to the hub together, still connected.
func everyone_to_hub() -> void:
	var lobby: NetLobby = session.lobby
	if lobby.get_phase() == NetLobby.Phase.IN_MATCH:
		lobby.conclude_match(-1)
	lobby.return_to_lobby()


## Ask to play the finished match again: this seat's ready mark. The lobby relaunches once it is agreed.
func rematch() -> void:
	var lobby: NetLobby = session.lobby
	if lobby.get_phase() == NetLobby.Phase.POST_MATCH and lobby.get_local_seat() != null:
		lobby.set_ready(lobby.get_local_seat_index(), true)


## The reason the last session ended under a session scene, once; empty when there is none.
func take_end_reason() -> StringName:
	var reason: StringName = _end_reason
	_end_reason = &""
	return reason


# --- Reading ------------------------------------------------------------------

## The lobby's epoch when it names a scene of this kind ([param hub] or match), else 0.
func epoch_for(hub: bool) -> int:
	var lobby: NetLobby = session.lobby
	return lobby.get_epoch() if hub == (lobby.get_phase() == NetLobby.Phase.GATHERING) else 0



# --- Epochs -------------------------------------------------------------------

func _on_roster_changed() -> void:
	var lobby: NetLobby = session.lobby
	if lobby.get_local_seat() == null or lobby.get_epoch() == _epoch:
		return
	_epoch = lobby.get_epoch()
	_standing = false
	_in_match = lobby.get_phase() != NetLobby.Phase.GATHERING
	_stop_warmup()
	_wanted_path = match_scene_path if _in_match else hub_scene_path
	scene_wanted.emit(_wanted_path)
	if _wanted_path.is_empty():
		# Nothing to load: the scene already up is this epoch's.
		_acknowledge(_epoch)
		return
	_away = true
	if follows:
		_place.call_deferred(_epoch)


## Load the scene of [param epoch] on the main thread and put it up, unless the lobby has moved on. The
## machine is LOADING, so its silence is allowed: no game script runs beside a load (no loader deadlock).
func _place(epoch: int) -> void:
	if epoch != _epoch:
		return
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_file(_wanted_path)
	if error != OK:
		push_error("SessionFlow could not load %s (%s); leaving the session." % [_wanted_path, error_string(error)])
		leave()


## The scene of [param epoch] has bound its bodies at [param scene]: warm it, then say it stands.
func scene_bound(epoch: int, scene: Node) -> void:
	if epoch != _epoch or _standing or _warmup != null:
		return
	_warmup = SceneWarmup.new(scene)
	_warmup.finished.connect(_acknowledge.bind(epoch), CONNECT_ONE_SHOT)
	add_child(_warmup)


func _acknowledge(epoch: int) -> void:
	if epoch != _epoch or _standing:
		return
	_warmup = null
	_standing = true
	session.lobby.acknowledge_scene(epoch)


func _stop_warmup() -> void:
	if is_instance_valid(_warmup):
		_warmup.queue_free()
	_warmup = null


# --- Ending -------------------------------------------------------------------

## The one session-end handler. A standing match keeps its result up with the host lost on it;
## anything else that replaced the starting screen goes back to the menu, saying why.
func _on_session_ended(failed: bool) -> void:
	var match_stands: bool = _in_match and _standing
	_epoch = 0
	_standing = false
	_stop_warmup()
	if not _away:
		return
	if failed and match_stands:
		host_lost.emit()
		return
	_to_menu(HOST_LOST_REASON if failed else &"")


func _to_menu(reason: StringName) -> void:
	_away = false
	_in_match = false
	_end_reason = reason
	scene_wanted.emit(menu_scene_path)
	if not follows:
		return
	get_tree().paused = false
	MouseFocus.set_play_wants(false)
	var error: Error = get_tree().change_scene_to_file(menu_scene_path)
	if error != OK:
		push_error("SessionFlow could not load %s: %s" % [menu_scene_path, error_string(error)])
