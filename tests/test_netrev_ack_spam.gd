extends "res://tests/support/net_hub_rig.gd"

## H2: _request_standing has no rate limit; each one fans out to every hub cat.

func test_a_client_repeating_its_scene_ack_makes_the_host_answer_every_one() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	var epoch: int = sessions[HOST].lobby.get_epoch()
	var bound: Array[int] = [0]
	net(HOST).peer_bound.connect(func(_peer: int) -> void: bound[0] += 1)
	var transport: Node = sessions[HOST].transport
	transport.call(&"take_wire_stats")
	await step_ticks(60)
	var idle: Dictionary = transport.call(&"take_wire_stats")
	var started: int = Time.get_ticks_usec()
	for _i: int in 2000:
		sessions[A].lobby.rpc_id(1, &"_request_standing", epoch)
	await step_ticks(60)
	var spent: int = Time.get_ticks_usec() - started
	var flooded: Dictionary = transport.call(&"take_wire_stats")
	print("PROOF h2: 2000 acks -> %d peer_bound emissions x %d hub cats = %d reliable RPCs back; host sent %d bytes/%d packets in the flooded second vs %d bytes/%d packets idle; %d ms" % [
		bound[0], cats(HOST).size(), bound[0] * cats(HOST).size(),
		int(flooded.get("sent_bytes", -1)), int(flooded.get("sent_packets", -1)),
		int(idle.get("sent_bytes", -1)), int(idle.get("sent_packets", -1)), spent / 1000,
	])
	assert_eq_int(bound[0], 0, "a scene already acknowledged is answered no second time")


func test_a_garbage_ack_changes_nothing_and_alternating_it_buys_no_answers() -> void:
	if not await stand_up():
		return
	var epoch: int = sessions[HOST].lobby.get_epoch()
	var bound: Array[int] = [0]
	net(HOST).peer_bound.connect(func(_peer: int) -> void: bound[0] += 1)
	# Alternating a real and a wrong epoch is how a did-this-change-anything check is beaten.
	for _i: int in 200:
		sessions[A].lobby.rpc_id(1, &"_request_standing", 123456789)
		sessions[A].lobby.rpc_id(1, &"_request_standing", epoch)
	await step_ticks(30)
	var a_id: int = sessions[A].get_local_peer_id()
	var b_id: int = sessions[B].get_local_peer_id()
	print("PROOF h2b: 200 alternations -> %d answers; standing(A)=%s standing(B)=%s" % [
		bound[0], str(sessions[HOST].lobby.is_standing_in(a_id, epoch)), str(sessions[HOST].lobby.is_standing_in(b_id, epoch)),
	])
	assert_eq_int(bound[0], 0, "a scene already acknowledged is answered no second time")
	assert_true(sessions[HOST].lobby.is_standing_in(a_id, epoch), "a wrong epoch does not unbind the sender")
	assert_true(sessions[HOST].lobby.is_standing_in(b_id, epoch), "B is untouched")
	if not await lift_hub_cat(B):
		return
	var offered: bool = await until(func() -> bool: return holds_locally(B))
	assert_true(offered, "B's hub still works")
