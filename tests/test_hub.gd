extends TestCase

## The hub world lobby: the ring of wedges you walk around between matches.
##
## [b]The scene is the shipped one.[/b] Every test here instances the real
## [code]scenes/hub/hub.tscn[/code], because the thing most likely to break is
## the wiring -- a [NodePath] export that is not named in a scene's
## [code]node_paths[/code] header resolves to null at load with no error at all,
## and a hub whose controller is not in [member MatchController.hub_mode] would
## try to run a race on a world with no track.
##
## [b]The two-peer tests are two real sessions on two real sockets[/b], built by
## [NetFixtures] the way [code]tests/test_net_session.gd[/code] builds them: one
## [MultiplayerAPI] per branch, so RPCs can only reach the other peer through
## the loopback interface. That is also why both hubs are named [code]Hub[/code]
## -- RPCs resolve by node path relative to each branch, so the two must be
## shaped identically.
##
## [b]Nothing here changes scene.[/b] [method SceneTree.change_scene_to_file]
## replaces the whole tree, which would take the test with it and could never
## work with two hubs standing side by side. [member HubLobby.changes_scene] is
## off and [signal HubLobby.match_starting] is what is asserted: the decision to
## switch, on both machines, which is the half a test can own.

const HUB_SCENE_PATH: String = "res://scenes/hub/hub.tscn"

## Ticks to let the authority produce and deliver a few snapshots. The same
## budget [code]tests/test_net_session.gd[/code] uses, for the same reason.
const REPLICATION_TICKS: int = 60

## How close a client's copy of a body has to end up to the authority's.
##
## Not zero: a client draws a mirrored body a JITTER BUFFER in the past by
## design, and the buffer's depth is measured from the connection rather than
## fixed -- see [NetReplicator]. Under this runner the socket is polled far less
## often than the compressed physics ticks, which reads as tens of milliseconds
## of jitter and buys a correspondingly deep buffer. What this number is for is
## the difference between followed and did not: the body starts parked a long
## way off.
const CONVERGENCE_METRES: float = 5.0

## Where a client's copy is parked before any snapshot arrives, so that "it
## converged" cannot be confused with "it was already there".
const PARKED_POSITION: Vector3 = Vector3(0.0, 0.0, 250.0)

var _host: NetSession = null
var _client: NetSession = null


func after_each() -> void:
	# Static, and read by the result screen in EVERY other test file: a hub left
	# set here would turn Play Again into Back to the hub for the whole run.
	HubLobby.returns_to_hub = false
	SettingsStore.instance().settings.map_pick_mode = GameSettings.DEFAULT_MAP_PICK_MODE
	SettingsStore.instance().settings.vote_seconds = GameSettings.DEFAULT_VOTE_SECONDS
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


# --- The scene ----------------------------------------------------------------

## The shipped hub is a hub: hub mode on, no rifle, and one body standing on a
## spawn marker rather than at the origin.
func test_the_hub_scene_is_a_hub_and_not_a_match() -> void:
	var hub: Node3D = _make_hub(self, null)
	var controller: MatchController = hub.get_node("MatchController") as MatchController
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby

	assert_true(controller.hub_mode, "the controller runs in hub mode")
	assert_null(controller.rifle, "there is no rifle in the lobby")
	assert_eq_string(controller.get_phase_name(), "HUB", "and no race and no round")
	assert_eq_int(controller.get_participants().size(), 1, "one body, offline: the player")
	assert_true(lobby.is_host(), "an offline hub is its own host")
	assert_eq_int(lobby.get_player_count(), 1, "and has one person in it")

	var participant: MatchParticipant = controller.get_participants()[0]
	assert_same(participant.body, hub.get_node("Player"), "the body is the scene's player")
	assert_true(participant.is_running, "it is in the world, so it can shove and be shoved")
	assert_false(participant.body.is_guard, "and it is nobody's guard")
	var spawn: Marker3D = hub.get_node("HubWorld/HubSpawns/Spawn1") as Marker3D
	assert_vec3_almost_eq(
		participant.body.global_position, spawn.global_position, 0.01,
		"the player stands on the first hub spawn"
	)


