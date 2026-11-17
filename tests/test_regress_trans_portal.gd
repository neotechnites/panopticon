extends TestCase
## Playtest regressions at the portal and the start line, two and four machines, hell and marble.
## PT1-07 (a client at the portal), PT2-04 (nobody could win the first race), PT2-09 (portal to tower by way of the pit),
## PT3-11 (eight on the start line) and the tower fight opening.

const Rig: GDScript = preload("res://tests/support/net_session_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
const CROSS_TICKS: int = 30
const STAGGER_TICKS: int = 12
const PIT_MARGIN: float = 3.0
## How far a mirror may trail the host's copy of a body that is standing still.
const AGREE_METRES: float = 0.5
const APART_METRES: float = 0.75

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


## Connect, choose [param map] and launch with [param guard_seat] in the tower (-1 opens with the race).
func _launch(map: StringName, clients: int, seats: int, guard_seat: int, host_first: bool, brawl: bool = false) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().map_id = map
	_rig.settings().tower_brawl = brawl
	if not await _rig.launch_staged(seats, guard_seat, _order(host_first), STAGGER_TICKS):
		fail("the match never started on every machine")
		return false
	var wanted: MatchController.Phase = MatchController.Phase.ROUND
	if guard_seat < 0:
		wanted = MatchController.Phase.BRAWL if brawl else MatchController.Phase.RACE
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == wanted):
			fail("peer %d never reached the opening phase (it is in %s)" % [peer, controller.get_phase_name()])
			return false
	for peer: int in range(1, _rig.peer_count()):
		var link: PlayerNetLink = _rig.net_match(peer).get_local_link()
		if not await _rig.wait_for(func() -> bool: return link.is_predicting()):
			fail("peer %d's own body was never placed" % peer)
			return false
	await step_ticks(CROSS_TICKS)
	return true


func _pit_line(peer: int) -> float:
	var controller: MatchController = _rig.controller(peer)
	var start: Marker3D = controller.arena.get_node(controller.start_marker_path) as Marker3D
	var tower: Marker3D = controller.arena.get_node(controller.spawn_marker_path) as Marker3D
	return minf(start.global_position.y, tower.global_position.y) - PIT_MARGIN


func _tower_point(peer: int) -> Vector3:
	var controller: MatchController = _rig.controller(peer)
	return (controller.arena.get_node(controller.spawn_marker_path) as Marker3D).global_position


## The host's trackers run to the portal of the map that stands, and that map is the chosen one.
func _assert_the_portal_is_the_standing_maps(map: StringName) -> void:
	var wanted: String = MapCatalog.scene_path_for(map)
	for peer: int in _rig.peer_count():
		assert_eq_string(_rig.controller(peer).arena.scene_file_path, wanted, "peer %d stands on the chosen map" % peer)
	var gate: Area3D = _rig.gate(HOST)
	if not assert_not_null(gate, "the host's map has a portal"):
		return
	for participant: MatchParticipant in _rig.controller(HOST).get_participants():
		if not participant.is_running:
			continue
		var held: Variant = participant.tracker.get(&"_gate")
		assert_true(is_instance_valid(held), "slot %d's tracker holds a live portal" % participant.index)
		assert_true(is_instance_valid(held) and held == gate, "slot %d's tracker holds the standing map's portal" % participant.index)
		assert_true(participant.tracker.is_counting(), "slot %d's lap is being counted" % participant.index)


func _assert_no_engine_error(why: String) -> void:
	var first: String = _log.lines[0] if _log.count() > 0 else ""
	assert_eq_int(_log.count(), 0, "engine errors %s (first: %s)" % [why, first])


