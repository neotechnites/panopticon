extends TestCase
## Review suspect, proven: the scene acknowledgement shared the lobby's request allowance, so a
## client that had just spent it (mashing Ready as the host launched) never stood in its match.

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


func test_a_client_that_spent_its_lobby_requests_still_stands() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return
	var host: NetLobby = _rig.sessions[HOST].lobby
	var client: NetLobby = _rig.sessions[CLIENT].lobby
	host.fill_with_bots(3)
	host.assign_guard(0)
	for seat: LobbySeat in host.get_occupied_seats():
		host.set_ready(seat.index, true)
	assert_true(host.launch(), "the host launches")
	if not await _rig.wait_for(func() -> bool: return client.get_phase() == NetLobby.Phase.IN_MATCH):
		fail("the client never heard the launch")
		return
	# A scene that loads inside the allowance's refill, after a second of mashing Ready.
	for _i: int in 12:
		client.rpc_id(1, &"_request_ready", true)
	client.acknowledge_scene(client.get_epoch())
	var peer: int = _rig.sessions[CLIENT].get_local_peer_id()
	var stood: bool = await _rig.wait_for(func() -> bool: return host.peer_state(peer) == NetLobby.PeerState.STANDING, 1500)
	print("PROOF launch-ack: after 12 ready requests the client's acknowledgement was heard=%s" % str(stood))
	assert_true(stood, "the host heard the client's scene stands")