## Ten wedges, one of which has a map on it. The other nine are undecided, and
## the whole of undecided is a null scene -- there is no second flag for it.
func test_ten_wedges_one_map_and_nine_question_marks() -> void:
	var hub: Node3D = _make_hub(self, null)
	var wedges: Node3D = hub.get_node("HubWorld/Wedges") as Node3D
	assert_eq_int(wedges.get_child_count(), 10, "ten 36 degree wedges")

	var decided: int = 0
	for child: Node in wedges.get_children():
		var wedge: MapWedge = child as MapWedge
		if not assert_not_null(wedge, "%s carries the MapWedge script" % child.name):
			continue
		assert_not_null(wedge.get_dais(), "%s has a dais to stand on" % wedge.name)
		var sign_label: Label3D = wedge.get_node_or_null(wedge.label_path) as Label3D
		if not assert_not_null(sign_label, "%s has a sign" % wedge.name):
			continue
		assert_false(sign_label.fixed_size, "%s's sign is sized in metres, not on screen" % wedge.name)
		assert_almost_eq(
			sign_label.font_size * sign_label.pixel_size, 1.28, 0.01,
			"%s's glyphs are about 1.3 m tall: readable at 40 m, not a wall at 5" % wedge.name
		)
		assert_almost_eq(wedge.sign_alpha_at(40.0), 1.0, 0.001, "and solid from across the ring")
		assert_lt(wedge.sign_alpha_at(0.0), 0.2, "and faded to nothing when you stand under it")
		if wedge.is_decided():
			decided += 1
			assert_eq_string(String(wedge.map_id), "bentham_ring", "the hell wedge is Map 1")
			assert_eq_string(sign_label.text, "MAP 1", "and says so")
		else:
			assert_eq_string(sign_label.text, "?", "%s is undecided" % wedge.name)
			assert_eq_string(String(wedge.map_id), "", "and names no map")
	assert_eq_int(decided, 1, "exactly one wedge has been decided")


## The spawns are spread. Two capsules in one cubic metre are thrown out of the
## world by the depenetration solver, which this project has already paid for.
func test_the_spawns_are_far_enough_apart_to_stand_on() -> void:
	var hub: Node3D = _make_hub(self, null)
	var spawns: Node3D = hub.get_node("HubWorld/HubSpawns") as Node3D
	assert_ge(float(spawns.get_child_count()), 2.0, "there is more than one place to stand")
	var places: Array[Vector3] = []
	for child: Node in spawns.get_children():
		var marker: Marker3D = child as Marker3D
		if marker == null:
			continue
		places.append(marker.global_position)
		# Facing the tower, not the wall. A Transform3D in a .tscn takes its
		# basis as ROWS, and getting that backwards spawns the field looking
		# out of the arena -- which is the kind of thing nobody notices until
		# they play it.
		var forward: Vector3 = -marker.global_transform.basis.z
		var inward: Vector3 = (Vector3.ZERO - marker.global_position)
		forward.y = 0.0
		inward.y = 0.0
		assert_gt(
			forward.normalized().dot(inward.normalized()), 0.9,
			"%s faces the tower" % marker.name
		)
	for i: int in places.size():
		for j: int in range(i + 1, places.size()):
			assert_gt(
				places[i].distance_to(places[j]), 1.5,
				"spawn %d and spawn %d are not on top of each other" % [i + 1, j + 1]
			)


# --- Offline: hub -> match -> hub ---------------------------------------------

## Standing on the hell wedge's dais offers the map; pressing it starts it.
func test_the_host_is_offered_map_one_on_the_dais() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby

	assert_eq_string(lobby.get_prompt(), "", "nothing is offered from across the ring")
	await _stand_on_the_dais(hub)
	assert_true(lobby.is_on_the_dais(), "the body is in the trigger")
	assert_eq_string(lobby.get_prompt(), "Start MAP 1: E", "and the host is offered the map")


