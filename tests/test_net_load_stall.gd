extends TestCase

## A machine loading a scene is silent for as long as the load takes. Both ends allow that silence for a
## while after a join and after every scene change, then go back to the mid-match ceiling.

const LOAD_STALL_SECONDS: float = 0.4

var _host: NetSession
var _client: NetSession


func before_each() -> void:
	_host = NetFixtures.make_peer(self, "Host", _settings())
	_client = NetFixtures.make_peer(self, "Client", _settings())


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


func _settings() -> NetSettings:
	var settings: NetSettings = NetFixtures.settings()
	settings.load_stall_seconds = LOAD_STALL_SECONDS
	return settings


func _ceiling(session: NetSession) -> float:
	return session.transport.get_silence_ceiling_seconds()


func _settled() -> bool:
	var mid_match: float = _host.get_settings().peer_timeout_seconds
	return is_equal_approx(_ceiling(_host), mid_match) and is_equal_approx(_ceiling(_client), mid_match)


func test_a_join_and_a_scene_change_are_allowed_a_load_stall_on_both_ends() -> void:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	var client_lobby: NetLobby = NetFixtures.lobby_of(_client)
	host_lobby.open("Host")
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	assert_almost_eq(_ceiling(_host), LOAD_STALL_SECONDS, 0.001, "the host allows a joiner its hub load")
	assert_almost_eq(_ceiling(_client), LOAD_STALL_SECONDS, 0.001, "the joiner allows the host the same")
	if not await NetFixtures.poll_until(self, _settled, 3000):
		fail("the mid-match ceiling never came back after the join")
		return

	if not await NetFixtures.poll_until(self, func() -> bool: return client_lobby.get_local_seat_index() >= 0):
		fail("the client was never seated")
		return
	host_lobby.set_ready(client_lobby.get_local_seat_index(), true)
	host_lobby.set_ready(0, true)
	assert_true(host_lobby.launch(), "the lobby launches")
	if not await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.get_phase() == NetLobby.Phase.LAUNCHING
	):
		fail("the client never learned of the launch")
		return
	assert_almost_eq(_ceiling(_host), LOAD_STALL_SECONDS, 0.001, "the host allows the map load")
	assert_almost_eq(_ceiling(_client), LOAD_STALL_SECONDS, 0.001, "and so does the client")
	if not await NetFixtures.poll_until(self, _settled, 3000):
		fail("the mid-match ceiling never came back after the launch")
