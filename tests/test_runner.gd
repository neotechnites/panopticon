extends TestCase

## [RunnerBrain] and [RingBake] on the real arena: what the bake knows about the
## map, and what the prisoner does with it.

## The lap is about 320 m of mesh path with four pad flights and eight hops in
## it; at ground speed that is 30 s. Sixty is generous without being a licence
## for a runner that has ground to a halt against something.
const LAP_BUDGET_SECONDS: float = 60.0
const SETTLE_SECONDS: float = 2.0
## Physics ticks the arena is given to build its collision before anything is stood on it.
const SETTLE_TICKS: int = 120
const COVER_REACT_SECONDS: float = 1.5

var _arena: Node3D
var _body: PlayerController
var _brain: RunnerBrain
var _profile: BotProfile

var _finishes: int = 0
var _finished_elapsed: float = 0.0
var _finished_path: float = 0.0


func before_each() -> void:
	_arena = TestFixtures.make_arena()
	add_child(_arena)
	await step_ticks(SETTLE_TICKS)

	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D

	_body = (load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	TestFixtures.silence_human_input(_body)
	_body.position = start_marker.global_position + Vector3.UP * 0.25
	# Under the ARENA: RingBake finds the level to bake by walking up to the
	# topmost Node3D above the body, and a bake keyed to the tree root would
	# outlive every arena in the run.
	_arena.add_child(_body)

	_brain = _find_brain(_body)
	_profile = TestFixtures.bot_profile()
	_brain.profile = _profile
	_brain.reached_end.connect(_on_reached_end)

	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)
	# configure() bakes; the region is parented deferred, so let that land.
	await step_ticks(2)


# --- The bake -----------------------------------------------------------------

## Every trap and the pit are carved out: the nearest walkable point to a lethal
## volume is never itself lethal, and the mesh stops short of the inner rim.
func test_the_bake_carves_every_lethal_volume_and_the_drops() -> void:
	var bake: RingBake = _brain.get_navigation()
	if not assert_not_null(bake, "the runner baked the arena") or not assert_true(bake.is_ready(), "and the mesh answers"):
		return
	var traps: int = 0
	for node: Node in _arena.find_children("*", "TrapVolume", true, false):
		var trap: TrapVolume = node as TrapVolume
		var nearest: Vector3 = bake.snap(trap.global_position)
		assert_false(bake.is_lethal(nearest), "the mesh nearest %s stands clear of it" % trap.get_path())
		traps += 1
	assert_gt(traps, 0, "the arena has traps to carve")

	var route: RingRoute = _arena.get_node("Route") as RingRoute
	var centre: Vector3 = _arena.global_position
	for degrees: float in [30.0, 100.0, 200.0, 280.0]:
		var angle: float = deg_to_rad(degrees)
		var inside: Vector3 = centre + Vector3(cos(angle) * 40.0, route.deck_height(0), sin(angle) * 40.0)
		var edge: Vector3 = bake.snap(inside)
		assert_gt(
			Vector2(edge.x - centre.x, edge.z - centre.z).length(), route.level_at(0).inner_radius + 0.5,
			"at %.0f degrees the mesh stops short of the pit" % degrees,
		)


## The pads and the stepping stones are links, and together they join the start to the portal.
func test_the_bake_links_the_whole_lap_into_one_path() -> void:
	var bake: RingBake = _brain.get_navigation()
	if not assert_true(bake != null and bake.is_ready(), "the mesh answers"):
		return
	var start: Vector3 = (_arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D).global_position
	var end: Vector3 = (_arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D).global_position
	var path: RingPath = RingPath.new()
	var layers: int = RingBake.LAYER_WALK | RingBake.LAYER_PAD | RingBake.LAYER_EASY_JUMP | RingBake.LAYER_HARD_JUMP
	if not assert_true(bake.plan(start, end, layers, path), "the mesh reaches the portal from the start"):
		return
	var pads: int = 0
	var jumps: int = 0
	for index: int in path.size():
		if path.links[index] < 0:
			continue
		if bake.get_link(path.links[index]).kind == RingBake.LinkKind.PAD:
			pads += 1
		else:
			jumps += 1
	assert_gt(pads, 0, "the lap flies at least one pad")
	assert_gt(jumps, 0, "and hops at least one gap")
	var route: RingRoute = _arena.get_node("Route") as RingRoute
	var metres: float = path.metres_between(0, path.size() - 1)
	assert_between(metres, route.lap_metres(0) * 0.9, route.lap_metres(0) * 1.3, "and it is a lap, not a detour")


