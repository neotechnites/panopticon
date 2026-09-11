extends TestCase

## [RingRunner]: the baseline prisoner, on the real arena.
##
## The greybox ring is instanced rather than stood in for by a flat plate. The
## runner's finish condition is arc travelled about the arena axis, and the track
## it holds is chosen to thread between the cover bands, so both are statements
## about [code]scenes/ring/bentham_ring.tscn[/code]'s actual geometry. A test on a
## featureless floor would keep passing after somebody moved a band of cover into
## the runner's channel.

## Simulated seconds a lap is allowed to take before the test gives up.
##
## The track is r=44.5, so the ~350 degree lap is about 272 m; at
## [member MovementProfile.ground_speed] that is 25 s, plus the second or so the
## body spends accelerating up to it. Sixty is generous without being a licence
## for a runner that has ground to a halt against something.
const LAP_BUDGET_SECONDS: float = 60.0

## Seconds of running before the drive-the-controller assertions are made: long
## enough for the body to be at speed and clear of its spawn.
const SETTLE_SECONDS: float = 2.0

## Physics ticks the arena is given to build its CSG collision before anything
## is stood on it.
const SETTLE_TICKS: int = 120

## Simulated seconds a cover-game lap is allowed to take before the test gives
## up. Generous relative to [constant LAP_BUDGET_SECONDS]: the cover game trades
## a straight line for a series of holds and crossings, and the profile the
## slide tests use below cuts patience hard but still pays for a settle after
## every crossing.
const COVER_LAP_BUDGET_SECONDS: float = 240.0

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
	# configured before that stands on nothing and falls into the pit. The arena
	# is three stacked galleries, two ramps and their walls now, so the wait is
	# generous rather than the two ticks one flat deck used to need -- and the
	# failure it prevents is silent: the body simply falls and every assertion
	# below reads a runner that never ran.
	await step_ticks(SETTLE_TICKS)

	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D

	_body = (load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	TestFixtures.silence_human_input(_body)
	# Placed before it enters the tree, exactly as MatchController does it, and
	# for exactly the same reason -- see test_round.gd.
	# A quarter of a metre up, exactly as MatchController places a body: feet on
	# the collision plane overlap the deck, and depenetration launches them.
	_body.position = start_marker.global_position + Vector3.UP * 0.25
	add_child(_body)

	_brain = _find_brain(_body)
	_profile = TestFixtures.bot_profile()
	_brain.profile = _profile
	_brain.reached_end.connect(_on_reached_end)

	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)


# --- The lap ------------------------------------------------------------------

