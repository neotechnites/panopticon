extends TestCase

## What the authority refuses from a client.
##
## Everything here is a thing a MODIFIED client can send, not a thing the game
## sends. The shipped client never sets a dev key on the wire, never floods, and
## never asks for a name mid-match; the point of these tests is that it makes no
## difference whether it does.

var _host: NetSession
var _client: NetSession
var _profile: MovementProfile


func before_each() -> void:
	_profile = TestFixtures.movement_profile()
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


## A host with one body in seat 0 owned by [param owner_peer_id], offline, which
## [method NetTransport.is_authority] counts as authoritative.
func _authority_link(owner_peer_id: int) -> PlayerNetLink:
	return NetFixtures.add_seat_body(_host, 0, owner_peer_id, _profile, false)


# --- Dev keys -----------------------------------------------------------------

func test_the_wire_never_carries_a_dev_key() -> void:
	var sent: MoveIntent = MoveIntent.new()
	sent.move_direction = Vector2(0.0, 1.0)
	sent.turbo_held = true
	sent.godmode = true

	# The struct decoded into is reused for the life of the session, so the test
	# is not only "does the format carry it" but "is it cleared off whatever was
	# there before" -- which is the way this leaks back in.
	var got: MoveIntent = MoveIntent.new()
	got.turbo_held = true
	got.godmode = true
	assert_eq_int(NetCodec.unpack_intent(NetCodec.pack_intent(9, sent), got), 9, "it decodes")
	assert_false(got.turbo_held, "turbo is not a thing a packet can ask for")
	assert_false(got.godmode, "and neither is invulnerability")
	assert_almost_eq(got.move_direction.y, 1.0, 0.001, "the rest of the intent is untouched")


func test_the_authority_refuses_a_power_a_client_picked_for_itself() -> void:
	# ability_slot is a dev test key: it picks a runner power DIRECTLY, skipping
	# the fallback to the match's own rules, so a client that sets it every tick
	# gets Armor Lock -- and rifle immunity with it -- in a match whose rules say
	# abilities are off.
	var owner: int = 77
	var link: PlayerNetLink = _authority_link(owner)
	await step_ticks(1)
	var asking: MoveIntent = MoveIntent.new()
	asking.ability_slot = 3

	link.accept_intent_payload(owner, NetCodec.pack_intent(1, asking))
	var source: RemoteIntentSource = link.get_remote_source()
	if not assert_not_null(source, "the link has a network-fed source"):
		return
	assert_eq_int(
		source.poll(SIM_DELTA).ability_slot, 0, "the host zeroes a power the client picked"
	)

	# And the harness, which drives abilities through exactly this field, can
	# still have it -- by the host's choice, on a flag, not by a client's.
	_host.get_settings().accept_remote_ability_slot = true
	link.accept_intent_payload(owner, NetCodec.pack_intent(2, asking))
	assert_eq_int(
		source.poll(SIM_DELTA).ability_slot, 3, "unless the host has opted in to it"
	)


# --- Edges --------------------------------------------------------------------

func test_a_jump_survives_a_dropped_snapshot() -> void:
	# A jump is an EDGE on an unreliable channel sampled at half the simulation
	# rate. As a flag it was lost whenever its snapshot was, and two hops inside
	# one interval arrived as one. It is a COUNT now, in bits the flag byte
	# already had spare, and a mirror fires once per increment.
	var link: PlayerNetLink = _authority_link(0)
	await step_ticks(1)
	var jumps: Array[int] = [0]
	link.controller.jumped.connect(func() -> void: jumps[0] += 1)

	var state: PlayerState = PlayerState.new()
	state.seat_index = 0
	state.tick = 10
	link.apply_state(state)
	assert_eq_int(jumps[0], 0, "the first snapshot sets the baseline and replays nothing")

	state.tick = 12
	state.jump_counter = 1
	link.apply_state(state)
	assert_eq_int(jumps[0], 1, "one jump, once")

	# Interpolation hands the same snapshot to the body every drawn frame.
	link.apply_state(state)
	assert_eq_int(jumps[0], 1, "and not once per frame it is drawn on")

	# The snapshots carrying counts 2 and 3 never arrive; the next one does.
	state.tick = 20
	state.jump_counter = 4
	link.apply_state(state)
	assert_eq_int(jumps[0], 4, "every jump in the gap is heard, not just the last")

	# And it wraps without replaying the whole modulus.
	state.tick = 22
	state.jump_counter = (4 + 2) % NetCodec.JUMP_COUNTER_MODULUS
	link.apply_state(state)
	assert_eq_int(jumps[0], 6, "the counter wraps and the count does not explode")


# --- Flooding -----------------------------------------------------------------

