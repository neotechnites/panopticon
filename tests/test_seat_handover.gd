extends TestCase

## THE TOWER CHANGING HANDS, and the camera finally noticing.
##
## A seat change is [method MatchController.start_round] writing a new
## [member Node3D.global_position] onto every body in the match on one tick, and
## the human's camera is a child of one of those bodies. The most dramatic thing
## in a match therefore used to arrive as a single-frame teleport: one frame on
## the ring, the next 38 m away and 12 m up, facing somewhere else, with nothing
## said about it. [SeatHandoverView] is the answer, and this file tests the seam
## between it and the match.
##
## [b]Why the node is built here rather than found in the scene[/b]
##
## The one shipped in [code]scenes/match/match.tscn[/code] is
## [code]headless_inert[/code] and switches itself off in a test run, which is
## right -- a headless bot sweep has no view to carry and no mouse to borrow. So
## the behaviour is tested on an instance built with that turned off and pointed
## at the same live [MatchController]; that the SHIPPED one is wired at all, and
## inert, is asserted separately off the scene.
##
## [b]The flight itself cannot be judged headless[/b] and nothing here pretends
## to. What is asserted is which camera is current, that the beat happens before
## the travel, that the travel ends on the player's own eye, who owns the mouse,
## and who yields to whom -- which is every failure that would leave a player
## staring at a black screen, spinning their aim, or scoped at nothing.

## Ticks to let the opening race and the first round settle before a test
## interferes with them.
const SETTLE_TICKS: int = 60

## Seconds the hand-driven ticks advance the view by. The view runs on the
## render tick and the runner drives the physics tick, so it is stepped by hand.
const VIEW_DELTA: float = 1.0 / 60.0

## How close the flight has to end to the player's own eye, in metres. Not zero:
## the arc is a sine of the travel fraction and has not quite closed one tick
## before the end, which is the point at which the last measurable frame is.
const ARRIVAL_TOLERANCE_METRES: float = 0.6

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _human: MatchParticipant

var _player_camera: Camera3D
var _human_input: HumanIntentSource
var _optic: WeaponOptic

var _view: SeatHandoverView
var _view_camera: Camera3D
var _profile: SeatHandoverProfile

var _activations: int = 0
var _deactivations: int = 0


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	# The portal finish these tests are written against. The shipped rules now
	# arm the finisher instead; see MatchRules.finisher_hunts_guard.
	_rules.finisher_hunts_guard = false
	_controller.rules = _rules
	add_child(_match)

	_human = _controller.get_human_participant()
	_player_camera = _match.get_node("Player/Head/Camera") as Camera3D
	_human_input = _match.get_node("Player/HumanInput") as HumanIntentSource
	_optic = _match.get_node("Player/Optic") as WeaponOptic

	# The shipped match opens with a race. Hand the tower to a BOT through the
	# seam the match itself scores on, so every test below starts from a real
	# round with the human out on the ring.
	var opener: MatchParticipant = _first_bot()
	if opener != null:
		opener.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)

	_stand_the_human_out_on_the_track()

	_profile = (
		load("res://resources/camera/default_seat_handover_profile.tres")
		as SeatHandoverProfile
	).duplicate() as SeatHandoverProfile
	# The SHIPPED profile cuts both ways -- see
	# test_the_shipped_profile_cuts_both_seat_changes below, which is the test of
	# that. Everything else in this file is about the flight itself, which is
	# still here, still supported and one exported boolean away, so this private
	# copy turns both directions back on.
	_profile.fly_to_tower = true
	_profile.fly_to_ring = true
	_build_view()


func after_each() -> void:
	# The view makes a camera current and mutes an input device; both are global
	# enough that a test which failed halfway must not leave them changed.
	if _view != null and is_instance_valid(_view):
		_view.stand_down()
	# stand_down hands the mouse BACK, which in a headless run is a device that
	# must stay silenced. Its own _exit_tree does the same thing when the case is
	# freed, so this is not optional politeness either.
	TestFixtures.silence_human_input(_match)


# --- The handover -------------------------------------------------------------

## Somebody else takes the tower, the round restarts around the human, and the
## camera carries them instead of cutting.
func test_a_seat_change_takes_the_view() -> void:
	assert_false(_view.is_active(), "nothing is being carried before the seat moves")

	_hand_tower_to(_first_bot_not_in_the_seat())

	if not assert_true(_view.is_active(), "the seat change armed the handover"):
		return
	assert_true(_view_camera.current, "the handover's own camera has the view")
	assert_false(_player_camera.current, "and the player's camera has stepped down")
	assert_eq_int(_activations, 1, "the handover announced itself exactly once")


