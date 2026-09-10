extends TestCase

## The session layer end to end: two real [NetSession] scenes, on two real UDP
## sockets, in this one headless process.
##
## [b]Nothing here is a mock.[/b] The host is the shipped
## [code]scenes/net/net_session.tscn[/code], so is the client, and the packets
## between them go through the loopback interface and the actual ENet stack.
## The trick that makes it fit in one process is one [MultiplayerAPI] per branch
## of the tree; [NetFixtures] explains it, and the fact that RPCs then resolve
## by node path relative to each branch is also the real constraint on the match
## layer -- bodies must be named after their seat on every machine.
##
## [b]Nothing here may hang.[/b] This project's schedule is unattended headless
## runs, and a test parked on a socket that will never answer wedges the whole
## suite until CI times out. Every wait is [method NetFixtures.poll_until],
## bounded by the wall clock, and a wait that runs out fails the test loudly
## instead of continuing into assertions that would then be meaningless.

## Ticks to let the authority produce and deliver a few snapshots. At 30 Hz on a
## 60 Hz simulation this is a dozen or so snapshots, which is plenty for a body
## to converge and short enough not to cost the suite anything.
const REPLICATION_TICKS: int = 40

## How close a client's body has to end up to the authority's.
##
## Not zero, and it should not be: a client draws bodies one snapshot interval
## in the past by design, so a falling body is legitimately a few centimetres
## behind. The number this bounds is the failure -- a body that never moved at
## all, sitting where the test parked it, tens of metres away.
const CONVERGENCE_METRES: float = 2.0

## Where a client's body is parked before any snapshot arrives. Far enough away
## that "it converged" cannot be confused with "it was already there".
const PARKED_POSITION: Vector3 = Vector3(0.0, 0.0, 250.0)

var _host: NetSession
var _client: NetSession
var _profile: MovementProfile


func before_each() -> void:
	_profile = TestFixtures.movement_profile()
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())


func after_each() -> void:
	# Sockets are not freed by the tree freeing their nodes quickly enough for
	# the next test's port probe, and a leaked listen socket is exactly the
	# flake that makes a networking suite untrustworthy.
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


## Bring both peers up and open the lobby. Returns false when the handshake did
## not complete, so every caller can fail loudly rather than assert into a
## session that does not exist.
func _connect() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	return await NetFixtures.join_and_wait(self, _client, _host, port)


# --- Transport ----------------------------------------------------------------

func test_a_host_and_a_client_find_each_other() -> void:
	if not await _connect():
		fail("the loopback handshake did not complete")
		return

	assert_true(_host.is_authority(), "the host simulates")
	assert_false(_client.is_authority(), "the client does not, and must never think it does")
	assert_eq_int(_host.get_peer_count(), 2, "the host sees both machines")
	assert_eq_int(_client.get_peer_count(), 2, "and so does the client")
	assert_true(
		_host.has_peer(NetTransport.AUTHORITY_PEER_ID), "the host is peer 1 in its own roster"
	)
	assert_true(
		_client.has_peer(NetTransport.AUTHORITY_PEER_ID), "and peer 1 in the client's roster too"
	)
	assert_gt(float(_client.get_local_peer_id()), 1.0, "the client got an id of its own")


func test_a_client_leaving_does_not_corrupt_the_host() -> void:
	if not await _connect():
		fail("the loopback handshake did not complete")
		return
	var client_id: int = _client.get_local_peer_id()

	_client.leave()
	var noticed: bool = await NetFixtures.poll_until(
		self, func() -> bool: return _host.get_peer_count() == 1
	)
	assert_true(noticed, "the host noticed the client go")
	assert_false(_host.has_peer(client_id), "and took it off the roster")
	assert_true(_host.is_authority(), "the host is still the host")
	assert_true(_host.is_established(), "and is still hosting, ready for someone else")


