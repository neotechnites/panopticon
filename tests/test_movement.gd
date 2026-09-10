extends TestCase

## [PlayerController]: the Quake movement model the whole game's feel rests on.
##
## [b]The one trap in this file[/b]
##
## [member MoveIntent.look_delta] is a per-tick delta [b]already in radians[/b].
## Every turn below therefore goes through
## [method BotIntentSource.aim], which takes radians per second and does the
## per-tick scaling itself. Reaching for
## [member MovementProfile.mouse_sensitivity] here -- as the pixels-to-radians
## conversion a mouse needs -- multiplies the yaw by a further ~0.002 or divides
## by it, and neither raises an error: the body simply turns by the wrong amount,
## the strafe stops gaining, and the failure reads as a physics regression rather
## than as a broken test. That mistake has already been made once on this
## project. [b]aim() takes radians per second. Nothing here scales by sensitivity.[/b]

## Yaw rates used by the strafe tests, in radians per second.
##
## All three are well inside [member BotProfile.max_yaw_rate] and inside what a
## hand on a mouse produces. Zero is the control: with no turn the wish direction
## never leaves the velocity's perpendicular, so air acceleration saturates at
## [member MovementProfile.max_air_speed] and the body cannot gain.
## Both non-zero rates sit below the gain optimum for the speeds reached here
## (about 4 rad/s at 8-13 m/s, and it falls as the body speeds up), which is what
## makes gain monotonic in the turn rate over this range. Pick a rate past the
## optimum and a faster turn gains *less*, which is correct physics and a
## worthless assertion.
const YAW_RATE_NONE: float = 0.0
const YAW_RATE_SLOW: float = 1.0
const YAW_RATE_FAST: float = 3.0

## Simulated seconds each strafe measurement runs for.
const STRAFE_SECONDS: float = 3.0

## Speed the body is launched with before a strafe measurement, in m/s. Roughly
## a running jump: the technique needs something to rotate, and starting from a
## standstill measures the first half second of acceleration instead.
const LAUNCH_SPEED: float = 8.0

## Height the airborne tests run at. Far enough above the origin that nothing
## another test left behind can be landed on.
const SKY_HEIGHT: float = 300.0

var _profile: MovementProfile
var _body: PlayerController
var _input: BotIntentSource

## Result slot for [method _measure_strafe]. A member rather than a return value
## because a test reads it after awaiting the coroutine, and awaiting a
## coroutine's return value hands back a [Variant] that would have to be cast
## before it could be compared.
var _measured_speed: float = 0.0


func before_each() -> void:
	_profile = TestFixtures.movement_profile()
	_body = TestFixtures.make_bot_player(_profile)
	add_child(_body)
	_input = TestFixtures.bot_input_of(_body)


# --- The air-strafe invariant -------------------------------------------------

## The identity the whole movement model reduces to.
##
## [method PlayerController._air_accelerate] adds, along the wish direction,
## exactly [code]max_air_speed - velocity.dot(wish)[/code] -- the acceleration
## rate is far larger than that difference at any sane tick length, so the
## [code]minf[/code] always picks the difference. After the add, by construction:
## [codeblock]
##   velocity.dot(wish) == max_air_speed
##   i.e. |v| * cos(theta) == max_air_speed
## [/codeblock]
## where theta is the angle between the velocity and the wish direction. Speed is
## therefore free to grow without bound as long as theta grows with it, which is
## the entire technique. Break the clamp, add a drag term, or let ground
## acceleration handle the air case, and this equality is the first thing to go.
##
## The wish direction is read back off the body's own basis after the tick: only
## the head pitches, so the body's basis is exactly what
## [method PlayerController._get_wish_vector] used, and a strafe-right intent
## makes the wish direction the body's +X axis.
func test_air_strafe_holds_the_quake_invariant() -> void:
	await _launch_airborne()
	_input.command.move_direction = Vector2(1.0, 0.0)

	var ticks: int = int(STRAFE_SECONDS * SIM_HZ)
	var worst_error: float = 0.0
	for _tick: int in ticks:
		# Radians per second. See the file header.
		_input.aim(YAW_RATE_FAST, 0.0, SIM_DELTA)
		await step_ticks(1)
		var wish: Vector3 = _body.global_transform.basis.x
		worst_error = maxf(worst_error, absf(_body.velocity.dot(wish) - _profile.max_air_speed))

	# 1e-4 rather than an exact match because velocity is float32 and this is
	# 180 accumulated additions, not one comparison.
	assert_almost_eq(
		worst_error, 0.0, 1e-4,
		"velocity.dot(wish) must equal max_air_speed on every one of %d air ticks" % ticks,
	)
	# If the body never actually gained, the invariant above is being satisfied
	# trivially -- a body that cannot accelerate satisfies it at rest -- and the
	# test proves nothing.
	assert_gt(
		_body.get_horizontal_speed(), LAUNCH_SPEED * 1.4,
		"a %.1f s strafe should have gained substantial speed" % STRAFE_SECONDS,
	)