## The offline round trip: the hub asks for a match, and the match that comes
## out of it knows to come back here rather than to the main menu.
func test_an_offline_hub_starts_a_match_that_returns_to_the_hub() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	var started: Array[StringName] = []
	lobby.match_starting.connect(func(map_id: StringName) -> void: started.append(map_id))

	await _stand_on_the_dais(hub)
	assert_true(lobby.start_map(), "the host started the map under their feet")
	assert_eq_int(started.size(), 1, "and said so exactly once")
	if not started.is_empty():
		assert_eq_string(String(started[0]), "bentham_ring", "the map is the hell wedge's")
	assert_true(HubLobby.returns_to_hub, "the match will come back to a hub")
	assert_eq_string(
		String(SettingsStore.instance().settings.map_id), "bentham_ring",
		"and the match is set up to run that map"
	)

	# The match the hub asked for, offline: the host alone plus bots, on the map
	# the wedge named, and its way out is the hub rather than the main menu.
	assert_eq_string(
		lobby.match_scene_path, TestFixtures.MATCH_SCENE_PATH,
		"the hub switches to the match scene"
	)
	var match_root: Node3D = TestFixtures.make_match()
	add_child(match_root)
	var playing: MatchController = match_root.get_node("MatchController") as MatchController
	assert_false(playing.hub_mode, "which comes up as a match, not a second hub")
	assert_eq_int(
		playing.get_participants().size(),
		SettingsStore.instance().settings.prisoner_count + 1,
		"with the host and the bots that fill the field"
	)
	var screen: MatchResultScreen = match_root.get_node("ResultScreen") as MatchResultScreen
	assert_true(screen.returns_to_hub(), "the result screen goes back to the hub")
	assert_false(screen.hub_scene_path.is_empty(), "and knows which scene that is")

	# And the hub it comes back to arms again, with the player standing in it.
	match_root.free()
	var again: Node3D = _make_hub(self, null)
	var controller: MatchController = again.get_node("MatchController") as MatchController
	assert_eq_string(controller.get_phase_name(), "HUB", "the hub is a hub again")
	assert_eq_int(controller.get_participants().size(), 1, "with the player back in it")


## A start press that lands after the launch has begun is ignored rather than
## dereferencing a null viewport, and two presses in one frame start one match.
##
## [method SceneTree.change_scene_to_file] takes the outgoing scene out of the
## tree the moment it is called, so the rest of that input frame runs on a node
## whose [method Node.get_viewport] is null. The listener below does exactly
## that, and the presses are delivered by hand because the engine will not
## dispatch to a node that has already left the tree.
func test_two_start_presses_in_one_frame_start_one_match() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	var started: Array[StringName] = []
	lobby.match_starting.connect(func(map_id: StringName) -> void:
		started.append(map_id)
		hub.get_parent().remove_child(hub)
	)
	await _stand_on_the_dais(hub)

	var press: InputEventAction = InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	lobby._unhandled_input(press)
	lobby._unhandled_input(press)

	assert_eq_int(started.size(), 1, "one launch out of two presses in one frame")
	assert_false(lobby.start_map(), "and the hub will not start a second")
	hub.free()


## Tab holds nothing while it is closed: the body reads the mouse and the
## keyboard exactly as it does in a scene with no panel at all.
func test_the_rules_panel_is_inert_while_it_is_closed() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	var overlay: Control = hub.get_node("Overlay/Root") as Control

	assert_false(lobby.is_overlay_open(), "the hub opens with the panel down")
	assert_false(overlay.visible, "which is not drawn")
	assert_eq_int(
		int(overlay.process_mode), int(Node.PROCESS_MODE_DISABLED),
		"and is not processing either"
	)

	lobby.set_overlay_open(true)
	assert_true(overlay.visible, "Tab raises it")
	assert_eq_int(
		int(overlay.process_mode), int(Node.PROCESS_MODE_INHERIT), "and wakes it"
	)
	assert_eq_string(lobby.get_prompt(), "", "the start prompt stands down behind it")

	lobby.set_overlay_open(false)
	assert_false(overlay.visible, "and Tab puts it back down")


# --- The vote -----------------------------------------------------------------

