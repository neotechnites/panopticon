extends TestCase

## [MatchController]: what a ROUND is worth inside a match, and the two forms of
## the placement trap that have each cost this project a day.
##
## Every test here instances the real [code]scenes/match/match.tscn[/code] --
## arena, four bodies, rifle, HUD and all -- on the shipped
## [code]resources/rules/default_match_rules.tres[/code], rather than wiring a
## controller up by hand or retuning the rules into something easier to test. The
## rules under test are about what happens when a whole round is armed, and the
## regressions at the bottom of this file are about what the physics server does
## on the tick bodies are placed. Neither survives being tested on a
## stripped-down stand-in.
##
## [b]A round is reached through the race[/b]
##
## The shipped match opens with a seatless race, so [method before_each] hands
## that race to the human through the one seam the match itself uses: a
## [MatchLapTracker] reporting that its body finished the lap. Nothing here
## forges a phase or writes a private field -- the controller is driven exactly
## as the game drives it, at the speed a test can afford.
##
## What a round now costs the shooter is no longer "the round": an arrival takes
## the SEAT and restarts the round, and only converting everyone ends the match.
## The tests below are named for that.

## Ticks to let a freshly armed round settle before it is measured. One second
## is far longer than the handful of ticks either placement bug needed to fling a
## body across the arena, which is the point: the assertion has to be made after
## the damage would have been done, not during it.
const SETTLE_TICKS: int = 60

## Ticks of real running, used where a test needs runners with progress to lose.
const RUNNING_TICKS: int = 60

## How far a body may be from the tower spawn, horizontally, and still count as
## standing on the tower. The platform is 8 m in radius and the outer wall is at
## 60 m; the bugs this bounds put bodies at 38 m and at 59 m. Half a metre leaves
## room for the settle onto the platform and nothing else.
const SPAWN_TOLERANCE_METRES: float = 0.5

## How far off the track a placed prisoner may be.
##
## The start line is dealt out across the width of the track, so a body that has
## only just been put down is legitimately up to half the line's width off it and
## a body that has been walking for a second has steered most of that back. The
## trap this bounds drags a body to r=59, which is 14.5 m off the track.
const TRACK_TOLERANCE_METRES: float = 4.0

## How far a standing body's feet may be from the surface it was put on. The deck
## and the tower platform are both at y=0 and the spawn markers sit 0.25 m above
## them; the trap this bounds lifts bodies to y=8 as they slide out to the wall.
const HEIGHT_TOLERANCE_METRES: float = 0.5

## How high a body can be over the deck and still be ON it: the tuned
## MovementProfile's jump apex, which a runner's brain may be part way through.
const JUMP_APEX_METRES: float = 1.11

## The running surface, from [code]scenes/ring/bentham_ring.tscn[/code]: an annulus
## with the inner kerb at r=36 and the outer wall at r=60.
const DECK_INNER_RADIUS: float = 36.0
const DECK_OUTER_RADIUS: float = 60.0

## Radius of the tower platform. A body further out than this is off the stand.
const TOWER_PLATFORM_RADIUS: float = 8.0

## Two bodies closer together than this on the start line are effectively in the
## same place. The body capsule is 0.8 m across, so anything under a metre is
## contact.
const MIN_START_SEPARATION_METRES: float = 1.0

## How far off the start marker's angle a freshly placed body may be, in radians.
## The spread along the line is radial, so it does not move an angle at all and
## this is float slop rather than a real bound.
const START_ANGLE_TOLERANCE_RADIANS: float = 1e-3

var _match: Node3D
var _controller: MatchController
var _player: PlayerController
var _participants: Array[MatchParticipant] = []
var _human: MatchParticipant

var _centre: Vector3 = Vector3.ZERO
var _start_point: Vector3 = Vector3.ZERO
var _tower_spawn: Vector3 = Vector3.ZERO

var _resolutions: int = 0
var _last_outcome: int = -1
var _wins: int = 0
var _winner: MatchParticipant

