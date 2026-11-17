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


func test_leaving_a_session_does_not_rebuild_the_hub_being_left() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var rebuilt: Array[int] = [0]
	ctrl(A).match_started.connect(func(_count: int) -> void: rebuilt[0] += 1)
	sessions[A].leave()
	await step_ticks(10)
	assert_eq_int(rebuilt[0], 0, "a closed lobby has no roster to stand bodies for")
	assert_true(await until(func() -> bool: return ctrl(HOST).get_participants().size() == 1), "the host's hub drops the leaver")
