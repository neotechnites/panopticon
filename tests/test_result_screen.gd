extends TestCase

## [MatchResultScreen]: what a finished match tells the player, and what Play
## Again actually resets.
##
## Two things are being defended here and they fail in opposite directions.
##
## 1. [b]The screen must name the real winner and the real role.[/b] It keeps no
##    score of its own -- every line is read back off [MatchController] when the
##    screen is shown -- so the failure mode is not a wrong sum, it is a screen
##    that reads the wrong field and cheerfully congratulates a player who lost.
##    Both endings are driven here: the human clears the ring from the tower, and
##    a bot clears the ring with the human out on it.
## 2. [b]Play Again must produce a genuinely fresh match, not a half-reset
##    one.[/b] The button calls [method MatchController.restart] rather than
##    reloading the scene, which means every participant, body, tracker and brain
##    survives the restart and each one is a separate chance to carry something
##    across: a turn count, a rounds-won tally, a ghost, a parked body under the
##    pit, a rifle still in the winner's hands, a frozen physics process. So the
##    fresh match is asserted field by field rather than by trusting that
##    [code]restart()[/code] does what its name says.
##
## Everything runs against the real [code]scenes/match/match.tscn[/code] on the
## shipped rules, and the match is won the way the match itself wins one: through
## [method MatchController.convert_participant], with the race decided through
## [signal MatchLapTracker.lap_finished]. No phase is forged and nothing private
## is written -- see the note in [code]test_match.gd[/code] on why no test here
## runs an actual 35 second lap.

## Ticks to let the restart's placement settle before bodies are measured.
## [constant MatchController.SETTLE_PHYSICS_FRAMES] is 2; this is comfortably
## past it.
const SETTLE_TICKS: int = 30

## Depth below which a body is unambiguously parked out of the world rather than
## standing somewhere low. [constant MatchController.PEN_DEPTH_METRES] is -100.
const PARKED_DEPTH_METRES: float = -50.0

var _match: Node3D
var _controller: MatchController
var _screen: MatchResultScreen
var _rifle: Rifle
var _trigger: WeaponInput
var _participants: Array[MatchParticipant] = []
var _human: MatchParticipant

var _shows: int = 0
var _hides: int = 0


func before_each() -> void:
	_match = TestFixtures.make_match()
	add_child(_match)

	_controller = _match.get_node("MatchController") as MatchController
	_screen = _match.get_node("ResultScreen") as MatchResultScreen
	_rifle = _controller.rifle
	_trigger = _rifle.get_node_or_null(^"HumanTrigger") as WeaponInput
	_participants = _controller.get_participants()
	_human = _participants[0]

	if _screen != null:
		_screen.result_shown.connect(_on_shown)
		_screen.result_dismissed.connect(_on_hidden)


# --- Wiring -------------------------------------------------------------------

## The shipped match scene actually carries the screen, wired to both nodes.
##
## A [NodePath] export that is not named in the scene's
## [code]node_paths[/code] header resolves to null at load with no error at all,
## which is how [code]PauseMenu.camera[/code] was silently broken on this project
## once already. A result screen with a null controller is exactly that failure:
## the match ends, nothing is connected, and the player sees nothing.
func test_the_match_scene_carries_a_wired_result_screen() -> void:
	assert_not_null(_screen, "scenes/match/match.tscn has a ResultScreen")
	if _screen == null:
		return
	assert_same(_screen.controller, _controller, "the screen watches this match's controller")
	assert_not_null(_screen.pause_menu, "the screen can hand the main-menu teardown to PauseMenu")
	assert_false(_screen.main_menu_scene_path.is_empty(), "and it has a fallback path if it cannot")
	assert_false(_screen.is_showing(), "a live match shows no result")
	assert_eq_int(_shows, 0, "nothing has been announced yet")


## Nothing appears while the match is still being played -- not during the race,
## and not when a round resolves and the seat merely changes hands.
##
## Reaching the end wins the TOWER, never the match. A screen that came up on
## [signal MatchController.round_resolved] would stop the game dead on the first
## seat change.
func test_the_screen_stays_down_until_the_match_is_over() -> void:
	assert_false(_screen.is_showing(), "the opening race shows no result")

	_win_the_race_for(_participants[1])
	assert_false(_screen.is_showing(), "taking the tower is not winning the match")

	# A round resolved as a LOSS: somebody arrived, the seat changed, the round
	# started again. Still not a match.
	_win_the_race_for(_human)
	assert_eq_string(_controller.get_outcome_name(), "IN_PROGRESS", "the next round is live")
	assert_false(_screen.is_showing(), "a seat change is not a result")
	assert_eq_int(_shows, 0, "nothing has been announced")