## Taking the tower and being put back on the ring are the same move with
## different clocks, and the arrival is the slower one.
##
## The second half of this is also the outgoing shooter's regression test.
## [method MatchController.take_seat] clears the previous holder's shooter flag
## before it announces anything, which leaves them -- for the length of one call
## stack -- neither shooting, nor running, nor a ghost, and therefore ELIMINATED
## by the match's phase-derived fallback. A player who has just lost the tower is
## the LEAST spectating anybody in the match, and reading that flag at that
## instant refused to carry them anywhere.
func test_taking_the_tower_is_the_slower_move() -> void:
	_hand_tower_to(_human)
	if not assert_true(_view.is_active(), "the human taking the tower is carried"):
		return
	assert_eq_int(
		int(_view.get_direction()),
		int(SeatHandoverView.Direction.TO_TOWER),
		"and is carried TOWARDS the tower",
	)
	var to_tower: float = _view.get_total_seconds()
	_view.stand_down()

	_hand_tower_to(_first_bot_not_in_the_seat())
	if not assert_true(_view.is_active(), "losing it is carried too"):
		return
	assert_eq_int(
		int(_view.get_direction()),
		int(SeatHandoverView.Direction.TO_RING),
		"and is carried towards the ring",
	)
	assert_gt(
		to_tower, _view.get_total_seconds(),
		"the arrival takes longer than the reset: winning the tower is the moment",
	)


## The beat. The camera holds where the player was while the bodies teleport
## underneath it, and only then starts moving -- which is the whole of what
## makes the seat change read as an event rather than as a glitch.
func test_the_camera_holds_still_before_it_travels() -> void:
	var was: Vector3 = _player_camera.global_position
	_hand_tower_to(_first_bot_not_in_the_seat())
	if not assert_true(_view.is_active(), "the handover armed"):
		return

	_tick_for(_profile.hold_seconds * 0.5)

	assert_almost_eq(
		_view.get_travel_progress(), 0.0, 0.0001,
		"nothing has travelled yet",
	)
	assert_vec3_almost_eq(
		_view_camera.global_position, was, 0.01,
		"the view is still exactly where the player was when the seat moved",
	)
	assert_true(_view.is_active(), "and the handover is still running")


## The flight ends on the player's own eye, so handing the view back is not a
## second cut.
func test_the_flight_arrives_on_the_players_own_eye() -> void:
	_hand_tower_to(_human)
	if not assert_true(_view.is_active(), "the handover armed"):
		return

	# Half way: the camera is somewhere between the two, and demonstrably not
	# parked on either.
	_tick_for(_profile.hold_seconds + _profile.to_tower_seconds * 0.5)
	var midway: float = _view_camera.global_position.distance_to(
		_player_camera.global_position
	)
	assert_gt(midway, ARRIVAL_TOLERANCE_METRES, "half way through it is still travelling")

	# One tick short of the end, which is the last frame there is anything to
	# measure: tick() hands the view back the moment it arrives.
	_tick_for(_profile.to_tower_seconds * 0.5 - VIEW_DELTA * 0.5)
	assert_lt(
		_view_camera.global_position.distance_to(_player_camera.global_position),
		ARRIVAL_TOLERANCE_METRES,
		"and it finishes on the eye it is handing back to",
	)


## And then gives everything back. A handover that left its own camera current
## would be a match played from a fixed point on the deck.
func test_the_view_is_handed_back_when_the_flight_ends() -> void:
	_hand_tower_to(_first_bot_not_in_the_seat())
	if not assert_true(_view.is_active(), "the handover armed"):
		return

	_tick_for(_view.get_total_seconds() + VIEW_DELTA)

	assert_false(_view.is_active(), "the handover is over")
	assert_true(_player_camera.current, "the player has their own camera back")
	assert_false(_view_camera.current, "and the handover's camera has stepped down")
	assert_eq_int(_deactivations, 1, "it announced handing back exactly once")


# --- What it clears on the way ------------------------------------------------