## Off by default: the dais offers the start, and there is no vote to open.
## Switched on, the same press opens a vote, and the host alone on its own dais
## wins it when the clock runs out.
func test_an_offline_vote_with_the_host_alone_starts_its_own_wedge() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	var wedge: MapWedge = hub.get_node("HubWorld/Wedges/W01_Hell") as MapWedge
	var sign_label: Label3D = wedge.get_node(wedge.label_path) as Label3D
	var vote_label: Label = hub.get_node("HUD/Root/Vote") as Label
	var started: Array[StringName] = []
	lobby.match_starting.connect(func(map_id: StringName) -> void: started.append(map_id))

	await _stand_on_the_dais(hub)
	assert_eq_string(lobby.get_prompt(), "Start MAP 1: E", "host pick is the default")
	assert_false(lobby.open_vote(), "and a vote cannot be opened under it")

	_vote_rules(5.0)
	lobby._refresh()
	assert_eq_string(lobby.get_prompt(), "Open vote: E", "under VOTE the dais offers the vote")
	assert_true(lobby.open_vote(7), "the host opened it")
	assert_true(lobby.is_vote_open(), "and it is open")
	assert_eq_int(lobby.get_vote_count(wedge), 1, "the host's body on the dais is its vote")
	assert_eq_string(sign_label.text, "MAP 1\n1 vote", "the sign shows the count")
	assert_true(vote_label.visible, "the readout is up")
	assert_eq_string(vote_label.text, "VOTE  5 s\nMAP 1  1", "with the timer and the count")
	assert_eq_string(lobby.get_prompt(), "Cancel vote: E", "and the host is offered the cancel")
	assert_eq_int(started.size(), 0, "nothing has started yet")

	await step_seconds(5.5)
	assert_false(lobby.is_vote_open(), "the clock ran out")
	assert_same(lobby.get_vote_winner(), wedge, "the host's wedge won")
	assert_false(lobby.was_vote_tied(), "outright")
	assert_eq_int(started.size(), 1, "and the match started once")
	if not started.is_empty():
		assert_eq_string(String(started[0]), "bentham_ring", "on the winning wedge's map")


## The host can drop a vote; nothing starts, and the signs go back to normal.
func test_the_host_can_cancel_a_vote() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	var wedge: MapWedge = hub.get_node("HubWorld/Wedges/W01_Hell") as MapWedge
	var sign_label: Label3D = wedge.get_node(wedge.label_path) as Label3D
	var vote_label: Label = hub.get_node("HUD/Root/Vote") as Label
	var started: Array[StringName] = []
	lobby.match_starting.connect(func(map_id: StringName) -> void: started.append(map_id))

	_vote_rules(5.0)
	await _stand_on_the_dais(hub)
	assert_true(lobby.open_vote(), "the host opened a vote")
	await step_seconds(1.0)
	assert_true(lobby.cancel_vote(), "and cancelled it")
	assert_false(lobby.is_vote_open(), "the vote is closed")
	assert_eq_string(sign_label.text, "MAP 1", "the sign is the title again")
	assert_false(vote_label.visible, "the readout is down")
	assert_eq_string(lobby.get_prompt(), "Open vote: E", "and the dais offers a fresh vote")
	assert_false(lobby.cancel_vote(), "there is nothing left to cancel")

	await step_seconds(6.0)
	assert_eq_int(started.size(), 0, "a cancelled vote starts nothing")


## Two decided wedges with nobody on either dais tie at zero; the seed picks,
## and the same seed picks the same wedge every time.
func test_a_tie_is_broken_by_the_seed() -> void:
	var hub: Node3D = _make_hub(self, null)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	var hell: MapWedge = hub.get_node("HubWorld/Wedges/W01_Hell") as MapWedge
	var other: MapWedge = hub.get_node("HubWorld/Wedges/W02") as MapWedge
	other.map_scene = hell.map_scene
	other.map_id = hell.map_id
	var wedges: Array[MapWedge] = [hell, other]
	var started: Array[StringName] = []
	lobby.match_starting.connect(func(map_id: StringName) -> void: started.append(map_id))

	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(10)
	var picked: Dictionary[int, int] = {}
	for rng_seed: int in range(1, 41):
		var first: int = lobby.resolve_winner(counts, rng_seed)
		assert_eq_int(lobby.resolve_winner(counts, rng_seed), first, "seed %d always draws the same wedge" % rng_seed)
		assert_true(first == 0 or first == 1, "and it is one of the two decided wedges")
		picked[first] = rng_seed
	assert_eq_int(picked.size(), 2, "different seeds draw different wedges")

	_vote_rules(5.0)
	var rng_seed: int = picked[1]
	assert_true(lobby.open_vote(rng_seed), "the host opened a vote with a known seed")
	assert_eq_int(lobby.get_vote_count(hell), 0, "nobody is on the hell dais")
	assert_eq_int(lobby.get_vote_count(other), 0, "or on the other")
	await step_seconds(5.5)
	assert_true(lobby.was_vote_tied(), "a tie was drawn")
	assert_eq_int(lobby.get_vote_seed(), rng_seed, "with the seed that was given")
	assert_same(lobby.get_vote_winner(), wedges[1], "and the seed's wedge won")
	assert_true(
		(hub.get_node("HUD/Root/Vote") as Label).text.contains("seed %d" % rng_seed),
		"the seed is shown"
	)
	assert_eq_int(started.size(), 1, "and the match started")


