extends TestCase
## A player's held power is theirs for the session: through hub, match and back to the hub, on every
## machine; bots hold one of their own.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const NONE: int = MatchRules.RunnerAbility.NONE

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## Every participant on every bound peer holds what its seat holds, and the seats hold [param want].
func _bodies_hold(want: Dictionary) -> bool:
	for peer: int in _rig.peer_count():
		for participant: MatchParticipant in _rig.controller(peer).get_participants():
			var held: int = int(RunnerPower.of(participant.body).get_held())
			if held != _rig.sessions[HOST].lobby.get_seat(participant.seat).power:
				return false
			if want.has(participant.seat) and held != int(want[participant.seat]):
				return false
	return true


func test_a_held_power_goes_from_the_hub_into_the_match_and_back() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("the loopback handshake did not complete")
		return
	var lobby: NetLobby = _rig.sessions[HOST].lobby
	var client_seat: int = _rig.sessions[CLIENT].lobby.get_local_seat_index()
	lobby.set_power(0, CAMO)
	lobby.set_power(client_seat, SHIELD)
	var want: Dictionary = {0: CAMO, client_seat: SHIELD}
	if not await _rig.launch(4, 0):
		fail("the match never started on every peer")
		return
	var bots_picked: Callable = func() -> bool:
		for seat: LobbySeat in lobby.get_occupied_seats():
			if seat.is_bot() and seat.power == NONE:
				return false
		return true
	assert_true(await _rig.wait_for(func() -> bool: return bots_picked.call() and _bodies_hold(want)),
			"every bot seat picked a power, and every machine's bodies hold their seat's")
	# A death and a round restart re-arm the body; the pick stays.
	var host: MatchController = _rig.controller(HOST)
	for participant: MatchParticipant in host.get_participants():
		RunnerPower.of(participant.body).arm(host.get_rules(), host)
	assert_true(_bodies_hold(want), "a re-armed body keeps its player's power")
	assert_true(lobby.conclude_match(-1), "the host ends the match")
	assert_true(lobby.return_to_lobby(), "and calls everyone back")
	for peer: int in _rig.peer_count():
		var session: NetSession = _rig.sessions[peer]
		if not await _rig.wait_for(func() -> bool: return session.lobby.get_phase() == NetLobby.Phase.GATHERING):
			fail("peer %d never heard of the return" % peer)
			return
		_rig.matches[peer].get_parent().queue_free()
	await step_ticks(2)
	_rig.bind_hubs()
	var stood: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if _rig.controller(peer).get_participants().size() != 2:
				return false
		return _bodies_hold(want))
	assert_true(stood, "back in the hub every machine has the host on camo and the client on the shield")
