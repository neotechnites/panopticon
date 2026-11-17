extends TestCase
## The end of a networked match as each machine is told it: verdicts, restarts and the roster a restart keeps.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const BLANK_SCENE_PATH: String = "res://tests/support/blank_scene.tscn"
const HOST: int = 0
const A: int = 1
const B: int = 2

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _result(peer: int) -> MatchResultScreen:
	return _rig.matches[peer].get_node("ResultScreen") as MatchResultScreen


func _verdict(peer: int) -> String:
	return (_result(peer).get_node("%Verdict") as Label).text


func _play(clients: int, seats: int) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	if not await _rig.launch(seats, 0):
		fail("the match never started on every peer")
		return false
	return true


func _everyone_sees_the_result() -> bool:
	return await _rig.wait_for(func() -> bool:
		for peer: int in _rig.sessions.size():
			if _rig.sessions[peer].is_established() and not _result(peer).is_showing():
				return false
		return true)


func _win(slot: int) -> bool:
	var host: MatchController = _rig.controller(HOST)
	host._win_match(host.get_participants()[slot])
	if not await _everyone_sees_the_result():
		fail("the result never reached every machine")
		return false
	return true


func _every_body_stands(peer: int) -> bool:
	for participant: MatchParticipant in _rig.controller(peer).get_participants():
		if not is_instance_valid(participant.body) or participant.body.is_queued_for_deletion():
			return false
	return true


## The client's own seat wins the match: the client reads VICTORY and the host DEFEAT.
func test_the_client_that_won_is_told_it_won() -> void:
	if not await _play(1, 3):
		return
	assert_eq_int(_rig.local_slot(A), 1, "the client holds slot 1")
	if not await _win(1):
		return
	assert_eq_string(_verdict(HOST), tr("RESULT_DEFEAT"), "the host lost, and is told so")
	assert_eq_string(_verdict(A), tr("RESULT_VICTORY"), "the client won, and is told so")


func test_the_client_that_lost_is_told_it_lost() -> void:
	if not await _play(1, 3):
		return
	if not await _win(0):
		return
	assert_eq_string(_verdict(HOST), tr("RESULT_VICTORY"), "the host won, and is told so")
	assert_eq_string(_verdict(A), tr("RESULT_DEFEAT"), "the client lost, and is told so")


func test_a_rematch_starts_when_every_human_asked() -> void:
	if not await _play(2, 3):
		return
	if not await _win(0):
		return
	for peer: int in [HOST, A, B]:
		_rig.net_match(peer).request_rematch()
	var host: MatchController = _rig.controller(HOST)
	var restarted: bool = await _rig.wait_for(func() -> bool: return not host.is_match_over())
	assert_true(restarted, "three of three asked: the match restarts")


## A setting applied mid-match leaves the saved prisoner count in the live rules; the roster is still the seats'.
func test_a_rematch_keeps_the_seated_roster_after_a_setting_is_applied() -> void:
	if not await _play(1, 4):
		return
	_rig.settings().prisoner_count = 7
	SettingsStore.instance().applied.emit()
	if not await _win(0):
		return
	for peer: int in [HOST, A]:
		_rig.net_match(peer).request_rematch()
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return not host.is_match_over()):
		fail("the rematch never started")
		return
	await step_ticks(20)
	for peer: int in [HOST, A]:
		assert_eq_int(_rig.controller(peer).get_participants().size(), 4, "peer %d still fields the four seats" % peer)
		assert_true(_every_body_stands(peer), "peer %d holds no freed body" % peer)
	if is_failed():
		return
	await _win(0)
	assert_true(_rig.controller(HOST).is_match_over(), "the rematch is won without the host falling over")


## Stand a peer's pause menu on a blank scene instead of the real main menu, and take it down after.
func _leave_by_menu(peer: int) -> void:
	var menu: PauseMenu = _rig.matches[peer].get_node("PauseMenu") as PauseMenu
	menu.main_menu_scene_path = BLANK_SCENE_PATH
	menu.return_to_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	var blank: Node = get_tree().current_scene
	if blank != null:
		get_tree().current_scene = null
		blank.queue_free()


func test_a_client_leaving_by_the_menu_leaves_the_session() -> void:
	if not await _play(2, 4):
		return
	var a_peer: int = _rig.sessions[A].get_local_peer_id()
	await _leave_by_menu(A)
	assert_eq_int(
		int(_rig.sessions[A].get_connection_state()), int(NetTransport.ConnectionState.OFFLINE),
		"Leave Match closes the client's session",
	)
	var host: NetSession = _rig.sessions[HOST]
	assert_true(await _rig.wait_for(func() -> bool: return not host.has_peer(a_peer)), "the host is told at once")
	assert_true(host.lobby.get_seat(A).is_bot(), "and a bot takes the leaver's seat for the rest of the match")
	assert_true(_rig.sessions[B].is_established(), "the other client plays on")


func test_the_host_leaving_by_the_menu_ends_the_session_for_everyone() -> void:
	if not await _play(1, 3):
		return
	await _leave_by_menu(HOST)
	assert_eq_int(
		int(_rig.sessions[HOST].get_connection_state()), int(NetTransport.ConnectionState.OFFLINE),
		"Leave Match closes the host's session",
	)
	var client: NetSession = _rig.sessions[A]
	assert_true(await _rig.wait_for(func() -> bool: return not client.is_established()), "the client is told at once")
	assert_true(_result(A).is_showing(), "and its screen says the host is gone")
	assert_eq_string(_verdict(A), tr("RESULT_HOST_LOST"), "in those words")


## Where everyone goes after a match is the host's to say: a client has no button that goes alone.
func test_a_client_cannot_leave_for_the_hub_ahead_of_the_host() -> void:
	if not await _play(1, 3):
		return
	HubLobby.returns_to_hub = true
	if not await _win(0):
		return
	var again_host: Button = _result(HOST).get_node("%PlayAgainButton") as Button
	var again_client: Button = _result(A).get_node("%PlayAgainButton") as Button
	assert_true(again_host.visible, "the host keeps its way back to the hub")
	assert_false(again_client.visible, "the client is not offered one of its own")
	_result(A).play_again()
	await get_tree().process_frame
	await get_tree().process_frame
	var changed: Node = get_tree().current_scene
	assert_null(changed, "and asking anyway changes no scene")
	if changed != null:
		get_tree().current_scene = null
		changed.queue_free()
	assert_true(_result(A).is_showing(), "the client's result stays up")
	assert_true((_result(A).get_node("%RematchButton") as Button).is_visible_in_tree(), "with Rematch on it")


## The restart key is an offline tool: a seated match restarts by its players' rematch.
func test_the_restart_key_does_not_restart_a_seated_match() -> void:
	if not await _play(1, 3):
		return
	var starts: Array[int] = [0]
	var host: MatchController = _rig.controller(HOST)
	host.match_started.connect(func(_count: int) -> void: starts[0] += 1)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = MatchController.RESTART_KEY
	key.pressed = true
	host._unhandled_input(key)
	await step_ticks(5)
	assert_eq_int(starts[0], 0, "R on the host mid-match restarts nothing")
	if not await _win(0):
		return
	host._unhandled_input(key)
	await step_ticks(5)
	assert_eq_int(starts[0], 0, "nor on the result screen")
	assert_eq_int(int(_rig.sessions[HOST].lobby.get_phase()), int(NetLobby.Phase.POST_MATCH), "the lobby still says the match is over")
	assert_true(host.is_match_over(), "and so does the match")