# --- Two peers ----------------------------------------------------------------

## The client's body stands on the dais and the host's does not: the host counts
## the body it owns for that seat, the client sees the count, and the client's
## wedge starts for everyone.
func test_a_client_standing_on_the_dais_wins_the_vote() -> void:
	if not await _connect():
		fail("the loopback handshake did not complete")
		return
	_vote_rules(5.0)
	var host_hub: Node3D = _make_hub(_host.get_parent(), _host)
	var client_hub: Node3D = _make_hub(_client.get_parent(), _client)
	await step_ticks(4)
	var host_lobby: HubLobby = host_hub.get_node("HubLobby") as HubLobby
	var client_lobby: HubLobby = client_hub.get_node("HubLobby") as HubLobby
	var host_wedge: MapWedge = host_hub.get_node("HubWorld/Wedges/W01_Hell") as MapWedge
	var client_wedge: MapWedge = client_hub.get_node("HubWorld/Wedges/W01_Hell") as MapWedge
	var host_told: Array[StringName] = []
	var client_told: Array[StringName] = []
	host_lobby.match_starting.connect(func(id: StringName) -> void: host_told.append(id))
	client_lobby.match_starting.connect(func(id: StringName) -> void: client_told.append(id))
	_untangle(host_hub.get_node("MatchController") as MatchController)
	_untangle(client_hub.get_node("MatchController") as MatchController)

	# The client's body as the host owns it, alone on the dais and back on the
	# layer the trigger watches.
	var voter: PlayerController = host_hub.get_node("Runners/Seat1") as PlayerController
	if not assert_not_null(voter, "the host built a body for the client's seat"):
		return
	var trigger: Area3D = host_wedge.get_trigger()
	voter.global_position = trigger.global_position - Vector3(0.0, 2.5, 0.0)
	voter.velocity = Vector3.ZERO
	voter.collision_layer = 1
	await step_ticks(4)

	assert_false(client_lobby.open_vote(), "a client cannot open a vote")
	assert_true(host_lobby.open_vote(11), "the host opened one")
	var seen: bool = await NetFixtures.poll_until(
		self, func() -> bool: return client_lobby.is_vote_open() and client_lobby.get_vote_count(client_wedge) == 1
	)
	assert_true(seen, "the client sees the vote open with its own body counted")
	assert_eq_int(host_lobby.get_vote_count(host_wedge), 1, "the host counts one body: the client's")
	assert_eq_string(client_lobby.get_prompt(), "", "the client is offered nothing to press")
	assert_true((client_hub.get_node("HUD/Root/Vote") as Label).visible, "and sees the readout")
	assert_eq_int(client_lobby.get_vote_seed(), 11, "with the host's seed")

	await step_seconds(5.5)
	var heard: bool = await NetFixtures.poll_until(
		self, func() -> bool: return not client_told.is_empty()
	)
	assert_true(heard, "the client was told the match is starting")
	assert_eq_int(host_told.size(), 1, "and so was the host, once")
	if not client_told.is_empty():
		assert_eq_string(String(client_told[0]), "bentham_ring", "on the wedge the client stood on")
	assert_same(host_lobby.get_vote_winner(), host_wedge, "the host's winner is that wedge")
	assert_same(client_lobby.get_vote_winner(), client_wedge, "and so is the client's")
	assert_eq_int(int(_host.lobby.get_phase()), int(NetLobby.Phase.LAUNCHING), "the roster is frozen")


