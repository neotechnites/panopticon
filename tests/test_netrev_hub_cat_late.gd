extends "res://tests/support/net_hub_rig.gd"

const LOAD_TICKS: int = 120


func _agree(clients: Array[int], what: String) -> void:
	var truth: HubCat = cat(HOST, HUB_CAT)
	for machine: int in clients:
		var mine: HubCat = cat(machine, HUB_CAT)
		print("PROOF %s: machine %d cat at %s visible=%s gone=%s | host at %s visible=%s gone=%s state=%d" % [
			what, machine, str(mine.global_position.snapped(Vector3.ONE * 0.01)), str(mine.visible), str(mine.get("_gone")),
			str(truth.global_position.snapped(Vector3.ONE * 0.01)), str(truth.visible), str(truth.get("_gone")), int(truth.get("_state")),
		])
		assert_le(mine.global_position.distance_to(truth.global_position), 0.6, "%s: machine %d draws the cat where the host has it" % [what, machine])
		assert_true(mine.visible == truth.visible, "%s: machine %d agrees on whether it is drawn" % [what, machine])
		assert_true(bool(mine.get("_gone")) == bool(truth.get("_gone")), "%s: machine %d agrees on gone" % [what, machine])


func test_s1_a_joiner_arriving_while_the_host_carries_a_hub_cat_sees_it_carried_then_thrown() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await lift_hub_cat(HOST):
		return
	if not await join_late(B, LOAD_TICKS):
		return
	await step_ticks(30)
	var truth: HubCat = cat(HOST, HUB_CAT)
	print("PROOF s1: after join host carrier=%s state=%d" % [str(truth.get("_carrier")), int(truth.get("_state"))])
	_agree([A, B], "s1 after join")
	assert_false(holds_locally(B), "B is not offered the pet")
	if int(truth.get("_state")) == HubCat.State.HELD:
		keys[HOST].tap(&"shove_pressed")
		var gone: bool = await until(func() -> bool: return bool(truth.get("_gone")))
		assert_true(gone, "the host's throw went off")
		await step_ticks(20)
		_agree([A, B], "s1 after blast")
		var back: bool = await until(func() -> bool: return not bool(truth.get("_gone")))
		assert_true(back, "it came back")
		await step_ticks(20)
		_agree([A, B], "s1 after return")


func test_s2_a_joiner_whose_hub_stands_while_the_cat_is_gone_sees_it_return() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await lift_hub_cat(A):
		return
	if not await connect_late(B):
		return
	# The roster change rebuilt the host: A's body was freed and the cat dropped. Lift and throw again.
	var truth: HubCat = cat(HOST, HUB_CAT)
	await until(func() -> bool: return int(truth.get("_state")) == HubCat.State.REST)
	await until(func() -> bool: return net(A).get_local_link() != null and net(A).get_local_link().is_predicting())
	if not await lift_hub_cat(A):
		return
	keys[A].tap(&"shove_pressed")
	var gone: bool = await until(func() -> bool: return bool(truth.get("_gone")))
	if not assert_true(gone, "A's throw went off on the host"):
		return
	# B's hub stands inside the 4 s the cat sits out.
	if not await load_hub(B):
		return
	await step_ticks(10)
	_agree([A, B], "s2 while gone")
	var back: bool = await until(func() -> bool: return not bool(truth.get("_gone")))
	assert_true(back, "it came back on the host")
	await step_ticks(20)
	_agree([A, B], "s2 after return")


func test_s3_a_joiner_whose_hub_stands_while_a_client_carries_then_throws() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await connect_late(B):
		return
	var truth: HubCat = cat(HOST, HUB_CAT)
	await until(func() -> bool: return net(A).get_local_link() != null and net(A).get_local_link().is_predicting())
	if not await lift_hub_cat(A):
		return
	if not await load_hub(B):
		return
	await step_ticks(20)
	print("PROOF s3: host state=%d (1=HELD)" % int(truth.get("_state")))
	_agree([A, B], "s3 carried after B stands")
	assert_true(holds_locally(A), "A is still offered the pet")
	assert_false(holds_locally(B), "B is not")
