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
