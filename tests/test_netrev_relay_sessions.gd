extends NetPowerRig

## H1: a client's CatGrenadeRelay remembers the ids of cats gone in a PREVIOUS session, so a new
## host's cats (ids restart at 1) are never drawn on it.

func _relay(session: NetSession) -> CatGrenadeRelay:
	return session.get_parent().get_node_or_null("CatGrenadeRelay") as CatGrenadeRelay


func test_a_new_hosts_first_cats_are_drawn_on_a_client_that_saw_cats_in_an_earlier_session() -> void:
	var port: int = await NetFixtures.host_and_wait(self, host)
	assert_gt(float(port), 0.0, "first host up")
	assert_true(await NetFixtures.join_and_wait(self, a, host, port), "A joined host 1")
	await step_ticks(3)
	var first: CatGrenadeRelay = _relay(host)
	var mine: CatGrenadeRelay = _relay(a)
	# Session 1: three cats are carried and go off.
	for _i: int in 3:
		var id: int = first.next_id()
		for _t: int in 5:
			first.pose(id, Vector3(1.0, 1.0, 1.0), 0.0, 0, null)
			await step_ticks(1)
		first.gone(id)
	await step_ticks(10)
	print("PROOF session1: client _ended=%s shown=%d" % [str((mine.get("_ended") as Dictionary).keys()), (mine.get("_shown") as Dictionary).size()])
	assert_eq_int((mine.get("_shown") as Dictionary).size(), 0, "session 1 leaves nothing drawn")
	# The host goes away; A stays in the game and joins another host (here: B hosts).
	a.leave()
	host.leave()
	await step_ticks(5)
	var port2: int = await NetFixtures.host_and_wait(self, b)
	assert_gt(float(port2), 0.0, "second host up")
	assert_true(await NetFixtures.join_and_wait(self, a, b, port2), "A joined host 2")
	await step_ticks(3)
	var second: CatGrenadeRelay = _relay(b)
	var id2: int = second.next_id()
	for _t: int in 20:
		second.pose(id2, Vector3(2.0, 1.0, 2.0), 0.0, 0, null)
		await step_ticks(1)
	var drawn_now: int = (mine.get("_shown") as Dictionary).size()
	print("PROOF session2: new host cat id=%d, client draws %d cat(s), _ended=%s" % [id2, drawn_now, str((mine.get("_ended") as Dictionary).keys())])
	assert_eq_int(drawn_now, 1, "the new host's cat (id %d) is drawn on the client" % id2)
	second.gone(id2)
	await step_ticks(5)


## The likeliest shape: friends swap who hosts. The old host's relay remembers its OWN cats as gone.
func test_yesterdays_host_sees_the_new_hosts_first_cats_when_it_joins_as_a_client() -> void:
	var port: int = await NetFixtures.host_and_wait(self, host)
	assert_gt(float(port), 0.0, "first host up")
	assert_true(await NetFixtures.join_and_wait(self, a, host, port), "A joined host 1")
	await step_ticks(3)
	var first: CatGrenadeRelay = _relay(host)
	for _i: int in 5:
		var id: int = first.next_id()
		first.pose(id, Vector3(1.0, 1.0, 1.0), 0.0, 0, null)
		await step_ticks(2)
		first.gone(id)
	await step_ticks(5)
	a.leave()
	host.leave()
	await step_ticks(5)
	# Now A hosts and the old host joins it.
	var port2: int = await NetFixtures.host_and_wait(self, a)
	assert_gt(float(port2), 0.0, "A hosts")
	assert_true(await NetFixtures.join_and_wait(self, host, a, port2), "the old host joined A")
	await step_ticks(3)
	var second: CatGrenadeRelay = _relay(a)
	var seen: Array[int] = []
	var ids: Array[int] = []
	for _i: int in 8:
		var id: int = second.next_id()
		ids.append(id)
		for _t: int in 10:
			second.pose(id, Vector3(2.0, 1.0, 2.0), 0.0, 0, null)
			await step_ticks(1)
		seen.append((first.get("_shown") as Dictionary).size())
		second.gone(id)
		await step_ticks(3)
	print("PROOF swap: new host's cat ids %s -> drawn on the old host: %s (1 = drawn, 0 = invisible)" % [str(ids), str(seen)])
	assert_eq_int(seen.count(0), 0, "every one of the new host's cats is drawn on the old host: %s" % str(seen))
