extends "res://tests/support/net_match_rig.gd"
## A whole session on the match rig: staged launches, the way back to the hub, and the next map.

const FINISH_GROUP: StringName = &"finish_gate"
const GATE_FLOOR_DROP: float = 1.3


## Launch like [method launch], binding the peers in [param order] with [param gap_ticks] between them.
func launch_staged(seats: int, guard_seat: int, order: Array[int], gap_ticks: int) -> bool:
	var host: NetSession = sessions[0]
	var store: GameSettings = settings()
	store.skip_opening_race = guard_seat >= 0
	store.tower_seat_index = maxi(guard_seat, 0)
	store.prisoner_count = seats - 1
	var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	store.apply_to_match_rules(rules)
	host.lobby.set_rules(rules)
	host.lobby.fill_with_bots(seats)
	if guard_seat >= 0:
		host.lobby.assign_guard(guard_seat)
	else:
		host.lobby.clear_roles()
	for seat: LobbySeat in host.lobby.get_occupied_seats():
		host.lobby.set_ready(seat.index, true)
	if not host.lobby.launch():
		return false
	for session: NetSession in sessions:
		if not await wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.LAUNCHING):
			return false
	matches.resize(sessions.size())
	for peer: int in order:
		unbind(peer)
		matches[peer] = _bind(sessions[peer])
		for _tick: int in gap_ticks:
			await _case.get_tree().physics_frame
	return await wait_for(_all_started)


## Take [param peer]'s scene down, as a scene change does: out of the tree, then freed.
func unbind(peer: int) -> void:
	var scene: Node = matches[peer]
	if scene == null:
		return
	var world: Node = scene.get_parent()
	world.get_parent().remove_child(world)
	world.queue_free()
	matches[peer] = null


## The shipped hub for one peer, in a world of its own.
func bind_hub(peer: int) -> void:
	var world: SubViewport = SubViewport.new()
	world.name = WORLD_NAME
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	sessions[peer].get_parent().add_child(world)
	var hub: Node3D = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	hub.name = "Hub"
	TestFixtures.silence_human_input(hub)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	lobby.changes_scene = false
	lobby.session_path = sessions[peer].get_path()
	(hub.get_node("NetMatch") as NetMatch).session_path = sessions[peer].get_path()
	_give_test_input(hub.get_node("Player") as PlayerController)
	var audio: Node = hub.get_node_or_null("GameAudio")
	if audio != null:
		audio.free()
	world.add_child(hub)
	matches[peer] = hub


## The host ends the match and calls everyone to the hub; every lobby is gathering again.
func call_everyone_to_the_hub() -> bool:
	net_match(0).return_all_to_hub()
	for session: NetSession in sessions:
		if not await wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.GATHERING):
			return false
	return true


## Every human in the hub holds a body per human and every client predicts its own.
func hubs_settled() -> bool:
	var humans: int = sessions.size()
	return await wait_for(func() -> bool:
		for peer: int in sessions.size():
			if matches[peer] == null or controller(peer).get_participants().size() != humans:
				return false
			if peer > 0:
				var link: PlayerNetLink = net_match(peer).get_local_link()
				if link == null or not link.is_predicting():
					return false
		return true)


## [param peer]'s own finish gate: the one under its own arena.
func gate(peer: int) -> Area3D:
	var arena: Node = controller(peer).arena
	for found: Node in _case.get_tree().get_nodes_in_group(FINISH_GROUP):
		if arena.is_ancestor_of(found):
			return found as Area3D
	return null


## Stand the host's copy of [param slot] in the finish gate, [param aside] metres across it.
func stand_in_gate(slot: int, aside: float = 0.0) -> void:
	var finish: Area3D = gate(0)
	var target: PlayerController = body(0, slot)
	target.velocity = Vector3.ZERO
	target.global_position = (
		finish.global_position - Vector3(0.0, GATE_FLOOR_DROP, 0.0)
		+ finish.global_transform.basis.x.normalized() * aside
	)


## One more client joins a session already under way, on a clean line. False rather than hanging.
func join_late() -> bool:
	var host: NetSession = sessions[0]
	var port: int = (host.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.get_local_port()
	var client: NetSession = NetFixtures.make_peer(_case, "Client%d" % sessions.size(), NetFixtures.settings())
	var expected: int = host.get_peer_count() + 1
	sessions.append(client)
	matches.append(null)
	if client.join("127.0.0.1", port) != OK:
		return false
	return await wait_for(func() -> bool:
		return client.is_established() and host.get_peer_count() >= expected and client.lobby.get_local_seat_index() >= 0)

## Engine errors raised while it is installed with [method OS.add_logger].
class ErrorLog extends Logger:
	var lines: PackedStringArray = PackedStringArray()
	var _lock: Mutex = Mutex.new()

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		lines.append("%s %s (%s:%d in %s)" % [code, rationale, file, line, function])
		_lock.unlock()

	func count() -> int:
		_lock.lock()
		var total: int = lines.size()
		_lock.unlock()
		return total
