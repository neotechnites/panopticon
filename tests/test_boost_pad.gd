extends TestCase

## [BoostPad]: the reusable Halo-style 45 degree launch pad.
##
## Unlike [code]tests/test_traps.gd[/code] this node never touches
## [MatchController] -- it is a movement toy, not a hazard the match rules hear
## about -- so nothing here needs a match, an arena, or a round. Every test
## instances the pad's own scene and a bare [PlayerController] body and proves
## the four things the brief asks for: a body that touches it is launched, the
## launch direction follows the node's own rotation, the strength is tunable,
## and a bot is launched exactly as a human is. A fifth test proves the design
## decision the brief asked to be made explicit: the pad OVERWRITES velocity
## rather than adding to it, so a slow approach and a sprinting approach leave
## on the identical vector.
##
## [b]Why every test captures the velocity off the signal instead of reading
## it back after a few physics ticks.[/b] [BoostPad] connects its own
## [method BoostPad._on_body_entered] in [method BoostPad._ready], before any
## test gets a chance to add a listener of its own -- so a listener a test
## connects afterwards always runs AFTER the pad's, in the same signal dispatch,
## on the same tick, before gravity or air friction have touched the body even
## once. Reading [member PlayerController.velocity] some ticks later instead
## would mix the launch itself with however much of the flight already
## happened -- and would mix it unevenly, because gravity subtracts from the Y
## axis every tick while air friction scales the horizontal speed
## multiplicatively, so the 45-degree split the pad actually launched at does
## not survive being read back late.

const PAD_SCENE_PATH: String = "res://scenes/props/boost_pad.tscn"

## Physics ticks a test allows for the Area3D to notice the body and fire
## [signal Area3D.body_entered]. Capture happens the instant it does; this is
## just the budget before a test gives up and reports whatever the box still
## holds (the zero it started with, which reads as an obvious failure).
const CONTACT_TICKS: int = 10

var _profile: MovementProfile


func before_each() -> void:
	_profile = TestFixtures.movement_profile()


# --- The four things the brief asks for ----------------------------------------


## A body that walks onto the pad is launched along its 45 degree arc, at its
## configured strength.
func test_a_body_that_enters_the_pad_is_launched() -> void:
	var pad: BoostPad = _make_pad()
	add_child(pad)
	var body: PlayerController = _make_bot()

	var velocity: Vector3 = (await _launch(pad, body, Vector3(0.0, 0.5, 0.0))) as Vector3

	var expected_direction: Vector3 = Vector3(0.0, 1.0, -1.0).normalized()
	assert_almost_eq(
		velocity.length(), pad.launch_speed, 1e-3,
		"the body leaves at exactly the pad's launch_speed",
	)
	assert_vec3_almost_eq(
		velocity.normalized(), expected_direction, 1e-4,
		"along the pad's own facing (-Z), tilted 45 degrees towards up",
	)


## Rotating the node aims it: yaw the pad and the horizontal launch direction
## turns by exactly as much, while the tilt off the ground stays the same.
func test_the_launch_direction_follows_the_pads_rotation() -> void:
	var pad: BoostPad = _make_pad()
	add_child(pad)

	var before_body: PlayerController = _make_bot()
	var before: Vector3 = (await _launch(pad, before_body, Vector3(0.0, 0.5, 0.0))) as Vector3

	pad.rotate_y(deg_to_rad(90.0))
	var after_body: PlayerController = _make_bot()
	var after: Vector3 = (await _launch(pad, after_body, Vector3(0.0, 0.5, 0.0))) as Vector3

	assert_almost_eq(after.y, before.y, 1e-3, "yawing the pad does not change how steeply it launches")
	assert_almost_eq(
		Vector2(after.x, after.z).length(), Vector2(before.x, before.z).length(), 1e-3,
		"or how fast -- only which way",
	)
	var turned: float = Vector2(before.x, before.z).angle_to(Vector2(after.x, after.z))
	assert_almost_eq(
		absf(turned), deg_to_rad(90.0), 1e-3,
		"the horizontal launch direction turned exactly as far as the node did",
	)


