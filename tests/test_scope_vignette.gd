extends TestCase

## [ScopeVignette]: the optic is drawn on the guard's screen, on the SAME clock
## the raised pose and the narrowed field of view run on, and on nobody else's
## screen at all.
##
## The overlay itself cannot be photographed in a headless run -- there is no
## window and the node says so by going inert -- so what is asserted here is the
## decision rather than the pixels: [method ScopeVignette.compute_amount], the
## pure function of the optic's progress and the profile that the shader's one
## animated uniform is set from. The picture was checked by rendering it on the
## PC; see [RifleAds]' class notes and tools/_scratch/ads_view.gd.
##
## Driven through [method WeaponOptic.tick] with explicit deltas, never a real
## clock, exactly as tests/test_rifle_ads.gd and tests/test_zoom_feel.gd are.

const ODD_DELTA: float = 1.0 / 47.0

var _camera: Camera3D
var _zoom_profile: ZoomProfile
var _optic: WeaponOptic
var _rifle: Rifle
var _ads: RifleAds
var _trigger: WeaponInput
var _vignette: ScopeVignette


func before_each() -> void:
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
	_optic.set_process(false)

	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	_rifle.profile = TestFixtures.weapon_profile()
	add_child(_rifle)
	_rifle.set_physics_process(false)

	_ads = _rifle.get_node_or_null(^"Ads") as RifleAds
	_ads.optic = _optic
	_trigger = _rifle.get_node_or_null(^"HumanTrigger") as WeaponInput
	_vignette = _rifle.get_node_or_null(^"ScopeVignette") as ScopeVignette
	# The human is in the tower: exactly what MatchController._attach_rifle does
	# for a human holder. Every test below that wants a bot says so itself.
	_trigger.capture_mouse_on_ready = false
	_trigger.set_active(true)
	_trigger.set_process(false)

	await step_ticks(1)


## Drive the optic all the way in, in irregular steps.
func _zoom_all_the_way_in() -> void:
	_optic.zoom_in()
	var remaining: float = _zoom_profile.zoom_in_seconds
	while remaining > 0.0:
		var step: float = minf(ODD_DELTA, remaining)
		_optic.tick(step)
		remaining -= step
	_optic.tick(0.001)


# --- Wiring -------------------------------------------------------------------

func test_the_rifle_carries_a_scope_vignette_wired_to_its_own_siblings() -> void:
	assert_not_null(_vignette, "scenes/weapon/rifle.tscn must carry a ScopeVignette node")
	assert_same(
		_vignette.ads, _ads,
		"the vignette must read the transition off the Ads node beside it, not a clock of its own",
	)
	assert_same(
		_vignette.trigger, _trigger,
		"and must read whose screen this is off HumanTrigger beside it",
	)
	assert_not_null(_vignette.overlay, "the overlay Control must be authored in the scene, not built in code")
	assert_not_null(
		_vignette.overlay.material as ShaderMaterial,
		"and must carry the vignette's ShaderMaterial",
	)


## No window, no drawing -- and, headless, nothing visible was ever made.
func test_it_is_inert_with_no_display_server() -> void:
	if DisplayServer.get_name() != ScopeVignette.HEADLESS_DISPLAY:
		return
	assert_false(_vignette.overlay.visible, "the overlay must not be shown in a headless run")
	assert_almost_eq(_vignette.get_amount(), 0.0, 0.0001, "and nothing must have been drawn")


# --- The one clock ------------------------------------------------------------

func test_no_vignette_at_the_hip() -> void:
	assert_almost_eq(
		_vignette.compute_amount(), 0.0, 0.0001,
		"an unaimed rifle must leave the whole screen clear",
	)


