extends Node

## Drives one peer of a real session in the EXPORTED build: main menu -> multiplayer -> hub -> each
## --maps wedge in turn -> result -> hub. An autoload named by an override.cfg beside the exe (a release
## template takes no --script), so the shipped pck is untouched; boot_from_source.gd adds it to a source run.
##
## --role=server|client --port --name --humans (host waits for this many) --maps=bentham_ring,marble
## --loops=1 --hub-seconds --match-seconds --prisoners --guard=<seat, -1 race> --limit
## --act=keys|aim|shove|idle: keys runs --program on the real key actions while walking; aim turns the
##   view onto the nearest runner and fires; shove (host) stands behind each client in turn and shoves.
## --program: steps split by ';'. '3h4' hold key 3 four seconds, '3t' tap, 'j' jump, 's' shove,
##   'e' interact, 'b'/'n' emotes, 'w1.5' wait. Loops for the whole session, hub included.
## --zap (host): the rifle's hit lands on every armor-locked body, every 0.6 s.
## --stall=s freezes this process once, a second into every match; --load-stall overrides the net setting.
## --phase: seconds the program start is held back. --mute=false keeps the game's volume.

const MENU_SCENE: String = "res://ui/main_menu.tscn"
const HUB_SCENE: String = "res://hub/hub.tscn"
const MATCH_SCENE: String = "res://match/match.tscn"
const TAP_SECONDS: float = 0.06
## Faster upward than anything the game throws a body with.
const FLUNG_SPEED: float = 40.0
const KEYS: Dictionary = {
	"1": &"ability_1", "2": &"ability_2", "3": &"ability_3", "4": &"ability_4", "5": &"ability_5",
	"j": &"jump", "s": &"shove", "e": &"interact", "b": &"emote", "n": &"emote_alt",
}

var _o: Dictionary = {}
var _t0: int = 0
var _menu: Node = null
var _screen: MultiplayerScreen = null
var _session: NetSession = null
var _lobby: NetLobby = null
var _joined: bool = false
var _scene: String = ""
var _scene_ms: int = 0
var _maps: PackedStringArray = PackedStringArray()
var _started: int = 0
var _matches_seen: int = 0
var _hub_visits: int = 0
var _starting: bool = false
var _won: bool = false
var _result_ms: int = -1
var _finished: bool = false
var _last_pos_ms: int = 0
var _shown: Dictionary = {}
var _hooked: Node = null
var _steps: PackedStringArray = PackedStringArray()
var _step: int = -1
var _step_until: float = 0.0
var _step_key: StringName = &""
var _aim_source: IntentSource = null
var _next_shove: float = 0.0
var _shove_turn: int = 0
var _session_over: bool = false
var _retries: int = 0
var _stall_at_ms: int = 0
var _zap_ms: int = 0
var _flung_ms: Dictionary = {}
var _trails: Dictionary = {}
var _last_physics_ms: int = 0
var _last_frame_ms: int = 0
var _retry_at: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_o = _arguments({
		"role": "server", "address": "127.0.0.1", "port": 27960, "name": "", "humans": 2,
		"maps": "bentham_ring,marble", "loops": 1, "hub-seconds": 8.0, "match-seconds": 60.0,
		"prisoners": 0, "guard": -2, "limit": 600.0, "act": "keys", "program": "", "phase": 0.0,
		"mute": true, "fire-every": 1.2, "width": 0, "height": 0, "zap": false, "stall": 0.0, "load-stall": 0.0, "peer-timeout": 0.0,
	})
	_t0 = Time.get_ticks_msec()
	_maps = String(_o.maps).split(",", false)
	_steps = String(_o.program).split(";", false)
	_step_until = float(_o.phase) + 4.0
	_boot()


func _arguments(defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	for argument: String in OS.get_cmdline_user_args():
		var body: String = argument.trim_prefix("--")
		var split: int = body.find("=")
		var key: String = body if split < 0 else body.substr(0, split)
		var raw: String = "true" if split < 0 else body.substr(split + 1)
		if not defaults.has(key):
			_line("ARG unknown %s" % argument)
			continue
		match typeof(defaults[key]):
			TYPE_INT: out[key] = int(raw)
			TYPE_FLOAT: out[key] = float(raw)
			TYPE_BOOL: out[key] = raw == "true"
			_: out[key] = raw
	return out


func _line(text: String) -> void:
	print("DRV t=%.2f %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])


## The silence ceiling in force and each ENet peer's state and round trip, for reading a drop.
func _wire() -> String:
	if _session == null or _session.transport == null:
		return ""
	var text: String = ""
	if _session.transport.has_method(&"get_silence_ceiling_seconds"):
		text += " ceiling=%.0f" % float(_session.transport.call(&"get_silence_ceiling_seconds"))
	var enet: ENetMultiplayerPeer = _session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.host != null:
		for packet_peer: ENetPacketPeer in enet.host.get_peers():
			text += " peer(state=%d rtt=%d last_rtt=%d loss=%d)" % [int(packet_peer.get_state()),
				int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
				int(packet_peer.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)),
				int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))]
	return text


