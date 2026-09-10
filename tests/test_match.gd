extends TestCase

## [MatchController]: the match, as opposed to the round.
##
## A match is not a longer round. It opens with a RACE in which there is no
## shooter at all and everybody runs the ring; whoever reaches the end takes the
## tower. After that it is rounds without a clock, and reaching the end never
## wins one -- it wins the SEAT, and the round starts again from the beginning
## with the outgoing shooter out on the track. Only holding the tower through a
## round wins the match. Each turn in the tower shortens that player's reload,
## which is the only reason a match is guaranteed to end at all.
##
## Everything below is asserted against the real
## [code]scenes/match/match.tscn[/code] on the shipped
## [code]resources/rules/default_match_rules.tres[/code]. No rule is retuned to
## make a test convenient: a test that measures a rule set nobody plays is
## measuring nothing.
##
## [b]Why no test here runs an actual lap[/b]
##
## A race is 250-350 m of walking, which is about 35 simulated seconds per
## participant. The suite can afford one lap ([code]test_runner.gd[/code] runs
## it) and not one per test. So the race is decided the way the match decides it
## -- [MatchController] scores off [signal MatchLapTracker.lap_finished] and
## nothing else -- with the tracker made to report the finish it would have
## reported anyway. The seam is the match's own; only the 35 seconds are skipped.
## That the race is genuinely run and genuinely measured, for the human on the
## same clock as the bots, is asserted in
## [method test_the_match_opens_with_a_race_and_no_shooter] against real running.

## Ticks of real running used where a test needs the race to have visibly begun.
const RUNNING_TICKS: int = 60

## Ticks to let placement settle before positions are measured.
const SETTLE_TICKS: int = 30

## How far from the tower spawn still counts as standing on the tower.
const SPAWN_TOLERANCE_METRES: float = 0.5

## The running surface: an annulus with the inner kerb at r=36 and the outer wall
## at r=60.
const DECK_INNER_RADIUS: float = 36.0
const DECK_OUTER_RADIUS: float = 60.0

## Depth below which a body is unambiguously parked out of the world rather than
## merely standing somewhere low. [constant MatchController.PEN_DEPTH_METRES] is
## -100.
const PARKED_DEPTH_METRES: float = -50.0

## Seat changes driven in the reload-ladder test. Alternating them gives one
## player half, so this is comfortably more turns than the shipped ladder needs
## to reach its floor -- the point being to run past the floor and prove the
## ladder stops there.
const LADDER_SWAPS: int = 16

## The seat the race-skip tests hand the tower to. Deliberately a BOT and
## deliberately not the first participant: "give it to myself or a bot" is the
## requirement, and a skip that only ever worked for seat 0 would pass a test
## written against seat 0.
const SKIP_SEAT_INDEX: int = 2

## An opening seat no match has. Names a bot in a field of a thousand.
const ABSURD_SEAT_INDEX: int = 999

## Tolerance on a reload read back off the live rifle, in seconds. The values are
## sums of exported floats, not measurements, so this is float noise and nothing
## else.
const RELOAD_EPSILON: float = 1e-4

var _match: Node3D
var _controller: MatchController
var _rifle: Rifle
var _trigger: WeaponInput
var _participants: Array[MatchParticipant] = []
var _human: MatchParticipant

var _centre: Vector3 = Vector3.ZERO
var _tower_spawn: Vector3 = Vector3.ZERO

var _seat_changes: int = 0
var _wins: int = 0
var _winner: MatchParticipant


func before_each() -> void:
	_match = TestFixtures.make_match()
	# Wired up after instancing but before the tree, because MatchController arms
	# the match from _ready: a listener connected later would miss match_started
	# and the race that follows it.
	add_child(_match)

	_controller = _match.get_node("MatchController") as MatchController
	_controller.seat_changed.connect(_on_seat_changed)
	_controller.match_won.connect(_on_match_won)

	var arena: Node3D = _match.get_node("Arena") as Node3D
	_centre = arena.global_position
	_tower_spawn = (arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D).global_position

	_rifle = _controller.rifle
	_trigger = _rifle.get_node_or_null(^"HumanTrigger") as WeaponInput
	_participants = _controller.get_participants()
	_human = _participants[0]


