extends SceneTree

## Headless server or client for a localhost net match, straight into match.tscn (no hub).
## Run one --role=server and N --role=client; logs through [SessionProbe]. Exit 0 ok, 1 bad
## arguments, 2 never launched or session lost, 3 --until=won and nobody won in --seconds.
##
## --humans people the host waits for (itself included), --seats total with bots, --tower the
## opening guard seat (-1 opens with the race), --map, --screen=true drives the real MultiplayerScreen.
## --until=time ends at --seconds; --until=won ends --linger seconds after match_won.
## Server debug hooks, seconds into the match: --arm-finisher, --kill-guard, --arm-host=true.
## --bind-delay holds this machine's match scene back after launch; --enet-throttle=true restores ENet's.
## Match settings, wire faults, quitting and the scripted human are [constant SessionProbe.OPTIONS].

const MATCH_SCENE: String = "res://match/match.tscn"
const SESSION_SCENE: String = "res://match/net/net_session.tscn"
const SCREEN_SCENE: String = "res://ui/multiplayer_screen.tscn"
const RULES_PATH: String = "res://match/rules/default_match_rules.tres"

var _o: Dictionary = {}
var _probe: SessionProbe = null
var _session: NetSession = null
var _screen: MultiplayerScreen = null
var _rules_set: bool = false
var _lobby: NetLobby = null
var _match: Node = null
var _started_ms: int = 0
var _readied: bool = false
var _launched: bool = false
var _exit_code: int = -1
var _armed_finisher: bool = false
var _killed_guard: bool = false
var _won_ms: int = -1
var _enet: ENetMultiplayerPeer = null


func _initialize() -> void:
	var defaults: Dictionary = SessionProbe.OPTIONS.duplicate()
	defaults.merge({
		"seconds": 90.0, "seats": 6, "tower": 1, "humans": 3, "screen": false, "preset": "classic",
		"press-ability": 0, "press-at": 6.0, "press-every": 0.0, "arm-finisher": 0.0, "kill-guard": 0.0,
		"map": "", "bind-delay": 0.0, "enet-throttle": false, "arm-host": false,
		"until": "time", "linger": 4.0,
	}, true)
	_o = BotHarness.parse_arguments(defaults)
	Engine.max_fps = 60
	_started_ms = Time.get_ticks_msec()
	if int(_o["press-ability"]) > 0:
		var legacy: String = "%d@%.2f+%.2f" % [int(_o["press-ability"]), float(_o["press-at"]), float(_o["press-every"]) * 0.8]
		if float(_o["press-every"]) > 0.0:
			legacy += "/%.2f" % float(_o["press-every"])
		_o.keys = legacy if String(_o.keys).is_empty() else "%s,%s" % [String(_o.keys), legacy]
	if String(_o.name).is_empty():
		_o.name = "Host" if _is_server() else "Client%d" % (OS.get_process_id() % 100)
	_probe = SessionProbe.new()
	_probe.configure(_o)
	if _o.has("_error"):
		_exit_code = 1


## Runs on the first frame: the tree has a MultiplayerAPI only once it is live.
func _boot() -> void:
	root.add_child(_probe)
	var settings: GameSettings = SettingsStore.instance().settings
	if _is_server():
		var map: String = String(_o.map)
		if not map.is_empty():
			settings.map_id = StringName(map)
		var tower: int = int(_o.tower)
		settings.skip_opening_race = tower >= 0
		settings.tower_seat_index = maxi(tower, 0)
		_probe.apply_settings()
	if _use_screen():
		_screen = (load(SCREEN_SCENE) as PackedScene).instantiate() as MultiplayerScreen
		root.add_child(_screen)
		current_scene = _screen
		_session = _screen.ensure_session()
		# This runner drives the screen's own lobby panel; it has no hub to walk into.
		_session.flow.hub_scene_path = ""
	else:
		_session = (load(SESSION_SCENE) as PackedScene).instantiate() as NetSession
		_session.name = "NetSession"
		# This runner adds the match scene itself on launch.
		_session.flow.follows = false
		root.add_child(_session)
	_lobby = _session.lobby
	_probe.attach(_session)
	_lobby.roster_changed.connect(_on_roster_changed)
	_lobby.match_launching.connect(_on_launching)
	_probe.host_lost.connect(func() -> void: _finish(0 if _probe.matches_bound > 0 else 2, "host-lost"))
	_probe.match_won.connect(func() -> void: _won_ms = Time.get_ticks_msec())
	var port: int = int(_o.port)
	var address: String = String(_o.address)
	if _use_screen():
		_screen.set_player_name(String(_o.name))
		if _is_server():
			_screen.set_host_port(port)
			_probe.line("HOST port=%d result=%s" % [port, error_string(_screen.start_hosting())])
		else:
			_screen.set_join_target(address, port)
			_probe.line("JOIN port=%d result=%s" % [port, error_string(_screen.join_game())])
	elif _is_server():
		var error: Error = _session.host(port)
		_probe.line("HOST port=%d result=%s" % [port, error_string(error)])
		if error != OK:
			_finish(2, "host-failed")
			return
		_lobby.open(String(_o.name))
	else:
		_probe.line("JOIN port=%d result=%s" % [port, error_string(_session.join(address, port))])
	_enet = _session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	_probe.condition_wire()


## ENet's default throttle (interval 5 s, accelerate 2, decelerate 2) on every live peer.
func _restore_enet_throttle() -> void:
	if _enet == null or _enet.host == null:
		return
	for packet_peer: ENetPacketPeer in _enet.host.get_peers():
		packet_peer.throttle_configure(5000, 2, 2)


