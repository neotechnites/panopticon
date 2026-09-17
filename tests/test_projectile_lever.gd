extends TestCase

## [member MatchRules.guard_projectile_speed]: the same rifle, with the round
## given time to cross the gap.
##
## The lever is the whole subject. [Rifle] asks
## [method Rifle.is_travelling_shot] once and everything downstream -- the
## raycast that became a sweep, the tracer that became a trail, the hit that
## arrived some frames later -- hangs off that one answer. So these tests are
## written as PAIRS wherever a pair is possible: one fixed piece of geometry,
## one shot fired through it twice, and the only difference between the two runs
## is the number in the rules. Anything that differs beyond the arrival time is
## the lever having changed the game rather than the clock, which is the thing
## it must never do.
##
## Every flight here is flown by explicit [method Rifle.tick] calls with
## [constant TestCase.SIM_DELTA], never by [code]_physics_process[/code] and
## never against a wall clock: a round in the air is the one part of the weapon
## whose whole subject IS elapsed time, so a test that let CI decide how much of
## it went by would be measuring the build machine.
##
## The rig lives at [constant FLOOR_TOP] metres up, on its own floor, so nothing
## the arena owns can wander into a shot line.

## The private floor's top surface, far above anything the ring occupies.
const FLOOR_TOP: float = 2000.0

## Eye height above that floor. The shot line is horizontal at this height, so a
## round that sagged would land in the floor and say so.
const EYE_HEIGHT: float = 1.6

## Where every shot in this file starts, and the rifle's own origin.
const ORIGIN: Vector3 = Vector3(0.0, FLOOR_TOP + EYE_HEIGHT, 0.0)

## Half-thickness of every test box along the shot axis, so a box placed at
## distance d is struck at [code]d - TARGET_HALF_DEPTH[/code].
const TARGET_HALF_DEPTH: float = 0.5

## The near target, in metres: the body both shot models are asked to land on.
const BODY_DISTANCE: float = 30.0

## Where the cover slab stands, well inboard of [constant BODY_DISTANCE].
const COVER_DISTANCE: float = 12.0

## A hundred metres, because [constant MatchRules.SUGGESTED_PROJECTILE_SPEED] is
## quoted in half-seconds at a hundred metres and that is the claim under test.
const LONG_DISTANCE: float = 100.0

## Length of the replayed shot line in the authority test. Deliberately NOT a
## whole number of ticks' travel, so the arrival tick is unambiguous.
const REPLAY_DISTANCE: float = 63.0

## A speed slow enough that the flight is many ticks long and fast enough to be
## a shot rather than a lob.
const SLOW_SPEED: float = 150.0

## A speed that crosses [constant COVER_DISTANCE] in a single tick. At 60 Hz
## this round moves 16.7 m per step, so the cover slab is entirely between two
## consecutive positions: a round tested by position alone is already past it.
const FAST_SPEED: float = 1000.0

## The speed the second arm of the suggested-speed test uses.
const BRISK_SPEED: float = 300.0

## A delta small enough to be "the next tick" and large enough to cross a
## boundary the weapon has already reached.
const NUDGE: float = 0.001

## Ticks a flight is given before the test gives up on it. A generous multiple
## of the longest flight here, so hitting it is a failure and never a timeout.
const MAX_FLIGHT_TICKS: int = 600

var _world: Node3D
var _rifle: Rifle
var _profile: WeaponProfile
var _rules: MatchRules

var _hits: int = 0
var _misses: int = 0
var _shots: int = 0
var _colliders: Array[Node3D] = []
var _last_hit_position: Vector3 = Vector3.ZERO


func before_each() -> void:
	# One node owns the world half of the rig: the floor, the targets, and --
	# because it is handed to Rifle.tracer_parent -- every round and every
	# streak the weapon puts in the air. Freeing it frees all of them, and
	# nothing this file launches can outlive the test that launched it.
	_world = Node3D.new()
	_world.name = "ProjectileWorld"
	add_child(_world)

	var floor_body: StaticBody3D = TestFixtures.make_floor(FLOOR_TOP)
	_world.add_child(floor_body)

	_profile = TestFixtures.weapon_profile()
	_rules = TestFixtures.match_rules()

	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(_rifle)
	# Both assigned before the instance enters the tree: Rifle._ready reads the
	# profile and seeds reload_seconds through the rules, and both objects are
	# private duplicates -- writing the lever into a shared .tres would retune
	# every later test in the same process.
	_rifle.profile = _profile
	_rifle.rules = _rules
	add_child(_rifle)

	# The rifle has no aim_source, so its own -Z is the shot line.
	_rifle.global_transform = Transform3D(Basis.IDENTITY, ORIGIN)
	# Own the clock. Rounds are advanced from tick() and from nowhere else, so a
	# physics frame spent waiting on the server does not also fly a shot.
	_rifle.set_physics_process(false)
	# Rounds and streaks hang here rather than on the scene root, so the test
	# can find what is in the air by looking at its own node.
	_rifle.tracer_parent = _world

	_rifle.target_hit.connect(_on_target_hit)
	_rifle.missed.connect(_on_missed)
	_rifle.fired.connect(_on_fired)

	# One physics frame so the floor is registered with the physics server.
	await step_ticks(1)


