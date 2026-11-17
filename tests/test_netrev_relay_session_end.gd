extends NetPowerRig

func _relay(session: NetSession) -> CatGrenadeRelay:
	return session.get_parent().get_node_or_null("CatGrenadeRelay") as CatGrenadeRelay


func test_a_cat_in_a_clients_hands_when_the_host_goes_is_cleared_from_its_screen() -> void:
	var port: int = await NetFixtures.host_and_wait(self, host)
	assert_gt(float(port), 0.0, "host up")
	assert_true(await NetFixtures.join_and_wait(self, a, host, port), "A joined")
	await step_ticks(3)
	var first: CatGrenadeRelay = _relay(host)
	var mine: CatGrenadeRelay = _relay(a)
	var id: int = first.next_id()
	for _t: int in 10:
		first.pose(id, Vector3(1.0, 1.0, 1.0), 0.0, a.get_local_peer_id(), null)
		await step_ticks(1)
	print("PROOF h1b: while held: shown=%d held_id=%d" % [(mine.get("_shown") as Dictionary).size(), int(mine.get("_held_id"))])
	assert_eq_int(int(mine.get("_held_id")), id, "A is offered the pet")
	host.leave()
	await until(func() -> bool: return not a.is_established())
	await step_ticks(30)
	var shown: Dictionary = mine.get("_shown")
	var mesh: MeshInstance3D = shown.get(id, null)
	print("PROOF h1b: 30 ticks after the host left: established=%s shown=%d mesh_alive=%s held_id=%d prompt_alive=%s" % [
		str(a.is_established()), shown.size(), str(is_instance_valid(mesh)), int(mine.get("_held_id")), str(is_instance_valid(mine.get("_prompt")))])
	assert_eq_int(shown.size(), 0, "no cat is left drawn after the session ended")
	assert_eq_int(int(mine.get("_held_id")), 0, "and no pet prompt (which eats the interact key) is left up")
	if is_instance_valid(mesh):
		mesh.queue_free()
