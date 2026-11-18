extends Node

## Host or client through the real MultiplayerScreen into the hub, then --matches matches off the
## wedges named by --maps, each to a result and back to the hub. Exit 0 END ok, 1 bad arguments, 2 timeout.
##
## A match ends on its own (ceiling --ceiling, then forced and logged) or forced at --win seconds.
## At the result, --back seconds in: --rematches=N rematches first, then --after=hub-all|back.
## --relaunch-bots=3,1 / --relaunch-seats / --relaunch-tower: the debug menu's relaunch at --win of match k.
## --shove-at=s: the host, in the hub, stands behind a client's body and shoves it, every 3 s from s.
## Match settings, wire faults, quitting and the scripted human are [constant SessionProbe.OPTIONS].

const SCREEN_SCENE: String = "res://ui/multiplayer_screen.tscn"
## The longest the host waits, past its own hub seconds, for the clients to finish theirs and go.
const HOST_LINGER_SECONDS: float = 8.0

var _o: Dictionary = {}
var _probe: SessionProbe = null
var _screen: MultiplayerScreen = null
var _lobby: NetLobby = null
var _session: NetSession = null
var _t0: int = 0
var _maps: PackedStringArray = PackedStringArray()
var _scene_kind: String = ""
var _scene_ms: int = 0
var _hub_visits: int = 0
var _matches_started: int = 0
var _matches_done: int = 0
var _started: bool = false
var _auto_relaunch: bool = false
var _physics_start: MapWedge = null
var _physics_hub: HubLobby = null
var _play_ms: int = -1
var _won: bool = false
var _result_ms: int = -1
var _acted: bool = false
var _rematches_left: int = 0
var _rematch_ms: int = -1
var _launch_ms: int = -1
var _gathered: bool = false
var _interact_down: int = 0
var _relaunched: int = 0
var _next_shove: float = 0.0
var _exit_code: int = -1


func _ready() -> void:
	var defaults: Dictionary = SessionProbe.OPTIONS.duplicate()
	defaults.merge({
		"humans": 2, "wait": 3.0, "limit": 240.0, "maps": "", "map": "", "matches": 0,
		"win": -1.0, "ceiling": 150.0, "back": 3.0, "after": "hub-all", "rematches": 0, "rematch-wait": 12.0,
		"hub-wait": 4.0, "hub_seconds": 6.0, "guard": -1, "press": true, "press_key": true,
		"relaunch-bots": "", "relaunch-seats": "", "relaunch-tower": -1, "shove-at": -1.0,
		"walk": true, "again": true, "rematch": false, "hub-all": true, "seconds": 20.0, "trace": 1.5,
	}, true)
	_o = BotHarness.parse_arguments(defaults)
	_t0 = Time.get_ticks_msec()
	Engine.max_fps = 60
	var maps: String = String(_o.maps) if not String(_o.maps).is_empty() else String(_o.map)
	_maps = maps.split(",", false)
	if int(_o.matches) <= 0:
		_o.matches = maxi(_maps.size(), 1)
	if bool(_o.rematch) and int(_o.rematches) == 0:
		_o.rematches = 1
	if not bool(_o.walk) and String(_o.mode) == "play":
		_o.mode = "idle"
	if String(_o.name).is_empty():
		_o.name = "Host" if _is_server() else "Client%d" % (OS.get_process_id() % 100)
	_probe = SessionProbe.new()
	_probe.configure(_o)
	if _o.has("_error"):
		_exit_code = 1
		get_tree().quit.call_deferred(1)
		return
	_boot.call_deferred()


func _is_server() -> bool:
	return String(_o.role) == "server"


## Moves itself to the root so the scene changes it drives do not free it.
func _boot() -> void:
	var tree: SceneTree = get_tree()
	reparent(tree.root)
	tree.root.add_child(_probe)
	_screen = (load(SCREEN_SCENE) as PackedScene).instantiate() as MultiplayerScreen
	tree.root.add_child(_screen)
	tree.current_scene = _screen
	_session = _screen.ensure_session()
	_lobby = _session.lobby
	_probe.attach(_session)
	_probe.scene_changed.connect(_on_scene_changed)
	_probe.match_started.connect(_on_match_started)
	_probe.match_won.connect(func() -> void: _won = true)
	_probe.host_lost.connect(func() -> void: _finish(0, "host-lost"))
	_screen.set_player_name(String(_o.name))
	var port: int = int(_o.port)
	if _is_server():
		var settings: GameSettings = SettingsStore.instance().settings
		settings.skip_opening_race = int(_o.guard) >= 0
		settings.tower_seat_index = maxi(int(_o.guard), 0)
		_probe.apply_settings()
		_screen.set_host_port(port)
		var error: Error = _screen.start_hosting()
		_probe.line("HOST port=%d result=%s" % [port, error_string(error)])
		if error != OK:
			_finish(2, "host-failed")
			return
	else:
		_screen.set_join_target(String(_o.address), port)
		_probe.line("JOIN port=%d result=%s" % [port, error_string(_screen.join_game())])
	_probe.condition_wire()


