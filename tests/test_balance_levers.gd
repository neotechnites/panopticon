extends TestCase

## THE BALANCE LEVERS: each one moves something the player can see.
##
## Every field these tests set defaults to today's behaviour, so the suite that
## does not touch them measures the game as shipped. What is asserted here is
## the one thing a default cannot prove: that the lever is WIRED -- that moving
## it moves the round, and not merely the settings file.

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## Ticks of running before a prisoner is shot, so "put back on the line" is a
## claim about a body that had gone somewhere.
const RUNNING_TICKS: int = 90

## Height of the private floor the jump test runs on. Clear of the arena by a
## kilometre, so nothing another test left lying about is jumped off instead.
const JUMP_FLOOR_Y: float = 1000.0

## Scope drift the sway tests run at: far larger than anything playable, so the
## deviation is unmistakably the lever and not float noise.
const TEST_SWAY_DEGREES: float = 4.0

## The deviation a drift of [constant TEST_SWAY_DEGREES] must exceed before it
## counts as having moved the aim. A fifth of the amplitude: the drift is a sine,
## and a sample taken near a zero crossing is small without being absent.
const SWAY_FLOOR_DEGREES: float = 0.8

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _human: MatchParticipant


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	# The portal finish, as the older match tests use: the finisher fight is not
	# what any of these levers is about.
	_rules.finisher_hunts_guard = false
	_controller.rules = _rules
	# SettingsBoot writes the player's SAVED settings over the shipped rules
	# resource, which is one instance for the whole process -- so a test that
	# left it in would hand every later test in the run whatever is in this
	# machine's settings.cfg, and would have its own levers overwritten before
	# the match read them.
	var boot: Node = _match.get_node_or_null(^"SettingsBoot")
	if boot != null:
		_match.remove_child(boot)
		boot.free()


## The match is armed here rather than in [method before_each], so a test may set
## its lever on [member _rules] first -- several are read once, when the match
## starts.
func _arm() -> void:
	add_child(_match)
	_human = _controller.get_participants()[0]
	# The shipped match opens with a race. Hand the tower to the human through
	# the seam the match scores on, rather than running a 35 second lap.
	_human.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


# --- Scope sway ---------------------------------------------------------------

## A drift amplitude above zero moves the line the shot is cast from.
##
## Asserted on the AIM NODE, not on an overlay, because that is the whole claim:
## hits are resolved in [method Rifle._resolve_shot] off
## [member Rifle.aim_source]'s global basis, so a sway that did not write that
## node would wander the crosshair and leave the bullet where it was.
func test_sway_drifts_the_node_the_shot_is_cast_from() -> void:
	var camera: Camera3D = Camera3D.new()
	var optic: WeaponOptic = _make_optic(camera)
	var sway: RifleSway = _make_sway(optic, camera)
	_rules.scope_sway_degrees = TEST_SWAY_DEGREES
	_rules.scope_sway_hz = 0.25

	var rest: Vector3 = -camera.global_transform.basis.z
	# A quarter of a cycle at 0.25 Hz is one second, which is the peak of the
	# horizontal sweep.
	sway.tick(1.0)

	var drifted: Vector3 = -camera.global_transform.basis.z
	assert_gt(
		rad_to_deg(rest.angle_to(drifted)), SWAY_FLOOR_DEGREES,
		"a %.1f degree sway moved the aim line" % TEST_SWAY_DEGREES,
	)
	assert_gt(absf(sway.get_offset().x), 0.0, "and the drift is reported as yaw")


## The shipped amplitude of zero writes nothing at all.
func test_no_sway_leaves_the_aim_exactly_where_it_was() -> void:
	var camera: Camera3D = Camera3D.new()
	var optic: WeaponOptic = _make_optic(camera)
	var sway: RifleSway = _make_sway(optic, camera)
	_rules.scope_sway_degrees = 0.0

	var rest: Transform3D = camera.transform
	sway.tick(1.0)

	assert_vec2_eq(sway.get_offset(), Vector2.ZERO, "the shipped rules drift nothing")
	assert_vec3_almost_eq(
		camera.transform.basis.z, rest.basis.z, 1e-6, "and the aim node is untouched"
	)