## A player who lost the tower mid-shot does not begin their next lap looking
## down a 2.5x scope.
func test_a_seat_change_drops_the_zoom() -> void:
	if not assert_not_null(_optic, "the player body carries an optic"):
		return
	_optic.zoom_in()
	if not assert_true(_optic.is_zoom_requested(), "the player is scoped"):
		return

	_hand_tower_to(_first_bot_not_in_the_seat())

	assert_false(_optic.is_zoom_requested(), "the seat change let the scope go")
	assert_almost_eq(
		_optic.get_zoom_progress(), 0.0, 0.0001,
		"and dropped it all the way, not gradually",
	)


## The banked-mouse fix. A body being placed is held inert and not polling, so a
## second of unmuted mouse motion would land on the aim in one frame the instant
## it woke and spin a player who has just been handed the tower.
func test_the_mouse_is_taken_for_the_flight_and_handed_back() -> void:
	_human_input.set_active(true)
	_hand_tower_to(_human)
	if not assert_true(_view.is_active(), "the handover armed"):
		return

	assert_false(
		_human_input.is_processing_unhandled_input(),
		"the body's device is muted for the flight",
	)

	_tick_for(_view.get_total_seconds() + VIEW_DELTA)

	assert_true(
		_human_input.is_processing_unhandled_input(),
		"and is handed back on arrival",
	)


# --- The cut ------------------------------------------------------------------

## [b]Ryan's ruling, pinned.[/b] "i dont like the camera jumping from the middle
## to the start when you loose, i dont mind that just being a jump cut."
##
## The shipped profile cuts BOTH directions, because [RoundTransitionScreen] is
## raised on every [signal MatchController.round_started] and every seat change
## restarts the round -- so a flight would run underneath an opaque card. The
## flight is not deleted and this file still exercises all of it; what is
## asserted here is what the game actually ships with.
func test_the_shipped_profile_cuts_both_seat_changes() -> void:
	var shipped: SeatHandoverProfile = load(
		"res://resources/camera/default_seat_handover_profile.tres"
	) as SeatHandoverProfile
	if not assert_not_null(shipped, "the shipped handover profile loads"):
		return
	assert_false(shipped.flies(true), "taking the tower cuts")
	assert_false(shipped.flies(false), "and losing it cuts, which is what Ryan asked for")
	# Switching the whole node off would be the lazy way to get a cut, and it
	# would take reset_zoom_on_handover -- a bug fix, not a flourish -- with it.
	assert_true(shipped.enabled, "the node itself is still live")
	assert_true(shipped.reset_zoom_on_handover, "so a cut seat change still drops the scope")


## Losing the tower with the flight switched off takes nothing: no camera, no
## mouse, no announcement. A plain cut, exactly as the match did it before this
## node existed.
func test_losing_the_tower_cuts_when_the_flight_is_off() -> void:
	_profile.fly_to_ring = false
	_human_input.set_active(true)

	_hand_tower_to(_first_bot_not_in_the_seat())

	assert_false(_view.is_active(), "nothing is carried")
	assert_false(_view_camera.current, "the handover never took the view")
	assert_eq_int(
		int(_view.get_direction()),
		int(SeatHandoverView.Direction.NONE),
		"and is not pointed anywhere",
	)
	assert_eq_int(_activations, 0, "nothing was announced")
	# The mute is the banked-mouse fix for a body held for the length of a
	# FLIGHT. A cut holds the body for MatchController.SETTLE_PHYSICS_FRAMES --
	# two ticks -- so muting would buy nothing and is one more thing to leave on.
	assert_true(
		_human_input.is_processing_unhandled_input(),
		"and the player keeps their mouse through the cut",
	)


## The two directions are switched independently, so keeping the arrival and
## cutting the reset is a supported configuration rather than an accident.
func test_the_two_directions_are_switched_separately() -> void:
	_profile.fly_to_tower = true
	_profile.fly_to_ring = false

	_hand_tower_to(_first_bot_not_in_the_seat())
	assert_false(_view.is_active(), "losing the tower cuts")

	_stand_the_human_out_on_the_track()
	_hand_tower_to(_human)
	assert_true(_view.is_active(), "and taking it is still flown")


## A cut seat change still drops the scope.
##
## [b]The trap this pins.[/b] The zoom reset is a FIX -- a player who lost the
## tower mid-shot began their next lap looking down a 2.5x scope at the inside of
## the start pad -- and it lived inside the code path that armed the flight. Turn
## the flight off naively and the fix goes with it.
func test_a_cut_seat_change_still_drops_the_zoom() -> void:
	if not assert_not_null(_optic, "the player body carries an optic"):
		return
	_profile.fly_to_ring = false
	_optic.zoom_in()
	if not assert_true(_optic.is_zoom_requested(), "the player is scoped"):
		return

	_hand_tower_to(_first_bot_not_in_the_seat())

	assert_false(_view.is_active(), "the seat change cut")
	assert_false(_optic.is_zoom_requested(), "and let the scope go anyway")


