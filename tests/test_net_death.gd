extends TestCase
## Death, ragdoll, ghost and finale as every peer sees them: the shipped match scene on real sockets.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
## Ticks for a reliable event and the snapshots behind it to cross loopback and be drawn.
const CROSS_TICKS: int = 30
## The same on a bad line: the runner compresses time fiftyfold, so 3 real ms each way is 150 ms of play.
const BAD_LINE_TICKS: int = 120
const BAD_LINE_LOSS: float = 0.1
const BAD_LINE_DELAY_MS: int = 3

var _rig: RefCounted = null
var _cross: int = CROSS_TICKS
var _bad_line: bool = false


func before_each() -> void:
	_rig = Rig.new()
	_cross = CROSS_TICKS
	_bad_line = false


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## Host in the tower, one client and one bot on the ring, the round running on both machines.
func _start_round(clients: int = 1, seats: int = 3, guard_seat: int = 0, late: Array[int] = []) -> bool:
	if _bad_line:
		_rig.wire_loss = BAD_LINE_LOSS
		_rig.wire_delay_ms = BAD_LINE_DELAY_MS
		_cross = BAD_LINE_TICKS
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	# A finale kill must turn the round over, not end the match.
	_rig.settings().rounds_to_win_match = 3
	if not await _rig.launch(seats, guard_seat, late):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.sessions.size():
		if late.has(peer):
			continue
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(_cross)
	return true


func test_a_killed_client_runs_again_as_a_ghost_on_its_own_machine() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(host, host.get_participants()[slot])
	assert_true(host.convert_participant(host.get_participants()[slot]), "the host converts the client's runner")
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	if not await _rig.wait_for(func() -> bool: return mine.is_ghost):
		fail("the client never learned it died")
		return
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	if not await _rig.wait_for(
		func() -> bool: return host_side.is_ghost and host_side.body.is_physics_processing()
	):
		fail("the host never woke the ghost")
		return
	await step_ticks(_cross)
	assert_true(mine.body.is_physics_processing(), "the client's own ghost is simulated again after its respawn")
	var from: Vector3 = host_side.body.global_position
	_rig.drive(CLIENT, Vector2(0.0, 1.0))
	await step_ticks(90)
	assert_gt(host_side.body.global_position.distance_to(from), 1.0, "and the ghost the client drives moves on the host")


## Every material the drawn body wears, surface by surface, as [param peer] holds it.
func _worn(peer: int, slot: int) -> Array[Material]:
	var mesh: MeshInstance3D = _rig.avatar(peer, slot).mesh
	var worn: Array[Material] = [mesh.material_override]
	for index: int in mesh.mesh.get_surface_count():
		worn.append(mesh.get_surface_override_material(index))
	return worn


## A rifle hit on [param slot], landed on the host as the rifle lands one.
func _shoot(slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	var body: PlayerController = _rig.body(HOST, slot)
	host.rifle.show_remote_hit(body, body.global_position + Vector3.UP, Vector3.BACK)


## True once every peer draws [param slot] limp; fails naming the peers that do not.
func _every_peer_sees_limp(slot: int, why: String) -> bool:
	var seen: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.ragdoll(peer, slot).is_active():
				return false
		return true)
	if not seen:
		for peer: int in _rig.peer_count():
			assert_true(_rig.ragdoll(peer, slot).is_active(), "peer %d draws slot %d limp %s" % [peer, slot, why])
	return seen


## The host's ghost in [param slot] is back in the world, and the peers have heard.
func _respawned(slot: int) -> bool:
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	if not await _rig.wait_for(
		func() -> bool: return host_side.is_ghost and host_side.body.is_physics_processing()
	):
		fail("the host never put slot %d back as a ghost" % slot)
		return false
	await step_ticks(_cross)
	return true