# --- The race -----------------------------------------------------------------

## The match opens with no shooter, and the race is really run.
##
## "No shooter" has to be true of the world and not merely of a variable, so the
## rifle is checked as well as the seat: during the race it is stowed on the
## controller, aimed by nobody, pointed at nobody, and the human's trigger is
## dead. Every participant, human included, is on the ring and being scored by a
## [MatchLapTracker] of their own -- one clock for the whole field, which is what
## makes this a race rather than four tests run side by side.
func test_the_match_opens_with_a_race_and_no_shooter() -> void:
	assert_eq_string(_controller.get_phase_name(), "RACE", "a match opens with the race")
	assert_null(_controller.get_seat_participant(), "nobody holds the tower during the race")
	assert_eq_int(_controller.get_seat_turns(), 0, "no turn has been taken in the tower")
	assert_eq_int(_controller.get_round_number(), 0, "the race is not a round")
	assert_eq_int(_seat_changes, 0, "the seat has not changed hands")

	assert_eq_int(
		_participants.size(), _controller.get_rules().get_participant_count(),
		"the match has a participant per player",
	)
	assert_eq_int(
		_controller.get_runners_remaining(), _participants.size(),
		"every participant races, one more than a round has runners",
	)
	assert_eq_int(_controller.get_runners_total(), _participants.size(), "the race was armed with the whole field")
	assert_true(_human.is_human(), "the human is a participant like any other")
	for participant: MatchParticipant in _participants:
		assert_false(participant.is_shooter, "%s is not a shooter" % participant.display_name)
		assert_true(participant.is_running, "%s is running" % participant.display_name)
		assert_eq_int(participant.turns_in_tower, 0, "%s has held no turn" % participant.display_name)
		assert_true(
			participant.body.is_in_group(MatchController.RUNNER_GROUP),
			"%s is a legitimate target" % participant.display_name,
		)

	assert_same(_rifle.get_parent(), _controller, "the rifle is stowed on the controller, not on a body")
	assert_null(_rifle.shooter_body, "the stowed rifle belongs to nobody")
	assert_null(_rifle.aim_source, "the stowed rifle is aimed by nobody")
	assert_false(_trigger.is_processing(), "the human's trigger is dead while the tower is empty")

	# The whole field is out on the deck, dealt out along one start line rather
	# than piled into one another. Measured here, before anybody has moved: the
	# spread is a property of the placement and a second of running closes it.
	var places: Array[Vector3] = []
	for participant: MatchParticipant in _participants:
		var place: Vector3 = participant.body.global_position
		assert_between(
			_radius_of(place), DECK_INNER_RADIUS, DECK_OUTER_RADIUS,
			"%s is on the deck" % participant.display_name,
		)
		places.append(place)
	for index: int in places.size():
		for other: int in range(index + 1, places.size()):
			assert_gt(
				_horizontal_distance(places[index], places[other]), 1.0,
				"racers %d and %d do not start inside one another" % [index, other],
			)

	# And it is a real race, measured by running. A second in, everybody's clock
	# is live, the bots have covered ground, and the tower is still empty: nothing
	# is won by standing on the start pad.
	await step_ticks(RUNNING_TICKS)
	assert_eq_string(_controller.get_phase_name(), "RACE", "a second of running does not decide a lap")
	assert_null(_controller.get_seat_participant(), "the tower is still empty")
	for participant: MatchParticipant in _participants:
		assert_true(participant.tracker.is_counting(), "%s is being scored" % participant.display_name)
		assert_false(participant.tracker.has_finished(), "%s has not finished a lap" % participant.display_name)
		if participant.brain != null:
			assert_gt(participant.tracker.get_progress(), 0.0, "%s has covered ground" % participant.display_name)
	# Nobody is at the keyboard, so the human's body has not moved -- and the
	# human is scored on exactly that, by the same tracker, with no credit for
	# standing still.
	assert_almost_eq(_human.tracker.get_progress(), 0.0, 1e-6, "a human who does not run makes no progress")


