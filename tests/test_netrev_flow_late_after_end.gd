extends TestCase
## Review proof (match flow): a peer whose scene binds after the match has already been won
## (launch timeout passed, a one-round match over) is never caught up, and blocks the rematch.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _late_start(win_first: bool) -> bool:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 1
	var late: Array[int] = [2]
	if not await _rig.launch(4, 0, late):
		fail("launch")
		return false
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return false
	if win_first:
		TestFixtures.pin_the_field(host, null)
		for participant: MatchParticipant in host.get_participants():
			if participant.is_running:
				host.convert_participant(participant)
		assert_true(host.is_match_over(), "the host's guard wins the one-round match")
		await step_ticks(30)
	return true


func test_control_a_peer_that_binds_late_mid_match_is_caught_up() -> void:
	if not await _late_start(false):
		return
	assert_true(await _rig.bind_late(2), "a late peer is caught up while the match runs")


func test_a_peer_that_binds_after_the_match_ended_is_caught_up_and_can_rematch() -> void:
	if not await _late_start(true):
		return
	var host: MatchController = _rig.controller(HOST)
	var lobby: NetLobby = _rig.sessions[HOST].lobby
	var bound: bool = await _rig.bind_late(2)
	var epoch: int = lobby.get_epoch()
	print("PROOF late after end: host lobby phase=%d (POST_MATCH=%d) late peer started=%s late phase=%s standing=%s" % [
		int(lobby.get_phase()), int(NetLobby.Phase.POST_MATCH), str(bound),
		_rig.controller(2).get_phase_name(), str(lobby.is_standing_in(_rig.sessions[2].get_local_peer_id(), epoch))])
	assert_true(bound, "the late peer learns the match (and that it is over)")
	assert_true(host.is_match_over(), "which is over")
	# Everybody presses Rematch.
	for peer: int in _rig.peer_count():
		_rig.sessions[peer].flow.rematch()
	var restarted: bool = await _rig.wait_rematch(epoch)
	print("PROOF late after end: all three pressed Rematch -> relaunched=%s" % str(restarted))
	assert_true(restarted, "and three presses relaunch the match")
	await step_ticks(30)
	for peer: int in _rig.peer_count():
		assert_false(_rig.controller(peer).is_match_over(), "peer %d plays the new match" % peer)


## A peer still loading cannot press anything: the humans whose scene stands decide the rematch,
## and the one that binds after it is brought into the new match.
func test_a_peer_still_loading_does_not_block_the_rematch_and_joins_it() -> void:
	if not await _late_start(true):
		return
	var epoch: int = _rig.sessions[HOST].lobby.get_epoch()
	_rig.sessions[HOST].flow.rematch()
	_rig.sessions[1].flow.rematch()
	var restarted: bool = await _rig.wait_rematch(epoch)
	assert_true(restarted, "the two whose scene stands relaunch the match")
	assert_true(await _rig.bind_late(2), "the late peer binds into the rematch")
	var host: MatchController = _rig.controller(HOST)
	var late: MatchController = _rig.controller(2)
	var caught_up: bool = await _rig.wait_for(func() -> bool:
		return late.get_phase() == host.get_phase() and late.get_round_number() == host.get_round_number())
	print("PROOF late into rematch: host %s r%d, late %s r%d" % [
		host.get_phase_name(), host.get_round_number(), late.get_phase_name(), late.get_round_number()])
	assert_true(caught_up, "and stands in the phase and round the host is in")
