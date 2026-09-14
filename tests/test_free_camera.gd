extends TestCase

## THE CAPTURE KEYS: H hides the HUD, C detaches a free camera.
##
## Both are dev toggles in the shape of T turbo and Y invincible: local, and
## invisible to the match. What is asserted here is the one thing that would
## make the free camera a gameplay change rather than a camera:
##
## [codeblock]
## 1. While the view is detached the local device reports an EMPTY intent, so
##    the packet this machine sends is the empty one and no key the pilot
##    presses can leak into the match. Bringing the view home gives the device
##    straight back.
## 2. The camera swap is a `current` flag and nothing else, and the body is
##    drawn while somebody else's camera is looking at it.
## 3. The HUD, crosshair included, goes off the screen and comes back.
## [/codeblock]
##
## [b]Why the node is built here[/b] -- the one shipped in match.tscn is
## [code]headless_inert[/code] and switches itself off in a test run, like
## [FxSpectatorView] before it. That it is wired at all, and inert, is asserted
## separately off the scene.

## Ticks to let the opening race settle before anything is measured.
const SETTLE_TICKS: int = 30

## The cull mask every camera in the game inherits from player.tscn. Layer 2,
## the owner-hidden layer, is the only bit it clears.
const CAMERA_CULL_MASK: int = 1048573

var _match: Node3D
var _controller: MatchController
var _hud: MatchHud
var _human_input: HumanIntentSource
var _player_camera: Camera3D
var _avatar: PrisonerAvatar

var _free: FxFreeCamera
var _camera: Camera3D


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = TestFixtures.match_rules()
	add_child(_match)

	_hud = _match.get_node("HUD/Root") as MatchHud
	_human_input = _match.get_node("Player/HumanInput") as HumanIntentSource
	_player_camera = _match.get_node("Player/Head/Camera") as Camera3D
	_avatar = _match.get_node("Player/Avatar") as PrisonerAvatar
	await step_ticks(SETTLE_TICKS)
	_build_camera()


## The camera makes a camera current and freezes an input device, and a held
## action outlives the case: both are global enough that a test which failed
## halfway must not leave them behind.
func after_each() -> void:
	if _free != null and is_instance_valid(_free):
		_free.set_detached(false)
	for action: StringName in [PlayerActions.MOVE_FORWARD, PlayerActions.FREECAM_UP]:
		if InputMap.has_action(action):
			Input.action_release(action)
	if _hud != null and is_instance_valid(_hud):
		_hud.set_hud_hidden(false)
	PrisonerAvatar.release_viewed_body()


# --- The wire -----------------------------------------------------------------

## The whole point: a detached view sends an empty intent, and only an empty one.
func test_detaching_zeroes_the_outgoing_intent_and_coming_home_restores_it() -> void:
	Input.action_press(PlayerActions.MOVE_FORWARD)
	var live: MoveIntent = _human_input.poll(SIM_DELTA)
	assert_almost_eq(
		live.move_direction.y, 1.0, 0.001, "the device drives the body while the view is home",
	)

	_free.set_detached(true)
	var frozen: MoveIntent = _human_input.poll(SIM_DELTA)
	assert_true(_human_input.is_frozen(), "the device is frozen while the view is out")
	assert_vec2_eq(frozen.move_direction, Vector2.ZERO, "no movement leaks into the match")
	assert_vec2_eq(frozen.look_delta, Vector2.ZERO, "and no aim does either")
	assert_false(frozen.jump_pressed, "nor any edge")
	assert_true(
		NetCodec.pack_intent(7, frozen) == NetCodec.pack_intent(7, MoveIntent.new()),
		"the packet on the wire is an empty intent's, byte for byte",
	)

	_free.set_detached(false)
	var back: MoveIntent = _human_input.poll(SIM_DELTA)
	assert_false(_human_input.is_frozen(), "the device is given back")
	assert_almost_eq(
		back.move_direction.y, 1.0, 0.001, "and drives the body again on the same key",
	)
	Input.action_release(PlayerActions.MOVE_FORWARD)


# --- The view -----------------------------------------------------------------

## The swap is two `current` flags. The player's camera is never written to.
func test_the_view_detaches_from_the_body_and_comes_home() -> void:
	assert_false(_camera.current, "the free camera is not current while it is stowed")
	assert_false(_free.is_detached(), "and the node is not flying")

	_free.set_detached(true)
	assert_true(_free.is_detached(), "C detaches the view")
	assert_true(_camera.current, "the free camera is what the pilot is looking through")
	assert_false(_player_camera.current, "and the body's camera is not")

	_free.set_detached(false)
	assert_false(_camera.current, "C again stows it")
	assert_true(_player_camera.current, "and hands the view back to the body")


## The pilot is looking AT their own body from ten metres away: it has to be
## drawn, and drawn whole, head included.
func test_the_body_is_drawn_while_a_camera_that_is_not_its_own_watches_it() -> void:
	assert_true(_avatar.is_viewed_first_person(), "the body is the viewed one while the view is home")
	assert_true(_avatar.is_head_hidden(), "so its own head is out of its own eye")

	_free.set_detached(true)
	_avatar.tick_first_person()
	assert_false(_avatar.is_viewed_first_person(), "a detached view is nobody's body")
	assert_false(_avatar.is_head_hidden(), "so the pilot sees their whole body")
	assert_false(_avatar.is_spine_hidden(), "torso included")
	assert_gt(
		float(_avatar.mesh.layers & CAMERA_CULL_MASK),
		0.0,
		"on a layer the cameras keep",
	)

	_free.set_detached(false)
	_avatar.tick_first_person()
	assert_true(_avatar.is_head_hidden(), "and the head goes back inside on the way home")


