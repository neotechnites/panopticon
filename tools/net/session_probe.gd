class_name SessionProbe
extends Node

## The one log vocabulary of the headless net runners, and the scripted human each peer plays.
## Sits at the root across scene changes; every line is "NL w=<unix ms> t=<s> TAG key=value ...".

## Options both runners take; each runner merges its own over these.
const OPTIONS: Dictionary = {
	"role": "server", "address": "127.0.0.1", "port": 27960, "name": "", "log": "",
	"prisoners": -1, "ability": -1, "rounds": -1, "lives": -1, "ghosts": "", "brawl": false,
	"loss": 0.0, "delay-ms": 0, "jitter-ms": 0.0, "jitter-dist": "uniform", "jitter-tau-ms": 0.0, "jitter-reorders": false,
	"burst-ms": 0.0, "burst-gap-ms": 0.0, "burst-loss": 1.0, "dup": 0.0, "reorder": 0.0, "reorder-ms": 0.0,
	"wire-layer": "peer", "wire-probe-hz": 20.0, "wire-log": "", "freeze": "", "stall-at": 0.0, "stall-ms": 0, "stall-match": 1,
	"quit-at": -1.0, "quit-match": 1, "quit-mode": "leave", "host-lost-exit": 4.0,
	"mode": "play", "aim": true, "marksman": false, "fire-every": 2.6, "press-fire": 3.0, "pitch-rate": 0.0,
	"keys": "", "hub-keys": "", "keys-wait": true, "sample": 0.5,
	"break": "", "break-at": 10.0,
}

const MATCH_SCENE: String = "res://match/match.tscn"
const HUB_SCENE: String = "res://hub/hub.tscn"
const HITCH_MS: int = 100
const ISOLATION_ENV: String = "PANOPTICON_NET_ISOLATED"
## The wire probe's packets: magic, u32 destination peer id, u32 sequence per destination, f64 send time (unix ms).
const PROBE_MAGIC: int = 0x5750
const PROBE_SIZE: int = 18
const WIRE_FLUSH_MS: int = 1000
## The keys the press check follows from the client's PRESS to the host's ruling: powers, cook, emotes, shove, jump.
const PRESS_BUTTONS: int = (MoveIntent.ALL_POWER_KEYS | MoveIntent.COOK | MoveIntent.EMOTE | MoveIntent.EMOTE_ALT
	| MoveIntent.SHOVE | MoveIntent.JUMP)
## --break=drop-*: the key whose first command the host throws away.
const DROPPED_KEYS: Dictionary[String, int] = {
	"drop-press": MoveIntent.ALL_POWER_KEYS, "drop-shove": MoveIntent.SHOVE, "drop-jump": MoveIntent.JUMP,
}

signal match_bound(authority: bool)
## A match, or a rematch of it, began on this machine.
signal match_started()
signal match_won()
signal host_lost()
## This machine is in another scene: "hub", "match", "other" or "none".
signal scene_changed(kind: String)

var o: Dictionary = {}
var session: NetSession = null
var lobby: NetLobby = null
var controller: MatchController = null
var net_match: NetMatch = null
var actor: ScriptedIntentSource = null
## Matches bound on this machine so far, and seconds since the current one bound (-1 before).
var matches_bound: int = 0
var finished: bool = false

var _t0: int = 0
var _log: FileAccess = null
var _scene_id: int = 0
var _scene_kind: String = ""
var _bound_ms: int = -1
var _bound_here: bool = false
var _last_sample_ms: int = 0
var _last_frame_ms: int = 0
var _state: String = ""
var _seen: Dictionary[String, String] = {}
var _lossy: LossyPeer = null
var _intents_in: int = 0
var _stalled: bool = false
var _host_lost_ms: int = -1
var _result_showing: bool = false
var _quit_done: bool = false
var _cats_seen: Dictionary[int, Array] = {}
var _broke: bool = false
var _hubs_bound: int = 0
## Freezes still to come: [scene kind ("match", "hub" or "any"), nth bind, seconds, ms].
var _freezes: Array[Array] = []
var _probe_seq: Dictionary[int, int] = {}
var _probe_last_ms: int = 0
var _wire_log: FileAccess = null
var _wire_flushed_ms: int = 0
var _wire_me: int = 0
## Host: the bodies whose rulings, knocks, holds and power ends are logged, by instance id.
var _ruled: Dictionary[int, bool] = {}
var _press_dropped: bool = false



func _init() -> void:
	_t0 = Time.get_ticks_msec()
	name = "SessionProbe"
	process_mode = Node.PROCESS_MODE_ALWAYS


