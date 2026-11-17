extends TestCase
## Death, ragdoll, ghost and finale as every peer sees them: the shipped match scene on real sockets.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
## Ticks for a reliable event and the snapshots behind it to cross loopback and be drawn.
const CROSS_TICKS: int = 30

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## Host in the tower, one client and one bot on the ring, the round running on both machines.
func _start_round(clients: int = 1, seats: int = 3, guard_seat: int = 0) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	if not await _rig.launch(seats, guard_seat):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.sessions.size():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(CROSS_TICKS)
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
	await step_ticks(CROSS_TICKS)
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
	await step_ticks(CROSS_TICKS)
	return true


## One rifle kill of [param slot], watched from death to respawn on every peer.
func _watch_a_rifle_kill(slot: int) -> void:
	var before: Array = []
	for peer: int in _rig.peer_count():
		before.append(_worn(peer, slot))
	_shoot(slot)
	assert_true(_rig.participant(HOST, slot).is_ghost, "the hit converts slot %d on the host" % slot)
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