func test_the_authority_stops_reading_a_flood_of_intent() -> void:
	var owner: int = 77
	var link: PlayerNetLink = _authority_link(owner)
	await step_ticks(1)
	var budget: int = _host.get_settings().max_intent_packets_per_tick
	var accepted: Array[int] = []
	link.intent_received.connect(func(_peer: int, tick: int) -> void: accepted.append(tick))

	var intent: MoveIntent = MoveIntent.new()
	for i: int in budget * 4:
		link.accept_intent_payload(owner, NetCodec.pack_intent(100 + i, intent))
	assert_eq_int(
		accepted.size(), budget, "the host reads its budget of packets and drops the rest"
	)

	# And the budget comes back on the next tick, or a peer on a jittery line
	# would be throttled for being bursty rather than for flooding.
	await step_ticks(1)
	link.accept_intent_payload(owner, NetCodec.pack_intent(1000, intent))
	assert_eq_int(accepted.size(), budget + 1, "the allowance is per tick, not per session")


func test_a_lobby_request_flood_is_throttled() -> void:
	var lobby: NetLobby = NetFixtures.lobby_of(_host)
	var peer: int = 99
	# Every granted request answers with a reliable broadcast of the whole
	# roster to everybody, so an unthrottled client makes the host send N
	# packets per packet it sends.
	var granted: int = 0
	for _i: int in NetLobby.REQUEST_BURST * 3:
		if lobby._spend_request_token(peer):
			granted += 1
	assert_eq_int(
		granted, NetLobby.REQUEST_BURST, "a burst is free and everything past it is refused"
	)
	assert_false(lobby._spend_request_token(peer), "and it stays refused while the bucket is dry")


func test_a_name_is_only_accepted_while_the_lobby_is_gathering() -> void:
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
	if not await NetFixtures.poll_until(
		self,
		func() -> bool:
			var seat: LobbySeat = host_lobby.get_seat(seat_index)
			return seat != null and seat.display_name == "Guest"
	):
		fail("the host never granted the name in the lobby")
		return

	# Into the match, where a rename would republish the whole roster to
	# everybody in the middle of a round and be drawn nowhere it was not already.
	host_lobby.set_ready(seat_index, true)
	host_lobby.set_ready(0, true)
	assert_true(host_lobby.launch(), "the lobby launched")
	host_lobby.begin_match()
	assert_eq_int(
		int(host_lobby.get_phase()), int(NetLobby.Phase.IN_MATCH), "and the phase moved on"
	)

	client_lobby.set_display_name(seat_index, "Someone Else")
	# Long enough for a granted request to have come back, so this is a refusal
	# and not a race.
	await NetFixtures.poll_until(
		self,
		func() -> bool: return host_lobby.get_seat(seat_index).display_name != "Guest",
		200,
	)
	assert_eq_string(
		host_lobby.get_seat(seat_index).display_name,
		"Guest",
		"a rename mid-match is refused",
	)


func test_a_name_longer_than_the_host_will_look_at_is_cut_before_it_is_walked() -> void:
	# The sanitiser inspects every character of what it is handed. A peer may
	# not choose how many of them the host inspects.
	var lobby: NetLobby = NetFixtures.lobby_of(_host)
	lobby.open("Ryan")
	var huge: String = "A".repeat(NetLobby.MAX_RAW_NAME_LENGTH * 64)
	lobby.set_display_name(0, huge)
	var cleaned: String = lobby.get_seat(0).display_name
	assert_le(
		float(cleaned.to_utf8_buffer().size()),
		float(_host.get_settings().max_name_bytes),
		"whatever arrives, what is kept is a name",
	)


# --- Launch acknowledgement ---------------------------------------------------

## Simulated seconds the host waits for a launch acknowledgement in these tests.
const LAUNCH_TIMEOUT_SECONDS: float = 1.0


func test_a_slow_client_acknowledges_late_and_is_caught_up() -> void:
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	var client_lobby: NetLobby = NetFixtures.lobby_of(_client)
	if not await _launch_with_one_client(host_lobby, client_lobby):
		return
	var client_id: int = _client.get_local_peer_id()

	# The host binds and waits; the client is still loading.
	var host_match: NetMatch = _bind_match(_host)
	assert_false(host_match.has_started(), "the host waits for the client's acknowledgement")
	if not await NetFixtures.poll_until(self, func() -> bool: return host_match.has_started(), 3000):
		fail("the host never gave up waiting")
		return
	assert_false(host_lobby.has_launched(client_id), "the client has not acknowledged")
	assert_eq_int(
		int(host_lobby.get_phase()), int(NetLobby.Phase.LAUNCHING),
		"the lobby stays LAUNCHING while a client is still binding"
	)

	# Now the client's scene binds: it acknowledges, and is caught up.
	var client_match: NetMatch = _bind_match(_client)
	assert_true(client_match.is_active(), "a slow client binds in LAUNCHING")
	if not await NetFixtures.poll_until(
		self, func() -> bool: return host_lobby.has_launched(client_id) and client_match.has_started()
	):
		fail("the late acknowledgement never reached the host, or the catch-up never came back")
		return
	assert_eq_int(
		int(host_lobby.get_phase()), int(NetLobby.Phase.IN_MATCH),
		"every peer has launched, so the match begins"
	)
	assert_eq_string(
		client_match.controller.get_phase_name(), host_match.controller.get_phase_name(),
		"the client mirrors the phase the host is in"
	)


