extends TestCase

## WHAT THE PLAYER IS TOLD, and whether it is true.
##
## The HUD is edges only. This file asserts three things about it:
##
## [codeblock]
## 1. Each role is shown its OWN readout -- the tower rifle bottom-left for a
##    prisoner, your own under the dot in the tower, ten pips for a finisher --
##    and a dead player is shown nothing at all, because the death screen has
##    them.
## 2. Every sentence follows the rules ACTUALLY IN PLAY. MatchRules is swept.
## 3. A match with no human in it is a match with no HUD in it. Every headless
##    bot sweep instances this same scene.
## [/codeblock]
##
## The shipped HUD is the one under test: everything below reads
## [code]HUD/Root[/code] straight out of [code]scenes/match/match.tscn[/code],
## which makes these tests an assertion that the scene is still wired -- an
## export whose [NodePath] has gone stale resolves to null at load with no error
## at all, and every text assertion here would come back empty.

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## The shipped readout tuning. Duplicated by [method _readout] because it is one
## instance for the whole process and a test that wrote into it would retune
## every later test.
const READOUT_PROFILE_PATH: String = "res://resources/rules/default_match_readout.tres"

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _hud: MatchHud
var _rifle: Rifle
var _human: MatchParticipant


func before_each() -> void:
	_rules = TestFixtures.match_rules()


# --- Arming -------------------------------------------------------------------

## Instance the shipped match, run it under [member _rules], and give the tower
## to somebody -- through the seam the match actually scores on, a finished lap,
## rather than by writing flags onto a participant.
func _arm(to_the_human: bool) -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = _rules
	add_child(_match)

	_hud = _match.get_node("HUD/Root") as MatchHud
	# Read off the controller's own export rather than by path: there is ONE
	# rifle and the match moves it.
	_rifle = _controller.rifle
	_human = _controller.get_human_participant()

	var opener: MatchParticipant = _human
	if not to_the_human:
		for participant: MatchParticipant in _controller.get_participants():
			if not participant.is_human():
				opener = participant
				break
	if opener != null:
		opener.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	_hud.tick()


func _readout() -> MatchReadoutProfile:
	return (load(READOUT_PROFILE_PATH) as MatchReadoutProfile).duplicate() as MatchReadoutProfile


# --- The guard ----------------------------------------------------------------

## In the tower you are shown the round, the prisoners left, your turn, and the
## one thing you act on: the rifle.
func test_the_tower_is_told_its_round_its_count_its_turn_and_its_rifle() -> void:
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_true(_human.is_shooter, "the human holds the tower")
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.GUARD), "the HUD reads the guard's game")
	assert_true(_hud.is_readout_showing(), "the HUD is up")

	var status: String = _hud.get_status_text()
	assert_true(
		status.contains("ROUND %d" % _controller.get_round_number()),
		"the top line names the round -- got \"%s\"" % status,
	)
	assert_true(
		status.contains("%s %d" % [words.prisoners_word, _controller.get_runners_remaining()]),
		"and how many prisoners are left -- got \"%s\"" % status,
	)
	assert_true(
		status.contains("%s %d" % [words.turn_word, _human.turns_in_tower]),
		"and which turn in the tower this is -- got \"%s\"" % status,
	)
	assert_eq_int(_controller.get_runners_remaining(), 3, "three prisoners are running")

	# The rifle, which is the single most important number in a guard's life,
	# and it is under the crosshair rather than in a corner.
	assert_true(_rifle.can_fire(), "the rifle is ready on the first tick of a turn")
	assert_eq_string(_hud.get_primary_text(), words.ready_text, "and the readout says so")

	# Nothing bottom-right in the tower.
	assert_eq_string(_hud.get_context_text(), "", "the tower carries no runner power")