## [member BoostPad.launch_speed] is the strength knob a map author has two of:
## duplicate the pad, change the number, get a weak pad and a strong one that
## still throw the same way.
func test_strength_is_tunable() -> void:
	var pad: BoostPad = _make_pad()
	add_child(pad)

	pad.launch_speed = 10.0
	var weak_body: PlayerController = _make_bot()
	var weak: Vector3 = (await _launch(pad, weak_body, Vector3(0.0, 0.5, 0.0))) as Vector3

	pad.launch_speed = 20.0
	var strong_body: PlayerController = _make_bot()
	var strong: Vector3 = (await _launch(pad, strong_body, Vector3(0.0, 0.5, 0.0))) as Vector3

	assert_almost_eq(weak.length(), 10.0, 1e-3, "the weak pad launches at 10 m/s")
	assert_almost_eq(strong.length(), 20.0, 1e-3, "the strong pad launches at 20 m/s")
	assert_almost_eq(
		strong.normalized().dot(weak.normalized()), 1.0, 1e-4,
		"only the strength changed -- both launches point exactly the same way",
	)


## A bot -- a [PlayerController] driven by a [BotIntentSource], the same body
## [RingRunner] runs on -- is launched off the identical vector a human-shaped
## body is. There is no branch in [BoostPad] that could tell them apart: it
## reads [member PlayerController.velocity] and nothing about where the intent
## driving the body comes from.
func test_a_bot_is_launched_the_same_as_a_human() -> void:
	var pad: BoostPad = _make_pad()
	add_child(pad)

	var bot_body: PlayerController = _make_bot()
	var bot_velocity: Vector3 = (await _launch(pad, bot_body, Vector3(0.0, 0.5, 0.0))) as Vector3

	var human_body: PlayerController = _make_human()
	var human_velocity: Vector3 = (await _launch(pad, human_body, Vector3(0.0, 0.5, 0.0))) as Vector3

	assert_vec3_almost_eq(
		bot_velocity, human_velocity, 1e-4,
		"the pad never reads intent_source at all -- a bot and a human leave on the identical vector",
	)


# --- The design decision the brief asked to be made explicit -------------------


## Walking on and sprinting on leave on the same arc. The pad OVERWRITES
## velocity rather than adding to it, which is what makes it usable as a
## map-making piece: a level author can place one knowing exactly where a
## touch lands, rather than tuning it against however fast people happen to
## arrive.
func test_the_pad_overwrites_whatever_velocity_the_body_arrived_with() -> void:
	var pad: BoostPad = _make_pad()
	add_child(pad)

	var walker: PlayerController = _make_bot()
	var walker_launch: Vector3 = (await _launch(
		pad, walker, Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.0, -0.6),
	)) as Vector3

	var sprinter: PlayerController = _make_bot()
	var sprinter_launch: Vector3 = (await _launch(
		pad, sprinter, Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.0, -11.0),
	)) as Vector3

	assert_vec3_almost_eq(
		walker_launch, sprinter_launch, 1e-4,
		"a slow approach and a sprinting approach leave the pad on the identical fixed vector",
	)


# --- Helpers --------------------------------------------------------------------


func _make_pad() -> BoostPad:
	return (load(PAD_SCENE_PATH) as PackedScene).instantiate() as BoostPad


func _make_bot() -> PlayerController:
	return TestFixtures.make_bot_player(_profile)


## A [PlayerController] built off the same real scene a human plays, with the
## human input silenced exactly as [method TestFixtures.make_match] silences
## it -- there is no mouse or keyboard in a headless run, but the node graph
## driving the body is the one a human's session actually uses.
func _make_human() -> PlayerController:
	var body: PlayerController = (
		load(TestFixtures.PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as PlayerController
	TestFixtures.silence_human_input(body)
	body.profile = _profile
	return body


## Add [param body] to the tree, stand it at [param on_pad_at] with
## [param entry_velocity], and return the velocity [param pad] actually
## assigned it -- captured the instant [param pad]'s own [code]body_entered[/code]
## handler ran. See the file header for why that instant and not some tick
## later.
func _launch(
	pad: BoostPad,
	body: PlayerController,
	on_pad_at: Vector3,
	entry_velocity: Vector3 = Vector3.ZERO,
) -> Vector3:
	var box: Array = [Vector3.ZERO, false]
	pad.body_entered.connect(func(entered: Node3D) -> void:
		if entered == body and not box[1]:
			box[0] = body.velocity
			box[1] = true
	)

	add_child(body)
	body.global_position = on_pad_at
	body.velocity = entry_velocity

	for _tick: int in CONTACT_TICKS:
		await step_ticks(1)
		if box[1]:
			break

	if not box[1]:
		fail("the pad never fired body_entered for the body placed on it")
	return box[0] as Vector3