func _is_server() -> bool:
	return String(_o.role) == "server"


func _seconds() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _boot() -> void:
	var store: SettingsStore = SettingsStore.instance()
	var settings: GameSettings = store.settings
	if bool(_o.mute):
		settings.master_volume = 0.0
	if int(_o.width) > 0:
		settings.display_mode = GameSettings.DisplayMode.WINDOWED
		settings.resolution = Vector2i(int(_o.width), int(_o.height))
	if _is_server():
		if int(_o.prisoners) > 0:
			settings.prisoner_count = int(_o.prisoners)
		if int(_o.guard) >= -1:
			settings.skip_opening_race = int(_o.guard) >= 0
			settings.tower_seat_index = maxi(int(_o.guard), 0)
	if not String(_o.name).is_empty():
		settings.player_name = String(_o.name)
	store.save_to_disk()
	store.apply_all(true)
	_line("BOOT version=%s role=%s act=%s display=%s video=%s audio=%s" % [
		str(ProjectSettings.get_setting("application/config/version", "")), String(_o.role), String(_o.act),
		DisplayServer.get_name(), RenderingServer.get_video_adapter_name(), AudioServer.get_driver_name()])


## Through the menu's own Multiplayer button and the screen's host/join, as a player goes.
func _enter_multiplayer() -> void:
	_menu = get_tree().current_scene
	_menu.call(&"open_multiplayer")
	_screen = _menu.get_node("%MultiplayerScreen") as MultiplayerScreen
	if not String(_o.name).is_empty():
		_screen.set_player_name(String(_o.name))
	_session = _screen.ensure_session()
	if float(_o["load-stall"]) > 0.0:
		_session.get_settings().set(&"load_stall_seconds", float(_o["load-stall"]))
	if float(_o["peer-timeout"]) > 0.0:
		_session.get_settings().peer_timeout_seconds = float(_o["peer-timeout"])
	_lobby = _session.lobby
	_session.session_ended.connect(func(failed: bool) -> void:
		_line("SESSION ended failed=%s%s" % [str(failed), _wire()])
		_session_over = true)
	_lobby.roster_changed.connect(func() -> void: _line("ROSTER " + _lobby.describe().replace("\n", " | ")))
	_lobby.phase_changed.connect(func(phase: NetLobby.Phase) -> void:
		_line("LOBBY phase=%s" % String(NetLobby.Phase.keys()[phase])))
	if _is_server():
		_screen.set_host_port(int(_o.port))
		_line("HOST %s" % error_string(_screen.start_hosting()))
	else:
		_screen.set_join_target(String(_o.address), int(_o.port))
		_line("JOIN %s" % error_string(_screen.join_game()))
	_joined = true


func _process(_delta: float) -> void:
	if _finished:
		return
	var frame_ms: int = Time.get_ticks_msec()
	if _last_frame_ms > 0 and frame_ms - _last_frame_ms > 250:
		_line("HITCH %d ms scene=%s%s" % [frame_ms - _last_frame_ms, _scene.get_file(), _wire()])
	_last_frame_ms = frame_ms
	var scene_node: Node = get_tree().current_scene
	var scene: String = scene_node.scene_file_path if scene_node != null else ""
	if scene != _scene:
		_scene = scene
		_scene_ms = Time.get_ticks_msec()
		_line("SCENE %s" % scene)
		_on_scene(scene)
	if scene == MENU_SCENE and not _joined:
		_enter_multiplayer()
		return
	var now: float = _seconds()
	if _session_over and _hub_visits == 0 and not _is_server() and _retries < 15:
		# The host was still loading; a player presses Join again.
		_session_over = false
		_retries += 1
		_retry_at = now + 2.0
		return
	if _retry_at > 0.0 and now >= _retry_at:
		_retry_at = 0.0
		_line("JOIN retry %d %s" % [_retries, error_string(_screen.join_game())])
	if _session_over:
		# Whole only if the host ended it from the hub after the last map; anything sooner is a drop.
		var whole: bool = _hub_visits > _maps.size() * int(_o.loops) and _scene == HUB_SCENE
		_end("ok" if whole and not _is_server() else "session-lost", 0 if whole else 3)
		return
	if now > float(_o.limit):
		_end("timeout", 2)
		return
	if scene_node == null:
		return
	if _stall_at_ms > 0 and Time.get_ticks_msec() >= _stall_at_ms:
		# This whole process frozen once, the way a first-run shader compile freezes it.
		_stall_at_ms = 0
		_line("STALL %.1f s" % float(_o.stall))
		OS.delay_msec(int(float(_o.stall) * 1000.0))
	var net: NetMatch = scene_node.get_node_or_null(^"NetMatch") as NetMatch
	if net != null:
		_watch(scene_node, net)
		_act(scene_node, net, now)
	if _is_server():
		if scene == HUB_SCENE:
			_drive_hub(scene_node)
		elif scene == MATCH_SCENE:
			_drive_match(scene_node)