## Call before anything is logged: opens --log and says what this process is.
func configure(options: Dictionary) -> void:
	o = options
	var path: String = String(o.get("log", ""))
	if not path.is_empty():
		_log = FileAccess.open(path, FileAccess.WRITE)
	line("BOOT role=%s name=%s pid=%d args=%s" % [String(o.role), String(o.name), OS.get_process_id(),
		" ".join(OS.get_cmdline_user_args())])
	if OS.get_environment(ISOLATION_ENV) != "1":
		# Never against the player's own user://: the launcher gives each peer a HOME and says so.
		push_error("SessionProbe: run through tools/net/run_session.sh (HOME is not isolated).")
		o["_error"] = true
	_parse_freezes()
	var wire_path: String = String(o.get("wire-log", ""))
	if not wire_path.is_empty():
		_wire_log = FileAccess.open(wire_path, FileAccess.WRITE)
	if o.has("_error"):
		line("END fail reason=bad-arguments")


## --freeze=<kind>[N]@<seconds>+<ms>[,...]: stop this whole process <ms> long, <seconds> after its N-th
## bound scene of that kind (match or hub; N defaults to 1), or after boot (any). --stall-* is one of these.
func _parse_freezes() -> void:
	var specs: PackedStringArray = String(o.get("freeze", "")).split(",", false)
	if float(o.get("stall-at", 0.0)) > 0.0:
		specs.append("match%d@%s+%d" % [int(o["stall-match"]), str(o["stall-at"]), int(o["stall-ms"])])
	if String(o["break"]) == "freeze-off":
		return
	var form: RegEx = RegEx.create_from_string("^(match|hub|any)(\\d*)@([\\d.]+)\\+(\\d+)$")
	for spec: String in specs:
		var m: RegExMatch = form.search(spec.strip_edges())
		if m == null:
			push_error("SessionProbe: bad --freeze item %s; expected kind[N]@seconds+ms" % spec)
			o["_error"] = true
			continue
		_freezes.append([m.get_string(1), int(m.get_string(2)) if not m.get_string(2).is_empty() else 1,
			float(m.get_string(3)), int(m.get_string(4))])


func is_server() -> bool:
	return String(o.get("role", "server")) == "server"


func get_scene_kind() -> String:
	return _scene_kind


func seconds() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


## Seconds since this machine's current match bound, or -1.
func match_seconds() -> float:
	return float(Time.get_ticks_msec() - _bound_ms) / 1000.0 if _bound_ms >= 0 else -1.0


func line(text: String) -> void:
	var stamped: String = "NL w=%d t=%.2f %s" % [int(Time.get_unix_time_from_system() * 1000.0), seconds(), text]
	print(stamped)
	if _log != null:
		_log.store_line(stamped)
		_log.flush()


## The host's match settings from the command line, onto the store the hub and the rules read.
func apply_settings() -> void:
	var settings: GameSettings = SettingsStore.instance().settings
	if int(o.prisoners) >= 0:
		settings.prisoner_count = int(o.prisoners)
	if int(o.ability) >= 0:
		settings.runner_ability = int(o.ability) as MatchRules.RunnerAbility
	if int(o.rounds) > 0:
		settings.rounds_to_win_match = int(o.rounds)
	if int(o.lives) > 0:
		settings.prisoner_lives = int(o.lives)
	var ghosts: String = String(o.ghosts)
	if not ghosts.is_empty():
		settings.ghosts_enabled = ghosts == "true" or ghosts == "1" or ghosts == "on" or ghosts == "yes"
	if bool(o.brawl):
		settings.tower_brawl = true
		settings.skip_opening_race = false
	line("SETTINGS prisoners=%d ability=%d rounds=%d lives=%d ghosts=%s brawl=%s skip_race=%s tower_seat=%d map=%s" % [
		settings.prisoner_count, int(settings.runner_ability), settings.rounds_to_win_match, settings.prisoner_lives,
		str(settings.ghosts_enabled), str(settings.tower_brawl), str(settings.skip_opening_race),
		settings.tower_seat_index, String(settings.map_id)])


## Watch [param net_session] from now on. Call once the session node exists.
func attach(net_session: NetSession) -> void:
	session = net_session
	lobby = session.lobby
	(session.multiplayer as SceneMultiplayer).peer_packet.connect(_on_probe_packet)
	get_tree().node_added.connect(_on_node_added)
	lobby.phase_changed.connect(func(phase: NetLobby.Phase) -> void:
		line("LOBBY phase=%s epoch=%d" % [String(NetLobby.Phase.keys()[phase]), lobby.get_epoch()]))
	lobby.roster_changed.connect(func() -> void: line("ROSTER " + lobby.describe().replace("\n", " | ")))
	lobby.rules_changed.connect(func() -> void:
		var rules: MatchRules = lobby.get_rules()
		if rules != null:
			if String(o["break"]) == "map" and not is_server():
				rules.map_id = &"bentham_ring" if rules.map_id == &"marble" else &"marble"
				line("BREAK map=%s" % String(rules.map_id))
			line("RULES " + describe_rules(rules)))
	lobby.join_refused.connect(func(peer: int, why: String) -> void: line("REFUSED peer=%d %s" % [peer, why]))
	lobby.seat_occupancy_changed.connect(func(seat: int, occupancy: LobbySeat.Occupancy) -> void:
		line("SEAT seat=s%d occupancy=%s" % [seat, String(LobbySeat.Occupancy.keys()[occupancy])]))
	session.flow.host_lost.connect(func() -> void: line("NET host_lost"))
	session.timed_out.connect(func(peer: int, state: NetLobby.PeerState) -> void:
		line("TIMEOUT peer=%d state=%s" % [peer, String(NetLobby.PeerState.keys()[state])]))
	session.session_ended.connect(func(failed: bool) -> void:
		line("SESSION ended failed=%s" % str(failed))
		if not is_server() and not finished:
			_host_lost_ms = Time.get_ticks_msec())