## Set while the re-entrancy probe in [method test_a_round_resolves_exactly_once]
## is armed, so it fires on the first resolution and never again.
var _probe_armed: bool = false
var _probe_conversions_refused: int = 0
var _probe_conversions_accepted: int = 0
var _probe_resolve_count: int = -1


func before_each() -> void:
	_match = TestFixtures.make_match()
	# Everything above happens before the instance enters the tree, because
	# MatchController arms the match from _ready and that arming is itself under
	# test.
	add_child(_match)

	_controller = _match.get_node("MatchController") as MatchController
	_player = _match.get_node("Player") as PlayerController
	_controller.round_resolved.connect(_on_round_resolved)
	_controller.match_won.connect(_on_match_won)

	var arena: Node3D = _match.get_node("Arena") as Node3D
	_centre = arena.global_position
	_start_point = (arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D).global_position
	_tower_spawn = (arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D).global_position

	_participants = _controller.get_participants()
	_human = _participants[0]

	# The match opens with a race for the tower. Hand it to the human, through
	# the same seam the match itself scores on, so that every test below starts
	# from a round with a known shooter instead of from a 35 second lap.
	_win_the_race_for(_human)

	await step_ticks(SETTLE_TICKS)


# --- Arming -------------------------------------------------------------------

## A round arms with every prisoner running, live, and unresolved -- and with the
## seat holder in the tower rather than on the ring.
func test_a_round_starts_with_every_prisoner_on_the_track() -> void:
	assert_eq_int(int(_controller.get_phase()), int(MatchController.Phase.ROUND), "the race is over and a round is on")
	assert_eq_int(_controller.get_round_number(), 1, "this is the first round of the match")
	assert_same(_controller.get_seat_participant(), _human, "the race winner holds the tower")
	assert_eq_int(
		_controller.get_runners_remaining(), _controller.get_runners_total(),
		"every prisoner armed is still running",
	)
	assert_eq_int(
		_controller.get_runners_total(), _controller.get_rules().prisoner_count,
		"a round is run by prisoner_count runners, one fewer than the race",
	)
	assert_false(_controller.is_resolved(), "a fresh round is not resolved")
	assert_eq_int(_controller.get_resolve_count(), 0, "a fresh round has resolved nothing")

	# The shooter is not a legitimate target and the runners are. Membership of
	# the group is how an AI in the tower finds who it may shoot at.
	assert_false(
		_human.body.is_in_group(MatchController.RUNNER_GROUP),
		"the shooter is not in the runner group",
	)

	# Every runner is out on the deck, on the shared track, and shootable. The
	# deck is the annulus r=36..60.
	#
	# [b]Re-armed with the brains stood down, and that is the point of the
	# assertion.[/b] This is a claim about the PLACEMENT, not about how the
	# prisoners then play: a cover-playing prisoner leaves the track on purpose
	# the moment it believes a guard is watching, and with a human in the tower
	# it now rightly does -- so a second of steering puts it against a cover
	# band, four metres or more off the track, and the assertion below stopped
	# measuring the trap it was written for. Standing the brains down for the
	# settle leaves exactly what this test is about: bodies put down on the line
	# and a physics server catching up with them, which is where the trap lives
	# -- it dragged a body to r=59 while nothing was steering it at all.
	_controller.start_round()
	var runners: Array[RingRunner] = _controller.get_live_runners()
	for runner: RingRunner in runners:
		runner.set_physics_process(false)
		# The intent seam holds its last command until something writes another,
		# so a brain switched off mid-stride would leave the body walking on the
		# strength of it. Letting go of the keys is what stopping actually is.
		runner.input.command.clear()
	await step_ticks(SETTLE_TICKS)

	for index: int in runners.size():
		var place: Vector3 = runners[index].controller.global_position
		assert_between(_radius_of(place), DECK_INNER_RADIUS, DECK_OUTER_RADIUS, "runner %d is on the deck" % index)
		assert_almost_eq(
			_radius_of(place), _controller.get_rules().track_radius, TRACK_TOLERANCE_METRES,
			"runner %d is on the track" % index,
		)
		assert_true(
			runners[index].controller.is_in_group(MatchController.RUNNER_GROUP),
			"runner %d is a legitimate target" % index,
		)


