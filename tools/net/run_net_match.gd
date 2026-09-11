extends SceneTree

## Headless server or client for a localhost net match. Logs phases, seats,
## positions and errors to --log. Run one --role=server and N --role=client.
## --screen=true goes through the real MultiplayerScreen instead of the lobby API.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const SESSION_SCENE: String = "res://scenes/net/net_session.tscn"
const SCREEN_SCENE: String = "res://scenes/ui/multiplayer_screen.tscn"
## Positions are logged once per this many authority ticks, on every process.
const SAMPLE_TICKS: int = 120

var _o: Dictionary = {}
var _session: NetSession = null
var _screen: MultiplayerScreen = null
var _rules_set: bool = false
var _lobby: NetLobby = null
var _log: FileAccess = null
var _match: Node = null
var _controller: MatchController = null
var _net_match: NetMatch = null
var _started_ms: int = 0
var _match_ms: int = -1
var _last_bucket: int = -1
var _readied: bool = false
var _launched: bool = false
var _finished: bool = false
var _errors: int = 0


func _initialize() -> void:
	_o = BotHarness.parse_arguments({
		"role": "server", "address": "127.0.0.1", "port": 27960, "seconds": 90.0,
		"log": "", "seats": 6, "tower": 1, "name": "", "humans": 3, "fire-every": 0.0,
		"screen": false, "preset": "classic",
	})
	Engine.max_fps = 60
	_started_ms = Time.get_ticks_msec()
	var log_path: String = String(_o.get("log", ""))
	if not log_path.is_empty():
		_log = FileAccess.open(log_path, FileAccess.WRITE)


## Runs on the first frame: the tree has a MultiplayerAPI only once it is live.
func _boot() -> void:
	if _use_screen():
		SettingsStore.instance().config_path = "user://net_harness_settings.cfg"
		_screen = (load(SCREEN_SCENE) as PackedScene).instantiate() as MultiplayerScreen
		root.add_child(_screen)
		current_scene = _screen
		_session = _screen.ensure_session()
	else:
		_session = (load(SESSION_SCENE) as PackedScene).instantiate() as NetSession
		_session.name = "NetSession"
		root.add_child(_session)
	_lobby = _session.lobby
	_lobby.rules_changed.connect(_on_rules_changed)
	_lobby.phase_changed.connect(func(phase: NetLobby.Phase) -> void:
		_line("LOBBY phase=%s" % String(NetLobby.Phase.keys()[phase])))
	_lobby.roster_changed.connect(_on_roster_changed)
	_lobby.match_launching.connect(_on_launching)
	_lobby.join_refused.connect(func(peer: int, why: String) -> void: _line("REFUSED peer=%d %s" % [peer, why]))
	_session.session_ended.connect(func(failed: bool) -> void:
		_line("SESSION ended failed=%s" % str(failed))
		if not _finished:
			_finish("session ended"))
	var port: int = int(_o.get("port", 27960))
	var address: String = String(_o.get("address", "127.0.0.1"))
	if _use_screen():
		_screen.set_player_name(_display_name())
		if _is_server():
			_screen.set_host_port(port)
			_line("HOST port=%d result=%s" % [port, error_string(_screen.start_hosting())])
			_line("ADDRESSES " + " | ".join(MultiplayerScreen.local_addresses()))
		else:
			_screen.set_join_target(address, port)
			_line("JOIN port=%d result=%s" % [port, error_string(_screen.join_game())])
	elif _is_server():
		var error: Error = _session.host(port)
		_line("HOST port=%d result=%s" % [port, error_string(error)])
		_lobby.open(_display_name())
	else:
		var error: Error = _session.join(address, port)
		_line("JOIN port=%d result=%s" % [port, error_string(error)])


func _process(_delta: float) -> bool:
	if _finished:
		return true
	if _session == null:
		_boot()
		return false
	var elapsed: float = _seconds()
	if _is_server() and not _launched and _lobby.get_phase() == NetLobby.Phase.GATHERING:
		_drive_lobby()
	if _launched and _match == null and current_scene != null and current_scene.has_node("MatchController"):
		_hook_match(current_scene)
	if _match_ms >= 0:
		var in_match: float = float(Time.get_ticks_msec() - _match_ms) / 1000.0
		var bucket: int = _tick() / SAMPLE_TICKS
		if _tick() >= 0 and bucket != _last_bucket:
			_last_bucket = bucket
			_sample()
		if in_match >= float(_o.get("seconds", 90.0)):
			_finish("time budget")
	elif elapsed > 60.0:
		_finish("never launched")
	return _finished