## The reload is a COUNTDOWN and a bar, not a state word. A guard who cannot see
## the number cannot tell a refused trigger from a broken one.
func test_the_tower_counts_its_reload_down() -> void:
	await _arm(true)

	assert_true(_rifle.try_fire(), "the rifle answers the trigger")
	await step_ticks(2)
	_hud.tick()

	assert_false(_rifle.can_fire(), "the rifle is now silent")
	var shown: String = _hud.get_primary_text()
	assert_gt(shown.to_float(), 0.0, "the readout is counting -- got \"%s\"" % shown)
	assert_almost_eq(
		shown.to_float(), _rifle.get_time_to_ready(), 0.1,
		"which is the rifle's own time to ready, rounded",
	)


# --- The prisoner -------------------------------------------------------------

## On the ring you are shown the round, how many of you are left, who is in the
## tower -- and, bottom-left, that tower's reload.
func test_a_prisoner_is_told_the_count_the_tower_and_its_reload() -> void:
	await _arm(false)
	var words: MatchReadoutProfile = _readout()

	assert_true(_human.is_running, "the human is a prisoner")
	assert_eq_int(
		int(_hud.get_role()), int(MatchHud.Role.PRISONER), "the HUD reads the prisoner's game"
	)
	assert_true(_hud.is_readout_showing(), "the HUD is up")

	var seat: MatchParticipant = _controller.get_seat_participant()
	if not assert_not_null(seat, "a bot holds the tower"):
		return
	var status: String = _hud.get_status_text()
	assert_true(
		status.contains("%s %d/%d" % [
			words.prisoners_word,
			_controller.get_runners_remaining(),
			_controller.get_runners_total(),
		]),
		"the top line counts the living prisoners -- got \"%s\"" % status,
	)
	assert_true(
		status.contains(seat.display_name),
		"and names who is holding the tower -- got \"%s\"" % status,
	)

	# The reload the prisoner is running from, as the tower's own state.
	assert_true(_rifle.can_fire(), "the tower is loaded")
	assert_eq_string(_hud.get_primary_text(), words.ready_text, "and the prisoner is told so")


## Ryan's ruling: the runner gets the tower rifle's reload as a bar filling, so
## the silence after a shot is something a prisoner can run against.
func test_a_prisoner_watches_the_tower_reload() -> void:
	await _arm(false)

	assert_true(_rifle.try_fire(), "the tower fires")
	await step_ticks(2)
	_hud.tick()

	assert_false(_rifle.can_fire(), "the rifle is silent")
	var shown: String = _hud.get_primary_text()
	assert_gt(shown.to_float(), 0.0, "the prisoner is shown the silence left -- got \"%s\"" % shown)
	assert_almost_eq(
		shown.to_float(), _rifle.get_time_to_ready(), 0.1,
		"which is the tower's own time to ready",
	)


# --- The ghost ----------------------------------------------------------------

## Being shot takes the HUD away. [MatchDeathScreen] owns the dead player's
## screen, and two readouts over one death is one too many.
func test_a_ghost_is_shown_no_hud_at_all() -> void:
	await _arm(false)

	assert_true(_controller.apply_hit(_human), "the rifle converts the human")
	_hud.tick()

	assert_true(_human.is_ghost, "the human is a ghost")
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.GHOST), "the HUD reads the ghost")
	assert_false(_hud.is_readout_showing(), "and draws nothing")
	assert_eq_string(_hud.get_status_text(), "", "no top line")
	assert_eq_int(
		int(_human.death_cause), int(MatchParticipant.DeathCause.SHOT),
		"the death screen is told what took them",
	)


## A hazard is a different death, and the controller says which. The death
## screen reads this and nothing else.
func test_a_hazard_death_is_named_apart_from_a_shot() -> void:
	await _arm(false)

	assert_true(_controller.handle_fall(_human, true), "the pit takes the human")
	assert_eq_int(
		int(_human.death_cause), int(MatchParticipant.DeathCause.FELL), "a pit is a fall"
	)


# --- The finisher -------------------------------------------------------------

