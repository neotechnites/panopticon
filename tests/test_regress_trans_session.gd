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
## A mirrored body further than this from where the host had it on the tick being drawn is somewhere else.
const DRAWN_SLACK: float = 0.5

var _rig: RefCounted = null
var _log: Logger = null
## Where the host had every slot's body on each of its recent ticks, by host tick.
var _trail: Dictionary[int, PackedVector3Array] = {}


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


## Where the host has every body now, by slot.
func _where_everyone_stands() -> Dictionary[int, Vector3]:
	var stood: Dictionary[int, Vector3] = {}
	for participant: MatchParticipant in _rig.controller(HOST).get_participants():
		stood[participant.index] = participant.body.global_position
	return stood


## Every body on every machine stands solid at floor height: on a hub spawn, or for a slot in
## [param stood] (a seat held across a roster change) where it stood before.
func _assert_everyone_stands_in_the_hub(why: String, stood: Dictionary[int, Vector3] = {}) -> void:
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_eq_int(controller.get_participants().size(), _rig.peer_count(), "%s: peer %d holds a body per human" % [why, peer])
		for participant: MatchParticipant in controller.get_participants():
			var body: PlayerController = participant.body
			var who: String = "%s: peer %d's copy of slot %d at %s" % [why, peer, participant.index, body.global_position]
			var off: Vector2
			if stood.has(participant.index):
				var was: Vector3 = stood[participant.index]
				off = Vector2(Vector2(body.global_position.x - was.x, body.global_position.z - was.z).length(), body.global_position.y - was.y)
				assert_lt(off.x, SPAWN_SLACK, "%s stands where it stood before the roster changed" % who)
				assert_between(_nearest_spawn(peer, body.global_position).y, -0.3, 0.6, "%s is on the hub's floor" % who)
			else:
				off = _nearest_spawn(peer, body.global_position)
				assert_lt(off.x, SPAWN_SLACK, "%s stands on a hub spawn" % who)
			assert_between(off.y, -0.3, 0.6, "%s is at floor height" % who)
			assert_true(body.collision_mask != 0, "%s collides with the hub" % who)
			assert_eq_int(body.collision_mask, participant.home_collision_mask, "%s has its authored mask" % who)
			assert_eq_int(body.collision_layer, participant.home_collision_layer, "%s has its authored layer" % who)
			assert_true(participant.home_collision_layer != 0, "%s: and that layer is not the held one" % who)
		assert_false(_rig.matches[peer].get_viewport().disable_3d, "%s: peer %d draws its hub" % [why, peer])


## Every client walks, and the host sees it move; nobody leaves the floor. [param ahead] is -1 to walk back.
func _assert_everyone_walks(why: String, ahead: float = 1.0) -> void:
	var from: Array[Vector3] = []
	for peer: int in _rig.peer_count():
		from.append(_rig.body(HOST, _rig.local_slot(peer)).global_position)
		_rig.drive(peer, Vector2(0.0, ahead))
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


## Keep where the host has every body on this tick.
func _remember_where_the_host_has_everyone() -> void:
	var participants: Array[MatchParticipant] = _rig.controller(HOST).get_participants()
	var places: PackedVector3Array = PackedVector3Array()
	places.resize(participants.size())
	for participant: MatchParticipant in participants:
		places[participant.index] = participant.body.global_position
	_trail[(_rig.sessions[HOST] as NetSession).replicator.get_tick()] = places