func test_a_join_that_nobody_answers_fails_instead_of_hanging() -> void:
	# The whole reason NetSettings.connect_timeout_seconds is measured on the
	# wall clock: the runner compresses simulated time fiftyfold and a socket
	# has not heard about it.
	_client.get_settings().connect_timeout_seconds = 0.2
	var dead_port: int = NetFixtures.reserve_port()
	assert_gt(float(dead_port), 0.0, "a port was found to not listen on")

	assert_true(_client.join("127.0.0.1", dead_port) == OK, "the attempt started")
	var gave_up: bool = await NetFixtures.poll_until(
		self,
		func() -> bool:
			return _client.get_connection_state() == NetTransport.ConnectionState.FAILED
	)
	assert_true(gave_up, "the client gave up rather than waiting forever")
	assert_false(
		_client.is_authority(),
		"a client that could not reach a host must not promote itself to one",
	)


# --- Lobby, with no wire at all -----------------------------------------------

func test_an_offline_lobby_seats_a_player_and_bots() -> void:
	# Offline is authoritative, so single player and the headless harness need
	# no special case anywhere. This is that claim, tested.
	var lobby: NetLobby = NetFixtures.lobby_of(_host)
	assert_true(lobby.open("Ryan"), "an offline lobby opens")
	assert_true(lobby.get_phase() == NetLobby.Phase.GATHERING, "and is gathering")
	assert_eq_int(lobby.get_local_seat_index(), 0, "the host takes seat 0")

	assert_eq_int(lobby.fill_with_bots(4), 3, "three bots make it a 1v3")
	assert_eq_int(lobby.get_occupant_count(), 4, "four in the lobby")
	var bot_seat: LobbySeat = lobby.get_seat(1)
	assert_not_null(bot_seat, "seat 1 exists")
	assert_true(bot_seat.is_bot(), "seat 1 holds a bot")
	assert_eq_int(bot_seat.peer_id, 0, "a bot has no peer, which is what makes the seat the identity")
	assert_true(bot_seat.is_ready, "a bot is ready by construction; nothing waits on one")


func test_a_lobby_will_not_launch_until_it_can() -> void:
	var lobby: NetLobby = NetFixtures.lobby_of(_host)
	lobby.open("Ryan")

	assert_false(lobby.can_launch(), "one player alone cannot start a match")
	assert_false(lobby.launch(), "and launching refuses")
	assert_true(
		lobby.describe_launch_block().contains("Add a bot"),
		"the refusal says what to do about it -- got \"%s\"" % lobby.describe_launch_block(),
	)

	lobby.add_bot()
	assert_false(lobby.can_launch(), "two in the lobby, but the human has not readied")
	lobby.set_ready(0, true)
	assert_true(lobby.can_launch(), "now it can")
	assert_eq_string(lobby.describe_launch_block(), "", "and has nothing to complain about")

	assert_true(lobby.launch(), "it launches")
	assert_true(lobby.get_phase() == NetLobby.Phase.LAUNCHING, "into LAUNCHING")
	assert_false(lobby.add_bot() >= 0, "the roster is frozen; no bot may join now")


func test_a_match_runs_the_whole_phase_loop() -> void:
	var lobby: NetLobby = NetFixtures.lobby_of(_host)
	lobby.open("Ryan")
	lobby.add_bot()
	lobby.set_ready(0, true)
	lobby.launch()

	assert_true(lobby.begin_match(), "the match begins")
	assert_true(lobby.get_phase() == NetLobby.Phase.IN_MATCH, "IN_MATCH")
	assert_false(lobby.begin_match(), "and cannot begin twice")

	assert_true(lobby.conclude_match(1), "it concludes")
	assert_true(lobby.get_phase() == NetLobby.Phase.POST_MATCH, "POST_MATCH")
	assert_eq_int(lobby.get_last_winning_seat(), 1, "the winning seat is remembered")

	assert_true(lobby.return_to_lobby(), "and it goes back to gathering")
	assert_true(lobby.get_phase() == NetLobby.Phase.GATHERING, "GATHERING")
	assert_eq_int(lobby.get_occupant_count(), 2, "keeping everyone who is still here")
	assert_false(
		lobby.get_seat(0).is_ready,
		"but not their readiness: readying for one match is not agreeing to the next",
	)
	assert_true(lobby.get_seat(1).is_ready, "a bot is still ready, because a bot always is")


