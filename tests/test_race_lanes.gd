extends TestCase

## Where the opening race starts, where it finishes, and why those are not the
## same question.
##
## [b]The defect underneath all of this[/b]
##
## The ring is concentric lanes, so an outer lane is physically longer. Started
## and finished on one line, the inside lane wins every opening race regardless
## of play -- measured, and recorded in the pod as
## [code]panopticon.finding.race_decided_by_lane[/code]. Equal metres is
## therefore not negotiable. WHERE the metres are equalised is
## [enum MatchRules.LaneEqualisation], and it has exactly two honest answers:
## move the starts, or move the finishes.
##
## [constant MatchRules.LaneEqualisation.STAGGER_START] moved the starts, which
## is correct and which a player standing on the start line reads as a broken
## start line -- nobody is alongside them. The shipped answer is now
## [constant MatchRules.LaneEqualisation.STAGGER_FINISH]: one common start line,
## and each lane's finish moved to the angle that makes that lane's ARC LENGTH
## equal to every other lane's.
##
## [b]What is asserted here, and what is not[/b]
##
## Geometry, at placement, in a headless world with no rendering and no laps:
## every racer's start angle, every racer's finish angle, and the metres between
## them at that racer's radius. That is the whole of the fairness claim as a
## PROPERTY, and it is checked to float tolerance rather than to a lap time
## because a lap time is a measurement of the physics solver and this is a
## measurement of the rule.
##
## That the property holds in a running match is a separate question and is
## answered by the harness, not here -- see the sweep in
## [code]tools/_scratch/[/code] and the note in [MatchRules.lane_equalisation].
## A test suite that ran 200 races to prove a division would cost more CI than
## the whole rest of the suite put together.
##
## [b]Why [BotMatchWorld] rather than the match scene[/b]
##
## Every test in this file varies the rules, and
## [code]scenes/match/match.tscn[/code] names the shipped
## [code].tres[/code] -- one shared instance for the process, which a test must
## never retune. [BotMatchWorld] is the harness's own composition of the same
## parts around rules it is handed, with no human body in it, which is exactly
## what a geometry test wants.

## Tolerance on a lane length, in metres. The lengths are a product of a float
## radius and a float arc computed two different ways; this is float noise on a
## ~235 m number and nothing else.
const LENGTH_EPSILON_METRES: float = 0.05

## Tolerance on an angle, in radians. About 0.006 degrees.
const ANGLE_EPSILON_RADIANS: float = 1e-4

## Metres the shipped race gives every racer under either stagger: a full lap of
## the innermost lane. Restated as a number so that a change to the ring's
## markers or to [member MatchRules.lane_radii] shows up here as a failure to
## look at rather than as a test that quietly agrees with whatever it is given.
const SHIPPED_EQUALISED_LENGTH_METRES: float = 235.43

var _world: BotMatchWorld = null
var _controller: MatchController = null
var _rules: MatchRules = null
var _centre: Vector3 = Vector3.ZERO


func before_each() -> void:
	# A private copy: the ghost tests in this suite prove what happens when one
	# is not taken.
	_rules = TestFixtures.match_rules()


func after_each() -> void:
	_world = null
	_controller = null


# --- The start line -----------------------------------------------------------

## Everybody starts on the same line. The defect Ryan reported, as an assertion.
##
## Same ANGLE, not same position: the racers are on different lanes and a lane is
## a radius, so a common start line is a radial line out from the arena axis and
## the bodies stand along it. That is what "alongside" means on a ring, and it is
## what the eye reads as a start line.
func test_every_racer_starts_on_the_common_start_line() -> void:
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	var racers: Array[MatchParticipant] = _controller.get_participants()
	assert_eq_int(racers.size(), _rules.get_participant_count(), "the whole field is racing")

	var line: float = _angle_of(racers[0].body.global_position)
	for index: int in racers.size():
		assert_almost_eq(
			_angle_delta(_angle_of(racers[index].body.global_position), line),
			0.0,
			ANGLE_EPSILON_RADIANS,
			"racer %d starts on the same line as racer 0" % index,
		)