func _on_scene(scene: String) -> void:
	_hooked = null
	_aim_source = null
	_shown.clear()
	if scene == HUB_SCENE:
		_hub_visits += 1
		_starting = false
	elif scene == MATCH_SCENE:
		_matches_seen += 1
		_stall_at_ms = Time.get_ticks_msec() + 1000 if float(_o.stall) > 0.0 else 0
		_won = false
		_result_ms = -1


func _end(verdict: String, code: int) -> void:
	_finished = true
	_release_all()
	_line("END %s matches=%d hub_visits=%d" % [verdict, _matches_seen, _hub_visits])
	if _session != null and is_instance_valid(_session):
		_session.leave()
	get_tree().quit(code)


# --- Host flow ----------------------------------------------------------------

func _humans() -> int:
	var count: int = 0
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if seat.is_human():
			count += 1
	return count


func _drive_hub(scene_node: Node) -> void:
	var in_hub: float = (Time.get_ticks_msec() - _scene_ms) / 1000.0
	if _starting or in_hub < float(_o["hub-seconds"]) or _humans() < int(_o.humans):
		return
	if _started >= _maps.size() * int(_o.loops):
		_end("ok", 0)
		return
	var hub: HubLobby = null
	for node: Node in scene_node.find_children("*", "Node", true, false):
		if node is HubLobby:
			hub = node as HubLobby
	if hub == null or hub.player == null:
		return
	var want: String = _maps[_started % _maps.size()]
	for child: Node in hub.wedges_root.get_children():
		var wedge: MapWedge = child as MapWedge
		if wedge == null or not wedge.is_decided() or String(wedge.map_id) != want:
			continue
		if hub.get_wedge_here() != wedge:
			hub.player.global_position = (wedge.get_node("Dais") as Node3D).global_position + Vector3.UP * 0.5
			hub.player.velocity = Vector3.ZERO
			return
		_starting = true
		_started += 1
		_release_all()
		var press: InputEventAction = InputEventAction.new()
		press.action = &"interact"
		press.pressed = true
		Input.parse_input_event(press)
		_line("START interact on wedge=%s" % want)
		return
	_line("START no decided wedge for %s" % want)
	_end("no-wedge", 4)


func _drive_match(scene_node: Node) -> void:
	var controller: MatchController = scene_node.get_node_or_null(^"MatchController") as MatchController
	var screen: MatchResultScreen = scene_node.get_node_or_null(^"ResultScreen") as MatchResultScreen
	var in_match: float = (Time.get_ticks_msec() - _scene_ms) / 1000.0
	if not _won and controller != null and in_match > float(_o["match-seconds"]):
		_won = true
		if controller.get_phase() != MatchController.Phase.MATCH_OVER and not controller.get_participants().is_empty():
			controller.call(&"_win_match", controller.get_participants()[0])
			_line("WIN forced")
	if bool(_o.zap) and controller != null and controller.rifle != null and Time.get_ticks_msec() - _zap_ms > 600:
		_zap_ms = Time.get_ticks_msec()
		_zap_locked(scene_node, controller)
	if screen != null and screen.is_showing() and _result_ms < 0:
		_result_ms = Time.get_ticks_msec()
		_line("RESULT showing")
	if _result_ms > 0 and Time.get_ticks_msec() - _result_ms > 4000:
		_result_ms = -2
		if not screen.has_method(&"_on_hub_all_pressed"):
			# A build from before the host could take everyone to the hub: the session ends at the result.
			_end("ok", 0)
			return
		_line("BACK hub-all")
		screen.call(&"_on_hub_all_pressed")


