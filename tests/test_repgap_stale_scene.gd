extends TestCase
## What a client sends at a match scene the host has already left reaches a host with no such
## scene and is dropped in silence: its input every tick, and its press of Rematch.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CROSS_TICKS: int = 30

var _rig: RefCounted = null
var _log: ErrorLog = null


## What the engine logs as an error while it is registered.
class ErrorLog extends Logger:
	var lines: PackedStringArray = PackedStringArray()
	var _lock: Mutex = Mutex.new()

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		lines.append("%s %s (%s:%d in %s)" % [code, rationale, file, line, function])
		_lock.unlock()

	func said() -> String:
		_lock.lock()
		var text: String = "%d engine errors%s" % [lines.size(), "" if lines.is_empty() else ", first: " + lines[0]]
		_lock.unlock()
		return text

	func count() -> int:
		_lock.lock()
		var total: int = lines.size()
		_lock.unlock()
		return total


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _log != null:
		OS.remove_logger(_log)
		_log = null
	if _rig != null:
		_rig.close()
		_rig = null


## [param peers] machines in a finished one-round match on [param map], the host having held the tower.
func _finish_a_match(peers: int, map: StringName) -> bool:
	if not await _rig.connect_peers(self, peers - 1):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 1
	_rig.settings().map_id = map
	if not await _rig.launch(peers + 1, 0):
		fail("the match never started")
		return false
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("the host never reached the round")
		return false
	await step_ticks(CROSS_TICKS)
	TestFixtures.pin_the_field(host, null)
	for participant: MatchParticipant in host.get_participants():
		if participant.is_running:
			host.convert_participant(participant)
	for peer: int in peers:
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.is_match_over()):
			fail("machine %d never saw the match end" % peer)
			return false
	return true


## The host's scene goes, as a scene change takes it, before any client has heard: what they send
## meanwhile is what is in flight when the host really leaves.
func _the_host_leaves_its_scene_unannounced() -> void:
	var scene: Node = _rig.matches[HOST]
	scene.get_parent().remove_child(scene)
	scene.queue_free()


func _stale_sends_are_quiet(peers: int, map: StringName) -> void:
	if not await _finish_a_match(peers, map):
		return
	var arrived: Array[int] = [0]
	for peer: int in range(1, peers):
		# A client's packets still cross: the silence below is the host's, not the wire's.
		_rig.drive(peer, Vector2(0.0, 1.0))
	_log = ErrorLog.new()
	OS.add_logger(_log)
	_the_host_leaves_its_scene_unannounced()
	var replicator: NetReplicator = _rig.sessions[HOST].replicator
	var tally: Callable = func(_tick: int, _bodies: int) -> void: arrived[0] += 1
	replicator.snapshot_sent.connect(tally)
	await step_ticks(CROSS_TICKS)
	for peer: int in range(1, peers):
		assert_gt(float(_rig.net_match(peer).get_local_link().get_intent_tick()), 0.0, "client %d is still sending its input" % peer)
		_rig.sessions[peer].flow.rematch()
	await step_ticks(CROSS_TICKS)
	replicator.snapshot_sent.disconnect(tally)
	assert_eq_int(arrived[0], 0, "the host, with no scene, sends no snapshot of one")
	assert_eq_int(_log.count(), 0, "what %d client(s) sent at a scene the host had left: %s" % [peers - 1, _log.said()])
	assert_eq_int(_rig.sessions[HOST].get_peer_count(), peers, "and nobody was dropped for it")


func test_two_machines_what_a_client_sends_at_a_scene_the_host_left_is_dropped_in_silence_hell() -> void:
	await _stale_sends_are_quiet(2, &"bentham_ring")


func test_four_machines_what_clients_send_at_a_scene_the_host_left_is_dropped_in_silence_marble() -> void:
	await _stale_sends_are_quiet(4, &"marble")


## The same request, with the host's scene standing, is a vote: the path that carries it works.
func test_a_clients_rematch_request_is_a_vote_while_the_hosts_scene_stands() -> void:
	if not await _finish_a_match(2, &"bentham_ring"):
		return
	var host: MatchController = _rig.controller(HOST)
	var epoch: int = _rig.sessions[HOST].lobby.get_epoch()
	_rig.sessions[1].flow.rematch()
	await step_ticks(CROSS_TICKS)
	assert_eq_int(_rig.sessions[HOST].lobby.get_epoch(), epoch, "one of two votes does not relaunch it")
	_rig.sessions[HOST].flow.rematch()
	var restarted: bool = await _rig.wait_rematch(epoch)
	assert_true(restarted, "the client's vote and the host's relaunch the match")
	await step_ticks(CROSS_TICKS)
