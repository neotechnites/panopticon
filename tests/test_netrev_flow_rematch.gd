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


func _epoch() -> int:
	return _rig.sessions[HOST].lobby.get_epoch()


## What a machine's result screen says about who has pressed Rematch, or empty when it says nothing.
func _marks(peer: int) -> String:
	var label: Label = _rig.matches[peer].get_node("ResultScreen").get_node("%RematchVotes") as Label
	return label.text if label.visible else ""


## CONTROL: all three humans press Rematch -> the match relaunches. Shows the test has teeth.
func test_control_every_human_votes_and_the_rematch_starts() -> void:
	if not await _start_round(2, 4, 1):
		return
	if not await _win_the_match():
		return
	var epoch: int = _epoch()
	for peer: int in _rig.peer_count():
		_rig.sessions[peer].flow.rematch()
	assert_true(await _rig.wait_rematch(epoch), "with every human's mark up, the host relaunches the match")
	await step_ticks(CROSS_TICKS)
	for peer: int in _rig.peer_count():
		assert_false(_rig.controller(peer).is_match_over(), "peer %d plays the new match" % peer)


## Host and client 1 press Rematch; client 2 quits instead. Every human still here has pressed.
func test_a_rematch_starts_when_the_one_who_had_not_voted_leaves() -> void:
	if not await _start_round(2, 4, 1):
		return
	if not await _win_the_match():
		return
	var epoch: int = _epoch()
	_rig.sessions[HOST].flow.rematch()
	_rig.sessions[1].flow.rematch()
	await step_ticks(CROSS_TICKS)
	assert_eq_int(_epoch(), epoch, "two of three marks do not relaunch it yet")
	assert_true(_rig.controller(HOST).is_match_over(), "and the result stays up")
	_rig.sessions[2].leave()
	var relaunched: bool = await _rig.wait_rematch(epoch)
	print("PROOF rematch after leaver: relaunched=%s" % relaunched)
	assert_true(relaunched, "every human still in the match has pressed: the rematch starts")
	var now: int = _epoch()
	_rig.sessions[HOST].flow.rematch()
	await step_ticks(CROSS_TICKS)
	assert_eq_int(_epoch(), now, "and Rematch means nothing in a match that is running")


## The leaver had pressed: the marks the others read lose it with the seat.
func test_a_leavers_vote_leaves_the_result_screen_with_them() -> void:
	if not await _start_round(2, 4, 1):
		return
	if not await _win_the_match():
		return
	var epoch: int = _epoch()
	_rig.sessions[2].flow.rematch()
	if not await _rig.wait_for(func() -> bool: return not _marks(1).is_empty()):
		fail("client 1 never read client 2's mark")
		return
	_rig.sessions[2].leave()
	var cleared: bool = await _rig.wait_for(func() -> bool: return _marks(1).is_empty(), 2000)
	print("PROOF leaver's mark: read on client 1 after the leaver went: '%s'" % _marks(1))
	assert_true(cleared, "the mark of a player who left is no longer shown")
	assert_eq_int(_epoch(), epoch, "and nobody left has pressed, so nothing relaunches")
