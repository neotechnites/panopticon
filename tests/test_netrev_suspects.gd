extends TestCase
## Review suspects (match flow), each proven here before its fix: an instant respawn against a
## mirror, and a restart inside the finale's kill beat.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CLIENT: int = 1

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## Host in the tower (seat 0), the client and bots on the ring.
func _start_round(seats: int) -> bool:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 3
	if not await _rig.launch(seats, 0):
		fail("launch")
		return false
	for peer: int in _rig.sessions.size():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(30)
	return true


## The debug slider's floor: with no respawn delay the host respawns a ghost inside its conversion.
func test_a_ghost_respawned_at_once_is_not_left_frozen_on_a_client() -> void:
	if not await _start_round(4):
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	host.get_ghost_profile().respawn_delay_seconds = 0.0
	TestFixtures.pin_the_field(host, null)
	var slot: int = _rig.local_slot(CLIENT)
	assert_true(host.convert_participant(_rig.participant(HOST, slot)), "the host converts the client's runner")
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	if not await _rig.wait_for(func() -> bool: return mine.is_ghost):
		fail("the client never saw its runner die")
		return
	await step_ticks(60)
	var on_host: MatchParticipant = _rig.participant(HOST, slot)
	print("PROOF instant-respawn: host ghost body simulated=%s awaiting=%s | client's own ghost simulated=%s awaiting=%s" % [
		str(on_host.body.is_physics_processing()), str(host.is_awaiting_respawn(on_host)),
		str(mine.body.is_physics_processing()), str(mirror.is_awaiting_respawn(mine))])
	assert_true(on_host.body.is_physics_processing(), "the host's ghost is up and running")
	assert_false(mirror.is_awaiting_respawn(mine), "the client is not left waiting on a respawn that has happened")
	assert_true(mine.body.is_physics_processing(), "and its own ghost moves")


## A restart (the debug menu's, mid-finale) into an opening race: the old round's beat must not score in it.
func test_a_restart_inside_the_kill_beat_does_not_score_into_the_new_match() -> void:
	if not await _start_round(3):
		return
	var host: MatchController = _rig.controller(HOST)
	var guard: MatchParticipant = _rig.participant(HOST, 0)
	var finisher: MatchParticipant = _rig.participant(HOST, 2)
	TestFixtures.pin_the_field(host, finisher)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return finisher.body.is_physics_processing()):
		fail("the finisher never landed in the tower")
		return
	assert_same(host.apply_shove(finisher), guard, "the finisher's shove takes the guard")
	var beat: float = float(host.get(&"_kill_beat_remaining"))
	assert_gt(beat, 0.0, "the kill beat is running")
	host.get_rules().open_with_race = true
	host.restart()
	assert_eq_int(int(host.get_phase()), int(MatchController.Phase.RACE), "the restart opens with the race")
	await step_ticks(int(beat * SIM_HZ) + 30)
	var mirror: MatchController = _rig.controller(CLIENT)
	print("PROOF restart-in-beat: %.2f s after the restart the host is in %s (seat %s), the client in %s" % [
		beat + 0.5, host.get_phase_name(), str(host.get_seat_participant() != null), mirror.get_phase_name()])
	assert_eq_int(int(host.get_phase()), int(MatchController.Phase.RACE), "the race is still the race when the old beat would have ended")
	assert_null(host.get_seat_participant(), "and nobody was handed the tower by it")
	assert_eq_int(int(mirror.get_phase()), int(MatchController.Phase.RACE), "the client agrees")
