extends TestCase

## The human-like tower guard: its reaction sample, its lead error, its decoy
## suspicion, and the skill lever that scales them travelling like any rule.

const SAMPLES: int = 400
const SEED: int = 20260914

## The band the projectile hit rate must hold against the hitscan one, as a
## ratio: the projectile rate over the hitscan rate.
##
## Deliberately wide, and it stays wide on purpose. Leading a round that has to
## fly is a DIFFERENT SKILL from tracking one that arrives, and
## [method TowerShooter._track] says so: the guard's lead misjudgement is taken
## as a fraction of the WHOLE of the longer lead, so a travelling round costs it
## accuracy at the same moment as the lead buys accuracy back. The two models
## have no reason to agree closely and a tighter band would go red on any honest
## retune of [member ShooterProfile.lead_error_seconds] or of the speed itself,
## which is tuning and not a bug. What this band catches is a COLLAPSE: a guard
## that stops leading at all and puts every round where the runner already was.
const HIT_RATE_BAND_LOW: float = 0.6
const HIT_RATE_BAND_HIGH: float = 1.4

## The skill both scripted engagements below run at: the middle of the dial,
## where [method ShooterProfile.skill_scale] is exactly 1.0 and the profile is
## the profile as written.
const ENGAGEMENT_SKILL: float = 0.5

## The aim engagement. The target rides a circle about the guard's stand, so its
## range and its crossing speed are both exactly constant for as long as the run
## lasts and the only thing that differs between two runs is the lever.
const LEAD_RANGE: float = 40.0
const LEAD_CROSSING_SPEED: float = 8.0
const LEAD_TRACK_SECONDS: float = 2.5

## The hit-rate trial: this many scripted shots in each mode.
const TRIAL_SHOTS: int = 80
const TRIAL_RANGE: float = 25.0
const TRIAL_CROSSING_SPEED: float = 3.0
## Where a round that misses is spent. Far enough past the target that nothing
## about a hit changes, near enough that eighty misses do not cost the run
## eighty flights out to the weapon's own 400 m and back in simulated seconds.
const TRIAL_SPENT_RANGE: float = 60.0
## Ticks of tracking between one scripted shot and the next: one
## [member ShooterProfile.aim_error_resample_seconds], so no two shots in a run
## are taken off the same draw of the guard's hand.
const TRIAL_SETTLE_TICKS: int = 21
## Ticks of tracking before the first scripted shot. The aim is a second-order
## response and settles in well under a second; without this the opening shots
## of every run would be taken while it was still swinging onto the target.
const TRIAL_WARMUP_TICKS: int = 90
## Ticks given to a round after the trigger, before the trigger comes round
## again. Spent in BOTH modes whether or not there is anything in the air to
## fly, so the two runs spend their shots at the same points of the same sweep;
## comfortably longer than the flight out to [constant TRIAL_SPENT_RANGE], so a
## round still in the air at the end of it has stalled rather than flown.
const TRIAL_FLIGHT_TICKS: int = 24
## Slack added when the reload is wound forward in a single call.
const READY_NUDGE: float = 0.01

## Where a finished engagement is parked: processing off and a kilometre down,
## so the next one can be built on the SAME stand. Two guards standing a few
## hundred metres apart would differ by float error of the same order as the
## 1e-6 this file compares their aims at, so the comparisons below are run one
## after another at the origin rather than side by side.
const RETIRED_POINT: Vector3 = Vector3(0.0, -1000.0, 0.0)

var _world: Node3D = null


func before_each() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_world.add_child(TestFixtures.make_floor(0.0))


# --- Reaction -----------------------------------------------------------------

## The reaction is a distribution around the profile's median, never below the
## floor, and a learner is slower than an expert.
func test_the_reaction_is_sampled_around_the_median_and_scales_with_skill() -> void:
	var guard: TowerShooter = _make_guard(Vector3(0.0, 0.0, 0.0), 0.5)
	var means: Dictionary = {}
	for skill: float in [0.2, 0.5, 0.8]:
		var total: float = 0.0
		var low: float = INF
		var high: float = -INF
		for _i: int in SAMPLES:
			var sample: float = guard.sample_reaction_seconds(skill)
			total += sample
			low = minf(low, sample)
			high = maxf(high, sample)
		means[skill] = total / float(SAMPLES)
		assert_ge(low, guard.profile.reaction_floor_seconds, "no sample under the floor at skill %.1f" % skill)
		assert_gt(high - low, 0.05, "the samples at skill %.1f are a spread, not a constant" % skill)
	assert_between(float(means[0.5]), 0.25, 0.40, "the mean reaction at skill 0.5 is about 300 ms")
	assert_gt(float(means[0.2]), float(means[0.5]), "a learner reacts slower than the default")
	assert_gt(float(means[0.5]), float(means[0.8]), "an expert reacts faster than the default")