func test_the_opening_guard_is_assignable_and_erasable() -> void:
	var lobby: NetLobby = NetFixtures.lobby_of(_host)
	lobby.open("Ryan")
	lobby.fill_with_bots(3)

	assert_true(lobby.assign_guard(2), "seat 2 takes the tower")
	assert_same(lobby.get_guard_seat(), lobby.get_seat(2), "and is the guard")
	assert_true(lobby.get_seat(0).role == LobbySeat.Role.PRISONER, "everyone else runs the ring")

	# The correct opening assignment under MatchRules.open_with_race is no
	# assignment at all: the race decides, and a lobby that named a guard
	# anyway would be quietly overruled.
	assert_true(lobby.clear_roles(), "roles can be taken away again")
	assert_null(lobby.get_guard_seat(), "nobody starts in the tower")


# --- Lobby, over the wire -----------------------------------------------------

func test_the_host_seats_a_joining_peer_and_tells_everyone() -> void:
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	var client_lobby: NetLobby = NetFixtures.lobby_of(_client)

	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	host_lobby.open("Ryan")
	host_lobby.add_bot("Warden")

	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return

	var seated: bool = await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.get_local_seat_index() >= 0
	)
	assert_true(seated, "the client learned which seat it is in")
	assert_eq_int(host_lobby.get_occupant_count(), 3, "the host has three occupants")
	assert_eq_int(client_lobby.get_occupant_count(), 3, "and so does the client's mirror")
	assert_eq_int(client_lobby.get_local_seat_index(), 2, "the client took the lowest empty seat")
	assert_eq_string(client_lobby.get_seat(0).display_name, "Ryan", "the host's name replicated")
	assert_true(client_lobby.get_seat(1).is_bot(), "and so did the bot, as a bot")


func test_a_client_can_only_ask_and_the_host_decides() -> void:
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	var client_lobby: NetLobby = NetFixtures.lobby_of(_client)

	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	host_lobby.open("Ryan")
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	if not await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.get_local_seat_index() >= 0
	):
		fail("the client was never seated")
		return

	var seat_index: int = client_lobby.get_local_seat_index()
	client_lobby.set_display_name(seat_index, "Guest")
	client_lobby.set_ready(seat_index, true)

	var granted: bool = await NetFixtures.poll_until(
		self,
		func() -> bool:
			var seat: LobbySeat = host_lobby.get_seat(seat_index)
			return seat != null and seat.is_ready and seat.display_name == "Guest"
	)
	assert_true(granted, "the host granted the request and it came back")
	assert_true(client_lobby.get_local_seat().is_ready, "the client's mirror agrees")

	# The rule that makes this a server-authoritative lobby rather than a
	# shared document: a client may not edit anybody, including itself,
	# directly, and may not touch somebody else's seat at all.
	assert_false(client_lobby.add_bot() >= 0, "a client cannot add a bot")
	assert_false(client_lobby.assign_guard(0), "a client cannot make itself the guard")
	assert_false(client_lobby.set_ready(0, false), "a client cannot un-ready the host")
	assert_true(host_lobby.get_seat(0).is_ready == false, "the host's own seat is untouched")


func test_a_peer_dropping_mid_match_leaves_its_seat_playable() -> void:
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	_host.get_settings().fill_vacated_seats_with_bots = true

	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	host_lobby.open("Ryan")
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	var client_id: int = _client.get_local_peer_id()
	if not await NetFixtures.poll_until(
		self, func() -> bool: return host_lobby.find_seat_by_peer(client_id) != null
	):
		fail("the client was never seated")
		return
	var seat_index: int = host_lobby.find_seat_by_peer(client_id).index

	host_lobby.set_ready(0, true)
	host_lobby.set_ready(seat_index, true)
	assert_true(host_lobby.launch(), "the match launches")
	assert_true(host_lobby.begin_match(), "and begins")

	_client.leave()
	var handled: bool = await NetFixtures.poll_until(
		self,
		func() -> bool:
			var seat: LobbySeat = host_lobby.get_seat(seat_index)
			return seat != null and seat.is_bot()
	)
	# The body is mid-round with other bodies racing it; deleting it would
	# leave a guard alone in a tower with a round that cannot end. Whether this
	# is the right answer is a question for Ryan -- see
	# NetSettings.fill_vacated_seats_with_bots.
	assert_true(handled, "the seat became a bot's rather than vanishing")
	assert_eq_int(host_lobby.get_seat(seat_index).peer_id, 0, "and no packet can drive it now")
	assert_eq_int(host_lobby.get_occupant_count(), 2, "the match still has two players in it")
	assert_true(host_lobby.get_phase() == NetLobby.Phase.IN_MATCH, "and is still running")