## An armed prisoner is shown the guard's readout plus their hit points, because
## they are now a body the guard is shooting ten times.
func test_a_finisher_is_shown_health_pips() -> void:
	_rules.finisher_hunts_guard = true
	await _arm(false)

	_human.tracker.lap_finished.emit(12.0, 96.0)
	await step_ticks(2)
	_hud.tick()

	if not assert_true(_human.is_finisher, "the human is armed"):
		return
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.FINISHER), "the HUD reads the finisher")
	assert_true(_hud.is_readout_showing(), "the HUD is up")
	assert_eq_int(_human.health, _rules.finisher_health, "on full health")
	assert_true(
		_hud.get_status_text().contains(_readout().turn_word),
		"and on the guard's own top line -- got \"%s\"" % _hud.get_status_text(),
	)
	assert_not_null(_controller.get_finisher_rifle(), "with a rifle of their own to read")


# --- The centre line ----------------------------------------------------------

## One transient line, never stacked: the last thing that happened, from this
## player's side of it.
func test_the_centre_line_names_the_event_from_the_players_side() -> void:
	await _arm(true)

	var seat: MatchParticipant = _controller.get_seat_participant()
	_controller.seat_changed.emit(seat, seat.turns_in_tower)
	assert_true(
		_hud.get_flash_text().contains("TOWER TAKEN BY"),
		"a seat change is announced -- got \"%s\"" % _hud.get_flash_text(),
	)

	# The human holds the tower, so the tower holding it is this player's win.
	_controller.round_resolved.emit(MatchController.Outcome.WIN)
	assert_eq_string(_hud.get_flash_text(), "ROUND WON", "the guard won the round")
	_controller.round_resolved.emit(MatchController.Outcome.LOSS)
	assert_eq_string(
		_hud.get_flash_text(), "ROUND LOST", "and a prisoner reaching the end is a loss"
	)


## Dev toggles are dressed as dev toggles: top-right, and only while one is on.
func test_the_dev_toggles_are_shown_only_when_they_are_on() -> void:
	await _arm(true)
	assert_eq_string(_hud.get_dev_text(), "", "nothing is on by default")

	_human.body.get_intent().godmode = true
	_hud.tick()
	assert_true(
		_hud.get_dev_text().contains("INVINCIBLE"),
		"the toggle is named -- got \"%s\"" % _hud.get_dev_text(),
	)


# --- The rules actually in play -----------------------------------------------

## Swept rules, honestly worded: a round played under ALL_ARRIVALS does not get
## told that first past the post takes the tower.
func test_the_runners_objective_follows_the_win_condition_in_play() -> void:
	_rules.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	await _arm(false)
	var words: MatchReadoutProfile = _readout()

	assert_eq_string(
		words.runner_objective(_controller.get_rules()),
		words.all_arrivals_objective,
		"the rules in play are the swept ones",
	)


## A match that takes more than one round has a score. The shipped rule -- one
## round -- has a sentence instead, because "0 / 1" is noise.
func test_match_progress_follows_rounds_to_win_match() -> void:
	_rules.rounds_to_win_match = 3
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_eq_string(
		words.match_progress(_controller.get_rules(), _human.rounds_won),
		"%s 0 / 3" % words.round_wins_word,
		"a three-round match is a score",
	)


## A win condition that IS implemented but has been handed a number it cannot be
## won with produces a round the tower cannot win, and is said to be.
func test_an_unwinnable_tower_is_told_so() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 0
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_true(
		_controller.get_rules().is_shooter_win_condition_implemented(),
		"the condition itself is implemented",
	)
	assert_gt(
		float(_controller.get_rules().validate().size()),
		0.0,
		"and the rule set still reports itself unwinnable",
	)
	assert_eq_string(
		words.shooter_objective(_controller.get_rules()),
		words.unwinnable_objective,
		"which is what it is called",
	)


## A round played under a set shutout is told what the shutout IS.
func test_the_towers_objective_follows_a_set_shutout() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 2
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_eq_string(
		words.shooter_objective(_controller.get_rules()),
		words.shutout_objective % 2,
		"the count in play is the count in the sentence",
	)


