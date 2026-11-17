extends TestCase
## Playtest regressions across scene changes: hub -> map -> hub -> the other map, two and four machines.
## PT2-01 (host crash leaving the hub), PT2-07 (skin lit for the last map), PT2-09 and PT2-10 (bodies placed by another scene).

const Rig: GDScript = preload("res://tests/support/net_session_rig.gd")

const HOST: int = 0
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
const CROSS_TICKS: int = 30
## Ticks one machine stays in the old scene while the others are already in the new one.
const STAGGER_TICKS: int = 12
## A hub body further than this from its spawn was put there by something else.
const SPAWN_SLACK: float = 0.6
## Metres under the lower of the start line and the tower floor: below it a body is in the pit.
const PIT_MARGIN: float = 3.0

var _rig: RefCounted = null
var _log: Logger = null


func before_each() -> void:
	_rig = Rig.new()
	_log = Rig.ErrorLog.new()
	OS.add_logger(_log)


func after_each() -> void:
	if _log != null:
		OS.remove_logger(_log)
		_log = null
	if _rig != null:
		_rig.close()
		_rig = null


func _order(host_first: bool) -> Array[int]:
	var order: Array[int] = []
	for peer: int in _rig.peer_count():
		order.append(peer)
	if not host_first:
		order.reverse()
	return order


## The spawn marker nearest [param at] in [param peer]'s hub, as a flat distance and a height.
func _nearest_spawn(peer: int, at: Vector3) -> Vector2:
	var best: Vector2 = Vector2(INF, 0.0)
	var spawns: Array = _rig.controller(peer).call(&"_hub_spawns")
	for marker: Marker3D in spawns:
		var flat: float = Vector2(at.x - marker.global_position.x, at.z - marker.global_position.z).length()
		if flat < best.x:
			best = Vector2(flat, at.y - marker.global_position.y)
	return best


## Every body on every machine stands on a hub spawn, solid, at floor height.
func _assert_everyone_stands_in_the_hub(why: String) -> void:
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_eq_int(controller.get_participants().size(), _rig.peer_count(), "%s: peer %d holds a body per human" % [why, peer])
		for participant: MatchParticipant in controller.get_participants():
			var body: PlayerController = participant.body
			var off: Vector2 = _nearest_spawn(peer, body.global_position)
			var who: String = "%s: peer %d's copy of slot %d at %s" % [why, peer, participant.index, body.global_position]
			assert_lt(off.x, SPAWN_SLACK, "%s stands on a hub spawn" % who)
			assert_between(off.y, -0.3, 0.6, "%s is at floor height" % who)
			assert_true(body.collision_mask != 0, "%s collides with the hub" % who)
			assert_eq_int(body.collision_mask, participant.home_collision_mask, "%s has its authored mask" % who)
			assert_eq_int(body.collision_layer, participant.home_collision_layer, "%s has its authored layer" % who)
			assert_true(participant.home_collision_layer != 0, "%s: and that layer is not the held one" % who)
		assert_false(_rig.matches[peer].get_viewport().disable_3d, "%s: peer %d draws its hub" % [why, peer])


## Every client walks, and the host sees it move; nobody leaves the floor.
func _assert_everyone_walks(why: String) -> void:
	var from: Array[Vector3] = []
	for peer: int in _rig.peer_count():
		from.append(_rig.body(HOST, _rig.local_slot(peer)).global_position)
		_rig.drive(peer, Vector2(0.0, 1.0))
	await step_ticks(45)
	for peer: int in _rig.peer_count():
		_rig.drive(peer, Vector2.ZERO)
		var now: Vector3 = _rig.body(HOST, _rig.local_slot(peer)).global_position
		assert_gt(Vector2(now.x - from[peer].x, now.z - from[peer].z).length(), 1.0, "%s: peer %d walks, as the host sees it" % [why, peer])
		assert_between(now.y - from[peer].y, -0.5, 0.5, "%s: peer %d stays on the hub floor" % [why, peer])


