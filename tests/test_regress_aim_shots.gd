extends TestCase
## Playtest regressions in shots: a client guard's shot, the shot rules and the replayed round, on every peer.

const Rig = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const GUARD: int = 1
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
## Ticks for a reliable event to cross a line held 3 real ms each way at fiftyfold time.
const CROSS_TICKS: int = 150
const LINE_LOSS: float = 0.1
const LINE_DELAY_MS: int = 3
## The line of the friend's session for the tests that run on the real clock: 100 ms there and back.
const REAL_DELAY_MS: int = 50
const REAL_CROSS_TICKS: int = 30
## Height on a body the guard aims at, metres.
const CHEST: float = 1.0
## A travelling round's speed for the arc tests, m/s; its drop is the shipped one.
const ROUND_SPEED: float = 60.0
## How the body the guard tracks moves: still, up and down the lane, shot just after it turns, or hopping.
enum Run { STAND, SHUTTLE, TURN, JUMP }
## Ticks the runner holds one way before it turns back: six metres of a stretch of eight.
const LEG_TICKS: int = 36
## Metres over the ground the real body must be from the drawn one for a shot to prove anything.
const PROVING_GAP: float = 0.6

var _rig: Rig = null
## Whether the match is played with a round that flies and drops.
var _travelling: bool = false
## Whether the rifle shoots straight unscoped: the host's own scope is a key, which a test has not got.
var _true_from_the_hip: bool = false
## Whether the round is played at the real clock, where a line's delay is the delay a player would have.
var _real_time: bool = false
var _cross: int = CROSS_TICKS
## The line the round is played over: milliseconds each way on the real clock, and the share lost.
var _delay_ms: int = REAL_DELAY_MS
var _loss: float = LINE_LOSS
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	_rig = Rig.new()
	_travelling = false
	_true_from_the_hip = false
	_real_time = false
	_cross = CROSS_TICKS
	_delay_ms = REAL_DELAY_MS
	_loss = LINE_LOSS
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	if _rig != null:
		_rig.close()
		_rig = null


## A round running on every peer over a bad line, client 1 in the tower.
func _start_round(map: StringName, clients: int, guard_slot: int = GUARD) -> bool:
	_rig.wire_loss = _loss
	_rig.wire_delay_ms = _delay_ms if _real_time else LINE_DELAY_MS
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 5
	_rig.settings().map_id = map
	if _travelling or _true_from_the_hip:
		var knobs: PackedFloat32Array = _rig.settings().sniper_by_visit
		for visit: int in SniperKnobs.VISITS:
			if _travelling:
				knobs[SniperKnobs.index(visit, SniperKnobs.Knob.SHOT_SPEED)] = ROUND_SPEED
			knobs[SniperKnobs.index(visit, SniperKnobs.Knob.HIP_SPREAD)] = 0.0
		_rig.settings().sniper_by_visit = knobs
	if not await _rig.launch(clients + 2, guard_slot):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	if _real_time:
		Engine.physics_ticks_per_second = int(SIM_HZ)
		Engine.time_scale = 1.0
		_cross = REAL_CROSS_TICKS * maxi(1, ceili(float(_delay_ms) / float(REAL_DELAY_MS)))
	await step_ticks(_cross)
	return true


func _input_of(peer: int) -> BotIntentSource:
	return (_rig.matches[peer].get_node("Player") as PlayerController).intent_source as BotIntentSource


## Turn [param own], through its input, to look from [param eye] at [param point] on this tick.
func _look_at(input: BotIntentSource, own: PlayerController, eye: Vector3, point: Vector3) -> void:
	var line: Vector3 = (point - eye).normalized()
	var view: Vector2 = own.get_view_angles()
	input.command.look_delta = Vector2(
		angle_difference(atan2(-line.x, -line.z), view.x), view.y - asin(clampf(line.y, -1.0, 1.0))
	)


## Whether the rifle's ray from [param eye] reaches [param point] in [param world], [param ignore] aside.
func _line_is_clear(world: World3D, eye: Vector3, point: Vector3, ignore: Array[RID]) -> bool:
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, point, TestFixtures.weapon_profile().hit_mask)
	ray.exclude = ignore
	return world.direct_space_state.intersect_ray(ray).is_empty()