# --- What it says -------------------------------------------------------------

## The human holds the tower and clears the ring: a win, named as one.
func test_a_win_from_the_tower_names_the_player_and_the_role() -> void:
	_win_the_match_for(_human)

	assert_true(_controller.is_match_over(), "the match is over")
	assert_same(_controller.get_match_winner(), _human, "the human won it")
	assert_true(_screen.is_showing(), "the player is told")
	assert_eq_int(_shows, 1, "and told exactly once")

	assert_eq_string(_verdict(), "VICTORY", "a win reads as a win")
	var headline: String = _headline()
	assert_true(
		headline.contains("held the tower"), "the win is named as a tower win -- got \"%s\"" % headline
	)
	assert_true(
		headline.contains("cleared the ring"), "and as clearing the ring -- got \"%s\"" % headline
	)
	assert_true(headline.begins_with("You "), "in the second person -- got \"%s\"" % headline)

	# The numbers are the controller's, not a tally of the screen's own.
	var detail: String = _detail()
	assert_true(
		detail.contains(_human.display_name), "the detail names the tower holder -- got \"%s\"" % detail
	)
	assert_true(
		detail.contains("Rounds played: %d" % _controller.get_round_number()),
		"and reports the controller's round count -- got \"%s\"" % detail,
	)
	assert_true(
		detail.contains("of %d" % _controller.get_runners_total()),
		"and the field it was cleared out of -- got \"%s\"" % detail,
	)


## A bot holds the tower and clears the ring with the human out on it: a loss,
## named as one, and the player is told what THEY were.
##
## The role line is read off the human's own state rather than assumed from the
## fact that somebody else won, which is what makes it survive the ghost rules:
## under the shipped [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP] a
## converted prisoner is a ghost, and under
## [constant MatchRules.GhostBehaviour.NONE] they are parked. Either way they
## were a prisoner and either way they did not hold the tower.
func test_a_loss_names_the_winner_and_what_the_player_was() -> void:
	var bot: MatchParticipant = _participants[2]
	assert_false(bot.is_human(), "participant 2 is an AI")
	_win_the_match_for(bot)

	assert_same(_controller.get_match_winner(), bot, "the AI won it")
	assert_true(_screen.is_showing(), "the player is told they lost")
	assert_eq_string(_verdict(), "DEFEAT", "a loss reads as a loss")

	var headline: String = _headline()
	assert_true(
		headline.contains(bot.display_name), "the winner is named -- got \"%s\"" % headline
	)
	assert_true(
		headline.contains("held the tower"), "in the role they won it in -- got \"%s\"" % headline
	)
	assert_true(
		headline.contains("prisoner"), "and the player is told they were a prisoner -- got \"%s\"" % headline
	)
	assert_false(
		headline.contains("You held the tower"),
		"a player who lost is never told they held the tower -- got \"%s\"" % headline,
	)
	assert_false(_human.is_shooter, "and they really did not hold it")
	assert_false(_human.is_running, "total conversion leaves no prisoner running")


# --- Play again ---------------------------------------------------------------

