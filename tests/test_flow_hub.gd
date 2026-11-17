extends "res://tests/support/net_hub_rig.gd"

## The hub as the session changes under it: a host lost, a peer leaving, a joiner arriving.

func _lobby_of(machine: int) -> HubLobby:
	return hubs[machine].get_node("HubLobby") as HubLobby


func test_a_client_is_told_when_the_host_leaves_the_hub() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var lost: Array[int] = count(_lobby_of(A).session_lost)
	sessions[HOST].leave()
	assert_true(await until(func() -> bool: return lost[0] > 0), "the client's hub hears the host is gone")
	assert_eq_int(lost[0], 1, "once")


## The host goes while a joiner's hub is still loading: the hub that then stands says so too.
func test_a_hub_that_loads_after_the_host_was_lost_still_says_so() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await connect_late(B):
		return
	sessions[HOST].leave()
	var failed: bool = await until(
		func() -> bool: return sessions[B].get_connection_state() == NetTransport.ConnectionState.FAILED
	)
	assert_true(failed, "the joiner's session fails while it has no hub yet")
	_make_hub(B)
	var lost: Array[int] = count(_lobby_of(B).session_lost)
	assert_true(await until(func() -> bool: return lost[0] > 0), "its hub, once standing, hears the host is gone")


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