# --- Who yields to whom -------------------------------------------------------

## [FxSpectatorView] outranks this node. Two nodes fighting over which camera is
## current is a black screen, and the dead player's claim is the more urgent.
func test_a_dead_player_is_not_carried() -> void:
	_human.respawn_hold_remaining = 2.0
	if not assert_true(
		_controller.is_spectating(_human), "the match says the human is dead"
	):
		return

	_hand_tower_to(_first_bot_not_in_the_seat())

	assert_false(_view.is_active(), "the handover left the dead player's camera alone")
	assert_false(_view_camera.current, "and never took the view")
	# And the trap that made this fail once, pinned so it cannot be walked back
	# into: the match clears the respawn hold on its way through
	# MatchController._freeze_runners, BEFORE it announces the seat change. Asked
	# at the moment of the signal, the match says this player is fine. They are
	# two seconds into a three second hold with a spectator camera orbiting their
	# body, and the answer has to come from the frame before.
	assert_false(
		_controller.is_awaiting_respawn(_human),
		"the seat change cleared the respawn hold on its way past",
	)
	assert_almost_eq(
		_controller.get_respawn_hold_remaining(_human), 0.0, 0.0001,
		"so nothing asked at the moment of the signal could have known",
	)


## Dying mid-flight hands the view straight back, so the spectator camera has
## something to take it from on its own next poll.
func test_dying_mid_flight_stands_the_handover_down() -> void:
	_hand_tower_to(_first_bot_not_in_the_seat())
	if not assert_true(_view.is_active(), "the handover armed"):
		return
	_tick_for(_profile.hold_seconds + _profile.to_ring_seconds * 0.25)

	_human.respawn_hold_remaining = 2.0
	_view.tick(VIEW_DELTA)

	assert_false(_view.is_active(), "the handover got out of the way")
	assert_true(_player_camera.current, "and left a camera current for the spectator to take")


## The opening grant of a match has nothing to carry the player FROM: no round
## has been played and every body is at its authored transform. Flying in from
## there would open every match with a swoop through the floor.
func test_the_opening_grant_of_a_match_is_not_a_handover() -> void:
	_rules.open_with_race = false
	_controller.restart()

	assert_false(_view.is_active(), "the tower being handed out at kickoff is not a handover")
	assert_false(_view_camera.current, "and nothing took the view")


## A seat change that does not actually move the player is not carried.
##
## The player is put back on the start line by every seat change, so a player
## who is ALREADY standing on the start line goes nowhere -- and neither does a
## shooter who converts the whole field, defends the tower and takes the seat
## again. Flying a camera from a pose to itself is a second of held breath for
## nothing, and it is the reason the handover verifies the distance a frame
## after the seat moves rather than trusting the signal.
func test_a_player_who_does_not_move_is_not_carried() -> void:
	# The first seat change finds the human out on the track and puts them back
	# on the line, which is a real move and is flown.
	_hand_tower_to(_first_bot_not_in_the_seat())
	if not assert_true(_view.is_active(), "a player out on the track is carried home"):
		return
	_tick_for(_view.get_total_seconds() + VIEW_DELTA)
	if not assert_false(_view.is_active(), "and the flight finishes"):
		return

	# The second finds them standing exactly where it is about to put them.
	_hand_tower_to(_first_bot_not_in_the_seat())

	assert_false(
		_view.is_active(),
		"a player put back where they already stand is not flown from their own eye",
	)
	assert_false(_view_camera.current, "and keeps their own camera throughout")


## A match with no human camera in it runs the identical seat-change path and
## never enters this node past its first guard. This is the bot harness, and it
## must be a no-op rather than an error.
func test_a_match_with_no_player_camera_is_a_no_op() -> void:
	_view.player_camera = null

	_hand_tower_to(_first_bot_not_in_the_seat())

	assert_false(_view.is_active(), "there is nobody to carry")
	assert_false(_view_camera.current, "and no view was taken")


# --- The shipped scene --------------------------------------------------------