# --- Replication --------------------------------------------------------------

func test_a_client_body_is_moved_by_the_authority_and_not_by_itself() -> void:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return

	var host_link: PlayerNetLink = NetFixtures.add_seat_body(_host, 0, 0, _profile, true)
	var client_link: PlayerNetLink = NetFixtures.add_seat_body(_client, 0, 0, _profile, false)
	# Parked a long way from where the authority's body is, so converging
	# cannot be confused with never having moved.
	client_link.controller.global_position = PARKED_POSITION
	await step_ticks(1)

	assert_false(
		client_link.controller.is_physics_processing(),
		"a client simulates nothing; leaving its physics on would fight every snapshot",
	)
	assert_true(host_link.controller.is_physics_processing(), "the authority does simulate")

	await step_ticks(REPLICATION_TICKS)
	var separation: float = client_link.controller.global_position.distance_to(
		host_link.controller.global_position
	)
	assert_lt(
		separation,
		CONVERGENCE_METRES,
		"the client's body followed the authority's (it is %.1f m away, parked at %.0f m)"
			% [separation, PARKED_POSITION.length()],
	)


func test_a_clients_intent_drives_its_body_through_the_same_seam_a_bot_uses() -> void:
	# The point of the whole intent seam: a remote player's body on the
	# authority runs the identical PlayerController physics off the identical
	# MoveIntent struct, filled from a socket instead of from a keyboard.
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	var client_id: int = _client.get_local_peer_id()

	var host_link: PlayerNetLink = NetFixtures.add_seat_body(_host, 0, client_id, _profile, false)
	var client_link: PlayerNetLink = NetFixtures.add_seat_body(_client, 0, client_id, _profile, true)
	await step_ticks(1)

	assert_not_null(host_link.get_remote_source(), "the authority has a network-fed source ready")
	assert_same(
		host_link.controller.intent_source,
		host_link.get_remote_source(),
		"and has switched the body onto it",
	)

	var bot_source: BotIntentSource = client_link.local_source as BotIntentSource
	assert_not_null(bot_source, "the client's own body is driven by a local source")
	if bot_source == null:
		return
	bot_source.command.move_direction = Vector2(0.0, 1.0)
	bot_source.command.sprint_held = true

	var arrived: bool = await NetFixtures.poll_until(
		self,
		func() -> bool:
			var source: RemoteIntentSource = host_link.get_remote_source()
			return source != null and source.last_tick >= 0 and source.command.sprint_held
	)
	assert_true(arrived, "the client's intent reached the authority")
	assert_almost_eq(
		host_link.get_remote_source().command.move_direction.y,
		1.0,
		0.01,
		"and arrived intact",
	)
	assert_false(host_link.get_remote_source().is_stale(), "the source is being fed, not timing out")


func test_the_authority_refuses_intent_for_a_seat_a_peer_does_not_own() -> void:
	# The one check that stops a peer driving somebody else's body. Seat 0 is
	# owned by the host, and the client sends intent for it anyway.
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return

	var host_link: PlayerNetLink = NetFixtures.add_seat_body(
		_host, 0, NetTransport.AUTHORITY_PEER_ID, _profile, true
	)
	var client_link: PlayerNetLink = NetFixtures.add_seat_body(
		_client, 0, NetTransport.AUTHORITY_PEER_ID, _profile, true
	)
	await step_ticks(1)

	var forger: BotIntentSource = client_link.local_source as BotIntentSource
	assert_not_null(forger, "the client has something to forge with")
	if forger == null:
		return
	forger.command.move_direction = Vector2(1.0, 0.0)

	await step_ticks(REPLICATION_TICKS)
	var source: RemoteIntentSource = host_link.get_remote_source()
	assert_not_null(source, "the authority has a network-fed source")
	assert_eq_int(
		source.last_tick, -1, "and never accepted a packet for a seat the sender does not own"
	)