## One rifle kill of [param slot], watched from death to respawn on every peer.
func _watch_a_rifle_kill(slot: int) -> void:
	var before: Array = []
	for peer: int in _rig.peer_count():
		before.append(_worn(peer, slot))
	_shoot(slot)
	assert_true(_rig.participant(HOST, slot).is_ghost, "the hit converts slot %d on the host" % slot)
	# The ghost included, its chase called off: a chasing ghost's shove is a catch, and a swap ends the watch early.
	TestFixtures.pin_the_field(_rig.controller(HOST), null)
	_rig.controller(HOST).call(&"_silence_brain", _rig.participant(HOST, slot))
	if not await _every_peer_sees_limp(slot, "after the rifle kill"):
		return
	await step_ticks(60)
	for peer: int in _rig.peer_count():
		assert_true(_rig.ragdoll(peer, slot).is_active(), "peer %d still draws slot %d limp a second later" % [peer, slot])
		assert_true(_rig.participant(peer, slot).is_ghost, "peer %d holds slot %d as a ghost" % [peer, slot])
		var worn: Array[Material] = _worn(peer, slot)
		for index: int in worn.size():
			assert_same(worn[index], before[peer][index], "peer %d: the corpse of slot %d wears what it wore alive (surface %d)" % [peer, slot, index - 1])
	if not await _respawned(slot):
		return
	for peer: int in _rig.peer_count():
		assert_false(_rig.ragdoll(peer, slot).is_active(), "peer %d: slot %d is no corpse after its respawn" % [peer, slot])
		assert_false(_lies_dead(peer, slot), "peer %d: slot %d stands at the start line, not in the death pose" % [peer, slot])
		var colour: Color = _rig.controller(peer).get_body_color(_rig.participant(peer, slot))
		assert_lt(colour.a, 1.0, "peer %d: the respawned ghost in slot %d wears the ghost colour" % [peer, slot])


## Whether [param peer] draws [param slot] dead: limp, or on the death clip.
func _lies_dead(peer: int, slot: int) -> bool:
	var avatar: PrisonerAvatar = _rig.avatar(peer, slot)
	return _rig.ragdoll(peer, slot).is_active() or bool(avatar.get(&"_dead"))


func test_a_shot_client_goes_limp_on_every_peer_and_stands_again() -> void:
	if not await _start_round(2, 4):
		return
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, slot))
	await _watch_a_rifle_kill(slot)


func test_a_shot_bot_goes_limp_on_every_peer_and_stands_again() -> void:
	if not await _start_round(2, 4):
		return
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, 3))
	await _watch_a_rifle_kill(3)


func test_a_fallen_runner_plays_dead_on_every_peer_and_stands_again_without_moving() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	assert_true(host.handle_fall(_rig.participant(HOST, slot)), "the host rules the lava death")
	var dead: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _lies_dead(peer, slot):
				return false
		return true)
	for peer: int in _rig.peer_count():
		assert_true(dead or _lies_dead(peer, slot), "peer %d draws the lava death" % peer)
		assert_false(_rig.ragdoll(peer, slot).is_active(), "peer %d: a lava death is the clip, not a limp body" % peer)
	if not await _respawned(slot):
		return
	for peer: int in _rig.peer_count():
		assert_false(_lies_dead(peer, slot), "peer %d: the respawned ghost stands, though it has not moved" % peer)


func test_a_killed_client_is_shown_its_death_and_its_countdown() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	var screen: MatchDeathScreen = _rig.matches[CLIENT].get_node("DeathScreen") as MatchDeathScreen
	var view: FxSpectatorView = _rig.matches[CLIENT].get_node("SpectatorView") as FxSpectatorView
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	assert_false(screen.is_showing(), "no death screen on a living client")
	_shoot(slot)
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	if not await _rig.wait_for(func() -> bool: return screen.is_showing() and view.is_active()):
		assert_true(screen.is_showing(), "the client is shown the death screen")
		assert_true(view.is_active(), "the client is given the death camera")
		return
	assert_eq_int(
		int(mirror.get_spectating_state(mine)), int(MatchController.Spectating.RESPAWNING),
		"the client knows it is waiting on a respawn"
	)
	assert_eq_int(int(mine.death_cause), int(MatchParticipant.DeathCause.SHOT), "and that it was shot")
	var first: float = mirror.get_respawn_hold_remaining(mine)
	assert_gt(first, 0.0, "the countdown has time on it")
	await step_ticks(30)
	assert_lt(mirror.get_respawn_hold_remaining(mine), first, "and it runs down")
	if not await _respawned(slot):
		return
	assert_false(screen.is_showing(), "the death screen hands back at the respawn")
	assert_false(view.is_active(), "and so does the camera")


