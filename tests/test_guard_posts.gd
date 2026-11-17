extends TestCase

## Where the AI guard stands: on its seat when the map has no posts, and at a post
## with a line of fire to what it is looking at when the map has them.

const SEED: int = 20260914
const POST_RADIUS: float = 4.0
const POSTS: int = 8
## Lane samples round the lap, and the share of them the guard must have a line to.
const LANE_SAMPLES: int = 72
const LANE_SEEN_AT_LEAST: float = 0.25
## A ray stopped this close to its lane point reached the lane.
const LANE_REACHED_METRES: float = 2.0

var _world: Node3D = null


func before_each() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_world.add_child(TestFixtures.make_floor(0.0))


## With no post markers on the map nothing about the guard's stand changes.
func test_a_guard_on_a_map_with_no_posts_keeps_its_seat() -> void:
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(40.0, 30.0))
	await step_seconds(2.0)
	assert_same(guard.get_target(), runner, "the runner is tracked")
	assert_eq_int(guard.get_post(), -1, "there is no post to hold")
	assert_lt(_flat_distance(guard.controller.global_position, Vector3.ZERO), 0.05, "and the guard has not left its seat")


## The post nearest the target's bearing is walked to and then held.
func test_a_guard_walks_to_the_post_that_faces_its_target() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(40.0, 30.0))
	await step_seconds(3.0)
	assert_same(guard.get_target(), runner, "the runner is tracked")
	var post: Vector3 = _at_bearing(45.0, POST_RADIUS)
	var settled: Vector3 = guard.controller.global_position
	assert_lt(_flat_distance(settled, post), 0.3, "the guard stands at the post 5 degrees off the runner's bearing")
	await step_seconds(1.0)
	assert_lt(_flat_distance(guard.controller.global_position, settled), 0.05, "and stands still once there")


## A post with a line is held however far the target moves along it; a post whose line is cut is left.
func test_a_guard_holds_its_post_while_it_has_a_line_and_leaves_it_when_the_line_is_cut() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(40.0, 30.0))
	runner.set_physics_process(false)
	await step_seconds(3.0)
	var held: int = guard.get_post()
	runner.global_position = _at_bearing(8.0, 30.0)
	await step_seconds(3.0)
	assert_eq_int(guard.get_post(), held, "37 degrees off its post but in its line, it stays")
	_make_wall(_at_bearing(45.0, POST_RADIUS + 1.0), 45.0)
	await step_seconds(6.0)
	assert_true(guard.get_post() != held, "with the line cut it moves")
	assert_same(guard.get_target(), runner, "to where it sees the runner again")


## The bug the line rule exists for: the post nearest the target's bearing is blind (a wall),
## another has a line. Bearing kept the guard at the blind one; the line takes it to the other.
func test_a_guard_at_a_blind_post_walks_to_one_with_a_line_and_holds_fire_on_the_way() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(45.0, 30.0))
	runner.set_physics_process(false)
	await step_seconds(3.0)
	var blind: int = guard.get_post()
	assert_lt(_flat_distance(guard.controller.global_position, _at_bearing(45.0, POST_RADIUS)), 0.3, "it first stands at the post facing the runner")
	var speeds: PackedFloat32Array = _record_shot_speeds(guard)
	_make_wall(_at_bearing(45.0, POST_RADIUS + 1.0), 45.0)
	await step_seconds(8.0)
	assert_true(guard.get_post() != blind, "it leaves the blind post")
	assert_lt(_flat_distance(guard.controller.global_position, _post_at(guard)), 0.3, "and stands at the one it chose")
	assert_same(guard.get_target(), runner, "from where it has the runner in sight")
	assert_gt(float(speeds.size()), 0.0, "and shoots from there")
	_assert_still_at_every_shot(speeds)


## A sniper does not fire on the move: in sight of its target for a whole 12 m walk, it shoots
## only once it stands at the post.
func test_a_guard_holds_fire_while_it_walks_to_its_post() -> void:
	_make_post(_at_bearing(45.0, 12.0))
	_make_post(_at_bearing(225.0, POST_RADIUS))
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(45.0, 40.0))
	runner.set_physics_process(false)
	var speeds: PackedFloat32Array = _record_shot_speeds(guard)
	await step_seconds(6.0)
	assert_lt(_flat_distance(guard.controller.global_position, _at_bearing(45.0, 12.0)), 0.3, "it walks to the post on the runner's side")
	assert_gt(float(speeds.size()), 0.0, "shoots once it is there")
	_assert_still_at_every_shot(speeds)


