extends TestCase
## Playtest regressions at the end of a match and around it, on real sockets with 2 and 4 machines:
## a client's Play Again, Rematch, Everyone to the Hub, the host's seat relaunch, the loading cover,
## a client guard's optic and the debug Skip Phase.

const Rig = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
## Ticks for a reliable event and the snapshots behind it to cross loopback.
const CROSS_TICKS: int = 30

var _rig: Rig = null
var _relaunch_seats: Variant = null
var _relaunch: bool = false


func before_each() -> void:
	_rig = Rig.new()
	_relaunch = HubLobby.relaunch_on_arrival
	_relaunch_seats = HubLobby.relaunch_bot_seats


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null
	HubLobby.relaunch_on_arrival = _relaunch
	HubLobby.relaunch_bot_seats = _relaunch_seats
	MouseFocus.set_play_wants(false)


# --- Fixtures -----------------------------------------------------------------

## [param clients] joined, [param seats] filled, the round (or the race, guard -1) running everywhere.
func _start(clients: int, seats: int, guard_seat: int = 0, map: StringName = &"") -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 3
	if map != &"":
		_rig.settings().map_id = map
	if not await _rig.launch(seats, guard_seat):
		fail("the match never started on every peer")
		return false
	return await _everyone_plays(guard_seat >= 0)


## Every peer's match is in the round (or the opening race).
func _everyone_plays(in_round: bool) -> bool:
	var wanted: MatchController.Phase = MatchController.Phase.ROUND if in_round else MatchController.Phase.RACE
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == wanted):
			fail("peer %d never reached %s (in %s)" % [peer, MatchController.Phase.keys()[wanted], controller.get_phase_name()])
			return false
	await step_ticks(CROSS_TICKS)
	return true


func _result(peer: int) -> MatchResultScreen:
	return _rig.matches[peer].get_node("ResultScreen") as MatchResultScreen


func _button(peer: int, unique: String) -> Button:
	return _result(peer).get_node("%" + unique) as Button


## The host ends the match; true once every peer shows the result.
func _end_match() -> bool:
	var host: MatchController = _rig.controller(HOST)
	host._win_match(host.get_participants()[0])
	var shown: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.controller(peer).is_match_over() or not _result(peer).is_showing():
				return false
		return true)
	if not shown:
		for peer: int in _rig.peer_count():
			assert_true(_rig.controller(peer).is_match_over(), "peer %d knows the match is over" % peer)
			assert_true(_result(peer).is_showing(), "peer %d shows the result" % peer)
	await step_ticks(CROSS_TICKS)
	return shown


## A button a player could press now: drawn, enabled and focusable. (The rig's window is 64 px; fit is test_regress_ui_layout's.)
func _assert_pressable(button: Button, what: String) -> void:
	assert_true(button.is_visible_in_tree(), "%s is drawn" % what)
	assert_false(button.disabled, "%s is enabled" % what)
	assert_true(button.focus_mode != Control.FOCUS_NONE, "%s takes focus" % what)


func _phases() -> Array[int]:
	var phases: Array[int] = []
	for session: NetSession in _rig.sessions:
		phases.append(int(session.lobby.get_phase()))
	return phases


## True once every machine's lobby is in [param phase] at the host's epoch.
func _lobbies_reach(phase: NetLobby.Phase) -> bool:
	var host: NetLobby = _rig.sessions[HOST].lobby
	return await _rig.wait_for(func() -> bool:
		for session: NetSession in _rig.sessions:
			if session.lobby.get_phase() != phase or session.lobby.get_epoch() != host.get_epoch():
				return false
		return true)