## A runner walks the track all the way round and reports that it arrived.
func test_a_runner_completes_a_lap() -> void:
	await _run_until_finished(LAP_BUDGET_SECONDS)

	if not assert_eq_int(_finishes, 1, "the runner must reach the end exactly once"):
		# Everything below reads the finish telemetry, so there is nothing
		# meaningful left to check.
		return

	# Not exactly 1.0: the finish fires with up to
	# BotProfile.arrival_tolerance metres of arc still outstanding, which on a
	# track this size is about half a percent. Deriving the slack from the profile
	# rather than hard-coding 0.99 means retuning the tolerance retunes the test.
	var slack: float = _profile.arrival_tolerance / (TAU * _profile.track_radius)
	assert_between(
		_brain.get_progress(), 1.0 - slack * 1.2, 1.0,
		"a finished lap is complete to within the profile's arrival tolerance",
	)

	# The track is an arc, so the shortest possible path is that arc. Anything
	# much longer is the steerer hunting about it, which is the failure mode a
	# raised BotProfile.steering_gain produces.
	#
	# Asked of the ROUTE rather than reconstructed from a full circle: a lap is
	# 330 degrees, not 360 -- the remaining thirty are the ramp bay -- and
	# multiplying a route fraction by TAU was measuring a lap the arena does not
	# have.
	var route: RingRoute = _brain.get_route()
	var lap_arc: float = (
		_brain.get_progress() * TAU * _profile.track_radius
		if route == null else route.lap_metres(0)
	)
	assert_between(
		_finished_path, lap_arc * 0.95, lap_arc * 1.15,
		"the measured path should be close to the track's own arc (%.1f m)" % lap_arc,
	)

	# Sanity on the pace: the body cannot beat the ground speed, and a lap far
	# slower than that means it spent the round stuck on something.
	var fastest_possible: float = _finished_path / _body.profile.ground_speed
	assert_ge(_finished_elapsed, fastest_possible, "a lap cannot be run faster than the ground speed")
	assert_lt(_finished_elapsed, fastest_possible * 1.5, "the runner should not be stalling")

	# It must finish where the lap ends, not wherever the arc counter happened
	# to tick over: still on the track, and back by the divider.
	assert_almost_eq(
		_radius_of(_body.global_position), _profile.track_radius, 2.0,
		"the runner holds the track radius all the way to the finish",
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


# --- Sliding --------------------------------------------------------------
#
# "The bots should be sliding": a bot opens one through
# [method BotIntentSource.hold_slide], the same door a held keypress goes
# through. In order: the press really is a one-tick edge, held rather than
# bare, and re-arms correctly on release; the cover-playing runner opens a
# slide on essentially any real crossing, not just one under a confirmed
# watching guard; the BASELINE control case this file's before_each already
# builds is untouched by any of it; and a runner that slides can still finish
# its lap, sliding for long enough that it would actually be seen.

## [method BotIntentSource.hold_slide] is what [method RingRunner._maybe_slide]
## calls, and it has to do two things right or a bot's slide is real for one
## physics tick and invisible to every render frame: [member MovementProfile.slide_requires_hold]
## is on, so [method PlayerController._update_slide_exit] closes a slide again
## on the very tick it opened unless [member MoveIntent.slide_held] is also
## true, not just [member MoveIntent.slide_pressed] -- the bug this test pins.
##
## So, in order: a fresh [code]hold_slide(true)[/code] raises the one-tick edge
## AND the held level; the edge is gone by the next poll but the level survives
## it, because [method BotIntentSource.poll] only ever clears the edge fields;
## a second [code]hold_slide(true)[/code] while already held raises no new
## edge, which is what stops a bot from re-arming its own held key; and
## [code]hold_slide(false)[/code] followed by [code]hold_slide(true)[/code]
## does raise a fresh edge, which is what lets the NEXT crossing's slide open
## at all.
func test_bot_intent_source_hold_slide_is_an_edge_that_persists_until_released() -> void:
	# IntentSource extends Node -- built and parented to self like every other
	# fixture in this file, so the runner frees it rather than leaking it.
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
	assert_false(
		still_held.slide_pressed,
		"asking to hold while already held must not raise a second edge",
	)

	input.hold_slide(false)
	var released: MoveIntent = input.poll(SIM_DELTA)
	assert_false(released.slide_pressed, "releasing is not itself a press")
	assert_false(released.slide_held, "releasing must drop the held level")

	input.hold_slide(true)
	var re_pressed: MoveIntent = input.poll(SIM_DELTA)
	assert_true(re_pressed.slide_pressed, "holding again after a release must raise a fresh edge")


## The BASELINE lap is the control case the whole rewrite is measured against,
## and it must stay exactly what it was: no cover awareness, no slide. Nothing
## in this file's slide additions lives outside
## [method RingRunner._begin_cross], [method RingRunner._tick_cross],
## [method RingRunner._maybe_slide] and
## [method RingRunner._tick_slide_release], and none of them run unless
## [method RingRunner.is_playing_cover] is true.
##
## [b]The baseline is asked for rather than assumed.[/b] This test used to take
## [method before_each]'s runner as already being the control case, and it is
## not: [code]scenes/bot/ring_runner.tscn[/code] ships
## [code]default_runner_profile.tres[/code], which is the prisoner that PLAYS
## the game -- the right default for a bot dropped into the world, and the wrong
## one to measure a control case against. So the profile is installed here, and
## the assertion below is that it took.
func test_the_baseline_runner_never_presses_slide() -> void:
	var baseline: RunnerProfile = RunnerProfile.new()
	baseline.behaviour = RunnerProfile.Behaviour.BASELINE
	_brain.runner_profile = baseline
	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D
	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)
	assert_false(_brain.is_playing_cover(), "the control case is in force")

	await step_seconds(SETTLE_SECONDS)

	assert_false(_body.is_sliding(), "the baseline runner must never open a slide")
	assert_eq_int(_brain.get_slides_attempted(), 0, "the baseline runner must never even try to")


## A cover-playing runner slides across real open ground -- not only when it
## happens to believe a guard is watching -- and still finishes the lap, with a
## slide that lasts long enough to actually be seen.
##
## The guard built by [method _make_guard] is a real [TowerShooter] --
## [RunnerPerception] finds threats by casting to that class, so nothing looser
## registers -- which is what puts the runner into the cover state machine at
## all. It never acquires or fires (see [method _make_guard]), because this
## test is about the runner's decision to slide, not about whether it believes
## it is being watched at the instant it decides: [method RingRunner._begin_cross]
## no longer asks [method RunnerPerception.believes_watched] at all, so nothing
## here has to force that belief either.
func test_a_runner_slides_across_open_ground_and_the_slide_is_visible() -> void:
	_make_guard()

	_brain.runner_profile = _make_fast_cover_profile()
	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D
	# Re-arm with the cover profile now attached; before_each's own configure()
	# ran before this test could set it and resolved the baseline instead.
	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)
	assert_true(_brain.is_playing_cover(), "the runner_profile set above should put the runner in COVER")

	var slide_starts: int = 0
	var first_start_frame: int = -1
	var first_end_frame: int = -1
	_body.slide_started.connect(func(_entry_speed: float) -> void:
		slide_starts += 1
		if first_start_frame < 0:
			first_start_frame = Engine.get_physics_frames()
	)
	_body.slide_ended.connect(func() -> void:
		if first_start_frame >= 0 and first_end_frame < 0:
			first_end_frame = Engine.get_physics_frames()
	)

	await _run_until_finished(COVER_LAP_BUDGET_SECONDS)

	if not assert_eq_int(_finishes, 1, "a runner that slides must still reach the end exactly once"):
		return

	assert_gt(_brain.get_crossings(), 0, "the cover game should have made at least one crossing")
	assert_gt(
		_brain.get_slides_attempted(), 0,
		"a lap of real crossings should open at least one slide with the shipped exposure floor",
	)
	assert_gt(
		slide_starts, 0,
		"PlayerController itself should have entered the slide state -- not merely been asked to",
	)
	assert_le(
		_brain.get_slides_attempted(), _brain.get_crossings(),
		"a slide is opened at most once per crossing, so this can never exceed the crossing count",
	)

	if assert_ge(first_start_frame, 0, "the first slide should have a recorded start") \
		and assert_ge(first_end_frame, first_start_frame, "the first slide should have a recorded end"):
		# Ten ticks is a sixth of a second at SIM_HZ -- well under
		# MovementProfile.slide_max_duration (1.0 s, the usual way a bot's slide
		# ends, since slide_friction rarely bleeds it down to slide_exit_speed
		# that fast) and comfortably more than "a couple of ticks", the failure
		# this pins: a slide that opens and closes within the tick it started,
		# which no render frame would ever sample as sliding.
		assert_ge(
			first_end_frame - first_start_frame, 10,
			"a bot's slide should last long enough to actually be seen, not open and close in a couple of ticks",
		)