## Everybody starts on ONE line, and nobody starts inside anybody else.
##
## The two halves are the whole of the placement rule. One line: every body is at
## the start marker's own angle, so they all owe the same arc to the same finish
## and the opening race is first past the post rather than a draw made before
## anybody moves. Not inside one another: two capsules placed in the same cubic
## metre are separated by the depenetration solver, which throws both of them
## across the arena -- a trap this project has already paid for twice.
##
## Measured on the frame the round is armed. A second later they have steered
## back onto the shared track and are legitimately shoulder to shoulder, which is
## the design and not a fault.
func test_the_field_is_dealt_out_along_one_start_line() -> void:
	_controller.start_round()

	var placed: Array[MatchParticipant] = _controller.get_live_participants()
	assert_gt(float(placed.size()), 1.0, "there is more than one body to separate")

	var line_angle: float = _angle_of(_start_point)
	for participant: MatchParticipant in placed:
		assert_almost_eq(
			absf(wrapf(_angle_of(participant.body.global_position) - line_angle, -PI, PI)),
			0.0, START_ANGLE_TOLERANCE_RADIANS,
			"%s starts on the one line" % participant.display_name,
		)
	for index: int in placed.size():
		for other: int in range(index + 1, placed.size()):
			assert_gt(
				_horizontal_distance(
					placed[index].body.global_position, placed[other].body.global_position
				),
				MIN_START_SEPARATION_METRES,
				"%s and %s do not start inside one another"
				% [placed[index].display_name, placed[other].display_name],
			)


# --- The rules ----------------------------------------------------------------

## Removing every runner is the win, only the last one is, and it wins the MATCH.
##
## Reaching the end wins the tower; holding the tower through a round is the only
## thing that wins a match. So the shooter who converts the ring does not merely
## take the round: with the shipped [member MatchRules.rounds_to_win_match] of 1,
## that is the end of the match and nothing resolves afterwards.
func test_all_runners_removed_wins_the_match() -> void:
	var runners: Array[RingRunner] = _controller.get_live_runners()
	assert_gt(float(runners.size()), 1.0, "the win condition needs more than one runner to be interesting")

	for index: int in runners.size():
		var is_last: bool = index == runners.size() - 1
		assert_true(_controller.remove_runner(runners[index]), "removing a live runner succeeds")
		assert_eq_int(
			_controller.get_runners_remaining(), runners.size() - index - 1,
			"the remaining count drops by one per removal",
		)
		if not is_last:
			assert_false(
				_controller.is_resolved(),
				"the round is still live with %d runners left" % (runners.size() - index - 1),
			)
			assert_false(_controller.is_match_over(), "the match is not over while a runner is still running")

	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.WIN), "an empty ring is a win")
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_eq_string(_controller.get_outcome_name(), "WIN", "the outcome name follows the outcome")

	# The round was held from the tower, so the match is over and the shooter has
	# won it -- not the round only.
	assert_eq_int(_human.rounds_won, 1, "the shooter is credited with the round")
	assert_true(_controller.is_match_over(), "converting the ring ends the match")
	assert_eq_string(_controller.get_phase_name(), "MATCH_OVER", "the phase follows the match")
	assert_same(_controller.get_match_winner(), _human, "the shooter won the match")
	assert_eq_int(_wins, 1, "match_won is announced once")
	assert_same(_winner, _human, "match_won names the shooter")

	# And the match STOPS: no further conversion, no further arrival, no second
	# resolution. A win that could be added to is not a win.
	for participant: MatchParticipant in _controller.get_participants():
		assert_false(
			_controller.convert_participant(participant),
			"a won match refuses to convert %s" % participant.display_name,
		)
	var rounds_before: int = _controller.get_round_number()
	for participant: MatchParticipant in _controller.get_participants():
		participant.tracker.lap_finished.emit(1.0, 300.0)
	assert_eq_int(_controller.get_round_number(), rounds_before, "an arrival after the match arms no new round")
	assert_eq_int(_controller.get_resolve_count(), 1, "one round was resolved, and only one")
	assert_same(_controller.get_match_winner(), _human, "the winner did not change")
	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.WIN), "the outcome did not change")