## Shoved while it has a runner in its sights, it shoots again only once its body has stopped.
func test_a_shoved_guard_does_not_fire_until_its_body_is_still() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(45.0, 30.0))
	runner.set_physics_process(false)
	await step_seconds(3.0)
	var speeds: PackedFloat32Array = _record_shot_speeds(guard)
	for shove: int in 6:
		var along: Vector3 = Vector3(-cos(deg_to_rad(45.0)), 0.0, -sin(deg_to_rad(45.0))) * (1.0 if shove % 2 == 0 else -1.0)
		guard.controller.velocity = along * 6.0
		await step_seconds(1.0)
	assert_gt(float(speeds.size()), 0.0, "it keeps shooting between shoves")
	_assert_still_at_every_shot(speeds)


## A guard that takes over a body standing anywhere in the room (a seat handed to a bot
## mid-round) takes the nearest post with a line, not one across the room.
func test_a_guard_armed_off_the_seat_takes_the_nearest_post_with_a_line() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3(3.0, 0.0, 1.0))
	var runner: PlayerController = _make_body(_at_bearing(40.0, 30.0))
	await step_seconds(3.0)
	assert_same(guard.get_target(), runner, "the runner is tracked")
	assert_lt(_flat_distance(guard.controller.global_position, _at_bearing(90.0, POST_RADIUS)), 0.3, "from the post 1.4 m away")


## Somebody inside the room (the finisher, come for the guard) is in the held post's line: no walk.
func test_a_target_inside_the_ring_of_posts_does_not_move_the_guard() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	var runner: PlayerController = _make_body(_at_bearing(40.0, 30.0))
	runner.set_physics_process(false)
	await step_seconds(3.0)
	var held: int = guard.get_post()
	runner.global_position = _at_bearing(200.0, POST_RADIUS * 0.5)
	await step_seconds(3.0)
	assert_eq_int(guard.get_post(), held, "the post is kept")
	assert_lt(_flat_distance(guard.controller.global_position, _at_bearing(45.0, POST_RADIUS)), 0.3, "and the guard is still on it")


## With nothing in sight and nothing remembered the guard stands where it faces.
func test_a_guard_with_nothing_to_look_at_takes_the_post_it_faces() -> void:
	_make_posts()
	var guard: TowerShooter = _make_guard(Vector3.ZERO)
	await step_seconds(3.0)
	assert_null(guard.get_target(), "nobody is on the ring")
	assert_lt(_flat_distance(guard.controller.global_position, _at_bearing(0.0, POST_RADIUS)), 0.3, "it stands at the post ahead")


## The bug this file exists for: a tower whose own railing hid the whole lane
## from the seat, on a map with nowhere else for the guard to stand.
func test_on_every_map_the_guard_has_a_line_to_the_lane_from_where_it_stands() -> void:
	var probe: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	var eye_height: float = probe.head.position.y if probe.head != null else 1.65
	probe.free()
	var aim_height: float = (load(BotMatchRunner.SHOOTER_PROFILE_PATH) as ShooterProfile).target_aim_height
	var mask: int = TestFixtures.weapon_profile().hit_mask
	for map: MapDefinition in MapCatalog.all():
		var arena: Node3D = (load(map.scene_path) as PackedScene).instantiate() as Node3D
		add_child(arena)
		await step_ticks(3)
		var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
		var stands: PackedVector3Array = GuardPosts.read(arena)
		if stands.is_empty():
			stands.append((arena.get_node(^"Tower/TowerSpawn") as Node3D).global_position)
		var eyes: PackedVector3Array = PackedVector3Array()
		for at: Vector3 in stands:
			var floor_hit: Dictionary = space.intersect_ray(
				PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, mask)
			)
			assert_false(floor_hit.is_empty(), "%s: the stand at %s has floor under it" % [map.id, at])
			if not floor_hit.is_empty():
				eyes.append((floor_hit["position"] as Vector3) + Vector3.UP * eye_height)
		var route: RingRoute = arena.get_node_or_null(^"Route") as RingRoute
		if not assert_not_null(route, "%s: the map has a route" % map.id):
			arena.free()
			continue
		var centre: Vector3 = arena.global_position
		var seen: int = 0
		for sample: int in LANE_SAMPLES:
			var angle: float = TAU * float(sample) / float(LANE_SAMPLES)
			var point: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * route.lane_radius(0)
			point.y = route.deck_height(0) + aim_height
			for eye: Vector3 in eyes:
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, mask))
				if hit.is_empty() or (hit["position"] as Vector3).distance_to(point) <= LANE_REACHED_METRES:
					seen += 1
					break
		var share: float = float(seen) / float(LANE_SAMPLES)
		print("    %s: the guard has a line to %d of %d lane samples from %d stand(s)" % [map.id, seen, LANE_SAMPLES, eyes.size()])
		assert_ge(share, LANE_SEEN_AT_LEAST, "%s: the guard can see the lane from where it stands" % map.id)
		arena.free()


