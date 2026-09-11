extends TestCase

## BEING DEAD, and having something to do about it.
##
## The author, on the three second respawn hold: [i]"when someone gets shot, they
## jsut stop animating and sit there for 3 secdson, let give them a reload
## screen, or make them a free camera or something. same with if they die durring
## the initial race."[/i]
##
## Two nodes answer that, and this file tests the seam between them and the
## match:
##
## [codeblock]
## FxSpectatorView   -> a camera of its own, made current while you are dead.
##                      Orbits your body for the respawn hold; goes up on the
##                      overlook for a racer who is out for the rest of a race.
## MatchDeathScreen  -> DOWN, and a countdown; or OUT OF THE RACE, and no
##                      countdown, because a race has no deadline to compute.
## [/codeblock]
##
## [b]Why the nodes are built here rather than found in the scene[/b]
##
## The two shipped in [code]scenes/match/match.tscn[/code] are
## [code]headless_inert[/code] and switch themselves off in a test run, which is
## right -- a sweep has no view to take over and no mouse to borrow. So the
## logic is tested on instances built with that turned off, pointed at the same
## live [MatchController]; and that the SHIPPED ones are wired at all, and inert,
## is asserted separately off the scene.
##
## [b]The camera itself cannot be judged headless[/b] and no test here pretends
## to. What is asserted is which camera is current, what the camera is aimed at,
## and who owns the mouse -- all three of which are the failures that would
## leave a player staring at a black screen or spinning their aim on respawn.

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## Ticks a respawn hold is polled for before a test gives up on it.
const HOLD_BUDGET_TICKS: int = 240

## Ticks the overlook is held for to show it is not on a three second clock.
## Comfortably longer than the respawn hold.
const OVERLOOK_TICKS: int = 300

## How close the camera's aim has to be to a point to count as looking at it.
const FOCUS_TOLERANCE_METRES: float = 0.75

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _ghost_rules: GhostProfile
var _human: MatchParticipant

var _view: FxSpectatorView
var _view_camera: Camera3D
var _player_camera: Camera3D
var _human_input: HumanIntentSource
var _screen: MatchDeathScreen
var _profile: SpectatorProfile

var _activations: int = 0
var _deactivations: int = 0


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_ghost_rules = _rules.ghost_profile
	_controller.rules = _rules
	add_child(_match)

	_human = _controller.get_human_participant()
	_player_camera = _match.get_node("Player/Head/Camera") as Camera3D
	_human_input = _match.get_node("Player/HumanInput") as HumanIntentSource

	# The shipped match opens with a race. Hand the tower to a BOT, not to the
	# human, through the same seam the match scores on -- every test below needs
	# the human out on the ring where they can be killed.
	var opener: MatchParticipant = null
	for participant: MatchParticipant in _controller.get_participants():
		if not participant.is_human():
			opener = participant
			break
	if opener != null:
		opener.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)

	_profile = (
		load("res://resources/fx/default_spectator_profile.tres") as SpectatorProfile
	).duplicate() as SpectatorProfile
	_build_view()
	_build_screen()


func after_each() -> void:
	# The view makes a camera current and mutes an input device; both are global
	# enough that a test which failed halfway must not leave them changed. Its
	# own _exit_tree does this when the runner frees the case, and this runs
	# first and is cheap.
	if _view != null and is_instance_valid(_view):
		_view.stand_down()


# --- Alive --------------------------------------------------------------------

## While you are playing, the view is yours and this node is not there.
func test_the_view_stays_out_of_the_way_while_you_are_alive() -> void:
	assert_true(_human.is_running, "the human is a prisoner")
	_view.tick(SIM_DELTA)

	assert_false(_view.is_active(), "the spectator camera is not up")
	assert_false(_view_camera.current, "and is not the current camera")
	assert_eq_int(
		int(_controller.get_spectating_state(_human)),
		int(MatchController.Spectating.NONE),
		"the match says the human is playing",
	)

	_screen.tick()
	assert_false(_screen.is_showing(), "and nothing is written over the screen")