func _process(_delta: float) -> void:
	if _lobby == null or _exit_code >= 0:
		return
	var now: int = Time.get_ticks_msec()
	var elapsed: float = float(now - _t0) / 1000.0
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	if _probe.wants_quit():
		if String(_o["quit-mode"]) == "drop":
			OS.kill(OS.get_process_id())
		_finish(0, "scripted-quit")
		return
	if _scene_kind == "hub":
		_in_hub(scene, now, elapsed)
	elif _scene_kind == "match":
		_in_match(scene, now)
	if elapsed > float(_o.limit):
		_finish(2, "timeout")


func _on_scene_changed(kind: String) -> void:
	if kind == "none" or kind == _scene_kind:
		return
	if _scene_kind == "match":
		_matches_done += 1
		_probe.line("FLOW match_done n=%d of=%d" % [_matches_done, int(_o.matches)])
	_scene_kind = kind
	_scene_ms = Time.get_ticks_msec()
	if kind == "hub":
		_hub_visits += 1
		_launch_ms = -1
		_started = _auto_relaunch
		_auto_relaunch = false
	elif kind == "match":
		_matches_started += 1
		_play_ms = -1
		_won = false
		_result_ms = -1
		_acted = false
		_rematches_left = int(_o.rematches)


## A match, or a rematch of it, has begun on this machine: its clocks start over.
func _on_match_started() -> void:
	_play_ms = Time.get_ticks_msec()
	_won = false
	_result_ms = -1
	_rematch_ms = -1
	_acted = false


func _in_hub(scene: Node, now: int, elapsed: float) -> void:
	var in_hub: float = float(now - _scene_ms) / 1000.0
	if _matches_done >= int(_o.matches):
		# The host leaves last: a client still counting its own hub seconds must not lose it first.
		var alone: bool = not _is_server() or _humans() <= 1 or in_hub > float(_o.hub_seconds) + HOST_LINGER_SECONDS
		if in_hub > float(_o.hub_seconds) and alone:
			_finish(0, "flow-complete")
		return
	if not _is_server():
		return
	if float(_o["shove-at"]) >= 0.0 and elapsed > float(_o["shove-at"]):
		_shove_client(scene, elapsed)
	if _launch_ms >= 0 and now - _launch_ms > 3000 and _lobby.get_phase() == NetLobby.Phase.GATHERING:
		# The press did not take (the body had stepped off the dais): stand on it again.
		_probe.line("START retry")
		_launch_ms = -1
		_started = false
	# Everyone is waited for once; a peer who leaves later does not hold the next map back.
	_gathered = _gathered or _humans() >= int(_o.humans)
	if _started or not _gathered or elapsed < float(_o.wait) or in_hub < float(_o["hub-wait"]):
		return
	var hub: HubLobby = null
	for n: Node in scene.find_children("*", "Node", true, false):
		if n is HubLobby:
			hub = n as HubLobby
	if hub == null:
		return
	var wanted: String = _maps[_matches_started % _maps.size()] if not _maps.is_empty() else ""
	for w: Node in hub.wedges_root.get_children():
		var wedge: MapWedge = w as MapWedge
		if wedge != null and wedge.is_decided() and (wanted.is_empty() or String(wedge.map_id) == wanted):
			_press_start(hub, wedge)
			return
	_probe.line("FLOW no decided wedge for map=%s" % wanted)
	_finish(2, "no-wedge")


func _humans() -> int:
	var n: int = 0
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if seat.is_human():
			n += 1
	return n


## The host's own way in: stand on the wedge's dais and press interact, as a player does.
func _press_start(hub: HubLobby, wedge: MapWedge) -> void:
	if not bool(_o.press):
		_started = true
		_probe.line("START wedge=%s result=%s" % [wedge.map_id, str(hub._start_on(wedge))])
		return
	if hub.get_wedge_here() != wedge:
		var dais: Node3D = wedge.get_node("Dais") as Node3D
		hub.player.global_position = dais.global_position + Vector3.UP * 0.5
		hub.player.velocity = Vector3.ZERO
		return
	_started = true
	_launch_ms = Time.get_ticks_msec()
	if not bool(_o.press_key):
		_physics_start = wedge
		_physics_hub = hub
		return
	_send_interact(true)
	_interact_down = 3
	_probe.line("START pressed interact on wedge=%s" % wedge.map_id)


