extends TestCase

## [MatchController]: the three ways the tower wins, and the ways it must not.
##
## [constant MatchRules.ShooterWinCondition.TOTAL_CONVERSION] is covered where it
## has always been covered, in [code]tests/test_round.gd[/code]. This file is
## about the two conditions that were declared and left unbuilt --
## [constant MatchRules.ShooterWinCondition.SHUTOUT_COUNT] and
## [constant MatchRules.ShooterWinCondition.HOLD_DURATION] -- plus the two runner
## conditions, one of which the shipped "Siege" preset selects.
##
## Every test asks three things of a condition, because two of them are what
## makes a rule real:
##
## [codeblock]
## it can be won      -- the round resolves WIN and the match ends
## it cannot be won by accident  -- no other condition's terms decide it
## the default is untouched      -- total conversion does what it always did
## [/codeblock]
##
## The match is the real [code]scenes/match/match.tscn[/code] on a private copy
## of the shipped rules, driven through the same seams the game drives it
## through: a [MatchLapTracker] reporting a finished lap, and
## [method MatchController.convert_participant]. Nothing here forges a phase or
## writes a private field.

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## A hold short enough to sit through in a test and long enough that no shipped
## reload can empty the ring inside it.
const SHORT_HOLD_SECONDS: float = 1.0

## Seconds of slack allowed on a clock measured in whole physics ticks.
const CLOCK_TOLERANCE_SECONDS: float = 0.2

## [member MatchRules.lap_arrival_tolerance] as the game ships it, in metres of
## arc. Put back by the ALL_ARRIVALS tests once they have finished forcing laps.
const SHIPPED_ARRIVAL_TOLERANCE: float = 1.5

## The shipped rule set, read off disk rather than out of the resource cache.
const SHIPPED_RULES_PATH: String = "res://resources/rules/default_match_rules.tres"

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _participants: Array[MatchParticipant] = []
var _human: MatchParticipant

var _resolutions: int = 0
var _last_outcome: int = -1
var _wins: int = 0
var _winner: MatchParticipant

## The roles every participant was in on the tick the match was won, snapshotted
## from the signal because a later read is a read of a frozen match rather than
## of the moment it ended.
var _running_at_win: int = 0
var _human_running_at_win: bool = false


func before_each() -> void:
	_match = TestFixtures.make_match()

	# The rules are handed over before the instance enters the tree:
	# MatchController arms the match from _ready and the rule set it arms on has
	# to be the one under test.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	# The portal finish these tests are written against. The shipped rules now
	# arm the finisher instead; see MatchRules.finisher_hunts_guard.
	_rules.finisher_hunts_guard = false
	_controller.rules = _rules

	add_child(_match)

	_controller.round_resolved.connect(_on_round_resolved)
	_controller.match_won.connect(_on_match_won)

	_participants = _controller.get_participants()
	_human = _participants[0]


# --- The shutout --------------------------------------------------------------

## A set shutout is won on the removal that reaches the count, and not before.
##
## Two of three, so the win lands with a prisoner still running -- which is the
## whole point of the condition. Under total conversion that same ring is a round
## still in progress.
func test_a_set_shutout_is_won_on_the_count() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 2
	await _arm_round_for(_human)

	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	assert_eq_int(runners.size(), 3, "the shipped round has three prisoners in it")

	assert_true(_controller.convert_participant(runners[0]), "the first removal lands")
	assert_false(_controller.is_resolved(), "one of two is not a shutout")
	assert_eq_int(_controller.get_runners_removed(), 1, "the tally is the round's removals")

	assert_true(_controller.convert_participant(runners[1]), "the second removal lands")
	assert_eq_int(
		int(_controller.get_outcome()), int(MatchController.Outcome.WIN),
		"the count is reached and the round is won",
	)
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_eq_int(_controller.get_resolve_count(), 1, "and happened once")

	# The same door total conversion goes through: a round win, a match win.
	assert_eq_int(_human.rounds_won, 1, "the shooter is credited with the round")
	assert_true(_controller.is_match_over(), "one round held wins the shipped match")
	assert_same(_controller.get_match_winner(), _human, "the shooter won the match")

	# And it was won with the ring not empty, which total conversion cannot do.
	assert_eq_int(_running_at_win, 1, "a prisoner was still running when the tower won")