## Every machine's match agrees with the host's on who is seated where and the state of play.
func _assert_one_match(why: String) -> void:
	var host: MatchController = _rig.controller(HOST)
	var seat: MatchParticipant = host.get_seat_participant()
	var locals: Dictionary[int, bool] = {}
	for peer: int in _rig.peer_count():
		var mine: MatchController = _rig.controller(peer)
		assert_eq_int(mine.get_participants().size(), host.get_participants().size(), "peer %d roster size %s" % [peer, why])
		assert_eq_int(int(mine.get_phase()), int(host.get_phase()), "peer %d phase %s" % [peer, why])
		assert_eq_int(mine.get_round_number(), host.get_round_number(), "peer %d round number %s" % [peer, why])
		var theirs: MatchParticipant = mine.get_seat_participant()
		assert_eq_int(theirs.index if theirs != null else -1, seat.index if seat != null else -1, "peer %d tower seat %s" % [peer, why])
		var slot: int = _rig.local_slot(peer)
		assert_true(slot >= 0, "peer %d has a body of its own %s" % [peer, why])
		assert_false(locals.has(slot), "peer %d's body is nobody else's %s" % [peer, why])
		locals[slot] = true
		if slot >= 0 and slot < host.get_participants().size():
			assert_true(host.get_participants()[slot].is_human(), "the host holds peer %d's slot as a person %s" % [peer, why])
		for index: int in mine.get_participants().size():
			assert_not_null(mine.get_participants()[index].body, "peer %d has a body for slot %d %s" % [peer, index, why])


# --- PT1-06: a client's Play Again -------------------------------------------

func _a_clients_play_again_restarts_nothing(clients: int) -> void:
	if not await _start(clients, clients + 2):
		return
	if not await _end_match():
		return
	var host: MatchController = _rig.controller(HOST)
	var winner: int = host.get_match_winner().index
	var round_number: int = host.get_round_number()
	for presser: int in range(1, _rig.peer_count()):
		_button(presser, "PlayAgainButton").pressed.emit()
		await step_ticks(CROSS_TICKS)
		for peer: int in _rig.peer_count():
			var mine: MatchController = _rig.controller(peer)
			var tag: String = "after client %d pressed Play Again, peer %d" % [presser, peer]
			assert_true(mine.is_match_over(), "%s still holds a finished match" % tag)
			assert_not_null(mine.get_match_winner(), "%s still has a winner" % tag)
			if mine.get_match_winner() != null:
				assert_eq_int(mine.get_match_winner().index, winner, "%s names the host's winner" % tag)
			assert_eq_int(mine.get_round_number(), round_number, "%s is on the host's round" % tag)
			assert_eq_int(mine.get_participants().size(), host.get_participants().size(), "%s keeps the roster" % tag)
		assert_eq_int(int(_rig.sessions[HOST].lobby.get_phase()), int(NetLobby.Phase.POST_MATCH), "the host's lobby is still after the match")
	assert_true(_result(HOST).is_showing(), "and the host's result is still up")


func test_a_clients_play_again_restarts_nothing_with_two() -> void:
	await _a_clients_play_again_restarts_nothing(1)


func test_a_clients_play_again_restarts_nothing_with_four() -> void:
	await _a_clients_play_again_restarts_nothing(3)


# --- PT3-07: Rematch and Everyone to the Hub ----------------------------------

func _result_buttons_are_there_for_everyone(clients: int) -> void:
	if not await _start(clients, clients + 1):
		return
	if not await _end_match():
		return
	for peer: int in _rig.peer_count():
		_assert_pressable(_button(peer, "RematchButton"), "peer %d's Rematch" % peer)
		_assert_pressable(_button(peer, "MainMenuButton"), "peer %d's Main Menu" % peer)
		var hub_all: Button = _button(peer, "HubAllButton")
		if peer == HOST:
			_assert_pressable(hub_all, "the host's Everyone to the Hub")
		else:
			assert_false(hub_all.is_visible_in_tree(), "client %d is not offered Everyone to the Hub" % peer)


func test_the_result_offers_rematch_to_everyone_and_the_hub_to_the_host_with_two() -> void:
	await _result_buttons_are_there_for_everyone(1)


func test_the_result_offers_rematch_to_everyone_and_the_hub_to_the_host_with_four() -> void:
	await _result_buttons_are_there_for_everyone(3)


