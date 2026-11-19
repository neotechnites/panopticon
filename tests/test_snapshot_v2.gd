extends TestCase

## Snapshot v2 on two real sessions (DESIGN 3.4, 4.3, 7): snapshots go only to standing peers and the
## first is whole, an epoch change starts both rings again with a full update, a placement is never
## slid across, and a lossless line predicts the host's body exactly.

const SEATS: int = 2

var _host: NetSession = null
var _client: NetSession = null
var _host_links: Array[PlayerNetLink] = []
var _client_links: Array[PlayerNetLink] = []


func before_each() -> void:
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	add_child(TestFixtures.make_floor(0.0))


func after_each() -> void:
	_host_links.clear()
	_client_links.clear()
	for session: NetSession in [_client, _host]:
		if session != null:
			session.leave()


## Connect; [param stand] stands the client in the lobby's epoch. Seat 0 is the client's (a bot's
## when not [param owns]), seat 1 a bot.
func _stand_up(stand: bool = true, owns: bool = true) -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0 or not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	if stand and not await NetFixtures.stand(self, _host, [_client]):
		return false
	var profile: MovementProfile = TestFixtures.movement_profile()
	var client_id: int = _client.get_local_peer_id()
	for seat: int in SEATS:
		var owner: int = client_id if seat == 0 and owns else 0
		_host_links.append(NetFixtures.add_seat_body(_host, seat, owner, profile, owner == 0))
		_client_links.append(NetFixtures.add_seat_body(_client, seat, owner, profile, owner != 0))
	for links: Array[PlayerNetLink] in [_host_links, _client_links]:
		for seat: int in SEATS:
			links[seat].controller.collision_mask = 1
			links[seat].controller.global_position = Vector3(float(seat) * 4.0, 0.1, 0.0)
	return true


func until(predicate: Callable) -> bool:
	return await NetFixtures.poll_until(self, predicate, 3000)


func _bot(seat: int) -> BotIntentSource:
	return _host_links[seat].local_source as BotIntentSource


func test_a_peer_not_standing_is_sent_nothing_and_its_first_snapshot_is_whole() -> void:
	if not assert_true(await _stand_up(false), "the sessions connect"):
		return
	await step_ticks(30)
	assert_eq_int(_client.replicator.get_latest_tick(), -1, "a peer not standing in the epoch is sent no snapshot")
	if not assert_true(await NetFixtures.stand(self, _host, [_client]), "the client stands"):
		return
	var heard: bool = await until(func() -> bool: return _client.replicator.get_latest_tick() >= 0)
	assert_true(heard, "once it stands, snapshots come")
	assert_eq_int(_client.replicator.last_baseline, -1, "and the first is a full update: there is no baseline yet")
	await step_ticks(30)
	assert_gt(float(_client.replicator.last_baseline), -1.0, "after its acknowledgement, deltas")


func test_an_epoch_change_forces_a_full_update_and_flushes_both_rings() -> void:
	if not assert_true(await _stand_up(), "the sessions stand"):
		return
	_bot(1).command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(40)
	if not assert_gt(float(_client.replicator.last_baseline), -1.0, "snapshots are deltas in the first epoch"):
		return
	var old_tick: int = _client.replicator.get_latest_tick()
	assert_not_null(_host.replicator._find_world(old_tick), "the host keeps what it sent as baselines")
	# A relaunch: a new epoch on the lobby, and each machine binds its new scene.
	_host.lobby._bump_epoch()
	_host.lobby._publish()
	var epoch: int = _host.lobby.get_epoch()
	if not await NetFixtures.poll_until(self, func() -> bool: return _client.lobby.get_epoch() == epoch):
		fail("the client never heard the new epoch")
		return
	_host.replicator.bind_scene(epoch)
	_client.replicator.bind_scene(epoch)
	assert_null(_host.replicator._find_world(old_tick), "the host's ring is flushed")
	assert_null(_client.replicator._find_world(old_tick), "and the client's")
	assert_eq_int(_client.replicator.get_latest_tick(), -1, "the client holds no world of the new epoch yet")
	_host.lobby.acknowledge_scene(epoch)
	_client.lobby.acknowledge_scene(epoch)
	var heard: bool = await until(func() -> bool: return _client.replicator.get_latest_tick() >= 0)
	if not assert_true(heard, "snapshots of the new epoch come"):
		return
	assert_eq_int(_client.replicator.last_baseline, -1, "the first of them is a full update")
	assert_eq_int(_client.replicator.missing_baselines, 0, "and nothing was coded against the old epoch's worlds")


func test_a_placement_is_never_drawn_sliding() -> void:
	if not assert_true(await _stand_up(), "the sessions stand"):
		return
	_bot(1).command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(60)
	var leap: float = 30.0
	var from: Vector3 = _host_links[1].controller.global_position
	_host_links[1].controller.place(from + Vector3(leap, 0.0, 0.0), 0.0)
	await step_ticks(20)
	# Every drawn time across the two worlds either side of the placement, on the client and the host.
	for machine: NetSession in [_client, _host]:
		var replicator: NetReplicator = machine.replicator
		var newest: int = replicator._newest().tick
		var after: int = -1
		for i: int in range(1, replicator._ring_count):
			if replicator._slot(i).find_seat(1).placed_counter != replicator._slot(i - 1).find_seat(1).placed_counter:
				after = i
		if not assert_gt(float(after), 0.0, "%s holds the worlds either side of the placement" % ("the client" if machine == _client else "the host")):
			continue
		var before_tick: int = replicator._slot(after - 1).tick
		var after_tick: int = replicator._slot(after).tick
		var link: PlayerNetLink = (_client_links if machine == _client else _host_links)[1]
		var worst: float = 0.0
		for step: int in 21:
			var time: float = lerpf(float(before_tick), float(after_tick), float(step) / 20.0)
			if machine == _client:
				replicator._draw(float(newest) - time)
			else:
				replicator.draw_host_at(time)
			var drawn: Vector3 = link.drawn_position() if machine == _host else link.controller.global_position
			var ends: float = minf(drawn.distance_to(replicator._slot(after - 1).find_seat(1).position),
				drawn.distance_to(replicator._slot(after).find_seat(1).position))
			worst = maxf(worst, ends)
		assert_lt(worst, 0.05, "%s draws the body at one end of the leap or the other, never between: %.2f m" % ["the client" if machine == _client else "the host", worst])