## A shutout is not won by the terms of any other condition.
##
## The count is 3 and two prisoners are removed: under total conversion that is
## still a live round, and it stays one here too -- the round does not fall back
## on "the ring is nearly empty" or on any arrival.
func test_a_shutout_short_of_the_count_wins_nothing() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 3
	await _arm_round_for(_human)

	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	assert_true(_controller.convert_participant(runners[0]), "one removal lands")
	assert_true(_controller.convert_participant(runners[1]), "a second removal lands")

	assert_false(_controller.is_resolved(), "two of three is not the shutout that was asked for")
	assert_eq_int(_wins, 0, "and nobody has won the match")
	await step_ticks(SETTLE_TICKS)
	assert_false(_controller.is_resolved(), "and a second of play does not change that")


## An UNSET count cannot be won, and emptying the ring does not quietly win it.
##
## [member MatchRules.shutout_count] ships at 0 = unset, and [MatchRules] refuses
## to read that as "all of them". This is the assertion that keeps the refusal
## honest: with every prisoner removed, total conversion's own trigger is true
## and the round still does not resolve, because total conversion is not the rule
## being played.
func test_an_unset_shutout_cannot_be_won_even_by_an_empty_ring() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	_rules.shutout_count = 0
	await _arm_round_for(_human)

	for participant: MatchParticipant in _controller.get_live_participants():
		assert_true(_controller.convert_participant(participant), "the removal lands")

	assert_eq_int(_controller.get_runners_remaining(), 0, "the ring is empty")
	assert_false(_controller.is_resolved(), "and an unset shutout is still not won")
	assert_eq_int(_wins, 0, "nobody won the match on another rule's terms")
	assert_gt(
		float(_rules.validate().size()), 0.0,
		"and the rule set says out loud that it cannot be won",
	)


# --- The hold -----------------------------------------------------------------

## A hold is won by the clock running out, and not one tick early.
func test_a_hold_is_won_when_the_clock_runs_out() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	_rules.hold_duration_seconds = SHORT_HOLD_SECONDS
	_arm_siege_for(_human)

	assert_almost_eq(
		_controller.get_hold_remaining_seconds(), SHORT_HOLD_SECONDS, CLOCK_TOLERANCE_SECONDS,
		"the siege clock is armed with the round",
	)
	await step_seconds(SHORT_HOLD_SECONDS * 0.5)
	assert_false(_controller.is_resolved(), "half a siege is not a siege")
	assert_lt(
		_controller.get_hold_remaining_seconds(), SHORT_HOLD_SECONDS,
		"and the clock is running",
	)

	await step_seconds(SHORT_HOLD_SECONDS * 0.5 + CLOCK_TOLERANCE_SECONDS)
	assert_eq_int(
		int(_controller.get_outcome()), int(MatchController.Outcome.WIN),
		"holding out for the duration wins the round",
	)
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_eq_int(_controller.get_resolve_count(), 1, "and happened once")
	assert_true(_controller.is_match_over(), "one round held wins the shipped match")
	assert_same(_controller.get_match_winner(), _human, "the tower won the match")
	assert_eq_int(_wins, 1, "match_won is announced once")

	# The clock stops with the match, rather than resolving a second round.
	await step_seconds(SHORT_HOLD_SECONDS * 2.0)
	assert_eq_int(_controller.get_resolve_count(), 1, "a won match resolves nothing more")


## Clearing the ring is NOT a hold. The siege is the rule; the conversions are
## not a second way to win it.
func test_clearing_the_ring_does_not_win_a_hold_early() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	_rules.hold_duration_seconds = SHORT_HOLD_SECONDS
	_arm_siege_for(_human)

	for participant: MatchParticipant in _controller.get_live_participants():
		assert_true(_controller.convert_participant(participant), "the removal lands")
	assert_eq_int(_controller.get_runners_remaining(), 0, "the ring is empty")
	assert_false(_controller.is_resolved(), "an empty ring is not a completed siege")
	assert_eq_int(_wins, 0, "and it has won nobody the match")

	# It still ENDS, which is the other half of the requirement: a condition that
	# can never trigger is as broken as one that is unimplemented.
	await step_seconds(SHORT_HOLD_SECONDS + CLOCK_TOLERANCE_SECONDS)
	assert_eq_int(
		int(_controller.get_outcome()), int(MatchController.Outcome.WIN),
		"the clock still decides the round",
	)


## An UNSET hold cannot be won, and does not resolve on the tick it arms.
func test_an_unset_hold_cannot_be_won() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	_rules.hold_duration_seconds = 0.0
	_arm_siege_for(_human)

	assert_almost_eq(
		_controller.get_hold_remaining_seconds(), 0.0, 0.001, "there is no siege to run down"
	)
	await step_seconds(1.0)
	assert_false(_controller.is_resolved(), "a hold of no seconds is not won instantly")
	assert_eq_int(_wins, 0, "and wins nobody the match")
	assert_gt(
		float(_rules.validate().size()), 0.0,
		"and the rule set says out loud that it cannot be won",
	)