## Whether [param body]'s own shape passes from standing at [param from] to standing at [param to], [param ignore] aside.
func _can_run(body: PlayerController, from: Vector3, to: Vector3, ignore: Array[RID]) -> bool:
	var sweep: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	sweep.exclude = ignore
	sweep.collision_mask = body.collision_mask
	sweep.motion = to - from
	for owner: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner):
			continue
		sweep.shape = body.shape_owner_get_shape(owner, 0)
		# Lifted off the deck by what the body steps over, so the deck itself is not in the way.
		sweep.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * 0.3) * body.shape_owner_get_transform(owner)
		if body.get_world_3d().direct_space_state.cast_motion(sweep)[0] < 1.0:
			return false
	return true


## Where the host's map lets its guard stand: the seat, and any guard posts.
func _stands(guard: PlayerController) -> Array[Vector3]:
	var stands: Array[Vector3] = [guard.global_position]
	for node: Node in get_tree().get_nodes_in_group(TowerShooter.POST_GROUP):
		if _rig.matches[HOST].is_ancestor_of(node):
			stands.append((node as Node3D).global_position)
	return stands


## Put the host's [param target] on a stretch of lane the host's [param guard] can see from end to end, and
## the guard where it sees it. The start line itself is behind cover on both maps.
func _stand_the_two_in_view(guard: PlayerController, target: PlayerController) -> bool:
	var route: RingRoute = _rig.matches[HOST].find_child("Route", true, false) as RingRoute
	if route == null:
		return false
	var world: World3D = target.get_world_3d()
	var centre: Vector3 = (route.get_parent() as Node3D).global_position
	var radius: float = route.lane_radius(0)
	var eye_height: float = guard.head.global_position.y - guard.global_position.y
	var ignore: Array[RID] = [guard.get_rid(), target.get_rid()]
	var from: Vector3 = target.global_position - centre
	var start_angle: float = atan2(from.z, from.x)
	# Two metres of lane a step, a stretch of five: room to run up and down.
	var step: float = 2.0 / radius
	# A stretch it can run from end to end if the map has one in view; on the spires of hell, one it can run about on.
	for open_run: bool in [true, false]:
		for stand: Vector3 in _stands(guard):
			var eye: Vector3 = stand + Vector3.UP * eye_height
			for first: int in range(2, int(TAU / step) - 6):
				var spots: PackedVector3Array = PackedVector3Array()
				for at: int in 5:
					var angle: float = start_angle + step * float(first + at)
					var over: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
					over.y = route.deck_height(0) + 2.0
					var down: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * 4.0)
					down.exclude = ignore
					var floor_hit: Dictionary = world.direct_space_state.intersect_ray(down)
					if floor_hit.is_empty() or absf((floor_hit["position"] as Vector3).y - route.deck_height(0)) > 0.3:
						break
					var spot: Vector3 = floor_hit["position"] as Vector3
					if not _line_is_clear(world, eye, spot + Vector3.UP * CHEST, ignore) \
							or not _line_is_clear(world, eye, spot + Vector3.UP * 0.2, ignore):
						break
					if open_run and not spots.is_empty() and not _can_run(target, spots[spots.size() - 1], spot, ignore):
						break
					spots.append(spot)
				if spots.size() < 5:
					continue
				guard.global_position = stand
				guard.velocity = Vector3.ZERO
				target.global_position = spots[0 if open_run else 2] + Vector3.UP * 0.05
				target.velocity = Vector3.ZERO
				# Along the lane, so forward and back keep it on the stretch.
				var along: Vector3 = spots[4] - spots[0]
				target.rotation.y = atan2(-along.x, -along.z)
				return true
	return false


# --- PT2-03: "the non hosts shots are just way way off" -------------------------------------------

