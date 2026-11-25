extends NetPowerRig

## The cat grenade (power 5) across three machines: held, cooked, its fuse and blast, and who
## is offered the pet. Throwing it and what the blast does to bodies is the hub scene's file.

const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const NONE: int = MatchRules.RunnerAbility.NONE
## The fuse is 2.5 s of simulation; a loaded machine may take several times that on the wall.
const FUSE_WAIT_MS: int = 20000
const DRAW_TOLERANCE_METRES: float = 0.3


func test_a_clients_cat_is_one_carried_cat_on_the_host_drawn_on_both_clients() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	var cats: Array[CatGrenade] = _host_cats()
	if not assert_eq_int(cats.size(), 1, "the host has exactly one cat for one press"):
		return
	assert_same(
		cats[0].carrier, body_of(host_links, A_SEAT), "the host's copy of A's body carries it"
	)
	assert_eq_int(int(power_of(host_links, A_SEAT).get_active()), CAT, "the host runs the cat power")
	await step_ticks(10)
	for session: NetSession in [host, a, b]:
		if not assert_eq_int(_shown_count(session), 1, "%s draws one cat" % _who(session)):
			continue
		var view: CatView = _views(session)[0]
		assert_lt(
			view.global_position.distance_to(cats[0].global_position), DRAW_TOLERANCE_METRES,
			"%s draws the cat where the host has it" % _who(session),
		)


func test_the_pet_prompt_is_on_the_client_that_holds_the_cat_only() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	var offered: bool = await until(func() -> bool: return _has_prompt(a))
	assert_true(offered, "A holds the cat and is offered the pet")
	assert_false(_has_prompt(host), "the host does not hold A's cat")
	assert_false(_has_prompt(b), "B does not hold A's cat")


func test_the_pet_prompt_is_on_the_host_when_the_host_holds_the_cat() -> void:
	if not await stand_up():
		return
	if not await _hold(host_keys, HOST_SEAT):
		return
	assert_true(_has_prompt(host), "the host holds its own cat and is offered the pet")
	await step_ticks(10)
	assert_false(_has_prompt(a), "A does not hold the host's cat")
	assert_false(_has_prompt(b), "B does not hold the host's cat")


func test_the_holder_is_found_when_its_link_is_not_under_its_body() -> void:
	var port: int = await NetFixtures.host_and_wait(self, host)
	if not assert_gt(float(port), 0.0, "the host took a port"):
		return
	# The match's layout: links sit beside the bodies they carry, never under them. The body is
	# the host's own player's, driven by no human device: only its link can say it is.
	var body: PlayerController = TestFixtures.make_bot_player(profile)
	body.name = "Seat1"
	host.get_parent().add_child(body)
	host.replicator.bind_scene(1)
	var link: PlayerNetLink = (
		(load(NetFixtures.LINK_SCENE_PATH) as PackedScene).instantiate() as PlayerNetLink
	)
	link.session = host
	link.replicator = host.replicator
	link.controller = body
	link.seat_index = A_SEAT
	link.owner_peer_id = host.get_local_peer_id()
	host.get_parent().add_child(link)
	await step_ticks(2)
	var stub: MatchController = _make_stub(host)
	_stubs.append(stub)
	var power: RunnerPower = RunnerPower.of(body)
	power.arm(rules, stub)
	assert_true(TestFixtures.fire(power, CAT as MatchRules.RunnerAbility), "the cat power starts")
	await step_ticks(2)
	var cats: Array[CatGrenade] = _host_cats()
	if not assert_eq_int(cats.size(), 1, "the host has the cat"):
		return
	await step_ticks(2)
	# Views are drawn per frame, not per tick: the signal comes before a frame's drawing, so two.
	await get_tree().process_frame
	await get_tree().process_frame
	var view: CatView = power.get_cat_view()
	if not assert_not_null(view, "the host draws the cat in its carrier's hands"):
		return
	assert_true(view.is_petting(), "the host's player, found through the link beside its body, is offered the pet")