## An arrival breaks the siege: the round is lost, the seat changes hands, and
## the incoming shooter starts a FRESH clock rather than inheriting a spent one.
func test_an_arrival_restarts_the_siege_clock() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	_rules.hold_duration_seconds = SHORT_HOLD_SECONDS
	_arm_siege_for(_human)

	await step_seconds(SHORT_HOLD_SECONDS * 0.5)
	var scorer: MatchParticipant = _controller.get_live_participants()[0]
	scorer.tracker.lap_finished.emit(12.0, 96.0)

	assert_eq_int(
		_last_outcome, int(MatchController.Outcome.LOSS), "an arrival is a loss for the tower"
	)
	assert_same(_controller.get_seat_participant(), scorer, "the scorer took the tower")
	assert_false(_controller.is_match_over(), "reaching the end never wins the match")
	assert_almost_eq(
		_controller.get_hold_remaining_seconds(), SHORT_HOLD_SECONDS, CLOCK_TOLERANCE_SECONDS,
		"the new shooter's siege starts from the top",
	)


## A hold ends a match with prisoners still on the ring -- including the human.
##
## This is the case [MatchResultScreen] documents as unreachable under total
## conversion: the match is over, somebody else won it, and the player is a
## prisoner who is still running. The screen reads exactly the flag asserted
## here, so this is what makes its "you survived" branch reachable.
func test_a_hold_can_end_a_match_with_the_human_still_running() -> void:
	_rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	_rules.hold_duration_seconds = SHORT_HOLD_SECONDS
	# Not a balance opinion: the tower is a bot with a live rifle for this one
	# test, and more than one life is what makes "the human is still running a
	# second from now" a fact rather than a race against a reload.
	_rules.prisoner_lives = 3
	_arm_siege_for(_participants[1])

	assert_true(_human.is_running, "the human is a prisoner in this round")
	await step_seconds(SHORT_HOLD_SECONDS + CLOCK_TOLERANCE_SECONDS)

	assert_true(_controller.is_match_over(), "the siege was held and the match is over")
	assert_same(_controller.get_match_winner(), _participants[1], "the tower won it")
	assert_true(
		_human_running_at_win, "and the human was still a running prisoner when it ended"
	)
	assert_gt(float(_running_at_win), 0.0, "the ring was not empty when the match ended")


# --- The runner conditions ----------------------------------------------------

## FIRST_ARRIVAL, the shipped rule: one prisoner through ends the round.
func test_first_arrival_ends_the_round_on_one_prisoner() -> void:
	_rules.runner_win_condition = MatchRules.RunnerWinCondition.FIRST_ARRIVAL
	await _arm_round_for(_human)

	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	runners[0].tracker.lap_finished.emit(12.0, 96.0)

	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "one arrival is a loss")
	assert_eq_int(_controller.get_resolve_count(), 1, "the round resolved once")
	assert_same(_controller.get_seat_participant(), runners[0], "the scorer took the tower")


## ALL_ARRIVALS, which the shipped "Siege" preset selects: the round is not lost
## until every prisoner still in it has finished, and then it is.
##
## The middle assertion is the one that matters -- two of three through is not a
## seat change -- because a stub would either resolve on the first arrival or on
## none at all.
##
## Unlike [constant MatchRules.RunnerWinCondition.FIRST_ARRIVAL], this rule reads
## [method MatchLapTracker.has_finished] on every OTHER prisoner, so a forged
## [signal MatchLapTracker.lap_finished] would not test it: the trackers have to
## finish for real. [method _arm_one_tick_laps] is how they are made to, in one
## physics tick each and through nothing but the rule that says how close to the
## end counts as the end.
func test_all_arrivals_ends_the_round_only_on_the_last_prisoner() -> void:
	_rules.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	var runners: Array[MatchParticipant] = await _arm_one_tick_laps(_human)
	assert_eq_int(runners.size(), 3, "the shipped round has three prisoners in it")

	await _run_lap_of(runners[0])
	assert_true(runners[0].tracker.has_finished(), "the first prisoner really finished")
	assert_false(_controller.is_resolved(), "one through is not all of them")

	await _run_lap_of(runners[1])
	assert_false(_controller.is_resolved(), "two through is not all of them")

	# Hand the arrival tolerance back before the round is lost, or the round the
	# seat change arms next would score three one-tick laps of its own and
	# resolve again while this test was reading the first resolution.
	_rules.lap_arrival_tolerance = SHIPPED_ARRIVAL_TOLERANCE
	await _run_lap_of(runners[2])
	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "the last one through is")
	assert_eq_int(_controller.get_resolve_count(), 1, "the round resolved once")
	assert_same(
		_controller.get_seat_participant(), runners[2],
		"the one who completed the set took the tower",
	)


