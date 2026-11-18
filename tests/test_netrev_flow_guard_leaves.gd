extends TestCase
## Review proofs (match flow): the tower's player leaves, mid-round and inside the finale's kill beat.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0

var _rig: RefCounted = null
var _shots: Array[int] = [0]


func before_each() -> void:
	_rig = Rig.new()
	_shots = [0]


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## Client 1 in the tower (seat 1), host, client 2 and a bot on the ring.
func _start_round() -> bool:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 3
	if not await _rig.launch(4, 1):
		fail("launch")
		return false
	for peer: int in _rig.sessions.size():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(30)
	return true


func _guard_drops() -> bool:
	_rig.sessions[1].leave()
	return await _rig.wait_for(func() -> bool:
		return not _rig.participant(HOST, 1).is_human() and not _rig.participant(2, 1).is_human())


func test_control_a_guard_who_leaves_mid_round_is_carried_on_by_the_tower_bot() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	if not await _guard_drops():
		fail("the seat never turned bot")
		return
	var guard: MatchParticipant = _rig.participant(HOST, 1)
	var shooter: TowerShooter = host.call(&"_find_tower_brain", guard)
	print("PROOF guard leaves mid-round: tower brain=%s processing=%s body phys=%s is_shooter=%s" % [
		str(shooter != null), str(shooter != null and shooter.is_physics_processing()),
		str(moves(guard.body)), str(guard.is_shooter)])
	assert_true(shooter != null and shooter.is_physics_processing(), "a tower bot takes the rifle over")
	assert_true(moves(guard.body), "and the body is simulated")


func test_a_guard_who_leaves_inside_the_kill_beat_stays_dead_for_the_beat() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var finisher: MatchParticipant = _rig.participant(HOST, 0)
	var guard: MatchParticipant = _rig.participant(HOST, 1)
	TestFixtures.pin_the_field(host, finisher)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return moves(finisher.body)):
		fail("the finisher never landed in the tower")
		return
	host.rifle.fired.connect(func(_origin: Vector3, _end: Vector3) -> void: _shots[0] += 1)
	assert_same(host.apply_shove(finisher), guard, "the finisher's shove takes the guard")
	assert_gt(float(host.get(&"_kill_beat_remaining")), 0.0, "the kill beat is running")
	await step_ticks(6)
	if not await _guard_drops():
		fail("the seat never turned bot")
		return
	var beat_left: float = float(host.get(&"_kill_beat_remaining"))
	var shooter: TowerShooter = host.call(&"_find_tower_brain", guard)
	var awake: bool = shooter != null and shooter.is_physics_processing()
	print("PROOF guard leaves in kill beat: beat_left=%.2fs tower brain processing=%s body phys=%s locked=%s" % [
		beat_left, str(awake), str(moves(guard.body)), str(guard.body.movement_locked)])
	assert_gt(beat_left, 0.0, "the beat is still running when the seat turns bot")
	assert_false(moves(guard.body), "the thrown guard's capsule stays held")
	assert_false(awake, "and no tower brain is driving the dead guard's rifle during the beat")
	var round_before: int = host.get_round_number()
	while float(host.get(&"_kill_beat_remaining")) > 0.0:
		await step_ticks(2)
	print("PROOF guard leaves in kill beat: shots fired by the dead guard during the beat=%d ; next round=%s" % [
		_shots[0], str(host.get_round_number() == round_before + 1)])
	assert_eq_int(_shots[0], 0, "the dead guard fires nothing during its own death")