## The rifle's own hit signal on every armor-locked body: the refusal on the host, the hit shown on every client.
func _zap_locked(scene_node: Node, controller: MatchController) -> void:
	var net: NetMatch = scene_node.get_node_or_null(^"NetMatch") as NetMatch
	if net == null:
		return
	for child: Node in net.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link == null or link.controller == null or not link.controller.is_inside_tree():
			continue
		var power: RunnerPower = RunnerPower.of(link.controller)
		if power == null or not power.is_hit_immune():
			continue
		_line("ZAP seat=%d" % link.seat_index)
		controller.rifle.target_hit.emit(link.controller, link.controller.global_position + Vector3.UP * 0.9, Vector3.UP)


# --- What this peer sees ------------------------------------------------------

func _hook(scene_node: Node) -> void:
	_hooked = scene_node
	var controller: MatchController = scene_node.get_node_or_null(^"MatchController") as MatchController
	if controller == null:
		return
	controller.match_started.connect(func(count: int) -> void: _line("EV match_started participants=%d map=%s" % [
		count, String(controller.get_rules().map_id) if controller.get_rules() != null else "?"]))
	controller.round_started.connect(func() -> void: _line("EV round_started round=%d" % controller.get_round_number()))
	controller.round_resolved.connect(func(outcome: MatchController.Outcome) -> void:
		_line("EV round_resolved outcome=%s" % String(MatchController.Outcome.keys()[outcome])))
	controller.match_won.connect(func(p: MatchParticipant) -> void: _line("EV match_won who=%d" % (p.index if p != null else -1)))
	# By name: an older build this driver is pointed at may not have them.
	if controller.has_signal(&"participant_shoved"):
		controller.connect(&"participant_shoved", func(a: MatchParticipant, b: MatchParticipant) -> void:
			_line("EV shoved by=%d victim=%d" % [a.index if a != null else -1, b.index if b != null else -1]))
	if controller.has_signal(&"kill_beat_started"):
		controller.connect(&"kill_beat_started", func(g: MatchParticipant, _s: float, _throw: Vector3) -> void:
			_line("EV kill_beat guard=%d" % (g.index if g != null else -1)))
	if controller.rifle != null:
		controller.rifle.fired.connect(func(_from: Vector3, _to: Vector3) -> void: _line("RIFLE fired"))
		controller.rifle.target_hit.connect(func(collider: Node3D, _at: Vector3, _n: Vector3) -> void:
			var hit: MatchParticipant = controller.resolve_participant(collider)
			var power: RunnerPower = RunnerPower.of(hit.body) if hit != null and hit.body != null else null
			_line("RIFLE hit=%d shown=%d" % [hit.index if hit != null else -1, int(power.get_shown()) if power != null else 0]))


func _watch(scene_node: Node, net: NetMatch) -> void:
	if _hooked != scene_node:
		_hook(scene_node)
	var now: int = Time.get_ticks_msec()
	var sample: bool = now - _last_pos_ms > 2000
	var parts: PackedStringArray = PackedStringArray()
	for child: Node in net.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link == null or link.controller == null or not link.controller.is_inside_tree():
			continue
		var body: PlayerController = link.controller
		var power: RunnerPower = RunnerPower.of(body)
		var shown: int = int(power.get_shown()) if power != null else 0
		if shown != int(_shown.get(link.seat_index, 0)):
			_shown[link.seat_index] = shown
			_line("POWER seat=%d shown=%d left=%.1f locked=%s floor=%s" % [link.seat_index, shown,
				power.get_remaining(), str(body.movement_locked), str(body.is_on_floor())])
		if sample:
			var at: Vector3 = body.global_position
			parts.append("s%d(%.1f,%.1f,%.1f)%s%s%s" % [link.seat_index, at.x, at.y, at.z,
				"G" if body.is_guard else "", "L" if body.movement_locked else "", "" if body.is_on_floor() else "^"])
	if sample:
		_last_pos_ms = now
		var controller: MatchController = scene_node.get_node_or_null(^"MatchController") as MatchController
		_line("POS %s phase=%s fps=%d %s" % [_scene.get_file(),
			controller.get_phase_name() if controller != null else "?", int(Engine.get_frames_per_second()), " ".join(parts)])