## A prisoner the rifle removed is not owed an arrival: ALL_ARRIVALS asks it of
## the prisoners still IN the round, or a converted runner would freeze the round
## forever.
func test_all_arrivals_ignores_prisoners_who_are_out_of_the_round() -> void:
	_rules.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	var runners: Array[MatchParticipant] = await _arm_one_tick_laps(_human)
	assert_true(_controller.convert_participant(runners[0]), "one prisoner is removed")

	await _run_lap_of(runners[1])
	assert_false(_controller.is_resolved(), "one of the two still running is not both")

	# See the test above: the next round must not run one-tick laps.
	_rules.lap_arrival_tolerance = SHIPPED_ARRIVAL_TOLERANCE
	await _run_lap_of(runners[2])
	assert_eq_int(
		_last_outcome, int(MatchController.Outcome.LOSS),
		"every prisoner still in the round is through, so the round is over",
	)


# --- The default is untouched -------------------------------------------------

## The shipped rules are total conversion, on an unset count and an unset hold,
## and they behave exactly as they always have: the round is won by emptying the
## ring, is not won before it, and no siege clock runs.
func test_the_shipped_default_is_unchanged() -> void:
	# Off DISK, not out of the cache. The shipped rules resource is one shared
	# instance for the whole process and the SettingsBoot in the match scene
	# writes the player's chosen rules into it every time a match is built, so
	# the cached copy answers "what is this process playing", not "what does the
	# game ship". This assertion is about the file.
	var shipped: MatchRules = ResourceLoader.load(
		SHIPPED_RULES_PATH, "MatchRules", ResourceLoader.CACHE_MODE_IGNORE
	) as MatchRules
	assert_not_null(shipped, "the shipped rule set loads")
	if shipped == null:
		return
	assert_eq_int(
		int(shipped.shooter_win_condition),
		int(MatchRules.ShooterWinCondition.TOTAL_CONVERSION),
		"the shipped rules are total conversion",
	)
	assert_eq_int(shipped.shutout_count, 0, "with no shutout count set")
	assert_almost_eq(shipped.hold_duration_seconds, 0.0, 0.001, "and no hold set")
	assert_true(
		shipped.is_shooter_win_condition_implemented(), "and it is an implemented condition"
	)

	# And the CODE default, which is the control case a rule set built from
	# nothing reproduces.
	var bare: MatchRules = MatchRules.new()
	assert_eq_int(
		int(bare.shooter_win_condition),
		int(MatchRules.ShooterWinCondition.TOTAL_CONVERSION),
		"a rule set built from nothing is total conversion too",
	)
	assert_eq_int(bare.shutout_count, 0, "with an unset count")
	assert_almost_eq(bare.hold_duration_seconds, 0.0, 0.001, "and an unset hold")

	await _arm_round_for(_human)
	assert_almost_eq(
		_controller.get_hold_remaining_seconds(), 0.0, 0.001,
		"no siege clock runs under total conversion",
	)

	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	for index: int in runners.size():
		assert_true(_controller.convert_participant(runners[index]), "the removal lands")
		if index < runners.size() - 1:
			assert_false(
				_controller.is_resolved(), "a ring with %d left is live" % (runners.size() - index - 1)
			)

	assert_eq_int(
		int(_controller.get_outcome()), int(MatchController.Outcome.WIN),
		"an empty ring is still the win",
	)
	assert_true(_controller.is_match_over(), "and still ends the shipped match")


## Every member of [enum MatchRules.ShooterWinCondition] is implemented, and
## [method MatchRules.is_shooter_win_condition_implemented] says so of each --
## which is what the setup screen greys its list out from.
func test_every_declared_shooter_win_condition_is_implemented() -> void:
	var probe: MatchRules = MatchRules.new()
	for value: int in MatchRules.ShooterWinCondition.size():
		probe.shooter_win_condition = value as MatchRules.ShooterWinCondition
		assert_true(
			probe.is_shooter_win_condition_implemented(),
			"%s is implemented" % String(MatchRules.ShooterWinCondition.keys()[value]),
		)


