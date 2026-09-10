extends TestCase

## [AirControlPreset]: the named air-control tunings the movement playground
## offers back to back, and the guarantees that make comparing them mean
## anything.
##
## [b]What is actually under test here[/b]
##
## Not "is Carve the right answer" -- that is a judgement, and the presets exist
## precisely because it is not a judgement a test can make. What is testable is
## everything that would quietly invalidate the judgement:
##
## - a preset that differs from the shipped game in something other than air
##   control, so a back-to-back comparison is secretly also comparing walk speed
##   or the slide's boost cap;
## - a preset that writes into the shipped default while building, retuning the
##   real game from a dev scene;
## - a set whose members do not actually span the axis, so the player is being
##   offered a choice between four tunings that feel the same;
## - a live swap that leaves the body half-configured, so what is being felt is
##   neither preset.
##
## [b]The measurement[/b]
##
## [method _measure_held_hop_turn] reproduces the complaint that started this:
## run up to sprint pace, hold jump, hold forward, and turn the mouse at a
## constant 90 deg/s for three seconds. It reports how many of those 180 physics
## ticks the body spent touching the floor and how far the velocity's heading
## fell behind the commanded yaw. Those two numbers together are the whole
## phenomenon -- 4 ticks of floor contact out of 180 is why ground acceleration
## never runs, and the lag it produces is what reads as "my direction doesn't
## change".

const PRESET_PATHS: Array[String] = [
	"res://resources/movement/air_control_01_committed.tres",
	"res://resources/movement/air_control_02_carve.tres",
	"res://resources/movement/air_control_03_kite.tres",
	"res://resources/movement/air_control_04_footwork.tres",
]

const SHIPPED_PROFILE_PATH: String = "res://scenes/player/default_movement_profile.tres"

## The only fields a preset is allowed to differ from the shipped default in.
## Everything else being equal is what makes the presets comparable at all.
const AIR_CONTROL_FIELDS: Array[String] = [
	"max_air_speed", "air_acceleration", "air_friction", "auto_bunny_hop",
]

## Ticks each measurement runs for: three seconds at 60 Hz, long enough for the
## heading lag to settle at its steady state and short enough that a body under
## the shipped tuning has not left the test floor.
const MEASURE_TICKS: int = 180

## Constant mouse turn used by the measurement, in radians per second -- 90 deg/s,
## an unhurried deliberate turn rather than a flick. Handed to
## [method BotIntentSource.aim], which does the per-tick scaling; see the header
## of [code]tests/test_movement.gd[/code] for why nothing here touches
## [member MovementProfile.mouse_sensitivity].
const TURN_RATE: float = PI / 2.0

## Ticks of ground running before a measurement starts, so the body is at sprint
## pace and the first hop is a real one.
const WARM_UP_TICKS: int = 90

var _presets: Array[AirControlPreset] = []


func before_each() -> void:
	_presets.clear()
	for path: String in PRESET_PATHS:
		_presets.append(load(path) as AirControlPreset)


# --- The guarantees -----------------------------------------------------------

## Every preset carries the shipped numbers everywhere except air control.
##
## This is the assertion that makes the playground's A/B honest. A preset is
## authored as a derivation of [code]default_movement_profile.tres[/code] rather
## than as a copy of it exactly so this can hold by construction -- the test is
## here to catch the day somebody "simplifies" that into four full profiles and
## one of them drifts.
func test_a_preset_changes_air_control_and_nothing_else() -> void:
	var shipped: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	assert_not_null(shipped, "the shipped movement profile must load")

	for preset: AirControlPreset in _presets:
		var built: MovementProfile = preset.build()
		assert_not_null(built, "%s must build a profile" % preset.display_name)
		for field: String in _tunable_names(shipped):
			if AIR_CONTROL_FIELDS.has(field):
				continue
			var expected: Variant = shipped.get(field)
			var actual: Variant = built.get(field)
			check(
				actual == expected,
				"%s must leave %s at the shipped value -- expected %s, got %s" % [
					preset.display_name, field, str(expected), str(actual),
				],
			)


## Building a preset must not write into the resource it derives from.
##
## [member AirControlPreset.base] is the single process-wide instance of the
## shipped profile: the body in every scene, every bot and every other test in
## this process is holding that exact object. A [method Resource.duplicate] that
## went missing would turn one keypress in a dev scene into a permanent retune
## of the game, and nothing would report it.
func test_building_never_writes_into_the_shipped_default() -> void:
	var shipped: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	var before: Array[Variant] = []
	for field: String in AIR_CONTROL_FIELDS:
		before.append(shipped.get(field))

	for preset: AirControlPreset in _presets:
		var built: MovementProfile = preset.build()
		assert_false(
			built == shipped,
			"%s must build its own profile, not hand back the shipped one" % preset.display_name,
		)

	for index: int in AIR_CONTROL_FIELDS.size():
		var field: String = AIR_CONTROL_FIELDS[index]
		check(
			shipped.get(field) == before[index],
			"the shipped default's %s must survive building every preset -- was %s, now %s" % [
				field, str(before[index]), str(shipped.get(field)),
			],
		)


