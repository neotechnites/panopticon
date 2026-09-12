extends TestCase

## [RoundTransitionScreen]: the card between two rounds, and the three ways it
## is stopped from being a tax.
##
## A round used to end and the next one begin on the same tick.
## [method MatchController.start_round] writes a new
## [member Node3D.global_position] onto every body in the match, so the most
## structural moment in a match arrived as a teleport with nothing said about it.
## Ryan asked for "a transition screen each round that shows the map or
## something"; this file tests the seam between that card and the match.
##
## [b]Three failures are being defended against, and they fail in opposite
## directions.[/b]
##
## 1. [b]The card must appear, and say the true thing.[/b] It keeps no tally --
##    every line is read back off [MatchController] when the card is raised -- so
##    the failure mode is not a wrong sum, it is a card that reads the wrong
##    field and announces the wrong round or the wrong tower.
## 2. [b]It must never cost a headless run anything at all.[/b] The bot harness
##    and this suite cross round boundaries constantly, and a card that held them
##    for a second and a half each time -- or, worse, PAUSED the tree and left it
##    paused -- would be the single most expensive thing in the project. The
##    shipped node switches itself off with no display server, and that is
##    asserted against the shipped node in the shipped scene rather than against
##    a flag.
## 3. [b]It must give the match back.[/b] The card pauses the tree so no bot runs
##    a metre of the new round while the player reads it, which means every path
##    out of the card is a path that has to unpause -- the clock, a skip, a won
##    match and a restart alike.
##
## Everything runs against the real [code]scenes/match/match.tscn[/code], and
## rounds are turned over the way the match itself turns one over: through
## [signal MatchLapTracker.lap_finished]. No phase is forged and nothing private
## is written.

const SCREEN_SCENE_PATH: String = "res://scenes/ui/round_transition_screen.tscn"
const ANNOUNCEMENT_PATH: String = "res://resources/rules/default_match_announcement.tres"

## Ticks to let the opening race and the first round settle before a test
## interferes with them.
const SETTLE_TICKS: int = 60

## Seconds the hand-driven ticks advance the card by. The card runs on the render
## tick and the suite drives the physics tick, so it is stepped by hand -- the
## same seam [SeatHandoverView] is stepped through.
const CARD_DELTA: float = 1.0 / 60.0

var _match: Node3D
var _controller: MatchController
var _human: MatchParticipant

var _card: RoundTransitionScreen
var _profile: MatchAnnouncementProfile

var _shows: int = 0
var _dismissals: int = 0
var _announced_round: int = 0


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	var rules: MatchRules = TestFixtures.match_rules()
	# The portal finish these tests are written against. The shipped rules now
	# arm the finisher instead; see MatchRules.finisher_hunts_guard.
	rules.finisher_hunts_guard = false
	_controller.rules = rules
	add_child(_match)

	_human = _controller.get_human_participant()

	# The shipped match opens with a race. Hand the tower to a BOT through the
	# seam the match itself scores on, so every test below starts from a real
	# round with the human out on the ring.
	var opener: MatchParticipant = _first_bot()
	if opener != null:
		opener.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)

	_build_card()


func after_each() -> void:
	# The card pauses the whole SceneTree. A test that failed halfway through one
	# must not hand the next test in the same process a paused world -- which
	# would look like every body in it having stopped working.
	if _card != null and is_instance_valid(_card):
		_card.hide_transition()
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	TestFixtures.silence_human_input(_match)


# --- The shipped scene --------------------------------------------------------

## The node in the match scene is wired, and switches itself off headless.
##
## A [NodePath] export that is not named in a scene's [code]node_paths[/code]
## header resolves to null at load with no error at all, which is how
## [code]PauseMenu.camera[/code] was silently broken on this project once
## already. A round card with a null controller is exactly that failure: rounds
## turn over, nothing is connected, and the player sees nothing.
func test_the_match_scene_carries_a_wired_round_card() -> void:
	var shipped: RoundTransitionScreen = _shipped()
	if not assert_not_null(shipped, "scenes/match/match.tscn carries a RoundTransitionScreen"):
		return
	assert_same(shipped.controller, _controller, "it watches this match's controller")
	assert_not_null(shipped.pause_menu, "and knows the pause menu it must not unpause under")
	assert_not_null(shipped.announcements, "and its durations are tunable in a .tres")
	assert_true(shipped.hold_match, "it holds the match for its own length")
	assert_true(shipped.is_inert(), "and it is inert with no display server")