## The first participant to reach the end takes the tower, and the round begins.
func test_the_race_winner_takes_the_tower() -> void:
	await step_ticks(RUNNING_TICKS)
	var winner: MatchParticipant = _participants[2]
	_win_the_race_for(winner)

	assert_same(_controller.get_seat_participant(), winner, "the first past the post takes the tower")
	assert_true(winner.is_shooter, "the race winner is the shooter")
	assert_false(winner.is_running, "the shooter does not also run")
	assert_eq_int(winner.turns_in_tower, 1, "the race winner is on turn one")
	assert_eq_int(_controller.get_seat_turns(), 1, "the seat reports the holder's own turn count")
	assert_eq_int(_seat_changes, 1, "the seat changed hands exactly once")

	assert_eq_string(_controller.get_phase_name(), "ROUND", "the race is over and a round is on")
	assert_eq_int(_controller.get_round_number(), 1, "round one is armed")
	assert_false(_controller.is_resolved(), "the round is live")
	assert_eq_int(
		_controller.get_runners_remaining(), _controller.get_rules().prisoner_count,
		"the rest of the field runs the round",
	)
	for participant: MatchParticipant in _participants:
		if participant == winner:
			continue
		assert_true(participant.is_running, "%s runs the round" % participant.display_name)

	# The seat is a role, and the rifle follows it.
	assert_same(_rifle.get_parent(), winner.body.head, "the rifle moved onto the seat holder's head")
	assert_same(_rifle.shooter_body, winner.body, "the rifle excludes the holder's own capsule")
	assert_not_null(_rifle.aim_source, "the rifle is aimed from the holder's eye")
	assert_almost_eq(
		_controller.get_current_reload_seconds(), _expected_base_reload(), RELOAD_EPSILON,
		"turn one runs the base reload",
	)

	# And the body went to the tower, not merely the bookkeeping.
	await step_ticks(SETTLE_TICKS)
	assert_lt(
		_horizontal_distance(winner.body.global_position, _tower_spawn), SPAWN_TOLERANCE_METRES,
		"the race winner is standing on the tower",
	)
	assert_false(
		winner.body.is_in_group(MatchController.RUNNER_GROUP),
		"the shooter is no longer a target",
	)
	assert_false(winner.tracker.is_counting(), "the shooter's lap clock is stopped")


# --- The seat is a role -------------------------------------------------------