## One runner reaching the end takes the SEAT and restarts the round.
##
## This is the asymmetry the game is built on, and the match's version of it: the
## tower has to stop all of them, so two out of three is not a partial success,
## it is the tower changing hands. The round the shooter was playing is over --
## resolved [constant MatchController.Outcome.LOSS], once -- and the next one
## begins immediately with the scorer in the tower, the outgoing shooter on a
## track, and nobody's progress carried over.
func test_one_arrival_takes_the_seat_and_restarts_the_round() -> void:
	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	assert_gt(float(runners.size()), 1.0, "the seat change needs survivors to be interesting")

	# Give the ring something to lose: real arc, and one runner already converted.
	await step_ticks(RUNNING_TICKS)
	var scorer: MatchParticipant = runners[0]
	var bystander: MatchParticipant = runners[1]
	var converted: MatchParticipant = runners[runners.size() - 1]
	assert_true(_controller.convert_participant(converted), "a runner is taken out before the arrival")
	assert_gt(bystander.tracker.get_progress(), 0.0, "a survivor has real progress to lose")

	# The tracker reports that the lap is complete. What that COSTS is the
	# match's business, which is exactly the seam being tested.
	scorer.tracker.lap_finished.emit(12.0, 96.0)

	# Read back in the same frame: a physics tick between the seat change and the
	# measurement would put a few centimetres of the NEW round on the clock and
	# hide a carried lap underneath them.
	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "one arrival is a loss for the shooter")
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_eq_int(_controller.get_resolve_count(), 1, "exactly one resolution for one round")

	# The seat, not the match.
	assert_same(_controller.get_seat_participant(), scorer, "the scorer took the tower")
	assert_true(scorer.is_shooter, "the scorer is the shooter")
	assert_false(scorer.is_running, "the shooter is not also a runner")
	assert_eq_int(scorer.turns_in_tower, 1, "the scorer is on their first turn")
	assert_false(_controller.is_match_over(), "reaching the end never wins the match")
	assert_null(_controller.get_match_winner(), "nobody has won the match")

	# The outgoing shooter becomes a runner, like everybody else.
	assert_false(_human.is_shooter, "the outgoing shooter no longer holds the seat")
	assert_true(_human.is_running, "the outgoing shooter is a runner now")
	assert_true(
		_human.body.is_in_group(MatchController.RUNNER_GROUP),
		"the outgoing shooter is a legitimate target now",
	)

	# The round restarts from the beginning: everyone back, nothing carried.
	assert_eq_int(_controller.get_round_number(), 2, "the round restarted")
	assert_false(_controller.is_resolved(), "the new round is live")
	assert_eq_int(
		_controller.get_runners_remaining(), _controller.get_rules().prisoner_count,
		"a full ring runs the restarted round, converted runners included",
	)
	assert_true(converted.is_running, "the runner converted in the last round is back on the ring")
	for participant: MatchParticipant in _controller.get_live_participants():
		assert_almost_eq(
			participant.tracker.get_progress(), 0.0, 1e-9,
			"%s starts the restarted round with no progress" % participant.display_name,
		)
		assert_false(participant.tracker.has_finished(), "%s has not finished" % participant.display_name)
		assert_almost_eq(
			absf(wrapf(
				_angle_of(participant.body.global_position) - _angle_of(_start_point), -PI, PI
			)),
			0.0, START_ANGLE_TOLERANCE_RADIANS,
			"%s is back on the start line" % participant.display_name,
		)

	# And the restarted round really is running, rather than a frozen tableau of
	# the one before it.
	await step_ticks(RUNNING_TICKS)
	for participant: MatchParticipant in _controller.get_live_participants():
		assert_true(participant.tracker.is_counting(), "%s is being scored" % participant.display_name)
		if participant.brain != null:
			assert_true(participant.brain.is_physics_processing(), "%s is running again" % participant.display_name)
			assert_gt(participant.tracker.get_progress(), 0.0, "%s has new progress" % participant.display_name)