func _rematch_restarts_for_everyone(clients: int, matches: int) -> void:
	if not await _start(clients, clients + 2):
		return
	MouseFocus.set_play_wants(true)
	for played: int in matches:
		var tag: String = "(rematch %d)" % (played + 1)
		# Each rematch is a fresh match scene, with a fresh result screen.
		for peer: int in _rig.peer_count():
			_result(peer).headless_inert = false
		var epoch: int = _rig.sessions[HOST].lobby.get_epoch()
		if not await _end_match():
			return
		assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_VISIBLE, "the result shows the cursor %s" % tag)
		# Everyone but the last presses: the match must wait for the last.
		var last: int = (played % _rig.peer_count())
		for peer: int in _rig.peer_count():
			if peer != last:
				_button(peer, "RematchButton").pressed.emit()
		await step_ticks(CROSS_TICKS)
		for peer: int in _rig.peer_count():
			assert_true(_rig.controller(peer).is_match_over(), "peer %d waits for the last vote %s" % [peer, tag])
			assert_true(_result(peer).is_showing(), "peer %d still shows the result while it waits %s" % [peer, tag])
			if _rig.peer_count() > 1 and (_rig.peer_count() > 2 or peer != last):
				assert_true((_result(peer).get_node("%RematchVotes") as Label).visible, "peer %d is shown who asked %s" % [peer, tag])
		_assert_pressable(_button(last, "RematchButton"), "the last voter's Rematch %s" % tag)
		_button(last, "RematchButton").pressed.emit()
		var restarted: bool = await _rig.wait_rematch(epoch)
		assert_true(restarted, "every peer left the result for the rematch %s" % tag)
		if not restarted:
			return
		if not await _everyone_plays(true):
			return
		assert_true(await _lobbies_reach(NetLobby.Phase.IN_MATCH), "every lobby is back in the match %s: %s" % [tag, _phases()])
		_assert_one_match("after the rematch %s" % tag)
		assert_eq_int(_rig.controller(HOST).get_round_number(), 1, "the rematch starts at round one %s" % tag)
		assert_false(MouseFocus.is_held(), "no result screen still holds the cursor %s" % tag)
		assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_CAPTURED, "the rematch hands the mouse back to play %s" % tag)
		for peer: int in _rig.peer_count():
			assert_false(_button(peer, "RematchButton").disabled, "peer %d can ask again next time %s" % [peer, tag])


func test_a_rematch_restarts_every_machine_and_hands_the_cursor_back_with_two() -> void:
	await _rematch_restarts_for_everyone(1, 5)


func test_a_rematch_restarts_every_machine_and_hands_the_cursor_back_with_three() -> void:
	await _rematch_restarts_for_everyone(2, 3)


func test_a_rematch_restarts_every_machine_and_hands_the_cursor_back_with_four() -> void:
	await _rematch_restarts_for_everyone(3, 5)


## One human never presses: the rest wait, nobody is stranded, and the host's hub button gets all out.
func _a_holdout_strands_nobody(clients: int) -> void:
	if not await _start(clients, clients + 1):
		return
	if not await _end_match():
		return
	var holdout: int = _rig.peer_count() - 1
	for peer: int in holdout:
		_button(peer, "RematchButton").pressed.emit()
	await step_ticks(CROSS_TICKS * 4)
	for peer: int in _rig.peer_count():
		assert_true(_rig.controller(peer).is_match_over(), "peer %d waits on the holdout" % peer)
		assert_true(_result(peer).is_showing(), "peer %d still has its result screen" % peer)
		_assert_pressable(_button(peer, "MainMenuButton"), "peer %d's way out" % peer)
	_assert_pressable(_button(holdout, "RematchButton"), "the holdout's Rematch")
	_assert_pressable(_button(HOST, "HubAllButton"), "the host's Everyone to the Hub")
	_button(HOST, "HubAllButton").pressed.emit()
	assert_true(await _lobbies_reach(NetLobby.Phase.GATHERING), "every lobby goes back to gathering at one epoch: %s" % [_phases()])
	assert_false(_result(HOST).is_showing(), "the host's result came down")


func test_a_rematch_holdout_strands_nobody_with_two() -> void:
	await _a_holdout_strands_nobody(1)


func test_a_rematch_holdout_strands_nobody_with_three() -> void:
	await _a_holdout_strands_nobody(2)


func test_a_rematch_holdout_strands_nobody_with_four() -> void:
	await _a_holdout_strands_nobody(3)