## Put this machine's sends through [LossyPeer] when a wire option asks for it. Call after host/join.
## With --wire-layer=socket the launcher's relay conditions the datagrams below ENet instead.
func condition_wire() -> void:
	var enet: ENetMultiplayerPeer = session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	if String(o["wire-layer"]) == "socket":
		line("WIRE layer=socket (tools/net/wire_relay.gd)")
		return
	var conditions: NetConditions = NetConditions.from_options(o, 7 if is_server() else 11 + OS.get_process_id() % 97)
	match String(o["break"]):
		"wire-off":
			conditions = NetConditions.new()
		"wire-weak":
			for knob: String in ["loss", "jitter_ms", "duplicate", "reorder", "burst_ms"]:
				conditions.set(knob, float(conditions.get(knob)) / 3.0)
	line("WIRE conditions %s" % conditions.describe())
	if not conditions.is_conditioned():
		return
	_lossy = LossyPeer.new(enet)
	_lossy.conditions = conditions
	session.multiplayer.multiplayer_peer = _lossy


static func describe_rules(rules: MatchRules) -> String:
	return "map=%s prisoners=%d ghosts=%s race=%s brawl=%s lives=%d rounds=%d ability=%d duration=%.1f cooldown=%.1f reload=%.2f shooter_win=%d runner_win=%d speed=%.1f slide=%s crouch=%s" % [
		String(rules.map_id), rules.prisoner_count, str(rules.has_ghosts()), str(rules.open_with_race),
		str(rules.open_with_tower_brawl), rules.prisoner_lives, rules.rounds_to_win_match, int(rules.runner_ability),
		rules.ability_duration_seconds, rules.ability_cooldown_seconds, rules.base_reload_seconds,
		int(rules.shooter_win_condition), int(rules.runner_win_condition), rules.guard_projectile_speed,
		str(rules.slide_enabled), str(rules.crouch_enabled)]


## Log the end and leave. [param ok] false is a run that did not do what it was asked.
func finish(ok: bool, reason: String) -> void:
	if finished:
		return
	finished = true
	_sample()
	if _wire_log != null:
		_wire_log.close()
		_wire_log = null
	var where: String = "phase=%s round=%d guard=%s outcome=%s" % [
		controller.get_phase_name(), controller.get_round_number(), _seat_of(controller.get_seat_participant()),
		controller.get_outcome_name()] if is_instance_valid(controller) else "phase=none"
	line("END %s reason=%s lobby=%s matches=%d %s" % ["ok" if ok else "fail", reason.replace(" ", "-"),
		String(NetLobby.Phase.keys()[lobby.get_phase()]) if lobby != null else "none", matches_bound, where])
	if _log != null:
		_log.close()
		_log = null


func _process(_delta: float) -> void:
	if session == null or finished:
		return
	var now: int = Time.get_ticks_msec()
	if _last_frame_ms > 0 and now - _last_frame_ms > HITCH_MS:
		line("HITCH ms=%d scene=%s" % [now - _last_frame_ms, _scene_kind])
	_last_frame_ms = now
	_watch_scene()
	_send_probes(now)
	_freeze_when_due()
	if _host_lost_ms >= 0 and now - _host_lost_ms > int(float(o["host-lost-exit"]) * 1000.0):
		_host_lost_ms = -1
		host_lost.emit()
	if not is_instance_valid(controller):
		return
	_install_actor()
	_break()
	_watch_state()
	_watch_bodies()
	_watch_result()
	if now - _last_sample_ms >= int(float(o.sample) * 1000.0):
		_last_sample_ms = now
		_sample()


## Whether this process should leave now, by --quit-at; the runner does the leaving.
func wants_quit() -> bool:
	if _quit_done or float(o["quit-at"]) < 0.0 or matches_bound != int(o["quit-match"]) or _scene_kind != "match":
		return false
	if match_seconds() < float(o["quit-at"]):
		return false
	_quit_done = true
	line("QUIT scripted mode=%s" % String(o["quit-mode"]))
	return true


# --- Scenes -------------------------------------------------------------------

func _watch_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or scene.get_instance_id() != _scene_id:
		_adopt(scene)


## A match or hub scene is hooked the moment its controller enters the tree, before it can emit.
func _on_node_added(node: Node) -> void:
	if node is MatchController and node.get_parent() != null and node.get_parent().get_node_or_null(^"NetMatch") is NetMatch:
		_adopt(node.get_parent())


