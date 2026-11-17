extends Node
## Flow probe: one process of the real game driven from the main menu by a timed plan, logging what
## this machine holds. Run by tools/net/flow_probes.py; --plan="2:host;8:start=marble;40:end" --name --port --limit

var _plan: Array = []
var _name: String = "P"
var _port: int = 27990
var _address: String = "127.0.0.1"
var _limit: float = 120.0
var _t0: int = 0
var _last_state: String = ""
var _last_state_ms: int = 0
var _last_frame_ms: int = 0
var _start_when: int = 0
var _start_map: String = ""
## The plan asked to quit: the tree is coming down and what it holds says nothing.
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--plan="):
			for step: String in argument.trim_prefix("--plan=").split(";", false):
				var at: PackedStringArray = step.split(":", true, 1)
				_plan.append([float(at[0]), at[1]])
		elif argument.begins_with("--name="):
			_name = argument.trim_prefix("--name=")
		elif argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--address="):
			_address = argument.trim_prefix("--address=")
		elif argument.begins_with("--limit="):
			_limit = float(argument.trim_prefix("--limit="))
	_t0 = Time.get_ticks_msec()
	_boot.call_deferred()


func _line(text: String) -> void:
	print("PROBE %s t=%.2f %s" % [_name, (Time.get_ticks_msec() - _t0) / 1000.0, text])


func _boot() -> void:
	var tree: SceneTree = get_tree()
	reparent(tree.root)
	tree.current_scene = null
	var error: Error = tree.change_scene_to_file("res://ui/main_menu.tscn")
	_line("BOOT main menu %s" % error_string(error))


func _session() -> NetSession:
	return get_tree().root.get_node_or_null(^"NetSession") as NetSession


func _find(type_name: String) -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	if scene.is_class(type_name) or (scene.get_script() != null and scene.get_script().get_global_name() == type_name):
		return scene
	for found: Node in scene.find_children("*", type_name, true, false):
		return found
	return null


func _process(_delta: float) -> void:
	if _done:
		return
	var now: int = Time.get_ticks_msec()
	if _last_frame_ms > 0 and now - _last_frame_ms > 250:
		_line("HITCH %d ms" % (now - _last_frame_ms))
	_last_frame_ms = now
	var elapsed: float = (now - _t0) / 1000.0
	while not _plan.is_empty() and elapsed >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		_do(String(step[1]))
		if not is_inside_tree():
			return
	if _start_when > 0 and _session() != null:
		var humans: int = 0
		for seat: LobbySeat in _session().lobby.get_occupied_seats():
			if seat.is_human():
				humans += 1
		if humans >= _start_when and _find("HubLobby") != null:
			_start_when = 0
			_do("start=" + _start_map)
	var state: String = _state()
	if state != _last_state or now - _last_state_ms > 1000:
		_last_state = state
		_last_state_ms = now
		_line("STATE " + state)
	if elapsed > _limit:
		_line("END limit")
		_done = true
		get_tree().quit(0)


func _state() -> String:
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene
	var parts: PackedStringArray = PackedStringArray()
	parts.append("scene=%s" % (scene.scene_file_path.get_file() if scene != null else "<none>"))
	var session: NetSession = _session()
	if session == null:
		parts.append("session=none")
	else:
		parts.append("conn=%s auth=%s peers=%s" % [
			NetTransport.state_name(session.get_connection_state()), str(session.is_authority()), str(session.get_peer_ids())])
		var lobby: NetLobby = session.lobby
		parts.append("lobby=%s epoch=%d seat=%d bound_scene=%d" % [
			String(NetLobby.Phase.keys()[lobby.get_phase()]), lobby.get_epoch(), lobby.get_local_seat_index(),
			session.replicator.get_scene()])
		var seats: PackedStringArray = PackedStringArray()
		for seat: LobbySeat in lobby.get_occupied_seats():
			seats.append("%d:%s:'%s':p%d" % [seat.index, "BOT" if seat.is_bot() else "HUM", seat.display_name, seat.peer_id])
		parts.append("seats=[%s]" % ",".join(seats))
		parts.append("rules_map=%s" % (String(lobby.get_rules().map_id) if lobby.get_rules() != null else "<null>"))
	parts.append("mp_peer=%s" % ("null" if tree.root.multiplayer.multiplayer_peer == null else tree.root.multiplayer.multiplayer_peer.get_class()))
	parts.append("3d_off=%s paused=%s" % [str(tree.root.disable_3d), str(tree.paused)])
	if scene != null:
		var controller: MatchController = _find("MatchController") as MatchController
		if controller != null:
			var names: PackedStringArray = PackedStringArray()
			for participant: MatchParticipant in controller.get_participants():
				names.append("%s%s" % [participant.display_name, "" if participant.is_human() else "(ai)"])
			var holder: MatchParticipant = controller.get_seat_participant()
			var alive: int = 0
			for participant: MatchParticipant in controller.get_participants():
				if participant.is_running and not participant.is_ghost:
					alive += 1
			parts.append("guard=%s alive=%d" % [holder.display_name if holder != null else "-", alive])
			parts.append("ctl=%s round=%d over=%s parts=[%s] map=%s" % [
				controller.get_phase_name(), controller.get_round_number(), str(controller.is_match_over()),
				",".join(names), String(controller.get_rules().map_id)])
		var net: NetMatch = _find("NetMatch") as NetMatch
		if net != null:
			var cover: bool = false
			for child: Node in net.get_children():
				if child is LoadingCover:
					cover = true
			parts.append("net_active=%s started=%s cover=%s" % [str(net.is_active()), str(net.has_started()), str(cover)])
		var result: MatchResultScreen = _find("MatchResultScreen") as MatchResultScreen
		if result != null:
			parts.append("rth=%s result_btn='%s'" % [str(HubLobby.returns_to_hub), (result.get_node("%PlayAgainButton") as Button).text])
			parts.append("result=%s" % ("'%s|%s' votes='%s'" % [
				(result.get_node("%Verdict") as Label).text, (result.get_node("%Headline") as Label).text.replace("\n", "/"),
				(result.get_node("%RematchVotes") as Label).text if (result.get_node("%RematchVotes") as Label).visible else ""]
				if result.is_showing() else "down"))
		var hub: HubLobby = _find("HubLobby") as HubLobby
		if hub != null:
			parts.append("hub_is_host=%s hub_players=%d seats_label='%s'" % [
				str(hub.is_host()), hub.get_player_count(),
				hub.seats_label.text.replace("\n", "/") if hub.seats_label != null else ""])
		var menu: MainMenu = scene as MainMenu
		if menu != null:
			var screen: MultiplayerScreen = menu.get_node("%MultiplayerScreen") as MultiplayerScreen
			parts.append("menu mp_visible=%s mp_lobby_panel=%s status='%s'" % [
				str(screen.visible), str((screen.get_node("%LobbyPanel") as Control).visible),
				(screen.get_node("%Status") as Label).text])
	return " ".join(parts)