## Host and client stand in the same hub, one body each, and the client sees the
## host's body move.
func test_two_peers_stand_in_one_hub_and_see_each_other() -> void:
	if not await _connect():
		fail("the loopback handshake did not complete")
		return
	var host_hub: Node3D = _make_hub(_host.get_parent(), _host)
	var client_hub: Node3D = _make_hub(_client.get_parent(), _client)
	await step_ticks(4)

	var host_controller: MatchController = host_hub.get_node("MatchController") as MatchController
	var client_controller: MatchController = client_hub.get_node("MatchController") as MatchController
	assert_eq_int(host_controller.get_participants().size(), 2, "the host sees two people")
	assert_eq_int(client_controller.get_participants().size(), 2, "and so does the client")
	assert_true(client_controller.is_mirror(), "the client simulates nothing it was not given")
	assert_eq_int(
		(host_hub.get_node("HubLobby") as HubLobby).get_player_count(), 2,
		"the hub's own count agrees"
	)
	assert_null(
		host_hub.get_node_or_null("Runners/Seat0"),
		"the host's own body is the scene's, not a spawned one"
	)

	# One physics world holds four bodies here, two of them copies of the other
	# two standing in the same spot. Off every layer, exactly as NetFixtures
	# does it, or the depenetration solver decides this test.
	_untangle(host_controller)
	_untangle(client_controller)

	var host_body: PlayerController = host_hub.get_node("Player") as PlayerController
	var mirror: PlayerController = client_hub.get_node("Runners/Seat0") as PlayerController
	if not assert_not_null(mirror, "the client built a body for the host's seat"):
		return
	var opened: Vector3 = host_body.global_position
	mirror.global_position = PARKED_POSITION

	_drive(host_body, Vector2(0.0, 1.0))
	await step_ticks(REPLICATION_TICKS)

	assert_gt(
		opened.distance_to(host_body.global_position), 1.0, "the host's body moved"
	)
	assert_le(
		mirror.global_position.distance_to(host_body.global_position), CONVERGENCE_METRES,
		"and the client's copy of it followed, from where the test parked it"
	)


## The host quitting is the end of the session, and a client is told so.
##
## There is no host migration -- promoting a client would hand it a world it
## never simulated -- so the only right answer is to say the match is over.
## Before this, a client kept running a match scene full of frozen bodies with
## nothing deciding anything and no way to find out.
func test_a_client_is_told_when_the_host_goes_away() -> void:
	if not await _connect():
		fail("the loopback handshake did not complete")
		return
	var _host_hub: Node3D = _make_hub(_host.get_parent(), _host)
	var client_hub: Node3D = _make_hub(_client.get_parent(), _client)
	await step_ticks(4)

	var client_match: NetMatch = client_hub.get_node("NetMatch") as NetMatch
	if not assert_not_null(client_match, "the client's hub has a NetMatch"):
		return
	var lost: Array[bool] = [false]
	client_match.host_lost.connect(func() -> void: lost[0] = true)

	_host.leave()
	await NetFixtures.poll_until(self, func() -> bool: return lost[0])
	assert_true(lost[0], "the client heard that the host had gone")


## The host presses interact on the dais and every machine is told to go, with
## the same map. The seat table is frozen and the people in it are still in it.
func test_the_host_starts_the_map_for_everyone() -> void:
	if not await _connect():
		fail("the loopback handshake did not complete")
		return
	var host_hub: Node3D = _make_hub(_host.get_parent(), _host)
	var client_hub: Node3D = _make_hub(_client.get_parent(), _client)
	await step_ticks(4)

	var host_lobby: HubLobby = host_hub.get_node("HubLobby") as HubLobby
	var client_lobby: HubLobby = client_hub.get_node("HubLobby") as HubLobby
	var host_told: Array[StringName] = []
	var client_told: Array[StringName] = []
	host_lobby.match_starting.connect(func(id: StringName) -> void: host_told.append(id))
	client_lobby.match_starting.connect(func(id: StringName) -> void: client_told.append(id))

	assert_false(client_lobby.is_host(), "a client may not start anything")
	assert_false(client_lobby.start_map(), "and pressing it does nothing")
	assert_eq_int(client_told.size(), 0, "nobody was told")

	assert_true(host_lobby.start_map(), "the host launched")
	var heard: bool = await NetFixtures.poll_until(
		self, func() -> bool: return not client_told.is_empty()
	)
	assert_true(heard, "the client was told the match is starting")
	assert_eq_int(host_told.size(), 1, "and so was the host, once")
	if not client_told.is_empty():
		assert_eq_string(String(client_told[0]), "bentham_ring", "on the host's map")
	assert_true(HubLobby.returns_to_hub, "and the match knows to come back")

	# Seats, not bodies: the match layer builds one body per seat on every
	# machine, and this is the table it builds them from.
	var host_seats: NetLobby = _host.lobby
	assert_eq_int(
		int(host_seats.get_phase()), int(NetLobby.Phase.LAUNCHING), "the roster is frozen"
	)
	assert_ge(float(host_seats.get_occupant_count()), 2.0, "with both people still seated")
	assert_eq_int(host_seats.get_local_seat_index(), 0, "the host is seat 0")
	assert_eq_int(_client.lobby.get_local_seat_index(), 1, "and the client has a seat of its own")

	# And the way back: the match ends, the lobby is told, and the hub the
	# players walk into puts the table back to gathering for the next start.
	host_seats.conclude_match(0)
	var back: Node3D = _make_hub(_host.get_parent(), _host)
	assert_eq_int(
		int(host_seats.get_phase()), int(NetLobby.Phase.GATHERING),
		"the hub they come back to reopens the lobby"
	)
	assert_true(
		(back.get_node("HubLobby") as HubLobby).is_host(), "and the host can start again"
	)