## The settle takes the drift away again, so holding the scope up steadies it.
func test_the_settle_runs_the_drift_down_to_nothing() -> void:
	var camera: Camera3D = Camera3D.new()
	var optic: WeaponOptic = _make_optic(camera)
	var sway: RifleSway = _make_sway(optic, camera)
	_rules.scope_sway_degrees = TEST_SWAY_DEGREES
	_rules.scope_sway_settle_seconds = 2.0

	sway.tick(1.0)
	assert_gt(absf(sway.get_offset().x), 0.0, "the drift is there a second in")
	sway.tick(1.5)
	assert_almost_eq(
		sway.get_offset().length(), 0.0, 1e-6, "and gone once the settle has run out"
	)


# --- Tower windows ------------------------------------------------------------

## Closing windows raises rock plugs, and the ones left open stay spread.
func test_closing_a_window_raises_a_plug() -> void:
	var arena: Node3D = TestFixtures.make_arena()
	add_child(arena)
	var tower: TowerVariant = arena.get_node("Tower") as TowerVariant
	if not assert_not_null(tower, "the arena's Tower carries the variant script"):
		return

	assert_eq_int(tower.get_plugged_count(), 0, "the shipped tower is open on every side")

	tower.open_windows = 4
	assert_eq_int(tower.get_plugged_count(), 4, "half shut leaves four plugs standing")
	var plug: StaticBody3D = tower.get_node_or_null(^"Plugs/Plug1") as StaticBody3D
	if not assert_not_null(plug, "a closed opening has a plug body in it"):
		return
	assert_true(plug.visible, "the plug is drawn")
	assert_gt(float(plug.collision_layer), 0.0, "and it stops a shot")

	# Spread, not taken off one side.
	assert_true(TowerVariant.is_window_open(0, 4), "opening 0 stays open at four")
	assert_false(TowerVariant.is_window_open(1, 4), "opening 1 is plugged")
	assert_true(TowerVariant.is_window_open(2, 4), "opening 2 stays open")

	tower.open_windows = TowerVariant.WINDOW_COUNT
	assert_eq_int(tower.get_plugged_count(), 0, "opening them all takes every plug down")
	assert_false(plug.visible, "the plug that was raised is hidden again")


# --- Lives --------------------------------------------------------------------

## Two lives buys one respawn on the start line, not a free hit where you stood.
func test_a_spare_life_puts_the_prisoner_back_on_the_line() -> void:
	_rules.prisoner_lives = 2
	await _arm()

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var start: Vector3 = victim.body.global_position
	victim.body.velocity = Vector3.ZERO
	await step_ticks(RUNNING_TICKS)
	var ran_to: Vector3 = victim.body.global_position

	assert_false(_controller.apply_hit(victim), "a prisoner with a life left is not converted")
	assert_true(victim.is_running, "and is still in the round")
	assert_eq_int(victim.lives, 1, "one life is spent")
	# The start line is behind where the bot had already got to when the round
	# settled, so "back on the line" reads as further from the shot than the
	# settled spot was, not as a return to that spot.
	assert_gt(
		victim.body.global_position.distance_to(ran_to),
		maxf(ran_to.distance_to(start), 1.0),
		"and the body is back behind where it was shot, not stood up there",
	)

	assert_true(_controller.apply_hit(victim), "the last life converts them as it always did")


# --- The guard's shot ---------------------------------------------------------

## A miss lengthens the reload that follows it, once.
func test_a_miss_costs_the_guard_the_penalty() -> void:
	_rules.guard_miss_penalty_seconds = 2.0
	await _arm()

	var rifle: Rifle = _controller.rifle
	var before: float = rifle.get_cycle_reload_seconds()
	rifle.missed.emit(Vector3.ZERO)

	assert_almost_eq(
		rifle.get_cycle_reload_seconds(), before + 2.0, 1e-3,
		"the miss added its penalty to the cycle",
	)
	assert_almost_eq(
		rifle.reload_seconds, before, 1e-3,
		"and did not write itself into the round's reload",
	)