## Whatever else happens, a round resolves exactly once.
##
## The window the guard protects is one frame wide and no longer reachable from
## outside: an arrival resolves the round and restarts it in the same call, so by
## the time a caller gets control back, round two is already armed. The honest
## way to stand in that window is to fire the second arrival and the late
## conversions from inside [signal MatchController.round_resolved] itself, which
## is exactly the instant the round is decided and has not yet been replaced.
## Unguarded, the conversions there would turn a lost seat into a won match.
##
## [method MatchController.get_resolve_count] is the assertion; it exists for
## precisely this.
func test_a_round_resolves_exactly_once() -> void:
	_probe_armed = true
	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	runners[0].tracker.lap_finished.emit(12.0, 96.0)

	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "the first arrival decides it")
	assert_gt(float(_probe_conversions_refused), 0.0, "the probe actually tried to convert somebody")
	assert_eq_int(_probe_conversions_accepted, 0, "a resolved round refuses every further removal")
	assert_eq_int(_probe_resolve_count, 1, "the arrivals fired inside the resolution added nothing")

	assert_eq_int(_controller.get_resolve_count(), 1, "exactly one resolution for one round")
	assert_eq_int(_resolutions, 1, "exactly one round_resolved signal for one round")
	assert_false(_controller.is_match_over(), "the late conversions did not turn the loss into a win")
	assert_eq_int(_controller.get_round_number(), 2, "the seat change restarted the round")

	# The next round is a new round, and gets its own single resolution.
	assert_false(_controller.is_resolved(), "the restarted round is live again")
	var next: Array[MatchParticipant] = _controller.get_live_participants()
	next[0].tracker.lap_finished.emit(12.0, 96.0)
	assert_eq_int(_controller.get_resolve_count(), 2, "two rounds played, two resolutions")
	assert_eq_int(_resolutions, 2, "two rounds played, two announcements")

	# And the other resolution path, once, on a round of its own.
	for participant: MatchParticipant in _controller.get_live_participants():
		_controller.convert_participant(participant)
	assert_eq_int(int(_controller.get_outcome()), int(MatchController.Outcome.WIN), "the third round was held")
	assert_eq_int(_controller.get_resolve_count(), 3, "three rounds played, three resolutions")
	assert_eq_int(_resolutions, 3, "three rounds played, three announcements")


# --- Regression ---------------------------------------------------------------

