extends TestCase
## Lag compensation on the authority: a ray traced in the past meets bodies where they stood, and moves nothing.

## Where the target stood, and where it stands when the shot is traced.
const THEN: Vector3 = Vector3(0.0, 50.0, -20.0)
const NOW: Vector3 = Vector3(6.0, 50.0, -20.0)
## Where the rays are cast from, level with the body's chest.
const EYE: Vector3 = Vector3(0.0, 51.0, 0.0)
const CHEST: Vector3 = Vector3.UP
const SHOOTER_SEAT: int = 0
const TARGET_SEAT: int = 1
## Ticks the target has stood at NOW when a test begins, and a lag that reaches back past them.
const MOVED_AGO: int = 6
const LAG: int = 12

var _host: NetSession
var _client: NetSession
var _replicator: NetReplicator
var _shooter: PlayerController
var _target: PlayerController


func before_each() -> void:
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	_replicator = _host.replicator


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


## A body in [param seat] on the host, standing still at [param at] and open to a shot.
func _stand(seat: int, at: Vector3) -> PlayerController:
	var link: PlayerNetLink = NetFixtures.add_seat_body(_host, seat, 0, TestFixtures.movement_profile(), false)
	var body: PlayerController = link.controller
	body.set_physics_process(false)
	body.global_position = at
	body.collision_layer = 1
	return body


## A session of two with a shooter at the eye and a target that stood at THEN and now stands at NOW.
func _a_target_that_has_moved() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0 or not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return false
	_shooter = _stand(SHOOTER_SEAT, EYE - CHEST)
	_target = _stand(TARGET_SEAT, THEN)
	await step_ticks(LAG)
	_target.global_position = NOW
	await step_ticks(MOVED_AGO)
	return true


func _ray(to: Vector3, from: Vector3 = EYE) -> PhysicsRayQueryParameters3D:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [_shooter.get_rid()]
	return query


func _space() -> PhysicsDirectSpaceState3D:
	return _shooter.get_world_3d().direct_space_state


## Past the chest of a body standing at [param feet], seen from the eye.
func _through(feet: Vector3) -> Vector3:
	return EYE + (feet + CHEST - EYE) * 2.0


func _wall(centre: Vector3) -> StaticBody3D:
	var wall: StaticBody3D = TestFixtures.make_box_body(Vector3(4.0, 4.0, 0.5), centre, "Wall")
	add_child(wall)
	return wall


func test_a_ray_in_the_past_meets_the_body_where_it_stood() -> void:
	if not await _a_target_that_has_moved():
		return
	assert_true(_space().intersect_ray(_ray(_through(THEN))).is_empty(), "the live ray finds nothing where the body was")
	var hit: Dictionary = _replicator.trace(_space(), _ray(_through(THEN)), LAG)
	if not assert_false(hit.is_empty(), "the ray traced in the past meets the body where it stood"):
		return
	assert_same(hit["collider"], _target, "the collider is the body itself")
	assert_true(hit["rid"] == _target.get_rid(), "and so is the rid")
	assert_lt((hit["position"] as Vector3).distance_to(THEN + CHEST), 0.6, "at its chest, where it stood")
	assert_gt(((hit["normal"] as Vector3)).dot(EYE - THEN), 0.0, "on the side that faces the eye")
	assert_true(_replicator.trace(_space(), _ray(_through(NOW)), LAG).is_empty(), "and not where it stands now")


func test_a_short_lag_meets_the_body_where_it_stands_now() -> void:
	if not await _a_target_that_has_moved():
		return
	var back: int = MOVED_AGO - 2
	assert_same(_replicator.trace(_space(), _ray(_through(NOW)), back).get("collider"), _target, "it had already moved")
	assert_true(_replicator.trace(_space(), _ray(_through(THEN)), back).is_empty(), "and had left where it was")