## Nothing is fired inside the sampled reaction delay of a fresh sighting.
func test_no_shot_lands_inside_the_reaction_delay() -> void:
	var guard: TowerShooter = _make_guard(Vector3(0.0, 0.0, 0.0), 0.5)
	var runner: PlayerController = _make_body(Vector3(0.0, 0.0, -20.0), MatchController.RUNNER_GROUP)
	await step_ticks(3)
	assert_same(guard.get_target(), runner, "the runner ahead is acquired")
	var delay: float = guard.get_reaction_delay()
	assert_gt(delay, 0.0, "a reaction delay was sampled on acquisition")
	assert_eq_int(guard.get_shots_taken(), 0, "no shot on the first ticks")
	await step_seconds(delay * 0.5)
	assert_eq_int(guard.get_shots_taken(), 0, "still no shot halfway through the delay")
	assert_eq_int(guard.get_state(), TowerShooter.State.ACQUIRING, "it is acquiring, not engaging")


# --- Lead error ---------------------------------------------------------------

## The lead misjudgement grows with the target's angular speed and shrinks with
## skill, and the skill scale is exactly one at the default.
func test_the_lead_error_scales_with_angular_speed_and_skill() -> void:
	var profile: ShooterProfile = ShooterProfile.new()
	assert_almost_eq(ShooterProfile.skill_scale(0.5, 0.7), 1.0, 1e-6, "skill 0.5 is the profile as written")
	assert_almost_eq(ShooterProfile.skill_scale(0.0, 0.7), 1.7, 1e-6, "skill 0 is one plus the span")
	assert_almost_eq(ShooterProfile.skill_scale(1.0, 0.7), 0.3, 1e-6, "skill 1 is one minus the span")
	var slow: float = profile.get_lead_error_radians(0.1, 0.5)
	var fast: float = profile.get_lead_error_radians(0.4, 0.5)
	assert_almost_eq(fast, slow * 4.0, 1e-6, "the error is proportional to angular speed")
	var learner: float = profile.get_lead_error_radians(0.2, 0.2)
	var expert: float = profile.get_lead_error_radians(0.2, 0.8)
	assert_gt(learner, profile.get_lead_error_radians(0.2, 0.5), "a learner misjudges the lead more")
	assert_gt(profile.get_lead_error_radians(0.2, 0.5), expert, "an expert misjudges it less")
	assert_almost_eq(profile.get_lead_error_radians(0.0, 0.2), 0.0, 1e-9, "a still target is not led wrong")
	assert_gt(profile.get_aim_error_radians_at(0.2), profile.get_aim_error_radians_at(0.8), "aim error follows skill too")
	assert_gt(profile.get_scan_yaw_rate(0.8), profile.get_scan_yaw_rate(0.2), "an expert scans faster")


# --- Decoys -------------------------------------------------------------------

## A body that appears beside a known runner is suspect for a while: the runner
## is preferred even when the newcomer sits nearer the crosshair, and the
## suspicion expires.
func test_a_body_that_appears_beside_a_runner_is_suspect_for_a_while() -> void:
	var guard: TowerShooter = _make_guard(Vector3(0.0, 0.0, 0.0), 0.5)
	guard.profile.decoy_suspicion_seconds = 1.0
	var runner: PlayerController = _make_body(Vector3(3.0, 0.0, -20.0), MatchController.RUNNER_GROUP)
	await step_ticks(3)
	assert_same(guard.get_target(), runner, "the lone runner is the target")

	var decoy: PlayerController = _make_body(Vector3(0.5, 0.0, -20.0), RunnerPower.DECOY_GROUP)
	await step_ticks(2)
	assert_true(guard.is_suspect(decoy), "the newcomer beside the runner is suspect")
	assert_false(guard.is_suspect(runner), "the runner it appeared beside is not")
	assert_same(guard.get_target(), runner, "the runner stays the target over the nearer suspect")

	await step_seconds(1.2)
	assert_false(guard.is_suspect(decoy), "the suspicion has expired")