## A cover point hides a standing body from the guard's eye and stands clear of lava.
func test_cover_points_hide_a_body_from_the_eye_and_stand_clear_of_lava() -> void:
	var bake: RingBake = _brain.get_navigation()
	if not assert_true(bake != null and bake.is_ready(), "the mesh answers"):
		return
	assert_gt(bake.get_cover_count(), 20, "the arena has cover on it")
	var space: PhysicsDirectSpaceState3D = _arena.get_world_3d().direct_space_state
	var hidden: int = 0
	for index: int in bake.get_cover_count():
		var point: Vector3 = bake.cover_point(index)
		assert_false(bake.is_lethal(point, 1.0), "cover %d stands a metre clear of anything lethal" % index)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			bake.get_eye(), point + Vector3.UP * RingBake.COVER_CHEST_METRES, RingBake.STATIC_COLLIDER_MASK
		)
		if not space.intersect_ray(query).is_empty():
			hidden += 1
	assert_eq_int(hidden, bake.get_cover_count(), "every cover point is blocked from the eye at chest height")


## Two decks in one sample column used to collapse to whichever the previous deck
## was, so a column carrying a low and a high deck emitted its low one twice.
func test_the_bake_emits_each_deck_of_a_sample_column_once() -> void:
	var bake: RingBake = _brain.get_navigation()
	if not assert_true(bake != null and bake.is_ready(), "the mesh answers"):
		return
	var count: int = bake.get_cover_count()
	if not assert_gt(count, 20, "the arena has cover on it"):
		return
	var duplicates: int = 0
	for index: int in count:
		var point: Vector3 = bake.cover_point(index)
		for other: int in range(index + 1, count):
			var twin: Vector3 = bake.cover_point(other)
			if (
				absf(twin.x - point.x) < RingBake.COVER_SAME_DECK_METRES
				and absf(twin.z - point.z) < RingBake.COVER_SAME_DECK_METRES
				and absf(twin.y - point.y) < RingBake.COVER_SAME_DECK_METRES
			):
				duplicates += 1
	assert_eq_int(duplicates, 0, "no sample column emits the same deck twice")


## Cover is shadow with a lit border. A deck the eye has no line into anywhere is a
## floor of its own, not cover: there is no sight line there for a runner to break,
## and nearest_cover_ahead refuses the point anyway for being off the runner's deck.
func test_every_cover_deck_is_one_the_eye_can_see_somewhere() -> void:
	var bake: RingBake = _brain.get_navigation()
	if not assert_true(bake != null and bake.is_ready(), "the mesh answers"):
		return
	var count: int = bake.get_cover_count()
	if not assert_gt(count, 20, "the arena has cover on it"):
		return
	# The box the cover itself occupies, opened out by eight samples so a deck whose
	# lit ground lies just past the shadow still counts. Nothing here knows a map.
	var margin: float = RingBake.COVER_SPACING_METRES * 8.0
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	var decks: Dictionary = {}
	for index: int in count:
		var point: Vector3 = bake.cover_point(index)
		low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
		decks[roundi(point.y)] = true
	var space: PhysicsDirectSpaceState3D = _arena.get_world_3d().direct_space_state
	for deck: int in decks:
		var lit: bool = false
		var x: float = low.x - margin
		while x <= high.x + margin and not lit:
			var z: float = low.y - margin
			while z <= high.y + margin and not lit:
				var height: float = bake.height_at(Vector3(x, float(deck), z))
				if not is_nan(height) and absf(height - float(deck)) <= 1.0:
					var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
						bake.get_eye(),
						Vector3(x, height, z) + Vector3.UP * RingBake.COVER_CHEST_METRES,
						RingBake.STATIC_COLLIDER_MASK
					)
					lit = space.intersect_ray(query).is_empty()
				z += RingBake.COVER_SPACING_METRES
			x += RingBake.COVER_SPACING_METRES
		assert_true(lit, "the eye has a line onto the deck at y %d that carries cover" % deck)


# --- The lap ------------------------------------------------------------------

## A runner runs the track all the way round, pads and stones included, and reports it.
func test_a_runner_completes_a_lap() -> void:
	await _run_until_finished(LAP_BUDGET_SECONDS)
	if not assert_eq_int(_finishes, 1, "the runner must reach the end exactly once"):
		return
	var slack: float = _profile.arrival_tolerance / (TAU * _profile.track_radius)
	assert_between(_brain.get_progress(), 1.0 - slack * 1.2, 1.0, "a finished lap is complete")
	var lap_arc: float = _brain.get_route().lap_metres(0)
	assert_between(_finished_path, lap_arc * 0.9, lap_arc * 1.3, "the path is the lap (%.1f m)" % lap_arc)
	var fastest_possible: float = _finished_path / _body.profile.ground_speed
	assert_ge(_finished_elapsed, fastest_possible, "a lap cannot be run faster than the ground speed")
	assert_lt(_finished_elapsed, fastest_possible * 1.6, "the runner should not be stalling")
	assert_gt(_brain.get_flights(), 3, "and it flew the links rather than walking round them")