func test_every_tick_of_the_history_is_the_tick_it_names() -> void:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0 or not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	_shooter = _stand(SHOOTER_SEAT, EYE - CHEST)
	_target = _stand(TARGET_SEAT, THEN)
	# Two metres a tick: no two ticks' bodies overlap, so a ray names one tick only.
	var walked: int = 40
	for step: int in walked:
		_target.global_position = THEN + Vector3.RIGHT * 2.0 * float(step)
		await step_ticks(1)
	for back: int in range(1, walked - 2):
		var stood: Vector3 = THEN + Vector3.RIGHT * 2.0 * float(walked - 1 - back)
		var hit: Dictionary = _replicator.trace(_space(), _ray(_through(stood)), back)
		if not assert_same(hit.get("collider"), _target, "%d ticks back the body is where it stood then" % back):
			return
		assert_true(
			_replicator.trace(_space(), _ray(_through(stood + Vector3.RIGHT * 2.0)), back).is_empty(),
			"%d ticks back it is not where it stood a tick later" % back,
		)


func test_cover_in_front_of_where_the_body_stood_stops_the_shot() -> void:
	if not await _a_target_that_has_moved():
		return
	var wall: StaticBody3D = _wall(Vector3(0.0, 51.0, -10.0))
	await step_ticks(2)
	assert_same(_replicator.trace(_space(), _ray(_through(THEN)), LAG + 2).get("collider"), wall, "the wall takes the shot")


func test_cover_behind_where_the_body_stood_does_not_save_it() -> void:
	if not await _a_target_that_has_moved():
		return
	_wall(Vector3(0.0, 51.0, -30.0))
	await step_ticks(2)
	assert_same(_replicator.trace(_space(), _ray(_through(THEN)), LAG + 2).get("collider"), _target, "the body is in front")


func test_cover_where_the_body_stands_now_does_not_shield_where_it_stood() -> void:
	if not await _a_target_that_has_moved():
		return
	_wall(Vector3(NOW.x, 51.0, -10.0))
	await step_ticks(2)
	assert_same(_replicator.trace(_space(), _ray(_through(THEN)), LAG + 2).get("collider"), _target, "the old line is open")


func test_a_trace_moves_no_body_and_no_ray_query() -> void:
	if not await _a_target_that_has_moved():
		return
	var bodies: Array[PlayerController] = [_shooter, _target, _stand(2, Vector3(20.0, 50.0, -20.0))]
	await step_ticks(2)
	var nodes: Array[Transform3D] = []
	var served: Array[Transform3D] = []
	for body: PlayerController in bodies:
		nodes.append(body.global_transform)
		served.append(PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM))
	var query: PhysicsRayQueryParameters3D = _ray(_through(THEN))
	assert_same(_replicator.trace(_space(), query, LAG + 2).get("collider"), _target, "the shot is traced in the past")
	assert_eq_int(query.exclude.size(), 1, "the query still excludes the shooter alone")
	assert_true(query.exclude[0] == _shooter.get_rid(), "and it is the shooter")
	for index: int in bodies.size():
		var body: PlayerController = bodies[index]
		assert_true(body.global_transform == nodes[index], "body %d's node is where it was" % index)
		assert_true(
			PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) == served[index],
			"body %d is where it was for the physics server" % index,
		)
	# On the same tick the live world is the live world.
	assert_same(_space().intersect_ray(_ray(_through(NOW))).get("collider"), _target, "a live ray meets it where it is")
	assert_true(_space().intersect_ray(_ray(_through(THEN))).is_empty(), "and nothing where it was")
	await step_ticks(3)
	for index: int in bodies.size():
		assert_true(bodies[index].global_transform == nodes[index], "body %d has not moved three ticks on" % index)
	assert_true(_space().intersect_ray(_ray(_through(THEN))).is_empty(), "nothing is left standing in the past")


func test_a_body_dead_now_is_not_shot_where_it_was_alive() -> void:
	if not await _a_target_that_has_moved():
		return
	# What the match does to a body it has shot.
	_target.collision_layer = 0
	assert_true(_replicator.trace(_space(), _ray(_through(THEN)), LAG).is_empty(), "not where it stood alive")
	assert_true(_replicator.trace(_space(), _ray(_through(NOW)), LAG).is_empty(), "nor where it lies")