## A body seen at the start of the round is never suspect: the guard knows the
## field it was given.
func test_the_opening_field_is_never_suspect() -> void:
	var guard: TowerShooter = _make_guard(Vector3(0.0, 0.0, 0.0), 0.5)
	var one: PlayerController = _make_body(Vector3(1.0, 0.0, -20.0), MatchController.RUNNER_GROUP)
	var two: PlayerController = _make_body(Vector3(-1.0, 0.0, -20.0), MatchController.RUNNER_GROUP)
	await step_ticks(2)
	assert_false(guard.is_suspect(one), "the first of the opening pair is trusted")
	assert_false(guard.is_suspect(two), "and so is the second")


# --- The lever ----------------------------------------------------------------

## [member MatchRules.guard_skill] rides the rules payload and the rules copy,
## and reaches the rules from the settings clamped.
func test_guard_skill_replicates_like_any_rule() -> void:
	var sent: MatchRules = MatchRules.new()
	sent.guard_skill = 0.8
	var got: MatchRules = MatchRules.new()
	assert_true(NetCodec.unpack_rules(NetCodec.pack_rules(sent), got), "the payload decodes")
	assert_almost_eq(got.guard_skill, 0.8, 1e-6, "the skill came over the wire")
	var copied: MatchRules = MatchRules.new()
	NetCodec.copy_rules(sent, copied)
	assert_almost_eq(copied.guard_skill, 0.8, 1e-6, "the skill is copied with the rules")

	var settings: GameSettings = GameSettings.new()
	settings.reset()
	assert_almost_eq(settings.guard_skill, 0.5, 1e-6, "the default is the middle of the dial")
	settings.guard_skill = 7.0
	settings.clamp_all()
	assert_almost_eq(settings.guard_skill, GameSettings.MAX_GUARD_SKILL, 1e-6, "a wild value is clamped")
	settings.guard_skill = 0.2
	var rules: MatchRules = MatchRules.new()
	settings.apply_to_match_rules(rules)
	assert_almost_eq(rules.guard_skill, 0.2, 1e-6, "the skill landed on the rules")

	var config: ConfigFile = ConfigFile.new()
	settings.write_to(config)
	var read: GameSettings = GameSettings.new()
	read.reset()
	read.read_from(config)
	assert_almost_eq(read.guard_skill, 0.2, 1e-6, "the skill survives the settings file")


## The guard reads the lever from its rules.
func test_the_guard_reads_the_skill_from_its_rules() -> void:
	var guard: TowerShooter = _make_guard(Vector3(0.0, 0.0, 0.0), 0.8)
	assert_almost_eq(guard.get_skill(), 0.8, 1e-6, "the rules' skill is the guard's")
	guard.rules = null
	assert_almost_eq(guard.get_skill(), 0.5, 1e-6, "no rules means the default")


# --- The round in flight ------------------------------------------------------

## A round that has to cross the gap is led further than one that arrives.
##
## Same skill, same target, same believed velocity -- the trajectory is scripted
## by the test and is identical in both runs, so the read the guard builds of it
## is identical too -- and the only difference is
## [member MatchRules.guard_projectile_speed].
##
## [b]The misjudgement knobs are zeroed here on purpose.[/b]
## [member ShooterProfile.aim_error_degrees] and
## [member ShooterProfile.lead_error_seconds] are the guard's random bias, and
## at the defaults they are far larger than the lead itself. Zeroing them leaves
## exactly one thing in the measurement: the LEAD, which is what this test is
## about. How the bias grows with the longer lead is the hit-rate test's
## business, further down.
##
## Measured against where the target IS, not where the guard believes it is:
## under hitscan the tracker's own lag very nearly cancels the lead it applies
## and the crosshair sits on the runner, while a travelling round has to be
## aimed at empty ground ahead of them.
func test_the_guard_leads_further_when_the_round_has_to_fly() -> void:
	var hitscan: float = await _measure_aim_offset(0.0, true, true)
	var flying: float = await _measure_aim_offset(MatchRules.SUGGESTED_PROJECTILE_SPEED, true, true)
	assert_gt(
		flying,
		hitscan,
		(
			"a round with %.0f m/s of flight is aimed further off the runner's"
			+ " current position than a hitscan shot (%.5f rad against %.5f rad)"
		) % [MatchRules.SUGGESTED_PROJECTILE_SPEED, flying, hitscan],
	)