func after_each() -> void:
	if is_instance_valid(_rifle):
		# Before the parent goes: a round left in the array would be stepped by
		# nothing and freed by its parent, which is tidy but silent. Clearing it
		# through the weapon is the path the round reset uses.
		_rifle.clear_projectiles()
		_rifle.queue_free()
	if is_instance_valid(_world):
		_world.queue_free()


# --- The lever ----------------------------------------------------------------

## The lever changes WHEN the shot lands, and nothing else about it.
##
## One body, one distance, two shot models. Under hitscan the outcome is part of
## the trigger pull: [signal Rifle.target_hit] has already been emitted by the
## time [method Rifle.try_fire] returns. Under the lever the same trigger pull
## returns with the round still in the air, and the same body is reported some
## ticks later by the same signal with the same meaning. That is the contract
## the whole feature rests on -- nothing downstream of the weapon may be able to
## tell which model fired -- and the only honest way to assert it is to make the
## two runs differ in exactly one number.
func test_both_shot_models_land_the_same_shot() -> void:
	var body: StaticBody3D = _add_body(BODY_DISTANCE, "Body")
	await step_ticks(1)

	# --- Hitscan: the shot is over before try_fire returns.
	_rules.guard_projectile_speed = 0.0
	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")
	assert_eq_int(_hits, 1, "under hitscan the hit resolves on the firing tick")
	assert_same(_last_collider(), body, "hitscan reports the body it struck")
	assert_eq_int(
		_rifle.get_projectiles_in_flight(), 0,
		"a hitscan shot puts nothing in the air to step",
	)
	var hitscan_impact: Vector3 = _last_hit_position

	_serve_the_cycle()
	_reset_counts()

	# --- The lever: the same shot, now with a flight to fly.
	_rules.guard_projectile_speed = SLOW_SPEED
	assert_true(_rifle.try_fire(), "the weapon is ready again and takes the second shot")
	assert_eq_int(_hits, 0, "under the lever nothing has landed on the tick the trigger broke")
	assert_eq_int(_rifle.get_projectiles_in_flight(), 1, "the round is in the air instead")

	var ticks: int = _fly_until_resolved()
	assert_eq_int(_hits, 1, "the round arrives and reports the hit it always would have")
	assert_eq_int(_misses, 0, "an arrival is not also a miss")
	assert_same(
		_last_collider(), body,
		"the travelling round struck the same collider the hitscan ray did",
	)
	assert_vec3_almost_eq(
		_last_hit_position, hitscan_impact, 0.05,
		"and struck it in the same place",
	)
	assert_eq_int(
		_rifle.get_projectiles_in_flight(), 0,
		"a resolved round is taken out of the air, not left to be stepped again",
	)

	# The flight is the distance over the speed, and nothing else. Tolerance is
	# one tick because the round can only arrive on a tick boundary.
	assert_almost_eq(
		float(ticks) * SIM_DELTA,
		(BODY_DISTANCE - TARGET_HALF_DEPTH) / SLOW_SPEED,
		SIM_DELTA,
		"the round was in the air for distance / guard_projectile_speed seconds",
	)


# --- Cover --------------------------------------------------------------------

