extends TestCase
## Playtest regressions where a roster changes under a match: the rifle on a body about to be freed,
## and a seat that turns bot while the match is still launching.

const Rig = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const SETTLE_TICKS: int = 60

var _rig: Rig = null


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## An offline match with a bot holding the tower and the rifle; returns the controller.
func _a_bot_in_the_tower() -> MatchController:
	var scene: Node3D = TestFixtures.make_match()
	var controller: MatchController = scene.get_node("MatchController") as MatchController
	controller.rules = TestFixtures.match_rules()
	add_child(scene)
	var bot: MatchParticipant = controller.get_participants()[1]
	bot.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	assert_same(controller.get_seat_participant(), bot, "a bot holds the tower")
	assert_true(bot.body.is_ancestor_of(controller.rifle), "and the rifle sits on its body")
	return controller


func test_the_rifle_outlives_a_roster_rebuilt_with_fewer_bots() -> void:
	var controller: MatchController = await _a_bot_in_the_tower()
	var rifle: Rifle = controller.rifle
	controller.rules.prisoner_count -= 1
	controller.restart()
	await step_ticks(SETTLE_TICKS)
	if not assert_true(is_instance_valid(rifle), "the rifle was not freed with the bot that held it"):
		return
	assert_true(rifle.is_inside_tree(), "and it is still in the match")
	assert_eq_int(controller.get_participants().size(), controller.rules.get_participant_count(), "the roster was rebuilt")


## Host and [param clients] clients launch; client 1 leaves before it acknowledges, with the host's scene already built.
func _launch_with_a_leaver(clients: int, map: StringName) -> bool:
	_rig = Rig.new()
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().map_id = map
	# Not awaited: the launch waits on client 1, and client 1 leaves while it does.
	var late: Array[int] = [1]
	_rig.launch(clients + 2, 0, late)
	# The rig's own wait on a late peer is one second; this host waits until the leaver has left.
	_rig.sessions[HOST].get_settings().launch_timeout_seconds = 60.0
	if not await _rig.wait_for(func() -> bool:
		return _rig.matches.size() > 0 and _rig.matches[0] != null and (_rig.net_match(HOST).get(&"_links") as Array).size() > 1
	):
		fail("the host never built its match scene")
		return false
	var host_net: NetMatch = _rig.net_match(HOST)
	if not assert_false(host_net.has_started(), "the host is still waiting on client 1"):
		return false
	var link: PlayerNetLink = host_net.call(&"_link_for_seat", 1)
	assert_gt(float(link.owner_peer_id), 1.0, "client 1's body was built as that player's")
	_rig.sessions[1].leave()
	if not await _rig.wait_for(func() -> bool: return host_net.has_started()):
		fail("the host never started after the leaver left")
		return false
	var controller: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
		fail("the host never reached the round")
		return false
	return true


## The seat a leaver vacated during the launch is played by a bot once the match starts.
func _watch_a_leaver(clients: int, map: StringName) -> void:
	if not await _launch_with_a_leaver(clients, map):
		return
	var left: MatchParticipant = _rig.participant(HOST, 1)
	assert_false(left.is_human(), "the seat is a bot's on the host")
	if not assert_not_null(left.brain, "and the body has a brain"):
		return
	var from: Vector3 = left.body.global_position
	await step_ticks(180)
	assert_gt(left.body.global_position.distance_to(from), 3.0, "the bot runs the body the leaver left")
	for peer: int in range(2, _rig.peer_count()):
		var seen: MatchParticipant = _rig.participant(peer, 1)
		var learned: bool = await _rig.wait_for(func() -> bool: return not seen.is_human())
		assert_true(learned, "peer %d holds the seat as a bot's" % peer)
		assert_gt(seen.body.global_position.distance_to(from), 3.0, "peer %d sees it run" % peer)


func test_a_seat_vacated_during_the_launch_gets_a_brain_two_peers_hell() -> void:
	await _watch_a_leaver(1, &"bentham_ring")


func test_a_seat_vacated_during_the_launch_gets_a_brain_four_peers_marble() -> void:
	await _watch_a_leaver(3, &"marble")