## A shooter is not dead either, however still they are standing.
func test_the_seat_holder_is_not_spectating() -> void:
	var seat: MatchParticipant = _controller.get_seat_participant()
	if not assert_not_null(seat, "somebody holds the tower"):
		return
	assert_eq_int(
		int(_controller.get_spectating_state(seat)),
		int(MatchController.Spectating.NONE),
		"the guard is playing, not watching",
	)


# --- The respawn hold ---------------------------------------------------------

## Shot: the camera comes off the body and the screen says how long.
##
## This is the whole of Ryan's complaint answered in one test. The body is frozen
## -- that is correct and asserted elsewhere -- and the VIEW is not.
func test_a_shot_player_gets_a_camera_and_a_countdown() -> void:
	assert_true(_controller.apply_hit(_human), "the human is shot")
	assert_true(_controller.is_awaiting_respawn(_human), "and is on the respawn clock")

	_take_the_view()
	_screen.tick()

	assert_true(_view.is_active(), "the spectator camera took over")
	assert_eq_int(
		int(_view.get_state()), int(MatchController.Spectating.RESPAWNING),
		"showing the respawn view",
	)
	assert_true(_view_camera.current, "its camera is the current one")
	assert_false(_player_camera.current, "and the frozen body's camera is not")
	assert_eq_int(_activations, 1, "the change was announced once")

	# Aimed at the body it just came off, at about head height -- so the player
	# sees the spot they were taken from.
	assert_vec3_almost_eq(
		_view.get_focus_point(),
		_human.body.global_position + Vector3(0.0, _profile.death_focus_height_metres, 0.0),
		1e-4,
		"the camera is looking at the body it just left",
	)
	assert_almost_eq(
		_view_camera.global_position.distance_to(_view.get_focus_point()),
		Vector2(_profile.death_radius_metres, _profile.death_height_metres).length(),
		FOCUS_TOLERANCE_METRES,
		"from the distance the profile asks for",
	)
	assert_gt(
		_view_camera.global_position.y, _human.body.global_position.y,
		"and from above it, not from inside the floor",
	)

	# The screen.
	assert_true(_screen.is_showing(), "the death screen is up")
	assert_eq_int(
		int(_screen.get_shown_state()), int(MatchController.Spectating.RESPAWNING),
		"showing the respawn state",
	)
	assert_eq_string(
		_screen.get_countdown_text(), "%.1f" % _ghost_rules.respawn_delay_seconds,
		"and the countdown starts at the profile's own duration",
	)


## The countdown counts down, and the camera keeps moving while it does.
##
## The drift is not decoration: a perfectly static third-person shot of a
## motionless body is exactly the "the game has frozen" reading this view exists
## to prevent.
func test_the_countdown_falls_and_the_camera_drifts() -> void:
	assert_true(_controller.apply_hit(_human), "the human is shot")
	_take_the_view()
	_screen.tick()

	var first_text: String = _screen.get_countdown_text()
	var first_position: Vector3 = _view_camera.global_position

	await step_ticks(int(_ghost_rules.respawn_delay_seconds * SIM_HZ * 0.5))
	_view.tick(SIM_DELTA * (_ghost_rules.respawn_delay_seconds * SIM_HZ * 0.5))
	_screen.tick()

	assert_true(_controller.is_awaiting_respawn(_human), "still on the clock")
	assert_lt(
		_controller.get_respawn_hold_remaining(_human),
		_ghost_rules.respawn_delay_seconds,
		"the hold has run down",
	)
	if not assert_true(first_text != _screen.get_countdown_text(), "and the screen says so"):
		return
	assert_gt(
		_view_camera.global_position.distance_to(first_position), 0.1,
		"the camera drifted rather than sitting perfectly still",
	)