## A round in flight is stopped by what stands in front of it, at any speed.
##
## [WeaponProjectile] raycasts the segment it just crossed rather than testing
## where it now is, and this is the test that holds that line. The fast arm is
## the point: at [constant FAST_SPEED] the round moves further in one tick than
## the entire gap between the muzzle and the cover slab, so a round checked by
## POSITION would be sampled once inboard of the slab and once beyond it and
## would sail through to the body behind. It does not. The slab stops it, and
## the body -- the only thing in this scene that would cost a runner the round
## -- is never named as the collider at either speed.
##
## [b]Read the assertions, not the brief.[/b] Cover is asked for as "the round
## hits the wall and [signal Rifle.missed] is emitted". The shipped weapon does
## not do that and never has: [method Rifle._report] emits
## [signal Rifle.target_hit] with whatever the round struck, exactly as
## [method Rifle._resolve_shot] does under hitscan, and [signal Rifle.missed] is
## reserved for a round that struck NOTHING and ran out of range. Striking cover
## is therefore a hit on the cover, and a miss in the sense the MATCH cares
## about -- see [member MatchRules.guard_miss_penalty_seconds], which is spent
## by the match when the collider is not a prisoner. The invariant that actually
## protects a runner is asserted below in full: the body is never the collider.
func test_a_round_in_flight_is_stopped_by_cover() -> void:
	var cover: StaticBody3D = _add_body(COVER_DISTANCE, "Cover")
	var body: StaticBody3D = _add_body(BODY_DISTANCE, "Body")
	await step_ticks(1)

	var expected_impact: Vector3 = ORIGIN + Vector3.FORWARD * (COVER_DISTANCE - TARGET_HALF_DEPTH)

	var speeds: Array[float] = [SLOW_SPEED, FAST_SPEED]
	for speed: float in speeds:
		_rules.guard_projectile_speed = speed
		assert_true(_rifle.try_fire(), "the weapon is ready and takes the shot")
		assert_eq_int(_rifle.get_projectiles_in_flight(), 1, "a round is in the air")

		var ticks: int = _fly_until_resolved()
		assert_lt(
			float(ticks), float(MAX_FLIGHT_TICKS),
			"the round resolved rather than running to the flight cap",
		)
		assert_eq_int(_hits, 1, "the round resolved exactly once")
		assert_eq_int(
			_misses, 0,
			"striking cover is reported as a hit on the cover -- see this test's note",
		)
		assert_same(
			_last_collider(), cover,
			"the thing the round struck is the slab standing in front of it",
		)
		assert_vec3_almost_eq(
			_last_hit_position, expected_impact, 0.05,
			"and it stopped at the slab's near face, not somewhere beyond it",
		)

		_serve_the_cycle()
		_reset_counts()

	# Said once, over both speeds, because it is the claim that matters: nothing
	# behind cover was ever credited with anything.
	for collider: Node3D in _colliders:
		assert_true(collider != body, "the body behind cover is never the collider")


# --- The number on the box ----------------------------------------------------

## [constant MatchRules.SUGGESTED_PROJECTILE_SPEED] is half a second at a
## hundred metres, as advertised.
##
## [b]This test is that constant's only consumer.[/b] Nothing in the shipped
## game reads it -- it is documentation, the number worth typing into the box
## first -- and a documented number with no reader is a number that drifts from
## what it claims. So the claim is asserted here instead: at a hundred metres
## the suggested speed puts the round in the air for about half a second, which
## is what makes leading a skill and what gives a runner who reads the muzzle
## flash time to break stride. The 300 m/s arm is the contrast: a third of a
## second, fast enough that the read is much harder, which is what the suggested
## speed is a choice AGAINST.
func test_the_suggested_speed_reads_as_half_a_second_at_a_hundred_metres() -> void:
	_add_body(LONG_DISTANCE, "Body")
	await step_ticks(1)

	var flight_distance: float = LONG_DISTANCE - TARGET_HALF_DEPTH

	_rules.guard_projectile_speed = MatchRules.SUGGESTED_PROJECTILE_SPEED
	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")
	var suggested_ticks: int = _fly_until_resolved()
	assert_eq_int(_hits, 1, "the round crossed a hundred metres and landed")
	assert_between(
		float(suggested_ticks) * SIM_DELTA, 0.4, 0.6,
		"SUGGESTED_PROJECTILE_SPEED is about half a second of flight at 100 m",
	)
	# The same number from the other direction, so a changed constant fails here
	# rather than quietly widening the window above.
	assert_almost_eq(
		float(suggested_ticks) * SIM_DELTA,
		flight_distance / MatchRules.SUGGESTED_PROJECTILE_SPEED,
		SIM_DELTA,
		"and it is exactly the distance over the constant",
	)

	_serve_the_cycle()
	_reset_counts()

	_rules.guard_projectile_speed = BRISK_SPEED
	assert_true(_rifle.try_fire(), "the weapon is ready again")
	var brisk_ticks: int = _fly_until_resolved()
	assert_eq_int(_hits, 1, "the faster round landed too")
	assert_between(
		float(brisk_ticks) * SIM_DELTA, 0.30, 0.36,
		"300 m/s is a third of a second at 100 m -- a much harder read",
	)
	assert_lt(
		float(brisk_ticks), float(suggested_ticks),
		"and it is unambiguously the faster of the two",
	)