func test_a_body_dead_then_is_not_shot_where_it_lay() -> void:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0 or not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	_shooter = _stand(SHOOTER_SEAT, EYE - CHEST)
	_target = _stand(TARGET_SEAT, THEN)
	_target.collision_layer = 0
	await step_ticks(LAG)
	# Back up, somewhere else.
	_target.global_position = NOW
	_target.collision_layer = 1
	await step_ticks(MOVED_AGO)
	assert_true(_replicator.trace(_space(), _ray(_through(THEN)), LAG).is_empty(), "a body that lay dead there is not shot there")
	assert_true(_replicator.trace(_space(), _ray(_through(NOW)), LAG).is_empty(), "nor where it had not yet stood up")
	assert_same(_replicator.trace(_space(), _ray(_through(NOW)), 2).get("collider"), _target, "it is shot where it stands alive")


func test_a_body_that_was_not_there_is_not_shot_in_the_past() -> void:
	if not await _a_target_that_has_moved():
		return
	var spot: Vector3 = THEN + Vector3.LEFT * 6.0
	var late: PlayerController = _stand(2, spot)
	await step_ticks(3)
	assert_true(_replicator.trace(_space(), _ray(_through(spot)), LAG).is_empty(), "it had not arrived on that tick")
	assert_same(_replicator.trace(_space(), _ray(_through(spot)), 2).get("collider"), late, "it has now")


func test_a_body_with_its_shape_off_is_not_shot_in_the_past() -> void:
	if not await _a_target_that_has_moved():
		return
	for owner: int in _target.get_shape_owners():
		_target.shape_owner_set_disabled(owner, true)
	assert_true(_replicator.trace(_space(), _ray(_through(THEN)), LAG).is_empty(), "a body with no shape has none in the past")


func test_the_shooter_is_never_met_where_it_stood() -> void:
	if not await _a_target_that_has_moved():
		return
	_shooter.global_position = EYE - CHEST + Vector3(0.0, 0.0, 5.0)
	await step_ticks(MOVED_AGO)
	# From where it stands now, through where it stood.
	var query: PhysicsRayQueryParameters3D = _ray(EYE + Vector3(0.0, 0.0, -10.0), EYE + Vector3(0.0, 0.0, 5.0))
	assert_true(_replicator.trace(_space(), query, LAG).is_empty(), "the shooter's own past is not in its way")


func test_a_ray_of_another_mask_passes_the_body_in_the_past() -> void:
	if not await _a_target_that_has_moved():
		return
	var query: PhysicsRayQueryParameters3D = _ray(_through(THEN))
	query.collision_mask = 2
	assert_true(_replicator.trace(_space(), query, LAG).is_empty(), "the body is not on that layer")


func test_no_lag_and_a_lag_past_the_history_are_the_live_ray() -> void:
	if not await _a_target_that_has_moved():
		return
	for back: int in [0, -3, NetReplicator.HISTORY_TICKS - 1, NetReplicator.HISTORY_TICKS, 5000]:
		assert_same(_replicator.trace(_space(), _ray(_through(NOW)), back).get("collider"), _target, "lag %d: where it is" % back)
		assert_true(_replicator.trace(_space(), _ray(_through(THEN)), back).is_empty(), "lag %d: not where it was" % back)


func test_a_client_traces_the_live_ray() -> void:
	if not await _a_target_that_has_moved():
		return
	assert_true(_client.replicator.trace(_space(), _ray(_through(THEN)), LAG).is_empty(), "a client rewinds nothing")
	assert_same(_client.replicator.trace(_space(), _ray(_through(NOW)), LAG).get("collider"), _target, "it sees what is")