## The guard on [param guard_peer] tracks a body as its own screen draws it and fires; the host scores it there.
func _a_guards_shot_lands_where_the_guard_drew_it(
	map: StringName, clients: int, run: Run, guard_peer: int = GUARD, delay_ms: int = REAL_DELAY_MS, loss: float = LINE_LOSS
) -> void:
	_real_time = true
	_true_from_the_hip = guard_peer == HOST
	_delay_ms = delay_ms
	_loss = loss
	if not await _start_round(map, clients, guard_peer):
		return
	var moving: bool = run != Run.STAND
	var target_peer: int = HOST if guard_peer != HOST else GUARD
	var host: MatchController = _rig.controller(HOST)
	var guard_slot: int = _rig.local_slot(guard_peer)
	var target_slot: int = _rig.local_slot(target_peer)
	var own: PlayerController = _rig.body(guard_peer, guard_slot)
	var real: PlayerController = _rig.body(HOST, target_slot)
	var drawn: PlayerController = _rig.body(guard_peer, target_slot)
	var input: BotIntentSource = _input_of(guard_peer)
	var legs: BotIntentSource = _input_of(target_peer)
	for participant: MatchParticipant in host.get_participants():
		if participant.index != guard_slot and participant.index != target_slot:
			participant.body.movement_locked = true
	if not assert_true(
		_stand_the_two_in_view(_rig.body(HOST, guard_slot), real), "the map has a stretch of lane the guard can see"
	):
		return
	await step_ticks(_cross)
	var hits: Array = []
	var shots: PackedInt32Array = PackedInt32Array()
	shots.resize(_rig.peer_count())
	var seen: Dictionary[int, Array] = {}
	var host_rifle: Rifle = host.rifle
	var lag: PackedInt32Array = PackedInt32Array()
	var replicator: NetReplicator = _rig.sessions[HOST].replicator
	var fired_on: PackedInt32Array = PackedInt32Array()
	for peer: int in _rig.peer_count():
		var rifle: Rifle = _rig.controller(peer).rifle
		seen[peer] = []
		rifle.fired.connect(
			func(_from: Vector3, _to: Vector3) -> void:
				shots[peer] += 1
				if peer == HOST:
					lag.append(host_rifle.lag_ticks)
					fired_on.append(replicator.get_tick())
		)
		rifle.target_hit.connect(
			func(collider: Node3D, at: Vector3, _normal: Vector3) -> void:
				if peer == HOST:
					hits.append([collider, at])
				else:
					seen[peer].append([collider, at])
		)
	var eye: Node3D = _rig.controller(guard_peer).rifle.aim_source
	input.command.aim_held = true
	# The target runs up and down the lane; the guard keeps its crosshair on what it is shown.
	var steady: int = 0
	var aimed_at: Vector3 = Vector3.ZERO
	var truly_at: Vector3 = Vector3.ZERO
	var drawn_was: Vector3 = drawn.global_position
	var pressed: bool = false
	for tick: int in 1200:
		var forward: bool = (tick / LEG_TICKS) % 2 == 0
		if moving:
			_rig.drive(target_peer, Vector2(0.0, 1.0 if forward else -1.0))
		if run == Run.JUMP:
			legs.command.jump_pressed = real.is_on_floor()
		steady = steady + 1 if tick % LEG_TICKS != 0 else 0
		var chest: Vector3 = drawn.global_position + Vector3.UP * CHEST
		var really: Vector3 = real.global_position + Vector3.UP * CHEST
		var drawn_step: Vector3 = drawn.global_position - drawn_was
		drawn_was = drawn.global_position
		_look_at(input, own, eye.global_position, chest)
		var gap: float = Vector2(chest.x - really.x, chest.z - really.z).length()
		var proving: bool = true
		match run:
			Run.STAND:
				proving = steady > 25 and real.velocity.length() < 0.1
			Run.SHUTTLE:
				proving = steady > 12 and steady < 30 and real.velocity.length() > 4.0
			Run.TURN:
				# The real body has turned back; the one the guard is shown is still running the old way.
				var heading: Vector3 = -real.global_basis.z * (-1.0 if forward else 1.0)
				proving = steady >= 1 and steady < 12 and tick >= LEG_TICKS and drawn_step.dot(heading) * SIM_HZ > 4.0
			Run.JUMP:
				proving = steady > 12 and steady < 30 and not real.is_on_floor() and real.velocity.length() > 4.0
		if guard_peer != HOST and moving:
			proving = proving and gap > PROVING_GAP
		if proving and host_rifle.can_fire() and host_rifle.get_hip_spread_degrees() <= 0.0 \
				and _line_is_clear(own.get_world_3d(), eye.global_position, chest, [own.get_rid(), drawn.get_rid()]):
			# This tick's command carries the trigger and the view laid on the chest as it is drawn now.
			aimed_at = chest
			truly_at = really
			pressed = true
			if guard_peer == HOST:
				# The host's own trigger is a key, which a test has not got: its view is on the chest a tick on.
				await step_ticks(1)
				aimed_at = drawn.global_position + Vector3.UP * CHEST
				truly_at = aimed_at
				_look_at(input, own, eye.global_position, aimed_at)
				await step_ticks(1)
				assert_true(host_rifle.try_fire(), "the host fires")
				break
			input.command.fire_pressed = true
			input.command.fire_held = true
		await step_ticks(1)
		if pressed:
			break
	input.command.fire_pressed = false
	if not assert_true(pressed, "the guard had a clear, scoped shot at the body"):
		return
	# Held, and still on the chest, until the host has fired it: one press can be lost on this line.
	for _tick: int in 120:
		if shots[HOST] > 0:
			break
		_look_at(input, own, eye.global_position, drawn.global_position + Vector3.UP * CHEST)
		await step_ticks(1)
	input.command.fire_held = false
	_rig.drive(target_peer, Vector2.ZERO)
	legs.command.jump_pressed = false
	if guard_peer != HOST and moving:
		assert_gt(
			Vector2(aimed_at.x - truly_at.x, aimed_at.z - truly_at.z).length(), PROVING_GAP,
			"the host's body had run on from where the client saw it",
		)
	if guard_peer != HOST and hits.size() == 1 and lag.size() == 1:
		# The body is a ghost now: the same ray, traced back to the tick it was shot alive on, passes it.
		var host_eye: Vector3 = host_rifle.aim_source.global_position
		var again: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			host_eye, host_eye + ((hits[0][1] as Vector3) - host_eye) * 1.5, host_rifle.profile.hit_mask
		)
		again.exclude = [_rig.body(HOST, guard_slot).get_rid()]
		var back: int = lag[0] + replicator.get_tick() - fired_on[0]
		if assert_lt(float(back), float(NetReplicator.HISTORY_TICKS), "the tick it was shot on is still in the history"):
			var found: Dictionary = replicator.trace(real.get_world_3d().direct_space_state, again, back)
			assert_true(found.get("collider") != real, "a body shot dead is not shot again where it stood alive")
	await step_ticks(_cross)
	assert_eq_int(shots[HOST], 1, "the host fired the guard's one shot")
	if guard_peer == HOST:
		assert_true(lag.size() == 1 and lag[0] == 0, "the host's own shot is traced in the present")
	elif assert_eq_int(lag.size(), 1, "the host traced one shot"):
		# There and back, and what the guard's screen holds back to draw between snapshots.
		assert_ge(float(lag[0]), float(2 * delay_ms) * SIM_HZ / 1000.0, "it is traced at least the line's delay in the past")
		assert_lt(float(lag[0]), float(NetReplicator.HISTORY_TICKS - 1), "and inside the history kept")
	if assert_eq_int(hits.size(), 1, "the shot aimed at the drawn body hits on the host"):
		assert_same(hits[0][0], real, "and it hits the body the guard aimed at")
		assert_lt((hits[0][1] as Vector3).distance_to(aimed_at), 0.8, "where the guard drew that body")
	assert_true(_rig.participant(HOST, target_slot).is_ghost, "the host's runner is shot")
	for peer: int in range(1, _rig.peer_count()):
		# A client's rifle fires on the host's word only: its own shot is drawn when the host has fired it.
		assert_eq_int(shots[peer], shots[HOST], "peer %d draws exactly the shots the host fired" % peer)
		if assert_eq_int(seen[peer].size(), hits.size(), "peer %d is told of the hit" % peer) and not hits.is_empty():
			assert_same(seen[peer][0][0], _rig.body(peer, target_slot), "peer %d: on the same body" % peer)
			assert_vec3_almost_eq(seen[peer][0][1], hits[0][1], 0.001, "peer %d: at the same point" % peer)
		assert_true(_rig.participant(peer, target_slot).is_ghost, "peer %d: the runner is shot" % peer)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.STAND)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_hell_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 3, Run.STAND)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_marble_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 1, Run.STAND)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_marble_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 3, Run.STAND)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.SHUTTLE)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_hell_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 3, Run.SHUTTLE)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_marble_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 1, Run.SHUTTLE)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_marble_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 3, Run.SHUTTLE)