func test_a_cooked_cat_runs_its_fuse_and_goes_off_everywhere() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	var host_power: RunnerPower = power_of(host_links, A_SEAT)
	assert_almost_eq(
		host_power.get_remaining(), RunnerPower.duration_of(MatchRules.RunnerAbility.CAT_GRENADE), 0.001, "an uncooked fuse is whole"
	)
	a_keys.tap(&"cook_pressed")
	var lit: bool = await until(func() -> bool: return _host_cooking())
	assert_true(lit, "A's E lit the fuse on the host")
	var falling: bool = await until(
		func() -> bool: return host_power.get_remaining() < RunnerPower.duration_of(MatchRules.RunnerAbility.CAT_GRENADE) - 0.1
	)
	assert_true(falling, "the fuse runs down: %.2f s left" % host_power.get_remaining())
	var blown: bool = await until(func() -> bool: return _host_cats().is_empty(), FUSE_WAIT_MS)
	assert_true(blown, "the host's cat is gone when the fuse ends")
	assert_eq_int(int(host_power.get_active()), NONE, "the host's cat power has ended")
	var cleared: bool = await until(func() -> bool: return all_draw(A_SEAT, NONE))
	assert_true(cleared, "the power ended on host, A and B: %s" % str(drawn(A_SEAT)))
	var undrawn: bool = await until(
		func() -> bool: return _shown_count(a) == 0 and _shown_count(b) == 0
	)
	assert_true(
		undrawn, "no client still draws a cat: A %d, B %d" % [_shown_count(a), _shown_count(b)]
	)
	assert_false(_has_prompt(a), "A is no longer offered the pet")
	await step_ticks(10)
	assert_true(
		_shown_count(a) == 0 and _shown_count(b) == 0, "and a late position does not redraw it"
	)
	for session: NetSession in [host, a, b]:
		assert_eq_int(_blasts(session).size(), 1, "%s plays the blast once" % _who(session))
	await _silence_blasts()


func test_an_uncooked_cat_does_not_go_off() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	await step_seconds(4.0)
	var cats: Array[CatGrenade] = _host_cats()
	if not assert_eq_int(cats.size(), 1, "the cat is still there four seconds on"):
		return
	var host_power: RunnerPower = power_of(host_links, A_SEAT)
	assert_false(host_power.state.cooking, "nobody lit it")
	assert_same(cats[0].carrier, body_of(host_links, A_SEAT), "it is still in A's hands")
	assert_almost_eq(host_power.get_remaining(), RunnerPower.duration_of(MatchRules.RunnerAbility.CAT_GRENADE), 0.001, "its fuse is whole")
	assert_true(all_draw(A_SEAT, CAT), "the power still runs on all three: %s" % str(drawn(A_SEAT)))
	assert_true(
		_shown_count(a) == 1 and _shown_count(b) == 1,
		"both clients still draw it: A %d, B %d" % [_shown_count(a), _shown_count(b)],
	)


func test_a_second_press_while_holding_adds_no_second_cat() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	var first: CatGrenade = _host_cats()[0]
	a_keys.tap_power(CAT)
	await step_ticks(20)
	var cats: Array[CatGrenade] = _host_cats()
	assert_eq_int(cats.size(), 1, "one cat at a time on the host")
	assert_true(cats.size() == 1 and cats[0] == first, "and it is the one already held")
	assert_true(
		_shown_count(a) == 1 and _shown_count(b) == 1,
		"each client draws one cat: A %d, B %d" % [_shown_count(a), _shown_count(b)],
	)
	assert_true(all_draw(A_SEAT, CAT), "the power still runs on all three: %s" % str(drawn(A_SEAT)))


func test_the_press_and_the_cook_survive_a_burst_of_loss() -> void:
	if not await _stand_up_on_wires():
		return
	var polls: int = a_keys.polls
	a_keys.tap_power(CAT)
	await black_out(a_wire, 4)
	assert_gt(float(a_keys.polls), float(polls), "the 5 went out inside the burst")
	var up: bool = await until(func() -> bool: return all_draw(A_SEAT, CAT))
	if not assert_true(up, "a 5 pressed in a burst of loss still holds a cat: %s" % str(drawn(A_SEAT))):
		return
	assert_eq_int(_host_cats().size(), 1, "the host has the cat")
	polls = a_keys.polls
	a_keys.tap(&"cook_pressed")
	await black_out(a_wire, 4)
	assert_gt(float(a_keys.polls), float(polls), "the E went out inside the burst")
	var lit: bool = await until(func() -> bool: return _host_cooking())
	assert_true(lit, "an E pressed in a burst of loss still lights the fuse")