## [b]The load-bearing test of this file.[/b] A headless round boundary costs
## nothing: no card, no pause, no wait.
##
## The bot harness and this suite turn rounds over constantly. If the shipped
## card ever stopped checking for a display server, every sweep in the project
## would slow to the card's duration per round and the tree would be paused for
## most of it.
func test_headless_crosses_a_round_boundary_with_no_card_and_no_pause() -> void:
	var shipped: RoundTransitionScreen = _shipped()
	if not assert_not_null(shipped, "the shipped card is there to be silent"):
		return
	var before: int = _controller.get_round_number()

	_turn_the_round_over()

	assert_gt(
		float(_controller.get_round_number()), float(before),
		"a real round boundary was crossed",
	)
	assert_false(shipped.is_showing(), "and nothing was shown")
	assert_false(shipped.is_holding_the_match(), "and nothing was held")
	assert_false(get_tree().paused, "and the tree is running, which is the whole point")


## Zeroing the duration takes the card off entirely, which is the control Ryan
## reaches for first when he is tired of looking at it.
func test_a_zero_duration_is_no_card_at_all() -> void:
	_profile.round_card_seconds = 0.0
	_turn_the_round_over()
	assert_false(_card.is_showing(), "round_card_seconds = 0 shows nothing")

	_profile.round_card_seconds = 1.6
	_profile.round_card_enabled = false
	_turn_the_round_over()
	assert_false(_card.is_showing(), "and so does the switch")

	_profile.round_card_enabled = true
	_profile.enabled = false
	_turn_the_round_over()
	assert_false(_card.is_showing(), "and so does switching every announcement off")


# --- The card appears between rounds ------------------------------------------

## A round turning over raises the card, once, for the length the profile says.
func test_a_round_boundary_raises_the_card() -> void:
	assert_false(_card.is_showing(), "a live round shows no card")

	_turn_the_round_over()

	if not assert_true(_card.is_showing(), "the round boundary raised the card"):
		return
	assert_eq_int(_shows, 1, "exactly once")
	assert_eq_int(
		_announced_round, _controller.get_round_number(),
		"and it announced the round the match has actually armed",
	)
	assert_almost_eq(
		_card.get_total_seconds(), _profile.get_round_card_seconds(), 0.0001,
		"for the length the profile says and no other",
	)


## Every word on the card is read back off the controller when it is raised.
## There is no second tally here, exactly as there is none in
## [MatchResultScreen].
func test_the_card_names_the_round_the_map_and_the_tower() -> void:
	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return

	assert_eq_string(
		_label("%Round"), "ROUND %d" % _controller.get_round_number(),
		"the round number is the match's own",
	)

	var seat: MatchParticipant = _controller.get_seat_participant()
	if assert_not_null(seat, "somebody holds the tower"):
		assert_true(
			_label("%Tower").contains(seat.display_name.to_upper()),
			"the card names the tower holder (%s)" % seat.display_name,
		)
		assert_true(
			_label("%Tower").contains("TURN %d" % seat.turns_in_tower),
			"and which of their turns this is, because that is what sets the reload",
		)

	assert_eq_string(
		_label("%Prisoners"), "PRISONERS  %d" % _controller.get_runners_remaining(),
		"and how many prisoners are on the ring",
	)

	var definition: MapDefinition = MapCatalog.by_id(_controller.get_rules().map_id)
	if assert_not_null(definition, "the rules name a map the catalog has"):
		assert_eq_string(
			_label("%MapName"), definition.title.to_upper(),
			"and the map is named from the catalog, not from a scene path",
		)