## When the match puts the body back, the player gets their own eyes back.
##
## The restore is EXPLICIT -- see [member FxSpectatorView.player_camera] -- and
## the failure it guards against is a black screen, because Godot does not
## promise which camera becomes current when the current one steps down.
func test_the_view_hands_back_when_the_body_is_placed() -> void:
	assert_true(_controller.apply_hit(_human), "the human is shot")
	_take_the_view()
	assert_true(_view.is_active(), "the view took over")

	for _tick: int in HOLD_BUDGET_TICKS:
		await step_ticks(1)
		_view.tick(SIM_DELTA)
		if not _controller.is_awaiting_respawn(_human):
			break
	_view.tick(SIM_DELTA)
	_screen.tick()

	assert_false(_controller.is_awaiting_respawn(_human), "the hold ran out")
	assert_false(_view.is_active(), "and the spectator camera stood down")
	assert_false(_view_camera.current, "it is not the current camera any more")
	assert_true(_player_camera.current, "the player's own camera is, explicitly")
	assert_eq_int(_deactivations, 1, "the hand-back was announced once")
	assert_false(_screen.is_showing(), "and the screen is gone")


## The dead player's mouse belongs to the spectator camera, not to their body.
##
## [b]This is a bug fix, not politeness.[/b] [HumanIntentSource] banks mouse
## motion in pixels and drains it when [PlayerController] polls, and a held body
## is not being polled -- so three seconds of banked mouse would land on the aim
## in a single frame the instant the body woke, and spin the player round.
## Muting the device drops the bank; the view reads the mouse itself instead.
func test_the_dead_players_mouse_is_taken_off_their_body() -> void:
	# The fixture silences human input before the scene enters the tree, so the
	# claim is about the TOGGLE and the test switches it back on first.
	_human_input.set_active(true)
	assert_true(
		_human_input.is_processing_unhandled_input(),
		"the device is reading the mouse while the player is alive",
	)

	assert_true(_controller.apply_hit(_human), "the human is shot")
	_view.tick(SIM_DELTA)
	assert_false(
		_view.is_active(),
		"the camera has not cut away yet -- the hit is still playing from inside the eyes",
	)
	assert_false(
		_human_input.is_processing_unhandled_input(),
		"but the mouse is already off the body, so nothing can bank up in the gap",
	)

	# Waited out on the MATCH's clock, not on the view's: the mouse comes back
	# when the player does, which is when the respawn hold ends.
	for _tick: int in HOLD_BUDGET_TICKS:
		await step_ticks(1)
		_view.tick(SIM_DELTA)
		if not _controller.is_awaiting_respawn(_human):
			break
	_view.tick(SIM_DELTA)

	assert_false(_view.is_active(), "the view has stood down")
	assert_true(
		_human_input.is_processing_unhandled_input(),
		"and the player has their mouse back",
	)


## The camera does not cut away until the hit has finished playing.
##
## [b]The failure this catches is losing the best part of the game.[/b]
## [FxHitReaction] whips the PLAYER's camera; this node's camera is a different
## one. A spectator view that took over on the frame of the kill would cut away
## one frame into the whip and throw the whole reaction away -- so it waits out
## [member SpectatorProfile.enter_delay_seconds] first, and that wait is longer
## than the reaction it is waiting for.
func test_the_camera_waits_for_the_hit_to_finish_before_it_cuts_away() -> void:
	assert_true(_controller.apply_hit(_human), "the human is shot")

	var elapsed: float = 0.0
	for _tick: int in HOLD_BUDGET_TICKS:
		if _view.is_active():
			break
		_view.tick(SIM_DELTA)
		elapsed += SIM_DELTA

	assert_true(_view.is_active(), "the view did take over eventually")
	assert_almost_eq(
		elapsed, _profile.enter_delay_seconds, 2.0 * SIM_DELTA,
		"after the profile's own delay, and not on the frame of the kill",
	)

	var feedback: FeedbackProfile = load(
		"res://scenes/fx/default_feedback_profile.tres"
	) as FeedbackProfile
	if feedback != null:
		assert_ge(
			_profile.enter_delay_seconds, feedback.impact_recover_seconds,
			"and the delay outlasts the camera whip it is waiting for",
		)
	assert_lt(
		_profile.enter_delay_seconds, _ghost_rules.respawn_delay_seconds,
		"while still leaving most of the hold to actually spectate",
	)