## The holdout leaves instead: everyone still here has asked, so the rematch goes ahead.
func test_a_rematch_goes_ahead_when_the_holdout_leaves() -> void:
	if not await _start(3, 5):
		return
	if not await _end_match():
		return
	var holdout: int = _rig.peer_count() - 1
	for peer: int in holdout:
		_button(peer, "RematchButton").pressed.emit()
	await step_ticks(CROSS_TICKS)
	assert_true(_rig.controller(HOST).is_match_over(), "the match waits on the holdout")
	var epoch: int = _rig.sessions[HOST].lobby.get_epoch()
	_rig.sessions[holdout].leave()
	var restarted: bool = await _rig.wait_rematch(epoch)
	assert_true(restarted, "the rematch starts for those who asked once the holdout is gone")
	if not restarted:
		return
	assert_true(_rig.sessions[HOST].lobby.get_phase() == NetLobby.Phase.IN_MATCH, "and the lobby is back in the match")
	assert_false(_rig.controller(HOST).get_participants()[holdout].is_human(), "with a bot in the seat that left")


# --- PT3-07 / PT2-10 / PT3-09: to the hub together, and the host's seat relaunch --

## Take down every machine's scene, as a scene change does.
func _free_scenes() -> void:
	for peer: int in _rig.peer_count():
		var scene: Node = _rig.matches[peer]
		if scene != null:
			var world: Node = scene.get_parent()
			world.get_parent().remove_child(world)
			world.free()
		_rig.matches[peer] = null


## The match scene on every machine after a hub launch, as SessionFlow loads it.
func _bind_matches() -> bool:
	for peer: int in _rig.peer_count():
		_rig.matches[peer] = _rig._bind(_rig.sessions[peer])
	return await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.net_match(peer).has_started():
				return false
		return _rig.sessions[HOST].lobby.get_phase() == NetLobby.Phase.IN_MATCH)


## The host relaunches with [param bots] seats as bots and [param tower] (seat, or -1 for the race).
func _relaunch_with(bots: Variant, tower: int) -> bool:
	var settings: GameSettings = _rig.settings()
	settings.skip_opening_race = tower >= 0
	settings.tower_seat_index = maxi(tower, 0)
	HubLobby.relaunch_bot_seats = bots
	HubLobby.relaunch_on_arrival = true
	_rig.sessions[HOST].flow.everyone_to_hub()
	if not await _lobbies_reach(NetLobby.Phase.GATHERING):
		fail("not every lobby went back to gathering: %s" % [_phases()])
		return false
	_free_scenes()
	_rig.bind_hubs()
	if not await _lobbies_reach(NetLobby.Phase.IN_MATCH):
		fail("the hub did not relaunch the map for everyone: %s" % [_phases()])
		return false
	assert_false(HubLobby.relaunch_on_arrival, "the relaunch is spent")
	_free_scenes()
	if not await _bind_matches():
		fail("the relaunched match never started on every peer")
		return false
	return await _everyone_plays(tower >= 0)


## Seats as every machine's lobby holds them: humans keep theirs, [param bots] are bots, the rest empty.
func _assert_seats(humans: int, bots: PackedInt32Array, tower: int, why: String) -> void:
	var host: NetLobby = _rig.sessions[HOST].lobby
	for peer: int in _rig.peer_count():
		var lobby: NetLobby = _rig.sessions[peer].lobby
		assert_eq_int(lobby.get_occupant_count(), humans + bots.size(), "peer %d seat count %s" % [peer, why])
		for seat: LobbySeat in lobby.seats:
			var tag: String = "peer %d seat %d %s" % [peer, seat.index, why]
			if seat.index < humans:
				assert_true(seat.is_human(), "%s is a person" % tag)
				assert_eq_int(seat.peer_id, host.get_seat(seat.index).peer_id, "%s is the machine the host says" % tag)
			elif bots.has(seat.index):
				assert_true(seat.is_bot(), "%s is a bot" % tag)
			else:
				assert_false(seat.is_occupied(), "%s is empty" % tag)
		assert_eq_int(lobby.get_local_seat_index(), peer, "peer %d kept its own seat %s" % [peer, why])
		var guard: LobbySeat = lobby.get_guard_seat()
		assert_eq_int(guard.index if guard != null else -1, tower, "peer %d opening tower seat %s" % [peer, why])
		assert_eq_int(_rig.controller(peer).get_participants().size(), humans + bots.size(), "peer %d bodies %s" % [peer, why])
	_assert_one_match(why)
	if tower >= 0:
		for peer: int in _rig.peer_count():
			var seated: MatchParticipant = _rig.controller(peer).get_seat_participant()
			assert_not_null(seated, "peer %d has somebody in the tower %s" % [peer, why])
			if seated != null and tower < humans:
				assert_true(seated.is_human(), "peer %d: the tower holder is the person asked for %s" % [peer, why])
				assert_eq_int(seated.index, _rig.local_slot(tower), "peer %d: the tower holder is seat %d's body %s" % [peer, tower, why])


