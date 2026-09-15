extends TestCase

## The human-like tower guard: its reaction sample, its lead error, its decoy
## suspicion, and the skill lever that scales them travelling like any rule.

const SAMPLES: int = 400
const SEED: int = 20260914

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
