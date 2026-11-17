extends TestCase

## A machine loading a scene may be silent for as long as a load takes; one standing in its scene only for
## the line timeout. The lifecycle the lobby holds picks the limit: seated into the hub, and every launch, is
## LOADING until the scene is acknowledged.

const TIMEOUT_SECONDS: float = 0.6
const LOAD_STALL_SECONDS: float = 3.0
## Silent for longer than a standing peer may be, shorter than a load.
const QUIET_SECONDS: float = 1.2

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
	settings.peer_timeout_seconds = TIMEOUT_SECONDS
	settings.load_stall_seconds = LOAD_STALL_SECONDS
	return settings


func _quiet(seconds: float) -> void:
	_client.set_process(false)
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_client.set_process(true)


func _stand() -> bool:
	var client_id: int = _client.get_local_peer_id()
	_client.lobby.acknowledge_scene(_client.lobby.get_epoch())
	return await NetFixtures.poll_until(
		self, func() -> bool: return _host.lobby.peer_state(client_id) == NetLobby.PeerState.STANDING
	)


func test_a_joiner_and_a_launch_are_allowed_a_load_and_a_standing_peer_only_the_timeout() -> void:
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
	if not await NetFixtures.poll_until(self, func() -> bool: return client_lobby.get_local_seat_index() >= 0):
		fail("the client was never seated")
		return
	var client_id: int = _client.get_local_peer_id()
	assert_true(host_lobby.peer_state(client_id) == NetLobby.PeerState.LOADING, "a seated joiner loads its hub")
	await _quiet(QUIET_SECONDS)
	assert_true(_host.has_peer(client_id), "and is allowed a load's silence")
	if not await _stand():
		fail("the client's hub never stood")
		return

	host_lobby.set_ready(client_lobby.get_local_seat_index(), true)
	host_lobby.set_ready(0, true)
	assert_true(host_lobby.launch(), "the lobby launches")
	assert_true(host_lobby.peer_state(client_id) == NetLobby.PeerState.LOADING, "a launch puts the client to loading")
	await _quiet(QUIET_SECONDS)
	assert_true(_host.has_peer(client_id), "and it is allowed the map load's silence")
	if not await _stand():
		fail("the client's match never stood")
		return

	_client.set_process(false)
	var began: int = Time.get_ticks_msec()
	var dropped: bool = await NetFixtures.poll_until(self, func() -> bool: return not _host.has_peer(client_id), 3000)
	assert_true(dropped, "a standing client gone silent is dropped")
	assert_lt(float(Time.get_ticks_msec() - began) / 1000.0, TIMEOUT_SECONDS + 0.5, "at the line timeout, not a load's")


## CONNECTED is the time to ask: a peer that has asked of a lobby nobody opened yet waits on the host,
## kept past the grace while its line lives, and seated when the lobby opens.
func test_a_peer_that_asked_before_the_lobby_opened_is_kept_and_seated_when_it_opens() -> void:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	var client_id: int = _client.get_local_peer_id()
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	if not await NetFixtures.poll_until(self, func() -> bool: return host_lobby.has_asked(client_id)):
		fail("the client never asked to join")
		return
	var until: int = Time.get_ticks_msec() + int(NetSession.REFUSAL_GRACE_SECONDS * 1000.0) + 1000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert_true(_host.has_peer(client_id), "a peer that asked is not dropped at the grace")
	host_lobby.open("Host")
	assert_not_null(host_lobby.find_seat_by_peer(client_id), "and is seated when the lobby opens")
