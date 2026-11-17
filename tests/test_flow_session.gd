extends TestCase
## Joining and losing a session: who is seated under what name, who is turned away and told why,
## and how long a silent peer is waited for.

const WAIT_MS: int = 3000
const SILENCE_SECONDS: float = 0.6

var _sessions: Array[NetSession] = []
var _port: int = -1


func after_each() -> void:
	for i: int in range(_sessions.size() - 1, -1, -1):
		_sessions[i].leave()
	_sessions.clear()


func _peer(branch: String, net_settings: NetSettings = null) -> NetSession:
	var session: NetSession = NetFixtures.make_peer(
		self, branch, net_settings if net_settings != null else NetFixtures.settings()
	)
	_sessions.append(session)
	return session


## A host with an open lobby, or null after failing loudly.
func _host(net_settings: NetSettings = null) -> NetSession:
	var host: NetSession = _peer("Host", net_settings)
	_port = await NetFixtures.host_and_wait(self, host)
	if _port < 0:
		fail("the host could not take a port")
		return null
	host.lobby.open("Host")
	return host


func _until(predicate: Callable) -> bool:
	return await NetFixtures.poll_until(self, predicate, WAIT_MS)


func test_a_joiner_is_seated_under_the_name_it_asked_for() -> void:
	var host: NetSession = await _host()
	if host == null:
		return
	var client: NetSession = _peer("Client")
	client.lobby.local_name = "Ada"
	assert_eq_int(client.join("127.0.0.1", _port), OK, "the client dials")
	assert_true(await _until(func() -> bool: return client.lobby.get_local_seat() != null), "the client is seated")
	var seat: LobbySeat = host.lobby.find_seat_by_peer(client.get_local_peer_id())
	assert_not_null(seat, "the host holds a seat for it")
	if seat == null:
		return
	assert_eq_string(seat.display_name, "Ada", "under its name, on the host")
	assert_eq_string(client.lobby.get_local_seat().display_name, "Ada", "and on the client")


func test_a_joiner_during_a_match_is_told_why_and_let_go() -> void:
	var host: NetSession = await _host()
	if host == null:
		return
	host.lobby.fill_with_bots(2)
	host.lobby.set_ready(0, true)
	assert_true(host.lobby.launch(), "the host launches with a bot")
	var client: NetSession = _peer("Late")
	var told: Array[int] = []
	client.lobby.refused.connect(func(reason: NetLobby.Refusal) -> void: told.append(int(reason)))
	assert_eq_int(client.join("127.0.0.1", _port), OK, "the late client dials")
	assert_true(await _until(func() -> bool: return not told.is_empty()), "the late client hears from the host")
	if told.is_empty():
		return
	assert_eq_int(told[0], int(NetLobby.Refusal.IN_MATCH), "and is told a match is running")
	assert_true(
		await _until(func() -> bool:
			return client.get_connection_state() == NetTransport.ConnectionState.OFFLINE),
		"it leaves the session by itself",
	)
	assert_true(await _until(func() -> bool: return host.get_peer_count() == 1), "and the host is rid of it")
	assert_eq_int(host.lobby.get_occupant_count(), 2, "the match's seats are untouched")


func test_a_joiner_to_a_lobby_full_of_people_is_told_it_is_full() -> void:
	var small: NetSettings = NetFixtures.settings()
	small.max_players = 2
	var host: NetSession = await _host(small)
	if host == null:
		return
	var first: NetSession = _peer("First")
	first.join("127.0.0.1", _port)
	assert_true(await _until(func() -> bool: return first.lobby.get_local_seat() != null), "the first joiner is seated")
	var second: NetSession = _peer("Second")
	var told: Array[int] = []
	second.lobby.refused.connect(func(reason: NetLobby.Refusal) -> void: told.append(int(reason)))
	second.join("127.0.0.1", _port)
	assert_true(await _until(func() -> bool: return not told.is_empty()), "the second hears from the host")
	if not told.is_empty():
		assert_eq_int(told[0], int(NetLobby.Refusal.FULL), "and is told the lobby is full")


func test_a_joiner_on_another_build_is_told_so() -> void:
	var host: NetSession = await _host()
	if host == null:
		return
	var client: NetSession = _peer("Other")
	client.lobby.build_fingerprint += 1
	var told: Array[int] = []
	client.lobby.refused.connect(func(reason: NetLobby.Refusal) -> void: told.append(int(reason)))
	client.join("127.0.0.1", _port)
	assert_true(await _until(func() -> bool: return not told.is_empty()), "the other build hears from the host")
	if not told.is_empty():
		assert_eq_int(told[0], int(NetLobby.Refusal.VERSION), "and is told the builds differ")
	assert_null(host.lobby.find_seat_by_peer(client.get_local_peer_id()), "it was never seated")


## A silent peer is one whose game has stopped while its socket still answers; ENet alone never drops it.
func _silent_pair() -> Array[NetSession]:
	var quick: NetSettings = NetFixtures.settings()
	quick.peer_timeout_seconds = SILENCE_SECONDS
	var host: NetSession = await _host(quick)
	if host == null:
		return []
	var client: NetSession = _peer("Client", quick.duplicate() as NetSettings)
	if not await NetFixtures.join_and_wait(self, client, host, _port):
		fail("the client never connected")
		return []
	return [host, client]


func test_a_client_gone_silent_is_dropped_at_the_timeout() -> void:
	var pair: Array[NetSession] = await _silent_pair()
	if pair.is_empty():
		return
	var host: NetSession = pair[0]
	var client: NetSession = pair[1]
	await step_seconds_real(SILENCE_SECONDS * 2.0)
	assert_eq_int(host.get_peer_count(), 2, "a client that keeps talking is kept")
	client.set_process(false)
	var began: int = Time.get_ticks_msec()
	assert_true(await _until(func() -> bool: return host.get_peer_count() == 1), "the host drops the silent client")
	assert_lt(float(Time.get_ticks_msec() - began) / 1000.0, SILENCE_SECONDS + 0.5, "at the timeout, not long after")
	assert_true(
		await _until(func() -> bool: return not client.is_established()), "and the client is told at once"
	)


func test_a_host_gone_silent_is_given_up_at_the_timeout() -> void:
	var pair: Array[NetSession] = await _silent_pair()
	if pair.is_empty():
		return
	var host: NetSession = pair[0]
	var client: NetSession = pair[1]
	host.set_process(false)
	var began: int = Time.get_ticks_msec()
	assert_true(
		await _until(func() -> bool: return client.get_connection_state() == NetTransport.ConnectionState.FAILED),
		"the client gives the silent host up",
	)
	assert_lt(float(Time.get_ticks_msec() - began) / 1000.0, SILENCE_SECONDS + 0.5, "at the timeout, not long after")


func step_seconds_real(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