## The node in the match scene is wired, and switches itself off headless.
func test_the_shipped_match_wires_a_handover_and_it_is_inert_headless() -> void:
	var shipped: SeatHandoverView = _match.get_node_or_null("SeatHandover") as SeatHandoverView
	if not assert_not_null(shipped, "scenes/match/match.tscn carries a SeatHandoverView"):
		return
	assert_not_null(shipped.profile, "it has a profile, so its numbers are tunable")
	assert_not_null(shipped.camera, "it has a camera of its own to carry the view with")
	assert_same(shipped.player_camera, _player_camera, "and knows whose view it is borrowing")
	assert_same(shipped.controller, _controller, "and which match to listen to")
	assert_not_null(shipped.optic, "and which optic a seat change should un-scope")
	assert_true(shipped.is_inert(), "and it is inert with no display server")
	assert_false(shipped.camera.current, "so a headless sweep is never played from it")
	assert_false(
		shipped.profile.flies(false),
		"and the seat change it ships with is a cut, not a flight",
	)


# --- Helpers ------------------------------------------------------------------

func _build_view() -> void:
	_view = SeatHandoverView.new()
	_view.name = "TestSeatHandover"
	_view.headless_inert = false
	_view.controller = _controller
	_view.player_camera = _player_camera
	_view.human_input = _human_input
	_view.optic = _optic
	_view.profile = _profile

	_view_camera = Camera3D.new()
	_view_camera.name = "Camera"
	_view.add_child(_view_camera)
	_view.camera = _view_camera

	add_child(_view)
	# Driven by hand at a delta the tests choose, exactly as the feedback nodes
	# are: this node runs on the render tick and the runner drives the physics.
	_view.set_process(false)
	_view.handover_changed.connect(_on_handover_changed)


func _on_handover_changed(active: bool) -> void:
	if active:
		_activations += 1
	else:
		_deactivations += 1


## Advance the view by [param seconds], in the fixed steps the shipped game runs
## it at, so the eased travel passes through the same states a played match does.
func _tick_for(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(VIEW_DELTA, remaining)
		_view.tick(step)
		remaining -= step


## Give the tower to [param participant] through the seam the match scores on:
## a finished lap. Nothing here reaches into MatchController's internals.
##
## The two zero-delta ticks are frames, not fudges. The view is stepped by hand
## here because it runs on the render tick and the runner drives the physics one,
## so a test has to supply the frames the shipped game supplies for free. Both
## are stepped by ZERO seconds, so neither consumes any of the handover's clock
## and everything measured below starts from the same zero a played match does.
##
## The one BEFORE is the frame the view samples who is watching on -- see
## [method SeatHandoverView._remember_who_is_watching], and note that by the time
## the signal below is emitted that answer is no longer available anywhere.
##
## The one AFTER is the verification frame: the seat change is announced before
## the bodies are placed, so whether the player actually moved is not knowable
## until the frame after it. See [method SeatHandoverView._take_the_view].
func _hand_tower_to(participant: MatchParticipant) -> void:
	if participant == null:
		return
	_view.tick(0.0)
	participant.tracker.lap_finished.emit(30.0, 240.0)
	_view.tick(0.0)


## Walk the human's body off the start line, so a round restart is a real move.
##
## [b]Not scene-setting for its own sake.[/b] Every seat change puts the human
## back on the start line, and a player who is already standing on it does not
## go anywhere -- which the handover correctly declines to fly, and which would
## make every test below assert against a cancelled handover. A player who is
## mid-lap when somebody takes the tower is the normal case, and this is it.
func _stand_the_human_out_on_the_track() -> void:
	if _human == null or _human.body == null or _controller.arena == null:
		return
	# A quarter turn round the ring axis, rather than an arbitrary offset: it
	# keeps the body on the track radius wherever the start marker happens to
	# be, and it is a long way from both the line and the tower on any arena.
	var centre: Vector3 = _controller.arena.global_position
	var offset: Vector3 = _human.body.global_position - centre
	_human.body.global_position = centre + offset.rotated(Vector3.UP, PI * 0.5)


func _first_bot() -> MatchParticipant:
	for participant: MatchParticipant in _controller.get_participants():
		if not participant.is_human():
			return participant
	return null


func _first_bot_not_in_the_seat() -> MatchParticipant:
	var seat: MatchParticipant = _controller.get_seat_participant()
	for participant: MatchParticipant in _controller.get_participants():
		if not participant.is_human() and participant != seat:
			return participant
	return null