## The first preset is the control case: the shipped tuning, unaltered.
##
## The playground opens on it, so if it drifted the scene would open on a game
## nobody plays and every comparison would be against the wrong baseline.
func test_the_first_preset_is_the_shipped_tuning() -> void:
	var shipped: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	var control: MovementProfile = _presets[0].build()
	for field: String in AIR_CONTROL_FIELDS:
		check(
			control.get(field) == shipped.get(field),
			"the control preset's %s must match the shipped default -- expected %s, got %s" % [
				field, str(shipped.get(field)), str(control.get(field)),
			],
		)


## Each preset is named, described, and distinct from the others.
##
## The set is meant to be chosen between by feel, which needs a name and a
## sentence; a nameless preset is a row in a spreadsheet.
func test_every_preset_is_named_and_described() -> void:
	var seen: Array[String] = []
	for preset: AirControlPreset in _presets:
		assert_false(preset.display_name.is_empty(), "a preset must have a display name")
		assert_false(
			preset.feel.is_empty(),
			"%s must say what it feels like" % preset.display_name,
		)
		assert_false(
			seen.has(preset.display_name),
			"preset names must be distinct -- \"%s\" appears twice" % preset.display_name,
		)
		seen.append(preset.display_name)


# --- The axis -----------------------------------------------------------------

## The three auto-hop presets are a genuine ladder of air authority.
##
## Ordered, not merely different: the point of the set is that a player can walk
## it in one direction and feel the axis. The mechanism is
## [member MovementProfile.air_friction] and nothing else -- with jump held the
## body is airborne for all but a handful of ticks, so the steady-state angle
## between facing and travel is [code]acos(max_air_speed / speed)[/code], and
## air friction is the only knob that puts a ceiling on that speed. Raising
## [member MovementProfile.max_air_speed] alone raises the speed in the same
## proportion and moves the angle almost not at all, which is why the middle
## preset raises both.
func test_the_auto_hop_presets_are_a_ladder_of_air_authority() -> void:
	var committed: Dictionary = await _measure_held_hop_turn(_presets[0].build())
	var carve: Dictionary = await _measure_held_hop_turn(_presets[1].build())
	var kite: Dictionary = await _measure_held_hop_turn(_presets[2].build())

	assert_gt(
		float(committed["lag_degrees"]) - float(carve["lag_degrees"]), 20.0,
		"Carve must steer meaningfully better than Committed",
	)
	assert_gt(
		float(carve["lag_degrees"]) - float(kite["lag_degrees"]), 20.0,
		"Kite must steer meaningfully better than Carve",
	)
	assert_lt(
		float(kite["lag_degrees"]), 25.0,
		"Kite is the forgiving end: the heading must follow the mouse closely",
	)
	# All three keep the body in the air, which is what makes them one ladder
	# rather than three unrelated tunings.
	for entry: Dictionary in [committed, carve, kite]:
		assert_lt(
			float(entry["floor_ticks"]), 20.0,
			"an auto-hop preset must stay airborne while jump is held",
		)


## Turning auto bunny hop off is a different lever, and a bigger one.
##
## It changes no air number at all. With jump held the body simply stops
## re-launching itself, lands, and spends most of the run on the floor -- where
## [method PlayerController._accelerate] and [method PlayerController._apply_friction]
## have always been able to turn it. The measurement is the argument: the same
## air physics, an order of magnitude more floor contact, and the heading lag
## collapses.
func test_footwork_trades_flight_for_floor() -> void:
	var committed: Dictionary = await _measure_held_hop_turn(_presets[0].build())
	var footwork: Dictionary = await _measure_held_hop_turn(_presets[3].build())

	assert_gt(
		float(footwork["floor_ticks"]), float(committed["floor_ticks"]) * 10.0,
		"with jump held, Footwork must put the body on the floor and keep it there",
	)
	assert_lt(
		float(footwork["lag_degrees"]), 25.0,
		"once the body is on the floor the heading must follow the mouse",
	)
	# The air numbers are untouched, so a player who taps instead of holding
	# still gets the full Quake hop chain. That is the whole reason this preset
	# costs nothing at the skill ceiling.
	var built: MovementProfile = _presets[3].build()
	var shipped: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	assert_almost_eq(
		built.max_air_speed, shipped.max_air_speed, 1e-6,
		"Footwork must not touch the air-strafe cap",
	)
	assert_almost_eq(
		built.air_friction, shipped.air_friction, 1e-6,
		"Footwork must not touch air friction",
	)


# --- The live swap ------------------------------------------------------------