func _the_host_relaunches_with_the_seats_it_set(clients: int, map: StringName) -> void:
	var humans: int = clients + 1
	if not await _start(clients, humans + 2, 0, map):
		return
	# Fewer bots, and a client opens in the tower.
	var one_bot: PackedInt32Array = PackedInt32Array([humans + 1])
	if not await _relaunch_with(one_bot, 1):
		return
	_assert_seats(humans, one_bot, 1, "after dropping to one bot (%s)" % map)
	assert_eq_string(String(_rig.sessions[humans - 1].lobby.get_rules().map_id), String(_rig.settings().map_id), "on the same map")
	# More bots, a different seat pattern, and the opening race.
	var three_bots: PackedInt32Array = PackedInt32Array([humans, humans + 1, humans + 3])
	if not await _relaunch_with(three_bots, -1):
		return
	_assert_seats(humans, three_bots, -1, "after raising to three bots (%s)" % map)
	# No bots at all, the host in the tower.
	if not await _relaunch_with(PackedInt32Array(), 0):
		return
	_assert_seats(humans, PackedInt32Array(), 0, "after emptying every bot seat (%s)" % map)


func test_the_hosts_seat_relaunch_reaches_every_machine_with_two_on_hell() -> void:
	await _the_host_relaunches_with_the_seats_it_set(1, &"bentham_ring")


func test_the_hosts_seat_relaunch_reaches_every_machine_with_four_on_hell() -> void:
	await _the_host_relaunches_with_the_seats_it_set(3, &"bentham_ring")


func test_the_hosts_seat_relaunch_reaches_every_machine_with_two_on_marble() -> void:
	await _the_host_relaunches_with_the_seats_it_set(1, &"marble")


func test_the_hosts_seat_relaunch_reaches_every_machine_with_four_on_marble() -> void:
	await _the_host_relaunches_with_the_seats_it_set(3, &"marble")


## The debug menu's bot count alone (no seat list): surplus bot seats are emptied, missing ones filled.
func _the_host_relaunches_with_a_bot_count(clients: int) -> void:
	var humans: int = clients + 1
	if not await _start(clients, humans + 3):
		return
	DebugMenu.write_bot_count(_rig.settings(), humans)
	if not await _relaunch_with(null, 0):
		return
	_assert_seats(humans, PackedInt32Array([humans]), 0, "after the count dropped to one bot")
	DebugMenu.write_bot_count(_rig.settings(), humans + 1)
	if not await _relaunch_with(null, 0):
		return
	_assert_seats(humans, PackedInt32Array([humans, humans + 1]), 0, "after the count rose to two bots")


func test_the_hosts_bot_count_relaunch_reaches_every_machine_with_two() -> void:
	await _the_host_relaunches_with_a_bot_count(1)


func test_the_hosts_bot_count_relaunch_reaches_every_machine_with_four() -> void:
	await _the_host_relaunches_with_a_bot_count(3)


# --- PT3-08: the loading cover -------------------------------------------------

func _cover_of(scene: Node) -> LoadingCover:
	for child: Node in scene.get_node("NetMatch").get_children():
		if child is LoadingCover:
			return child as LoadingCover
	return null