# --- Authority ----------------------------------------------------------------

## A replayed round is a picture and nothing else.
##
## This is the authority invariant in its smallest form. A client that is not
## the host still has to SHOW the round crossing the gap, and the host has
## already told it where the shot ended -- so the client flies a cosmetic round
## down that line. It flies through the same [method WeaponProjectile.advance]
## as a live one, on the same tick, which is what stops the two from drifting
## apart into two flight paths. What it must never do is arrive at a CONCLUSION:
## the hit and the miss are the host's and come on their own messages, and a
## replay that also reported would score one shot twice on one machine.
##
## The body standing in the round's path is the whole point, and this test
## proves the path is genuinely obstructed before it trusts the silence -- a
## body that turned out not to be there would make this test pass by accident
## forever. The cosmetic round flies straight past it, to the end point the
## authority resolved, and says nothing on the way.
func test_a_replayed_round_never_claims_a_hit() -> void:
	_rules.guard_projectile_speed = SLOW_SPEED

	var body: StaticBody3D = _add_body(BODY_DISTANCE, "Body")
	await step_ticks(1)

	var end_point: Vector3 = ORIGIN + Vector3.FORWARD * REPLAY_DISTANCE
	assert_same(
		_what_blocks(ORIGIN, end_point), body,
		"the replayed line really is obstructed, or this test proves nothing",
	)

	_rifle.show_remote_shot(ORIGIN, end_point, _rifle.reload_seconds)

	assert_eq_int(_rifle.get_visual_rounds_in_flight(), 1, "the replay put a round in the air")
	assert_eq_int(
		_rifle.get_projectiles_in_flight(), 0,
		"and not a live one -- a client holds no authority to spend",
	)
	assert_eq_int(_shots, 1, "the replay announces the shot, because the shot did happen")

	var replayed: WeaponProjectile = _only_round_in_world()
	assert_not_null(replayed, "the cosmetic round is reachable under the rifle's tracer parent")
	# Short-circuited rather than split: an assertion here never halts the test,
	# so a null round must not reach a method call on the following line.
	assert_true(
		replayed != null and replayed.is_cosmetic(),
		"the round is marked cosmetic, which is what strips its mask and its gravity",
	)

	var ticks: int = _fly_visual_until_clear()
	assert_lt(
		float(ticks), float(MAX_FLIGHT_TICKS),
		"the cosmetic round resolved rather than running to the flight cap",
	)
	assert_eq_int(_hits, 0, "a replayed round never emits target_hit")
	assert_eq_int(_misses, 0, "and never emits missed either -- both belong to the host")
	assert_eq_int(_shots, 1, "and it never announces a second shot on arrival")

	# It flew the WHOLE line. Stopping at the body would have taken roughly
	# BODY_DISTANCE / SLOW_SPEED instead, which this tolerance cannot absorb.
	assert_almost_eq(
		float(ticks) * SIM_DELTA,
		REPLAY_DISTANCE / SLOW_SPEED,
		SIM_DELTA,
		"the cosmetic round flew past the body to the end point the host resolved",
	)
	assert_eq_int(
		_rifle.get_visual_rounds_in_flight(), 0,
		"and was taken out of the air when it arrived",
	)


# --- The shipped lever --------------------------------------------------------

## At 0.0 the feature is not merely off, it is absent.
##
## The shipped match runs hitscan, and the cost of carrying a shot model nobody
## has switched on has to be nothing: no round, no array to walk, no cosmetic
## twin. [method Rifle.get_shot_speed] returning exactly 0.0 is the sentinel the
## rest of the game leans on -- a bot's lead computation multiplies by it, a
## replay draws its streak instantly off it -- so it is compared exactly here
## rather than approximately. It is a flag spelled as a float, not a
## measurement, and a value near zero would be a stalled round rather than an
## instant one.
func test_the_shipped_lever_puts_nothing_in_the_air() -> void:
	_add_body(BODY_DISTANCE, "Body")
	await step_ticks(1)

	_rules.guard_projectile_speed = 0.0
	assert_true(_rifle.get_shot_speed() == 0.0, "the shipped lever reads as hitscan, exactly 0.0")
	assert_false(_rifle.is_travelling_shot(), "and the weapon agrees the shot does not travel")
	assert_eq_int(_rifle.get_projectiles_in_flight(), 0, "nothing is in the air before the shot")

	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")
	assert_eq_int(_hits, 1, "the shot resolved on the firing tick, as hitscan does")

	# The whole cycle, one tick at a time, so an allocation on any single tick
	# of the firing window or the reload is caught rather than averaged away.
	var guard: int = 0
	while _rifle.get_state() != Rifle.State.READY and guard < MAX_FLIGHT_TICKS:
		_rifle.tick(SIM_DELTA)
		guard += 1
		if _rifle.get_projectiles_in_flight() != 0 or _rifle.get_visual_rounds_in_flight() != 0:
			fail("the hitscan cycle put a round in the air on tick %d" % guard)
			break
	assert_eq_int(
		int(_rifle.get_state()), int(Rifle.State.READY),
		"the full fire-and-reload cycle was served",
	)
	assert_eq_int(_rifle.get_projectiles_in_flight(), 0, "and nothing was in the air at the end")
	assert_eq_int(_rifle.get_visual_rounds_in_flight(), 0, "nor any cosmetic round")
	assert_true(_rifle.get_shot_speed() == 0.0, "the sentinel is unchanged by a cycle")