# --- The opening race ---------------------------------------------------------

## A racer who falls is out for the rest of the race, and gets the overlook.
##
## [b]The ruling stands and is not changed here[/b]: [i]"if a racer falls durring
## the opening race they can be out."[/i] What changes is what they LOOK AT while
## they are out, and it has to be handled separately from the round case for two
## reasons -- there is no clock to count down, and the body has been buried a
## hundred metres under the deck by [method MatchController._park_body], so there
## is nothing down there to orbit.
func test_a_racer_who_is_out_gets_the_overlook_and_no_countdown() -> void:
	# Back to the top of the match: before_each handed the tower over to get a
	# round, and this is the test that wants the race.
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)
	if not assert_eq_string(_controller.get_phase_name(), "RACE", "the match is racing"):
		return

	assert_true(_controller.handle_fall(_human), "the human falls out of the race")
	assert_false(_human.is_running, "and is out")
	assert_false(_human.is_ghost, "with no shooter, there is no ghost to become")
	assert_false(_controller.is_awaiting_respawn(_human), "and no respawn clock to wait on")

	_view.tick(SIM_DELTA)
	_screen.tick()

	assert_eq_int(
		int(_controller.get_spectating_state(_human)),
		int(MatchController.Spectating.ELIMINATED),
		"the match says they are out rather than respawning",
	)
	assert_true(_view.is_active(), "the view took over")
	assert_eq_int(
		int(_view.get_state()), int(MatchController.Spectating.ELIMINATED),
		"showing the overlook",
	)
	assert_true(_view_camera.current, "its camera is current")

	# Up, outside the ring, looking at the arena -- not at a body buried under
	# the deck.
	var arena: Node3D = _match.get_node("Arena") as Node3D
	assert_vec3_almost_eq(
		_view.get_focus_point(),
		arena.global_position + Vector3(0.0, _profile.overlook_focus_height_metres, 0.0),
		1e-4,
		"the overlook watches the ring, not the corpse",
	)
	assert_gt(
		_view_camera.global_position.y - arena.global_position.y,
		_profile.overlook_height_metres * 0.5,
		"and watches it from above",
	)
	assert_lt(
		_human.body.global_position.y, arena.global_position.y - 50.0,
		"which is just as well, because the body is buried in the pen",
	)

	# And no number, because there is no deadline anybody can compute.
	assert_true(_screen.is_showing(), "the screen is up")
	assert_eq_string(_screen.get_countdown_text(), "", "with no countdown on it")


## The overlook is not on a three second clock. A race can outlast one many
## times over, and the player has to still have a view at the end of it.
func test_the_overlook_outlasts_a_respawn_hold() -> void:
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)
	if not assert_eq_string(_controller.get_phase_name(), "RACE", "the match is racing"):
		return
	assert_true(_controller.handle_fall(_human), "the human falls out of the race")

	var budget: int = maxi(OVERLOOK_TICKS, int(_ghost_rules.respawn_delay_seconds * SIM_HZ) * 3)
	for _tick: int in budget:
		await step_ticks(1)
		# BOTH are stepped. Each is set_process(false) in this file and driven by
		# hand, and the first version of this test drove only the view -- so the
		# screen was never ticked at all and the assertion below read a Control
		# that had simply never been shown. Nothing was clearing the state; the
		# test was not asking.
		_view.tick(SIM_DELTA)
		_screen.tick()
		if _controller.get_phase_name() != "RACE":
			break
		if not _view.is_active():
			fail("the overlook stood down while the racer was still out")
			break

	if _controller.get_phase_name() == "RACE":
		assert_true(_view.is_active(), "still watching, long past three seconds")
		assert_true(_screen.is_showing(), "and still told why")