## A shutout of more prisoners than the round has is a round nobody can win, and
## [method MatchRules.validate] says so rather than leaving it to be discovered
## by playing it.
func test_an_unreachable_shutout_is_reported() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	rules.shooter_win_condition = MatchRules.ShooterWinCondition.SHUTOUT_COUNT
	rules.shutout_count = rules.prisoner_count
	assert_false(_mentions_shutout(rules.validate()), "a reachable count draws no complaint")

	rules.shutout_count = rules.prisoner_count + 1
	assert_true(_mentions_shutout(rules.validate()), "a count past the field does")


# --- Helpers ------------------------------------------------------------------

## Take the opening race with [param holder] and settle the round it arms.
##
## Through the seam the match itself scores on -- a lap tracker reporting a
## finished lap -- so every test starts from a real round with a known shooter
## instead of from a 35 second lap.
func _arm_round_for(holder: MatchParticipant) -> void:
	holder.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


## [method _arm_round_for] without the settle, for the siege tests.
##
## The hold clock starts on the tick the round is armed, so a test that waited a
## second for the bodies to come to rest would have spent a second of the siege
## before it measured any of it. Nothing in a siege test reads a position, which
## is what the settle is for.
func _arm_siege_for(holder: MatchParticipant) -> void:
	holder.tracker.lap_finished.emit(30.0, 240.0)


## Arm a round for [param holder] in which a lap takes one physics tick, and hand
## back its prisoners with their trackers held.
##
## [member MatchRules.lap_arrival_tolerance] is "how close to the end counts as
## the end", in metres of arc. Set wider than the longest lap, every tracker
## scores on its first tick -- which is a rule value a sweep may legitimately
## hold, not a forged signal or a written private field. The trackers are stopped
## in the same frame the round arms them, before a single tick has run, so that
## [method _run_lap_of] can decide who finishes and in what order.
##
## [b]The tolerance is no longer enough on its own.[/b] A level is banked on the
## arc AND on the body being at the height of the level above it, so a wide
## tolerance sweeps every lap instantly and then waits forever for a climb that
## is never coming. So the bodies are also put down on the TOP level's lane --
## which is where a prisoner about to finish actually is -- and from there the
## wide tolerance carries them through the remaining levels a tick at a time.
## Nothing private is written and no signal is forged; the bodies are placed and
## the rules are set, and the trackers do the rest themselves.
func _arm_one_tick_laps(holder: MatchParticipant) -> Array[MatchParticipant]:
	# The longest lap of the shipped route is about 490 m of arc; anything past
	# that is "already at the end" on the first tick, on every level.
	_rules.lap_arrival_tolerance = 2000.0
	holder.tracker.lap_finished.emit(30.0, 240.0)
	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	for participant: MatchParticipant in runners:
		participant.tracker.stop()
	_put_on_the_last_level(runners)
	await step_ticks(SETTLE_TICKS)
	for participant: MatchParticipant in runners:
		assert_false(
			participant.tracker.has_finished(),
			"%s has not finished before it is let run" % participant.display_name,
		)
	return runners


## Let one held tracker run, which under [method _arm_one_tick_laps] finishes its
## lap on the next tick and reports it exactly as a real arrival does.
func _run_lap_of(participant: MatchParticipant) -> void:
	participant.tracker.set_physics_process(true)
	# One tick to bank each level still outstanding, one to report the finish,
	# and one of slack. Derived from the route so a fourth level costs no edit.
	var route: RingRoute = _controller.get_route()
	await step_ticks(2 if route == null else route.level_count() + 2)


## Put every body in [param runners] down on the top level's lane, at the bearing
## it is already standing on.
##
## Placed rather than teleported blind: the point comes from the route, so it is
## on a real deck with real floor under it, and the body cannot fall off the one
## it was moved to.
func _put_on_the_last_level(runners: Array[MatchParticipant]) -> void:
	var route: RingRoute = _controller.get_route()
	if route == null or route.level_count() <= 1:
		return
	var centre: Vector3 = _controller.arena.global_position
	for participant: MatchParticipant in runners:
		var body: PlayerController = participant.body
		if body == null:
			continue
		var here: Vector3 = body.global_position
		var bearing: float = atan2(here.z - centre.z, here.x - centre.x)
		body.velocity = Vector3.ZERO
		body.global_position = route.point_on_lane(
			centre, route.last_index(), bearing
		) + Vector3.UP * 0.25


static func _mentions_shutout(problems: PackedStringArray) -> bool:
	for problem: String in problems:
		if problem.contains("shutout_count"):
			return true
	return false


func _on_round_resolved(outcome: int) -> void:
	_resolutions += 1
	_last_outcome = outcome


func _on_match_won(participant: MatchParticipant) -> void:
	_wins += 1
	_winner = participant
	_running_at_win = _controller.get_runners_remaining()
	_human_running_at_win = _human.is_running
