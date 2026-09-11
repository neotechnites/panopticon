extends TestCase

## [RifleRecoil]: the view model kicks and settles back, and nothing it touches
## is the shot.
##
## These tests exist to hold down the three guarantees the class description
## makes: the shot line is untouched by a kick in progress, the muzzle marker
## rides the model through the whole motion because it is a child of the node
## being kicked, and recovery lands on the scene-authored rest transform exactly
## -- not approximately, and not with drift after many shots -- however the
## clock is stepped. All three are driven through
## [method RifleRecoil.tick] with explicit deltas, mirroring how
## [code]tests/test_weapon.gd[/code] drives [Rifle] itself: a kick measured
## against a real clock would be a test of how busy CI was.

## Distance from the muzzle to the test target, in metres. Matches
## [code]tests/test_weapon.gd[/code] so a hit lands at the same place.
const TARGET_DISTANCE: float = 20.0
const TARGET_HALF_DEPTH: float = 0.5

## The barrel end in the model's own coordinates. See
## [code]tests/test_weapon.gd[/code]'s [code]MODEL_MUZZLE[/code].
const MODEL_MUZZLE: Vector3 = Vector3(0.0, 0.0, -1.150)

var _rifle: Rifle
var _profile: WeaponProfile
var _recoil: RifleRecoil
var _view_model: Node3D
var _target: StaticBody3D

var _shots: int = 0
var _last_shot_origin: Vector3 = Vector3.ZERO
var _last_hit_position: Vector3 = Vector3.ZERO


func before_each() -> void:
	_target = TestFixtures.make_box_body(
		Vector3(6.0, 6.0, TARGET_HALF_DEPTH * 2.0),
		Vector3(0.0, 0.0, -TARGET_DISTANCE),
		"Target",
	)
	add_child(_target)

	_profile = TestFixtures.weapon_profile()
	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(_rifle)
	_rifle.profile = _profile
	add_child(_rifle)

	_rifle.global_transform = Transform3D.IDENTITY
	# Own both clocks. _physics_process and _process are only ever callers of
	# tick() -- see Rifle.tick and RifleRecoil.tick.
	_rifle.set_physics_process(false)

	_recoil = _rifle.get_node_or_null(^"Recoil") as RifleRecoil
	if _recoil != null:
		_recoil.set_process(false)
	_view_model = _rifle.get_node_or_null(^"ViewModel") as Node3D

	_rifle.fired.connect(_on_fired)

	# One physics frame so the target is registered with the physics server.
	await step_ticks(1)


# --- Wiring ---------------------------------------------------------------------

func test_the_rifle_carries_a_recoil_node_wired_to_the_view_model() -> void:
	assert_not_null(_recoil, "scenes/weapon/rifle.tscn must carry a Recoil node")
	assert_not_null(_view_model, "scenes/weapon/rifle.tscn must carry a ViewModel node")


## The weapon ACTUALLY firing starts the kick, and nothing else does.
##
## No test here ever touches [Input] -- the harness has no device to read from
## -- so a kick that only ever started on [signal Rifle.fired] is exactly the
## kick this test observes. A bot AI calling [method Rifle.try_fire] exercises
## the identical path.
func test_a_shot_starts_the_kick() -> void:
	assert_true(_recoil.is_at_rest(), "nothing has fired yet")
	assert_true(_rifle.try_fire(), "a READY rifle must take the shot")
	assert_false(_recoil.is_at_rest(), "the weapon firing must have started the kick")


## A profile with both recoil fields zeroed is a profile with no kick at all --
## the "disabled" state the design calls for, expressed by numbers rather than a
## second switch.
func test_a_zeroed_profile_never_moves_the_model() -> void:
	var zero_profile: WeaponProfile = _profile.duplicate() as WeaponProfile
	zero_profile.recoil_kick_distance = 0.0
	zero_profile.recoil_kick_pitch_degrees = 0.0
	assert_false(zero_profile.has_recoil(), "zeroing both fields must read as recoil disabled")

	_rifle.profile = zero_profile
	assert_true(_rifle.try_fire(), "the shot is still taken")
	assert_true(_recoil.is_at_rest(), "a zeroed profile must never move the view model")


# --- The shot line ----------------------------------------------------------

## The single most important guarantee: a shot fired while the view model is
## mid-kick lands exactly where a shot fired at rest would.
##
## The kick is played directly here, bypassing a real trigger pull, precisely so
## the rifle itself stays READY and can still fire a comparable shot -- a real
## single-shot weapon refuses a second trigger pull during its own recoil, which
## would make the interesting case untestable through try_fire() alone. What
## matters is the invariant [method Rifle._resolve_shot] is built on: it reads
## [member Rifle.aim_source], never the view model, so whatever state ViewModel
## is in cannot be visible in the result.
func test_a_shot_mid_kick_lands_exactly_where_an_unkicked_shot_would() -> void:
	_recoil.kick(_profile)
	_recoil.tick(_profile.recoil_kick_seconds + _profile.recoil_recover_seconds * 0.4)
	assert_false(_recoil.is_at_rest(), "the view model must actually be mid-kick for this test to mean anything")

	assert_true(_rifle.try_fire(), "a READY rifle fires even while its own view model is kicking")
	assert_vec3_almost_eq(
		_last_shot_origin, Vector3.ZERO, 0.001,
		"the shot still starts at the aim source, never at the kicked view model",
	)
	assert_vec3_almost_eq(
		_last_hit_position,
		Vector3(0.0, 0.0, -(TARGET_DISTANCE - TARGET_HALF_DEPTH)),
		0.01,
		"and lands exactly where a shot fired at rest lands",
	)