## The lowest a living body may be on the standing map.
func _pit_line(peer: int) -> float:
	var controller: MatchController = _rig.controller(peer)
	var start: Marker3D = controller.arena.get_node(controller.start_marker_path) as Marker3D
	var tower: Marker3D = controller.arena.get_node(controller.spawn_marker_path) as Marker3D
	return minf(start.global_position.y, tower.global_position.y) - PIT_MARGIN


## No drawn body is in the pit and nobody has died, on any machine whose match stands.
func _assert_nobody_is_in_the_pit(why: String) -> void:
	for peer: int in _rig.peer_count():
		if _rig.matches[peer] == null or _rig.matches[peer].name != &"Match":
			continue
		if _rig.matches[peer].get_viewport().disable_3d:
			continue
		var floor_y: float = _pit_line(peer)
		for participant: MatchParticipant in _rig.controller(peer).get_participants():
			assert_gt(participant.body.global_position.y, floor_y, "%s: peer %d draws slot %d above the pit" % [why, peer, participant.index])
			assert_false(participant.is_ghost, "%s: peer %d has slot %d alive" % [why, peer, participant.index])


## The map stands, lit for itself, on every machine, and every machine draws the bodies where the host has them.
func _assert_the_match_stands(map: StringName, why: String) -> void:
	var wanted: String = MapCatalog.scene_path_for(map)
	var fit: CharacterFit = load("res://maps/%s/%s_character_fit.tres" % [map, map]) as CharacterFit
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_eq_string(controller.arena.scene_file_path, wanted, "%s: peer %d stands on the chosen map" % [why, peer])
		assert_eq_int(controller.get_round_number(), 1, "%s: peer %d is in round one" % [why, peer])
		assert_same(controller.get_seat_participant(), _rig.participant(peer, 0), "%s: peer %d has the host in the tower" % [why, peer])
		var gate: Area3D = _rig.gate(peer)
		assert_not_null(gate, "%s: peer %d's map has its portal" % [why, peer])
		for participant: MatchParticipant in controller.get_participants():
			var who: String = "%s: peer %d's copy of slot %d" % [why, peer, participant.index]
			var tracker_gate: Variant = participant.tracker.get(&"_gate")
			if participant.is_running and not controller.is_mirror():
				assert_true(is_instance_valid(tracker_gate) and tracker_gate == gate, "%s runs to the standing map's portal" % who)
			var mesh: MeshInstance3D = _rig.avatar(peer, participant.index).mesh
			var shirt: Material = mesh.get_surface_override_material(MatchController.shirt_surface_of(mesh))
			var light: CharacterLight = controller.get(&"_character_light") as CharacterLight
			assert_true(light != null and light.fit == fit, "%s: the bodies are lit for this map" % who)
			var cache: Dictionary = light.get(&"_cache") if light != null else {}
			assert_true(cache.values().has(shirt), "%s wears a shirt lit for this map" % who)
			var there: Vector3 = _rig.body(HOST, participant.index).global_position
			assert_lt(participant.body.global_position.distance_to(there), 3.0, "%s is drawn where the host has it" % who)
		var own: PlayerController = _rig.body(peer, _rig.local_slot(peer))
		assert_true(own.is_physics_processing(), "%s: peer %d simulates its own body" % [why, peer])
		assert_false(_rig.matches[peer].get_viewport().disable_3d, "%s: peer %d draws its match" % [why, peer])