## Spawning the runners must not move the shooter off the tower.
##
## [b]The bug.[/b] [MatchController] instanced each runner and added it to the
## tree at the scene's default transform -- the origin -- and only then placed it
## on the track. The physics server registers a body where it is on the tick it
## enters the tree, and the tower spawn [i]is[/i] the origin, so three 0.8 m
## capsules materialised inside the shooter's own capsule. Depenetration resolved
## the overlap the only way it could and threw the shooter out to the arena's
## outer wall, 59 m away, before the runners had moved anywhere.
##
## [b]Why it needs a test and not a comment.[/b] It is invisible after the fact:
## by the time anything could look, the runners are correctly placed and
## a shape query at the tower finds nothing wrong. The only evidence is where the
## shooter ended up. It survived one fix attempt because the ejection is not
## instantaneous -- it takes a few ticks -- so a check made on the spawn frame saw
## nothing. And it will come back the moment somebody adds a fourth spawn site,
## or reorders the spawn so the placement follows the [method Node.add_child]
## again.
##
## [b]What the fix is.[/b] The body's position is written [i]before[/i] it enters
## the tree, so it is never registered at the origin at all.
##
## [b]The margin.[/b] The restart assertion is the strict one: the player is
## settled and stationary, the restart puts it back on the same marker, and a
## measured reproduction of the old ordering lifts it 1.78 m. The threshold is
## 0.05 m -- 35x under the bug, and 197x over the 0.000254 m the body actually
## moves when it is re-placed on the spawn 0.25 m above the platform and allowed
## to settle again. Both numbers are measured, not guessed; do not relax it.
func test_spawning_runners_does_not_displace_the_player() -> void:
	# before_each has already armed a round with the human in the tower and let
	# it settle for a second.
	assert_true(_human.is_shooter, "the human holds the seat for this test")
	var drift: float = _horizontal_distance(_player.global_position, _tower_spawn)
	assert_lt(
		drift, SPAWN_TOLERANCE_METRES,
		"the player must still be on the tower after the opening round is armed",
	)

	# And again on a restart, which re-places four bodies while the player is
	# already standing on the spawn point rather than arriving at it.
	var settled_at: Vector3 = _player.global_position
	_controller.start_round()
	await step_ticks(SETTLE_TICKS)
	assert_vec3_almost_eq(
		_player.global_position, settled_at, 0.05,
		"arming a round must not move a stationary player one way or the other",
	)
	assert_lt(
		_horizontal_distance(_player.global_position, _tower_spawn), SPAWN_TOLERANCE_METRES,
		"the player must still be on the tower after a restart re-spawns the runners",
	)

	# The player is standing, not falling through the platform or riding it up.
	assert_almost_eq(
		_player.global_position.y, _tower_spawn.y, HEIGHT_TOLERANCE_METRES,
		"the player is standing on the tower platform",
	)
	assert_true(_player.is_on_floor(), "the player is on the tower platform, not in the air")

	# The runners went where they were meant to go, which is the other half of
	# the same fix: nothing was displaced, in either direction.
	var runners: Array[RingRunner] = _controller.get_live_runners()
	assert_eq_int(runners.size(), _controller.get_runners_total(), "all runners survived the spawn")
	for index: int in runners.size():
		assert_gt(
			_radius_of(runners[index].controller.global_position), 30.0,
			"runner %d is out on the ring, not at the origin" % index,
		)


## A seat change must not drag both bodies out of the arena.
##
## [b]The same trap, second form, and the nastier one.[/b] The known form is a
## body ADDED to the tree at the origin. The form that bites a MATCH is a body
## MOVED while another body stands on the point it is moving away from -- which is
## every seat change, because the incoming shooter is put exactly where the
## outgoing one is standing.
##
## Setting [member Node3D.global_position] on a [CharacterBody3D] is not a
## teleport as far as the physics server is concerned. The body is kinematic, so
## the server treats the change as MOTION from the transform it last flushed to
## the new one, and a kinematic body that moves CARRIES whatever is standing at
## the start of that motion. Measured, with the tower at the origin: the outgoing
## shooter is sent to the track, picks up the incoming shooter who has just been
## put on the tower, and deposits it 38 m away on top of itself; both then slide
## off the deck and out to the wall at r=59, gaining height the whole way, while
## the node graph insists the shooter is standing on the tower. Reordering the
## two placements does not help: only the last transform written in a frame is
## flushed, so the server sees the same swap either way.
##
## [b]Why it needs a test.[/b] The node graph is not evidence. Every readable
## field -- the seat, the phase, the participant's own position -- was correct
## while both capsules were against the outer wall, because the position IS
## correct and it is the physics that runs away with it afterwards. Only a
## measurement taken after the bodies have been woken and allowed to move can see
## it, which is why this asserts a second after the change and not on the frame
## of it.
##
## [b]What the fix is.[/b] Bodies are placed with their collision switched off
## and their motion stopped, and woken two physics frames later, once the server
## has flushed the new transforms. Delete
## [method MatchController._hold_body] or the settle counter and this fails.
##
## [b]The margin.[/b] The bug parks both bodies at r=59, y=8, and a reproduction
## of the un-held placement run against this fixture -- both transforms written
## in one frame with collision live -- left the incoming shooter 37.7 m from the
## tower spawn a second later. The incoming shooter is asserted within 0.5 m of
## that spawn, so the measured reproduction trips it by 75x and the shipped bug
## by 118x; the height bound of 0.5 m trips on the bug's 7.75 m by 15x, and the
## outgoing shooter's 4.0 m track bound on its 20.5 m by 5x.
func test_a_seat_change_does_not_drag_the_bodies_off_the_tower() -> void:
	assert_true(_human.is_shooter, "the human opens this test in the tower")

	# --- the human loses the seat to a runner ---
	var challenger: MatchParticipant = _controller.get_live_participants()[0]
	challenger.tracker.lap_finished.emit(12.0, 96.0)
	assert_same(_controller.get_seat_participant(), challenger, "the challenger took the tower")
	await step_ticks(SETTLE_TICKS)
	_assert_on_the_tower(challenger, "the incoming shooter")
	_assert_on_the_track(_human, "the outgoing shooter")

	# --- and takes it straight back, which is the same trap mirrored ---
	_human.tracker.lap_finished.emit(12.0, 96.0)
	assert_same(_controller.get_seat_participant(), _human, "the human took the tower back")
	await step_ticks(SETTLE_TICKS)
	_assert_on_the_tower(_human, "the returning shooter")
	_assert_on_the_track(challenger, "the shooter who lost the seat")

	# Nobody was left behind out at the wall. Every body in the match is either on
	# the tower, on the ring, or parked out of the world on purpose -- and none of
	# them is riding the outer wall at head height.
	for participant: MatchParticipant in _controller.get_participants():
		if not (participant.is_shooter or participant.is_running):
			continue
		assert_lt(
			participant.body.global_position.y, HEIGHT_TOLERANCE_METRES + _tower_spawn.y,
			"%s is standing on a surface, not climbing the wall" % participant.display_name,
		)


