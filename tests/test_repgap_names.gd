extends TestCase
## Every machine shows every player under the name that player asked for: in the lobby and the hub,
## through the match, and on the result screen, at two, three and four machines.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CLIENT_NAMES: PackedStringArray = ["Ada", "Bo", "Cy"]
const CROSS_TICKS: int = 30

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## The name each seat's player asked for, the host's first.
func _asked(peers: int) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(["Host"])
	names.append_array(CLIENT_NAMES.slice(0, peers - 1))
	return names


func _connect(peers: int) -> bool:
	_rig.client_names = CLIENT_NAMES.slice(0, peers - 1)
	if not await _rig.connect_peers(self, peers - 1):
		fail("the loopback handshake did not complete")
		return false
	return true


## Every machine's seat table names every human as asked.
func _lobbies_name_everyone(peers: int, where: String) -> void:
	var asked: PackedStringArray = _asked(peers)
	for peer: int in peers:
		for seat: int in peers:
			assert_eq_string(
				_rig.sessions[peer].lobby.get_seat(seat).display_name, asked[seat],
				"%s: machine %d's lobby names seat %d" % [where, peer, seat],
			)


func _names_in_the_hub(peers: int) -> void:
	if not await _connect(peers):
		return
	await step_ticks(CROSS_TICKS)
	_lobbies_name_everyone(peers, "seated")
	_rig.bind_hubs()
	var built: bool = await _rig.wait_for(func() -> bool:
		for peer: int in peers:
			if _rig.controller(peer).get_participants().size() != peers:
				return false
		return true)
	if not assert_true(built, "every machine's hub has a body per player"):
		return
	await step_ticks(CROSS_TICKS)
	var asked: PackedStringArray = _asked(peers)
	for peer: int in peers:
		var listed: String = String(_rig.matches[peer].get_node("HubLobby").call("_seat_lines"))
		for seat: int in peers:
			assert_eq_string(
				_rig.participant(peer, seat).display_name, asked[seat],
				"machine %d's hub body for seat %d carries its player's name" % [peer, seat],
			)
			assert_true(listed.contains(asked[seat]), "machine %d's hub panel lists %s: %s" % [peer, asked[seat], listed.replace("\n", " | ")])


## The first [param kind] node in [param peer]'s match scene.
func _find(peer: int, kind: String) -> Node:
	var found: Array[Node] = (_rig.matches[peer] as Node).find_children("*", kind, true, false)
	return found[0] if not found.is_empty() else null


