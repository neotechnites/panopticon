extends Node

## Host or client through the real MultiplayerScreen into the hub; the host starts the first decided wedge
## once --humans are in, --win ends it, --back returns to the hub. Logs every body's position. Stdout.

const SCREEN_SCENE: String = "res://ui/multiplayer_screen.tscn"

var _o: Dictionary = {}
var _screen: MultiplayerScreen = null
var _lobby: NetLobby = null
var _session: NetSession = null
var _t0: int = 0
var _started: bool = false
var _match_ms: int = -1
var _last_scene: String = ""
var _physics_start: MapWedge = null
var _physics_hub: HubLobby = null
var _scene_ms: int = 0
var _trace_ms: int = 0
var _won: bool = false
var _back_ms: int = -1
var _hub_again_ms: int = -1
var _hub_visits: int = 0


func _ready() -> void:
	_o = BotHarness.parse_arguments({"role": "server", "address": "127.0.0.1", "port": 27960,
		"seconds": 20.0, "humans": 2, "wait": 3.0, "limit": 120.0, "map": "", "walk": false, "name": "", "press": true, "press_key": true,
		"win": -1.0, "back": -1.0, "hub_seconds": 6.0, "trace": 1.5, "guard": -1})
	_t0 = Time.get_ticks_msec()
	_boot.call_deferred()


