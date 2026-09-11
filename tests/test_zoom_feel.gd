extends TestCase

## HOW THE SCOPE FEELS, as opposed to where it ends up.
##
## [WeaponOptic] already had the endpoint right: the zoom is a fraction of the
## player's own display FOV rather than an angle that overrules it, and mouse
## sensitivity is scaled by the visible field so a scope is not untrackable. What
## it had never had was a TRANSITION anybody had looked at -- a linear ramp of
## one duration in both directions.
##
## Three claims are made about that here, and each of them is a decision that
## would otherwise be invisible:
##
## [codeblock]
## 1. Coming out is quicker than going in. Aiming is a decision; un-aiming is a
##    reaction, and a symmetric transition charges the same for both.
## 2. The transition is EASED but the CLOCK is not, so it still arrives in
##    exactly its stated time at any framerate.
## 3. Feathering the button cannot pop the FOV. This is what forces one shared
##    curve rather than a curve per direction.
## [/codeblock]

## The base field of view every test here zooms from: the value
## [code]scenes/player/player.tscn[/code] ships its camera at.
const BASE_FOV: float = 100.0

## Two framerates, to show the transition is time-based and not frame-based.
const FAST_DELTA: float = 1.0 / 144.0
const SLOW_DELTA: float = 1.0 / 30.0

var _camera: Camera3D
var _optic: WeaponOptic
var _profile: ZoomProfile


func before_each() -> void:
	_profile = (
		load("res://scripts/optics/default_zoom_profile.tres") as ZoomProfile
	).duplicate() as ZoomProfile

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.current = false
	_camera.fov = BASE_FOV
	add_child(_camera)

	_optic = WeaponOptic.new()
	_optic.name = "Optic"
	_optic.camera = _camera
	_optic.profile = _profile
	add_child(_optic)
	# Stepped by hand at a delta each test chooses; the point of several of them
	# is that the delta does not matter.
	_optic.set_process(false)


# --- The two clocks -----------------------------------------------------------

## Letting go is cheaper than committing.
func test_coming_out_of_the_scope_is_quicker_than_going_in() -> void:
	assert_gt(
		_profile.zoom_in_seconds, _profile.zoom_out_seconds,
		"the shipped profile charges more for aiming than for stopping",
	)
	assert_almost_eq(
		_optic.transition_seconds_for_direction(true), _profile.zoom_in_seconds,
		0.0001, "and the optic reads the in clock for going in",
	)
	assert_almost_eq(
		_optic.transition_seconds_for_direction(false), _profile.zoom_out_seconds,
		0.0001, "and the out clock for coming out",
	)

	# Tolerance is one step of the clock they are being driven at, plus half
	# again: a transition can only ever finish on a tick boundary, so the last
	# tick always overshoots the stated time by up to one delta.
	assert_almost_eq(
		_seconds_to_settle(true), _profile.zoom_in_seconds, SLOW_DELTA * 1.5,
		"a full zoom in takes its stated time",
	)
	assert_almost_eq(
		_seconds_to_settle(false), _profile.zoom_out_seconds, SLOW_DELTA * 1.5,
		"and a full zoom out takes its own, shorter one",
	)


## The easing shapes the value, never the clock. A transition that took longer
## on a slower machine would be a scope whose speed is the framerate's opinion.
func test_the_transition_arrives_in_the_same_time_at_any_framerate() -> void:
	var fast: float = _seconds_to_settle(true, FAST_DELTA)
	_optic.reset_zoom()
	var slow: float = _seconds_to_settle(true, SLOW_DELTA)

	assert_almost_eq(
		fast, _profile.zoom_in_seconds, FAST_DELTA * 1.5,
		"at 144 Hz it arrives on time",
	)
	assert_almost_eq(
		slow, _profile.zoom_in_seconds, SLOW_DELTA * 1.5,
		"and at 30 Hz it arrives on the same time",
	)


# --- The shape ----------------------------------------------------------------