## The prisoners can see that the HUMAN is in the tower.
##
## [b]The bug this pins, in the author's words:[/b] [i]"the bots dont slide when
## im sniper."[/i] The slide was the symptom; the cause was the whole cover game.
##
## A prisoner finds the guard through [RunnerPerception], which used to look for
## one thing only: a [TowerShooter] node that was running. A human guard has no
## such node -- [method MatchController._arm_tower_brain] stands every brain down
## when the seat holder is the human -- so a human's round read to every bot on
## the ring as a round with nobody in the tower at all. They fell back to the
## baseline lap, which holds no cover, makes no crossings and therefore never
## slides, and they did it in front of a live rifle.
##
## So the match announces the SEAT rather than the brain -- see
## [constant MatchController.GUARD_GROUP] -- and this asserts the announcement
## and what the prisoners make of it. It is deliberately not a test about
## sliding: a slide is a decision several states downstream of this one, and it
## is pinned where it belongs, in [code]test_runner.gd[/code].
func test_the_prisoners_can_see_a_human_in_the_tower() -> void:
	assert_true(_human.is_shooter, "the human holds the seat for this test")
	assert_true(
		_human.body.is_in_group(MatchController.GUARD_GROUP),
		"the body in the tower is announced as the guard, human or not",
	)

	var runners: Array[RingRunner] = _controller.get_live_runners()
	assert_gt(runners.size(), 0, "there are prisoners on the ring to do the seeing")
	for index: int in runners.size():
		var perception: RunnerPerception = runners[index].get_perception()
		if not assert_true(perception.has_threat(), "runner %d knows there is a guard" % index):
			continue
		assert_same(
			perception.get_threat_body(), _human.body,
			"runner %d has found the human, not some other body" % index,
		)
		if runners[index].is_playing_cover():
			# RUNNING is the state a cover runner sits in while it believes the
			# ring has no guard. Leaving it is the whole behavioural consequence
			# of the fix, and every state the brain can be in instead -- RECOVER,
			# HOLD, EVALUATE, CROSS -- is the cover game being played.
			assert_false(
				runners[index].get_state() == RingRunner.State.RUNNING,
				"runner %d has stopped running the baseline lap and started playing the guard" % index,
			)