## [param peer] draws another machine's body from its snapshot buffer: no deeper than the buffer is built to
## be, no further back than that depth, and where the host had the body on the tick being drawn.
func _assert_drawn_where_the_host_had_it(peer: int, slot: int, who: String) -> void:
	var session: NetSession = _rig.sessions[peer]
	var settings: NetSettings = session.get_settings()
	var view: int = floori(session.replicator.get_view_time())
	var now: int = (_rig.sessions[HOST] as NetSession).replicator.get_tick()
	# A frame here runs up to this many ticks between two polls and two draws.
	var frame: int = Engine.max_physics_steps_per_frame
	var snapshot_ticks: int = ceili(SIM_HZ / float(settings.snapshot_hz))
	var delay: float = session.replicator.get_delay_ticks()
	var deepest: int = settings.interpolation_delay_ticks + settings.max_interpolation_jitter_ticks
	if not assert_true(view >= 0, "%s is drawn from a running snapshot clock" % who):
		return
	assert_le(delay, float(deepest), "%s is drawn from a buffer no deeper than its settings allow" % who)
	# The newest snapshot is up to an interval and a frame old when it is read here.
	assert_between(
		float(NetCodec.tick_delta(view, now)), 0.0, ceilf(delay) + float(snapshot_ticks + frame),
		"%s is drawn no further back than the buffer's depth" % who,
	)
	var drawn: Vector3 = _rig.body(peer, slot).global_position
	var nearest: float = INF
	for tick: int in range(view - frame - 1, view + 2):
		if _trail.has(tick):
			nearest = minf(nearest, drawn.distance_to(_trail[tick][slot]))
	assert_lt(nearest, DRAWN_SLACK, "%s is drawn where the host had it on the tick it draws" % who)


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
			if peer != HOST and participant.index != _rig.local_slot(peer):
				_assert_drawn_where_the_host_had_it(peer, participant.index, who)
			else:
				# Its own body runs ahead of the host's copy by the input in flight.
				var there: Vector3 = _rig.body(HOST, participant.index).global_position
				assert_lt(participant.body.global_position.distance_to(there), 3.0, "%s is where the host has it" % who)
		var own: PlayerController = _rig.body(peer, _rig.local_slot(peer))
		assert_true(moves(own), "%s: peer %d simulates its own body" % [why, peer])
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
		_trail.clear()
		for _tick: int in 60:
			await step_ticks(1)
			_remember_where_the_host_has_everyone()
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


## A third and a fourth machine walk into a hub others are standing in: each joiner stands on a spawn, everyone
## already there stays solid where they stood, and all of them still walk.
func test_a_late_joiner_stands_on_a_spawn_and_leaves_everyone_solid_where_they_stood() -> void:
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
	# Ahead for the first joiner and back for the second: a body that kept its place may be standing at a wall.
	var ahead: float = 1.0
	for joiner: int in [2, 3]:
		var stood: Dictionary[int, Vector3] = _where_everyone_stands()
		if not await _rig.join_late():
			fail("machine %d could not join" % joiner)
			return
		_rig.bind_hub(joiner)
		if not await _rig.hubs_settled():
			fail("the hub never settled for %d" % (joiner + 1))
			return
		await step_ticks(CROSS_TICKS)
		assert_false(stood.has(_rig.local_slot(joiner)), "machine %d took a slot nobody held" % joiner)
		_assert_everyone_stands_in_the_hub("%d in the hub" % (joiner + 1), stood)
		await step_ticks(60)
		_assert_everyone_stands_in_the_hub("a second later, %d in the hub" % (joiner + 1), stood)
		await _assert_everyone_walks("%d in the hub" % (joiner + 1), ahead)
		if is_failed():
			return
		ahead = -ahead
		# Standing still again before the roster moves, so a place is where a body stays.
		await step_ticks(CROSS_TICKS)
	var before: Dictionary[int, Vector3] = _where_everyone_stands()
	# Two roster changes inside one frame: the second rebuild finds the bodies still held by the first.
	for peer: int in _rig.peer_count():
		_rig.net_match(peer).rebuild_hub()
		_rig.net_match(peer).rebuild_hub()
	if not await _rig.hubs_settled():
		fail("the hub never settled after two rebuilds in a frame")
		return
	await step_ticks(CROSS_TICKS)
	_assert_everyone_stands_in_the_hub("after two rebuilds in a frame", before)
	await _assert_everyone_walks("after two rebuilds in a frame", ahead)
	var first: String = _log.lines[0] if _log.count() > 0 else ""
	assert_eq_int(_log.count(), 0, "engine errors as the hub fills (first: %s)" % first)