## The tower can be held by an AI while the human runs, on identical terms.
##
## This is the requirement the whole participant abstraction exists for. When a
## bot wins the race the human is put on the track and runs like everybody else, the
## rifle goes to the bot's head, the mouse cannot fire it, and the bot's own
## lap-running brain is switched off because a shooter does not run laps. The bot
## then converts the field -- the human included, through the same call and the
## same rule -- and wins the match.
func test_the_seat_can_be_held_by_an_ai_while_the_human_runs() -> void:
	var bot: MatchParticipant = _participants[1]
	assert_false(bot.is_human(), "participant 1 is an AI")
	_win_the_race_for(bot)

	assert_same(_controller.get_seat_participant(), bot, "the AI holds the tower")
	assert_true(bot.is_shooter, "the AI is the shooter")
	assert_not_null(bot.brain, "the AI has a lap-running brain")
	assert_false(bot.brain.is_physics_processing(), "a shooter does not run laps")
	assert_same(_rifle.get_parent(), bot.body.head, "the rifle is on the AI's head")
	assert_same(_rifle.shooter_body, bot.body, "the rifle excludes the AI's own capsule")
	assert_false(_trigger.is_processing(), "the mouse cannot fire a rifle the human does not hold")

	assert_true(_human.is_running, "the human runs when a bot holds the tower")
	assert_false(_human.is_shooter, "the human is not the shooter")
	assert_true(
		_human.body.is_in_group(MatchController.RUNNER_GROUP),
		"the human is a legitimate target like any other runner",
	)
	assert_eq_int(_controller.get_lives_left(_human), _controller.get_rules().prisoner_lives, "the human has lives")

	await step_ticks(SETTLE_TICKS)
	assert_lt(
		_horizontal_distance(bot.body.global_position, _tower_spawn), SPAWN_TOLERANCE_METRES,
		"the AI is standing on the tower",
	)
	assert_between(
		_radius_of(_human.body.global_position), DECK_INNER_RADIUS, DECK_OUTER_RADIUS,
		"the human is out on the deck",
	)

	# The bot shoots the human off the ring exactly as a human would shoot a bot.
	assert_true(_controller.convert_participant(_human), "the AI in the tower converts the human")
	assert_false(_human.is_running, "the converted human is out of the round")
	assert_false(
		_human.body.is_in_group(MatchController.RUNNER_GROUP),
		"a converted body is no longer a target",
	)
	# The shipped rules play GhostBehaviour.CATCH_AND_SWAP, so "out of the round"
	# is a change of role rather than a removal: the body stays in the world and
	# keeps being stepped. What it stops being is a RUNNER, which is what the
	# shooter's win condition counts. Under GhostBehaviour.NONE the same call
	# parks the body under the pit instead; that branch is test_ghosts.gd's.
	assert_true(_human.is_ghost, "a converted prisoner becomes a ghost")
	assert_gt(
		_human.body.global_position.y, PARKED_DEPTH_METRES,
		"a ghost is still in the world, not parked under the pit",
	)

	for participant: MatchParticipant in _controller.get_live_participants():
		assert_true(_controller.convert_participant(participant), "the AI converts %s" % participant.display_name)

	assert_true(_controller.is_match_over(), "converting the field wins the match")
	assert_same(_controller.get_match_winner(), bot, "an AI can win the match")
	assert_eq_int(_wins, 1, "match_won is announced once")
	assert_same(_winner, bot, "match_won names the AI")
	assert_false(_trigger.is_processing(), "the trigger is dead once the match is over")
	for participant: MatchParticipant in _participants:
		assert_false(
			participant.body.is_physics_processing(),
			"%s is frozen by the end of the match" % participant.display_name,
		)


# --- The terminator -----------------------------------------------------------

