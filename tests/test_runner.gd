extends TestCase

## [RingRunner]: the baseline prisoner, on the real arena.
##
## The greybox ring is instanced rather than stood in for by a flat plate. The
## runner's finish condition is arc travelled about the arena axis and its lane
## is chosen to thread between the cover bands, so both are statements about
## [code]scenes/ring/test_ring.tscn[/code]'s actual geometry. A test on a
## featureless floor would keep passing after somebody moved a cover lane into
## the runner's channel.

## Simulated seconds a lap is allowed to take before the test gives up.
##
## The default lane is r=44.5, so the ~350 degree lap is about 272 m; at
## [member MovementProfile.walk_speed] that is 34 s, plus the second or so the
## body spends accelerating up to it. Sixty is generous without being a licence
## for a runner that has ground to a halt against something.
const LAP_BUDGET_SECONDS: float = 60.0

## Seconds of running before the drive-the-controller assertions are made: long
## enough for the body to be at speed and clear of its spawn.
const SETTLE_SECONDS: float = 2.0

var _arena: Node3D
var _body: PlayerController
var _brain: RingRunner
var _profile: BotProfile

var _finishes: int = 0
var _finished_elapsed: float = 0.0
var _finished_path: float = 0.0


func before_each() -> void:
	_arena = TestFixtures.make_arena()
	add_child(_arena)
	# CSG builds its collision on the first frames it is in the tree; a runner
	# configured before that stands on nothing and falls into the pit.
	await step_ticks(2)

	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D

	_body = (load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	TestFixtures.silence_human_input(_body)
	# Placed before it enters the tree, exactly as MatchController does it, and
	# for exactly the same reason -- see test_round.gd.
	_body.position = start_marker.global_position
	add_child(_body)

	_brain = _find_brain(_body)
	_profile = TestFixtures.bot_profile()
	_brain.profile = _profile
	_brain.reached_end.connect(_on_reached_end)

	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)


# --- The lap ------------------------------------------------------------------

## A runner walks its lane all the way round and reports that it arrived.
func test_a_runner_completes_a_lap() -> void:
	await _run_until_finished(LAP_BUDGET_SECONDS)

	if not assert_eq_int(_finishes, 1, "the runner must reach the end exactly once"):
		# Everything below reads the finish telemetry, so there is nothing
		# meaningful left to check.
		return

	# Not exactly 1.0: the finish fires with up to
	# BotProfile.arrival_tolerance metres of arc still outstanding, which on a
	# lane this size is about half a percent. Deriving the slack from the profile
	# rather than hard-coding 0.99 means retuning the tolerance retunes the test.
	var slack: float = _profile.arrival_tolerance / (TAU * _profile.lane_radius)
	assert_between(
		_brain.get_progress(), 1.0 - slack * 1.2, 1.0,
		"a finished lap is complete to within the profile's arrival tolerance",
	)

	# The lane is a circle, so the shortest possible path is its arc. Anything
	# much longer is the steerer hunting about the lane, which is the failure
	# mode a raised BotProfile.steering_gain produces.
	var lap_arc: float = _brain.get_progress() * TAU * _profile.lane_radius
	assert_between(
		_finished_path, lap_arc * 0.95, lap_arc * 1.15,
		"the measured path should be close to the lane's own arc (%.1f m)" % lap_arc,
	)

	# Sanity on the pace: the body cannot beat walk speed on the ground, and a
	# lap far slower than that means it spent the round stuck on something.
	var fastest_possible: float = _finished_path / _profile_walk_speed()
	assert_ge(_finished_elapsed, fastest_possible, "a lap cannot be run faster than walk speed")
	assert_lt(_finished_elapsed, fastest_possible * 1.5, "the runner should not be stalling")

	# It must finish where the lap ends, not wherever the arc counter happened
	# to tick over: still on its own lane radius, and back by the divider.
	assert_almost_eq(
		_radius_of(_body.global_position), _profile.lane_radius, 2.0,
		"the runner holds its lane radius all the way to the finish",
	)


# --- The hard rule of the file ------------------------------------------------

## The brain writes intent; the shared [PlayerController] does the moving.
##
## [RingRunner] owns no movement numbers and never calls
## [code]move_and_slide[/code]: it fills a [MoveIntent] and the same controller
## a human drives applies the same Quake physics to it. That is the only reason
## a headless bot match is evidence about the shipped game rather than about a
## second, private movement system.
##
## The proof is the freeze below. Stop the controller's physics processing and
## the body must stop dead even though the brain is still running and still
## writing intent every tick -- because nothing else in the runner scene is
## capable of moving it. A brain that had grown its own integrator would sail on.
func test_the_runner_drives_the_shared_player_controller() -> void:
	assert_same(_brain.controller, _body, "the brain drives the PlayerController it was given")
	assert_same(_brain.get_parent(), _body, "the brain is a child of the body it drives")
	assert_same(
		_body.intent_source, _brain.input,
		"the controller's intent source is the brain's BotIntentSource",
	)

	await step_seconds(SETTLE_SECONDS)

	assert_gt(_body.get_horizontal_speed(), 4.0, "the runner should be up to speed")
	assert_vec2_eq(
		_brain.input.command.move_direction, Vector2(0.0, 1.0),
		"the baseline runner holds full forward, unconditionally",
	)

	# --- Freeze the body, leave the brain running ---
	_body.set_physics_process(false)
	var frozen_at: Vector3 = _body.global_position
	var frozen_velocity: Vector3 = _body.velocity
	await step_ticks(30)

	assert_true(_brain.is_physics_processing(), "the brain is still thinking")
	assert_gt(frozen_velocity.length(), 4.0, "the body still holds the velocity it had")
	assert_vec3_almost_eq(
		_body.global_position, frozen_at, 1e-4,
		"with the controller stopped, nothing else moves the body",
	)

	# --- And it starts again ---
	_body.set_physics_process(true)
	await step_ticks(30)
	assert_gt(
		_body.global_position.distance_to(frozen_at), 1.0,
		"the body moves again once the controller is processing",
	)


# --- Helpers ------------------------------------------------------------------

func _on_reached_end(elapsed_seconds: float, path_length: float) -> void:
	_finishes += 1
	_finished_elapsed = elapsed_seconds
	_finished_path = path_length


## Step until the runner reports a finish or the budget runs out.
func _run_until_finished(budget_seconds: float) -> void:
	var budget_ticks: int = int(budget_seconds * SIM_HZ)
	for _tick: int in budget_ticks:
		if _finishes > 0:
			return
		await step_ticks(1)


func _find_brain(body: Node) -> RingRunner:
	for child: Node in body.get_children():
		var brain: RingRunner = child as RingRunner
		if brain != null:
			return brain
	return null


func _radius_of(point: Vector3) -> float:
	var centre: Vector3 = _arena.global_position
	return Vector2(point.x - centre.x, point.z - centre.z).length()


## The ground speed the runner's body is actually capable of, read from the
## movement profile the shipped player scene carries rather than restated here.
func _profile_walk_speed() -> float:
	return _body.profile.get_ground_speed(_profile.wants_sprint())