## The lever at 0.0 is today's game, to the last micro-radian.
##
## Both runs are hitscan and both must aim identically, but they reach 0.0 by
## different roads: one rifle carries the match's rules with the lever off, the
## other carries no rules at all, which is the wiring the tower had before the
## lever existed. The guard's hand is left random here rather than zeroed --
## same seed, same tick count, so the same draws -- so what is compared is the
## whole aim and not a stripped-down one.
func test_the_lever_off_leaves_the_guard_s_aim_untouched() -> void:
	var today: float = await _measure_aim_offset(0.0, false, false)
	var lever_off: float = await _measure_aim_offset(0.0, true, false)
	assert_almost_eq(
		lever_off,
		today,
		1e-6,
		"the lever at 0.0 aims where a rifle with no match opinion on the round aims",
	)


## The guard still hits things when the round has to travel.
##
## One guard at one skill, a target crossing at a fixed speed and a fixed range,
## one seed, and the same scripted shots in each mode: the test pulls the
## trigger, so the guard's own shot-confidence threshold is put out of reach and
## every shot below is the test's. Under the lever each round is flown to
## completion before the next shot, so a hit is a hit the round actually made.
##
## Both rates must be non-zero -- a mode that never connects is broken however
## the ratio reads -- and the projectile rate must hold
## [constant HIT_RATE_BAND_LOW]..[constant HIT_RATE_BAND_HIGH] of the hitscan
## one. See those constants for why the band is that wide and not tighter.
##
## The scripted trigger fires one tick later in the guard's own pipeline than
## the guard's would, so both rates carry the same small constant lag. It is the
## same in both modes and cancels in the ratio, which is the number asserted.
func test_the_hit_rate_holds_its_band_under_a_travelling_round() -> void:
	var hitscan: float = await _measure_hit_rate(0.0)
	var flying: float = await _measure_hit_rate(MatchRules.SUGGESTED_PROJECTILE_SPEED)
	assert_gt(hitscan, 0.0, "the guard connects at all under hitscan")
	assert_gt(flying, 0.0, "the guard connects at all with the round in the air")
	assert_between(
		flying / maxf(hitscan, 1e-6),
		HIT_RATE_BAND_LOW,
		HIT_RATE_BAND_HIGH,
		(
			"a travelling round holds %.2f..%.2f of the hitscan hit rate over"
			+ " %d scripted shots (%.3f against %.3f)"
		) % [HIT_RATE_BAND_LOW, HIT_RATE_BAND_HIGH, TRIAL_SHOTS, flying, hitscan],
	)


# --- Fixtures -----------------------------------------------------------------

## A [TowerShooter] on a real body with a real rifle, facing -Z, that does not
## sweep on its own so the field placed ahead of it is what it sees.
func _make_guard(at: Vector3, skill: float) -> TowerShooter:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	var rifle: Rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	rifle.profile = TestFixtures.weapon_profile()
	body.add_child(rifle)

	var profile: ShooterProfile = ShooterProfile.new()
	profile.scan_yaw_rate = 0.0
	profile.aim_random_seed = SEED
	profile.use_optic = false

	var rules: MatchRules = TestFixtures.match_rules()
	rules.guard_skill = skill

	var shooter: TowerShooter = TowerShooter.new()
	shooter.name = "GuardBrain"
	shooter.controller = body
	shooter.input = TestFixtures.bot_input_of(body)
	shooter.rifle = rifle
	shooter.profile = profile
	shooter.rules = rules
	shooter.target_group = MatchController.RUNNER_GROUP
	body.add_child(shooter)
	_world.add_child(body)
	shooter.configure(at, 0.0)
	return shooter


## A standing body in [param group], placed on the floor at [param at].
func _make_body(at: Vector3, group: StringName) -> PlayerController:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	body.add_to_group(group)
	_world.add_child(body)
	body.global_position = at
	return body


