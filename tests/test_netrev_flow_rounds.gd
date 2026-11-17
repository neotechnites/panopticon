extends TestCase
## Review proof (match flow): the rounds a guard has held, counted on a mirror.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CROSS_TICKS: int = 30

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _start_round(clients: int, seats: int, rounds_to_win: int) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = rounds_to_win
	if not await _rig.launch(seats, 0):
		fail("launch")
		return false
	for peer: int in _rig.sessions.size():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(CROSS_TICKS)
	return true


## The guard (host, slot 0) clears the ring: every runner converted, as the rifle converts them.
func _guard_clears_the_ring() -> void:
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	for participant: MatchParticipant in host.get_participants():
		if participant.is_running:
			host.convert_participant(participant)


## The guard holds a round: the host counts it; does the client?
func test_a_client_counts_the_rounds_the_guard_has_held() -> void:
	if not await _start_round(1, 3, 3):
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(1)
	for round_index: int in 2:
		var before: int = host.get_round_number()
		_guard_clears_the_ring()
		if not await _rig.wait_for(func() -> bool: return mirror.get_round_number() == before + 1):
			fail("the client never saw round %d" % (before + 1))
			return
		await step_ticks(CROSS_TICKS)
	var on_host: int = _rig.participant(HOST, 0).rounds_won
	var on_client: int = _rig.participant(1, 0).rounds_won
	print("PROOF rounds_won host=%d client=%d ; turns host=%d client=%d" % [
		on_host, on_client, _rig.participant(HOST, 0).turns_in_tower, _rig.participant(1, 0).turns_in_tower])
	assert_eq_int(on_host, 2, "the host counts two rounds held")
	assert_eq_int(on_client, on_host, "the client's copy of the guard has held as many rounds")
	assert_eq_int(_rig.participant(1, 0).turns_in_tower, _rig.participant(HOST, 0).turns_in_tower, "turns agree")
	# Third round: match over; what the client's result screen would print.
	_guard_clears_the_ring()
	if not await _rig.wait_for(func() -> bool: return mirror.is_match_over()):
		fail("the client never saw the match end")
		return
	var winner: MatchParticipant = mirror.get_match_winner()
	print("PROOF result screen rounds: host=%d client=%d" % [
		host.get_match_winner().rounds_won, winner.rounds_won if winner != null else -1])
	assert_eq_int(winner.rounds_won if winner != null else -1, 3, "the client's result names three rounds held")