## Every body's vertical speed, each tick: a body thrown upward faster than any jump, pad or shove is logged once.
func _physics_process(_delta: float) -> void:
	var scene_node: Node = get_tree().current_scene
	var net: NetMatch = scene_node.get_node_or_null(^"NetMatch") as NetMatch if scene_node != null else null
	if net == null:
		return
	var now: int = Time.get_ticks_msec()
	for child: Node in net.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link == null or link.controller == null or not link.controller.is_inside_tree():
			continue
		var body: PlayerController = link.controller
		var trail: PackedStringArray = _trails.get(link.seat_index, PackedStringArray())
		var under: String = ""
		for i: int in body.get_slide_collision_count():
			var c: KinematicCollision3D = body.get_slide_collision(i)
			var who: Node = c.get_collider() as Node
			under += "%s%s " % [str(who.get_path()) if who != null else "?", str(c.get_collider_velocity())]
		trail.append("f%d ms=%d y=%.3f vy=%.2f floor=%s plat=%s layer=%d mask=%d under=%s" % [Engine.get_physics_frames(), now,
			body.global_position.y, body.velocity.y, str(body.is_on_floor()), str(body.get_platform_velocity()),
			body.collision_layer, body.collision_mask, under])
		if trail.size() > 10:
			trail.remove_at(0)
		_trails[link.seat_index] = trail
		if body.velocity.y < FLUNG_SPEED or now - int(_flung_ms.get(link.seat_index, -5000)) < 3000:
			continue
		for entry: String in trail:
			_line("TRAIL seat=%d %s" % [link.seat_index, entry])
		_flung_ms[link.seat_index] = now
		var touching: PackedStringArray = PackedStringArray()
		for i: int in body.get_slide_collision_count():
			var hit: KinematicCollision3D = body.get_slide_collision(i)
			touching.append("%s v=%s" % [str(hit.get_collider()), str(hit.get_collider_velocity())])
		_line("FLUNG seat=%d guard=%s at=%s velocity=%s platform=%s floor=%s sim=%s frame_ms=%d touching=[%s]" % [
			link.seat_index, str(body.is_guard), str(body.global_position), str(body.velocity),
			str(body.get_platform_velocity()), str(body.is_on_floor()), str(body.is_physics_processing()),
			now - _last_physics_ms, " | ".join(touching)])
	_last_physics_ms = now


# --- What this peer does ------------------------------------------------------

func _act(scene_node: Node, net: NetMatch, now: float) -> void:
	var act: String = String(_o.act)
	var link: PlayerNetLink = net.get_local_link()
	var mine: PlayerController = link.controller if link != null else null
	if mine == null:
		return
	if act == "aim" and _scene == MATCH_SCENE:
		if _aim_source == null and net.has_started():
			_aim_source = _make_aim_source(scene_node, mine)
			net.add_child(_aim_source)
			net.set_local_source(_aim_source)
			_line("ACT aim source installed guard=%s" % str(mine.is_guard))
		return
	if act == "idle":
		return
	_walk(now)
	if act == "shove" and _is_server() and now >= _next_shove:
		_shove_next(net, mine, now)
	if act == "keys" or act == "shove":
		_run_program(now)


func _walk(now: float) -> void:
	var phase: int = int(now / 1.5) % 4
	_hold(&"move_forward", phase != 2)
	_hold(&"move_left", phase == 1)
	_hold(&"move_right", phase == 3)
	_hold(&"move_back", phase == 2)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(6.0, sin(now) * 3.0)
	Input.parse_input_event(motion)


func _hold(action: StringName, on: bool) -> void:
	if not InputMap.has_action(action):
		return
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _release_all() -> void:
	for action: StringName in [&"move_forward", &"move_left", &"move_right", &"move_back"]:
		_hold(action, false)
	for key: String in KEYS:
		_hold(KEYS[key], false)
	_hold(WeaponActions.FIRE, false)
	_step_key = &""


func _run_program(now: float) -> void:
	if _steps.is_empty() or now < _step_until:
		return
	if _step_key != &"":
		_hold(_step_key, false)
		_step_key = &""
		# One frame released, so the next press of the same key is a fresh edge.
		_step_until = now + 0.04
		return
	_step = (_step + 1) % _steps.size()
	var token: String = _steps[_step]
	var key: String = token.substr(0, 1)
	var rest: String = token.substr(1)
	if key == "w":
		_step_until = now + float(rest)
		return
	if not KEYS.has(key):
		_line("STEP bad token %s" % token)
		return
	_step_key = KEYS[key]
	_hold(_step_key, true)
	_step_until = now + (float(rest.substr(1)) if rest.begins_with("h") else TAP_SECONDS)
	_line("STEP %d %s scene=%s" % [_step, token, _scene.get_file()])


