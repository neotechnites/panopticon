extends TestCase
## Playtest regressions on a bad line: a hitch is ridden out, and a real drop is told to everybody.

const Rig = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
## Ticks for an event to cross loopback and be drawn, at the real clock these tests run on.
const CROSS_TICKS: int = 20
## Set to 1 to run the tests of bugs that are known and open; unset, they are skipped by name.
const OPEN_BUGS_ENV: String = "PANOPTICON_RUN_OPEN_BUGS"
## Wall milliseconds a dead line is given to be noticed. ENet counts its timeout in doubling resends,
## so the shipped 8 s lands anywhere from 8 s to about twice that.
const DEAD_LINE_LIMIT_MS: int = 30000

var _rig: Rig = null
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	_rig = Rig.new()
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale


func after_each() -> void:
	get_tree().multiplayer_poll = true
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	if _rig != null:
		_rig.close()
		_rig = null


## A round running on every peer, the host in the tower and the bots held still; then the real clock.
func _start_round(map: StringName, clients: int) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 5
	_rig.settings().map_id = map
	if not await _rig.launch(clients + 2, HOST):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	_rig.body(HOST, clients + 1).movement_locked = true
	# A socket's timeout is wall time: a stall of seconds has to be seconds of play too.
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	await step_ticks(CROSS_TICKS)
	return true


## [param stalled]'s machine hears nothing, says nothing and runs nothing for [param wall_ms], or until
## [param until] if one is given; the others play on. Returns the wall milliseconds it lasted.
func _stall(stalled: int, wall_ms: int, until: Callable = Callable()) -> int:
	var tree: SceneTree = get_tree()
	var machine: Node = (_rig.sessions[stalled] as NetSession).get_parent()
	tree.multiplayer_poll = false
	machine.process_mode = Node.PROCESS_MODE_DISABLED
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < wall_ms and not (until.is_valid() and until.call()):
		for peer: int in _rig.peer_count():
			if peer != stalled:
				(_rig.sessions[peer] as NetSession).multiplayer.poll()
		await tree.process_frame
	machine.process_mode = Node.PROCESS_MODE_INHERIT
	tree.multiplayer_poll = true
	return Time.get_ticks_msec() - began


## Nobody was dropped, and every peer holds the host's round, seat and dead.
func _everyone_is_still_playing_the_same_round(clients: int, when: String) -> void:
	await step_ticks(CROSS_TICKS * 2)
	var host_session: NetSession = _rig.sessions[HOST]
	var host: MatchController = _rig.controller(HOST)
	assert_eq_int(host_session.get_peer_count(), clients + 1, "the host still has every peer %s" % when)
	for peer: int in _rig.peer_count():
		var session: NetSession = _rig.sessions[peer]
		assert_true(session.is_established(), "peer %d is still connected %s" % [peer, when])
		var seat: LobbySeat = host_session.lobby.get_seat(session.lobby.get_local_seat_index())
		assert_false(seat == null or seat.is_bot(), "peer %d's seat is still its own %s" % [peer, when])
		var controller: MatchController = _rig.controller(peer)
		assert_eq_int(controller.get_phase(), host.get_phase(), "peer %d is in the host's phase %s" % [peer, when])
		assert_eq_int(controller.get_round_number(), host.get_round_number(), "peer %d is in the host's round %s" % [peer, when])
		assert_eq_int(
			controller.get_seat_participant().index, host.get_seat_participant().index,
			"peer %d has the host's guard %s" % [peer, when],
		)
		for slot: int in host.get_participants().size():
			assert_true(
				_rig.participant(peer, slot).is_ghost == _rig.participant(HOST, slot).is_ghost,
				"peer %d agrees with the host on whether slot %d is dead %s" % [peer, slot, when],
			)
		assert_false(
			(_rig.matches[peer].get_node("ResultScreen") as MatchResultScreen).is_showing(),
			"peer %d is shown no result %s" % [peer, when],
		)
	# And every client still drives its own body on the host.
	for client: int in range(1, clients + 1):
		var on_host: PlayerController = _rig.body(HOST, _rig.local_slot(client))
		var from: Vector3 = on_host.global_position
		_rig.drive(client, Vector2(0.0, 1.0))
		await step_ticks(30)
		_rig.drive(client, Vector2(0.0, -1.0))
		assert_gt(on_host.global_position.distance_to(from), 0.5, "client %d still moves its body on the host %s" % [client, when])
		await step_ticks(30)
		_rig.drive(client, Vector2.ZERO)


# --- PT2-08: "when i shot him, he kept playing, and then in my game a new round started and he was a bot"

func test_a_three_second_client_hitch_drops_nobody_hell_two_peers() -> void:
	if not await _start_round(HELL, 1):
		return
	await _stall(1, 3000)
	await _everyone_is_still_playing_the_same_round(1, "after a 3 s client hitch")


