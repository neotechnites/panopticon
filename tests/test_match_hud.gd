extends TestCase

## WHAT THE PLAYER IS TOLD, and whether it is true.
##
## [MatchHud] is the only thing in the game that speaks to the player in words,
## and it speaks to two players who are playing different games: a guard holding
## a tower with a bolt-action rifle, and a prisoner running a ring away from it.
## This file asserts three things about it and nothing else:
##
## [codeblock]
## 1. Each role is shown its OWN numbers -- and, as importantly, not the
##    other role's. The live reload countdown is the guard's alone.
## 2. Every sentence follows the rules ACTUALLY IN PLAY. MatchRules is swept,
##    so a readout that assumed the shipped defaults would lie to a player in
##    exactly the matches the harness exists to run.
## 3. A match with no human in it is a match with no readout in it. Every
##    headless bot sweep instances this same scene.
## [/codeblock]
##
## [b]The shipped HUD is the one under test[/b], not a stand-in: it is a
## [Control] and a handful of [Label]s with no display server dependency, so
## unlike [MatchDeathScreen] and [FxSpectatorView] it needs no headless-inert
## flag and none was added. Everything below reads
## [code]HUD/Root[/code] straight out of [code]scenes/match/match.tscn[/code],
## which is what makes these tests also an assertion that the scene is still
## wired: an export whose [NodePath] has gone stale resolves to null at load with
## no error at all, and every text assertion here would come back empty.
##
## [b]Wording is read off the profile, not typed in twice.[/b] The strings live
## in [MatchReadoutProfile] precisely so they can be retuned, and a test that
## hard-coded "CATCH A PRISONER" would turn a wording change into a red suite.
## What is asserted is that the readout says the thing the profile says for the
## situation the match is actually in.

## Ticks to let a freshly armed round settle before it is measured. The bodies
## are placed, held and woken over a couple of physics frames.
const SETTLE_TICKS: int = 60

## The shipped readout tuning. Duplicated by [method _readout] for the same
## reason [TestFixtures] duplicates everything else: it is one instance for the
## whole process and a test that wrote into it would retune every later test.
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
## to somebody.
##
## [param to_the_human] decides which somebody, and it is the whole asymmetry
## this file is about. Either way the seat is granted through the seam the match
## actually scores on -- a finished lap -- rather than by writing flags onto a
## participant, so what is under test is a HUD reading a match the match arrived
## at by itself.
func _arm(to_the_human: bool) -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = _rules
	add_child(_match)

	_hud = _match.get_node("HUD/Root") as MatchHud
	# Read off the controller's own export rather than by path. The rifle is
	# authored at Player/Head/Rifle, but there is ONE of it and the match moves
	# it: MatchController stows it on ITSELF for the opening race -- which the
	# shipped rules open with, so it has already left the head by the time
	# add_child() returns -- and reparents it onto whoever takes the tower.
	# The export is still the wiring assertion the header describes: a stale
	# NodePath there resolves to null and every rifle read below dies on it.
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


## A private copy of the shipped readout tuning, so wording assertions compare
## against the same strings the HUD is reading.
func _readout() -> MatchReadoutProfile:
	return (load(READOUT_PROFILE_PATH) as MatchReadoutProfile).duplicate() as MatchReadoutProfile


# --- The guard ----------------------------------------------------------------

## In the tower you are told the three things a guard acts on: the state of the
## rifle, how many prisoners are left, and how close the match is to ending.
func test_the_tower_is_told_its_rifle_its_count_and_its_progress() -> void:
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_true(_human.is_shooter, "the human holds the tower")
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.GUARD), "the HUD reads the guard's game")
	assert_true(_hud.is_readout_showing(), "the readout is on screen")

	# The role line carries the turn count, because the reload shortens with
	# every turn and the turn number is therefore the tower's difficulty.
	assert_true(
		_hud.get_role_text().contains(words.guard_role),
		"the role line names the tower -- got \"%s\"" % _hud.get_role_text(),
	)
	assert_true(
		_hud.get_role_text().contains("%s %d" % [words.turn_word, _human.turns_in_tower]),
		"the role line carries the turn count -- got \"%s\"" % _hud.get_role_text(),
	)

	# The rifle, which is the single most important number in a guard's life.
	assert_true(_rifle.can_fire(), "the rifle is ready on the first tick of a turn")
	assert_eq_string(_hud.get_primary_text(), words.ready_text, "and the readout says so")

	assert_eq_int(_controller.get_runners_remaining(), 3, "three prisoners are running")
	assert_true(
		_hud.get_objective_text().contains(words.prisoner_count_text(3, 3)),
		"the count of living prisoners is shown -- got \"%s\"" % _hud.get_objective_text(),
	)
	assert_true(
		_hud.get_objective_text().contains(words.total_conversion_objective),
		"and what the tower must do to them -- got \"%s\"" % _hud.get_objective_text(),
	)

	# rounds_to_win_match is 1 on the shipped rules, so there is no score to
	# show and the line says what winning IS instead.
	assert_eq_string(
		_hud.get_context_text(),
		words.final_round_text,
		"the tower is told how close the match is to being over",
	)