# --- The shipped wiring -------------------------------------------------------

## Both nodes are actually in the match scene, and both switch themselves off in
## a headless run.
##
## The wiring check matters more than it looks: this whole feature is a pair of
## additive nodes, and a pair of additive nodes that nobody instanced is a
## feature that does not exist. The inertness check is the other half -- the bot
## harness runs thousands of matches with no viewport and must pay nothing for a
## view nobody is looking through.
func test_the_match_scene_ships_both_and_they_are_headless_inert() -> void:
	var shipped_view: FxSpectatorView = _match.get_node_or_null(
		"SpectatorView"
	) as FxSpectatorView
	if not assert_not_null(shipped_view, "scenes/match/match.tscn carries a SpectatorView"):
		return
	assert_not_null(shipped_view.profile, "wired to a SpectatorProfile")
	assert_not_null(shipped_view.camera, "with a camera of its own")
	assert_not_null(shipped_view.controller, "and a match to ask")
	assert_same(
		shipped_view.player_camera, _player_camera,
		"and it knows which camera to give the view back to",
	)
	assert_same(
		shipped_view.human_input, _human_input,
		"and whose mouse to borrow while the body is frozen",
	)
	assert_true(shipped_view.is_inert(), "and it is inert with no display server")
	assert_false(shipped_view.camera.current, "so it never takes the view in a sweep")

	var shipped_screen: MatchDeathScreen = _match.get_node_or_null(
		"DeathScreen"
	) as MatchDeathScreen
	if not assert_not_null(shipped_screen, "and a DeathScreen"):
		return
	assert_not_null(shipped_screen.controller, "wired to the match")
	assert_true(shipped_screen.is_inert(), "and inert with no display server")


## Turning the profile off restores the frozen first-person shot this replaced.
## The honest control for "is it better".
func test_the_profile_switch_turns_the_view_off() -> void:
	_profile.enabled = false
	assert_true(_controller.apply_hit(_human), "the human is shot")
	_take_the_view()

	assert_false(_view.is_active(), "no spectator camera")
	assert_false(_view_camera.current, "the view stayed where it was")


# --- Fixtures -----------------------------------------------------------------

## A live [FxSpectatorView] with its own camera, pointed at the match, with the
## headless switch-off deliberately turned off. See the class description.
func _build_view() -> void:
	_view = FxSpectatorView.new()
	_view.name = "TestSpectatorView"
	_view.headless_inert = false
	_view.controller = _controller
	_view.player_camera = _player_camera
	_view.human_input = _human_input
	_view.profile = _profile

	_view_camera = Camera3D.new()
	_view_camera.name = "Camera"
	_view.add_child(_view_camera)
	_view.camera = _view_camera

	add_child(_view)
	# Driven by hand from the tests, at a delta they choose, exactly as the
	# feedback nodes are: this node runs on the render tick and the runner drives
	# the physics tick.
	_view.set_process(false)
	_view.spectating_changed.connect(_on_spectating_changed)
	# The scene's own player camera is the one that was current when the match
	# loaded; re-assert it so a previous test in this process cannot have left
	# some other camera holding the viewport.
	_player_camera.current = true


func _build_screen() -> void:
	_screen = MatchDeathScreen.new()
	_screen.name = "TestDeathScreen"
	_screen.headless_inert = false
	_screen.controller = _controller
	add_child(_screen)
	_screen.set_process(false)


## Step the view until it takes the view, or give up.
##
## Not a single tick: the view deliberately waits out
## [member SpectatorProfile.enter_delay_seconds] so the hit reaction can play
## from inside the victim's own eyes first. That wait has its own test.
func _take_the_view() -> void:
	for _tick: int in HOLD_BUDGET_TICKS:
		_view.tick(SIM_DELTA)
		if _view.is_active():
			return


func _on_spectating_changed(active: bool) -> void:
	if active:
		_activations += 1
	else:
		_deactivations += 1