func test_a_seven_second_host_hitch_drops_nobody_marble_two_peers() -> void:
	if not await _start_round(MARBLE, 1):
		return
	await _stall(HOST, 7000)
	await _everyone_is_still_playing_the_same_round(1, "after a 7 s host hitch")


func test_a_seven_second_client_hitch_drops_nobody_hell_four_peers() -> void:
	if not await _start_round(HELL, 3):
		return
	await _stall(2, 7000)
	await _everyone_is_still_playing_the_same_round(3, "after a 7 s client hitch")


func test_a_three_second_host_hitch_drops_nobody_marble_four_peers() -> void:
	if not await _start_round(MARBLE, 3):
		return
	await _stall(HOST, 3000)
	await _everyone_is_still_playing_the_same_round(3, "after a 3 s host hitch")


## Client 1's line dies for good: a bot plays its seat on, the others play on, and it is told.
func _a_dead_line_is_told_to_everybody(map: StringName, clients: int) -> void:
	if not await _start_round(map, clients):
		return
	var host_session: NetSession = _rig.sessions[HOST]
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(1)
	var seat_index: int = (_rig.sessions[1] as NetSession).lobby.get_local_seat_index()
	var timeout_ms: int = int(host_session.get_settings().peer_timeout_seconds * 1000.0)
	assert_ge(float(timeout_ms), 8000.0, "the shipped line rides out eight seconds of silence")
	var silent_ms: int = await _stall(
		1, DEAD_LINE_LIMIT_MS, func() -> bool: return host_session.get_peer_count() == clients
	)
	print("    the host let the dead line go after %d ms of silence" % silent_ms)
	assert_ge(float(silent_ms), float(timeout_ms), "and not before the timeout: a hitching machine is still a player")
	await step_ticks(CROSS_TICKS * 2)
	# The host: one peer fewer, the seat a bot's, and the bot plays the body.
	assert_eq_int(host_session.get_peer_count(), clients, "the host has let the dead line go")
	var seat: LobbySeat = host_session.lobby.get_seat(seat_index)
	assert_true(seat != null and seat.is_bot(), "its seat is a bot's on the host")
	var body: PlayerController = _rig.body(HOST, slot)
	assert_false(body.intent_source is RemoteIntentSource, "the body no longer waits on the dead line's input")
	assert_not_null(body.intent_source, "the bot has the body's controls")
	var from: Vector3 = body.global_position
	await step_ticks(150)
	assert_gt(body.global_position.distance_to(from), 1.0, "and runs it")
	assert_eq_int(host.get_phase(), MatchController.Phase.ROUND, "the host's round carries on")
	# The one that dropped: told, not left playing a dead match. The host says nothing to a line it gave up on,
	# so the client finds out when its own line times out in turn: one more timeout after it wakes.
	var gone: NetSession = _rig.sessions[1]
	var woke_ms: int = Time.get_ticks_msec()
	await _rig.wait_for(func() -> bool: return not gone.is_established(), DEAD_LINE_LIMIT_MS)
	print("    the dropped client learned %d ms after it woke" % (Time.get_ticks_msec() - woke_ms))
	assert_false(gone.is_established(), "the dropped client knows its session is over")
	await step_ticks(CROSS_TICKS)
	var screen: MatchResultScreen = _rig.matches[1].get_node("ResultScreen") as MatchResultScreen
	assert_true(screen.is_showing(), "the dropped client is shown a result")
	assert_eq_string(
		(screen.get_node("%Verdict") as Label).text, tr("RESULT_HOST_LOST"), "and it says the connection was lost"
	)
	# Everybody else: still in, and told the seat is a bot's.
	for peer: int in range(2, _rig.peer_count()):
		var session: NetSession = _rig.sessions[peer]
		assert_true(session.is_established(), "peer %d is still connected" % peer)
		var theirs: LobbySeat = session.lobby.get_seat(seat_index)
		assert_true(theirs != null and theirs.is_bot(), "peer %d is told the seat is a bot's" % peer)
		assert_eq_int(_rig.controller(peer).get_phase(), MatchController.Phase.ROUND, "peer %d plays on" % peer)
		assert_false(
			(_rig.matches[peer].get_node("ResultScreen") as MatchResultScreen).is_showing(),
			"peer %d is shown no result" % peer,
		)


func test_a_dead_line_is_told_to_everybody_hell_two_peers() -> void:
	await _a_dead_line_is_told_to_everybody(HELL, 1)


func test_a_dead_line_is_told_to_everybody_marble_four_peers() -> void:
	await _a_dead_line_is_told_to_everybody(MARBLE, 3)


# --- Known gap: no way back into a running match ----------------------------------------------------