func test_a_client_that_never_acknowledges_is_dropped_by_policy() -> void:
	var host_lobby: NetLobby = NetFixtures.lobby_of(_host)
	var client_lobby: NetLobby = NetFixtures.lobby_of(_client)
	_host.get_settings().drop_unlaunched_peers = true
	if not await _launch_with_one_client(host_lobby, client_lobby):
		return
	var client_id: int = _client.get_local_peer_id()
	var seat_index: int = host_lobby.find_seat_by_peer(client_id).index

	var host_match: NetMatch = _bind_match(_host)
	var dropped: Callable = func() -> bool:
		var gone: bool = host_match.has_started() and not _host.has_peer(client_id)
		return gone and host_lobby.get_phase() == NetLobby.Phase.IN_MATCH
	if not await NetFixtures.poll_until(self, dropped, 3000):
		fail("the host never started, dropped the silent client and began the match")
		return
	var seat: LobbySeat = host_lobby.get_seat(seat_index)
	assert_true(seat != null and seat.is_bot(), "the dropped client's seat is a bot's")


## Host and client seated and readied, launched, and the client told so.
func _launch_with_one_client(host_lobby: NetLobby, client_lobby: NetLobby) -> bool:
	_host.get_settings().launch_timeout_seconds = LAUNCH_TIMEOUT_SECONDS
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		fail("the host could not take a port")
		return false
	host_lobby.open("Ryan")
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return false
	if not await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.get_local_seat_index() >= 0
	):
		fail("the client was never seated")
		return false
	host_lobby.set_ready(client_lobby.get_local_seat_index(), true)
	host_lobby.set_ready(0, true)
	if not host_lobby.launch():
		fail("the lobby did not launch")
		return false
	if not await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.get_phase() == NetLobby.Phase.LAUNCHING
	):
		fail("the client never learned of the launch")
		return false
	return true


## A match world and a NetMatch bound to [param session], under its branch.
func _bind_match(session: NetSession) -> NetMatch:
	var world: BotMatchWorld = BotMatchWorld.new()
	session.get_parent().add_child(world)
	world.build(TestFixtures.match_rules())
	var net_match: NetMatch = NetMatch.new()
	net_match.name = "NetMatch"
	net_match.controller = world.get_controller()
	net_match.runner_scene = load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene
	net_match.runner_container = world.get_runner_container()
	net_match.session_path = session.get_path()
	world.add_child(net_match)
	# Two arenas share one physics world here; off every layer so nothing collides.
	for participant: MatchParticipant in world.get_controller().get_participants():
		participant.home_collision_layer = 0
		if participant.body != null:
			participant.body.collision_layer = 0
	return net_match


# --- Robustness ---------------------------------------------------------------

func test_every_per_tick_message_fits_in_one_datagram() -> void:
	# A fragmented UDP datagram is lost whole when any one of its fragments is,
	# so the per-tick messages have to fit in the smallest path worth playing on.
	var snapshot: WorldSnapshot = WorldSnapshot.new()
	for seat: int in NetTransport.MAX_PLAYERS:
		var state: PlayerState = PlayerState.new()
		state.seat_index = seat
		state.position = Vector3(float(seat) * 7.0, 3.0, -float(seat))
		state.velocity = Vector3(1.0, -2.0, 3.0)
		snapshot.append(state)
	var packed: PackedByteArray = NetCodec.pack_snapshot(snapshot)
	assert_eq_int(
		packed.size(),
		NetCodec.SNAPSHOT_HEADER_SIZE + NetTransport.MAX_PLAYERS * NetCodec.SNAPSHOT_BODY_SIZE,
		"a full snapshot is the size the codec says it is",
	)
	assert_lt(
		float(packed.size()),
		float(ENetTransport.SAFE_PAYLOAD_BYTES),
		"and a full lobby's snapshot is nowhere near a datagram",
	)

	var intents: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_INTENT_REDUNDANCY:
		intents.append(MoveIntent.new())
	assert_lt(
		float(NetCodec.pack_intents(5, intents, NetCodec.MAX_INTENT_REDUNDANCY).size()),
		float(ENetTransport.SAFE_PAYLOAD_BYTES),
		"nor is the most redundant intent packet this build can send",
	)
	assert_lt(
		float(NetCodec.DECOY_MOVE_SIZE),
		float(ENetTransport.SAFE_PAYLOAD_BYTES),
		"nor a hologram's transform",
	)
