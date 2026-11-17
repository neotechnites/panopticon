extends TestCase
## The per-peer lifecycle and its one timeout rule, on real sockets: a machine frozen while loading or
## standing, one that beats but never stands, and a rematch under a new epoch.

const Rig = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const HELL: StringName = &"bentham_ring"
## Ticks for an event to cross loopback and be drawn, at the real clock these tests run on.
const CROSS_TICKS: int = 20

var _rig: Rig = null
var _saved_hz: int = 0
var _saved_scale: float = 1.0
## Per machine, the peers its own timeout rule let go, in the order it did.
var _timed_out: Array[PackedInt32Array] = []


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
	_timed_out.clear()


## Host and [param clients] connected, each machine's own drops recorded. The real clock from here.
func _connect(clients: int) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	for peer: int in _rig.peer_count():
		var mine: PackedInt32Array = PackedInt32Array()
		_timed_out.append(mine)
		var at: int = peer
		(_rig.sessions[peer] as NetSession).timed_out.connect(
			func(gone: int, _state: NetLobby.PeerState) -> void: _timed_out[at].append(gone)
		)
	_rig.settings().rounds_to_win_match = 5
	_rig.settings().map_id = HELL
	# A socket's timeout is wall time: a freeze of seconds has to be seconds of play too.
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	return true


## [param frozen]'s machine runs nothing, hears nothing and says nothing for [param wall_ms] (a shader
## compile, a debugger), or until [param until]; the others play on. Returns the wall milliseconds.
func _freeze(frozen: int, wall_ms: int, until: Callable = Callable()) -> int:
	var tree: SceneTree = get_tree()
	var machine: Node = (_rig.sessions[frozen] as NetSession).get_parent()
	tree.multiplayer_poll = false
	machine.process_mode = Node.PROCESS_MODE_DISABLED
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < wall_ms and not (until.is_valid() and until.call()):
		for peer: int in _rig.peer_count():
			if peer != frozen:
				(_rig.sessions[peer] as NetSession).multiplayer.poll()
		await tree.process_frame
	machine.process_mode = Node.PROCESS_MODE_INHERIT
	tree.multiplayer_poll = true
	return Time.get_ticks_msec() - began


func _every_round_runs() -> bool:
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	return true


## The host's own load freezes it 20 s past every client (a cold shader cache): it is LOADING, so they wait.
func test_a_host_loading_twenty_seconds_longer_than_every_client_keeps_them_all() -> void:
	if not await _connect(2):
		return
	var late: Array[int] = [HOST]
	await _rig.launch(4, HOST, late)
	for client: int in [1, 2]:
		if not await _rig.wait_for(func() -> bool: return _rig.net_match(client) != null and _rig.sessions[0].lobby.peer_state(
				(_rig.sessions[client] as NetSession).get_local_peer_id()) == NetLobby.PeerState.STANDING):
			fail("client %d never stood in the match" % client)
			return
	var frozen_ms: int = await _freeze(HOST, 20000)
	assert_ge(float(frozen_ms), 20000.0, "the host was frozen for 20 s")
	for client: int in [1, 2]:
		assert_true((_rig.sessions[client] as NetSession).is_established(), "client %d waited for the loading host" % client)
		assert_true(_timed_out[client].is_empty(), "client %d let nobody go" % client)
	if not await _rig.bind_late(HOST):
		fail("the host's match never started once its scene stood")
		return
	if not await _every_round_runs():
		return
	await step_ticks(CROSS_TICKS * 3)
	assert_eq_int((_rig.sessions[HOST] as NetSession).get_peer_count(), 3, "the host keeps every client")
	for peer: int in _rig.peer_count():
		assert_true(_timed_out[peer].is_empty(), "machine %d's rule let nobody go" % peer)


## A client frozen 12 s in a round is STANDING: the host lets it go at the line timeout, before it wakes.
func test_a_client_frozen_twelve_seconds_while_standing_is_dropped_by_the_host_at_the_timeout() -> void:
	if not await _connect(1):
		return
	if not await _rig.launch(3, HOST):
		fail("the match never started on every peer")
		return
	if not await _every_round_runs():
		return
	var host: NetSession = _rig.sessions[HOST]
	var client_id: int = (_rig.sessions[1] as NetSession).get_local_peer_id()
	var timeout_ms: int = int(host.get_settings().peer_timeout_seconds * 1000.0)
	var dropped_ms: Array[int] = [-1]
	var began: int = Time.get_ticks_msec()
	host.peer_left.connect(func(peer: int) -> void:
		if peer == client_id and dropped_ms[0] < 0:
			dropped_ms[0] = Time.get_ticks_msec() - began)
	await _freeze(1, 12000)
	print("    the host let the frozen client go after %d ms" % dropped_ms[0])
	assert_eq_int(Array(_timed_out[HOST]).count(client_id), 1, "the host's own rule let it go")
	# Timed from the last keep-alive, which went out up to one beat before the freeze.
	assert_ge(float(dropped_ms[0]), float(timeout_ms - NetSession.BEAT_MS), "not before the timeout")
	assert_lt(float(dropped_ms[0]), 12000.0, "and before it woke")


