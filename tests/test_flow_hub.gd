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