func test_a_shot_host_goes_limp_on_every_peer_and_stands_again() -> void:
	if not await _start_round(2, 4, 1):
		return
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, 0))
	await _watch_a_rifle_kill(0)


func test_a_client_is_told_what_killed_it() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	assert_true(host.handle_fall(_rig.participant(HOST, 1)), "the host rules a lava death")
	assert_true(host.handle_fall(_rig.participant(HOST, 2), true), "and a fall into the pit")
	if not await _rig.wait_for(func() -> bool:
		return _rig.participant(2, 1).is_ghost and _rig.participant(1, 2).is_ghost and _rig.participant(1, 1).is_ghost):
		fail("the deaths never reached the clients")
		return
	for peer: int in [1, 2]:
		assert_eq_int(int(_rig.participant(peer, 1).death_cause), int(MatchParticipant.DeathCause.LAVA), "peer %d knows slot 1 died in lava" % peer)
		assert_eq_int(int(_rig.participant(peer, 2).death_cause), int(MatchParticipant.DeathCause.FELL), "peer %d knows slot 2 fell" % peer)


func test_a_client_ghost_that_falls_again_is_held_and_shown_its_respawn() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	_shoot(slot)
	if not await _respawned(slot):
		return
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	assert_true(mine.body.is_physics_processing(), "the client's ghost is running")
	assert_true(host.handle_fall(_rig.participant(HOST, slot)), "the host rules the ghost's fall into lava")
	if not await _rig.wait_for(func() -> bool: return mirror.is_awaiting_respawn(mine)):
		fail("the client was never told its ghost fell: no hold, no countdown, no death view")
		return
	assert_false(mine.body.is_physics_processing(), "the client's ghost is held where it fell")
	assert_eq_int(int(mine.death_cause), int(MatchParticipant.DeathCause.LAVA), "and the client knows it was the lava")
	if not await _respawned(slot):
		return
	assert_false(mirror.is_awaiting_respawn(mine), "the hold ends at the respawn")
	assert_true(mine.body.is_physics_processing(), "and the client's ghost runs again")


func test_a_late_peer_finds_a_ghost_already_back_in_the_world() -> void:
	if not await _start_round(2, 4, 0, [2]):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	_shoot(1)
	_shoot(2)
	if not await _respawned(2):
		return
	if not await _rig.bind_late(2):
		fail("the late peer never bound")
		return
	await step_ticks(_cross)
	var late: MatchController = _rig.controller(2)
	for slot: int in [1, 2]:
		var ghost: MatchParticipant = _rig.participant(2, slot)
		assert_true(ghost.is_ghost, "the late peer holds slot %d as a ghost" % slot)
		assert_false(late.is_awaiting_respawn(ghost), "and not as one still waiting on a respawn that already landed")
		assert_lt(late.get_body_color(ghost).a, 1.0, "wearing the ghost colour")
	assert_true(_rig.body(2, 2).is_physics_processing(), "the late peer's own ghost is simulated")
	assert_false(_lies_dead(2, 1), "and nobody lies dead at the start line")


## The tower's colliders and their layers, as [param peer] holds them.
func _tower_layers(peer: int) -> Dictionary:
	var layers: Dictionary = {}
	var tower: Node = _rig.controller(peer).call(&"_tower_node")
	for node: Node in tower.find_children("*", "StaticBody3D", true, false):
		layers[node] = (node as StaticBody3D).collision_layer
	return layers