func _send_interact(pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"interact"
	event.pressed = pressed
	Input.parse_input_event(event)


func _physics_process(_delta: float) -> void:
	if _interact_down > 0:
		# The key comes back up, or the action stays pressed and E never reads as pressed again.
		_interact_down -= 1
		if _interact_down == 0:
			_send_interact(false)
	if _physics_start != null:
		_probe.line("START in physics wedge=%s result=%s" % [_physics_start.map_id, str(_physics_hub.start_map())])
		_physics_start = null


func _in_match(scene: Node, now: int) -> void:
	var controller: MatchController = _probe.controller
	if not is_instance_valid(controller) or _play_ms < 0:
		return
	var playing: float = float(now - _play_ms) / 1000.0
	if _is_server() and not _won and _relaunch_due(scene, playing):
		return
	if _is_server() and not _won and controller.get_phase() != MatchController.Phase.MATCH_OVER:
		var forced: bool = float(_o.win) >= 0.0 and playing > float(_o.win)
		var ceiling: bool = float(_o.win) < 0.0 and playing > float(_o.ceiling)
		if (forced or ceiling) and not controller.get_participants_ref().is_empty():
			_won = true
			_probe.line("WIN forced" if forced else "CEILING unresolved after=%.0f phase=%s round=%d" % [
				playing, controller.get_phase_name(), controller.get_round_number()])
			controller._win_match(controller.get_participants_ref()[0])
	var screen: MatchResultScreen = scene.get_node_or_null(^"ResultScreen") as MatchResultScreen
	if screen == null or not screen.is_showing() or float(_o.back) < 0.0:
		return
	if _result_ms < 0:
		_result_ms = now
	if _acted and _rematch_ms >= 0 and _is_server() and float(now - _rematch_ms) / 1000.0 > float(_o["rematch-wait"]):
		# Somebody never asked: the result is still up. Stop waiting and take the other way out.
		_probe.line("REMATCH gave up after=%.0f" % float(_o["rematch-wait"]))
		_rematch_ms = -1
		_rematches_left = 0
		_acted = false
	if _acted or float(now - _result_ms) / 1000.0 < float(_o.back):
		return
	_acted = true
	if _rematches_left > 0:
		_rematches_left -= 1
		_rematch_ms = now
		_probe.line("REMATCH pressed left=%d" % _rematches_left)
		screen.request_rematch()
	elif String(_o.after) == "back":
		_probe.line("BACK pressed")
		screen.play_again()
	elif _is_server():
		_probe.line("HUBALL pressed")
		screen._on_hub_all_pressed()


## The debug menu's relaunch: at --win of match k the host goes back with the k-th bot count.
func _relaunch_due(scene: Node, playing: float) -> bool:
	var counts: PackedStringArray = String(_o["relaunch-bots"]).split(",", false)
	if counts.is_empty() or float(_o.win) < 0.0 or _relaunched >= counts.size() or _relaunched >= _matches_started:
		return false
	if playing <= float(_o.win):
		return true
	var count: int = int(counts[_relaunched])
	_relaunched = _matches_started
	var settings: GameSettings = SettingsStore.instance().settings
	DebugMenu.write_bot_count(settings, count)
	HubLobby.relaunch_on_arrival = true
	_auto_relaunch = true
	if _relaunched == 1 and not String(_o["relaunch-seats"]).is_empty():
		HubLobby.relaunch_bot_seats = PackedInt32Array(Array(String(_o["relaunch-seats"]).split(",")).map(func(x: String) -> int: return int(x)))
		settings.skip_opening_race = int(_o["relaunch-tower"]) >= 0
		settings.tower_seat_index = maxi(int(_o["relaunch-tower"]), 0)
	_probe.line("RELAUNCH bots=%d" % count)
	_session.flow.everyone_to_hub()
	return true


func _shove_client(scene: Node, elapsed: float) -> void:
	var net: NetMatch = scene.get_node_or_null(^"NetMatch") as NetMatch
	if net == null:
		return
	var mine: PlayerController = null
	var theirs: PlayerController = null
	for child: Node in net.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link == null or link.controller == null:
			continue
		if link.seat_index == _lobby.get_local_seat_index():
			mine = link.controller
		elif theirs == null:
			theirs = link.controller
	if mine == null or theirs == null:
		return
	var press: bool = elapsed >= _next_shove
	if press:
		_next_shove = elapsed + 3.0
		var ahead: Vector3 = -theirs.global_transform.basis.z
		mine.global_position = theirs.global_position - Vector3(ahead.x, 0.0, ahead.z).normalized() * 1.0
		mine.velocity = Vector3.ZERO
		mine.look_at(theirs.global_position, Vector3.UP)
		_probe.line("SHOVE try")
		Input.action_press(&"shove")
	elif Input.is_action_pressed(&"shove"):
		Input.action_release(&"shove")


func _finish(code: int, reason: String) -> void:
	if _exit_code >= 0:
		return
	_exit_code = code
	_probe.finish(code == 0, reason)
	if _session != null:
		_session.leave()
	get_tree().quit(code)