func _adopt(scene: Node) -> void:
	var id: int = scene.get_instance_id() if scene != null else 0
	if id == _scene_id:
		return
	_scene_id = id
	controller = null
	net_match = null
	actor = null
	_bound_ms = -1
	_bound_here = false
	_seen.clear()
	_ruled.clear()
	_state = ""
	_result_showing = false
	_scene_kind = "none"
	if scene == null:
		line("SCENE kind=none")
		scene_changed.emit(_scene_kind)
		return
	var found: NetMatch = scene.get_node_or_null(^"NetMatch") as NetMatch
	var found_controller: MatchController = scene.get_node_or_null(^"MatchController") as MatchController
	_scene_kind = "other"
	if found != null and found_controller != null:
		_scene_kind = "hub" if found.hub_mode else "match"
	line("SCENE kind=%s path=%s epoch=%d" % [_scene_kind, scene.scene_file_path, lobby.get_epoch()])
	scene_changed.emit(_scene_kind)
	if _scene_kind == "other":
		return
	controller = found_controller
	net_match = found
	_hook_controller()
	net_match.match_bound.connect(_on_bound)
	if net_match.has_started():
		_on_bound(session.is_authority())
		if _scene_kind == "match":
			match_started.emit()


func _on_bound(authority: bool) -> void:
	if _bound_here:
		return
	_bound_here = true
	_bound_ms = Time.get_ticks_msec()
	if _scene_kind == "match":
		matches_bound += 1
	else:
		_hubs_bound += 1
	line("MATCH bound kind=%s epoch=%d authority=%s local_seat=s%d n=%d" % [_scene_kind, lobby.get_epoch(),
		str(authority), lobby.get_local_seat_index(), controller.get_participants_ref().size()])
	line("MATCH rules kind=%s epoch=%d %s" % [_scene_kind, lobby.get_epoch(), describe_rules(controller.get_rules())])
	match_bound.emit(authority)


func _hook_controller() -> void:
	controller.match_started.connect(func(count: int) -> void:
		_ev("match_started n=%d" % count)
		if _scene_kind == "match":
			match_started.emit())
	controller.race_started.connect(func() -> void: _ev("race_started"))
	controller.brawl_started.connect(func() -> void: _ev("brawl_started"))
	controller.brawler_out.connect(func(p: MatchParticipant, _throw: Vector3) -> void: _ev("brawl_out seat=%s" % _seat_of(p)))
	controller.round_started.connect(func() -> void:
		_ev("round_started round=%d guard=%s" % [controller.get_round_number(), _seat_of(controller.get_seat_participant())]))
	controller.seat_changed.connect(func(p: MatchParticipant, turns: int) -> void:
		_ev("seat_changed guard=%s turns=%d" % [_seat_of(p), turns]))
	controller.participant_converted.connect(func(p: MatchParticipant) -> void: _ev("converted seat=%s" % _seat_of(p)))
	controller.runner_ghosted.connect(func(p: MatchParticipant) -> void: _ev("ghosted seat=%s" % _seat_of(p)))
	controller.ghost_respawned.connect(func(p: MatchParticipant) -> void: _ev("ghost_respawned seat=%s" % _seat_of(p)))
	controller.ghost_caught.connect(func(g: MatchParticipant, c: MatchParticipant) -> void:
		_ev("ghost_caught ghost=%s caught=%s" % [_seat_of(g), _seat_of(c)]))
	controller.round_resolved.connect(func(outcome: MatchController.Outcome) -> void:
		_ev("round_resolved round=%d outcome=%s" % [controller.get_round_number(), String(MatchController.Outcome.keys()[outcome])]))
	controller.match_won.connect(func(p: MatchParticipant) -> void:
		_ev("match_won seat=%s" % _seat_of(p))
		match_won.emit())
	controller.participant_shoved.connect(func(shover: MatchParticipant, victim: MatchParticipant) -> void:
		_ev("shoved shover=%s victim=%s" % [_seat_of(shover), _seat_of(victim)]))
	controller.finisher_armed.connect(func(_weapon: Rifle) -> void: _ev("finisher seat=%s" % _seat_of(controller.get_finisher())))
	controller.kill_beat_started.connect(func(guard: MatchParticipant, _s: float, _throw: Vector3) -> void:
		_ev("kill_beat guard=%s" % _seat_of(guard)))
	var rifle: Rifle = controller.rifle
	if rifle != null:
		rifle.fired.connect(func(origin: Vector3, end_point: Vector3) -> void:
			line("RIFLE fired by=%s from=%.1f,%.1f,%.1f to=%.1f,%.1f,%.1f" % [_seat_of(controller.get_seat_participant()),
				origin.x, origin.y, origin.z, end_point.x, end_point.y, end_point.z]))
		rifle.target_hit.connect(func(collider: Node3D, _at: Vector3, _n: Vector3) -> void:
			line("RIFLE hit seat=%s" % _seat_of(controller.resolve_participant(collider))))
		rifle.missed.connect(func(end_point: Vector3) -> void:
			line("RIFLE missed at=%.1f,%.1f,%.1f" % [end_point.x, end_point.y, end_point.z]))