# --- Rig ----------------------------------------------------------------------

## A static box on the shot line, [param distance] metres down it.
func _add_body(distance: float, node_name: String) -> StaticBody3D:
	var body: StaticBody3D = TestFixtures.make_box_body(
		Vector3(6.0, 6.0, TARGET_HALF_DEPTH * 2.0),
		ORIGIN + Vector3.FORWARD * distance,
		node_name,
	)
	_world.add_child(body)
	return body


## Fly the weapon a tick at a time until a round reports something, and return
## how many ticks that took.
##
## Explicit deltas, never [method TestCase.step_ticks]: the rifle's physics
## process is off, so a physics frame moves nothing and a flight measured in
## them would be a flight of length zero that never ended.
func _fly_until_resolved() -> int:
	var ticks: int = 0
	while _hits + _misses == 0 and ticks < MAX_FLIGHT_TICKS:
		_rifle.tick(SIM_DELTA)
		ticks += 1
	return ticks


## The same, for a cosmetic round, which reports nothing and can only be watched
## by whether it is still in the air.
func _fly_visual_until_clear() -> int:
	var ticks: int = 0
	while _rifle.get_visual_rounds_in_flight() > 0 and ticks < MAX_FLIGHT_TICKS:
		_rifle.tick(SIM_DELTA)
		ticks += 1
	return ticks


## Run the cycle out in one step so the next shot can be fired.
func _serve_the_cycle() -> void:
	_rifle.tick(_rifle.get_time_to_ready() + NUDGE)
	assert_eq_int(
		int(_rifle.get_state()), int(Rifle.State.READY), "the cycle was served and the weapon is ready"
	)


## The single [WeaponProjectile] hanging off the rifle's tracer parent, or null
## when there is not exactly one.
##
## Found by type rather than by name: the round names its own child, not itself,
## and tracers share this parent.
func _only_round_in_world() -> WeaponProjectile:
	var found: WeaponProjectile = null
	for child: Node in _world.get_children():
		var round_shot: WeaponProjectile = child as WeaponProjectile
		if round_shot == null:
			continue
		if found != null:
			return null
		found = round_shot
	return found


## What a straight line from [param from] to [param to] runs into, or null.
##
## The premise-check for the replay test. Not a hot path and not a weapon path:
## it exists so a test that asserts a silence can first prove there was
## something to be silent about.
func _what_blocks(from: Vector3, to: Vector3) -> Node3D:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	if space == null:
		return null
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _profile.hit_mask
	query.collide_with_areas = _profile.hit_areas
	query.collide_with_bodies = true
	var result: Dictionary = space.intersect_ray(query)
	return result.get("collider", null) as Node3D


## The collider the most recent [signal Rifle.target_hit] named, or null when
## nothing has been struck yet. Never an index into an empty array: a failed
## assertion above must not take the whole run down with it.
func _last_collider() -> Node3D:
	if _colliders.is_empty():
		return null
	return _colliders[_colliders.size() - 1]


## Forget what the last shot did, so the next arm of a paired test reads its own
## outcome and not the previous one's.
func _reset_counts() -> void:
	_hits = 0
	_misses = 0
	_shots = 0


# --- Signal capture -----------------------------------------------------------

func _on_target_hit(collider: Node3D, hit_position: Vector3, _hit_normal: Vector3) -> void:
	_hits += 1
	_colliders.append(collider)
	_last_hit_position = hit_position


func _on_missed(_end_point: Vector3) -> void:
	_misses += 1


func _on_fired(_origin: Vector3, _end_point: Vector3) -> void:
	_shots += 1