## Eased, and demonstrably so: the shipped smoothing leaves and arrives gently
## and covers the middle fast, which is the difference between a number changing
## and a camera moving.
func test_the_transition_is_eased_rather_than_a_constant_ramp() -> void:
	if not assert_gt(_profile.transition_smoothing, 0.0, "the shipped profile eases"):
		return

	_optic.zoom_in()
	# A quarter of the way through the clock, an eased transition has covered
	# LESS than a quarter of the distance -- it is still getting under way.
	_optic.tick(_profile.zoom_in_seconds * 0.25)
	assert_almost_eq(
		_optic.get_zoom_progress(), 0.25, 0.02,
		"the clock itself is linear",
	)
	assert_lt(
		_optic.get_shaped_progress(), 0.25,
		"but the view has not covered a quarter of the distance yet",
	)

	# And through the middle it is moving faster than the clock.
	var before: float = _optic.get_shaped_progress()
	_optic.tick(_profile.zoom_in_seconds * 0.25)
	var after: float = _optic.get_shaped_progress()
	assert_gt(
		after - before, 0.25,
		"the middle of the move covers more than its share",
	)


## Feathering the button is the most common thing anybody does with a
## hold-to-aim scope, and it must not pop.
##
## This is the whole reason the easing is one shared curve rather than one per
## direction: the shaped value is a pure function of the linear clock, so
## reversing changes the RATE and never the value. Two curves would make the FOV
## jump on every feather by the difference between them at that point.
func test_feathering_the_button_never_pops_the_field_of_view() -> void:
	_optic.zoom_in()
	_optic.tick(_profile.zoom_in_seconds * 0.5)
	var mid_fov: float = _camera.fov
	assert_between(
		mid_fov, _optic.get_zoomed_fov() + 0.5, BASE_FOV - 0.5,
		"the optic is genuinely part way in",
	)

	# One millisecond of travel is worth well under a degree of the 60 degree
	# span; a curve swapped underneath the transition would move it by several
	# at once, which is the pop this is watching for.
	_optic.zoom_out()
	_optic.tick(0.001)
	assert_almost_eq(
		_camera.fov, mid_fov, 1.0,
		"reversing moves the view on from where it was, it does not jump",
	)

	_optic.zoom_in()
	_optic.tick(0.001)
	assert_almost_eq(
		_camera.fov, mid_fov, 1.0,
		"and reversing back does not jump either",
	)


# --- The endpoint, which was already right --------------------------------------

## The zoom composes with the player's display FOV instead of replacing it, and
## the sensitivity multiplier tracks the visible field the whole way. Asserted
## here because the transition rewrite runs through both.
func test_the_zoom_stays_relative_and_the_sensitivity_stays_compensated() -> void:
	assert_almost_eq(
		_optic.get_zoomed_fov(), BASE_FOV * _profile.zoom_factor, 0.01,
		"full zoom is a fraction of the camera's own field of view",
	)
	assert_almost_eq(
		_optic.sensitivity_multiplier, 1.0, 0.01,
		"un-zoomed, the mouse is untouched",
	)

	_optic.zoom_in()
	_optic.tick(_profile.zoom_in_seconds)

	assert_true(_optic.is_fully_zoomed(), "the optic arrived")
	assert_almost_eq(
		_optic.sensitivity_multiplier,
		pow(_profile.zoom_factor, _profile.sensitivity_compensation), 0.01,
		"and the mouse now sweeps the same fraction of a narrower field",
	)
	assert_lt(
		_optic.sensitivity_multiplier, 1.0,
		"which is to say aiming zoomed is not twitchy",
	)

	# The player's display FOV setting still wins: written straight onto the
	# camera, it becomes the new base and the zoom re-derives from it.
	_optic.reset_zoom()
	_camera.fov = 80.0
	_optic.tick(0.0)
	assert_almost_eq(
		_optic.get_zoomed_fov(), 80.0 * _profile.zoom_factor, 0.01,
		"a player who changed their display FOV is not overruled by aiming",
	)


# --- Helpers ------------------------------------------------------------------

## Seconds of ticks it takes a full transition in [param zooming_in]'s direction
## to settle, stepped at [param delta].
func _seconds_to_settle(zooming_in: bool, delta: float = SLOW_DELTA) -> float:
	if not zooming_in:
		# Start from a settled full zoom, so what is measured is the way out.
		_optic.zoom_in()
		while _optic.is_transitioning():
			_optic.tick(delta)

	_optic.set_zoomed(zooming_in)
	var elapsed: float = 0.0
	var budget: float = 5.0
	while _optic.is_transitioning() and elapsed < budget:
		_optic.tick(delta)
		elapsed += delta
	return elapsed