func _ev(text: String) -> void:
	line("EV %s kind=%s epoch=%d" % [text, _scene_kind, lobby.get_epoch()])


## The lobby seat a participant plays, "s<seat>", the one name every machine agrees on.
func _seat_of(p: MatchParticipant) -> String:
	if p == null or not is_instance_valid(net_match):
		return "none"
	return "s%d" % net_match._seat_index_of(p.index)


# --- The scripted human -------------------------------------------------------

func _install_actor() -> void:
	if actor != null or not _bound_here or net_match.get_local_link() == null:
		return
	var mine: MatchParticipant = controller.get_human_participant()
	if mine == null or mine.body == null:
		return
	actor = ScriptedIntentSource.new()
	actor.name = "Scripted"
	var hub: bool = _scene_kind == "hub"
	var mode: String = String(o.mode)
	actor.mode = ScriptedIntentSource.Mode.PLAY if mode == "play" else (
		ScriptedIntentSource.Mode.WALK if mode == "walk" else ScriptedIntentSource.Mode.IDLE)
	actor.device_only = hub
	actor.device_walk = hub and mode != "idle"
	actor.aim_enabled = bool(o.aim)
	actor.marksman = bool(o.marksman)
	actor.fire_at = float(o["press-fire"])
	actor.fire_every = float(o["fire-every"])
	actor.pitch_rate = float(o["pitch-rate"])
	actor.keys_wait = bool(o["keys-wait"])
	actor.mute_keys = String(o["break"]) == "mute-keys"
	actor.set_keys(String(o["hub-keys"]) if hub else String(o.keys))
	actor.key_pressed.connect(_on_key_pressed)
	actor.key_released.connect(func(key: String) -> void:
		line("RELEASE key=%s frame=%d" % [key, Engine.get_physics_frames()]))
	actor.role_changed.connect(func(role: String) -> void: line("ACTOR role=%s" % role))
	actor.trigger_pulled.connect(_on_trigger_pulled)
	actor.bind(controller, mine.body)
	net_match.add_child(actor)
	if not hub:
		net_match.set_local_source(actor)
	line("ACTOR installed kind=%s mode=%s seat=%s keys=%s" % [_scene_kind, mode, _seat_of(mine),
		String(o["hub-keys"]) if hub else String(o.keys)])


func _on_key_pressed(key: String, valid: bool, note: String) -> void:
	var mine: MatchParticipant = controller.get_human_participant()
	var power: RunnerPower = RunnerPower.of(mine.body) if mine != null and mine.body != null else null
	line("PRESS key=%s seat=%s valid=%d note=%s role=%s phase=%s sim=%d shown=%d frame=%d" % [key, _seat_of(mine), int(valid),
		note if not note.is_empty() else "ok", mine.get_role_name() if mine != null else "none", controller.get_phase_name(),
		int(mine != null and mine.body != null and _simulated(mine.body)),
		int(power.get_shown()) if power != null else -1, Engine.get_physics_frames()])


# --- Press accounting -----------------------------------------------------------
# A client logs each command it sends with a press or release in it (SENT, by sequence); the host logs
# what each command it ran made of its presses (RULE), and the host events that can overrule a press the
# client could not yet see: holds, knocks and power ends. tools/net/check_session.py joins them by sequence.

## Client: the sequence and the edges of a command this machine sent.
func _on_command_sent(seq: int, command: MoveIntent) -> void:
	if (command.pressed | command.released) & PRESS_BUTTONS == 0:
		return
	line("SENT seat=%s peer=%d seq=%d frame=%d pressed=%d released=%d" % [_seat_of(controller.get_human_participant()),
		session.get_local_peer_id(), seq, Engine.get_physics_frames(), command.pressed & PRESS_BUTTONS,
		command.released & PRESS_BUTTONS])


## Host: start logging what [param body] does with its commands, once per body.
func _watch_rulings(body: PlayerController) -> void:
	if _ruled.has(body.get_instance_id()):
		return
	_ruled[body.get_instance_id()] = true
	body.press_ruled.connect(func(buttons: int, ruling: StringName) -> void:
		var p: MatchParticipant = controller.resolve_participant(body) if is_instance_valid(controller) else null
		# A bot's rulings answer no press anyone logged.
		if buttons & PRESS_BUTTONS != 0 and p != null and p.is_human():
			var running: RunnerPower = RunnerPower.of(body)
			line("RULE seat=%s %s pressed=%d ruling=%s ability=%d" % [_seat_of_body(body), _command_of(body),
				buttons & PRESS_BUTTONS, ruling, int(running.get_active()) if running != null else 0]))
	body.launched.connect(func(velocity_vector: Vector3) -> void:
		line("KNOCK seat=%s frame=%d speed=%.1f" % [_seat_of_body(body), Engine.get_physics_frames(), velocity_vector.length()]))
	body.held_changed.connect(func(hold: bool) -> void:
		line("HOLD seat=%s frame=%d on=%d" % [_seat_of_body(body), Engine.get_physics_frames(), int(hold)]))
	var power: RunnerPower = RunnerPower.of(body)
	if power != null:
		power.ended.connect(func(which: MatchRules.RunnerAbility, reason: StringName) -> void:
			line("PWEND seat=%s %s ability=%d reason=%s" % [_seat_of_body(body), _command_of(body), int(which), reason]))