## The reload shortens on every turn a player takes in the tower, and stops at
## the floor.
##
## This is the only thing that guarantees a match ends. A shooter too slow to
## close a round loses the seat, wins it back, and comes back faster; eventually
## fast enough. The ladder is a player's OWN history -- turns accumulate across
## seats lost to somebody else, which is what makes regaining the tower progress
## rather than a fresh start -- and it is bounded, so it can never turn the
## single-shot rifle into an automatic.
##
## Driven by handing the tower back and forth between two players, which is the
## only way a turn is ever counted, and read off the live rifle rather than out
## of the rule that computed it.
func test_the_reload_shortens_across_turns_and_stops_at_the_floor() -> void:
	var rules: MatchRules = _controller.get_rules()
	var rival: MatchParticipant = _participants[1]
	var base: float = _expected_base_reload()
	var floor_seconds: float = maxf(rules.reload_floor_seconds, _rifle.profile.min_reload_seconds)

	# Without this the test would pass vacuously on a rule set with no ladder in
	# it -- and a match with no ladder has no terminator at all.
	assert_gt(rules.reload_reduction_per_turn, 0.0, "the shipped match has a terminator")
	assert_gt(base, floor_seconds, "there is room between the base reload and the floor")

	_win_the_race_for(_human)
	assert_almost_eq(_controller.get_current_reload_seconds(), base, RELOAD_EPSILON, "turn one is the base reload")

	var human_ladder: PackedFloat32Array = PackedFloat32Array([_controller.get_current_reload_seconds()])
	for _swap: int in LADDER_SWAPS:
		# Whoever is not in the tower reaches the end and takes it.
		var scorer: MatchParticipant = rival if _controller.get_seat_participant() == _human else _human
		_win_the_race_for(scorer)

		var holder: MatchParticipant = _controller.get_seat_participant()
		var reload: float = _controller.get_current_reload_seconds()
		assert_ge(
			reload, floor_seconds - RELOAD_EPSILON,
			"turn %d never drills through the floor" % holder.turns_in_tower,
		)
		assert_almost_eq(
			reload,
			maxf(base - rules.reload_reduction_per_turn * float(holder.turns_in_tower - 1), floor_seconds),
			RELOAD_EPSILON,
			"%s on turn %d runs the ladder's reload" % [holder.display_name, holder.turns_in_tower],
		)
		if holder == _human:
			human_ladder.append(reload)

	# Turns are the player's own and survive losing the seat: the ladder has one
	# rung per turn the human ever took, not per turn they held consecutively.
	assert_eq_int(
		_human.turns_in_tower, human_ladder.size(),
		"a turn count accumulates across seats lost to somebody else",
	)
	assert_gt(float(human_ladder.size()), 2.0, "the ladder needs several turns to be a ladder")

	for index: int in range(1, human_ladder.size()):
		var previous: float = human_ladder[index - 1]
		var current: float = human_ladder[index]
		if previous > floor_seconds + RELOAD_EPSILON:
			assert_lt(current, previous, "turn %d is faster than turn %d" % [index + 1, index])
		else:
			assert_almost_eq(current, previous, RELOAD_EPSILON, "at the floor the ladder stops")
		assert_ge(current, floor_seconds - RELOAD_EPSILON, "turn %d respects the floor" % (index + 1))

	assert_almost_eq(
		human_ladder[human_ladder.size() - 1], floor_seconds, RELOAD_EPSILON,
		"enough turns in the tower reach the floor exactly",
	)
	assert_almost_eq(
		_rifle.reload_seconds, human_ladder[human_ladder.size() - 1], RELOAD_EPSILON,
		"the rifle is running the reload the ladder says it is",
	)


# --- Skipping the race --------------------------------------------------------

## Skipping the race arms exactly the round the race would have armed.
##
## [b]The whole value of the skip is that it produces no difference.[/b] It
## exists because somebody testing a change to anything else should not have to
## run a lap of the ring first -- so what it must hand back is the match they
## would have had by running it and winning, and not a second kind of match that
## is nearly the same. A skip that produced a subtly different round would be
## worse than no skip, because every measurement taken through it would be a
## measurement of something nobody plays.
##
## So the match is armed both ways -- skipped, and raced and then won by the same
## seat -- and the same description is read off it each time and compared as one
## string. The description is taken before a single physics frame on purpose:
## placement is arithmetic and deterministic, and a tick of bot steering
## afterwards is not.
func test_skipping_the_race_arms_the_round_a_race_would_have() -> void:
	# A private copy. The shipped .tres is one instance for the whole process and
	# a test that retuned it would hand every later test a different game.
	var rules: MatchRules = TestFixtures.match_rules()
	assert_true(rules.open_with_race, "the shipped rules open with a race")
	rules.open_with_race = false
	rules.opening_seat_index = SKIP_SEAT_INDEX
	_controller.rules = rules
	_controller.start_match()

	var seat: MatchParticipant = _controller.get_seat_participant()
	assert_not_null(seat, "somebody is in the tower the moment a skipped match starts")
	if seat == null:
		return
	assert_eq_int(seat.index, SKIP_SEAT_INDEX, "and it is the seat the rules named")
	assert_false(seat.is_human(), "which is a bot, so the skip is not a human-only path")
	assert_eq_string(_controller.get_phase_name(), "ROUND", "the match is in a round, not a race")
	assert_eq_int(_controller.get_round_number(), 1, "and it is the first one")
	assert_eq_int(seat.turns_in_tower, 1, "the seat holder is on turn one")
	assert_almost_eq(
		_horizontal_distance(seat.body.global_position, _tower_spawn), 0.0,
		SPAWN_TOLERANCE_METRES, "standing on the tower",
	)
	assert_same(_rifle.get_parent(), seat.body.head, "with the rifle in their hands")
	assert_eq_int(
		_controller.get_runners_remaining(), _controller.get_rules().prisoner_count,
		"and every other participant out on the track",
	)
	var skipped: PackedStringArray = _describe_round()

	# Now the same rules with the race back on, won by the same seat.
	rules.open_with_race = true
	_controller.start_match()
	assert_eq_string(_controller.get_phase_name(), "RACE", "the race is back")
	_win_the_race_for(_participants[SKIP_SEAT_INDEX])

	var raced: PackedStringArray = _describe_round()
	assert_eq_string(
		"\n".join(skipped), "\n".join(raced),
		"a skipped round is the round a race would have produced",
	)