## The hitmarker is the host's to switch off.
func test_the_hit_marker_obeys_the_match_rules() -> void:
	_rules.guard_hit_marker = false
	await _arm()

	# The rig's own marker switches itself off with no display server, which is
	# correct for a bot sweep and useless here, so this test builds one that is
	# awake -- the licence match/feedback/feedback_rig.tscn's header grants.
	var confirm: FxHitConfirm = FxHitConfirm.new()
	confirm.headless_inert = false
	confirm.profile = (
		load("res://match/feedback/default_feedback_profile.tres") as FeedbackProfile
	).duplicate() as FeedbackProfile
	confirm.rifle = _controller.rifle
	confirm.controller = _controller
	add_child(confirm)
	confirm.set_process(false)

	confirm.show_mark(FxHitConfirm.Mark.CONFIRMED)
	assert_eq_int(
		int(confirm.get_mark()), int(FxHitConfirm.Mark.NONE),
		"a match with the marker off draws nothing on a hit",
	)

	_rules.guard_hit_marker = true
	confirm.show_mark(FxHitConfirm.Mark.CONFIRMED)
	assert_eq_int(
		int(confirm.get_mark()), int(FxHitConfirm.Mark.CONFIRMED),
		"and turning it back on draws it again",
	)


# --- The runner side ----------------------------------------------------------

## Pace and jump reach the prisoners' bodies and stay off the guard's.
func test_the_runner_multipliers_land_on_the_prisoners_only() -> void:
	_rules.runner_speed_multiplier = 1.5
	_rules.runner_jump_multiplier = 2.0
	await _arm()

	var prisoner: MatchParticipant = _controller.get_live_participants()[0]
	assert_almost_eq(
		prisoner.body.run_speed_scale, 1.5, 1e-6, "the prisoner runs at the rule's pace"
	)
	assert_almost_eq(prisoner.body.jump_scale, 2.0, 1e-6, "and jumps at its height")

	var guard: MatchParticipant = _controller.get_seat_participant()
	if not assert_not_null(guard, "somebody holds the tower"):
		return
	assert_almost_eq(
		guard.body.run_speed_scale, 1.0, 1e-6, "the guard keeps the profile's own pace"
	)
	assert_almost_eq(guard.body.jump_scale, 1.0, 1e-6, "and its own jump")


## Jump height, not launch speed: the launch is the square root of the lever.
func test_the_jump_multiplier_is_a_height() -> void:
	var profile: MovementProfile = TestFixtures.movement_profile()
	add_child(TestFixtures.make_floor(JUMP_FLOOR_Y))
	var body: PlayerController = TestFixtures.make_bot_player(profile)
	add_child(body)
	body.global_position = Vector3(0.0, JUMP_FLOOR_Y + 1.0, 0.0)
	body.jump_scale = 4.0
	await step_ticks(SETTLE_TICKS)

	var launch: Array[float] = [0.0]
	body.jumped.connect(func() -> void: launch[0] = body.velocity.y)
	# Through the body's own intent source, which is re-polled every tick and
	# would overwrite a one-off set_intent on the tick after it.
	TestFixtures.bot_input_of(body).command.jump_pressed = true
	await step_ticks(4)

	# Four times the height is twice the launch speed, not four times it.
	assert_almost_eq(
		launch[0], profile.jump_velocity * 2.0, 0.01,
		"a height multiplier of four leaves the ground at twice the launch speed",
	)


## The cooldown multiplier scales the seconds the rule names.
func test_the_ability_cooldown_multiplier_scales_the_wait() -> void:
	_rules.runner_ability = MatchRules.RunnerAbility.BUBBLE_SHIELD
	_rules.ability_cooldown_seconds = 4.0
	_rules.ability_duration_seconds = 0.5
	_rules.ability_cooldown_multiplier = 0.5
	await _arm()

	var prisoner: MatchParticipant = _controller.get_live_participants()[0]
	var power: RunnerPower = RunnerPower.of(prisoner.body)
	if not assert_not_null(power, "a prisoner carries a power node"):
		return

	assert_true(power.activate(), "the power starts")
	await step_seconds(0.7)

	assert_false(power.is_active(), "and runs out")
	assert_almost_eq(
		power.get_cooldown_remaining(), 2.0, 0.3,
		"the cooldown is the rule's four seconds halved, not four",
	)


# --- The settings door --------------------------------------------------------