## And the line is the arena's own start marker, not merely a line they agree on.
##
## Without this, a bug that put the whole field on one arbitrary angle would pass
## the test above. The start pad is where a player expects to be standing.
func test_the_common_start_line_is_the_start_marker() -> void:
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	var marker: float = _angle_of(_start_marker_position())
	for participant: MatchParticipant in _controller.get_participants():
		assert_almost_eq(
			_angle_delta(_angle_of(participant.body.global_position), marker),
			0.0,
			ANGLE_EPSILON_RADIANS,
			"racer %d starts on the PrisonerStart marker's line" % participant.index,
		)


# --- Equal metres -------------------------------------------------------------

## The fairness claim itself: every lane is the same number of metres.
##
## Measured as the arc each racer must sweep multiplied by the radius they sweep
## it at, which is the definition of the distance owed. The two ends come from
## the two places the match itself reads them: the body's placed position, and
## [member MatchParticipant.lane_end_point], which is the same point
## [MatchLapTracker] scores against and the same point [RingRunner] steers at.
func test_stagger_finish_gives_every_lane_the_same_length() -> void:
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	var lengths: PackedFloat32Array = _lane_lengths()
	assert_gt(float(lengths.size()), 1.0, "there is more than one lane to compare")
	for index: int in lengths.size():
		assert_almost_eq(
			lengths[index],
			lengths[0],
			LENGTH_EPSILON_METRES,
			"lane %d owes the same metres as lane 0" % index,
		)
		assert_almost_eq(
			lengths[index],
			SHIPPED_EQUALISED_LENGTH_METRES,
			0.5,
			"lane %d owes the shipped race's distance" % index,
		)


## The finishes really do move, and they move OUTWARD-EARLIER rather than at
## random.
##
## An implementation that equalised the lengths by leaving every finish on the
## end marker and quietly shortening the arc would pass the length test and be
## nonsense. A longer lane must sweep less angle for the same metres, so the
## finish angles must be ordered against the radii.
func test_stagger_finish_moves_each_finish_and_leaves_the_starts_alone() -> void:
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	var racers: Array[MatchParticipant] = _controller.get_participants()
	var marker_end: float = _angle_of(_end_marker_position())
	var previous_arc: float = TAU
	for participant: MatchParticipant in racers:
		var arc: float = _swept_arc(participant)
		assert_lt(
			arc,
			previous_arc + ANGLE_EPSILON_RADIANS,
			"lane %d (r=%.1f) sweeps no more angle than the lane inside it" % [
				participant.index, participant.lane_radius,
			],
		)
		previous_arc = arc

	# The innermost lane is the reference, so its finish is still the marker and
	# the human -- who holds seat zero and therefore lane zero -- runs exactly
	# the race they always did.
	assert_almost_eq(
		_angle_delta(_angle_of(racers[0].lane_end_point), marker_end),
		0.0,
		ANGLE_EPSILON_RADIANS,
		"the innermost lane still finishes at the end marker",
	)
	# And every other lane does not.
	for index: int in range(1, racers.size()):
		assert_gt(
			absf(_angle_delta(_angle_of(racers[index].lane_end_point), marker_end)),
			ANGLE_EPSILON_RADIANS,
			"lane %d finishes somewhere other than the end marker" % index,
		)


## The tracker is scoring the line the lane actually finishes at.
##
## This is the honesty of the arrival test, and it is the thing most likely to
## rot: the finish used to be one world point on the controller, and a per-lane
## finish that reached the brain but not the tracker would look right, run right,
## and score the outer lanes against a line 60 m past where they stop.
func test_the_tracker_is_armed_with_the_lane_it_will_be_scored_on() -> void:
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	for participant: MatchParticipant in _controller.get_participants():
		var tracked_arc: float = participant.tracker.get_finish_arc()
		assert_almost_eq(
			tracked_arc,
			_swept_arc(participant),
			ANGLE_EPSILON_RADIANS,
			"lane %d is scored against its own finish" % participant.index,
		)
		assert_almost_eq(
			tracked_arc * participant.lane_radius,
			SHIPPED_EQUALISED_LENGTH_METRES,
			0.5,
			"lane %d is scored over the equalised distance" % participant.index,
		)


