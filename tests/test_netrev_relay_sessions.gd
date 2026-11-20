extends NetPowerRig

## H1: a cat in a second session is drawn on a client that saw cats go off in the first, whoever
## hosts it. Nothing of a cat outlives the session that had it.

const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const FUSE_WAIT_MS: int = 20000


func test_a_new_hosts_first_cat_is_drawn_on_a_client_that_saw_cats_in_an_earlier_session() -> void:
	if not await stand_up():
		return
	for round_index: int in 2:
		a_keys.tap_slot(CAT)
		if not assert_true(await until(func() -> bool: return _drawn_on(b, A_SEAT)), "session 1: B draws A's cat %d" % round_index):
			return
		a_keys.tap(&"cook_pressed")
		if not assert_true(await until(func() -> bool: return not _drawn_on(b, A_SEAT), FUSE_WAIT_MS), "and it went off"):
			return
		await step_ticks(5)
	_close_session()
	await step_ticks(5)
	# A stays in the game and joins another host: B.
	if not await _second_session(b, a):
		return
	_new_keys.tap_slot(CAT)
	var drawn: bool = await until(func() -> bool: return _drawn_on(a, HOST_SEAT))
	print("PROOF session2: the new host's cat is drawn on the client: %s" % str(drawn))
	assert_true(drawn, "the new host's first cat is drawn on the client")


## Friends swap who hosts: yesterday's host joins today's and draws its cats.
func test_yesterdays_host_sees_the_new_hosts_cats_when_it_joins_as_a_client() -> void:
	if not await stand_up():
		return
	host_keys.tap_slot(CAT)
	if not assert_true(await until(func() -> bool: return _drawn_on(a, HOST_SEAT)), "session 1: A draws the host's cat"):
		return
	host_keys.tap(&"cook_pressed")
	if not assert_true(await until(func() -> bool: return not _drawn_on(a, HOST_SEAT), FUSE_WAIT_MS), "and it went off"):
		return
	_close_session()
	await step_ticks(5)
	if not await _second_session(a, host):
		return
	var seen: Array[bool] = []
	for _i: int in 3:
		_new_keys.tap_slot(CAT)
		seen.append(await until(func() -> bool: return _drawn_on(host, HOST_SEAT)))
		_new_keys.tap(&"cook_pressed")
		await until(func() -> bool: return not _drawn_on(host, HOST_SEAT), FUSE_WAIT_MS)
		await step_ticks(5)
	print("PROOF swap: the new host's cats drawn on the old host: %s" % str(seen))
	assert_eq_int(seen.count(false), 0, "every one of the new host's cats is drawn on the old host: %s" % str(seen))


var _new_keys: PressSource = null
var _second: Array[Node] = []


func after_each() -> void:
	for node: Node in _second:
		if is_instance_valid(node):
			node.queue_free()
	_second.clear()
	super.after_each()


## True when [param machine] draws a cat for [param seat] in the session it is in now.
func _drawn_on(machine: NetSession, seat: int) -> bool:
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		for link: PlayerNetLink in links:
			if is_instance_valid(link) and link.session == machine and link.seat_index == seat and is_instance_valid(link.controller):
				var power: RunnerPower = RunnerPower.of(link.controller)
				if power.get_cat_view() != null:
					return true
	return false


## Everyone leaves and the first session's bodies go with its scene, as [SessionFlow] does.
func _close_session() -> void:
	for session: NetSession in [b, a, host]:
		session.leave()
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		for link: PlayerNetLink in links:
			if is_instance_valid(link) and is_instance_valid(link.controller):
				link.controller.queue_free()
	host_links = []
	a_links = []
	b_links = []


## [param new_host] hosts and [param client] joins; seat 0 is the new host's, seat 1 the client's.
func _second_session(new_host: NetSession, client: NetSession) -> bool:
	var port: int = await NetFixtures.host_and_wait(self, new_host)
	if not assert_gt(float(port), 0.0, "the second host is up"):
		return false
	if not assert_true(await NetFixtures.join_and_wait(self, client, new_host, port), "the client joined the second host"):
		return false
	if not assert_true(await NetFixtures.stand(self, new_host, [client]), "the client stands in the second session"):
		return false
	var client_id: int = client.get_local_peer_id()
	host_links = [
		NetFixtures.add_seat_body(new_host, HOST_SEAT, 1, profile, true),
		NetFixtures.add_seat_body(new_host, A_SEAT, client_id, profile, false),
	]
	a_links = [
		NetFixtures.add_seat_body(client, HOST_SEAT, 1, profile, false),
		NetFixtures.add_seat_body(client, A_SEAT, client_id, profile, true),
	]
	for links: Array[PlayerNetLink] in [host_links, a_links]:
		for seat: int in links.size():
			links[seat].controller.collision_mask = 1
			links[seat].controller.global_position = START[seat]
			_second.append(links[seat].controller)
	_new_keys = _give_keys(host_links[HOST_SEAT])
	await step_ticks(1)
	for session: NetSession in [new_host, client]:
		var stub: MatchController = _make_stub(session)
		_stubs.append(stub)
		for links: Array[PlayerNetLink] in [host_links, a_links]:
			for link: PlayerNetLink in links:
				if link.session == session:
					RunnerPower.of(link.controller).arm(rules, stub)
	return assert_true(await until(func() -> bool: return a_links[A_SEAT].is_predicting() and client.replicator.get_latest_tick() >= 0), "the client's body was placed")