# --- The muzzle ---------------------------------------------------------------

## The muzzle marker is a child of ViewModel, so it can only ride the kick -- but
## that is the whole guarantee the requirement asks for, and it is worth pinning
## down rather than trusting the scene tree by eye.
func test_the_muzzle_rides_the_model_through_the_whole_kick() -> void:
	_recoil.kick(_profile)
	var checkpoints: Array[float] = [
		0.0,
		_profile.recoil_kick_seconds * 0.5,
		_profile.recoil_kick_seconds,
		_profile.recoil_kick_seconds + _profile.recoil_recover_seconds * 0.5,
		_profile.recoil_kick_seconds + _profile.recoil_recover_seconds,
	]
	var rest: Transform3D = _recoil.get_rest_transform()
	var elapsed: float = 0.0
	var saw_a_kicked_frame: bool = false
	var saw_the_view_model_actually_move: bool = false
	for t: float in checkpoints:
		_recoil.tick(t - elapsed)
		elapsed = t
		if not _recoil.is_at_rest():
			saw_a_kicked_frame = true
		if not _view_model.transform.is_equal_approx(rest):
			# Confirms the SCENE's ViewModel node -- fetched independently of
			# RifleRecoil -- is the one actually moving, not just RifleRecoil's
			# own clock, so a Recoil wired to the wrong node would be caught here.
			saw_the_view_model_actually_move = true
		var expected: Vector3 = _view_model.global_transform * MODEL_MUZZLE
		assert_vec3_almost_eq(
			_rifle.muzzle.global_position, expected, 1e-4,
			"the muzzle must sit at the model's barrel end at t=%.3f, kicked or not" % t,
		)
	assert_true(saw_a_kicked_frame, "at least one checkpoint must actually be mid-kick")
	assert_true(
		saw_the_view_model_actually_move,
		"the scene's own ViewModel node must be the one that moved, not just RifleRecoil's clock",
	)


# --- Recovery -------------------------------------------------------------------

## Recovery is frame-rate independent and lands on the exact authored rest
## transform, with no drift after many shots.
##
## The rifle's floor reload is used so the cycle is as tight as the profile
## permits, which is also the boundary condition the design cares about: the
## kick has to fit inside the fastest legal cycle, not just the leisurely default
## one. Each kick is stepped with an irregular, non-60Hz delta on purpose, so a
## per-frame lerp toward the target -- which would only ever approach it -- would
## fail this test where a closed-form decay does not.
func test_the_view_model_returns_to_rest_after_many_shots_at_uneven_frame_rates() -> void:
	_rifle.reload_seconds = _profile.min_reload_seconds
	var cycle: float = _profile.get_cycle_seconds(_rifle.reload_seconds)
	var kick_duration: float = _profile.get_recoil_duration()
	assert_lt(kick_duration, cycle, "the fixture's own numbers must leave room for a kick to finish")

	var rest: Transform3D = _recoil.get_rest_transform()
	var odd_delta: float = 1.0 / 47.0  # deliberately not 60 Hz

	for shot: int in range(15):
		assert_true(_rifle.try_fire(), "shot %d should be allowed; the previous cycle must have finished" % shot)

		var remaining: float = kick_duration
		while remaining > 0.0:
			var step: float = minf(odd_delta, remaining)
			_recoil.tick(step)
			remaining -= step
		# One more nudge past the end: the recovery must have already reached
		# exactly zero, not merely be close to it.
		_recoil.tick(0.001)

		assert_true(_recoil.is_at_rest(), "the kick must be fully spent after shot %d" % shot)
		assert_true(
			_view_model.transform.is_equal_approx(rest),
			"the view model must be exactly on its authored rest transform after shot %d" % shot,
		)
		assert_vec3_almost_eq(
			_view_model.position, rest.origin, 1e-5,
			"no positional drift may accumulate across shots (shot %d)" % shot,
		)

		# Serve the rest of the reload so the next trigger pull is legal.
		_rifle.tick(cycle + 0.001)


# --- Timing budget --------------------------------------------------------------

## The shipped numbers leave real margin before the fastest legal cycle, which is
## what keeps a kick from ever being visible on a shot that has already been
## fired again.
func test_the_shipped_recoil_fits_well_inside_the_fastest_cycle() -> void:
	var soonest: float = _profile.get_cycle_seconds(_profile.min_reload_seconds)
	assert_lt(
		_profile.get_recoil_duration(), soonest,
		"the view-model kick must finish before the weapon can possibly fire again",
	)


func _on_fired(origin: Vector3, end_point: Vector3) -> void:
	_shots += 1
	_last_shot_origin = origin
	_last_hit_position = end_point
