extends TestCase
## Review proofs (match flow): rematch votes against a leaver.

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


func _win_the_match() -> bool:
	var host: MatchController = _rig.controller(HOST)
	_guard_clears_the_ring()
	if not host.is_match_over():
		fail("clearing the ring did not end a one-round match (phase %s)" % host.get_phase_name())
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.is_match_over()):
			fail("peer %d never saw the match end" % peer)
			return false
	return true


## CONTROL: all three humans vote -> the rematch starts. Shows the test has teeth.
func test_control_every_human_votes_and_the_rematch_starts() -> void:
	if not await _start_round(2, 4, 1):
		return
	if not await _win_the_match():
		return
	var host: MatchController = _rig.controller(HOST)
	for peer: int in _rig.peer_count():
		_rig.net_match(peer).request_rematch()
	var restarted: bool = await _rig.wait_for(func() -> bool: return not host.is_match_over())
	assert_true(restarted, "with every human's vote in, the host restarts the match")


## Host and client 1 vote; client 2 quits instead. Every human still here has voted.
func test_a_rematch_starts_when_the_one_who_had_not_voted_leaves() -> void:
	if not await _start_round(2, 4, 1):
		return
	if not await _win_the_match():
		return
	var host: MatchController = _rig.controller(HOST)
	_rig.net_match(HOST).request_rematch()
	_rig.net_match(1).request_rematch()
	await step_ticks(CROSS_TICKS)
	assert_true(host.is_match_over(), "two of three votes do not restart it yet")
	_rig.sessions[2].leave()
	if not await _rig.wait_for(func() -> bool: return _rig.sessions[HOST].get_peer_count() == 2):
		fail("the host never saw the leaver go")
		return
	await step_ticks(CROSS_TICKS * 2)
	print("PROOF rematch after leaver: match_over=%s" % host.is_match_over())
	assert_false(host.is_match_over(), "every human still in the match has voted: the rematch starts")
	# And pressing again cannot rescue it.
	_rig.net_match(HOST).request_rematch()
	_rig.net_match(1).request_rematch()
	await step_ticks(CROSS_TICKS * 2)
	print("PROOF rematch after re-press: match_over=%s" % host.is_match_over())
	assert_false(host.is_match_over(), "and pressing Rematch again starts it")


## The leaver had voted: the names the others read lose it.
func test_a_leavers_vote_leaves_the_result_screen_with_them() -> void:
	if not await _start_round(2, 4, 1):
		return
	if not await _win_the_match():
		return
	var names: Array[PackedStringArray] = [PackedStringArray()]
	_rig.net_match(1).rematch_votes_changed.connect(func(said: PackedStringArray) -> void: names[0] = said)
	_rig.net_match(2).request_rematch()
	if not await _rig.wait_for(func() -> bool: return names[0].size() == 1):
		fail("client 1 never read client 2's vote")
		return
	_rig.sessions[2].leave()
	var cleared: bool = await _rig.wait_for(func() -> bool: return names[0].is_empty(), 2000)
	print("PROOF leaver's vote: names read on client 1 after the leaver went: %s" % str(names[0]))
	assert_true(cleared, "the vote of a player who left is no longer shown")
	assert_true(_rig.controller(HOST).is_match_over(), "and nobody left has asked, so nothing restarts")
