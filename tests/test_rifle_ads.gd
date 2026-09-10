extends TestCase

## [RifleAds]: the view model actually raises toward the eye when the optic
## zooms, on the SAME clock the field of view itself runs on, and composes with
## [RifleRecoil] instead of fighting it for [code]Rifle/ViewModel[/code].
##
## Every claim here is driven through [method WeaponOptic.tick] and
## [method RifleRecoil.tick] with explicit, irregular deltas -- never a real
## clock -- mirroring tests/test_zoom_feel.gd and tests/test_rifle_recoil.gd.
## [member WeaponOptic.camera] and [member Rifle.aim_source] are the SAME
## [Camera3D] here, exactly as scenes/player/player.tscn wires them: the
## guarantee that matters most is that raising the model changes nothing about
## where that camera is pointed.

const TARGET_DISTANCE: float = 20.0
const TARGET_HALF_DEPTH: float = 0.5

## An irregular, non-60Hz delta, so a per-frame lerp toward a moving target --
## which would only ever approach it -- fails these tests where a value that is
## a pure function of the optic's own progress does not.
const ODD_DELTA: float = 1.0 / 47.0

var _camera: Camera3D
var _zoom_profile: ZoomProfile
var _optic: WeaponOptic

var _weapon_profile: WeaponProfile
var _rifle: Rifle
var _recoil: RifleRecoil
var _ads: RifleAds
var _view_model: Node3D
var _target: StaticBody3D

var _last_shot_origin: Vector3 = Vector3.ZERO
var _last_shot_end: Vector3 = Vector3.ZERO


func before_each() -> void:
	_target = TestFixtures.make_box_body(
		Vector3(6.0, 6.0, TARGET_HALF_DEPTH * 2.0),
		Vector3(0.0, 0.0, -TARGET_DISTANCE),
		"Target",
	)
	add_child(_target)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.current = false
	add_child(_camera)

	_zoom_profile = (
		load("res://scripts/optics/default_zoom_profile.tres") as ZoomProfile
	).duplicate() as ZoomProfile

	_optic = WeaponOptic.new()
	_optic.name = "Optic"
	_optic.camera = _camera
	_optic.profile = _zoom_profile
	add_child(_optic)
	# Own the clock, exactly as test_zoom_feel.gd does.
	_optic.set_process(false)

	_weapon_profile = TestFixtures.weapon_profile()
	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(_rifle)
	_rifle.profile = _weapon_profile
	add_child(_rifle)

	_rifle.global_transform = Transform3D.IDENTITY
	# The shot line is the camera's -- the same camera the optic zooms.
	_rifle.aim_source = _camera
	_rifle.set_physics_process(false)

	_recoil = _rifle.get_node_or_null(^"Recoil") as RifleRecoil
	_recoil.set_process(false)
	_ads = _rifle.get_node_or_null(^"Ads") as RifleAds
	# The one cross-scene wire MatchController._attach_rifle draws at runtime --
	# see its own comment there. Everything else (view_model, pose_source) is
	# wired inside scenes/weapon/rifle.tscn itself.
	_ads.optic = _optic
	_view_model = _rifle.get_node_or_null(^"ViewModel") as Node3D

	_rifle.fired.connect(_on_fired)

	# One physics frame so the target is registered with the physics server.
	await step_ticks(1)


func _on_fired(origin: Vector3, end_point: Vector3) -> void:
	_last_shot_origin = origin
	_last_shot_end = end_point


## The aimed pose, rebuilt independently from [member RifleAds.aim_position],
## [member RifleAds.aim_rotation_degrees] and [member RifleAds.aim_scale] rather
## than read back through [method RifleAds.get_current_base_pose] -- so this
## checks the exported contract those fields promise, and keeps working exactly
## as written if Ryan nudges the numbers in the inspector.
func _expected_aim_transform() -> Transform3D:
	var basis: Basis = Basis.from_euler(
		Vector3(
			deg_to_rad(_ads.aim_rotation_degrees.x),
			deg_to_rad(_ads.aim_rotation_degrees.y),
			deg_to_rad(_ads.aim_rotation_degrees.z),
		)
	).scaled(Vector3.ONE * _ads.aim_scale)
	return Transform3D(basis, _ads.aim_position)


# --- Wiring ---------------------------------------------------------------------

func test_the_rifle_carries_an_ads_node_composed_with_recoil() -> void:
	assert_not_null(_ads, "scenes/weapon/rifle.tscn must carry an Ads node")
	assert_not_null(_recoil, "scenes/weapon/rifle.tscn must carry a Recoil node")
	assert_true(
		_recoil.is_at_rest(),
		"with the optic unzoomed, the view model must start settled at the hip pose",
	)
	assert_true(
		_view_model.transform.is_equal_approx(_ads.get_hip_transform()),
		"and that hip pose must be the scene's own authored ViewModel transform",
	)
	assert_false(
		_ads.get_hip_transform().is_equal_approx(_expected_aim_transform()),
		"the aimed pose must actually differ from the hip pose for any of this to be observable",
	)


## The default profile is what Ryan asked for: half a second going in. Both the
## FOV and the raise run off this single number -- see [RifleAds]'s own class
## notes for why there is no second one.
func test_the_shipped_profile_zooms_in_over_half_a_second() -> void:
	assert_almost_eq(
		_zoom_profile.zoom_in_seconds, 0.5, 0.0001,
		"zoom_in_seconds is the one clock both the FOV and the raised pose run on",
	)


# --- The shot line ----------------------------------------------------------