func test_a_holder_freed_mid_hold_takes_its_cat_with_it() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	# The owner's copy goes first, so no intent is in flight to a link the host has dropped.
	body_of(a_links, A_SEAT).queue_free()
	await step_ticks(3)
	assert_eq_int(_host_cats().size(), 1, "the host still has the cat while its holder stands")
	body_of(host_links, A_SEAT).queue_free()
	# B's copy is taken away by its roster (NetMatch), covered in test_net_power_hub_roster.
	var ticks: int = 0
	while ticks < 30 and not (_host_cats().is_empty() and _shown_count(a) == 0 and _shown_count(host) == 0):
		await step_ticks(1)
		ticks += 1
	assert_eq_int(_host_cats().size(), 0, "the host's cat went with its holder")
	assert_eq_int(_shown_count(a), 0, "A draws no cat within 30 ticks")
	assert_eq_int(_shown_count(host), 0, "the host draws no cat within 30 ticks")
	assert_false(_has_prompt(a), "A is no longer offered the pet")
	await step_ticks(10)
	assert_true(
		_shown_count(a) == 0 and _shown_count(host) == 0, "and a later world does not redraw it"
	)


func test_a_cat_is_drawn_from_the_power_alone_on_every_machine() -> void:
	if not await stand_up():
		return
	if not await _hold(a_keys, A_SEAT):
		return
	# Every cat drawn anywhere belongs to the power of the body that carries it.
	for session: NetSession in [host, a, b]:
		var drawn: int = 0
		for node: Node in session.get_parent().find_children("*", "Node3D", true, false):
			if node is CatView and not node.is_queued_for_deletion():
				drawn += 1
		assert_eq_int(drawn, 1, "%s draws one cat, and only through A's power" % _who(session))


func test_a_blast_does_not_store_a_launch_on_a_body_held_out_of_the_world() -> void:
	var runner: MatchParticipant = await _standing_runner()
	var body: PlayerController = runner.body
	var start: Vector3 = body.global_position
	body.set_held(true)
	_blast_beside(runner)
	body.set_held(false)
	await step_ticks(5)
	assert_lt(
		body.global_position.distance_to(start), 0.1,
		"a body that was held when the cat went off is not thrown when it is let go",
	)
	assert_lt(body.velocity.length(), 0.5, "and carries no launch speed")
	assert_almost_eq(body.get_air_lock_remaining(), 0.0, 0.001, "nor a launch's air lock")


func test_a_blast_throws_a_body_that_is_simulating() -> void:
	var runner: MatchParticipant = await _standing_runner()
	var body: PlayerController = runner.body
	var start: Vector3 = body.global_position
	_blast_beside(runner)
	await step_ticks(5)
	assert_gt(body.global_position.y - start.y, 0.2, "the blast lifts a simulating body")
	assert_gt(
		body.global_position.x - start.x, 0.2, "and throws it away from where the cat went off"
	)


func after_each() -> void:
	super.after_each()
	# A wire forwards its socket's signals through closures that hold it; let go so it can die.
	for wire: LossyPeer in [a_wire, host_wire]:
		if wire == null:
			continue
		var real: MultiplayerPeer = wire.get("_real") as MultiplayerPeer
		for signal_name: StringName in [&"peer_connected", &"peer_disconnected"]:
			for connection: Dictionary in real.get_signal_connection_list(signal_name):
				real.disconnect(signal_name, connection["callable"] as Callable)
	a_wire = null
	host_wire = null


# --- Helpers ------------------------------------------------------------------

## The blast sounds playing on [param session]'s machine.
func _blasts(session: NetSession) -> Array[AudioStreamPlayer3D]:
	var sounds: Array[AudioStreamPlayer3D] = []
	for child: Node in session.get_parent().get_children():
		var sound: AudioStreamPlayer3D = child as AudioStreamPlayer3D
		if sound != null and sound.stream == CatView.EXPLOSION_SOUND:
			sounds.append(sound)
	return sounds


## Stop the blast sounds and let the audio server drop them, so none outlives the run.
func _silence_blasts() -> void:
	for session: NetSession in [host, a, b]:
		for sound: AudioStreamPlayer3D in _blasts(session):
			sound.stop()
	await step_ticks(4)