## The host stands behind the next human client's body and shoves it.
func _shove_next(net: NetMatch, mine: PlayerController, now: float) -> void:
	_next_shove = now + 3.0
	var others: Array[PlayerController] = []
	for child: Node in net.get_children():
		var link: PlayerNetLink = child as PlayerNetLink
		if link != null and link.controller != null and link.controller != mine and link.owner_peer_id > 1:
			others.append(link.controller)
	if others.is_empty() or mine.is_guard:
		return
	_shove_turn += 1
	var theirs: PlayerController = others[_shove_turn % others.size()]
	var ahead: Vector3 = -theirs.global_transform.basis.z
	mine.global_position = theirs.global_position - Vector3(ahead.x, 0.0, ahead.z).normalized() * 1.0
	mine.velocity = Vector3.ZERO
	mine.look_at(theirs.global_position, Vector3.UP)
	if _step_key != &"":
		_hold(_step_key, false)
	Input.action_press(&"shove")
	_step_key = &"shove"
	_step_until = now + TAP_SECONDS
	_line("SHOVE try at locked=%s" % str(theirs.movement_locked))


func _make_aim_source(scene_node: Node, mine: PlayerController) -> IntentSource:
	var source: AimSource = AimSource.new()
	source.name = "DriverAim"
	source.body = mine
	source.controller = scene_node.get_node_or_null(^"MatchController") as MatchController
	source.fire_every = float(_o["fire-every"])
	source.drives_action = _is_server()
	return source


## A guard that faces the nearest runner it can see, a locked one first, and fires on a clock.
class AimSource:
	extends IntentSource

	var body: PlayerController = null
	var controller: MatchController = null
	var fire_every: float = 1.2
	const HOLD_SECONDS: float = 0.9
	var drives_action: bool = false
	var _elapsed: float = 0.0
	var _next_fire: float = 3.0
	var _held: bool = false

	func poll(delta: float) -> MoveIntent:
		_elapsed += delta
		_intent.clear()
		if body == null or controller == null or not body.is_guard:
			return _intent
		var eye: Vector3 = (body.get_node(^"Head/Camera") as Node3D).global_position
		var best: float = INF
		var at: Vector3 = Vector3.INF
		var target_velocity: Vector3 = Vector3.ZERO
		for p: MatchParticipant in controller.get_participants():
			if p.body == null or p.body == body or not p.is_running:
				continue
			var chest: Vector3 = p.body.global_position + Vector3.UP * 0.9
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, chest)
			query.exclude = [body.get_rid()]
			var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.collider != p.body:
				continue
			var distance: float = eye.distance_to(chest) * (0.1 if p.body.movement_locked else 1.0)
			if distance < best:
				best = distance
				at = chest
				target_velocity = p.body.velocity
		if not at.is_finite():
			if _held and drives_action:
				Input.action_release(WeaponActions.FIRE)
			_held = false
			return _intent
		at = _lead(eye, at, target_velocity)
		var dir: Vector3 = (at - eye).normalized()
		var want: Vector2 = Vector2(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))
		var view: Vector2 = body.get_view_angles()
		_intent.look_delta = Vector2(angle_difference(want.x, view.x), -(want.y - view.y))
		# A charged rifle wants the trigger held and let go; the host's own trigger reads the action itself.
		var holding: bool = _elapsed >= _next_fire
		if holding and not _held:
			_intent.fire_pressed = true
		if holding and _elapsed >= _next_fire + HOLD_SECONDS:
			holding = false
			_next_fire = _elapsed + fire_every
		_intent.fire_held = holding
		if holding != _held:
			_held = holding
			if drives_action and holding and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
				# No captured mouse (headless): WeaponInput reads nothing, so the host pulls its own trigger.
				controller.rifle.try_fire()
			elif drives_action and holding:
				Input.action_press(WeaponActions.FIRE)
			elif drives_action:
				Input.action_release(WeaponActions.FIRE)
		return _intent


	## Where to point so a travelling, falling round meets a target moving at [param velocity].
	func _lead(eye: Vector3, at: Vector3, velocity: Vector3) -> Vector3:
		var speed: float = controller.rifle.get_shot_speed() if controller.rifle != null else 0.0
		if speed <= 0.0:
			return at
		var flight: float = (at - eye + velocity * ((at - eye).length() / speed)).length() / speed
		at += velocity * flight
		at.y += 0.5 * controller.rifle.profile.projectile_gravity * flight * flight
		return at