## [method PlayerController.set_profile] re-reads everything the profile is only
## read for once.
##
## The floor angle and the snap length are pushed into [CharacterBody3D] at
## ready, and the [IntentSource] takes its own copy at ready. A swap that
## assigned [member PlayerController.profile] and stopped there would leave a
## body obeying one profile's physics with another profile's walkable slope, and
## it would look exactly like a physics bug.
func test_a_live_swap_reconfigures_everything_derived_from_the_profile() -> void:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	add_child(body)

	var replacement: MovementProfile = TestFixtures.movement_profile()
	replacement.max_floor_angle_degrees = 30.0
	replacement.floor_snap_length = 0.75
	replacement.mouse_sensitivity = 0.01
	body.set_profile(replacement)

	assert_same(body.profile, replacement, "the body must be holding the new profile")
	assert_almost_eq(
		rad_to_deg(body.floor_max_angle), 30.0, 0.01,
		"the walkable slope must follow the new profile",
	)
	assert_almost_eq(
		body.floor_snap_length, 0.75, 1e-6,
		"the floor snap length must follow the new profile",
	)
	assert_same(
		body.intent_source.profile, replacement,
		"the intent source must be reconfigured against the new profile",
	)


## A swap keeps the body's momentum, so two tunings can be felt back to back.
##
## A swap that zeroed the velocity, ended the slide or re-armed the jump would
## make every comparison a comparison of standing starts, which is the one thing
## the playground is not for.
func test_a_live_swap_leaves_the_body_moving() -> void:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	add_child(body)
	add_child(TestFixtures.make_floor(0.0))
	body.global_position = Vector3(0.0, 0.6, 0.0)
	await step_ticks(1)

	var input: BotIntentSource = TestFixtures.bot_input_of(body)
	input.command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(WARM_UP_TICKS)

	var before: Vector3 = body.velocity
	assert_gt(before.length(), 1.0, "the body must actually be moving before the swap")
	body.set_profile(_presets[2].build())
	assert_vec3_almost_eq(
		body.velocity, before, 1e-6,
		"a profile swap must not touch the velocity it is being judged against",
	)


# --- Measurement --------------------------------------------------------------

## Run up to sprint pace, then hold jump and forward while turning the mouse at
## a constant rate. Returns floor ticks and the heading lag in degrees.
##
## Jump is [b]held[/b], not re-pressed, because that is what a hand does and it
## is the case the complaint came from. It is also the only case in which
## [member MovementProfile.auto_bunny_hop] makes any difference: a caller that
## re-presses on every tick keeps the jump buffer permanently full and so
## re-launches on the landing tick either way.
func _measure_held_hop_turn(profile: MovementProfile) -> Dictionary:
	var body: PlayerController = TestFixtures.make_bot_player(profile)
	add_child(body)
	var ground: StaticBody3D = TestFixtures.make_floor(0.0)
	add_child(ground)
	body.global_position = Vector3(0.0, 0.6, 0.0)
	await step_ticks(1)

	var input: BotIntentSource = TestFixtures.bot_input_of(body)
	input.command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(WARM_UP_TICKS)

	input.command.jump_pressed = true
	input.command.jump_held = true

	var floor_ticks: int = 0
	var velocity_rotation: float = 0.0
	var commanded_rotation: float = 0.0
	var previous_heading: float = _heading_of(body)
	var previous_yaw: float = body.rotation.y

	for _tick: int in MEASURE_TICKS:
		input.aim(TURN_RATE, 0.0, SIM_DELTA)
		await step_ticks(1)
		if body.is_on_floor():
			floor_ticks += 1
		var heading: float = _heading_of(body)
		velocity_rotation += wrapf(heading - previous_heading, -PI, PI)
		previous_heading = heading
		# The body's own yaw, not the commanded rate, so a clamp or a dropped
		# tick would show up as a smaller turn rather than as a phantom lag.
		commanded_rotation += wrapf(body.rotation.y - previous_yaw, -PI, PI)
		previous_yaw = body.rotation.y

	var result: Dictionary = {
		"floor_ticks": floor_ticks,
		"speed": body.get_horizontal_speed(),
		"lag_degrees": rad_to_deg(absf(commanded_rotation) - absf(velocity_rotation)),
	}
	body.queue_free()
	ground.queue_free()
	await step_ticks(1)
	return result


## Compass bearing of the body's horizontal velocity, in radians.
func _heading_of(body: PlayerController) -> float:
	return Vector2(body.velocity.x, body.velocity.z).angle()


## Names of the script-declared properties on a [MovementProfile]. Read off the
## instance rather than listed here, so a knob added to the profile tomorrow is
## covered by the equality check above without anyone remembering to add it.
func _tunable_names(profile: MovementProfile) -> Array[String]:
	var names: Array[String] = []
	for entry: Dictionary in profile.get_property_list():
		var usage: int = int(entry.get("usage", 0))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		names.append(String(entry.get("name", "")))
	return names