## The rig's stand_up on conditioned wires, each wrapped before its machine has a peer: a
## wire swapped in under a live connection makes the engine forget who it is connected to.
func _stand_up_on_wires() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, host)
	if port < 0:
		fail("the host could not take a port")
		return false
	host_wire = _condition(host, 0.0, 7, 1)
	if a.join("127.0.0.1", port) != OK:
		fail("client A could not start joining")
		return false
	a_wire = _condition(a, 0.0, 11, 1)
	var joined: bool = await until(
		func() -> bool: return a.is_established() and host.get_peer_count() >= 1
	)
	if not joined or not await NetFixtures.join_and_wait(self, b, host, port):
		fail("a loopback handshake did not complete")
		return false
	if not await NetFixtures.stand(self, host, [a, b]):
		fail("the clients never stood in the host's epoch")
		return false
	var a_id: int = a.get_local_peer_id()
	host_links = [
		NetFixtures.add_seat_body(host, HOST_SEAT, 1, profile, true),
		NetFixtures.add_seat_body(host, A_SEAT, a_id, profile, false),
	]
	a_links = [
		NetFixtures.add_seat_body(a, HOST_SEAT, 1, profile, false),
		NetFixtures.add_seat_body(a, A_SEAT, a_id, profile, true),
	]
	b_links = [
		NetFixtures.add_seat_body(b, HOST_SEAT, 1, profile, false),
		NetFixtures.add_seat_body(b, A_SEAT, a_id, profile, false),
	]
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		for seat: int in links.size():
			links[seat].controller.collision_mask = 1
			links[seat].controller.global_position = START[seat]
	host_keys = _give_keys(host_links[HOST_SEAT])
	a_keys = _give_keys(a_links[A_SEAT])
	await step_ticks(1)
	for session: NetSession in [host, a, b]:
		var stub: MatchController = _make_stub(session)
		_stubs.append(stub)
		for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
			for link: PlayerNetLink in links:
				if link.session == session:
					RunnerPower.of(link.controller).arm(rules, stub)
	var placed: bool = await until(func() -> bool: return a_links[A_SEAT].is_predicting())
	return assert_true(placed, "client A's body was placed by a snapshot on the conditioned wire")


## Press 5 on [param keys] and wait for the cat on the host and drawn on both clients.
func _hold(keys: PressSource, seat: int) -> bool:
	keys.tap_power(CAT)
	var up: bool = await until(func() -> bool: return all_draw(seat, CAT))
	if not assert_true(up, "the cat power is up on host, A and B: %s" % str(drawn(seat))):
		return false
	if not assert_true(not _host_cats().is_empty(), "the host has a cat for the press"):
		return false
	var seen: bool = await until(
		func() -> bool: return _shown_count(a) == 1 and _shown_count(b) == 1
	)
	return assert_true(
		seen, "A and B each draw the cat: A %d, B %d" % [_shown_count(a), _shown_count(b)]
	)


## The live cats under the host's branch.
func _host_cats() -> Array[CatGrenade]:
	var cats: Array[CatGrenade] = []
	for child: Node in host.get_parent().get_children():
		if child is CatGrenade and not child.is_queued_for_deletion():
			cats.append(child as CatGrenade)
	return cats


func _host_cooking() -> bool:
	return not _host_cats().is_empty() and power_of(host_links, A_SEAT).state.cooking


## The cats [param session]'s machine draws for its seats.
func _views(session: NetSession) -> Array[CatView]:
	var views: Array[CatView] = []
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		for link: PlayerNetLink in links:
			if is_instance_valid(link) and link.session == session and is_instance_valid(link.controller):
				var view: CatView = RunnerPower.of(link.controller).get_cat_view()
				if view != null:
					views.append(view)
	return views


func _shown_count(session: NetSession) -> int:
	return _views(session).size()


## True while [param session]'s machine offers its own player the pet.
func _has_prompt(session: NetSession) -> bool:
	for view: CatView in _views(session):
		if view.is_petting():
			return true
	return false


func _who(session: NetSession) -> String:
	return String(session.get_parent().name)


## A running participant on a real body, standing on the floor away from the rig's seats.
func _standing_runner() -> MatchParticipant:
	var body: PlayerController = TestFixtures.make_bot_player(profile)
	add_child(body)
	body.global_position = Vector3(40.0, 0.1, 40.0)
	await step_ticks(20)
	var runner: MatchParticipant = MatchParticipant.new()
	runner.body = body
	runner.is_running = true
	return runner


## A cat's blast one metre to the -X side of [param runner], at chest height.
func _blast_beside(runner: MatchParticipant) -> void:
	CatGrenade.push(runner, runner.body.global_position + Vector3(-1.0, CatGrenade.BODY_CENTRE, 0.0))
