extends TestCase
## Review proofs (match flow): the tower-fight opening vs a late peer and vs a leaver.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _start_brawl(clients: int, seats: int, late: Array[int] = []) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().tower_brawl = true
	if not await _rig.launch(seats, -1, late):
		fail("launch")
		return false
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.BRAWL):
		fail("the host never opened with the tower fight (phase %s)" % host.get_phase_name())
		return false
	return true


func test_control_an_on_time_client_is_in_the_tower_fight() -> void:
	if not await _start_brawl(1, 4):
		return
	var mirror: MatchController = _rig.controller(1)
	var there: bool = await _rig.wait_for(func() -> bool: return mirror.get_phase() == MatchController.Phase.BRAWL)
	assert_true(there, "an on-time client replays the brawl opening")
	assert_true(mirror.is_tower_open(), "with the tower's walls open")


func test_a_late_peer_joins_the_tower_fight_it_arrived_in() -> void:
	if not await _start_brawl(2, 4, [2]):
		return
	var host: MatchController = _rig.controller(HOST)
	# Keep the fight going while the late peer binds: nobody can be pushed out by a bot that cannot swing.
	for participant: MatchParticipant in host.get_participants():
		participant.body.shove_cooldown_remaining = 600.0
	if not await _rig.bind_late(2):
		fail("the late peer never bound")
		return
	await step_ticks(30)
	var late: MatchController = _rig.controller(2)
	var own: int = _rig.local_slot(2)
	print("PROOF late-in-brawl: host phase=%s tower_open=%s | late phase=%s tower_open=%s own.is_running=%s (host says %s) brawl_floor=%s" % [
		host.get_phase_name(), str(host.is_tower_open()), late.get_phase_name(), str(late.is_tower_open()),
		str(_rig.participant(2, own).is_running), str(_rig.participant(HOST, own).is_running),
		str(is_instance_valid(late.get(&"_brawl_floor")))])
	assert_eq_int(int(host.get_phase()), int(MatchController.Phase.BRAWL), "the host is still in the tower fight")
	assert_eq_int(int(late.get_phase()), int(host.get_phase()), "the late peer is in the phase the host is in")
	assert_true(late.is_tower_open(), "the late peer's tower is open like the host's")
	# And a fighter thrown out now: does the late peer see it go?
	var victim: MatchParticipant = _rig.participant(HOST, 3)
	host.call(&"_brawl_out", victim, Vector3(8.0, 2.0, 0.0))
	await step_ticks(30)
	print("PROOF late-in-brawl: slot 3 out on host is_running=%s, on late peer is_running=%s limp=%s" % [
		str(victim.is_running), str(_rig.participant(2, 3).is_running), str(_rig.ragdoll(2, 3).is_active())])
	assert_true(_rig.ragdoll(2, 3).is_active(), "the late peer sees a thrown fighter go limp")


func test_a_late_peer_finds_a_fighter_thrown_before_it_arrived_already_out() -> void:
	if not await _start_brawl(2, 5, [2]):
		return
	var host: MatchController = _rig.controller(HOST)
	for participant: MatchParticipant in host.get_participants():
		participant.body.shove_cooldown_remaining = 600.0
	host.call(&"_brawl_out", _rig.participant(HOST, 4), Vector3(8.0, 2.0, 0.0))
	await step_ticks(10)
	if not await _rig.bind_late(2):
		fail("the late peer never bound")
		return
	await step_ticks(30)
	assert_eq_int(int(host.get_phase()), int(MatchController.Phase.BRAWL), "the host is still in the tower fight")
	assert_false(_rig.participant(2, 4).is_running, "the late peer holds the thrown fighter out")
	assert_true(_rig.participant(2, 3).is_running, "and the one still standing in")


func test_a_fighter_whose_player_leaves_fights_on_as_a_brawl_bot() -> void:
	if not await _start_brawl(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	for participant: MatchParticipant in host.get_participants():
		participant.body.shove_cooldown_remaining = 600.0
	await step_ticks(10)
	# How a bot born a bot stands in the fight: lap brain silent, lap tracker stopped.
	var native: MatchParticipant = _rig.participant(HOST, 3)
	assert_false(native.brain.is_physics_processing(), "a bot fighter's lap brain is silent")
	_rig.sessions[1].leave()
	if not await _rig.wait_for(func() -> bool: return not _rig.participant(HOST, 1).is_human()):
		fail("the seat never turned bot")
		return
	var taken: MatchParticipant = _rig.participant(HOST, 1)
	await step_ticks(5)
	print("PROOF leaver-in-brawl: phase=%s taken.brain_processing=%s (native %s) tracker_processing=%s (native %s) shove_enabled=%s (native %s)" % [
		host.get_phase_name(), str(taken.brain.is_physics_processing()), str(native.brain.is_physics_processing()),
		str(taken.tracker.is_physics_processing()), str(native.tracker.is_physics_processing()),
		str(taken.brain.input.shove_enabled), str(native.brain.input.shove_enabled)])
	assert_eq_int(int(host.get_phase()), int(MatchController.Phase.BRAWL), "still the tower fight")
	assert_false(taken.brain.is_physics_processing(), "the taken-over fighter's lap brain is silent like any brawl bot's")
	# Where does it go? A brawl bot holds the room; a lap brain walks for the ring.
	var floor_y: float = float(host.get(&"_brawl_floor_y"))
	var fell_at: int = -1
	var steered: bool = false
	for tick: int in 600:
		await step_ticks(1)
		steered = steered or taken.brain.input.command.move_direction.length() > 0.01
		if not taken.is_running:
			fell_at = tick
			break
	assert_true(steered, "the tower fight drives the taken-over fighter as it drives any bot")
	print("PROOF leaver-in-brawl: out of the fight after %d ticks (-1 = still standing), y=%.2f floor=%.2f" % [
		fell_at, taken.body.global_position.y, floor_y])
	assert_eq_int(fell_at, -1, "nobody can shove (cooldowns held): the taken-over fighter does not leave the tower by itself")