## The single most important guarantee: raising the model toward the eye must
## never move where a shot actually goes, at any point during the raise.
func test_the_shot_line_is_unchanged_throughout_an_ads_transition() -> void:
	_optic.zoom_in()
	var checkpoints: Array[float] = [0.0, 0.1, 0.25, 0.4]
	var elapsed: float = 0.0
	var saw_a_genuinely_mid_flight_checkpoint: bool = false

	for t: float in checkpoints:
		var step: float = t - elapsed
		if step > 0.0:
			_optic.tick(step)
			_recoil.tick(step)
			elapsed = t

		var progress: float = _optic.get_shaped_progress()
		if progress > 0.01 and progress < 0.99:
			saw_a_genuinely_mid_flight_checkpoint = true
			assert_false(
				_view_model.transform.is_equal_approx(_ads.get_hip_transform()),
				"the model must have actually left the hip pose at t=%.2f" % t,
			)

		assert_true(_rifle.try_fire(), "a READY rifle fires while its own view model is mid-raise")
		assert_vec3_almost_eq(
			_last_shot_origin, Vector3.ZERO, 0.001,
			"the shot must still start at the camera, never at the raised view model, at t=%.2f" % t,
		)
		assert_vec3_almost_eq(
			_last_shot_end,
			Vector3(0.0, 0.0, -(TARGET_DISTANCE - TARGET_HALF_DEPTH)),
			0.01,
			"and land exactly where an unaimed shot lands, at t=%.2f" % t,
		)

		# Clear the reload so the next checkpoint's trigger pull is legal.
		_rifle.tick(_weapon_profile.get_cycle_seconds(_rifle.reload_seconds) + 0.001)

	assert_true(
		saw_a_genuinely_mid_flight_checkpoint,
		"at least one checkpoint must actually be mid-transition for this test to mean anything",
	)


# --- Arrival, and drift -----------------------------------------------------

## Frame-rate independent and exact at both ends, however many times the
## player feathers the zoom button.
func test_the_view_model_returns_exactly_to_hip_and_aim_over_many_cycles() -> void:
	var hip: Transform3D = _ads.get_hip_transform()
	var aim: Transform3D = _expected_aim_transform()

	for cycle: int in range(8):
		_optic.zoom_in()
		var remaining: float = _zoom_profile.zoom_in_seconds
		while remaining > 0.0:
			var step: float = minf(ODD_DELTA, remaining)
			_optic.tick(step)
			_recoil.tick(step)
			remaining -= step
		# One more nudge past the end: the arrival must already be exact, not
		# merely close to it.
		_optic.tick(0.001)
		_recoil.tick(0.001)

		assert_true(_optic.is_fully_zoomed(), "the optic must have actually arrived, cycle %d" % cycle)
		assert_true(_recoil.is_at_rest(), "and the view model must have settled with it, cycle %d" % cycle)
		assert_true(
			_view_model.transform.is_equal_approx(aim),
			"the view model must sit exactly on the aimed pose after cycle %d, not merely near it" % cycle,
		)

		_optic.zoom_out()
		remaining = _zoom_profile.zoom_out_seconds
		while remaining > 0.0:
			var step: float = minf(ODD_DELTA, remaining)
			_optic.tick(step)
			_recoil.tick(step)
			remaining -= step
		_optic.tick(0.001)
		_recoil.tick(0.001)

		assert_false(_optic.is_fully_zoomed(), "the optic must have actually come back out, cycle %d" % cycle)
		assert_true(_recoil.is_at_rest(), "and the view model must have settled at the hip, cycle %d" % cycle)
		assert_true(
			_view_model.transform.is_equal_approx(hip),
			(
				"the view model must be exactly back on its authored hip pose after cycle %d, "
				+ "with no drift accumulated across cycles"
			) % cycle,
		)


# --- Composing with recoil ---------------------------------------------------

## A shot fired while fully aimed must recoil from, and recover to, the AIMED
## pose -- never drift toward the hip, and never leave the two systems fighting
## over the node.
func test_recoil_while_fully_aimed_recovers_exactly_to_the_aim_pose() -> void:
	_optic.zoom_in()
	_optic.tick(_zoom_profile.zoom_in_seconds)
	_optic.tick(0.001)
	_recoil.tick(_zoom_profile.zoom_in_seconds + 0.001)
	assert_true(_optic.is_fully_zoomed(), "must actually be fully aimed for this test to mean anything")

	var aim: Transform3D = _expected_aim_transform()
	assert_true(_view_model.transform.is_equal_approx(aim), "settled aimed, before any shot is fired")

	_recoil.kick(_weapon_profile)
	assert_false(_recoil.is_at_rest(), "the kick must actually be running")

	var kick_duration: float = _weapon_profile.get_recoil_duration()
	var remaining: float = kick_duration
	var saw_it_leave_the_aim_pose: bool = false
	while remaining > 0.0:
		var step: float = minf(ODD_DELTA, remaining)
		_recoil.tick(step)
		remaining -= step
		if not _view_model.transform.is_equal_approx(aim):
			saw_it_leave_the_aim_pose = true
	# One more nudge past the end: recovery must already be exact.
	_recoil.tick(0.001)

	assert_true(
		saw_it_leave_the_aim_pose,
		"the kick must actually have moved the model away from the aim pose at some point",
	)
	assert_true(_recoil.is_at_rest(), "the kick must be fully spent")
	assert_true(
		_view_model.transform.is_equal_approx(aim),
		"a shot fired while aimed must recover to the AIMED pose, never drift toward the hip",
	)