## Hub, then each map in [param maps] and the hub again after it, the machines changing scene out of step.
func _play_a_session(clients: int, maps: Array[StringName]) -> void:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return
	_rig.settings().rounds_to_win_match = 3
	_rig.matches.resize(_rig.peer_count())
	for peer: int in _rig.peer_count():
		_rig.bind_hub(peer)
	if not await _rig.hubs_settled():
		fail("the first hub never settled")
		return
	await step_ticks(CROSS_TICKS)
	_assert_everyone_stands_in_the_hub("first hub")
	var host_first: bool = false
	for map: StringName in maps:
		var why: String = "%s, %s first" % [map, "host" if host_first else "clients"]
		_rig.settings().map_id = map
		# Walking as the wedge is pressed: intent is in flight when the hub goes.
		for peer: int in _rig.peer_count():
			_rig.drive(peer, Vector2(0.0, 1.0))
		await step_ticks(6)
		if not await _launch(clients + 3, _order(host_first), why):
			return
		for peer: int in _rig.peer_count():
			_rig.drive(peer, Vector2(0.0, 1.0))
		for _tick: int in 60:
			await step_ticks(1)
			_assert_nobody_is_in_the_pit(why)
			if is_failed():
				return
		_assert_the_match_stands(map, why)
		if not await _return(_order(not host_first), why):
			return
		_assert_everyone_stands_in_the_hub("hub after %s" % why)
		await step_ticks(60)
		_assert_everyone_stands_in_the_hub("a second later, hub after %s" % why)
		await _assert_everyone_walks("hub after %s" % why)
		if is_failed():
			return
		host_first = not host_first
	var first: String = _log.lines[0] if _log.count() > 0 else ""
	assert_eq_int(_log.count(), 0, "engine errors over the session (first: %s)" % first)


## Launch with the host in the tower, the machines binding in [param order], watched from the first bind.
func _launch(seats: int, order: Array[int], why: String) -> bool:
	var started: Array[bool] = [false]
	var watch: Callable = func() -> void:
		if not started[0]:
			_assert_nobody_is_in_the_pit(why + ", loading")
	get_tree().physics_frame.connect(watch)
	var ok: bool = await _rig.launch_staged(seats, HOST, order, STAGGER_TICKS)
	if ok:
		for peer: int in _rig.peer_count():
			var controller: MatchController = _rig.controller(peer)
			if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
				ok = false
		for peer: int in range(1, _rig.peer_count()):
			var link: PlayerNetLink = _rig.net_match(peer).get_local_link()
			if not await _rig.wait_for(func() -> bool: return link.is_predicting()):
				ok = false
	started[0] = true
	get_tree().physics_frame.disconnect(watch)
	if not ok:
		fail("%s: the match never started on every machine" % why)
	return ok


## Everyone back to the hub, the machines changing scene in [param order], a stagger apart.
func _return(order: Array[int], why: String) -> bool:
	if not await _rig.call_everyone_to_the_hub():
		fail("%s: not every lobby went back to gathering" % why)
		return false
	for peer: int in order:
		_rig.unbind(peer)
		_rig.bind_hub(peer)
		for _tick: int in STAGGER_TICKS:
			await step_ticks(1)
			for seen: int in _rig.peer_count():
				if _rig.matches[seen] == null or _rig.matches[seen].name != &"Hub":
					continue
				if _rig.matches[seen].get_viewport().disable_3d:
					continue
				for participant: MatchParticipant in _rig.controller(seen).get_participants():
					var off: Vector2 = _nearest_spawn(seen, participant.body.global_position)
					assert_lt(off.x, SPAWN_SLACK, "%s: while others load, peer %d draws slot %d on a hub spawn (at %s)" % [why, seen, participant.index, participant.body.global_position])
	if not await _rig.hubs_settled():
		fail("%s: the hub never settled on every machine" % why)
		return false
	await step_ticks(CROSS_TICKS)
	return true


func test_two_machines_play_hell_then_marble_through_the_hub() -> void:
	await _play_a_session(1, [HELL, MARBLE])


func test_two_machines_play_marble_then_hell_through_the_hub() -> void:
	await _play_a_session(1, [MARBLE, HELL])


func test_four_machines_play_hell_then_marble_through_the_hub() -> void:
	await _play_a_session(3, [HELL, MARBLE])


func test_four_machines_play_marble_then_hell_through_the_hub() -> void:
	await _play_a_session(3, [MARBLE, HELL])


func test_two_machines_go_round_the_hub_six_times() -> void:
	await _play_a_session(1, [HELL, MARBLE, MARBLE, HELL, HELL, MARBLE])


