extends TestCase
## Review proof: a peer whose match binds late while its own runner lies dead and held.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const LATE: int = 2

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func test_rv_a_late_peer_dead_at_bind_does_not_walk_its_corpse() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return
	_rig.settings().rounds_to_win_match = 3
	var late: Array[int] = [LATE]
	if not await _rig.launch(4, 0, late):
		fail("the match never started")
		return
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return
	await step_ticks(30)
	host.get_ghost_profile().respawn_delay_seconds = 600.0
	TestFixtures.pin_the_field(host, null)
	var slot: int = 2
	var body: PlayerController = _rig.body(HOST, slot)
	host.rifle.show_remote_hit(body, body.global_position + Vector3.UP, Vector3.BACK)
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	if not await _rig.wait_for(func() -> bool: return host_side.is_ghost and host.is_awaiting_respawn(host_side)):
		fail("the host never held the dead runner (ghost %s)" % str(host_side.is_ghost))
		return
	assert_false(moves(host_side.body), "the host holds the dead body")
	if not await _rig.bind_late(LATE):
		fail("the late peer never bound")
		return
	await step_ticks(60)
	var mirror: MatchController = _rig.controller(LATE)
	var own: int = _rig.local_slot(LATE)
	assert_eq_int(own, slot, "the late peer's own slot is the dead one")
	var mine: MatchParticipant = _rig.participant(LATE, slot)
	print("PROOF late-dead: late peer own body: ghost=%s awaiting=%s physics=%s ; host body physics=%s" % [
		str(mine.is_ghost), str(mirror.is_awaiting_respawn(mine)), str(moves(mine.body)),
		str(moves(host_side.body))])
	assert_true(mirror.is_awaiting_respawn(mine), "the late peer knows it is waiting on a respawn")
	assert_false(moves(mine.body), "and its held corpse is not simulated on its own machine")
	var from: Vector3 = mine.body.global_position
	var host_from: Vector3 = host_side.body.global_position
	_rig.drive(LATE, Vector2(0.0, 1.0))
	await step_ticks(90)
	var walked: float = mine.body.global_position.distance_to(from)
	var host_walked: float = host_side.body.global_position.distance_to(host_from)
	print("PROOF late-dead: with forward held 90 ticks the late peer's own copy moved %.2f m, the host's %.2f m" % [walked, host_walked])
	assert_true(walked < 0.2, "the dead player's own copy stays where the host holds it: it moved %.2f m" % walked)
	# The hold is the match's to lift: the respawn hands the body back to its own machine.
	host_side.respawn_hold_remaining = 0.05
	var back: bool = await _rig.wait_for(func() -> bool: return moves(mine.body))
	assert_true(back, "and the respawn wakes it on its own machine")