# --- The modes it is not ------------------------------------------------------

## The old rule still works, because it is evidence.
##
## [constant MatchRules.LaneEqualisation.STAGGER_START] is what every number this
## project measured before the switch existed was measured under. It is kept, it
## is selectable, and it still equalises: same metres, staggered starts, one
## shared finish. Deleting it would put those measurements beyond reproduction.
func test_stagger_start_still_staggers_the_starts_and_still_equalises() -> void:
	await _race_under(MatchRules.LaneEqualisation.STAGGER_START)

	var lengths: PackedFloat32Array = _lane_lengths()
	for index: int in lengths.size():
		assert_almost_eq(
			lengths[index], lengths[0], LENGTH_EPSILON_METRES,
			"lane %d owes the same metres as lane 0 under STAGGER_START" % index,
		)

	var racers: Array[MatchParticipant] = _controller.get_participants()
	var end_angle: float = _angle_of(_end_marker_position())
	var start_line: float = _angle_of(racers[0].body.global_position)
	for participant: MatchParticipant in racers:
		assert_almost_eq(
			_angle_delta(_angle_of(participant.lane_end_point), end_angle),
			0.0,
			ANGLE_EPSILON_RADIANS,
			"lane %d still finishes at the end marker under STAGGER_START" % participant.index,
		)
	for index: int in range(1, racers.size()):
		assert_gt(
			absf(_angle_delta(_angle_of(racers[index].body.global_position), start_line)),
			ANGLE_EPSILON_RADIANS,
			"lane %d starts somewhere other than the start line under STAGGER_START" % index,
		)


## Off is off: the finding is reproducible.
##
## Under [constant MatchRules.LaneEqualisation.NONE] every racer starts and
## finishes on the markers and the lengths differ by the radii, which IS
## [code]panopticon.finding.race_decided_by_lane[/code]. A control case that
## cannot be reproduced is not a control case.
func test_no_equalisation_leaves_the_lanes_unequal() -> void:
	await _race_under(MatchRules.LaneEqualisation.NONE)

	var lengths: PackedFloat32Array = _lane_lengths()
	for index: int in range(1, lengths.size()):
		assert_gt(
			lengths[index],
			lengths[index - 1] + 1.0,
			"lane %d is longer than the lane inside it when nothing is equalised" % index,
		)


## The master switch still switches. A rule set that turned equalising off before
## this enum existed must still get no equalising.
func test_the_master_switch_overrides_the_mode() -> void:
	_rules.equalise_race_lane_distance = false
	_rules.lane_equalisation = MatchRules.LaneEqualisation.STAGGER_FINISH
	assert_eq_int(
		int(_rules.get_lane_equalisation()),
		int(MatchRules.LaneEqualisation.NONE),
		"equalise_race_lane_distance = false means NONE whatever the mode says",
	)

	await _race()
	var lengths: PackedFloat32Array = _lane_lengths()
	assert_gt(
		lengths[lengths.size() - 1],
		lengths[0] + 1.0,
		"the lanes are unequal when the master switch is off",
	)


## The default the game ships is the new one. Stated as an assertion because it
## is a decision, and a decision that lives only in a default is a decision one
## careless edit away from being reversed silently.
func test_the_shipped_default_is_stagger_finish() -> void:
	var shipped: MatchRules = TestFixtures.match_rules()
	assert_true(shipped.equalise_race_lane_distance, "the shipped rules equalise")
	assert_eq_int(
		int(shipped.get_lane_equalisation()),
		int(MatchRules.LaneEqualisation.STAGGER_FINISH),
		"the shipped rules stagger the finish",
	)


# --- The dead heat equalisation creates ---------------------------------------