## Every machine has [param slot] in the tower as the guard of round [param round_number].
func _assert_the_seat(slot: int, round_number: int, why: String) -> void:
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_eq_int(int(controller.get_phase()), int(MatchController.Phase.ROUND), "%s: peer %d is in a round" % [why, peer])
		assert_eq_int(controller.get_round_number(), round_number, "%s: peer %d counts the round" % [why, peer])
		assert_same(controller.get_seat_participant(), _rig.participant(peer, slot), "%s: peer %d has slot %d in the tower" % [why, peer, slot])
		assert_true(_rig.participant(peer, slot).is_shooter, "%s: peer %d has it as the guard" % [why, peer])
		var at: Vector3 = _rig.body(peer, slot).global_position
		assert_lt(at.distance_to(_tower_point(peer)), 2.0, "%s: peer %d draws the guard in the tower (at %s)" % [why, peer, at])
		for participant: MatchParticipant in controller.get_participants():
			if participant.index != slot:
				assert_true(participant.is_running, "%s: peer %d has slot %d running" % [why, peer, participant.index])
				assert_false(participant.is_shooter, "%s: peer %d has one guard only" % [why, peer])


## The opening race on [param map]: a client crosses the portal first and holds the tower on every machine.
func _a_client_wins_the_opening_race(map: StringName, clients: int, host_first: bool) -> void:
	if not await _launch(map, clients, clients + 3, -1, host_first):
		return
	_assert_the_portal_is_the_standing_maps(map)
	var slot: int = _rig.local_slot(CLIENT)
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	_rig.stand_in_gate(slot)
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d: standing in the portal did not end the race" % peer)
			return
	await step_ticks(CROSS_TICKS)
	_assert_the_seat(slot, 1, "after the race")
	_assert_the_portal_is_the_standing_maps(map)
	_assert_no_engine_error("over the opening race")


func test_hell_two_machines_a_client_wins_the_race_clients_loaded_first() -> void:
	await _a_client_wins_the_opening_race(HELL, 1, false)


func test_marble_two_machines_a_client_wins_the_race_clients_loaded_first() -> void:
	await _a_client_wins_the_opening_race(MARBLE, 1, false)


func test_marble_two_machines_a_client_wins_the_race_host_loaded_first() -> void:
	await _a_client_wins_the_opening_race(MARBLE, 1, true)


func test_hell_four_machines_a_client_wins_the_race_host_loaded_first() -> void:
	await _a_client_wins_the_opening_race(HELL, 3, true)


func test_marble_four_machines_a_client_wins_the_race_clients_loaded_first() -> void:
	await _a_client_wins_the_opening_race(MARBLE, 3, false)


## One tap of shove on [param peer]'s own device.
func _tap_shove(peer: int) -> void:
	var input: BotIntentSource = (_rig.matches[peer].get_node("Player") as PlayerController).intent_source as BotIntentSource
	input.command.shove_pressed = true