func test_a_client_guards_shot_at_a_body_that_has_just_turned_lands_where_the_client_drew_it_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.TURN)


func test_a_client_guards_shot_at_a_body_that_has_just_turned_lands_where_the_client_drew_it_marble_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 3, Run.TURN)


func test_a_client_guards_shot_at_a_jumping_body_lands_where_the_client_drew_it_hell_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 3, Run.JUMP)


func test_a_client_guards_shot_at_a_jumping_body_lands_where_the_client_drew_it_marble_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 1, Run.JUMP)


func test_a_client_guards_shot_at_a_running_body_lands_at_50_ms_ping_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.SHUTTLE, GUARD, 25)


func test_a_client_guards_shot_at_a_running_body_lands_at_50_ms_ping_marble_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 3, Run.SHUTTLE, GUARD, 25)


func test_a_client_guards_shot_at_a_running_body_lands_at_200_ms_ping_hell_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 3, Run.SHUTTLE, GUARD, 100)


func test_a_client_guards_shot_at_a_running_body_lands_at_200_ms_ping_marble_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 1, Run.SHUTTLE, GUARD, 100)


func test_a_client_guards_shot_at_a_running_body_lands_on_a_clean_line_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.SHUTTLE, GUARD, REAL_DELAY_MS, 0.0)