## The same freeze with a host that waits longer: the client wakes, and its own rule does not charge its
## freeze to the host. The listen clock stopped while it was deaf.
func test_a_client_frozen_twelve_seconds_does_not_drop_the_host_when_it_wakes() -> void:
	if not await _connect(1):
		return
	(_rig.sessions[HOST] as NetSession).settings.peer_timeout_seconds = 60.0
	if not await _rig.launch(3, HOST):
		fail("the match never started on every peer")
		return
	if not await _every_round_runs():
		return
	var client: NetSession = _rig.sessions[1]
	assert_eq_int(int(client.get_settings().peer_timeout_seconds), 8, "the client holds the host to the shipped 8 s")
	if not await _rig.wait_for(func() -> bool:
			return client.lobby.peer_state(NetTransport.AUTHORITY_PEER_ID) == NetLobby.PeerState.STANDING):
		fail("the client never heard the host stands")
		return
	# A second of the host's keep-alives under the client's own rule, so the freeze is what is timed.
	await step_ticks(60)
	await _freeze(1, 12000)
	await step_ticks(CROSS_TICKS * 6)
	assert_true(client.is_established(), "the woken client still has its host")
	assert_true(_timed_out[1].is_empty(), "its own rule let nobody go")
	assert_eq_int((_rig.sessions[HOST] as NetSession).get_peer_count(), 2, "and the host still has it")


## A peer that keeps its line alive but never stands in the launched scene is let go by the time-in-loading
## rule at the load stall, and not before.
func test_a_peer_that_beats_but_never_stands_is_dropped_at_the_load_stall() -> void:
	if not await _connect(1):
		return
	var host: NetSession = _rig.sessions[HOST]
	host.settings.load_stall_seconds = 2.5
	var client_id: int = (_rig.sessions[1] as NetSession).get_local_peer_id()
	var dropped_ms: Array[int] = [-1]
	var began: Array[int] = [Time.get_ticks_msec()]
	host.peer_left.connect(func(peer: int) -> void:
		if peer == client_id and dropped_ms[0] < 0:
			dropped_ms[0] = Time.get_ticks_msec() - began[0])
	var late: Array[int] = [1]
	began[0] = Time.get_ticks_msec()
	await _rig.launch(3, HOST, late)
	assert_true(await _rig.wait_for(func() -> bool: return dropped_ms[0] >= 0, 6000), "the host lets the peer go")
	print("    the host let the never-standing peer go after %d ms" % dropped_ms[0])
	assert_ge(float(dropped_ms[0]), 2500.0, "not before the load stall")
	assert_lt(float(dropped_ms[0]), 3500.0, "and at it, though its keep-alives never stopped")
	assert_eq_int(Array(_timed_out[HOST]).count(client_id), 1, "by the host's own rule")
	assert_true(host.lobby.get_seat(1).is_bot(), "and its seat is a bot's")


## A rematch is a launch under a new epoch: what was in flight from the finished match is refused.
func test_a_rematch_runs_under_a_new_epoch_and_refuses_the_old_epochs_packets() -> void:
	if not await _connect(1):
		return
	_rig.settings().rounds_to_win_match = 1
	if not await _rig.launch(3, HOST):
		fail("the match never started on every peer")
		return
	if not await _every_round_runs():
		return
	var host: MatchController = _rig.controller(HOST)
	host._win_match(host.get_participants()[0])
	if not await _rig.wait_for(func() -> bool: return _rig.controller(1).is_match_over()):
		fail("the client never saw the match end")
		return
	var old: int = (_rig.sessions[HOST] as NetSession).lobby.get_epoch()
	for peer: int in _rig.peer_count():
		(_rig.sessions[peer] as NetSession).flow.rematch()
	if not await _rig.wait_rematch(old):
		fail("the rematch never started")
		return
	await step_ticks(CROSS_TICKS)
	var client: NetSession = _rig.sessions[1]
	var now: int = client.lobby.get_epoch()
	assert_true(now != old, "the rematch is a new epoch")
	assert_eq_int(client.replicator.get_scene(), now, "and the client takes only it")
	# A snapshot of the finished match, newer than anything held, arriving late.
	var stale: WorldSnapshot = WorldSnapshot.new()
	stale.tick = client.replicator.get_latest_tick() + 600
	stale.scene = old
	var held: int = client.replicator.get_latest_tick()
	client.replicator._receive_snapshot(NetCodec.pack_snapshot(stale))
	assert_eq_int(client.replicator.get_latest_tick(), held, "a snapshot of the finished match is refused")
	var current: WorldSnapshot = WorldSnapshot.new()
	current.tick = held + 600
	current.scene = now
	client.replicator._receive_snapshot(NetCodec.pack_snapshot(current))
	assert_eq_int(client.replicator.get_latest_tick(), held + 600, "while one of the rematch is taken")
