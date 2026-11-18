extends "res://tests/support/net_hub_rig.gd"

## The hub as the session changes under it: a host lost, a peer leaving, a joiner arriving.

func _lobby_of(machine: int) -> HubLobby:
	return hubs[machine].get_node("HubLobby") as HubLobby


## The menus [param machine]'s session flow asked for, as it would stand them.
func _menus_wanted(machine: int) -> Array[String]:
	var wanted: Array[String] = []
	sessions[machine].flow.scene_wanted.connect(func(path: String) -> void:
		if path == SessionFlow.MENU_SCENE_PATH:
			wanted.append(path))
	return wanted


func test_a_client_is_told_when_the_host_leaves_the_hub() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var menus: Array[String] = _menus_wanted(A)
	sessions[HOST].leave()
	assert_true(await until(func() -> bool: return not menus.is_empty()), "the client's flow takes it out of the hub")
	assert_eq_int(menus.size(), 1, "once")
	assert_eq_string(String(sessions[A].flow.take_end_reason()), String(SessionFlow.HOST_LOST_REASON), "saying the host is gone")


## The host goes while a joiner's hub is still loading: the joiner goes back to the menu, told why.
func test_a_joiner_still_loading_its_hub_is_told_the_host_went() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await connect_late(B):
		return
	var menus: Array[String] = _menus_wanted(B)
	sessions[HOST].leave()
	var failed: bool = await until(
		func() -> bool: return sessions[B].get_connection_state() == NetTransport.ConnectionState.FAILED
	)
	assert_true(failed, "the joiner's session fails while it has no hub yet")
	assert_eq_int(menus.size(), 1, "its flow takes it to the menu")
	assert_eq_string(String(sessions[B].flow.take_end_reason()), String(SessionFlow.HOST_LOST_REASON), "saying the host is gone")


func test_leaving_a_session_does_not_rebuild_the_hub_being_left() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var rebuilt: Array[int] = [0]
	ctrl(A).match_started.connect(func(_count: int) -> void: rebuilt[0] += 1)
	sessions[A].leave()
	await step_ticks(10)
	assert_eq_int(rebuilt[0], 0, "a closed lobby has no roster to stand bodies for")
	assert_true(await until(func() -> bool: return ctrl(HOST).get_participants().size() == 1), "the host's hub drops the leaver")


func test_a_joiner_arriving_leaves_everyone_standing_where_they_were() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var host_spot: Vector3 = body(HOST, HOST).global_position + Vector3(3.0, 0.0, 2.0)
	var a_spot: Vector3 = body(HOST, A).global_position + Vector3(-2.0, 0.0, 3.0)
	body(HOST, HOST).global_position = host_spot
	for machine: int in [HOST, A]:
		body(machine, A).global_position = a_spot
	await step_ticks(30)
	host_spot = body(HOST, HOST).global_position
	a_spot = body(HOST, A).global_position
	if not await join_late(B):
		return
	assert_lt(flat_distance(body(HOST, HOST).global_position, host_spot), 0.5, "the host's body stayed put on the host")
	assert_lt(flat_distance(body(HOST, A).global_position, a_spot), 0.5, "A's body stayed put on the host")
	await step_ticks(30)
	assert_lt(flat_distance(body(A, A).global_position, a_spot), 0.5, "and on A's own machine")
	assert_lt(flat_distance(body(B, HOST).global_position, host_spot), 0.5, "and the joiner sees the host there")


func test_only_the_host_is_offered_the_rules_panel() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	for machine: int in [HOST, A]:
		var lobby: HubLobby = _lobby_of(machine)
		lobby.set_overlay_open(true)
		assert_true(lobby.setup_screen.visible == (machine == HOST), "machine %d: the rules are the host's to edit" % machine)
		lobby.set_overlay_open(false)


## Past the hub's edge there is nothing to land on: the host stands the faller back on a spawn,
## and the faller's own machine follows.
func test_a_body_that_falls_out_of_the_hub_is_stood_back_in_it() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	for seat: int in [HOST, A]:
		var home: Vector3 = body(HOST, seat).global_position
		for machine: int in ([HOST] if seat == HOST else [HOST, seat]):
			body(machine, seat).global_position = home + Vector3(400.0, 0.0, 400.0)
			body(machine, seat).velocity = Vector3.ZERO
		var back: bool = await until(func() -> bool:
			return (body(HOST, seat).is_on_floor() and flat_distance(body(HOST, seat).global_position, home) < 30.0
				and body(seat, seat).global_position.distance_to(body(HOST, seat).global_position) < 1.0), 15000)
		assert_true(back, "seat %d, walked off the edge, stands in the hub again on the host and on its own machine" % seat)