## A client waits longer for a host it holds no snapshot from (the host may be loading): it must hold none
## from the moment the lobby names another scene, in both directions, and hold one once that scene runs.
func test_a_client_holds_no_snapshot_of_a_scene_the_lobby_has_left() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("the loopback handshake did not complete")
		return
	_rig.matches.resize(_rig.peer_count())
	for peer: int in _rig.peer_count():
		_rig.bind_hub(peer)
	if not await _rig.hubs_settled():
		fail("the hub never settled")
		return
	var client: NetSession = _rig.sessions[1]
	assert_true(await _rig.wait_for(func() -> bool: return client.replicator.get_latest_tick() >= 0), "in the hub the client holds the host's snapshots")
	_rig.settings().map_id = HELL
	var seen_at_launch: Array[int] = []
	client.lobby.match_launching.connect(func() -> void: seen_at_launch.append(client.replicator.get_latest_tick()))
	if not await _rig.launch_staged(4, HOST, _order(false), STAGGER_TICKS):
		fail("the match never started on every machine")
		return
	assert_eq_int(seen_at_launch.size(), 1, "the client heard of the launch")
	if not seen_at_launch.is_empty():
		assert_eq_int(seen_at_launch[0], -1, "and held no hub snapshot by the end of the roster that named the match")
	assert_true(await _rig.wait_for(func() -> bool: return client.replicator.get_latest_tick() >= 0), "in the match it holds the host's snapshots again")
	var seen_at_return: Array[int] = []
	client.lobby.phase_changed.connect(func(phase: NetLobby.Phase) -> void:
		if phase == NetLobby.Phase.GATHERING:
			seen_at_return.append(client.replicator.get_latest_tick()))
	if not await _rig.call_everyone_to_the_hub():
		fail("not every lobby went back to gathering")
		return
	assert_eq_int(seen_at_return.size(), 1, "the client heard of the return")
	if not seen_at_return.is_empty():
		assert_eq_int(seen_at_return[0], -1, "and held no match snapshot by the end of the roster that named the hub")
	assert_eq_int(client.replicator.get_latest_tick(), -1, "nor a moment later, its old scene still standing")


## Every machine's flow wants the match scene for a launch and the hub for the way back from one.
func test_every_machines_level_follows_the_hosts_lobby() -> void:
	if not await _rig.connect_peers(self, 3):
		fail("the loopback handshake did not complete")
		return
	var host: NetSession = _rig.sessions[HOST]
	var wanted: Array[PackedStringArray] = []
	for session: NetSession in _rig.sessions:
		var paths: PackedStringArray = PackedStringArray()
		wanted.append(paths)
		var at: int = wanted.size() - 1
		session.flow.scene_wanted.connect(func(path: String) -> void: wanted[at].append(path))
	host.lobby.fill_with_bots(5)
	for seat: LobbySeat in host.lobby.get_occupied_seats():
		host.lobby.set_ready(seat.index, true)
	var before: int = host.lobby.get_epoch()
	assert_true(host.lobby.launch(), "the host launches")
	for index: int in _rig.sessions.size():
		var session: NetSession = _rig.sessions[index]
		if not await _rig.wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.IN_MATCH):
			fail("a lobby never heard of the launch")
			return
		assert_gt(float(session.lobby.get_epoch()), float(before), "%s is on the launch's epoch" % session.get_parent().name)
		assert_eq_string(wanted[index][-1] if not wanted[index].is_empty() else "", SessionFlow.MATCH_SCENE_PATH,
			"%s's flow wants the match" % session.get_parent().name)
	assert_true(host.lobby.conclude_match(-1), "the host ends the match")
	var launched: int = host.lobby.get_epoch()
	assert_true(host.lobby.return_to_lobby(), "and calls everyone back")
	for index: int in _rig.sessions.size():
		var session: NetSession = _rig.sessions[index]
		if not await _rig.wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.GATHERING):
			fail("a lobby never heard of the return")
			return
		assert_gt(float(session.lobby.get_epoch()), float(launched), "%s is on a new epoch for the hub" % session.get_parent().name)
		assert_eq_string(wanted[index][-1], SessionFlow.HUB_SCENE_PATH, "%s's flow wants the hub" % session.get_parent().name)