func _the_cover_holds_until_the_match_is_bound(clients: int) -> void:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return
	var late: int = clients
	var held_back: Array[int] = [late]
	if not await _rig.launch(clients + 2, 0, held_back):
		fail("the match never started for those on time")
		return
	# The late machine's scene the frame it stands, before anything of the match has reached it.
	_rig.matches[late] = _rig._bind(_rig.sessions[late])
	var scene: Node = _rig.matches[late]
	var cover: LoadingCover = _cover_of(scene)
	assert_not_null(cover, "a scene that is still binding is covered")
	if cover == null:
		return
	assert_true(cover.is_covering(), "the cover is up")
	assert_eq_int(int(cover.get("_released_ms")), -1, "and is not counting down before the body is placed")
	assert_true(scene.get_viewport().disable_3d, "and the world is not drawn under it")
	if not await _rig.wait_for(func() -> bool: return _rig.net_match(late).has_started()):
		fail("the late machine never bound")
		return
	for peer: int in _rig.peer_count():
		var world: Viewport = _rig.matches[peer].get_viewport()
		var lifted: bool = await _rig.wait_for(func() -> bool:
			return not world.disable_3d and _cover_of(_rig.matches[peer]) == null, LoadingCover.MAX_HOLD_MS + 2000)
		assert_true(lifted, "peer %d: the world is drawn and the cover is gone once it is in the match" % peer)


func test_the_loading_cover_holds_until_bound_then_lifts_with_two() -> void:
	await _the_cover_holds_until_the_match_is_bound(1)


func test_the_loading_cover_holds_until_bound_then_lifts_with_four() -> void:
	await _the_cover_holds_until_the_match_is_bound(3)


# --- PT1-08: a client guard's optic -------------------------------------------

func _vignette(peer: int) -> ScopeVignette:
	return _rig.controller(peer).rifle.get_node("ScopeVignette") as ScopeVignette


func _a_client_guard_has_the_optic(clients: int, map: StringName) -> void:
	# Seat 1 is the first client: it opens in the tower.
	if not await _start(clients, clients + 2, 1, map):
		return
	for peer: int in _rig.peer_count():
		var seated: MatchParticipant = _rig.controller(peer).get_seat_participant()
		assert_eq_int(seated.index if seated != null else -1, _rig.local_slot(1), "peer %d: the first client holds the tower" % peer)
		var holds: bool = bool(_vignette(peer).call("_holder_is_the_human"))
		if peer == 1:
			assert_true(holds, "the client guard's own screen draws its optic (%s)" % map)
			var trigger: WeaponInput = _vignette(peer).trigger
			assert_true(trigger != null and not trigger.is_active(), "though its trigger is the host's to pull")
		else:
			assert_false(holds, "peer %d does not draw somebody else's optic (%s)" % [peer, map])
	# The seat moves to the host: the client's optic goes with it.
	var host: MatchController = _rig.controller(HOST)
	host.take_seat(host.get_participants()[_rig.local_slot(HOST)])
	host.start_round()
	var moved: bool = await _rig.wait_for(func() -> bool:
		var seated: MatchParticipant = _rig.controller(1).get_seat_participant()
		return seated != null and seated.index == _rig.local_slot(HOST))
	assert_true(moved, "the client heard the seat change")
	await step_ticks(CROSS_TICKS)
	assert_false(bool(_vignette(1).call("_holder_is_the_human")), "a client that lost the tower lost the optic")
	assert_true(bool(_vignette(HOST).call("_holder_is_the_human")), "and the host that took it has it")


func test_a_client_guard_draws_its_own_optic_with_two_on_hell() -> void:
	await _a_client_guard_has_the_optic(1, &"bentham_ring")


func test_a_client_guard_draws_its_own_optic_with_four_on_marble() -> void:
	await _a_client_guard_has_the_optic(3, &"marble")


# --- S-09: the debug Skip Phase, from the host of a networked match ---------------