func _seat_of_body(body: PlayerController) -> String:
	return _seat_of(controller.resolve_participant(body)) if is_instance_valid(controller) else "none"


## The command [param body] is running: its peer and sequence off the wire (-1 from a local source), the
## physics frame, and whether it is one the client sent (0: a starved stream's released stand-in).
func _command_of(body: PlayerController) -> String:
	var link: PlayerNetLink = PlayerNetLink.of(body)
	var stream: CommandStream = body.intent_source as CommandStream
	return "peer=%d seq=%d frame=%d real=%d" % [link.owner_peer_id if link != null else 0,
		stream.get_ack() if stream != null else -1, Engine.get_physics_frames(),
		int(stream == null or stream.get_state() == CommandStream.State.RUNNING)]


## The actor pulled the trigger: on the host as on a client, its command carries the pull to the rifle.
func _on_trigger_pulled() -> void:
	var mine: MatchParticipant = controller.get_human_participant()
	var aimed: MatchParticipant = actor.get_aimed()
	line("TRIGGER seat=%s guard=%d aimed=%s" % [_seat_of(mine), int(mine != null and mine.is_shooter), _seat_of(aimed)])


# --- Watching -----------------------------------------------------------------

## The body moves on this machine: it runs here and the match is not holding it.
func _simulated(body: PlayerController) -> bool:
	return body.is_physics_processing() and not body.held


func _note(key: String, value: String, text: String) -> void:
	if _seen.get(key, "") == value:
		return
	_seen[key] = value
	line(text)


func _watch_state() -> void:
	var state: String = "kind=%s epoch=%d phase=%s round=%d guard=%s outcome=%s n=%d" % [_scene_kind, lobby.get_epoch(),
		controller.get_phase_name(), controller.get_round_number(), _seat_of(controller.get_seat_participant()),
		controller.get_outcome_name(), controller.get_participants_ref().size()]
	if state != _state:
		_state = state
		line("STATE " + state)


## What each body is drawing here, logged on the frame it changes: power, emote, ragdoll, role.
func _watch_bodies() -> void:
	var cats: int = 0
	for p: MatchParticipant in controller.get_participants_ref():
		if p.body == null:
			continue
		if session.is_authority():
			_watch_rulings(p.body)
		var seat: String = _seat_of(p)
		var power: RunnerPower = RunnerPower.of(p.body)
		var shown: int = int(power.get_shown()) if power != null else 0
		_note("power" + seat, str(shown), "POWER seat=%s ability=%d left=%.1f immune=%d camo=%d shield=%d decoy=%d cool=%.1f" % [
			seat, shown, power.get_remaining() if power != null else 0.0,
			int(power != null and power.is_hit_immune()), int(power != null and power.is_camouflaged()),
			int(power != null and power.get_shield() != null), int(power != null and power.get_decoy() != null),
			power.get_cooldown_remaining() if power != null else 0.0])
		var emote: int = (2 if p.body.is_emote_alt() else 1) if p.body.is_emoting() else 0
		_note("emote" + seat, str(emote), "EMOTE seat=%s on=%d alt=%d" % [seat, int(emote > 0), int(emote == 2)])
		_note("role" + seat, p.get_role_name(), "ROLE seat=%s role=%s kind=%s" % [seat, p.get_role_name(),
			"HUMAN" if p.is_human() else "AI"])
		var avatar: PrisonerAvatar = _avatar_of(p.body)
		if avatar != null and avatar._ragdoll != null:
			var rag: int = (1 if avatar._ragdoll.is_active() else 0) + (2 if avatar._ragdoll.is_flopping() else 0)
			_note("rag" + seat, str(rag), "RAG seat=%s active=%d flop=%d" % [seat, rag & 1, rag >> 1])
		if session.is_authority() and power != null:
			var cat: CatGrenade = power._cat
			if is_instance_valid(cat):
				cats += 1
				_cats_seen[p.index] = [cat.cooking, cat.fuse_left]
				_note("cat" + seat, str(cat.cooking), "CATHOST seat=%s held=1 cooking=%d fuse=%.2f" % [seat, int(cat.cooking), cat.fuse_left])
			elif _seen.get("cat" + seat, "gone") != "gone":
				var last: Array = _cats_seen.get(p.index, [false, 0.0])
				_note("cat" + seat, "gone", "CATHOST seat=%s held=0 was_cooking=%d fuse_was=%.2f" % [seat, int(last[0]), float(last[1])])
	var link: PlayerNetLink = net_match.get_local_link()
	if not session.is_authority() and link != null and not link.command_sent.is_connected(_on_command_sent):
		link.command_sent.connect(_on_command_sent)
	if not session.is_authority():
		var relay: CatGrenadeRelay = CatGrenadeRelay.of(session)
		cats = relay._shown.size() if relay != null else 0
	_note("cats", str(cats), "CATS drawn=%d" % cats)