## Play Again produces a genuinely fresh match, asserted field by field.
##
## [method MatchController.restart] keeps every participant, body, brain and
## tracker, so this is the test that says the reset is a reset: no turn count, no
## rounds-won tally, no ghost, no parked body, no rifle left in the winner's
## hands, no frozen physics, and no result screen left over the top of a live
## match.
func test_play_again_produces_a_genuinely_fresh_match() -> void:
	var bot: MatchParticipant = _participants[1]
	_win_the_match_for(bot)
	assert_true(_screen.is_showing(), "the result is up")
	assert_gt(float(bot.turns_in_tower), 0.0, "the winner has a turn count to lose")
	assert_gt(float(_controller.get_resolve_count()), 0.0, "and the match has resolutions to lose")

	_screen.play_again()

	# The screen is down, and it came down because a match began.
	assert_false(_screen.is_showing(), "the result screen is gone")
	assert_eq_int(_hides, 1, "and reported itself gone once")

	# The match itself is at the beginning, not at the end.
	assert_false(_controller.is_match_over(), "the new match is not over")
	assert_false(_controller.is_resolved(), "the new match is live")
	assert_null(_controller.get_match_winner(), "the new match has no winner")
	assert_eq_string(_controller.get_outcome_name(), "IN_PROGRESS", "and no outcome")
	assert_eq_string(_controller.get_phase_name(), "RACE", "it opens with the race again")
	assert_eq_int(_controller.get_round_number(), 0, "the race is not a round")
	assert_eq_int(_controller.get_resolve_count(), 0, "nothing has resolved yet")
	assert_eq_int(_controller.get_runners_removed(), 0, "nobody has been removed")
	assert_eq_int(_controller.get_catch_count(), 0, "no ghost has caught anybody")
	assert_null(_controller.get_seat_participant(), "nobody holds the tower during the race")
	assert_eq_int(_controller.get_seat_turns(), 0, "no turn has been taken")

	# The roster survives the restart; its history does not.
	var after: Array[MatchParticipant] = _controller.get_participants()
	assert_eq_int(after.size(), _participants.size(), "the same field plays the next match")
	for participant: MatchParticipant in after:
		assert_eq_int(participant.turns_in_tower, 0, "%s starts on no turns" % participant.display_name)
		assert_eq_int(participant.rounds_won, 0, "%s has won no rounds" % participant.display_name)
		assert_false(participant.is_shooter, "%s is not a shooter" % participant.display_name)
		assert_false(participant.is_ghost, "%s is not a ghost" % participant.display_name)
		assert_true(participant.is_running, "%s is racing" % participant.display_name)
		assert_true(participant.body.visible, "%s's body is back in the world" % participant.display_name)
		assert_gt(
			participant.body.global_position.y, PARKED_DEPTH_METRES,
			"%s is not still parked under the pit" % participant.display_name,
		)
		assert_true(
			participant.body.is_in_group(MatchController.RUNNER_GROUP),
			"%s is a legitimate target again" % participant.display_name,
		)
		assert_true(participant.tracker.is_counting(), "%s is being scored again" % participant.display_name)
		assert_false(participant.tracker.has_finished(), "%s has not finished" % participant.display_name)

	# And the world is armed for a race rather than left dressed for the end of
	# the last match: no shooter, which has to be true of the rifle too.
	assert_same(_rifle.get_parent(), _controller, "the rifle is out of the winner's hands")
	assert_null(_rifle.shooter_body, "the stowed rifle belongs to nobody")
	assert_false(_trigger.is_processing(), "the human's trigger is dead while the tower is empty")

	# The freeze a won match applies is genuinely lifted, once the placement has
	# settled. Asserted on the bodies rather than on the counters, because
	# _freeze_everyone() switched their physics process off one by one.
	await step_ticks(SETTLE_TICKS)
	for participant: MatchParticipant in after:
		assert_true(
			participant.body.is_physics_processing(),
			"%s is moving again" % participant.display_name,
		)


## The R key restarts the match too, and it must take the screen down with it.
##
## [method MatchController.start_match] is the one thing that dismisses the
## result, so every route into a fresh match -- the button, the key, an
## all-racers-out fall -- leaves the screen in the same state. A screen dismissed
## only by its own button would strand itself over a live match on the other two.
func test_a_restart_from_anywhere_else_also_dismisses_the_screen() -> void:
	_win_the_match_for(_human)
	assert_true(_screen.is_showing(), "the result is up")

	# Not the button: the controller's own restart, as the R key and a fall both
	# call it.
	_controller.restart()

	assert_false(_screen.is_showing(), "a fresh match takes the result down")
	assert_false(_controller.is_match_over(), "and the match is live again")


# --- Helpers ------------------------------------------------------------------

## Hand the tower to [param participant] through the tracker seam, exactly as
## [code]test_match.gd[/code] does. Nothing private is written and no phase is
## forged.
func _win_the_race_for(participant: MatchParticipant) -> void:
	participant.tracker.lap_finished.emit(30.0, 240.0)


## Give [param participant] the tower and let them clear the ring, which is the
## only way a match is won under the shipped rules.
func _win_the_match_for(participant: MatchParticipant) -> void:
	_win_the_race_for(participant)
	for other: MatchParticipant in _controller.get_live_participants():
		_controller.convert_participant(other)


func _verdict() -> String:
	return (_screen.get_node("%Verdict") as Label).text


func _headline() -> String:
	return (_screen.get_node("%Headline") as Label).text


func _detail() -> String:
	return (_screen.get_node("%Detail") as Label).text


func _on_shown(_winner: MatchParticipant) -> void:
	_shows += 1


func _on_hidden() -> void:
	_hides += 1