## A round with the host in the tower: a client reaches the portal, is put in the tower, shoves the guard out and takes it.
func _a_client_takes_the_tower_through_the_portal(map: StringName, clients: int) -> void:
	if not await _launch(map, clients, clients + 3, HOST, true):
		return
	_assert_the_portal_is_the_standing_maps(map)
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	var deaths: Array[int] = []
	host.participant_converted.connect(func(who: MatchParticipant) -> void: deaths.append(who.index))
	host.ghost_fell.connect(func(who: MatchParticipant) -> void: deaths.append(who.index))
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	_rig.participant(HOST, HOST).body.movement_locked = false
	_rig.stand_in_gate(slot)
	# From the portal to the tower, every tick, on every machine: never in the pit, never dead.
	var armed_on_all: bool = false
	for _tick: int in 150:
		await step_ticks(1)
		armed_on_all = true
		for peer: int in _rig.peer_count():
			var seen: MatchParticipant = _rig.participant(peer, slot)
			assert_gt(seen.body.global_position.y, _pit_line(peer), "peer %d never draws the finisher in the pit (at %s)" % [peer, seen.body.global_position])
			assert_false(seen.is_ghost, "peer %d never has the finisher dead" % peer)
			armed_on_all = armed_on_all and seen.is_finisher
		if is_failed():
			return
		if armed_on_all and _rig.body(HOST, slot).is_physics_processing() and _rig.body(CLIENT, slot).is_physics_processing():
			break
	if not assert_true(armed_on_all, "every machine learned the client is the finisher"):
		return
	await step_ticks(CROSS_TICKS)
	assert_false(deaths.has(slot), "the host never ruled the finisher dead on the way up")
	for peer: int in _rig.peer_count():
		var at: Vector3 = _rig.body(peer, slot).global_position
		assert_lt(at.distance_to(_tower_point(peer)), MatchController.FINISHER_TOWER_OFFSET + 1.5, "peer %d draws the finisher in the tower room (at %s)" % [peer, at])
		assert_same(_rig.controller(peer).get_finisher(), _rig.participant(peer, slot), "peer %d knows who the finisher is" % peer)
	assert_true(_rig.body(CLIENT, slot).is_physics_processing(), "the client has its body back in the tower")
	# The client's own key, over the wire: the shove that throws the guard.
	var beats: Array[int] = []
	host.kill_beat_started.connect(func(guard: MatchParticipant, _seconds: float, _throw: Vector3) -> void: beats.append(guard.index))
	_tap_shove(CLIENT)
	if not await _rig.wait_for(func() -> bool: return not beats.is_empty()):
		fail("the client's shove in the tower did not throw the guard (finisher at %s facing %.2f, guard at %s)" % [
			_rig.body(HOST, slot).global_position, _rig.body(HOST, slot).rotation.y, _rig.body(HOST, HOST).global_position])
		return
	assert_eq_int(beats[0], HOST, "it is the guard who is thrown")
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_round_number() == 2):
			fail("peer %d never saw the round turn over" % peer)
			return
	await step_ticks(CROSS_TICKS)
	_assert_the_seat(slot, 2, "after the finale")
	for peer: int in _rig.peer_count():
		assert_null(_rig.controller(peer).get_finisher(), "peer %d has no finisher in the new round" % peer)
		assert_eq_int(_rig.participant(peer, slot).rounds_won, _rig.participant(HOST, slot).rounds_won, "peer %d agrees on the client's score" % peer)
	_assert_no_engine_error("from the portal to the next round")


func test_hell_two_machines_a_client_takes_the_tower_through_the_portal() -> void:
	await _a_client_takes_the_tower_through_the_portal(HELL, 1)


func test_marble_two_machines_a_client_takes_the_tower_through_the_portal() -> void:
	await _a_client_takes_the_tower_through_the_portal(MARBLE, 1)


func test_hell_four_machines_a_client_takes_the_tower_through_the_portal() -> void:
	await _a_client_takes_the_tower_through_the_portal(HELL, 3)


func test_marble_four_machines_a_client_takes_the_tower_through_the_portal() -> void:
	await _a_client_takes_the_tower_through_the_portal(MARBLE, 3)


## Every body [param who] names stands over floor, clear of the map and of the others, and where the host has it.
func _assert_placed(who: Array[MatchParticipant], why: String) -> void:
	var host: MatchController = _rig.controller(HOST)
	var space: PhysicsDirectSpaceState3D = host.arena.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for participant: MatchParticipant in host.get_participants():
		exclude.append(participant.body.get_rid())
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	for participant: MatchParticipant in who:
		var at: Vector3 = participant.body.global_position
		var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 2.5, 1, exclude))
		assert_false(down.is_empty(), "%s: slot %d stands over floor at %s" % [why, participant.index, at])
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.95)
		query.collision_mask = 1
		query.exclude = exclude
		assert_true(space.intersect_shape(query, 4).is_empty(), "%s: slot %d is clear of the map at %s" % [why, participant.index, at])
		for other: MatchParticipant in who:
			if other.index > participant.index:
				var gap: Vector3 = other.body.global_position - at
				gap.y = 0.0
				assert_gt(gap.length(), APART_METRES, "%s: slots %d and %d stand apart" % [why, participant.index, other.index])
		for peer: int in range(1, _rig.peer_count()):
			var seen: Vector3 = _rig.body(peer, participant.index).global_position
			assert_lt(seen.distance_to(at), AGREE_METRES, "%s: peer %d draws slot %d where the host has it (%s against %s)" % [why, peer, participant.index, seen, at])


