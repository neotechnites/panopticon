extends "res://tests/support/net_hub_rig.gd"

## H2: _request_standing has no rate limit; a client repeating it must buy no answer from the host.
## The host's one answer to a scene acknowledgement is the roster it publishes on the first.

func test_a_client_repeating_its_scene_ack_makes_the_host_answer_none() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var epoch: int = sessions[HOST].lobby.get_epoch()
	var answers: Array[int] = [0]
	sessions[HOST].lobby.roster_changed.connect(func() -> void: answers[0] += 1)
	var started: int = Time.get_ticks_usec()
	for _i: int in 2000:
		sessions[A].lobby.rpc_id(1, &"_request_standing", epoch)
	await step_ticks(60)
	print("PROOF h2: 2000 acks -> %d rosters published; %d ms" % [answers[0], (Time.get_ticks_usec() - started) / 1000])
	assert_eq_int(answers[0], 0, "a scene already acknowledged is answered no second time")


func test_a_garbage_ack_changes_nothing_and_alternating_it_buys_no_answers() -> void:
	if not await stand_up():
		return
	var epoch: int = sessions[HOST].lobby.get_epoch()
	var answers: Array[int] = [0]
	sessions[HOST].lobby.roster_changed.connect(func() -> void: answers[0] += 1)
	# Alternating a real and a wrong epoch is how a did-this-change-anything check is beaten.
	for _i: int in 200:
		sessions[A].lobby.rpc_id(1, &"_request_standing", 123456789)
		sessions[A].lobby.rpc_id(1, &"_request_standing", epoch)
	await step_ticks(30)
	var a_id: int = sessions[A].get_local_peer_id()
	var b_id: int = sessions[B].get_local_peer_id()
	print("PROOF h2b: 200 alternations -> %d rosters published; standing(A)=%s standing(B)=%s" % [
		answers[0], str(sessions[HOST].lobby.is_standing_in(a_id, epoch)), str(sessions[HOST].lobby.is_standing_in(b_id, epoch)),
	])
	assert_eq_int(answers[0], 0, "a scene already acknowledged is answered no second time")
	assert_true(sessions[HOST].lobby.is_standing_in(a_id, epoch), "a wrong epoch does not unbind the sender")
	assert_true(sessions[HOST].lobby.is_standing_in(b_id, epoch), "B is untouched")
	if not await lift_hub_cat(B):
		return
	var offered: bool = await until(func() -> bool: return holds_locally(B))
	assert_true(offered, "B's hub still works")