func _every_peer_seats(slot: int, why: String) -> void:
	var agreed: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			var seated: MatchParticipant = _rig.controller(peer).get_seat_participant()
			if seated == null or seated.index != slot or _rig.controller(peer).get_phase() != MatchController.Phase.ROUND:
				return false
			if _rig.controller(peer).get_round_number() != _rig.controller(HOST).get_round_number():
				return false
		return true)
	if not agreed:
		for peer: int in _rig.peer_count():
			var seated: MatchParticipant = _rig.controller(peer).get_seat_participant()
			assert_eq_int(seated.index if seated != null else -1, slot, "peer %d tower seat %s" % [peer, why])
			assert_eq_int(_rig.controller(peer).get_round_number(), _rig.controller(HOST).get_round_number(), "peer %d round %s" % [peer, why])
	else:
		assert_true(agreed, "every peer seats slot %d %s" % [slot, why])
	await step_ticks(CROSS_TICKS)


func _the_hosts_skip_phase_seats_its_tower_choice(clients: int) -> void:
	if not await _start(clients, clients + 2, -1):
		return
	var host: MatchController = _rig.controller(HOST)
	var mine: int = _rig.local_slot(HOST)
	# A client's menu decides nothing.
	_rig.controller(1).debug_skip_phase(GameSettings.DEBUG_TOWER_ME)
	await step_ticks(CROSS_TICKS)
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_rig.controller(peer).get_phase()), int(MatchController.Phase.RACE), "peer %d is still in the race after a client's skip" % peer)
	# Bot: the race ends with somebody else in the tower and the host still running.
	host.debug_skip_phase(GameSettings.DEBUG_TOWER_BOT)
	var first: MatchParticipant = host.get_seat_participant()
	assert_true(first != null and first.index != mine, "Bot: skipping the race does not seat the host")
	await _every_peer_seats(first.index, "after Bot off the race")
	assert_true(host.get_participants()[mine].is_running, "the host is still a runner")
	# Me: the round ends with the host in the tower.
	host.debug_skip_phase(GameSettings.DEBUG_TOWER_ME)
	await _every_peer_seats(mine, "after Me off the round")
	# A named seat: the last client.
	var named: int = _rig.local_slot(clients)
	host.debug_skip_phase(named)
	await _every_peer_seats(named, "after naming the last client")
	# Bot again: on from there, never the host.
	host.debug_skip_phase(GameSettings.DEBUG_TOWER_BOT)
	var after: MatchParticipant = host.get_seat_participant()
	assert_true(after != null and after.index != mine and after.index != named, "Bot: the seat moves on and skips the host")
	await _every_peer_seats(after.index, "after Bot off the round")
	_assert_one_match("after four skips")


func test_the_hosts_skip_phase_seats_its_tower_choice_on_every_machine_with_two() -> void:
	await _the_hosts_skip_phase_seats_its_tower_choice(1)


func test_the_hosts_skip_phase_seats_its_tower_choice_on_every_machine_with_four() -> void:
	await _the_hosts_skip_phase_seats_its_tower_choice(3)


# --- PT1-06 as shipped: a client presses Back to Hub before the host does ---------

## The shipped hub for one machine, as its own scene change would load it.
func _bind_hub(peer: int) -> Node3D:
	var world: SubViewport = SubViewport.new()
	world.name = "World"
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	_rig.sessions[peer].get_parent().add_child(world)
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	hub.name = "Hub"
	TestFixtures.silence_human_input(hub)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	lobby.changes_scene = false
	lobby.session_path = _rig.sessions[peer].get_path()
	(hub.get_node("NetMatch") as NetMatch).session_path = _rig.sessions[peer].get_path()
	_rig._give_test_input(hub.get_node("Player") as PlayerController)
	var audio: Node = hub.get_node_or_null("GameAudio")
	if audio != null:
		audio.free()
	world.add_child(hub)
	_rig.matches[peer] = hub
	return hub


func _free_scene(peer: int) -> void:
	var world: Node = _rig.matches[peer].get_parent()
	world.get_parent().remove_child(world)
	world.free()
	_rig.matches[peer] = null