## The brain writes intent; the shared [PlayerController] does the moving.
## Freeze the controller and the body must stop dead even though the brain is still running.
func test_the_runner_drives_the_shared_player_controller() -> void:
	assert_same(_brain.controller, _body, "the brain drives the PlayerController it was given")
	assert_same(_brain.get_parent(), _body, "the brain is a child of the body it drives")
	assert_same(_body.intent_source, _brain.input, "the controller's intent source is the brain's BotIntentSource")

	await step_seconds(SETTLE_SECONDS)

	assert_gt(_body.get_horizontal_speed(), 4.0, "the runner should be up to speed")
	var wish: Vector2 = _brain.input.command.move_direction
	assert_gt(wish.length(), 0.1, "the brain is asking the body to move")
	assert_le(wish.length(), 1.0 + 1e-4, "and never asks for more than a full stick")

	_body.set_physics_process(false)
	var frozen_at: Vector3 = _body.global_position
	var frozen_velocity: Vector3 = _body.velocity
	await step_ticks(30)

	assert_true(_brain.is_physics_processing(), "the brain is still thinking")
	assert_gt(frozen_velocity.length(), 4.0, "the body still holds the velocity it had")
	assert_vec3_almost_eq(_body.global_position, frozen_at, 1e-4, "with the controller stopped, nothing else moves the body")

	_body.set_physics_process(true)
	await step_ticks(30)
	assert_gt(_body.global_position.distance_to(frozen_at), 1.0, "the body moves again once the controller is processing")


## A bot never crouches: nothing in the brain asks for one, and a slide key held
## past its slide is the only way a crouch happens by accident.
func test_a_bot_never_crouches() -> void:
	var crouched_ticks: int = 0
	for _tick: int in int(20.0 * SIM_HZ):
		await step_ticks(1)
		if _body.is_crouching():
			crouched_ticks += 1
	assert_eq_int(crouched_ticks, 0, "a bot must never crouch")


# --- The intent source --------------------------------------------------------

## [method BotIntentSource.hold_slide] raises a one-tick edge and a held level that outlives it.
func test_bot_intent_source_hold_slide_is_an_edge_that_persists_until_released() -> void:
	var input: BotIntentSource = BotIntentSource.new()
	add_child(input)

	input.hold_slide(true)
	var first: MoveIntent = input.poll(SIM_DELTA)
	assert_true(first.slide_pressed, "the tick of the press should read true")
	assert_true(first.slide_held, "the same tick must also report the key held")

	var second: MoveIntent = input.poll(SIM_DELTA)
	assert_false(second.slide_pressed, "the edge must be gone the tick after the press")
	assert_true(second.slide_held, "the held level must survive a poll with nothing re-pressed")

	input.hold_slide(true)
	var still_held: MoveIntent = input.poll(SIM_DELTA)
	assert_false(still_held.slide_pressed, "asking to hold while already held must not raise a second edge")

	input.hold_slide(false)
	var released: MoveIntent = input.poll(SIM_DELTA)
	assert_false(released.slide_pressed, "releasing is not itself a press")
	assert_false(released.slide_held, "releasing must drop the held level")

	input.hold_slide(true)
	var re_pressed: MoveIntent = input.poll(SIM_DELTA)
	assert_true(re_pressed.slide_pressed, "holding again after a release must raise a fresh edge")


# --- Cover --------------------------------------------------------------------

## Shot at, a prisoner goes to the nearest cover ahead, waits, and runs again.
func test_a_runner_shot_at_takes_cover_and_then_runs_again() -> void:
	var guard: TowerShooter = _make_guard()
	var cover: RunnerProfile = RunnerProfile.new()
	cover.behaviour = RunnerProfile.Behaviour.COVER
	cover.perception_seed = 20260910
	cover.boldness = 1.0
	cover.cover_patience_seconds = 1.0
	_brain.runner_profile = cover
	_reconfigure()
	# A second of running: the perception has found the guard and the runner is bold enough to keep going.
	await step_seconds(1.0)
	assert_true(_brain.get_perception().has_threat(), "the runner knows there is a guard")
	assert_eq_int(int(_brain.get_state()), int(RunnerBrain.State.RUN), "a bold runner keeps running while merely watched")

	# The report of a shot that lands beside it.
	guard.rifle.fired.emit(guard.controller.global_position, _body.global_position + Vector3.RIGHT)
	var took_cover: bool = false
	for _tick: int in int(COVER_REACT_SECONDS * SIM_HZ):
		await step_ticks(1)
		if _brain.get_state() == RunnerBrain.State.TAKE_COVER:
			took_cover = true
			break
	assert_true(took_cover, "a runner that was shot at heads for cover")
	assert_gt(_brain.get_covers(), 0, "and counts the cover it took")

	var ran_again: bool = false
	for _tick: int in int((cover.cover_patience_seconds + 4.0) * SIM_HZ):
		await step_ticks(1)
		if _brain.get_state() != RunnerBrain.State.TAKE_COVER:
			ran_again = true
			break
	assert_true(ran_again, "and leaves cover again once its patience is spent")