func test_the_vignette_closes_only_over_the_back_of_the_raise_and_arrives_with_it() -> void:
	_zoom_all_the_way_in()
	assert_true(_optic.is_fully_zoomed(), "the optic must have actually arrived")
	assert_almost_eq(
		_vignette.compute_amount(), 1.0, 0.0001,
		"the border must be fully closed at exactly the moment the zoom settles",
	)

	# Wind back out and sample: nothing at all before the profile's onset, and
	# strictly increasing after it. The vignette is a function of the SHARED
	# progress, so this is a statement about the optic's own clock too.
	_optic.zoom_out()
	var previous: float = 1.0
	var saw_a_partial: bool = false
	var remaining: float = _zoom_profile.zoom_out_seconds
	while remaining > 0.0:
		var step: float = minf(ODD_DELTA, remaining)
		_optic.tick(step)
		remaining -= step
		var amount: float = _vignette.compute_amount()
		assert_le(amount, previous + 0.0001, "the border may only open as the scope comes down")
		previous = amount
		if _optic.get_shaped_progress() <= _zoom_profile.vignette_onset:
			assert_almost_eq(
				amount, 0.0, 0.0001,
				"there must be no vignette at all below ZoomProfile.vignette_onset",
			)
		elif amount > 0.0 and amount < 1.0:
			saw_a_partial = true
	_optic.tick(0.001)

	assert_true(saw_a_partial, "the border must actually close gradually, not snap")
	assert_almost_eq(
		_vignette.compute_amount(), 0.0, 0.0001,
		"and must be gone entirely once the scope is down",
	)


## The onset is a remap of the shared progress, not a second timer: at any
## progress the amount is exactly what the profile says it is.
func test_the_amount_is_a_pure_function_of_the_shared_progress() -> void:
	_optic.zoom_in()
	var elapsed: float = 0.0
	while elapsed < _zoom_profile.zoom_in_seconds:
		_optic.tick(ODD_DELTA)
		elapsed += ODD_DELTA
		var progress: float = _optic.get_shaped_progress()
		var onset: float = _zoom_profile.vignette_onset
		var expected: float = clampf((progress - onset) / (1.0 - onset), 0.0, 1.0)
		assert_almost_eq(
			_vignette.compute_amount(), expected, 0.0001,
			"the vignette must be the optic's own progress remapped, and nothing else",
		)


# --- Whose screen this is -----------------------------------------------------

## A bot in the tower runs every line of this and draws nothing.
func test_a_bot_held_rifle_draws_no_vignette_at_full_aim() -> void:
	_trigger.set_active(false)
	_zoom_all_the_way_in()
	assert_true(
		_optic.is_fully_zoomed(),
		"the bot's optic must really be zoomed for this test to mean anything",
	)
	assert_almost_eq(
		_vignette.compute_amount(), 0.0, 0.0001,
		"a bot guard, a prisoner, a spectator and a ghost must never see the optic",
	)
	# And it comes straight back the moment the human takes the seat, with no
	# transition of its own to catch up on.
	_trigger.set_active(true)
	assert_almost_eq(
		_vignette.compute_amount(), 1.0, 0.0001,
		"the human taking the tower mid-zoom must see the optic immediately",
	)


## An unwired rifle -- a stowed spare, a bare fixture -- is safe by default.
func test_an_optic_less_rifle_draws_nothing() -> void:
	_ads.optic = null
	assert_almost_eq(
		_vignette.compute_amount(), 0.0, 0.0001,
		"with no optic there is no transition, and so no vignette",
	)


## The other way a bot's rifle is silenced: [code]scenes/bot/tower_shooter.tscn[/code]
## disables its own HumanTrigger with [member Node.process_mode] rather than
## calling [method WeaponInput.set_active], so a gate that only read the flag
## would put the optic on screen for a bot in the tower.
func test_a_trigger_silenced_by_process_mode_draws_no_vignette() -> void:
	_trigger.process_mode = Node.PROCESS_MODE_DISABLED
	assert_false(_trigger.is_active(), "a process-mode-disabled trigger is not the human's")
	_zoom_all_the_way_in()
	assert_almost_eq(
		_vignette.compute_amount(), 0.0, 0.0001,
		"the way scenes/bot/tower_shooter.tscn silences its trigger must gate the optic too",
	)