## Equal lanes mean dead heats, and [enum MatchRules.ArrivalTiebreak] is what
## settles them. It still does.
##
## The tiebreak is implemented as the physics priority of the trackers, because
## an arrival is resolved on the tick it happens and the first tracker processed
## takes the seat. So the assertion is on the priorities: seat order gives them
## out in participant order, which is the unstated behaviour the match always
## had, and every racer must get a distinct one or two of them are back to being
## settled by whatever order the tree happens to hold them in.
func test_seat_order_still_settles_a_dead_heat() -> void:
	_rules.arrival_tiebreak = MatchRules.ArrivalTiebreak.SEAT_ORDER
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	var racers: Array[MatchParticipant] = _controller.get_participants()
	for index: int in racers.size():
		assert_eq_int(
			racers[index].tracker.process_physics_priority,
			MatchController.TRACKER_PRIORITY_BASE + index,
			"racer %d is scored in seat order" % index,
		)


## The lot spreads the seat instead, and it is a permutation rather than a
## reshuffle that can drop or double a racer.
func test_the_lot_is_a_permutation_of_the_field() -> void:
	_rules.arrival_tiebreak = MatchRules.ArrivalTiebreak.DRAW_LOT
	_rules.arrival_tiebreak_seed = 20260910
	await _race_under(MatchRules.LaneEqualisation.STAGGER_FINISH)

	var racers: Array[MatchParticipant] = _controller.get_participants()
	var seen: Dictionary[int, bool] = {}
	for participant: MatchParticipant in racers:
		var rank: int = (
			participant.tracker.process_physics_priority - MatchController.TRACKER_PRIORITY_BASE
		)
		assert_between(float(rank), 0.0, float(racers.size() - 1), "the lot gives a rank in range")
		assert_false(seen.has(rank), "no two racers are given rank %d" % rank)
		seen[rank] = true
	assert_eq_int(seen.size(), racers.size(), "every racer is given a rank")


# --- Fixture ------------------------------------------------------------------

## Build a headless world on [member _rules] and run the opening race's
## placement, then stop before anybody has moved.
##
## The wait is one physics frame, which is what puts the bodies where the
## placement put them; nothing here needs a lap, and a settled body is a worse
## measurement of a start line than a placed one.
func _race() -> void:
	_world = BotMatchWorld.new()
	add_child(_world)
	_world.build(_rules)
	_controller = _world.get_controller()
	_centre = (_world.get_node(^"Arena") as Node3D).global_position
	_controller.start_match()
	await step_ticks(1)
	# Nothing in this file measures running, and a world left ticking would go on
	# walking bodies through the next test's frames.
	for participant: MatchParticipant in _controller.get_participants():
		if participant.brain != null:
			participant.brain.set_physics_process(false)
		if participant.body != null:
			participant.body.set_physics_process(false)
			participant.body.velocity = Vector3.ZERO


func _race_under(mode: MatchRules.LaneEqualisation) -> void:
	_rules.equalise_race_lane_distance = mode != MatchRules.LaneEqualisation.NONE
	_rules.lane_equalisation = mode
	await _race()


## Metres of lane each racer owes, in participant order.
func _lane_lengths() -> PackedFloat32Array:
	var lengths: PackedFloat32Array = PackedFloat32Array()
	for participant: MatchParticipant in _controller.get_participants():
		lengths.append(_swept_arc(participant) * participant.lane_radius)
	return lengths


## Radians this racer must sweep: from where they were placed to where their lane
## finishes, in the direction of travel.
func _swept_arc(participant: MatchParticipant) -> float:
	return wrapf(
		(_angle_of(participant.lane_end_point) - _angle_of(participant.body.global_position))
		* RingRunner.TRAVEL_SIGN,
		0.0,
		TAU,
	)


func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


## Signed shortest difference between two angles, so a pair straddling the
## +/-PI seam does not read as a whole turn apart.
func _angle_delta(from: float, to: float) -> float:
	return wrapf(from - to, -PI, PI)


func _start_marker_position() -> Vector3:
	return _marker(TestFixtures.START_MARKER_PATH)


func _end_marker_position() -> Vector3:
	return _marker(TestFixtures.END_MARKER_PATH)


func _marker(path: NodePath) -> Vector3:
	var arena: Node3D = _world.get_node(^"Arena") as Node3D
	return (arena.get_node(path) as Marker3D).global_position