func _finalize() -> void:
	if _log != null:
		_log.close()


# --- Lobby --------------------------------------------------------------------

func _is_server() -> bool:
	return String(_o.get("role", "server")) == "server"


func _use_screen() -> bool:
	return bool(_o.get("screen", false))


func _on_rules_changed() -> void:
	var rules: MatchRules = _lobby.get_rules()
	if rules == null:
		return
	_line("RULES prisoners=%d ghosts=%s race=%s lives=%d rounds=%d runner_win=%d reload=%.2f" % [
		rules.prisoner_count, str(rules.has_ghosts()), str(rules.open_with_race), rules.prisoner_lives,
		rules.rounds_to_win_match, int(rules.runner_win_condition), rules.base_reload_seconds,
	])


func _display_name() -> String:
	var wanted: String = String(_o.get("name", ""))
	return wanted if not wanted.is_empty() else ("Host" if _is_server() else "Client%d" % (Time.get_ticks_msec() % 100))


func _on_roster_changed() -> void:
	_line("ROSTER " + _lobby.describe().replace("\n", " | "))
	if _is_server() or _readied:
		return
	var seat: LobbySeat = _lobby.get_local_seat()
	if seat == null:
		return
	_readied = true
	if _use_screen():
		_screen.set_ready(true)
		return
	_lobby.set_display_name(seat.index, _display_name())
	_lobby.set_ready(seat.index, true)


func _humans() -> int:
	var count: int = 0
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if seat.is_human():
			count += 1
	return count


func _drive_lobby() -> void:
	if _humans() < int(_o.get("humans", 3)):
		return
	if _use_screen():
		if not _rules_set:
			_rules_set = true
			_screen.select_preset(StringName(String(_o.get("preset", "classic"))))
			# The opening is a GameSettings choice the preset resets; --tower overrides it.
			var tower: int = int(_o.get("tower", 1))
			var settings: GameSettings = SettingsStore.instance().settings
			settings.skip_opening_race = tower >= 0
			settings.tower_seat_index = maxi(tower, 0)
			_screen.set_prisoner_count(int(_o.get("seats", 6)) - 1)
			_line("RULES set prisoners=%d preset=%s" % [int(_o.get("seats", 6)) - 1, String(_o.get("preset", "classic"))])
		_screen.set_ready(true)
		if _screen.can_start():
			_line("START result=%s" % str(_screen.start_match()))
		return
	if _lobby.get_occupant_count() < int(_o.get("seats", 6)):
		_lobby.fill_with_bots(int(_o.get("seats", 6)))
		var tower: int = int(_o.get("tower", 1))
		if tower >= 0:
			_lobby.assign_guard(tower)
		else:
			_lobby.clear_roles()
	_lobby.set_ready(_lobby.get_local_seat_index(), true)
	if _lobby.can_launch():
		_lobby.launch()


func _on_launching() -> void:
	if _launched:
		return
	_launched = true
	_line("LAUNCH local_seat=%d" % _lobby.get_local_seat_index())
	if _use_screen():
		return
	_match = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(_match)
	current_scene = _match
	_hook_match(_match)


func _hook_match(match_scene: Node) -> void:
	_match = match_scene
	_controller = _match.get_node("MatchController") as MatchController
	_net_match = _match.get_node("NetMatch") as NetMatch
	var rules: MatchRules = _controller.get_rules()
	_line("MATCH rules prisoners=%d ghosts=%s race=%s map=%s" % [
		rules.prisoner_count, str(rules.has_ghosts()), str(rules.open_with_race), String(rules.map_id)])
	_hook_controller()
	_net_match.match_bound.connect(func(authority: bool) -> void:
		_match_ms = Time.get_ticks_msec()
		_line("MATCH bound authority=%s" % str(authority)))
	if _net_match.has_started():
		_match_ms = Time.get_ticks_msec()
		_line("MATCH bound authority=true (started on load)")
	var scripted: ScriptedIntentSource = ScriptedIntentSource.new()
	scripted.name = "Scripted"
	scripted.fire_every = float(_o.get("fire-every", 0.0))
	_net_match.add_child(scripted)
	_net_match.set_local_source(scripted)


# --- Logging ------------------------------------------------------------------