func test_a_lossless_line_predicts_the_host_exactly() -> void:
	if not assert_true(await _stand_up(), "the sessions stand"):
		return
	var link: PlayerNetLink = _client_links[0]
	var errors: PackedFloat32Array = PackedFloat32Array()
	link.prediction_corrected.connect(func(metres: float, _snapped: bool) -> void: errors.append(metres))
	var device: BotIntentSource = link.local_source as BotIntentSource
	await until(func() -> bool: return link.is_predicting())
	await step_ticks(20)
	errors.clear()
	device.command.move_direction = Vector2(0.3, 1.0)
	device.command.look_delta.x = 0.01
	await step_ticks(90)
	device.command.look_delta.x = -0.02
	device.command.move_direction = Vector2(-1.0, 0.2)
	await step_ticks(90)
	var worst: float = 0.0
	for metres: float in errors:
		worst = maxf(worst, metres)
	print("          lossless reconcile: worst %.7f m over %d corrections" % [worst, errors.size()])
	assert_gt(float(errors.size()), 20.0, "the client was corrected against many snapshots")
	assert_lt(worst, 1e-4, "and the host's state at each acknowledgement was the prediction, within float noise")


func test_a_client_with_no_body_of_its_own_still_acknowledges() -> void:
	if not assert_true(await _stand_up(true, false), "the sessions stand"):
		return
	_bot(1).command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(40)
	assert_eq_int(_client.replicator.get_last_command_packet().size(), 0, "it sent no commands")
	assert_gt(float(_client.replicator.last_baseline), -1.0, "yet its snapshots are deltas against what it acknowledged")


## The client's own body is thrown on the host only (a shove, a blast): [param throw], for 90 ticks.
## The first correction is the throw itself, unknowable to the client; the rest are measured.
func _host_throws_the_client(throw: Vector3) -> Array:
	var link: PlayerNetLink = _client_links[0]
	var errors: PackedFloat32Array = PackedFloat32Array()
	link.prediction_corrected.connect(func(metres: float, _snapped: bool) -> void: errors.append(metres))
	await until(func() -> bool: return link.is_predicting())
	await step_ticks(30)
	errors.clear()
	_host_links[0].controller.launch(throw, 0.4)
	await step_ticks(90)
	var worst: float = 0.0
	for i: int in range(1, errors.size()):
		worst = maxf(worst, errors[i])
	return [worst, errors.size()]


func test_a_body_the_host_throws_is_predicted_in_the_air() -> void:
	if not assert_true(await _stand_up(), "the sessions stand"):
		return
	var measured: Array = await _host_throws_the_client(Vector3(3.0, 9.0, 4.0))
	print("          thrown: worst %.6f m over %d corrections" % [measured[0], measured[1]])
	assert_gt(float(measured[1]), 8.0, "the client was corrected through the flight")
	assert_lt(float(measured[0]), 1e-4, "and after the host's word on the launch it flies exactly the host's arc")


func test_a_boost_pad_launch_is_replayed_as_it_was_run() -> void:
	if not assert_true(await _stand_up(), "the sessions stand"):
		return
	# One pad on each machine, in the client's path; the machines share a physics world, so each pad
	# sees only its own machine's copy of the body.
	var machines: Array[NetSession] = [_host, _client]
	var links: Array = [_host_links, _client_links]
	for index: int in 2:
		var layer: int = 1 << (2 + index)
		(links[index][0] as PlayerNetLink).controller.collision_layer = layer
		var pad: BoostPad = (load("res://props/boost_pad.tscn") as PackedScene).instantiate() as BoostPad
		pad.collision_mask = layer
		machines[index].get_parent().add_child(pad)
		pad.global_position = Vector3(0.0, 0.0, -4.0)
	var link: PlayerNetLink = _client_links[0]
	var errors: PackedFloat32Array = PackedFloat32Array()
	link.prediction_corrected.connect(func(metres: float, _snapped: bool) -> void: errors.append(metres))
	var launches: Array[int] = [0, 0]
	_host_links[0].controller.launched.connect(func(_v: Vector3) -> void: launches[0] += 1)
	link.controller.launched.connect(func(_v: Vector3) -> void: launches[1] += 1)
	await until(func() -> bool: return link.is_predicting())
	await step_ticks(20)
	errors.clear()
	(link.local_source as BotIntentSource).command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(120)
	var worst: float = 0.0
	for metres: float in errors:
		worst = maxf(worst, metres)
	print("          pad: host launched %d, client %d; worst %.6f m over %d corrections" % [launches[0], launches[1], worst, errors.size()])
	assert_eq_int(launches[0], 1, "the host's body crossed the pad and was launched")
	assert_gt(float(errors.size()), 10.0, "the client was corrected through the flight")
	assert_lt(worst, 1e-4, "and every replay across the pad threw the body as its first run did")