# --- Fixtures -----------------------------------------------------------------

## Switch the host's settings to a vote of [param seconds].
func _vote_rules(seconds: float) -> void:
	var settings: GameSettings = SettingsStore.instance().settings
	settings.map_pick_mode = int(MatchRules.MapPickMode.VOTE)
	settings.vote_seconds = seconds

## Two peers on two sockets, connected. Returns false rather than hanging.
func _connect() -> bool:
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	_host.lobby.open("Host")
	return await NetFixtures.poll_until(
		self, func() -> bool: return _client.lobby.get_local_seat() != null
	)


## The shipped hub, pointed at [param session] and told not to change scene.
##
## Named [code]Hub[/code] on every peer on purpose: a body's node path has to
## match across machines, and the links under [code]Hub/NetMatch[/code] are
## addressed by path.
func _make_hub(parent: Node, session: NetSession) -> Node3D:
	var hub: Node3D = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	hub.name = "Hub"
	TestFixtures.silence_human_input(hub)

	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	lobby.changes_scene = false
	if session != null:
		lobby.session_path = session.get_path()
		(hub.get_node("NetMatch") as NetMatch).session_path = session.get_path()

	# The local body is driven by a bot source, so a test can push it without a
	# keyboard. Set before the hub enters the tree: NetMatch reads the body's
	# intent source when it builds the link.
	var body: PlayerController = hub.get_node("Player") as PlayerController
	var input: BotIntentSource = BotIntentSource.new()
	input.name = "BotInput"
	input.shove_enabled = false
	body.add_child(input)
	body.intent_source = input

	# One world per process. Two WorldEnvironments and two audio directors in
	# one tree are an engine complaint and nothing any test here reads.
	var environment: Node = hub.get_node_or_null("HubWorld/WorldEnvironment")
	if environment != null:
		environment.free()
	var audio: Node = hub.get_node_or_null("GameAudio")
	if audio != null:
		audio.free()

	parent.add_child(hub)
	return hub


## Put the local body on the start trigger and wait for the hub to notice.
##
## Bounded, and it waits on IDLE frames as well as physics ones. [HubLobby] reads
## the area from [method Node._process], the runner compresses simulated time
## fiftyfold so several physics ticks can pass between two idle frames, and
## [signal SceneTree.process_frame] fires immediately BEFORE the frame's
## [method Node._process] calls -- so a fixed "step, then one process frame" is
## a coin toss rather than a wait.
func _stand_on_the_dais(hub: Node3D) -> void:
	var trigger: Area3D = hub.get_node(
		"HubWorld/Wedges/W01_Hell/Dais/StartTrigger"
	) as Area3D
	var body: PlayerController = hub.get_node("Player") as PlayerController
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	body.global_position = trigger.global_position - Vector3(0.0, 2.5, 0.0)
	body.velocity = Vector3.ZERO
	await step_ticks(4)
	for _attempt: int in 60:
		if lobby.is_on_the_dais():
			return
		await get_tree().process_frame


## Take every body in [param controller] off every collision LAYER, leaving its
## mask alone so it still stands on the hub floor.
##
## Two peers share one physics world in this process, so the host's body and the
## client's copy of it stand inside each other; off every layer, they pass
## through one another instead of being thrown apart by the depenetration
## solver. [method NetFixtures.add_seat_body] clears both and lets its bodies
## fall, which is fine for a body nobody measures -- here the fall is what the
## measurement is against, and a body accelerating downward is legitimately
## metres behind its own snapshot.
func _untangle(controller: MatchController) -> void:
	for participant: MatchParticipant in controller.get_participants():
		participant.home_collision_layer = 0
		if participant.body != null:
			participant.body.collision_layer = 0


## Hold a direction on a body driven by a [BotIntentSource].
func _drive(body: PlayerController, direction: Vector2) -> void:
	var input: BotIntentSource = body.intent_source as BotIntentSource
	if input != null:
		input.command.move_direction = direction