func _hook_controller() -> void:
	_controller.match_started.connect(func(count: int) -> void: _line("EV match_started participants=%d" % count))
	_controller.race_started.connect(func() -> void: _line("EV race_started"))
	_controller.round_started.connect(func() -> void:
		_line("EV round_started round=%d seat=%s" % [_controller.get_round_number(), _who(_controller.get_seat_participant())]))
	_controller.seat_changed.connect(func(p: MatchParticipant, turns: int) -> void:
		_line("EV seat_changed seat=%s turns=%d" % [_who(p), turns]))
	_controller.participant_converted.connect(func(p: MatchParticipant) -> void:
		_line("EV converted who=%s phase=%s" % [_who(p), _controller.get_phase_name()]))
	_controller.runner_ghosted.connect(func(p: MatchParticipant) -> void: _line("EV ghosted who=%s" % _who(p)))
	_controller.ghost_respawned.connect(func(p: MatchParticipant) -> void: _line("EV ghost_respawned who=%s" % _who(p)))
	_controller.ghost_caught.connect(func(g: MatchParticipant, c: MatchParticipant) -> void:
		_line("EV ghost_caught ghost=%s caught=%s" % [_who(g), _who(c)]))
	_controller.round_resolved.connect(func(outcome: MatchController.Outcome) -> void:
		_line("EV round_resolved round=%d outcome=%s" % [_controller.get_round_number(), String(MatchController.Outcome.keys()[outcome])]))
	_controller.match_won.connect(func(p: MatchParticipant) -> void: _line("EV match_won who=%s" % _who(p)))
	if _controller.rifle != null:
		_controller.rifle.fired.connect(func(origin: Vector3, _end: Vector3) -> void:
			_line("RIFLE fired by=%s from=%.1f,%.1f,%.1f" % [_who(_controller.get_seat_participant()), origin.x, origin.y, origin.z]))
		_controller.rifle.target_hit.connect(func(collider: Node3D, _at: Vector3, _n: Vector3) -> void:
			_line("RIFLE hit=%s" % _who(_controller.resolve_participant(collider))))
	var transition: RoundTransitionScreen = _match.get_node_or_null("RoundTransition") as RoundTransitionScreen
	if transition != null:
		transition.transition_shown.connect(func(round_number: int) -> void:
			_line("EV card_shown round=%d paused=%s" % [round_number, str(paused)]))


func _who(p: MatchParticipant) -> String:
	return "%d:%s" % [p.index, p.display_name] if p != null else "none"


func _tick() -> int:
	var replicator: NetReplicator = _session.replicator
	return replicator.get_tick() if _session.is_authority() else replicator.get_latest_tick()


func _sample() -> void:
	if _controller == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	for p: MatchParticipant in _controller.get_participants():
		var at: Vector3 = p.body.global_position if p.body != null else Vector3.ZERO
		parts.append("%d=%s:%.1f,%.1f,%.1f" % [p.index, p.get_role_name(), at.x, at.y, at.z])
	_line("POS tick=%d phase=%s round=%d seat=%s paused=%s %s" % [
		_tick(), _controller.get_phase_name(), _controller.get_round_number(),
		_who(_controller.get_seat_participant()), str(paused), " ".join(parts),
	])
	var mine: MatchParticipant = _controller.get_human_participant()
	if mine != null and mine.body != null:
		var source: IntentSource = mine.body.intent_source
		_line("LOCAL slot=%d phys=%s src=%s layer=%d vel=%.1f" % [
			mine.index, str(mine.body.is_physics_processing()),
			source.get_class() if source != null else "null",
			mine.body.collision_layer, mine.body.velocity.length(),
		])


func _seconds() -> float:
	return float(Time.get_ticks_msec() - _started_ms) / 1000.0


func _line(text: String) -> void:
	var stamped: String = "t=%.2f %s" % [_seconds(), text]
	print(stamped)
	if _log != null:
		_log.store_line(stamped)
		_log.flush()


func _finish(reason: String) -> void:
	if _finished:
		return
	if _controller != null:
		_line("END reason=%s phase=%s round=%d seat=%s outcome=%s" % [
			reason, _controller.get_phase_name(), _controller.get_round_number(),
			_who(_controller.get_seat_participant()), _controller.get_outcome_name(),
		])
	else:
		_line("END reason=%s (no match)" % reason)
	_finished = true
	_session.leave()
	quit(0)