## Four people and four bots: the race start, then the runner start, the same on every machine.
func _eight_take_their_places(map: StringName) -> void:
	if not await _launch(map, 3, 8, -1, true):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	for peer: int in _rig.peer_count():
		assert_eq_int(_rig.controller(peer).get_participants().size(), 8, "peer %d fields eight" % peer)
	await step_ticks(CROSS_TICKS)
	_assert_placed(host.get_participants(), "%s race start" % map)
	_rig.stand_in_gate(_rig.local_slot(2))
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never left the race" % peer)
			return
	TestFixtures.pin_the_field(host, null)
	await step_ticks(CROSS_TICKS * 2)
	var runners: Array[MatchParticipant] = []
	for participant: MatchParticipant in host.get_participants():
		if participant.is_running:
			runners.append(participant)
	assert_eq_int(runners.size(), 7, "%s: seven run the first round" % map)
	_assert_placed(runners, "%s runner start" % map)
	_assert_the_seat(_rig.local_slot(2), 1, "%s, eight seats" % map)
	_assert_no_engine_error("with eight seats")


func test_hell_four_people_and_four_bots_take_the_same_places_on_every_machine() -> void:
	await _eight_take_their_places(HELL)


func test_marble_four_people_and_four_bots_take_the_same_places_on_every_machine() -> void:
	await _eight_take_their_places(MARBLE)


## The tower fight: everybody in the tower room on every machine, the fallen out on every machine, the last one the guard.
func _a_tower_fight_is_the_same_everywhere(map: StringName, clients: int) -> void:
	if not await _launch(map, clients, clients + 2, -1, true, true):
		return
	var host: MatchController = _rig.controller(HOST)
	var count: int = host.get_participants().size()
	for participant: MatchParticipant in host.get_participants():
		participant.body.movement_locked = true
		if participant.brain != null:
			participant.brain.set_physics_process(false)
	await step_ticks(CROSS_TICKS)
	for peer: int in _rig.peer_count():
		for participant: MatchParticipant in _rig.controller(peer).get_participants():
			var at: Vector3 = participant.body.global_position
			assert_true(participant.is_running, "peer %d has slot %d in the fight" % [peer, participant.index])
			assert_lt(Vector2(at.x - _tower_point(peer).x, at.z - _tower_point(peer).z).length(), 8.0, "peer %d draws slot %d in the tower room (at %s)" % [peer, participant.index, at])
			assert_lt(at.distance_to(_rig.body(HOST, participant.index).global_position), AGREE_METRES, "peer %d draws slot %d where the host has it" % [peer, participant.index])
	if is_failed():
		return
	# Everybody but the last client goes over the edge, one at a time, as a fall does it.
	var winner: int = _rig.local_slot(clients)
	for slot: int in count:
		if slot == winner:
			continue
		_rig.body(HOST, slot).global_position += Vector3.DOWN * 12.0
		for peer: int in _rig.peer_count():
			var seen: MatchParticipant = _rig.participant(peer, slot)
			if not await _rig.wait_for(func() -> bool: return not seen.is_running):
				fail("peer %d never saw slot %d go out of the fight" % [peer, slot])
				return
		for peer: int in _rig.peer_count():
			assert_true(_rig.participant(peer, winner).is_running, "peer %d still has the last one standing" % peer)
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND, 8000):
			fail("peer %d never left the tower fight (it is in %s)" % [peer, controller.get_phase_name()])
			return
	await step_ticks(CROSS_TICKS)
	_assert_the_seat(winner, 1, "after the tower fight")
	for peer: int in _rig.peer_count():
		assert_false(_rig.controller(peer).is_tower_open(), "peer %d has the tower closed for the round" % peer)
		assert_true(_rig.body(peer, _rig.local_slot(peer)).is_physics_processing(), "peer %d simulates its own body in the round" % peer)
	_assert_no_engine_error("over the tower fight")


func test_hell_two_machines_fight_for_the_tower() -> void:
	await _a_tower_fight_is_the_same_everywhere(HELL, 1)


func test_marble_two_machines_fight_for_the_tower() -> void:
	await _a_tower_fight_is_the_same_everywhere(MARBLE, 1)


func test_hell_four_machines_fight_for_the_tower() -> void:
	await _a_tower_fight_is_the_same_everywhere(HELL, 3)


func test_marble_four_machines_fight_for_the_tower() -> void:
	await _a_tower_fight_is_the_same_everywhere(MARBLE, 3)