## The cover bake looks from the same places the guard stands.
func test_the_cover_bake_looks_from_the_posts() -> void:
	_make_posts()
	var seat: Marker3D = Marker3D.new()
	seat.name = "TowerSpawn"
	_world.add_child(seat)
	var bake: RingBake = RingBake.new()
	_world.add_child(bake)
	bake.bake_from(_world)
	assert_eq_int(bake.get_eyes().size(), POSTS, "one eye per post")
	for eye: Vector3 in bake.get_eyes():
		assert_almost_eq(Vector2(eye.x, eye.z).length(), POST_RADIUS, 0.01, "each over a post")
	for node: Node in get_tree().get_nodes_in_group(GuardPosts.GROUP):
		node.remove_from_group(GuardPosts.GROUP)
	bake.bake_from(_world)
	assert_eq_int(bake.get_eyes().size(), 1, "with no posts the seat is the only eye")
	assert_vec3_almost_eq(bake.get_eyes()[0], bake.get_eye(), 0.001, "and it is the seat's")


# --- Fixtures -----------------------------------------------------------------

## Bearing 0 is straight ahead of a guard at yaw 0 (-Z); positive turns right.
func _at_bearing(degrees: float, radius: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(sin(angle), 0.0, -cos(angle)) * radius


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _make_posts() -> void:
	for index: int in POSTS:
		_make_post(_at_bearing(360.0 * float(index) / float(POSTS), POST_RADIUS))


func _make_post(at: Vector3) -> void:
	var post: Marker3D = Marker3D.new()
	post.add_to_group(GuardPosts.GROUP)
	_world.add_child(post)
	post.global_position = at


## The guard's body speed over the ground at each shot it takes.
func _record_shot_speeds(guard: TowerShooter) -> PackedFloat32Array:
	var speeds: PackedFloat32Array = PackedFloat32Array()
	guard.shot_taken.connect(func(_c: float) -> void:
		speeds.append(Vector2(guard.controller.velocity.x, guard.controller.velocity.z).length()))
	return speeds


func _assert_still_at_every_shot(speeds: PackedFloat32Array) -> void:
	var fastest: float = 0.0
	for speed: float in speeds:
		fastest = maxf(fastest, speed)
	assert_lt(fastest, TowerShooter.STILL_SPEED_METRES + 0.001, "no shot is taken while the body moves")


func _post_at(guard: TowerShooter) -> Vector3:
	var posts: PackedVector3Array = GuardPosts.read(_world)
	return posts[guard.get_post()] if guard.get_post() >= 0 else Vector3.INF


## A wall 3 m wide and 4 m tall at [param at], its face turned to [param bearing].
func _make_wall(at: Vector3, bearing: float) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3.0, 4.0, 0.3)
	shape.shape = box
	shape.position = Vector3.UP * 2.0
	wall.add_child(shape)
	_world.add_child(wall)
	wall.global_position = at
	wall.rotation.y = -deg_to_rad(bearing)


func _make_guard(at: Vector3) -> TowerShooter:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	var rifle: Rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	rifle.profile = TestFixtures.weapon_profile()
	body.add_child(rifle)
	var profile: ShooterProfile = ShooterProfile.new()
	profile.scan_yaw_rate = 0.0
	profile.aim_random_seed = SEED
	profile.use_optic = false
	var shooter: TowerShooter = TowerShooter.new()
	shooter.name = "GuardBrain"
	shooter.controller = body
	shooter.input = TestFixtures.bot_input_of(body)
	shooter.rifle = rifle
	shooter.profile = profile
	shooter.rules = TestFixtures.match_rules()
	shooter.target_group = MatchController.RUNNER_GROUP
	body.add_child(shooter)
	_world.add_child(body)
	shooter.configure(at, 0.0)
	return shooter


func _make_body(at: Vector3) -> PlayerController:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	body.add_to_group(MatchController.RUNNER_GROUP)
	# Placed before it enters the tree: a body that appears inside the guard lifts it.
	body.position = at
	_world.add_child(body)
	return body