## The reload is a COUNTDOWN, not a state word. A guard who cannot see the
## number cannot tell a refused trigger from a broken one.
func test_the_tower_counts_its_reload_down() -> void:
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_true(_rifle.try_fire(), "the rifle answers the trigger")
	await step_ticks(2)
	_hud.tick()

	assert_false(_rifle.can_fire(), "the rifle is now silent")
	var shown: String = _hud.get_primary_text()
	assert_true(
		shown.begins_with(words.reload_word),
		"the readout is counting the reload -- got \"%s\"" % shown,
	)
	var seconds: float = shown.substr(words.reload_word.length()).strip_edges().to_float()
	assert_gt(seconds, 0.0, "and the number is a real time to the next shot")
	assert_almost_eq(
		seconds, _rifle.get_time_to_ready(), 0.1,
		"which is the rifle's own time to ready, rounded",
	)


# --- The prisoner -------------------------------------------------------------

## On the ring you are told how far you still have to go, how many of you are
## left, and who is in the tower -- and you are NOT told when they can shoot.
func test_a_prisoner_is_told_the_distance_the_count_and_the_tower() -> void:
	await _arm(false)
	var words: MatchReadoutProfile = _readout()

	assert_true(_human.is_running, "the human is a prisoner")
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.PRISONER), "the HUD reads the prisoner's game")
	assert_eq_string(_hud.get_role_text(), words.prisoner_role, "and says so in one word")

	# Distance: the whole ROUTE left, not the lap. The arena is three decks of
	# three different sizes, so the number a prisoner needs is every level still
	# owed, each taken at its own lane radius. Recomputed here from the route
	# rather than read back off the tracker, so the HUD is being checked against
	# arithmetic this file owns.
	var shown: String = _hud.get_primary_text()
	assert_true(
		shown.ends_with(words.distance_suffix),
		"the prisoner is shown metres to the end -- got \"%s\"" % shown,
	)
	var route: RingRoute = _controller.get_route()
	if not assert_not_null(route, "the arena should carry a route"):
		return
	var expected: float = 0.0
	for level: int in route.level_count():
		expected += route.lap_arc(level) * route.lane_radius(level)
	expected -= _human.tracker.get_travelled_arc() * route.lane_radius(
		_human.tracker.get_level()
	)
	assert_almost_eq(
		shown.split(" ")[0].to_float(), expected, 1.0,
		"and the metres are the route the tracker is actually scoring",
	)
	assert_gt(expected, 100.0, "which on this arena is most of three laps")

	assert_true(
		_hud.get_objective_text().contains(words.prisoner_count_text(3, 3)),
		"how many prisoners are still alive -- got \"%s\"" % _hud.get_objective_text(),
	)
	assert_true(
		_hud.get_objective_text().contains(words.first_arrival_objective),
		"and what reaching the end is worth -- got \"%s\"" % _hud.get_objective_text(),
	)

	# The tower, as a property of the tower: who, on which turn, and how long
	# their silence between shots lasts.
	var seat: MatchParticipant = _controller.get_seat_participant()
	assert_not_null(seat, "a bot holds the tower")
	var context: String = _hud.get_context_text()
	assert_true(context.contains(seat.display_name), "the prisoner is told who is up there -- got \"%s\"" % context)
	assert_true(
		context.contains("%s %d" % [words.turn_word, seat.turns_in_tower]),
		"and on which turn -- got \"%s\"" % context,
	)
	assert_true(
		context.contains(words.reload_length_suffix),
		"and how long that turn's reload is -- got \"%s\"" % context,
	)


## The live countdown is the guard's alone. A prisoner who could watch it would
## run by reading the HUD rather than by watching the tower.
func test_a_prisoner_is_not_given_the_live_reload_countdown() -> void:
	await _arm(false)
	var words: MatchReadoutProfile = _readout()

	assert_true(_rifle.try_fire(), "the tower fires")
	await step_ticks(2)
	_hud.tick()

	assert_false(_rifle.can_fire(), "the rifle is silent")
	var lines: PackedStringArray = PackedStringArray([
		_hud.get_primary_text(), _hud.get_objective_text(), _hud.get_context_text(),
	])
	for line: String in lines:
		assert_false(
			line.begins_with(words.reload_word) or line.contains(words.ready_text),
			"no line of a prisoner's readout counts the tower's reload -- got \"%s\"" % line,
		)


# --- The ghost ----------------------------------------------------------------