## The route into cover is the runner's own. The cover search plans into scratch that the
## next search clears; sharing that scratch's arrays once emptied the route under the cursor.
func test_the_cover_route_survives_the_next_cover_search() -> void:
	var guard: TowerShooter = _make_guard()
	var cover: RunnerProfile = RunnerProfile.new()
	cover.behaviour = RunnerProfile.Behaviour.COVER
	cover.perception_seed = 20260910
	cover.boldness = 1.0
	_brain.runner_profile = cover
	_reconfigure()
	await step_seconds(1.0)
	guard.rifle.fired.emit(guard.controller.global_position, _body.global_position + Vector3.RIGHT)
	for _tick: int in int(COVER_REACT_SECONDS * SIM_HZ):
		await step_ticks(1)
		if _brain.get_state() == RunnerBrain.State.TAKE_COVER:
			break
	assert_eq_int(int(_brain.get_state()), int(RunnerBrain.State.TAKE_COVER), "the runner is on its way to cover")
	var corners: int = _brain._path.size()
	assert_gt(corners, 0, "with a route to it")

	# What the next search does first, whether or not it finds anything.
	_brain._cover_path.clear()
	assert_eq_int(_brain._path.size(), corners, "the route into cover is untouched")
	await step_ticks(3)
	assert_true(_brain._path.cursor < _brain._path.size(), "and the cursor still points at a corner of it")


## The baseline prisoner ignores the guard entirely: the control case every claim is measured against.
func test_the_baseline_runner_never_takes_cover() -> void:
	var guard: TowerShooter = _make_guard()
	var baseline: RunnerProfile = RunnerProfile.new()
	baseline.behaviour = RunnerProfile.Behaviour.BASELINE
	_brain.runner_profile = baseline
	_reconfigure()
	assert_false(_brain.is_playing_cover(), "the control case is in force")
	await step_seconds(1.0)
	guard.rifle.fired.emit(guard.controller.global_position, _body.global_position + Vector3.RIGHT)
	for _tick: int in int(COVER_REACT_SECONDS * SIM_HZ):
		await step_ticks(1)
		assert_eq_int(int(_brain.get_state()), int(RunnerBrain.State.RUN), "the baseline runner keeps running")
	assert_eq_int(_brain.get_covers(), 0, "and never took cover")


# --- Helpers ------------------------------------------------------------------

func _on_reached_end(elapsed_seconds: float, path_length: float) -> void:
	_finishes += 1
	_finished_elapsed = elapsed_seconds
	_finished_path = path_length


func _run_until_finished(budget_seconds: float) -> void:
	for _tick: int in int(budget_seconds * SIM_HZ):
		if _finishes > 0:
			return
		await step_ticks(1)


func _reconfigure() -> void:
	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D
	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)


func _find_brain(body: Node) -> RunnerBrain:
	for child: Node in body.get_children():
		var brain: RunnerBrain = child as RunnerBrain
		if brain != null:
			return brain
	return null


## A real [TowerShooter] at TowerSpawn that never acquires or fires: a threat for
## [RunnerPerception] to find, and a rifle whose report the test can fake.
func _make_guard() -> TowerShooter:
	var tower_spawn: Marker3D = _arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D

	var body: PlayerController = (load(TestFixtures.PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	TestFixtures.silence_human_input(body)
	body.profile = TestFixtures.movement_profile()

	var input: BotIntentSource = BotIntentSource.new()
	input.name = "GuardInput"
	body.add_child(input)
	body.intent_source = input

	var rifle: Rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	rifle.profile = TestFixtures.weapon_profile()
	body.add_child(rifle)

	var shooter_profile: ShooterProfile = ShooterProfile.new()
	shooter_profile.scan_yaw_rate = 0.0

	var shooter: TowerShooter = TowerShooter.new()
	shooter.name = "GuardBrain"
	shooter.controller = body
	shooter.input = input
	shooter.rifle = rifle
	shooter.profile = shooter_profile
	shooter.target_group = &"nobody_in_this_test"
	body.add_child(shooter)

	_arena.add_child(body)
	shooter.configure(tower_spawn.global_position, 0.0)
	return shooter