## An opening seat the match has no participant for still starts a match.
##
## The value is a saved player preference by the time the match reads it, and a
## preference outlives the prisoner count it was chosen against. Dropping the
## count must not leave the game unable to start.
func test_a_skipped_race_clamps_a_seat_the_match_does_not_have() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	rules.open_with_race = false
	rules.opening_seat_index = ABSURD_SEAT_INDEX
	_controller.rules = rules
	_controller.start_match()

	var seat: MatchParticipant = _controller.get_seat_participant()
	assert_not_null(seat, "a match with an impossible seat still has somebody in the tower")
	if seat == null:
		return
	assert_eq_int(
		seat.index, _controller.get_participants().size() - 1,
		"clamped to the last seat the match actually has",
	)
	assert_eq_string(_controller.get_phase_name(), "ROUND", "and the round is armed")


# --- Helpers ------------------------------------------------------------------

## Hand the tower to [param participant] through the tracker seam.
##
## [MatchController] scores a race and a round off
## [signal MatchLapTracker.lap_finished] and nothing else, so this is the event a
## body finishing its lap produces -- without the 35 simulated seconds of walking
## that produce it. Nothing private is written and no phase is forged.
func _win_the_race_for(participant: MatchParticipant) -> void:
	participant.tracker.lap_finished.emit(30.0, 240.0)


## What the match asks the rifle to reload in on turn one: the rules' own base
## when they state one, and the weapon's when they do not.
func _expected_base_reload() -> float:
	return _controller.get_rules().get_base_reload_seconds(_rifle.profile.base_reload_seconds)


func _on_seat_changed(_participant: MatchParticipant, _turns_in_tower: int) -> void:
	_seat_changes += 1


func _on_match_won(participant: MatchParticipant) -> void:
	_wins += 1
	_winner = participant


func _radius_of(point: Vector3) -> float:
	return Vector2(point.x - _centre.x, point.z - _centre.z).length()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Everything about the round that has just been armed, as readable lines.
##
## Positions are in it on purpose: "the same round" has to mean the bodies are in
## the same places and the rifle is in the same hands, not merely that the
## counters read alike. Compared as one joined string so a difference names
## itself in the failure message instead of being reported as "false".
func _describe_round() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("phase=%s outcome=%s" % [
		_controller.get_phase_name(), _controller.get_outcome_name(),
	])
	lines.append("round=%d resolves=%d" % [
		_controller.get_round_number(), _controller.get_resolve_count(),
	])
	lines.append("runners=%d/%d removed=%d" % [
		_controller.get_runners_remaining(),
		_controller.get_runners_total(),
		_controller.get_runners_removed(),
	])
	lines.append("reload=%.4f" % _controller.get_current_reload_seconds())
	lines.append("rifle=%s aim=%s" % [
		_rifle.get_parent().get_path(),
		"none" if _rifle.aim_source == null else _rifle.aim_source.get_path(),
	])
	for participant: MatchParticipant in _controller.get_participants():
		lines.append("%s role=%s turns=%d lives=%d target=%s at=%s" % [
			participant.display_name,
			participant.get_role_name(),
			participant.turns_in_tower,
			participant.lives,
			participant.body.is_in_group(MatchController.RUNNER_GROUP),
			_describe_point(participant.body.global_position),
		])
	return lines


func _describe_point(point: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [point.x, point.y, point.z]