## Being shot changes your JOB, and the readout changes with it on the same
## tick: the lap you were running has stopped being scored, so the metres stop
## and the orders start.
func test_a_ghost_is_told_its_job_has_changed() -> void:
	await _arm(false)
	var words: MatchReadoutProfile = _readout()

	assert_true(_controller.apply_hit(_human), "the rifle converts the human")
	_hud.tick()

	assert_true(_human.is_ghost, "the human is a ghost")
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.GHOST), "the HUD reads the ghost's game")
	assert_eq_string(_hud.get_role_text(), words.ghost_role, "and names the role")
	assert_eq_string(
		_hud.get_primary_text(), words.ghost_orders,
		"the distance readout is replaced by the chase -- a ghost has no lap left to run",
	)

	var profile: GhostProfile = _controller.get_ghost_profile()
	var objective: String = _hud.get_objective_text()
	assert_true(
		objective.contains(words.ghost_take_place_text),
		"the ghost is told what catching somebody is FOR -- got \"%s\"" % objective,
	)
	assert_true(
		objective.contains("%.1f%s" % [profile.speed_multiplier, words.ghost_speed_suffix]),
		"and how much faster it now is, off the live GhostProfile -- got \"%s\"" % objective,
	)
	assert_false(profile.shootable, "the shipped ghost cannot be shot")
	assert_true(
		objective.contains(words.ghost_unshootable_text),
		"and is told so -- got \"%s\"" % objective,
	)

	# Only the rifle lowers the living count, and it just did.
	assert_eq_int(_controller.get_runners_remaining(), 2, "two prisoners are left running")
	assert_true(
		objective.contains(words.prisoner_count_text(2, 3)),
		"which is what the ghost is shown -- got \"%s\"" % objective,
	)


# --- The rules actually in play -----------------------------------------------

## Swept rules, honestly reported: a round played under ALL_ARRIVALS does not
## get told that first past the post takes the tower.
func test_the_runners_objective_follows_the_win_condition_in_play() -> void:
	_rules.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	await _arm(false)
	var words: MatchReadoutProfile = _readout()

	assert_true(
		_hud.get_objective_text().contains(words.all_arrivals_objective),
		"the readout states the win condition in play -- got \"%s\"" % _hud.get_objective_text(),
	)
	assert_false(
		_hud.get_objective_text().contains(words.first_arrival_objective),
		"and not the shipped default it is not playing",
	)


## A match that takes more than one round shows the score. The shipped rule --
## one round -- shows what winning is instead, because "0 / 1" is noise.
func test_match_progress_follows_rounds_to_win_match() -> void:
	_rules.rounds_to_win_match = 3
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_eq_string(
		_hud.get_context_text(),
		words.match_progress(_rules, 0),
		"the tower is shown its round wins against the number the rules demand",
	)
	assert_true(
		_hud.get_context_text().contains("0 / 3"),
		"which is a score, not the one-round sentence -- got \"%s\"" % _hud.get_context_text(),
	)
	assert_false(
		_hud.get_context_text().contains(words.final_round_text),
		"and not the shipped one-round wording",
	)


## A win condition that IS implemented but has been handed a number it cannot be
## won with produces a round the tower cannot win. The readout says that, rather
## than describing the condition that would work and leaving the player to wonder
## why the round never ends.
##
## SHUTOUT_COUNT on the shipped rules is exactly that case: the condition is
## built, and [member MatchRules.shutout_count] ships at 0 = unset because
## [MatchRules] refuses to guess a design number.
func test_an_unwinnable_tower_is_told_so() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 0
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_true(
		_rules.is_shooter_win_condition_implemented(), "the condition itself is implemented"
	)
	assert_gt(
		float(_rules.validate().size()), 0.0, "and the rule set still reports itself unwinnable"
	)
	assert_true(
		_hud.get_objective_text().contains(words.unwinnable_objective),
		"and the readout says so -- got \"%s\"" % _hud.get_objective_text(),
	)
	assert_false(
		_hud.get_objective_text().contains(words.total_conversion_objective),
		"rather than describing a rule this round is not playing",
	)


## A round played under a set shutout is told what the shutout IS, not that it
## cannot be won. The count is the rule, so the count is in the sentence.
func test_the_towers_objective_follows_a_set_shutout() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 2
	await _arm(true)
	var words: MatchReadoutProfile = _readout()

	assert_true(
		_hud.get_objective_text().contains(words.shutout_objective % 2),
		"the readout states the count in play -- got \"%s\"" % _hud.get_objective_text(),
	)
	assert_false(
		_hud.get_objective_text().contains(words.unwinnable_objective),
		"and does not call a winnable round unwinnable",
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
		"the human is reading the prisoner's readout, not the tower's",
	)
	assert_false(
		_hud.get_primary_text().contains(_readout().ready_text),
		"and is not being shown the rifle's state",
	)


## Every headless bot sweep instances this same scene. With no human in the
## match there is nobody to read a readout, and it is a no-op rather than an
## error: hidden, silent, and stepping the same path the shipped HUD steps.
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
	assert_false(_hud.is_readout_showing(), "the readout stays down")
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