## A third machine walks into a hub two are standing in: the hub is rebuilt, and nobody is left unsolid or off a spawn.
func test_a_late_joiner_leaves_everyone_solid_on_a_hub_spawn() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("the loopback handshake did not complete")
		return
	_rig.matches.resize(_rig.peer_count())
	for peer: int in _rig.peer_count():
		_rig.bind_hub(peer)
	if not await _rig.hubs_settled():
		fail("the hub never settled for two")
		return
	_assert_everyone_stands_in_the_hub("two in the hub")
	for joiner: int in [2, 3]:
		if not await _rig.join_late():
			fail("machine %d could not join" % joiner)
			return
		_rig.bind_hub(joiner)
		if not await _rig.hubs_settled():
			fail("the hub never settled for %d" % (joiner + 1))
			return
		await step_ticks(CROSS_TICKS)
		_assert_everyone_stands_in_the_hub("%d in the hub" % (joiner + 1))
		await step_ticks(60)
		_assert_everyone_stands_in_the_hub("a second later, %d in the hub" % (joiner + 1))
		await _assert_everyone_walks("%d in the hub" % (joiner + 1))
		if is_failed():
			return
	# Standing still again before the roster moves, so a spawn is where a body stays.
	await step_ticks(CROSS_TICKS)
	# Two roster changes inside one frame: the second rebuild finds the bodies still held by the first.
	for peer: int in _rig.peer_count():
		_rig.net_match(peer).rebuild_hub()
		_rig.net_match(peer).rebuild_hub()
	if not await _rig.hubs_settled():
		fail("the hub never settled after two rebuilds in a frame")
		return
	await step_ticks(CROSS_TICKS)
	_assert_everyone_stands_in_the_hub("after two rebuilds in a frame")
	await _assert_everyone_walks("after two rebuilds in a frame")
	var first: String = _log.lines[0] if _log.count() > 0 else ""
	assert_eq_int(_log.count(), 0, "engine errors as the hub fills (first: %s)" % first)


## Every machine's level names the match scene for a launch and the hub for the way back from one.
func test_every_machines_level_follows_the_hosts_lobby() -> void:
	if not await _rig.connect_peers(self, 3):
		fail("the loopback handshake did not complete")
		return
	var host: NetSession = _rig.sessions[HOST]
	host.lobby.fill_with_bots(5)
	for seat: LobbySeat in host.lobby.get_occupied_seats():
		host.lobby.set_ready(seat.index, true)
	var before: int = host.lobby.get_epoch()
	assert_true(host.lobby.launch(), "the host launches")
	for session: NetSession in _rig.sessions:
		if not await _rig.wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.LAUNCHING):
			fail("a lobby never heard of the launch")
			return
		assert_gt(float(session.lobby.get_epoch()), float(before), "%s is on the launch's epoch" % session.get_parent().name)
		assert_eq_int(int(session.level.get(&"_epoch")), session.lobby.get_epoch(), "%s's level took that epoch" % session.get_parent().name)
		for phase: NetLobby.Phase in [NetLobby.Phase.LAUNCHING, NetLobby.Phase.IN_MATCH, NetLobby.Phase.POST_MATCH]:
			assert_eq_string(str(session.level.call(&"_scene_for", phase)), NetLevel.MATCH_SCENE_PATH, "%s loads the match in phase %d" % [session.get_parent().name, phase])
	assert_true(host.lobby.conclude_match(-1), "the host ends the match")
	var launched: int = host.lobby.get_epoch()
	assert_true(host.lobby.return_to_lobby(), "and calls everyone back")
	for session: NetSession in _rig.sessions:
		if not await _rig.wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.GATHERING):
			fail("a lobby never heard of the return")
			return
		assert_gt(float(session.lobby.get_epoch()), float(launched), "%s is on a new epoch for the hub" % session.get_parent().name)
		assert_eq_int(int(session.level.get(&"_epoch")), session.lobby.get_epoch(), "%s's level took the hub's epoch" % session.get_parent().name)