func _avatar_of(body: PlayerController) -> PrisonerAvatar:
	for child: Node in body.get_children():
		if child is PrisonerAvatar:
			return child as PrisonerAvatar
	return null


func _watch_result() -> void:
	var screen: MatchResultScreen = controller.get_parent().get_node_or_null(^"ResultScreen") as MatchResultScreen
	if screen == null or screen.is_showing() == _result_showing:
		return
	_result_showing = screen.is_showing()
	var votes: Label = screen.get_node_or_null(^"%RematchVotes") as Label
	line("RESULT showing=%d phase=%s votes=%s" % [int(_result_showing), controller.get_phase_name(),
		votes.text.replace(" ", "_") if votes != null and votes.visible else "-"])


## Freeze this whole process when a --freeze item comes due, the way a hitching machine does.
func _freeze_when_due() -> void:
	for i: int in _freezes.size():
		var item: Array = _freezes[i]
		var kind: String = item[0]
		var since: float = seconds() if kind == "any" else match_seconds()
		if kind != "any" and (_scene_kind != kind or (matches_bound if kind == "match" else _hubs_bound) != int(item[1])):
			continue
		if since < float(item[2]):
			continue
		_freezes.remove_at(i)
		line("STALL ms=%d scene=%s" % [int(item[3]), _scene_kind])
		OS.delay_msec(int(item[3]))
		_last_frame_ms = Time.get_ticks_msec()
		line("STALL over")
		return


# --- The wire probe ----------------------------------------------------------------

## A small unreliable stream to every peer this machine talks to, through the same conditioned wire as
## the game's packets. Both ends write --wire-log ("me id", "s to seq sent_ms", "r from to seq sent_ms recv_ms"),
## and tools/net/check_session.py measures what the wire really did from the two.
func _send_probes(now: int) -> void:
	var hz: float = float(o["wire-probe-hz"])
	if _wire_log == null or hz <= 0.0 or now - _probe_last_ms < int(1000.0 / hz) or not session.is_established():
		return
	_probe_last_ms = now
	if _wire_me != session.get_local_peer_id():
		_wire_me = session.get_local_peer_id()
		_wire_log.store_line("me %d" % _wire_me)
	var api: SceneMultiplayer = session.multiplayer as SceneMultiplayer
	var targets: PackedInt32Array = api.get_peers() if is_server() else PackedInt32Array([NetTransport.AUTHORITY_PEER_ID])
	var sent_ms: float = Time.get_unix_time_from_system() * 1000.0
	for peer: int in targets:
		var seq: int = _probe_seq.get(peer, 0)
		_probe_seq[peer] = seq + 1
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(PROBE_SIZE)
		bytes.encode_u16(0, PROBE_MAGIC)
		bytes.encode_u32(2, peer)
		bytes.encode_u32(6, seq)
		bytes.encode_double(10, sent_ms)
		api.send_bytes(bytes, peer, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 0)
		_wire_log.store_line("s %d %d %.3f" % [peer, seq, sent_ms])
	if now - _wire_flushed_ms >= WIRE_FLUSH_MS:
		_wire_flushed_ms = now
		_wire_log.flush()


func _on_probe_packet(from: int, bytes: PackedByteArray) -> void:
	if _wire_log == null or bytes.size() != PROBE_SIZE or bytes.decode_u16(0) != PROBE_MAGIC:
		return
	_wire_log.store_line("r %d %d %d %.3f %.3f" % [from, bytes.decode_u32(2), bytes.decode_u32(6),
		bytes.decode_double(10), Time.get_unix_time_from_system() * 1000.0])


## --break: deliberate faults on this one machine, to prove tools/net/check_session.py sees them.
func _break() -> void:
	var kind: String = String(o["break"])
	if kind.is_empty() or _scene_kind != "match" or match_seconds() < float(o["break-at"]):
		return
	var mine: MatchParticipant = controller.get_human_participant()
	match kind:
		"freeze":
			if mine != null and mine.body != null:
				mine.body.set_physics_process(false)
		"teleport":
			for p: MatchParticipant in controller.get_participants_ref():
				if p != mine and p.body != null:
					p.body.global_position.y = 400.0
					break
		"error":
			if not _broke:
				push_error("SessionProbe: deliberate error (--break=error)")
		"state":
			if not _broke and not is_server():
				controller.net_resolve(MatchController.Outcome.LOSS)
		"die":
			OS.kill(OS.get_process_id())
		"event":
			if not _broke and not is_server():
				controller.round_started.emit()
		"emote", "role":
			for p: MatchParticipant in controller.get_participants_ref():
				if p != mine and p.body != null and p.is_running:
					if kind == "emote":
						p.body.net_emote = 1
					else:
						p.is_running = false
						p.is_ghost = true
					break
		"hide-world":
			get_viewport().disable_3d = true
		"flood":
			if not _broke:
				for i: int in 60:
					push_error("Invalid packet received. Requested node was not found.")
		"leave":
			if not _broke:
				session.leave()
	if not _broke:
		_broke = true
		line("BREAK kind=%s" % kind)