## Everyone to the hub: the clients' hubs stand before the host's, and are let in once it stands.
func _a_client_back_in_the_hub_first_waits_quietly_and_is_let_in(clients: int) -> void:
	if not await _start(clients, clients + 2):
		return
	if not await _end_match():
		return
	_rig.sessions[HOST].flow.everyone_to_hub()
	assert_true(await _lobbies_reach(NetLobby.Phase.GATHERING), "every lobby is gathering again: %s" % [_phases()])
	# Every client is in the hub; the host is still taking its match down.
	var held: Dictionary[int, Vector3] = {}
	for peer: int in range(1, _rig.peer_count()):
		var old: PlayerNetLink = _rig.net_match(HOST).call(
			"_link_for_seat", _rig.sessions[peer].lobby.get_local_seat_index()) as PlayerNetLink
		if old != null:
			held[peer] = old.controller.global_position
		_free_scene(peer)
		_bind_hub(peer)
		_rig.drive(peer, Vector2(0.0, 1.0))
	await step_ticks(CROSS_TICKS * 2)
	assert_eq_int(held.size(), clients, "the host's old match has every client's body")
	for peer: int in held:
		var old: PlayerNetLink = _rig.net_match(HOST).call(
			"_link_for_seat", _rig.sessions[peer].lobby.get_local_seat_index()) as PlayerNetLink
		assert_lt(old.controller.global_position.distance_to(held[peer]), 0.05,
			"the host's old match does not move client %d's body for its hub input" % peer)
	for peer: int in range(1, _rig.peer_count()):
		assert_false(_rig.net_match(peer).get_local_link().is_predicting(), "client %d waits for the host's hub" % peer)
	# The host follows: everybody stands in one hub and the clients can walk.
	_free_scene(HOST)
	_bind_hub(HOST)
	for peer: int in range(1, _rig.peer_count()):
		var seat: int = _rig.sessions[peer].lobby.get_local_seat_index()
		var world: Viewport = _rig.matches[peer].get_viewport()
		var live: bool = await _rig.wait_for(func() -> bool:
			return not world.disable_3d and _cover_of(_rig.matches[peer]) == null, LoadingCover.MAX_HOLD_MS + 2000)
		assert_true(live, "client %d's hub is drawn once the host is in it" % peer)
		var net: NetMatch = _rig.net_match(HOST)
		var link: PlayerNetLink = net.call("_link_for_seat", seat) as PlayerNetLink
		if not assert_not_null(link, "the host has a body for client %d" % peer):
			continue
		var from: Vector3 = link.controller.global_position
		var walked: bool = await _rig.wait_for(func() -> bool:
			return link.controller.global_position.distance_to(from) > 1.0)
		assert_true(walked, "client %d walks in the hub and the host sees it" % peer)


func test_a_client_back_in_the_hub_first_waits_quietly_and_is_let_in_with_two() -> void:
	await _a_client_back_in_the_hub_first_waits_quietly_and_is_let_in(1)


func test_a_client_back_in_the_hub_first_waits_quietly_and_is_let_in_with_four() -> void:
	await _a_client_back_in_the_hub_first_waits_quietly_and_is_let_in(3)


# --- PT3-09: the relaunch leaves the hub the frame it stands ----------------------

## A hub that has left the tree for the relaunched match tells a late-binding client nothing.
func test_a_hub_that_has_left_the_tree_answers_no_late_client() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("the loopback handshake did not complete")
		return
	_rig.matches.resize(_rig.peer_count())
	var hub: Node3D = _bind_hub(HOST)
	var told: Array[int] = []
	(hub.get_node("NetMatch") as NetMatch).peer_bound.connect(func(peer: int) -> void: told.append(peer))
	# The scene change: out of the tree now, freed later.
	var world: Node = hub.get_parent()
	world.get_parent().remove_child(world)
	var late: Node3D = _bind_hub(1)
	# Only the client's scene acknowledgement is wanted on the wire, not input for a body that is gone.
	for link: Node in late.get_node("NetMatch").get_children():
		if link is PlayerNetLink:
			link.set_physics_process(false)
	var client_id: int = _rig.sessions[1].multiplayer.get_unique_id()
	var acknowledged: bool = await _rig.wait_for(func() -> bool:
		return _rig.sessions[HOST].lobby.peer_state(client_id) == NetLobby.PeerState.STANDING)
	assert_true(acknowledged, "the client's hub acknowledged its scene to the host")
	await step_ticks(4)
	assert_eq_int(told.size(), 0, "a hub out of the tree announces no peer to its cats")
	_rig.matches[HOST] = null
	world.free()