func _do(action: String) -> void:
	var name_and_arg: PackedStringArray = action.split("=", true, 1)
	var verb: String = name_and_arg[0]
	var arg: String = name_and_arg[1] if name_and_arg.size() > 1 else ""
	var scene: Node = get_tree().current_scene
	var menu: MainMenu = scene as MainMenu
	match verb:
		"host", "join":
			if menu == null:
				_line("DO %s REFUSED: not at the main menu" % verb)
				return
			menu.open_multiplayer()
			var screen: MultiplayerScreen = menu.get_node("%MultiplayerScreen") as MultiplayerScreen
			screen.set_player_name(_name)
			if verb == "host":
				screen.set_host_port(_port)
				_line("DO host -> %s" % error_string(screen.start_hosting()))
			else:
				screen.set_join_target(_address, _port)
				_line("DO join -> %s" % error_string(screen.join_game()))
		"mp_open":
			menu.open_multiplayer()
			_line("DO mp_open")
		"mp_leave":
			(menu.get_node("%MultiplayerScreen") as MultiplayerScreen).leave()
			_line("DO mp_leave")
		"play":
			if menu == null:
				_line("DO play REFUSED: not at the main menu")
				return
			menu.play_hub()
			_line("DO play")
		"start":
			var hub: HubLobby = _find("HubLobby") as HubLobby
			if hub == null:
				_line("DO start REFUSED: no hub")
				return
			for child: Node in hub.wedges_root.get_children():
				var wedge: MapWedge = child as MapWedge
				if wedge != null and String(wedge.map_id) == arg:
					var ok: bool = hub._start_on(wedge)
					var why: String = hub.get_lobby().describe_launch_block() if hub.get_lobby() != null else "offline"
					_line("DO start=%s -> %s (launch block: '%s')" % [arg, str(ok), why])
					return
			_line("DO start REFUSED: no wedge %s" % arg)
		"start_when":
			_start_when = int(arg.split(",")[0])
			_start_map = arg.split(",")[1]
			_line("DO start_when %s" % arg)
		"win":
			var controller: MatchController = _find("MatchController") as MatchController
			if controller == null or controller.get_participants().is_empty():
				_line("DO win REFUSED")
				return
			controller._win_match(controller.get_participants()[int(arg) if not arg.is_empty() else 0])
			_line("DO win")
		"leave_menu":
			var pause: PauseMenu = _find("PauseMenu") as PauseMenu
			if pause == null:
				_line("DO leave_menu REFUSED: no pause menu")
				return
			pause.open()
			pause.return_to_main_menu()
			_line("DO leave_menu (PauseMenu: Leave Match)")
		"pause_open":
			(_find("PauseMenu") as PauseMenu).open()
			_line("DO pause_open")
		"pause_close":
			(_find("PauseMenu") as PauseMenu).close()
			_line("DO pause_close")
		"result_menu":
			(_find("MatchResultScreen") as MatchResultScreen).return_to_main_menu()
			_line("DO result_menu (ResultScreen: Main Menu)")
		"back":
			(_find("MatchResultScreen") as MatchResultScreen).play_again()
			_line("DO back (ResultScreen: Back to Hub / Play Again)")
		"rematch":
			(_find("MatchResultScreen") as MatchResultScreen).request_rematch()
			_line("DO rematch")
		"huball":
			var net: NetMatch = _find("NetMatch") as NetMatch
			net.return_all_to_hub()
			_line("DO huball")
		"restart_key":
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = KEY_R
			key.keycode = KEY_R
			key.pressed = true
			Input.parse_input_event(key)
			_line("DO restart_key (R)")
		"setting":
			var pair: PackedStringArray = arg.split(",", true, 1)
			var store: SettingsStore = SettingsStore.instance()
			store.settings.set(pair[0], str_to_var(pair[1]))
			store.apply_all()
			_line("DO setting %s=%s applied" % [pair[0], pair[1]])
		"stall":
			_line("DO stall %s ms" % arg)
			OS.delay_msec(int(arg))
			_line("stall over")
		"quit":
			_line("DO quit")
			_done = true
			get_tree().quit(0)
		"crash":
			_line("DO crash (kill self)")
			OS.kill(OS.get_process_id())
		"end":
			_line("END ok")
			_done = true
			get_tree().quit(0)
		_:
			_line("DO ? %s" % action)