## Wire a guard's rifle for firing, exactly as
## [method MatchController._attach_rifle] does it.
##
## [method _make_guard] builds the rifle and hangs it on the body but stops
## there, because most of this file only watches where the guard points. A shot
## needs three more things: the shot line is the EYE's, so there is no parallax
## between the crosshair and where the round goes; the shooter's own body is
## excluded from it, or every shot is a self-hit at point blank; and the match's
## rules reach the weapon, which is the only road
## [member MatchRules.guard_projectile_speed] travels to
## [method Rifle.get_shot_speed] and from there to the guard's lead.
func _wire_rifle(guard: TowerShooter) -> void:
	guard.rifle.aim_source = guard.controller.head
	guard.rifle.shooter_body = guard.controller
	guard.rifle.rules = guard.rules


## A target the test flies itself, standing at the near point of its circle.
##
## Physics off: its position and its velocity are then exactly what the loop
## writes and never a frame's worth of gravity or a controller's opinion of
## where it ought to be. That is what makes two runs of the same engagement the
## same engagement.
func _make_scripted_target(radius: float, speed: float) -> PlayerController:
	var body: PlayerController = _make_body(Vector3(0.0, 0.0, -radius), MatchController.RUNNER_GROUP)
	body.set_physics_process(false)
	body.velocity = Vector3(speed, 0.0, 0.0)
	return body


## Put [param body] on a circle of [param radius] about the guard's stand, at
## [param angle] radians from the guard's opening facing, moving along it at
## [param speed].
##
## A circle rather than a straight line so that the range and the crossing speed
## are both constants of the run: a target on a chord changes both as it goes,
## and the lever's whole effect is a function of range and crossing speed.
func _place_on_circle(body: PlayerController, angle: float, radius: float, speed: float) -> void:
	body.global_position = Vector3(sin(angle), 0.0, -cos(angle)) * radius
	body.velocity = Vector3(cos(angle), 0.0, sin(angle)) * speed


## The angle between the line the guard's next shot would take and the line to
## where the target IS, in radians: how far ahead of the runner it is aiming,
## measured against the present rather than against the guard's own guess.
func _aim_offset(guard: TowerShooter, target: PlayerController) -> float:
	var eye: Node3D = guard.rifle.aim_source
	var to_now: Vector3 = (
		target.global_position
		+ Vector3.UP * guard.profile.target_aim_height
		- eye.global_position
	)
	return (-eye.global_transform.basis.z).angle_to(to_now)


## Take a finished engagement off the field: stop it processing, drop anything
## it left in the air, and park it out from under the next one's sightlines, so
## the next run can be built on the same stand. See [constant RETIRED_POINT].
func _retire(guard: TowerShooter, target: PlayerController) -> void:
	guard.set_physics_process(false)
	guard.rifle.clear_projectiles()
	guard.rifle.set_physics_process(false)
	guard.controller.set_physics_process(false)
	guard.controller.global_position = RETIRED_POINT
	target.remove_from_group(MatchController.RUNNER_GROUP)
	target.global_position = RETIRED_POINT


## Track a scripted crossing target for [constant LEAD_TRACK_SECONDS] and hand
## back how far ahead of it the guard ended up aiming, in radians.
##
## [param projectile_speed] is written into the rules' lever.
## [param attach_rules] false leaves the rifle with no rules at all -- the wiring
## before the lever existed -- which is a second road to a shot speed of 0.0.
## [param zero_misjudgement] silences the guard's random hand and its random
## lead bias, leaving the lead itself as the only thing in the measurement.
##
## The trigger is held throughout: the aim is the whole measurement, a shot
## changes nothing about where the guard is pointing, and confidence is a
## product of three terms none of which reaches 1.0 against a crossing target,
## so a threshold of 1.0 is a trigger that cannot be pulled.
func _measure_aim_offset(
	projectile_speed: float, attach_rules: bool, zero_misjudgement: bool
) -> float:
	var guard: TowerShooter = _make_guard(Vector3.ZERO, ENGAGEMENT_SKILL)
	if zero_misjudgement:
		guard.profile.aim_error_degrees = 0.0
		guard.profile.lead_error_seconds = 0.0
	guard.profile.shot_confidence_threshold = 1.0
	guard.rules.guard_projectile_speed = projectile_speed
	_wire_rifle(guard)
	if not attach_rules:
		guard.rifle.rules = null
	# The profile above was read once as the guard entered the tree, so the
	# retune is made to take effect from tick one the way the match does it.
	guard.configure(Vector3.ZERO, 0.0)

	var target: PlayerController = _make_scripted_target(LEAD_RANGE, LEAD_CROSSING_SPEED)
	var sweep: float = LEAD_CROSSING_SPEED / LEAD_RANGE
	var angle: float = 0.0
	for _i: int in int(LEAD_TRACK_SECONDS * SIM_HZ):
		await step_ticks(1)
		angle += sweep * SIM_DELTA
		_place_on_circle(target, angle, LEAD_RANGE, LEAD_CROSSING_SPEED)
	var offset: float = _aim_offset(guard, target)
	_retire(guard, target)
	return offset