## The clock takes the card down on its own, and says so once.
func test_the_card_comes_down_when_its_time_runs_out() -> void:
	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return

	_tick_for(_card.get_total_seconds() * 0.5)
	assert_true(_card.is_showing(), "half way through it is still up")

	_tick_for(_card.get_total_seconds() * 0.5 + CARD_DELTA)

	assert_false(_card.is_showing(), "and it takes itself down")
	assert_eq_int(_dismissals, 1, "announcing that exactly once")


# --- Skipping -----------------------------------------------------------------

## Skippable, because Ryan will see this hundreds of times -- but not by the
## input that ended the round.
##
## The lockout is a bug fix rather than a nag: a round ends with a shot or with a
## runner crossing the line, and a player holding fire would otherwise dismiss
## the card with the press that raised it and never see it at all.
func test_the_card_is_skippable_but_not_by_the_press_that_raised_it() -> void:
	_profile.round_card_skip_lockout_seconds = 0.2
	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return

	assert_false(_card.is_skippable(), "it refuses to be skipped on the frame it appears")
	_card.skip()
	assert_true(_card.is_showing(), "so a trigger still held down does not dismiss it")

	_tick_for(_profile.round_card_skip_lockout_seconds + CARD_DELTA)
	if not assert_true(_card.is_skippable(), "a fifth of a second later it will answer"):
		return

	_card.skip()

	assert_false(_card.is_showing(), "and a deliberate press is answered")
	assert_eq_int(_dismissals, 1, "which is the same dismissal the clock would have made")
	assert_false(get_tree().paused, "and the match is running again")


## A lockout of zero is answered immediately, so the number is honest rather than
## a floor written into the file.
func test_a_zero_lockout_is_skippable_at_once() -> void:
	_profile.round_card_skip_lockout_seconds = 0.0
	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return

	assert_true(_card.is_skippable(), "nothing is holding it")
	_card.skip()
	assert_false(_card.is_showing(), "and it goes at once")


# --- Holding the match --------------------------------------------------------

## [b]The fairness of the card.[/b] The round is LIVE behind it -- the seat has
## changed, the bodies are placed, the bots are armed -- so a card the player has
## to read while three prisoners run is a handicap the rules never wrote. The
## tree is paused for its length and released on the way out.
func test_the_card_holds_the_whole_match_and_gives_it_back() -> void:
	_card.hold_match = true

	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return
	assert_true(_card.is_holding_the_match(), "and it is holding the match")
	assert_true(get_tree().paused, "so no bot runs a metre of the new round")

	_tick_for(_card.get_total_seconds() + CARD_DELTA)

	assert_false(_card.is_showing(), "the card is done")
	assert_false(_card.is_holding_the_match(), "and has let go")
	assert_false(get_tree().paused, "and the round resumes for everybody on one tick")


## Turning the hold off is supported and changes nothing else about the card.
func test_the_hold_can_be_switched_off_on_its_own() -> void:
	_card.hold_match = false

	_turn_the_round_over()

	assert_true(_card.is_showing(), "the card still appears")
	assert_false(_card.is_holding_the_match(), "and holds nothing")
	assert_false(get_tree().paused, "so the round runs behind it")


# --- Who yields to whom -------------------------------------------------------

## A won match belongs to [MatchResultScreen]'s win beat. Two announcements over
## each other read as one unreadable one -- the same ruling [MatchHud] makes
## about its handover banner -- and a card left up over a frozen match would also
## leave the tree paused under a dialog nobody can reach.
func test_a_won_match_takes_the_card_down() -> void:
	_card.hold_match = true
	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return

	_controller.match_won.emit(_controller.get_seat_participant())

	assert_false(_card.is_showing(), "the win takes the card")
	assert_false(get_tree().paused, "and unpauses the match on the way")