## A rifle at the eye aimed through [param feet], wired as the match wires a client guard's.
func _rifle_aimed_at(feet: Vector3, travelling: bool) -> Rifle:
	var rifle: Rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(rifle)
	rifle.profile = TestFixtures.weapon_profile()
	if travelling:
		rifle.profile.shot_model = WeaponProfile.ShotModel.PROJECTILE
		rifle.profile.projectile_speed = 60.0
		rifle.profile.projectile_gravity = 0.0
		rifle.profile.max_range = 40.0
	add_child(rifle)
	rifle.set_physics_process(false)
	rifle.shooter_body = _shooter
	rifle.lag_back = _replicator.rewind_ticks
	rifle.lag_trace = _replicator.trace
	rifle.global_transform = Transform3D(Basis.IDENTITY, EYE).looking_at(feet + CHEST)
	return rifle


## Fire [param rifle] with [param lag] ticks of lag and fly its round out; what it hit, or null.
func _fire(rifle: Rifle, lag: int) -> Node3D:
	var struck: Array[Node3D] = []
	rifle.target_hit.connect(func(collider: Node3D, _at: Vector3, _normal: Vector3) -> void: struck.append(collider))
	var ended: Array[bool] = []
	rifle.missed.connect(func(_at: Vector3) -> void: ended.append(true))
	# The shooter saw the world [param lag] ticks ago: that is the view time its command carries.
	assert_true(rifle.try_fire(float(_replicator.get_tick() - lag)), "the rifle fires")
	for _tick: int in 120:
		if not struck.is_empty() or not ended.is_empty():
			break
		rifle.tick(SIM_DELTA)
		await step_ticks(1)
	assert_eq_int(struck.size() + ended.size(), 1, "the shot ended once")
	return struck[0] if not struck.is_empty() else null


func test_a_lagged_rifle_shot_hits_the_body_where_it_stood() -> void:
	if not await _a_target_that_has_moved():
		return
	assert_same(await _fire(_rifle_aimed_at(THEN, false), LAG), _target, "aimed where the shooter saw it")
	assert_true(_target.global_position == NOW, "the body it hit never left where it stands")


func test_a_lagged_rifle_shot_misses_where_the_body_stands_now() -> void:
	if not await _a_target_that_has_moved():
		return
	assert_null(await _fire(_rifle_aimed_at(NOW, false), LAG), "the shooter had not seen it there yet")


func test_an_unlagged_rifle_shot_is_the_live_shot() -> void:
	if not await _a_target_that_has_moved():
		return
	assert_same(await _fire(_rifle_aimed_at(NOW, false), 0), _target, "the host's own shot hits what is there")
	assert_null(await _fire(_rifle_aimed_at(THEN, false), 0), "and nothing where it was")


func test_a_lagged_round_in_flight_hits_the_body_where_it_stood_that_long_ago() -> void:
	if not await _a_target_that_has_moved():
		return
	# The round is a third of a second in the air; the body has stood at NOW since before it left.
	assert_same(await _fire(_rifle_aimed_at(NOW, true), 2), _target, "each step of the flight is traced the lag ago")
	assert_true(_target.global_position == NOW, "the body it hit never left where it stands")


func test_a_lagged_round_in_flight_passes_where_the_body_no_longer_was() -> void:
	if not await _a_target_that_has_moved():
		return
	assert_null(await _fire(_rifle_aimed_at(THEN, true), 2), "by the time the round arrived it had long gone")


func test_a_lagged_round_fired_as_the_body_leaves_hits_it_where_the_shooter_saw_it() -> void:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0 or not await NetFixtures.join_and_wait(self, _client, _host, port):
		fail("the loopback handshake did not complete")
		return
	_shooter = _stand(SHOOTER_SEAT, EYE - CHEST)
	# Two metres off, so the round arrives within the lag.
	var near: Vector3 = Vector3(0.0, 50.0, -2.0)
	_target = _stand(TARGET_SEAT, near)
	await step_ticks(LAG)
	_target.global_position = near + Vector3.RIGHT * 6.0
	await step_ticks(2)
	assert_same(await _fire(_rifle_aimed_at(near, true), LAG), _target, "the round meets the body the shooter was shown")