## And nobody is announced during the opening race, which has no shooter at all.
##
## The other half of [constant MatchController.GUARD_GROUP]: a group that named
## the last round's holder through a race would have the field hiding from an
## empty tower, and the race is the one part of the match that is meant to be a
## flat sprint.
func test_nobody_holds_the_tower_during_the_opening_race() -> void:
	_controller.start_race()
	await step_ticks(SETTLE_TICKS)

	assert_eq_int(
		int(_controller.get_phase()), int(MatchController.Phase.RACE), "the race is on",
	)
	for participant: MatchParticipant in _controller.get_participants():
		assert_false(
			participant.body.is_in_group(MatchController.GUARD_GROUP),
			"%s is not the guard during a race nobody is shooting in" % participant.display_name,
		)
	for runner: RingRunner in _controller.get_live_runners():
		assert_false(
			runner.get_perception().has_threat(),
			"a racer has nobody to hide from",
		)


# --- Helpers ------------------------------------------------------------------

## The tower is 8 m across and the deck starts at 36 m, so "on the tower" and "on
## the track" cannot be confused for one another however the fix is rewritten.
func _assert_on_the_tower(participant: MatchParticipant, who: String) -> void:
	var position: Vector3 = participant.body.global_position
	assert_lt(
		_horizontal_distance(position, _tower_spawn), SPAWN_TOLERANCE_METRES,
		"%s is standing on the tower spawn (at %v)" % [who, position],
	)
	assert_almost_eq(
		position.y, _tower_spawn.y, HEIGHT_TOLERANCE_METRES,
		"%s is at tower height" % who,
	)
	assert_true(participant.body.is_on_floor(), "%s is on the platform, not in the air" % who)


func _assert_on_the_track(participant: MatchParticipant, who: String) -> void:
	var position: Vector3 = participant.body.global_position
	var radius: float = _radius_of(position)
	assert_gt(radius, TOWER_PLATFORM_RADIUS, "%s is off the tower platform (at %v)" % [who, position])
	assert_between(radius, DECK_INNER_RADIUS, DECK_OUTER_RADIUS, "%s is out on the deck" % who)
	assert_almost_eq(
		radius, _controller.get_rules().track_radius, TRACK_TOLERANCE_METRES,
		"%s is on the track" % who,
	)
	# The route's own first gallery, not the marker cached at setup: the ring is
	# lifted so its top deck is level with the guard's eye, and "deck height" is
	# a number the map owns.
	#
	# The tolerance allows a JUMP APEX as well as a settle. A prisoner is a live
	# body with a brain that hops -- see RingRunner._maybe_jump -- and this
	# assertion is "on the deck, not on the tower and not down the pit", not
	# "both feet on the floor at the instant we happened to look".
	var route: RingRoute = _controller.get_route()
	var deck: float = _start_point.y if route == null else route.deck_height(0)
	assert_between(
		position.y,
		deck - HEIGHT_TOLERANCE_METRES,
		deck + HEIGHT_TOLERANCE_METRES + JUMP_APEX_METRES,
		"%s is at deck height" % who,
	)


## Hand the opening race to [param participant] through the tracker seam.
##
## The controller scores a race off [signal MatchLapTracker.lap_finished] and
## nothing else, so this is the same event a body finishing a lap produces --
## without spending the 35 simulated seconds of running that produce it.
func _win_the_race_for(participant: MatchParticipant) -> void:
	participant.tracker.lap_finished.emit(30.0, 240.0)


func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	_resolutions += 1
	_last_outcome = int(outcome)
	if _probe_armed:
		_probe_armed = false
		_probe_the_resolution_window()


## Fired from inside the resolution: the one frame in which the round is decided
## and has not yet been replaced. Every call here must be refused.
func _probe_the_resolution_window() -> void:
	for participant: MatchParticipant in _controller.get_live_participants():
		# A second and a third arrival, in the same frame as the first.
		participant.tracker.lap_finished.emit(12.5, 97.0)
		# And a shot that lands after the round is decided, which unguarded would
		# convert the ring and turn the lost seat into a won match.
		if _controller.convert_participant(participant):
			_probe_conversions_accepted += 1
		else:
			_probe_conversions_refused += 1
	_probe_resolve_count = _controller.get_resolve_count()


func _on_match_won(participant: MatchParticipant) -> void:
	_wins += 1
	_winner = participant


func _radius_of(point: Vector3) -> float:
	return Vector2(point.x - _centre.x, point.z - _centre.z).length()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)