## The wording is a pure function of the rules, and is asserted as one: no
## scene, no controller, no viewport. This is the seam a sweep varies.
func test_the_wording_is_a_pure_function_of_the_rules() -> void:
	var words: MatchReadoutProfile = _readout()
	var rules: MatchRules = TestFixtures.match_rules()

	rules.runner_win_condition = MatchRules.RunnerWinCondition.FIRST_ARRIVAL
	assert_eq_string(words.runner_objective(rules), words.first_arrival_objective, "first arrival")
	rules.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	assert_eq_string(words.runner_objective(rules), words.all_arrivals_objective, "all arrivals")

	rules.shooter_win_condition = MatchRules.ShooterWinCondition.TOTAL_CONVERSION
	assert_eq_string(words.shooter_objective(rules), words.total_conversion_objective, "total conversion")
	rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	rules.shutout_count = 2
	assert_eq_string(words.shooter_objective(rules), words.shutout_objective % 2, "a set shutout")
	rules.shutout_count = 0
	assert_eq_string(
		words.shooter_objective(rules), words.unwinnable_objective, "an unset shutout"
	)

	rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	rules.hold_duration_seconds = 45.0
	assert_eq_string(
		words.shooter_objective(rules), words.hold_duration_objective % 45, "a set hold"
	)
	rules.hold_duration_seconds = 0.0
	assert_eq_string(words.shooter_objective(rules), words.unwinnable_objective, "an unset hold")

	rules.shooter_win_condition = MatchRules.ShooterWinCondition.TOTAL_CONVERSION

	rules.rounds_to_win_match = 1
	assert_eq_string(words.match_progress(rules, 0), words.final_round_text, "one round to win")
	rules.rounds_to_win_match = 4
	assert_eq_string(words.match_progress(rules, 2), "%s 2 / 4" % words.round_wins_word, "four rounds to win")

	assert_eq_string(words.prisoner_count_text(1, 3), "%s 1 / 3" % words.prisoners_word, "the shared count")


# --- A bot pays nothing -------------------------------------------------------

## A bot holding the tower is a seat the human does not have. It must not
## produce a guard readout for a body the player is not in.
func test_a_bot_in_the_tower_does_not_hand_the_human_a_guard_readout() -> void:
	await _arm(false)

	var seat: MatchParticipant = _controller.get_seat_participant()
	assert_not_null(seat, "somebody holds the tower")
	assert_false(seat.is_human(), "and it is a bot")
	assert_eq_int(
		int(_hud.get_role()), int(MatchHud.Role.PRISONER),
		"the human is reading the prisoner's HUD, not the tower's",
	)
	assert_false(
		_hud.get_status_text().contains(_readout().turn_word),
		"and is not being shown the tower's own turn line",
	)


## Every headless bot sweep instances this same scene. With no human in the
## match there is nobody to read a HUD, and it is a no-op rather than an error.
func test_a_match_with_no_human_shows_no_readout() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = _rules
	# The one seam that makes a match bot-only: MatchController builds a human
	# participant if and only if it has a body to give one.
	_controller.player = null
	add_child(_match)
	_hud = _match.get_node("HUD/Root") as MatchHud
	await step_ticks(SETTLE_TICKS)

	assert_null(_controller.get_human_participant(), "the match has no human in it")
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.NONE), "so the HUD has no role to draw")

	_hud.tick()
	assert_false(_hud.is_readout_showing(), "nothing is on screen")
	assert_true(
		_controller.get_participants().size() >= 2,
		"and the match itself is unaffected -- the bots still hold and run",
	)


## Switching the readout off is the honest control for whether it was an
## improvement: the match is played exactly as it was, without it.
func test_the_readout_can_be_switched_off_entirely() -> void:
	await _arm(true)
	var off: MatchReadoutProfile = _readout()
	off.enabled = false
	_hud.readout = off
	_hud.tick()

	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.NONE), "there is no readout to draw")
	assert_false(_hud.is_readout_showing(), "and nothing is on screen")
	assert_true(_human.is_shooter, "while the match goes on exactly as it was")
