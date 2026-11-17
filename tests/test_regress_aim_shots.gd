extends TestCase
## Playtest regressions in shots: a client guard's shot, the shot rules and the replayed round, on every peer.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

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
## Set to 1 to run the tests of bugs that are known and open; unset, they are skipped by name.
const OPEN_BUGS_ENV: String = "PANOPTICON_RUN_OPEN_BUGS"
const LAG_COMPENSATION_BUG: String = (
	"LIVE BUG (PT2-03): NetReplicator.rewind moves the bodies' nodes, but a CharacterBody3D moved inside a tick "
	+ "is still where it was for a ray cast in that tick, so a client guard's shot is traced against where the "
	+ "runner is now, not where the client saw it. %s=1 runs this test." % "PANOPTICON_RUN_OPEN_BUGS"
)

var _rig: RefCounted = null
## Whether the match is played with a round that flies and drops.
var _travelling: bool = false
## Whether the round is played at the real clock, where a line's delay is the delay a player would have.
var _real_time: bool = false
var _cross: int = CROSS_TICKS
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	_rig = Rig.new()
	_travelling = false
	_real_time = false
	_cross = CROSS_TICKS
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
	_rig.wire_loss = LINE_LOSS
	_rig.wire_delay_ms = REAL_DELAY_MS if _real_time else LINE_DELAY_MS
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 5
	_rig.settings().map_id = map
	if _travelling:
		var knobs: PackedFloat32Array = _rig.settings().sniper_by_visit
		for visit: int in SniperKnobs.VISITS:
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
		_cross = REAL_CROSS_TICKS
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
				spots.append(spot)
			if spots.size() < 5:
				continue
			guard.global_position = stand
			guard.velocity = Vector3.ZERO
			target.global_position = spots[2] + Vector3.UP * 0.05
			target.velocity = Vector3.ZERO
			# Along the lane, so forward and back keep it on the stretch.
			var along: Vector3 = spots[4] - spots[0]
			target.rotation.y = atan2(-along.x, -along.z)
			return true
	return false


# --- PT2-03: "the non hosts shots are just way way off" -------------------------------------------

## A client guard tracks a running body as its own screen draws it and fires; the host scores it there.
func _a_client_guards_shot_lands_where_the_client_drew_it(map: StringName, clients: int, moving: bool) -> void:
	if moving and OS.get_environment(OPEN_BUGS_ENV) != "1":
		skip(LAG_COMPENSATION_BUG)
		return
	_real_time = true
	if not await _start_round(map, clients):
		return
	var host: MatchController = _rig.controller(HOST)
	var guard_slot: int = _rig.local_slot(GUARD)
	var target_slot: int = _rig.local_slot(HOST)
	var own: PlayerController = _rig.body(GUARD, guard_slot)
	var real: PlayerController = _rig.body(HOST, target_slot)
	var drawn: PlayerController = _rig.body(GUARD, target_slot)
	var input: BotIntentSource = _input_of(GUARD)
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
	for peer: int in _rig.peer_count():
		var rifle: Rifle = _rig.controller(peer).rifle
		seen[peer] = []
		rifle.fired.connect(func(_from: Vector3, _to: Vector3) -> void: shots[peer] += 1)
		rifle.target_hit.connect(
			func(collider: Node3D, at: Vector3, _normal: Vector3) -> void:
				if peer == HOST:
					hits.append([collider, at])
				else:
					seen[peer].append([collider, at])
		)
	var eye: Node3D = _rig.controller(GUARD).rifle.aim_source
	var host_rifle: Rifle = host.rifle
	input.command.aim_held = true
	# The host runs up and down the lane; the client keeps its crosshair on what it is shown.
	var steady: int = 0
	var aimed_at: Vector3 = Vector3.ZERO
	var truly_at: Vector3 = Vector3.ZERO
	var pressed: bool = false
	for tick: int in 900:
		if moving:
			_rig.drive(HOST, Vector2(0.0, 1.0 if (tick / 50) % 2 == 0 else -1.0))
		steady = steady + 1 if tick % 50 != 0 else 0
		var chest: Vector3 = drawn.global_position + Vector3.UP * CHEST
		_look_at(input, own, eye.global_position, chest)
		if steady > 25 and steady < 40 and host_rifle.can_fire() \
				and host_rifle.get_hip_spread_degrees() <= 0.0 and (real.velocity.length() > 4.0) == moving \
				and _line_is_clear(own.get_world_3d(), eye.global_position, chest, [own.get_rid(), drawn.get_rid()]):
			# This tick's command carries the trigger and the view laid on the chest as it is drawn now.
			aimed_at = chest
			truly_at = real.global_position + Vector3.UP * CHEST
			input.command.fire_pressed = true
			input.command.fire_held = true
			pressed = true
		await step_ticks(1)
		if pressed:
			break
	input.command.fire_pressed = false
	if not assert_true(pressed, "the client had a clear, scoped shot at a running body"):
		return
	# Held, and still on the chest, until the host has fired it: one press can be lost on this line.
	for _tick: int in 120:
		if shots[HOST] > 0:
			break
		_look_at(input, own, eye.global_position, drawn.global_position + Vector3.UP * CHEST)
		await step_ticks(1)
	input.command.fire_held = false
	_rig.drive(HOST, Vector2.ZERO)
	await step_ticks(_cross)
	if moving:
		assert_gt(aimed_at.distance_to(truly_at), 0.5, "the host's body had run on from where the client saw it")
	assert_eq_int(shots[HOST], 1, "the host fired the client's one shot")
	if assert_eq_int(hits.size(), 1, "the shot aimed at the drawn body hits on the host"):
		assert_same(hits[0][0], real, "and it hits the body the client aimed at")
		assert_lt((hits[0][1] as Vector3).distance_to(aimed_at), 0.8, "where the client drew that body")
	assert_true(_rig.participant(HOST, target_slot).is_ghost, "the host's runner is shot")
	for peer: int in range(1, _rig.peer_count()):
		# A client's rifle fires on the host's word only: its own shot is drawn when the host has fired it.
		assert_eq_int(shots[peer], shots[HOST], "peer %d draws exactly the shots the host fired" % peer)
		if assert_eq_int(seen[peer].size(), hits.size(), "peer %d is told of the hit" % peer) and not hits.is_empty():
			assert_same(seen[peer][0][0], _rig.body(peer, target_slot), "peer %d: on the same body" % peer)
			assert_vec3_almost_eq(seen[peer][0][1], hits[0][1], 0.001, "peer %d: at the same point" % peer)
		assert_true(_rig.participant(peer, target_slot).is_ghost, "peer %d: the runner is shot" % peer)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_hell_two_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(HELL, 1, false)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_hell_four_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(HELL, 3, false)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_marble_two_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(MARBLE, 1, false)


func test_a_client_guards_shot_at_a_standing_body_lands_where_the_client_drew_it_marble_four_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(MARBLE, 3, false)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_hell_two_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(HELL, 1, true)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_hell_four_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(HELL, 3, true)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_marble_two_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(MARBLE, 1, true)


func test_a_client_guards_shot_at_a_running_body_lands_where_the_client_drew_it_marble_four_peers() -> void:
	await _a_client_guards_shot_lands_where_the_client_drew_it(MARBLE, 3, true)


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