func _process(_delta: float) -> bool:
	if _exit_code >= 0:
		quit(_exit_code)
		return true
	if _session == null:
		_boot()
		return false
	if _is_server() and not _launched and _lobby.get_phase() == NetLobby.Phase.GATHERING:
		_drive_lobby()
	if bool(_o["enet-throttle"]):
		_restore_enet_throttle()
	if _probe.wants_quit():
		if String(_o["quit-mode"]) == "drop":
			OS.kill(OS.get_process_id())
		_finish(0, "scripted-quit")
		return true
	var in_match: float = _probe.match_seconds()
	if _probe.matches_bound > 0 and in_match >= 0.0:
		_run_debug_hooks(in_match)
		var until_won: bool = String(_o.until) == "won"
		if until_won and _won_ms >= 0 and Time.get_ticks_msec() - _won_ms > int(float(_o.linger) * 1000.0):
			_finish(0, "match-won")
		elif in_match >= float(_o.seconds):
			_finish(3 if until_won and _is_server() else 0, "ceiling-unresolved" if until_won else "time-budget")
	elif float(Time.get_ticks_msec() - _started_ms) / 1000.0 > 60.0 + float(_o["bind-delay"]):
		_finish(2, "never-launched")
	return _exit_code >= 0


# --- Debug hooks --------------------------------------------------------------

## The server's two shortcuts into the finale, so a short run shows a client what it is meant to see.
func _run_debug_hooks(in_match: float) -> void:
	var controller: MatchController = _probe.controller
	if not _is_server() or not is_instance_valid(controller):
		return
	var arm_at: float = float(_o["arm-finisher"])
	if arm_at > 0.0 and not _armed_finisher and in_match >= arm_at:
		_armed_finisher = true
		var who: MatchParticipant = controller.get_human_participant() if bool(_o["arm-host"]) else _remote_prisoner(controller)
		_probe.line("DEBUG arm-finisher seat=%s" % _probe._seat_of(who))
		if who != null:
			controller._arm_the_finisher(who)
	var kill_at: float = float(_o["kill-guard"])
	if kill_at > 0.0 and not _killed_guard and in_match >= kill_at:
		_killed_guard = true
		var guard: MatchParticipant = controller.get_seat_participant()
		var finisher: MatchParticipant = controller.get_finisher()
		_probe.line("DEBUG kill-guard guard=%s finisher=%s" % [_probe._seat_of(guard), _probe._seat_of(finisher)])
		if guard != null and finisher != null and finisher.body != null and guard.body != null:
			controller.throw_guard(guard, guard.body.global_position - finisher.body.global_position)


## A prisoner some other peer is driving: the one whose client this run is about.
func _remote_prisoner(controller: MatchController) -> MatchParticipant:
	for p: MatchParticipant in controller.get_participants():
		if p.is_human() and p != controller.get_human_participant() and p.is_running:
			return p
	return null


# --- Lobby --------------------------------------------------------------------

func _is_server() -> bool:
	return String(_o.get("role", "server")) == "server"


func _use_screen() -> bool:
	return bool(_o.get("screen", false))


func _on_roster_changed() -> void:
	if _is_server() or _readied:
		return
	var seat: LobbySeat = _lobby.get_local_seat()
	if seat == null:
		return
	_readied = true
	if _use_screen():
		_screen.set_ready(true)
		return
	_lobby.set_display_name(seat.index, String(_o.name))
	_lobby.set_ready(seat.index, true)


func _humans() -> int:
	var count: int = 0
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if seat.is_human():
			count += 1
	return count


func _drive_lobby() -> void:
	if _humans() < int(_o.humans):
		return
	var seats: int = maxi(int(_o.seats), int(_o.humans))
	var settings: GameSettings = SettingsStore.instance().settings
	if _use_screen():
		if not _rules_set:
			_rules_set = true
			_screen.select_preset(StringName(String(_o.preset)))
			# The preset resets the opening and the settings; the command line goes back over it.
			var tower: int = int(_o.tower)
			settings.skip_opening_race = tower >= 0
			settings.tower_seat_index = maxi(tower, 0)
			_probe.apply_settings()
			_screen.set_prisoner_count(seats - 1)
		_screen.set_ready(true)
		if _screen.can_start():
			_probe.line("START result=%s" % str(_screen.start_match()))
		return
	if not _rules_set:
		_rules_set = true
		# Published whoever is seated, as the hub does, so every machine loads the host's map and rules.
		var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
		settings.prisoner_count = seats - 1
		settings.apply_to_match_rules(rules)
		_lobby.set_rules(rules)
		_lobby.fill_with_bots(seats)
		var tower: int = int(_o.tower)
		if tower >= 0:
			_lobby.assign_guard(tower)
		else:
			_lobby.clear_roles()
	_lobby.set_ready(_lobby.get_local_seat_index(), true)
	if _lobby.can_launch():
		_probe.line("START result=%s" % str(_lobby.launch()))


func _on_launching() -> void:
	if _launched:
		return
	_launched = true
	_probe.line("LAUNCH local_seat=s%d" % _lobby.get_local_seat_index())
	if _use_screen():
		return
	var delay: float = float(_o["bind-delay"])
	if delay > 0.0:
		await create_timer(delay).timeout
		_probe.line("BIND after delay=%.1f" % delay)
	_match = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(_match)
	current_scene = _match


func _finish(code: int, reason: String) -> void:
	if _exit_code >= 0:
		return
	_exit_code = code
	_probe.finish(code == 0, reason)
	if _session != null:
		_session.leave()
	quit(code)