func _names_through_a_match(peers: int, map: StringName) -> void:
	if not await _connect(peers):
		return
	_rig.settings().rounds_to_win_match = 1
	_rig.settings().map_id = map
	# The first client opens in the tower, so a client's name is the one every screen has to show.
	if not await _rig.launch(peers + 1, 1):
		fail("the match never started")
		return
	for peer: int in peers:
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("machine %d never reached the round" % peer)
			return
	await step_ticks(CROSS_TICKS)
	_lobbies_name_everyone(peers, "in the match")
	var asked: PackedStringArray = _asked(peers)
	var guard: String = asked[1]
	for peer: int in peers:
		for seat: int in peers:
			assert_eq_string(
				_rig.participant(peer, seat).display_name, asked[seat],
				"machine %d's match names seat %d" % [peer, seat],
			)
		assert_false(_rig.participant(peer, peers).display_name.is_empty(), "machine %d names the bot" % peer)
		var seat_holder: MatchParticipant = _rig.controller(peer).get_seat_participant()
		assert_eq_string(seat_holder.display_name if seat_holder != null else "", guard, "machine %d has %s in the tower" % [peer, guard])
		if peer != 1:
			var hud: MatchHud = _find(peer, "MatchHud") as MatchHud
			assert_true(hud != null and hud.get_status_text().contains(guard), "machine %d's HUD names the guard: %s" % [peer, hud.get_status_text() if hud != null else "no HUD"])

	# The guard clears the ring: a one-round match is won by the client in the tower.
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	for participant: MatchParticipant in host.get_participants():
		if participant.is_running:
			host.convert_participant(participant)
	for peer: int in peers:
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.is_match_over()):
			fail("machine %d never saw the match end" % peer)
			return
	var heard: Array[PackedStringArray] = []
	for peer: int in peers:
		heard.append(PackedStringArray())
		var at: int = peer
		_rig.net_match(peer).rematch_votes_changed.connect(func(names: PackedStringArray) -> void: heard[at] = names)
	for peer: int in peers:
		var screen: MatchResultScreen = _find(peer, "MatchResultScreen") as MatchResultScreen
		if not assert_not_null(screen, "machine %d has a result screen" % peer):
			return
		var detail: Label = screen.get("_detail_label")
		var named: bool = await _rig.wait_for(func() -> bool: return detail.text.contains(guard))
		assert_true(named, "machine %d's result screen names the winner %s: %s" % [peer, guard, detail.text.replace("\n", " | ")])
		assert_eq_string(_rig.controller(peer).get_match_winner().display_name, guard, "machine %d's winner is %s" % [peer, guard])
	# The last machine asks for a rematch: every result screen says who, by name.
	var voter: int = peers - 1
	_rig.net_match(voter).request_rematch()
	var told: bool = await _rig.wait_for(func() -> bool:
		for peer: int in peers:
			if heard[peer].size() != 1:
				return false
		return true)
	assert_true(told, "every machine heard the vote")
	for peer: int in peers:
		assert_eq_string(", ".join(heard[peer]), asked[voter], "machine %d reads who asked for the rematch" % peer)


func test_two_machines_name_each_other_in_the_hub() -> void:
	await _names_in_the_hub(2)


func test_three_machines_name_each_other_in_the_hub() -> void:
	await _names_in_the_hub(3)


func test_four_machines_name_each_other_in_the_hub() -> void:
	await _names_in_the_hub(4)


func test_two_machines_name_each_other_through_a_match_on_hell() -> void:
	await _names_through_a_match(2, &"bentham_ring")


func test_three_machines_name_each_other_through_a_match_on_marble() -> void:
	await _names_through_a_match(3, &"marble")


func test_four_machines_name_each_other_through_a_match_on_hell() -> void:
	await _names_through_a_match(4, &"bentham_ring")


## A player who asked for no name is shown under one name everywhere, the result screen's votes included.
func test_a_player_with_no_name_is_one_name_on_every_screen() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("the loopback handshake did not complete")
		return
	_rig.settings().rounds_to_win_match = 1
	if not await _rig.launch(3, 0):
		fail("the match never started")
		return
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return
	await step_ticks(CROSS_TICKS)
	var shown: String = _rig.participant(HOST, 1).display_name
	assert_false(shown.is_empty(), "the host's match shows the unnamed client under a name")
	assert_eq_string(_rig.participant(1, 1).display_name, shown, "and its own machine shows the same one")
	TestFixtures.pin_the_field(host, null)
	for participant: MatchParticipant in host.get_participants():
		if participant.is_running:
			host.convert_participant(participant)
	var client: MatchController = _rig.controller(1)
	if not await _rig.wait_for(func() -> bool: return client.is_match_over()):
		fail("the client never saw the match end")
		return
	var heard: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
	_rig.net_match(HOST).rematch_votes_changed.connect(func(names: PackedStringArray) -> void: heard[0] = names)
	_rig.net_match(1).rematch_votes_changed.connect(func(names: PackedStringArray) -> void: heard[1] = names)
	_rig.net_match(1).request_rematch()
	if not await _rig.wait_for(func() -> bool: return heard[0].size() == 1 and heard[1].size() == 1):
		fail("the vote was never read on both machines")
		return
	assert_eq_string(heard[0][0], shown, "the host reads the vote under the name the match showed")
	assert_eq_string(heard[1][0], shown, "and so does the client")