## A fresh match is a fresh screen. The R key, an all-racers-out restart and Play
## Again all reach this same signal, so all three leave the card in one state.
func test_a_fresh_match_takes_the_card_down() -> void:
	_card.hold_match = true
	_turn_the_round_over()
	if not assert_true(_card.is_showing(), "the card is up"):
		return

	# The real thing rather than the signal: restart() is the same call the R key,
	# an all-racers-out fall and Play Again all make.
	_controller.restart()

	assert_false(_card.is_showing(), "the new match takes it down")
	assert_false(get_tree().paused, "and the tree is running again")


## A match with no human in it runs the identical round-start path and never gets
## past the card's first guard. This is the bot harness, and it must be a no-op
## rather than an error -- and above all it must not pause a headless sweep.
func test_a_match_with_no_human_is_a_no_op() -> void:
	_card.hold_match = true
	# The card asks the controller who the human is, and MatchParticipant.kind is
	# the one field that answers -- see its header: human and AI are the same
	# thing everywhere else. Turn the human into an AI and this match becomes the
	# harness's match, with no other difference at all.
	if _human != null:
		_human.kind = MatchParticipant.Kind.AI
	if not assert_null(
		_controller.get_human_participant(), "this match has nobody at a screen"
	):
		return

	_turn_the_round_over()

	assert_false(_card.is_showing(), "there is nobody to show a card to")
	assert_eq_int(_shows, 0, "and nothing was announced")
	assert_false(get_tree().paused, "and nothing was held")


# --- Helpers ------------------------------------------------------------------

## The card the shipped match scene carries, which is inert in this process.
func _shipped() -> RoundTransitionScreen:
	return _match.get_node_or_null("RoundTransition") as RoundTransitionScreen


## Build a card that is NOT inert, pointed at the same live controller.
##
## The one shipped in the match scene switches itself off with no display server,
## which is right and is asserted separately. The behaviour has to be tested on
## an instance with that turned off -- exactly the arrangement
## [code]test_seat_handover.gd[/code] uses for the same reason.
func _build_card() -> void:
	var packed: PackedScene = load(SCREEN_SCENE_PATH) as PackedScene
	_card = packed.instantiate() as RoundTransitionScreen
	_card.name = "TestRoundTransition"
	_card.headless_inert = false
	# Off by default here, and switched on by the two tests that are about it: a
	# card that paused the tree in every test would pause the fixtures of every
	# test that followed it in the same process.
	_card.hold_match = false
	# There is no display server to render an arena into. The map panel is the
	# one part of this card a headless run cannot judge and does not pretend to.
	_card.show_map = false
	_card.controller = _controller
	# A private copy: the .tres is one instance for the whole process and a test
	# that wrote a duration into it would retune every later test in the run.
	_profile = (load(ANNOUNCEMENT_PATH) as MatchAnnouncementProfile).duplicate() \
		as MatchAnnouncementProfile
	_card.announcements = _profile

	add_child(_card)
	# Stepped by hand at a delta the tests choose, exactly as the handover view
	# is: this node runs on the render tick and the suite drives the physics one.
	_card.set_process(false)
	_card.set_process_input(false)
	_card.transition_shown.connect(_on_shown)
	_card.transition_dismissed.connect(_on_dismissed)


## Turn the round over through the seam the match itself scores on: a finished
## lap by a runner who is not in the tower. Nothing here reaches into
## [MatchController]'s internals.
func _turn_the_round_over() -> void:
	var scorer: MatchParticipant = _first_bot_not_in_the_seat()
	if scorer == null:
		return
	scorer.tracker.lap_finished.emit(30.0, 240.0)


## Advance the card by [param seconds], in the fixed steps the shipped game runs
## it at.
func _tick_for(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(CARD_DELTA, remaining)
		_card.tick(step)
		remaining -= step


func _label(unique_name: String) -> String:
	var label: Label = _card.get_node_or_null(NodePath(unique_name)) as Label
	return "" if label == null else label.text


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


func _on_shown(round_number: int) -> void:
	_shows += 1
	_announced_round = round_number


func _on_dismissed() -> void:
	_dismissals += 1