## Fire [constant TRIAL_SHOTS] scripted shots at a scripted crossing target and
## hand back the fraction of them that struck it.
##
## The guard aims; the test pulls the trigger, on its own clock. Every trial
## spends exactly the same number of ticks in both modes -- see
## [constant TRIAL_FLIGHT_TICKS] -- so the two runs take their shots at the same
## points of the same sweep and the two rates are comparable. Under the lever
## each round is flown to completion with [method Rifle.tick] inside that window,
## so a hit is one the round really made and a miss is one it really missed.
## Only the reload is skipped, wound forward in a single call with nothing left
## in the air, which changes no outcome and saves the run eighty reloads of
## simulated time.
func _measure_hit_rate(projectile_speed: float) -> float:
	var guard: TowerShooter = _make_guard(Vector3.ZERO, ENGAGEMENT_SKILL)
	guard.profile.shot_confidence_threshold = 1.0
	guard.rules.guard_projectile_speed = projectile_speed
	_wire_rifle(guard)
	# A private copy, made by TestFixtures: shortening the reach only decides
	# where a MISS is spent, and nothing about a shot taken at TRIAL_RANGE.
	guard.rifle.profile.max_range = TRIAL_SPENT_RANGE
	guard.configure(Vector3.ZERO, 0.0)
	# Own the weapon's clock. _physics_process is only ever a caller of tick().
	guard.rifle.set_physics_process(false)

	var target: PlayerController = _make_scripted_target(TRIAL_RANGE, TRIAL_CROSSING_SPEED)
	var struck: Array[Node3D] = []
	guard.rifle.target_hit.connect(
		func(collider: Node3D, _at: Vector3, _normal: Vector3) -> void: struck.append(collider)
	)

	var sweep: float = TRIAL_CROSSING_SPEED / TRIAL_RANGE
	var angle: float = 0.0
	for _i: int in TRIAL_WARMUP_TICKS:
		await step_ticks(1)
		angle += sweep * SIM_DELTA
		_place_on_circle(target, angle, TRIAL_RANGE, TRIAL_CROSSING_SPEED)
		guard.rifle.tick(SIM_DELTA)

	var shots: int = 0
	var stalled: int = 0
	for _trial: int in TRIAL_SHOTS:
		for _i: int in TRIAL_SETTLE_TICKS:
			await step_ticks(1)
			angle += sweep * SIM_DELTA
			_place_on_circle(target, angle, TRIAL_RANGE, TRIAL_CROSSING_SPEED)
			guard.rifle.tick(SIM_DELTA)
		if guard.rifle.try_fire():
			shots += 1
		for _i: int in TRIAL_FLIGHT_TICKS:
			await step_ticks(1)
			angle += sweep * SIM_DELTA
			_place_on_circle(target, angle, TRIAL_RANGE, TRIAL_CROSSING_SPEED)
			guard.rifle.tick(SIM_DELTA)
		if guard.rifle.get_projectiles_in_flight() > 0:
			stalled += 1
		guard.rifle.tick(guard.rifle.get_time_to_ready() + READY_NUDGE)

	assert_eq_int(shots, TRIAL_SHOTS, "every trial at %.0f m/s spent its shot" % projectile_speed)
	assert_eq_int(stalled, 0, "every round at %.0f m/s flew to completion" % projectile_speed)
	var landed: int = 0
	for collider: Node3D in struck:
		if collider == target:
			landed += 1
	_retire(guard, target)
	return float(landed) / float(TRIAL_SHOTS)