func _tick() -> int:
	var replicator: NetReplicator = session.replicator
	return replicator.get_tick() if session.is_authority() else replicator.get_latest_tick()


func _sample() -> void:
	if not is_instance_valid(controller) or not is_instance_valid(net_match):
		return
	var parts: PackedStringArray = PackedStringArray()
	for p: MatchParticipant in controller.get_participants_ref():
		var b: PlayerController = p.body
		if b == null or not b.is_inside_tree():
			continue
		var at: Vector3 = b.global_position
		var power: RunnerPower = RunnerPower.of(b)
		parts.append("%s:%s:%.2f,%.2f,%.2f:v%.1f:sim%d:vis%d:fl%d:pw%d:lay%d:yaw%.2f:clip-%s" % [_seat_of(p), p.get_role_name(),
			at.x, at.y, at.z, b.velocity.length(), int(_simulated(b)), int(b.is_visible_in_tree()),
			int(b.is_on_floor()), int(power.get_shown()) if power != null else 0, b.collision_layer, b.rotation.y, _clip_of(b)])
	line("POS tick=%d %s paused=%d 3d=%d | %s" % [_tick(), _state, int(get_tree().paused),
		int(not get_viewport().disable_3d), " | ".join(parts)])
	var mine: MatchParticipant = controller.get_human_participant()
	if mine != null and mine.body != null:
		var source: IntentSource = mine.body.intent_source
		line("LOCAL seat=%s role=%s sim=%d hold=%.1f settle=%d predicted=%d src=%s result=%d vel=%.1f actor=%s" % [
			_seat_of(mine), mine.get_role_name(), int(_simulated(mine.body)), mine.respawn_hold_remaining,
			mine.ghost_settle_frames, int(mine.body.net_predicted),
			(source.get_script() as Script).get_global_name() if source != null and source.get_script() != null else "none",
			int(_result_showing), mine.body.velocity.length(), actor.get_role_name() if actor != null else "none"])
	if session.is_authority():
		for node: Node in net_match.get_children():
			var link: PlayerNetLink = node as PlayerNetLink
			if link != null and not link.intent_received.is_connected(_on_intent_in):
				link.intent_received.connect(_on_intent_in)
	line("WIRE sent=%d dropped=%d intents_in=%d snap_tick=%d" % [_lossy.sent if _lossy != null else -1,
		_lossy.dropped if _lossy != null else -1, _intents_in, session.replicator.get_latest_tick()])
	if _lossy != null:
		var stats: Dictionary = _lossy.conditions.stats()
		line("WIRE link offered=%d lost=%d duplicated=%d held=%d spells=%d spell_ms=%.0f" % [int(stats.get("offered", 0)),
			int(stats.get("lost", 0)), int(stats.get("duplicated", 0)), int(stats.get("held", 0)),
			int(stats.get("spells", 0)), float(stats.get("spell_ms", 0.0))])


func _on_intent_in(peer: int, _tick_number: int) -> void:
	_intents_in += 1
	var kind: String = String(o["break"])
	if DROPPED_KEYS.has(kind) and not _press_dropped and _scene_kind == "match" and match_seconds() >= float(o["break-at"]):
		_drop_press(session.replicator._streams.get(peer, null) as CommandStream, DROPPED_KEYS[kind], kind)


## --break=drop-*: the host throws away the first command a client pressed [param keys] in, as a stream
## past its resend cap does (the skip in [method CommandStream.receive]), and runs on from the next.
func _drop_press(stream: CommandStream, keys: int, kind: String) -> void:
	if stream == null:
		return
	var buttons: int = stream._last.buttons
	for i: int in stream.get_backlog():
		var seq: int = stream._last_run + 1 + i
		var command: MoveIntent = stream._ring[seq % CommandStream.RING]
		if (command.buttons | command.pressed) & ~buttons & keys != 0:
			for skipped: int in range(stream._last_run + 1, seq + 1):
				stream._held[skipped % CommandStream.RING] = -1
			stream._last_run = seq
			_press_dropped = true
			line("BREAK kind=%s seq=%d" % [kind, seq])
			return
		buttons = command.buttons


func _clip_of(body: PlayerController) -> String:
	var avatar: PrisonerAvatar = _avatar_of(body)
	if avatar == null or avatar.animation == null:
		return "none"
	var clip: String = String(avatar.animation.current_animation)
	return clip.replace(" ", "_") if not clip.is_empty() else "none"