func _line(s: String) -> void:
	print("HUBRUN t=%.2f %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, s])


## Moves itself to the root so the scene changes it drives do not free it.
func _boot() -> void:
	var tree: SceneTree = get_tree()
	reparent(tree.root)
	SettingsStore.instance().config_path = "user://net_harness_settings.cfg"
	_screen = (load(SCREEN_SCENE) as PackedScene).instantiate() as MultiplayerScreen
	tree.root.add_child(_screen)
	tree.current_scene = _screen
	_session = _screen.ensure_session()
	_lobby = _session.lobby
	_lobby.roster_changed.connect(func() -> void: _line("ROSTER " + _lobby.describe().replace("\n", " | ")))
	if not String(_o.name).is_empty():
		_screen.set_player_name(String(_o.name))
	var port: int = int(_o.port)
	if String(_o.role) == "server":
		if int(_o.guard) >= 0:
			SettingsStore.instance().settings.skip_opening_race = true
			SettingsStore.instance().settings.tower_seat_index = int(_o.guard)
		_screen.set_host_port(port)
		_line("HOST " + error_string(_screen.start_hosting()))
	else:
		_screen.set_join_target(String(_o.address), port)
		_line("JOIN " + error_string(_screen.join_game()))


func _process(_delta: float) -> void:
	if _lobby == null:
		return
	var tree: SceneTree = get_tree()
	var scene_node: Node = tree.current_scene
	var scene: String = scene_node.scene_file_path if scene_node != null else "<none>"
	if scene != _last_scene:
		_last_scene = scene
		_scene_ms = Time.get_ticks_msec()
		_line("SCENE " + scene)
		if scene == "res://hub/hub.tscn":
			_hub_visits += 1
			if _hub_visits >= 2:
				_hub_again_ms = _scene_ms
	var elapsed: float = (Time.get_ticks_msec() - _t0) / 1000.0
	if bool(_o.walk):
		_walk(elapsed)
	if String(_o.role) == "server" and not _started and scene_node != null:
		var hub: HubLobby = null
		for n: Node in scene_node.find_children("*", "Node", true, false):
			if n is HubLobby:
				hub = n as HubLobby
		if hub != null and _humans() >= int(_o.humans) and elapsed > float(_o.wait):
			for w: Node in hub.wedges_root.get_children():
				var wedge: MapWedge = w as MapWedge
				if wedge != null and wedge.is_decided() and (String(_o.map).is_empty() or String(wedge.map_id) == String(_o.map)):
					_press_start(hub, wedge)
					break
	if _match_ms < 0 and scene == "res://match/match.tscn":
		_match_ms = Time.get_ticks_msec()
		_line("MATCH loaded")
	if _match_ms >= 0 and _hub_visits < 2:
		_finish_match(scene_node)
	var seconds: float = float(_o.hub_seconds) if float(_o.back) >= 0.0 else float(_o.seconds)
	var since: int = _hub_again_ms if float(_o.back) >= 0.0 else _match_ms
	if since >= 0 and (Time.get_ticks_msec() - since) / 1000.0 > seconds:
		_line("END ok phase=%s" % String(NetLobby.Phase.keys()[_lobby.get_phase()]))
		tree.quit(0)
	elif elapsed > float(_o.limit):
		_line("END timeout")
		tree.quit(2)


func _humans() -> int:
	var n: int = 0
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if seat.is_human():
			n += 1
	return n


## Scripted wandering: forward and strafe in turns, jumps, shoves and mouse look.
func _walk(elapsed: float) -> void:
	var phase: int = int(elapsed / 1.5) % 4
	_hold(&"move_forward", phase != 2)
	_hold(&"move_left", phase == 1)
	_hold(&"move_right", phase == 3)
	_hold(&"move_back", phase == 2)
	_hold(&"jump", fmod(elapsed, 2.3) < 0.1)
	_hold(&"shove", fmod(elapsed, 3.7) < 0.1)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(6.0, sin(elapsed) * 3.0)
	Input.parse_input_event(motion)


func _hold(action: StringName, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


## The host's own way in: stand on the wedge's dais and press interact, as a player does.
func _press_start(hub: HubLobby, wedge: MapWedge) -> void:
	if not bool(_o.press):
		_started = true
		_line("START wedge=%s result=%s" % [wedge.map_id, str(hub._start_on(wedge))])
		return
	if hub.get_wedge_here() != wedge:
		var dais: Node3D = wedge.get_node("Dais") as Node3D
		hub.player.global_position = dais.global_position + Vector3.UP * 0.5
		hub.player.velocity = Vector3.ZERO
		return
	_started = true
	if not bool(_o.press_key):
		_physics_start = wedge
		_physics_hub = hub
		return
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	_line("START pressed interact on wedge=%s" % wedge.map_id)


func _physics_process(_delta: float) -> void:
	_trace()
	if _physics_start != null:
		_line("START in physics wedge=%s result=%s" % [_physics_start.map_id, str(_physics_hub.start_map())])
		_physics_start = null


## Host: --win seconds into the match, seat 0 wins. Anyone: --back seconds after the win, Back to hub.
func _finish_match(scene_node: Node) -> void:
	var now: int = Time.get_ticks_msec()
	if String(_o.role) == "server" and not _won and float(_o.win) >= 0.0 and (now - _match_ms) / 1000.0 > float(_o.win):
		var controller: MatchController = scene_node.get_node_or_null(^"MatchController") as MatchController
		if controller != null and controller.get_phase() != MatchController.Phase.MATCH_OVER and not controller.get_participants().is_empty():
			_won = true
			controller._win_match(controller.get_participants()[0])
			_line("WIN forced")
	var screen: MatchResultScreen = scene_node.get_node_or_null(^"ResultScreen") as MatchResultScreen
	if _back_ms == -1 and screen != null and screen.is_showing() and float(_o.back) >= 0.0:
		_back_ms = now
	if _back_ms >= 0 and screen != null and (now - _back_ms) / 1000.0 > float(_o.back):
		_back_ms = -2
		_line("BACK pressed")
		screen.play_again()


## Every body this scene's NetMatch drives: seat, position, shown, simulating. Each physics
## frame for --trace seconds after a scene change, then twice a second.
func _trace() -> void:
	var scene_node: Node = get_tree().current_scene
	if scene_node == null:
		return
	var net: NetMatch = scene_node.get_node_or_null(^"NetMatch") as NetMatch
	if net == null:
		return
	var now: int = Time.get_ticks_msec()
	if (now - _scene_ms) / 1000.0 > float(_o.trace) and now - _trace_ms < 500:
		return
	_trace_ms = now
	var parts: PackedStringArray = PackedStringArray()
	for child: Node in net.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link == null or link.controller == null or not link.controller.is_inside_tree():
			continue
		var body: PlayerController = link.controller
		var p: Vector3 = body.global_position
		parts.append("s%d(%.2f,%.2f,%.2f)%s%s%s" % [link.seat_index, p.x, p.y, p.z,
			"" if body.is_visible_in_tree() else " hidden", " sim" if body.is_physics_processing() else "",
			" floor" if body.is_on_floor() else ""])
	_line("POS %s%s %s" % [scene_node.scene_file_path.get_file(), " 3d-off" if get_viewport().disable_3d else "", " ".join(parts)])