## Turning faster gains speed faster, and not turning gains nothing.
##
## The control case matters more than the two that gain: with no turn the wish
## direction stays put, [code]velocity.dot(wish)[/code] reaches
## [member MovementProfile.max_air_speed] on the first tick and add_speed is
## non-positive forever after, so the launch speed is all the body will ever
## have. Any change that lets a straight-line air hold accelerate has turned the
## air into ground.
func test_air_speed_grows_with_turn_rate() -> void:
	await _measure_strafe(YAW_RATE_NONE)
	var no_turn: float = _measured_speed
	await _measure_strafe(YAW_RATE_SLOW)
	var slow_turn: float = _measured_speed
	await _measure_strafe(YAW_RATE_FAST)
	var fast_turn: float = _measured_speed

	# Not "unchanged": the very first air tick spends one full max_air_speed
	# perpendicular to the launch velocity, and that one addition is all a
	# straight-line hold will ever get. Anything more means air acceleration
	# found a second bite.
	var single_tick_only: float = sqrt(
		LAUNCH_SPEED * LAUNCH_SPEED + _profile.max_air_speed * _profile.max_air_speed
	)
	assert_almost_eq(
		no_turn, single_tick_only, 0.01,
		"holding a strafe key without turning must gain exactly one tick of max_air_speed",
	)
	assert_gt(slow_turn, no_turn + 1.0, "a slow turn must out-gain no turn")
	assert_gt(fast_turn, slow_turn + 1.0, "a fast turn must out-gain a slow turn")


# --- Ground -------------------------------------------------------------------

## Friction brings a moving body to a complete stop, not to a crawl.
##
## [method PlayerController._apply_friction] uses Quake's stop-speed floor
## precisely so the last metre per second does not decay asymptotically, and
## snaps to zero under
## [member MovementProfile.friction_speed_epsilon]. A body that ends this test
## at 0.3 m/s reads as ice underfoot and would drift a player off a ledge after
## they let go of the keys.
func test_ground_friction_brings_the_body_to_rest() -> void:
	add_child(TestFixtures.make_floor(0.0))
	_body.global_position = Vector3(0.0, 0.5, 0.0)
	await step_ticks(30)

	assert_true(_body.is_on_floor(), "the body should have landed on the test floor")

	# Released controls, a running shove, and nothing but friction to answer it.
	_input.command.clear()
	_body.velocity = Vector3(_profile.walk_speed, 0.0, 0.0)
	var launch_speed: float = _body.get_horizontal_speed()
	await step_ticks(1)
	assert_lt(
		_body.get_horizontal_speed(), launch_speed,
		"friction must start biting on the first grounded tick",
	)

	await step_seconds(3.0)
	assert_almost_eq(
		_body.get_horizontal_speed(), 0.0, 1e-6,
		"friction must bring the body to a dead stop within 3 s",
	)


# --- Airborne state -----------------------------------------------------------

## With nothing under it, the body is airborne and falling.
##
## The floor test above is only meaningful if the body can tell the difference,
## and [member MovementProfile.floor_snap_length] is exactly the kind of number
## that, raised far enough, glues a body to a floor that is not there.
func test_body_is_airborne_with_no_floor_beneath_it() -> void:
	_body.global_position = Vector3(0.0, SKY_HEIGHT, 0.0)
	_input.command.clear()
	await step_ticks(10)

	assert_false(_body.is_on_floor(), "nothing is beneath the body, so it is not on a floor")
	assert_lt(_body.velocity.y, -1.0, "an airborne body accelerates downwards")
	assert_lt(
		_body.global_position.y, SKY_HEIGHT,
		"an airborne body loses height",
	)

	# Gravity is the profile's, not the engine's default 9.8: a wrong source here
	# would still fall, just wrongly, and every jump arc in the game would change.
	var expected_fall_speed: float = _profile.get_effective_gravity() * 10.0 * SIM_DELTA
	assert_almost_eq(
		-_body.velocity.y, expected_fall_speed, expected_fall_speed * 0.05,
		"fall speed after 10 ticks must come from MovementProfile.gravity",
	)


# --- Helpers ------------------------------------------------------------------

## Run one strafe measurement and leave the final horizontal speed in
## [member _measured_speed].
func _measure_strafe(yaw_rate: float) -> void:
	await _launch_airborne()
	_input.command.move_direction = Vector2(1.0, 0.0)
	for _tick: int in int(STRAFE_SECONDS * SIM_HZ):
		# Radians per second. See the file header.
		_input.aim(yaw_rate, 0.0, SIM_DELTA)
		await step_ticks(1)
	_measured_speed = _body.get_horizontal_speed()


## Park the body high in an empty sky, facing -Z, already moving that way.
##
## The trailing tick is not padding. [signal SceneTree.physics_frame] fires
## before the tree is stepped, so a coroutine that writes a state and immediately
## awaits one frame reads back the state from *before* that step. Burning one
## tick here puts every measurement that follows a whole step behind the writes,
## which is what makes the first sample of a strafe a real sample instead of the
## launch values.
func _launch_airborne() -> void:
	_body.global_position = Vector3(0.0, SKY_HEIGHT, 0.0)
	_body.rotation = Vector3.ZERO
	_body.velocity = Vector3(0.0, 0.0, -LAUNCH_SPEED)
	_input.command.clear()
	await step_ticks(1)