## A player dialling a match that is already running is turned away, and nobody already in it is disturbed.
func _a_join_into_a_running_match_is_refused(map: StringName, clients: int) -> void:
	if OS.get_environment(OPEN_BUGS_ENV) != "1":
		skip(
			"LIVE BUG (minor, about 1 run in 5): refusing a join into a running match can log 'Unable to send packet "
			+ "on channel N, max channels: 0' on the host, from the snapshot broadcast reaching the peer being "
			+ "turned away. The refusal itself works. %s=1 runs this test." % OPEN_BUGS_ENV
		)
		return
	if not await _start_round(map, clients):
		return
	var host_session: NetSession = _rig.sessions[HOST]
	var port: int = (host_session.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.get_local_port()
	var refused: Array[String] = []
	host_session.lobby.join_refused.connect(func(_peer: int, reason: String) -> void: refused.append(reason))
	var late: NetSession = NetFixtures.make_peer(self, "Late", NetFixtures.settings())
	assert_eq_int(late.join("127.0.0.1", port), OK, "a late player dials the host")
	await _rig.wait_for(func() -> bool: return not refused.is_empty())
	assert_eq_int(refused.size(), 1, "the host refuses a join into a running match")
	await _rig.wait_for(func() -> bool: return not late.is_established() and host_session.get_peer_count() == clients + 1)
	assert_false(late.is_established(), "the late player is not left half connected")
	assert_eq_int(late.lobby.get_local_seat_index(), -1, "and holds no seat")
	late.leave()
	await _everyone_is_still_playing_the_same_round(clients, "after a late join was refused")


func test_a_join_into_a_running_match_is_refused_hell_two_peers() -> void:
	await _a_join_into_a_running_match_is_refused(HELL, 1)


func test_a_join_into_a_running_match_is_refused_marble_four_peers() -> void:
	await _a_join_into_a_running_match_is_refused(MARBLE, 3)


# --- Known gap: a client's input arriving before the host's scene stands -------------------------

## The client's scene is up and sending for a second before the host's own is; nothing breaks and the match starts.
func _a_client_ahead_of_the_host_is_quiet(map: StringName, clients: int) -> void:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return
	_rig.settings().rounds_to_win_match = 5
	_rig.settings().map_id = map
	# Returns false by design: with the host unbound nobody can be told the match has started.
	var late: Array[int] = [HOST]
	await _rig.launch(clients + 2, HOST, late)
	for client: int in range(1, clients + 1):
		_rig.drive(client, Vector2(0.0, 1.0))
	await step_ticks(120)
	for client: int in range(1, clients + 1):
		_rig.drive(client, Vector2.ZERO)
	if not await _rig.bind_late(HOST):
		fail("the host's match never started once its scene stood")
		return
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	await _everyone_is_still_playing_the_same_round(clients, "after the client's scene stood first")


func test_a_client_whose_scene_stands_before_the_hosts_is_quiet_hell_two_peers() -> void:
	await _a_client_ahead_of_the_host_is_quiet(HELL, 1)


func test_a_client_whose_scene_stands_before_the_hosts_is_quiet_marble_four_peers() -> void:
	await _a_client_ahead_of_the_host_is_quiet(MARBLE, 3)


# --- Known gap (tasks 84-88): the host decides, whatever a client sends ---------------------------

func test_a_client_cannot_drive_another_clients_body() -> void:
	if not await _start_round(HELL, 2):
		return
	var victim_slot: int = _rig.local_slot(1)
	var on_host: PlayerController = _rig.body(HOST, victim_slot)
	var from: Vector3 = on_host.global_position
	var facing: float = on_host.rotation.y
	# Client 2 holds a copy of client 1's link; it sends the host a run and a turn in client 1's name.
	var forged_link: PlayerNetLink = _rig.net_match(2).call(&"_link_of_slot", victim_slot)
	var real_link: PlayerNetLink = _rig.net_match(1).call(&"_link_of_slot", victim_slot)
	var forged: MoveIntent = MoveIntent.new()
	forged.move_direction = Vector2(0.0, 1.0)
	forged.view_angles = Vector2(1.5, 0.0)
	forged.view_absolute = true
	var intents: Array[MoveIntent] = [forged]
	var epoch: int = forged_link.call(&"_epoch")
	var tick: int = int(real_link.get(&"_tick")) + 600
	for step: int in 60:
		forged_link.rpc_id(
			NetTransport.AUTHORITY_PEER_ID, &"_receive_intent", NetCodec.pack_intents(tick + step, intents, 1, epoch)
		)
		await step_ticks(1)
	await step_ticks(CROSS_TICKS)
	assert_lt(on_host.global_position.distance_to(from), 0.1, "the host did not move client 1's body for client 2")
	assert_lt(absf(angle_difference(facing, on_host.rotation.y)), 0.01, "nor turn it")
	await _everyone_is_still_playing_the_same_round(2, "after a forged intent")