func test_a_client_guards_shot_at_a_running_body_lands_with_a_third_of_the_line_lost_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.SHUTTLE, GUARD, REAL_DELAY_MS, 0.3)


func test_a_client_guards_shot_at_a_running_body_lands_with_a_third_of_the_line_lost_marble_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 3, Run.SHUTTLE, GUARD, REAL_DELAY_MS, 0.3)


func test_a_host_guards_shot_at_a_running_client_lands_where_the_host_sees_it_hell_two_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(HELL, 1, Run.SHUTTLE, HOST)


func test_a_host_guards_shot_at_a_running_client_lands_where_the_host_sees_it_marble_four_peers() -> void:
	await _a_guards_shot_lands_where_the_guard_drew_it(MARBLE, 3, Run.SHUTTLE, HOST)


# --- PT3-06: a client saw a dropped shot hit dead on ----------------------------------------------

## Metres from [param point] to the polyline through [param path].
func _distance_to_path(point: Vector3, path: PackedVector3Array) -> float:
	var best: float = INF
	for i: int in range(1, path.size()):
		var from: Vector3 = path[i - 1]
		var along: Vector3 = path[i] - from
		var t: float = clampf((point - from).dot(along) / maxf(along.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, point.distance_to(from + along * t))
	return best


## A travelling round fired from the tower by [param guard_peer]; every other machine flies and lands it as the host did.
func _a_dropped_round_is_replayed_as_the_host_flew_it(map: StringName, clients: int, guard_peer: int) -> void:
	_travelling = true
	if not await _start_round(map, clients, guard_peer):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, _rig.local_slot(guard_peer)))
	var rifle: Rifle = host.rifle
	if not assert_true(rifle.is_travelling_shot(), "the guard's shot travels, so it has an arc to replay"):
		return
	var input: BotIntentSource = _input_of(guard_peer)
	# A little up and over the sill: in the air long enough to fall, and down onto the map before its range runs out.
	for _tick: int in 8:
		input.command.look_delta = Vector2(0.0, -0.01)
		await step_ticks(1)
	await step_ticks(CROSS_TICKS)
	var host_end: Array[Vector3] = []
	var ends: Dictionary[int, Array] = {}
	rifle.missed.connect(func(end_point: Vector3) -> void: host_end.append(end_point))
	rifle.target_hit.connect(func(_c: Node3D, at: Vector3, _n: Vector3) -> void: host_end.append(at))
	for peer: int in range(1, _rig.peer_count()):
		var mirror: Rifle = _rig.controller(peer).rifle
		ends[peer] = []
		mirror.missed.connect(func(end_point: Vector3) -> void: ends[peer].append(end_point))
		mirror.target_hit.connect(func(_c: Node3D, at: Vector3, _n: Vector3) -> void: ends[peer].append(at))
	if not await _rig.wait_for(func() -> bool: return rifle.can_fire()):
		fail("the tower rifle never came ready")
		return
	if guard_peer == HOST:
		assert_true(rifle.try_fire(), "the host fires")
	else:
		# Held until the host has fired it: one press can be lost on this line, a held trigger cannot.
		input.command.fire_pressed = true
		input.command.fire_held = true
		await step_ticks(1)
		input.command.fire_pressed = false
	var host_path: PackedVector3Array = PackedVector3Array()
	var paths: Dictionary[int, PackedVector3Array] = {}
	for peer: int in range(1, _rig.peer_count()):
		paths[peer] = PackedVector3Array()
	for _tick: int in 1200:
		if not rifle.can_fire():
			input.command.fire_held = false
		var flying: Array = rifle.get(&"_projectiles")
		if not flying.is_empty() and is_instance_valid(flying[0]):
			host_path.append((flying[0] as Node3D).global_position)
		var told: bool = not host_end.is_empty()
		for peer: int in range(1, _rig.peer_count()):
			var shown: Array = _rig.controller(peer).rifle.get(&"_visual_rounds")
			# Only while the host's round is in the air: past its landing a replay flies on until it is told.
			if host_end.is_empty() and not shown.is_empty() and is_instance_valid(shown[0]):
				paths[peer].append((shown[0] as Node3D).global_position)
			told = told and not (ends[peer] as Array).is_empty()
		if told:
			break
		await step_ticks(1)
	if not assert_false(host_end.is_empty(), "the host's round landed"):
		return
	if not assert_ge(float(host_path.size()), 30.0, "the round was in the air long enough to drop"):
		return
	assert_lt(
		host_path[0].distance_to(host_end[0]), rifle.profile.max_range - 5.0,
		"the round met the map before its range ran out, so a replay has to be told where",
	)
	host_path.append(host_end[0])
	var straight: Vector3 = host_path[0].lerp(host_end[0], 0.5)
	assert_gt(_distance_to_path(straight, host_path), 1.0, "its flight is an arc, not the straight line to where it landed")
	for peer: int in range(1, _rig.peer_count()):
		if not assert_false((ends[peer] as Array).is_empty(), "peer %d is told where the round landed" % peer):
			continue
		assert_vec3_almost_eq(ends[peer][0], host_end[0], 0.001, "peer %d lands it where the host did" % peer)
		var path: PackedVector3Array = paths[peer]
		if not assert_gt(float(path.size()), 10.0, "peer %d drew the round in flight" % peer):
			continue
		var worst: float = 0.0
		for point: Vector3 in path:
			worst = maxf(worst, _distance_to_path(point, host_path))
		assert_le(worst, 0.5, "peer %d's replayed round flies the host's arc" % peer)
		var still_flying: Array = _rig.controller(peer).rifle.get(&"_visual_rounds")
		assert_eq_int(still_flying.size(), 0, "peer %d's replayed round ends when the host's has landed" % peer)


func test_a_client_guards_dropped_round_is_replayed_as_the_host_flew_it_hell_two_peers() -> void:
	await _a_dropped_round_is_replayed_as_the_host_flew_it(HELL, 1, GUARD)


func test_a_client_guards_dropped_round_is_replayed_as_the_host_flew_it_marble_four_peers() -> void:
	await _a_dropped_round_is_replayed_as_the_host_flew_it(MARBLE, 3, GUARD)


func test_a_host_guards_dropped_round_is_replayed_as_the_host_flew_it_hell_four_peers() -> void:
	await _a_dropped_round_is_replayed_as_the_host_flew_it(HELL, 3, HOST)


func test_a_host_guards_dropped_round_is_replayed_as_the_host_flew_it_marble_two_peers() -> void:
	await _a_dropped_round_is_replayed_as_the_host_flew_it(MARBLE, 1, HOST)