## A bot's slide is followed by RUNNING, never by a crouch-walk.
##
## [b]The bug this pins, in the author's words:[/b] [i]"it looks like the crouch
## animation gets played in the last 2/3s of a slide instead of the slide
## animation."[/i] The animation was telling the truth. The key does two things
## and which one depends on how long it is down: a slide ends on
## [member MovementProfile.slide_max_duration], the crouch has no timer, so a
## key still held when the slide's second is spent legitimately becomes a
## crouch. The brain held it for the whole crossing, so every slide was followed
## by the body crouch-walking the rest of the open ground at
## [member MovementProfile.crouch_speed] -- slow, in the one place a prisoner
## cannot afford to be slow.
##
## [method RingRunner._tick_slide_release] now lets go on the tick the slide
## ends, so the count below is zero: not "few", not "brief". A bot has no reason
## to crouch at all -- nothing in the cover game ever asks for one -- so any
## crouched tick a lap produces is this bug and no other.
func test_a_bots_slide_is_never_followed_by_a_crouch() -> void:
	_make_guard()

	_brain.runner_profile = _make_fast_cover_profile()
	var start_marker: Marker3D = _arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	var end_marker: Marker3D = _arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D
	_brain.configure(_arena.global_position, start_marker.global_position, end_marker.global_position)

	var crouched_ticks: int = 0
	var slid_ticks: int = 0
	var budget_ticks: int = int(COVER_LAP_BUDGET_SECONDS * SIM_HZ)
	for _tick: int in budget_ticks:
		if _finishes > 0:
			break
		await step_ticks(1)
		if _body.is_crouching():
			crouched_ticks += 1
		if _body.is_sliding():
			slid_ticks += 1

	assert_gt(slid_ticks, 0, "the runner slid at least once, or there is nothing to be after")
	assert_eq_int(
		crouched_ticks, 0,
		"a bot must never crouch: the slide key comes up when the slide ends, not when the crossing does",
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


## A real [TowerShooter], standing at TowerSpawn, built from the same three
## parts [BotTowerSeat] wires up for a headless match -- a [PlayerController],
## a [BotIntentSource] and a [Rifle] -- minus the match around them, because
## [RunnerPerception] only ever asks whether a [TowerShooter] exists and is
## processing, never how it got there.
##
## [member ShooterProfile.scan_yaw_rate] is zeroed so the guard's facing never
## drifts off whatever [method TowerShooter.configure] gave it, and
## [member TowerShooter.target_group] is pointed at a group nothing joins, so
## the guard can never acquire the runner under test and fire -- this fixture
## exists to give [RunnerPerception] a threat to find, not to referee a shot.
func _make_guard() -> TowerShooter:
	var tower_spawn: Marker3D = _arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D

	var body: PlayerController = (
		load(TestFixtures.PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as PlayerController
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

	add_child(body)
	shooter.configure(tower_spawn.global_position, 0.0)
	return shooter


## A cover-playing [RunnerProfile] that moves through the state machine fast,
## so the test's budget is spent on crossings rather than on patience.
##
## Perception is left at its shipped defaults deliberately -- the slide
## decision no longer reads [method RunnerPerception.believes_watched] at all
## (see [method RingRunner._begin_cross]), so there is nothing about the
## guard's attention this fixture needs to pin. [member RunnerProfile.slide_min_exposed_metres]
## is likewise left at its shipped default: the point of this test is that the
## default is now low enough to fire on an ordinary lap, not that some special
## low value can be found that makes it fire.
func _make_fast_cover_profile() -> RunnerProfile:
	var profile: RunnerProfile = RunnerProfile.new()
	profile.behaviour = RunnerProfile.Behaviour.COVER
	profile.perception_seed = 20260910
	profile.min_hold_seconds = 0.1
	profile.max_hold_seconds = 1.0
	profile.break_confidence_threshold = 0.0
	return profile

