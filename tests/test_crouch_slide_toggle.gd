extends TestCase

## Crouch and slide ship off; switched on in the debug menu they behave as before.

var _profile: MovementProfile
var _body: PlayerController


func before_each() -> void:
	_profile = TestFixtures.movement_profile()
	_body = TestFixtures.make_bot_player(_profile)
	add_child(_body)
	_body.intent_source = null
	add_child(TestFixtures.make_floor(0.0))
	_body.global_position = Vector3(0.0, 0.5, 0.0)
	_body.rotation = Vector3.ZERO


func _drive(intent: MoveIntent, ticks: int) -> void:
	for _tick: int in ticks:
		_body.set_intent(intent)
		await step_ticks(1)


## Settle on the floor, then press and hold the key once, at a standstill or after a run-up.
func _press(run_up: bool) -> void:
	var intent: MoveIntent = MoveIntent.new()
	if run_up:
		intent.move_direction = Vector2(0.0, 1.0)
	await _drive(intent, 110 if run_up else 30)
	intent.slide_pressed = true
	intent.slide_held = true
	await _drive(intent, 1)
	intent.slide_pressed = false
	await _drive(intent, 5)


func test_both_are_off_by_default() -> void:
	assert_false(GameSettings.new().crouch_enabled, "settings ship with crouch off")
	assert_false(GameSettings.new().slide_enabled, "settings ship with slide off")
	assert_false(MatchRules.new().crouch_enabled, "rules ship with crouch off")
	assert_false(MatchRules.new().slide_enabled, "rules ship with slide off")
	assert_false(_body.crouch_enabled, "a fresh body cannot crouch")
	assert_false(_body.slide_enabled, "a fresh body cannot slide")


func test_off_a_standing_press_does_nothing() -> void:
	var standing: float = _body.get_stance_height()
	var eye: float = _body.get_eye_height()
	await _press(false)
	assert_false(_body.is_crouching(), "no crouch while crouch is off")
	assert_almost_eq(_body.get_stance_height(), standing, 0.001, "the hitbox keeps its height")
	assert_almost_eq(_body.get_eye_height(), eye, 0.001, "the eye stays where it was")


func test_off_a_running_press_does_nothing() -> void:
	await _press(true)
	assert_false(_body.is_sliding(), "no slide while slide is off")
	assert_false(_body.is_crouching(), "and no crouch in its place")
	assert_almost_eq(_body.get_horizontal_speed(), _profile.ground_speed, 0.01, "no slide boost")


func test_on_a_standing_press_crouches() -> void:
	_body.crouch_enabled = true
	var standing: float = _body.get_stance_height()
	await _press(false)
	assert_true(_body.is_crouching(), "crouch on, the held key crouches")
	if _body.get_stance_height() > 0.0:
		assert_lt(_body.get_stance_height(), standing, "the hitbox shrinks")


func test_on_a_running_press_slides() -> void:
	_body.slide_enabled = true
	await _press(true)
	assert_true(_body.is_sliding(), "slide on, a fast forward press slides")


func test_slide_on_crouch_off_never_crouches_when_slow() -> void:
	_body.slide_enabled = true
	await _press(false)
	assert_false(_body.is_crouching(), "a slow press with crouch off stays standing")


func test_switching_slide_off_ends_a_slide_now() -> void:
	_body.slide_enabled = true
	await _press(true)
	assert_true(_body.is_sliding(), "the slide opened")
	_body.slide_enabled = false
	var intent: MoveIntent = MoveIntent.new()
	intent.move_direction = Vector2(0.0, 1.0)
	intent.slide_held = true
	await _drive(intent, 1)
	assert_false(_body.is_sliding(), "switched off, the slide closes on the next tick")


func test_the_settings_reach_the_rules_and_the_wire() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.crouch_enabled = true
	settings.slide_enabled = true
	var host: MatchRules = MatchRules.new()
	settings.apply_to_match_rules(host)
	var client: MatchRules = MatchRules.new()
	assert_true(NetCodec.unpack_rules(NetCodec.pack_rules(host), client), "the rules decode")
	assert_true(client.crouch_enabled, "the host's crouch reaches the client")
	assert_true(client.slide_enabled, "the host's slide reaches the client")