## Every lever reaches [MatchRules] through the one door the rest of the Match
## tab uses, and a wild saved value is clamped rather than propagated.
func test_the_levers_reach_the_rules_and_are_clamped() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.reset()
	settings.scope_sway_degrees = 900.0
	settings.tower_open_windows = 99
	settings.runner_speed_multiplier = -3.0
	settings.guard_health = 0
	settings.guard_projectile_speed = 9000.0
	settings.clamp_all()

	assert_almost_eq(
		settings.scope_sway_degrees, GameSettings.MAX_SCOPE_SWAY_DEGREES, 1e-6, "sway clamped"
	)
	assert_eq_int(
		settings.tower_open_windows, MatchRules.TOWER_WINDOW_COUNT, "window count clamped"
	)
	assert_almost_eq(
		settings.runner_speed_multiplier, GameSettings.MIN_RUNNER_SPEED_MULTIPLIER, 1e-6,
		"pace clamped",
	)
	assert_eq_int(settings.guard_health, GameSettings.MIN_GUARD_HEALTH, "guard health clamped")
	assert_almost_eq(
		settings.guard_projectile_speed, GameSettings.MAX_GUARD_PROJECTILE_SPEED, 1e-6,
		"the round's speed clamped",
	)

	settings.scope_sway_degrees = 2.0
	settings.tower_variant = 0
	settings.tower_open_windows = 5
	settings.guard_miss_penalty_seconds = 1.5
	settings.guard_projectile_speed = MatchRules.SUGGESTED_PROJECTILE_SPEED
	settings.guard_hit_marker = false
	settings.runner_jump_multiplier = 1.4
	settings.ability_cooldown_multiplier = 2.0
	settings.finisher_health = 7
	var rules: MatchRules = MatchRules.new()
	settings.apply_to_match_rules(rules)

	assert_almost_eq(rules.scope_sway_degrees, 2.0, 1e-6, "sway landed on the rules")
	assert_eq_int(rules.tower_variant, 0, "the tower landed")
	assert_eq_int(rules.tower_open_windows, 5, "the openings landed")
	assert_almost_eq(rules.guard_miss_penalty_seconds, 1.5, 1e-6, "the miss penalty landed")
	assert_almost_eq(
		rules.guard_projectile_speed, MatchRules.SUGGESTED_PROJECTILE_SPEED, 1e-6,
		"the round's speed landed",
	)
	assert_false(rules.guard_hit_marker, "the hitmarker landed")
	assert_almost_eq(rules.runner_jump_multiplier, 1.4, 1e-6, "the jump landed")
	assert_almost_eq(rules.ability_cooldown_multiplier, 2.0, 1e-6, "the cooldown landed")
	assert_eq_int(rules.finisher_health, 7, "the finisher's health landed")


## And they survive the settings file, which is what makes them a host setting
## rather than a value typed once and lost.
func test_the_levers_round_trip_through_the_config() -> void:
	var written: GameSettings = GameSettings.new()
	written.reset()
	written.scope_sway_degrees = 1.25
	written.scope_sway_hz = 0.4
	written.scope_sway_settle_seconds = 3.0
	written.tower_variant = 0
	written.tower_open_windows = 2
	written.guard_miss_penalty_seconds = 0.5
	written.guard_projectile_speed = 175.0
	written.guard_hit_marker = false
	written.runner_speed_multiplier = 1.2
	written.runner_jump_multiplier = 0.8
	written.ability_cooldown_multiplier = 1.5
	written.guard_health = 3
	written.finisher_health = 12

	var config: ConfigFile = ConfigFile.new()
	written.write_to(config)
	var read: GameSettings = GameSettings.new()
	read.reset()
	read.read_from(config)

	assert_true(read.equals(written), "every balance lever survived the round trip")


# --- Fixtures -----------------------------------------------------------------

## A camera with a fully zoomed optic on it, both parented to this test.
func _make_optic(camera: Camera3D) -> WeaponOptic:
	camera.name = "Camera"
	camera.current = false
	add_child(camera)

	var optic: WeaponOptic = WeaponOptic.new()
	optic.camera = camera
	optic.profile = (
		load("res://weapons/default_zoom_profile.tres") as ZoomProfile
	).duplicate() as ZoomProfile
	add_child(optic)
	optic.set_process(false)
	optic.set_zoomed(true)
	# Far past the longest zoom-in the profile allows, so the drift is measured
	# at full aim rather than part way up.
	optic.tick(10.0)
	return optic


## The shipped rifle's own sway node, pointed at [param camera].
func _make_sway(optic: WeaponOptic, camera: Camera3D) -> RifleSway:
	var rifle: Rifle = (
		load("res://weapons/rifle.tscn") as PackedScene
	).instantiate() as Rifle
	rifle.rules = _rules
	add_child(rifle)
	var sway: RifleSway = rifle.get_node("Sway") as RifleSway
	sway.set_physics_process(false)
	sway.optic = optic
	sway.aim_node = camera
	return sway