## One second of forward is one second of speed, along the camera's own facing.
func test_the_camera_flies_along_its_own_axes() -> void:
	_free.set_detached(true)
	var from: Vector3 = _camera.global_position
	var facing: Vector3 = -_camera.global_basis.z

	Input.action_press(PlayerActions.MOVE_FORWARD)
	_free.tick(1.0)
	Input.action_release(PlayerActions.MOVE_FORWARD)

	assert_vec3_almost_eq(
		_camera.global_position,
		from + facing * _free.metres_per_second,
		0.01,
		"W flies the camera forward at its own speed",
	)

	from = _camera.global_position
	Input.action_press(PlayerActions.FREECAM_UP)
	_free.tick(1.0)
	Input.action_release(PlayerActions.FREECAM_UP)
	assert_almost_eq(
		_camera.global_position.y - from.y,
		_free.metres_per_second,
		0.01,
		"E lifts it straight up, whatever it is looking at",
	)


## A body that is not flying is not moved by the keyboard at all.
func test_a_stowed_camera_ignores_the_keyboard() -> void:
	var from: Vector3 = _camera.global_position
	Input.action_press(PlayerActions.MOVE_FORWARD)
	_free.tick(1.0)
	Input.action_release(PlayerActions.MOVE_FORWARD)
	assert_vec3_almost_eq(_camera.global_position, from, 0.001, "the stowed camera stays put")


## The wheel is the speed control, and it is clamped.
func test_the_wheel_changes_the_fly_speed() -> void:
	_free.set_detached(true)
	var base: float = _free.get_speed()
	get_viewport().push_unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_gt(_free.get_speed(), base, "a notch up is faster")
	get_viewport().push_unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	assert_almost_eq(_free.get_speed(), base, 0.001, "and a notch down is back where it was")

	for _i: int in 60:
		get_viewport().push_unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	assert_ge(_free.get_speed(), FxFreeCamera.SPEED_MIN, "the wheel cannot stop the camera dead")


# --- The HUD ------------------------------------------------------------------

## H takes the readout off the screen, crosshair and all.
func test_h_hides_the_whole_hud_and_shows_it_again() -> void:
	_hud.tick()
	assert_true(_hud.is_readout_showing(), "the human is a prisoner and has a readout")
	assert_true(_hud.crosshair.is_visible_in_tree(), "the dot is on screen")

	_hud.set_hud_hidden(true)
	_hud.tick()
	assert_true(_hud.is_hud_hidden(), "the HUD is hidden")
	assert_false(_hud.visible, "the whole readout is off the screen")
	assert_false(_hud.crosshair.is_visible_in_tree(), "and the crosshair went with it")

	_hud.set_hud_hidden(false)
	_hud.tick()
	assert_false(_hud.is_hud_hidden(), "H again brings it back")
	assert_true(_hud.crosshair.is_visible_in_tree(), "dot included")


## FREECAM reads out next to INVINCIBLE and TURBO while the view is detached.
func test_the_hud_tags_a_detached_view() -> void:
	_hud.free_camera = _free
	_hud.tick()
	assert_eq_string(_hud.get_dev_text(), "", "nothing is tagged while the view is home")

	_free.set_detached(true)
	_hud.tick()
	assert_eq_string(_hud.get_dev_text(), "FREECAM", "a detached view is tagged")

	_hud.set_hud_hidden(true)
	_hud.tick()
	assert_eq_string(_hud.get_dev_text(), "", "and a hidden HUD tags nothing at all")


# --- The shipped scene --------------------------------------------------------

## The scene ships one, wired, and switched off in a headless sweep.
func test_the_shipped_match_wires_a_free_camera_and_leaves_it_inert() -> void:
	var shipped: FxFreeCamera = _match.get_node("FreeCamera") as FxFreeCamera
	assert_not_null(shipped, "match.tscn ships a FreeCamera")
	assert_true(shipped.is_inert(), "which is inert with no display server")
	assert_false(shipped.is_detached(), "and stowed")
	assert_same(shipped.camera, _match.get_node("FreeCamera/Camera"), "it has its own camera")
	assert_same(shipped.player_camera, _player_camera, "it knows the camera to hand back to")
	assert_same(shipped.human_input, _human_input, "and the device to freeze")
	assert_same(shipped.controller, _controller, "and the match to ask who is dead")
	assert_same(_hud.free_camera, shipped, "and the HUD reads its tag off that same node")


# --- Fixtures -----------------------------------------------------------------

func _build_camera() -> void:
	_free = FxFreeCamera.new()
	_free.name = "TestFreeCamera"
	_free.headless_inert = false
	_free.player_camera = _player_camera
	_free.human_input = _human_input
	_free.controller = _controller

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_free.add_child(_camera)
	_free.camera = _camera
	_match.add_child(_free)


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event