## The host arms [param finisher_slot], who shoves the guard out; watched to the next round on every peer.
func _watch_a_finale(guard_slot: int, finisher_slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, finisher_slot))
	var towers: Array[Dictionary] = []
	for peer: int in _rig.peer_count():
		towers.append(_tower_layers(peer))
	var finisher: MatchParticipant = _rig.participant(HOST, finisher_slot)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return finisher.body.is_physics_processing()):
		fail("the finisher never landed in the tower")
		return
	for peer: int in _rig.peer_count():
		var mirrored: MatchParticipant = _rig.participant(peer, finisher_slot)
		if not await _rig.wait_for(func() -> bool: return mirrored.is_finisher):
			fail("peer %d never learned who the finisher is" % peer)
			return
	var round_before: int = host.get_round_number()
	var beat_ticks: int = int(host.get_rules().kill_beat_seconds * SIM_HZ)
	assert_same(host.apply_shove(finisher), _rig.participant(HOST, guard_slot), "the finisher's shove takes the guard")
	if not await _every_peer_sees_limp(guard_slot, "on the finale shove"):
		return
	var held: Array[Vector3] = []
	for peer: int in _rig.peer_count():
		held.append(_rig.body(peer, guard_slot).global_position)
	# Most of the beat, measured on the host's clock: the guard stays down and both bodies stay put.
	var until: float = host.get_rules().kill_beat_seconds * 0.25
	while float(host.get(&"_kill_beat_remaining")) > until:
		await step_ticks(4)
		for peer: int in _rig.peer_count():
			if float(host.get(&"_kill_beat_remaining")) <= 0.0:
				break
			assert_true(_rig.ragdoll(peer, guard_slot).is_active(), "peer %d: the guard stays limp through the beat" % peer)
			assert_true(_rig.body(peer, guard_slot).movement_locked, "peer %d: the guard has no controls in the beat" % peer)
			assert_true(_rig.body(peer, finisher_slot).movement_locked, "peer %d: nor has the finisher" % peer)
			assert_false(_rig.body(peer, guard_slot).is_physics_processing(), "peer %d: the guard's capsule is held" % peer)
			assert_lt(_rig.body(peer, guard_slot).global_position.distance_to(held[peer]), 0.5, "peer %d: and it has not fallen out of the tower" % peer)
			assert_false(_rig.controller(peer).is_tower_open(), "peer %d: the tower stays solid" % peer)
		if is_failed():
			return
	assert_gt(float(beat_ticks), 0.0, "the shipped rules hold a kill beat")
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_round_number() == round_before + 1):
			fail("peer %d never saw the next round" % peer)
			return
	await step_ticks(_cross)
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_same(controller.get_seat_participant(), _rig.participant(peer, finisher_slot), "peer %d: the finisher holds the tower" % peer)
		assert_false(_rig.ragdoll(peer, guard_slot).is_active(), "peer %d: the thrown guard is no corpse in the new round" % peer)
		assert_false(_lies_dead(peer, guard_slot), "peer %d: and stands on the ring" % peer)
		assert_false(_rig.body(peer, guard_slot).movement_locked, "peer %d: the old guard has its controls back" % peer)
		assert_false(_rig.body(peer, finisher_slot).movement_locked, "peer %d: and so has the new one" % peer)
		assert_true(_rig.participant(peer, guard_slot).is_running, "peer %d: the old guard runs this round" % peer)
		var layers: Dictionary = _tower_layers(peer)
		for wall: Node in layers:
			assert_eq_int(int(layers[wall]), int(towers[peer][wall]), "peer %d: %s collides as it did" % [peer, wall.name])
	for peer: int in _rig.peer_count():
		var own: int = _rig.local_slot(peer)
		assert_true(_rig.body(peer, own).is_physics_processing(), "peer %d simulates its own body in the new round" % peer)


func test_a_client_guard_thrown_by_the_host_stays_down_for_the_beat() -> void:
	if not await _start_round(2, 4, 1):
		return
	await _watch_a_finale(1, 0)


func test_a_host_guard_thrown_by_a_client_stays_down_for_the_beat() -> void:
	if not await _start_round(2, 4, 0):
		return
	await _watch_a_finale(0, 1)


func test_a_bot_guard_thrown_by_a_bot_is_seen_by_every_peer() -> void:
	if not await _start_round(2, 5, 3):
		return
	await _watch_a_finale(3, 4)


func test_a_shot_client_goes_limp_on_every_peer_over_a_bad_line() -> void:
	_bad_line = true
	if not await _start_round(2, 4):
		return
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, slot))
	# Running when it is hit, so snapshots still in flight carry the run past the death.
	_rig.drive(CLIENT, Vector2(0.0, 1.0))
	await step_ticks(_cross)
	await _watch_a_rifle_kill(slot)


func test_a_running_bot_shot_over_a_bad_line_goes_limp_on_every_peer() -> void:
	_bad_line = true
	if not await _start_round(2, 4):
		return
	await step_ticks(_cross)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, 3))
	await _watch_a_rifle_kill(3)


func test_a_finale_over_a_bad_line_holds_on_every_peer() -> void:
	_bad_line = true
	if not await _start_round(2, 4, 1):
		return
	await _watch_a_finale(1, 0)
