extends TestCase

## The finisher: reaching the end arms a prisoner instead of ending the round.
##
## One test, and it is the whole mechanic end to end on the real
## [code]scenes/match/match.tscn[/code]: the portal stops being a win, the
## prisoner who reached it carries the guard's own rifle and
## [member MatchRules.finisher_health] hit points, the guard stands on
## [member MatchRules.guard_health], and the shot that kills the guard takes the
## tower exactly as the portal finish used to.

## Ticks to let the round the race arms settle before it is measured.
const SETTLE_TICKS: int = 60

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _participants: Array[MatchParticipant] = []

var _resolutions: int = 0
var _last_outcome: int = -1


func before_each() -> void:
	_match = TestFixtures.make_match()
	# Before the instance enters the tree: MatchController arms from _ready, and
	# the rule set it arms on has to be the one under test.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_rules.finisher_hunts_guard = true
	_controller.rules = _rules

	add_child(_match)
	_controller.round_resolved.connect(_on_round_resolved)
	_participants = _controller.get_participants()


func test_a_finisher_is_armed_and_takes_the_tower_by_killing_the_guard() -> void:
	# The race is unchanged: first past the post takes the tower.
	var guard: MatchParticipant = _participants[0]
	guard.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	assert_same(_controller.get_seat_participant(), guard, "the race winner holds the tower")
	assert_eq_int(guard.health, _rules.guard_health, "the guard stands on one hit point")

	var rounds_before: int = _controller.get_round_number()
	var finisher: MatchParticipant = _controller.get_live_participants()[0]
	finisher.tracker.lap_finished.emit(12.0, 96.0)

	# Read back in the same frame: the portal is no longer an ending.
	assert_eq_int(_resolutions, 0, "reaching the end resolves nothing")
	assert_eq_int(_controller.get_round_number(), rounds_before, "and restarts no round")
	assert_same(_controller.get_seat_participant(), guard, "the guard keeps the tower")

	assert_true(finisher.is_finisher, "the finisher is armed")
	assert_true(finisher.is_running, "and is still a prisoner the guard may shoot")
	assert_eq_int(finisher.health, _rules.finisher_health, "with ten hit points")
	var weapon: Rifle = _controller.get_finisher_rifle()
	assert_not_null(weapon, "the finisher was handed a rifle")
	assert_same(weapon.get_parent(), finisher.body.head, "on the finisher's own head")
	assert_same(weapon.shooter_body, finisher.body, "excluding its holder from its own shot")

	# And is standing in the tower room rather than back at the portal.
	var spawn: Marker3D = _controller.arena.get_node(_controller.spawn_marker_path) as Marker3D
	assert_lt(
		finisher.body.global_position.distance_to(spawn.global_position),
		4.0,
		"the armed finisher is put by the guard's own spawn point"
	)

	# The guard's shots come off the hit points one at a time, and the ghost
	# path is not reached until they are gone.
	for shot: int in _rules.finisher_health - 1:
		assert_false(_controller.apply_hit(finisher), "hit %d does not finish the finisher" % shot)
	assert_true(finisher.is_running, "nine hits leave the finisher in the round")
	assert_eq_int(finisher.health, 1, "with one hit point left")

	# And the finisher's one shot kills the guard.
	assert_true(_controller.apply_guard_hit(guard), "one shot at guard_health 1 is a kill")

	# The kill is given time to land before the seat changes hands: the guard is
	# dead and frozen, the round is still running. See MatchRules.kill_beat_seconds.
	assert_gt(_rules.kill_beat_seconds, 0.0, "the rules hold the kill for a beat")
	assert_eq_int(_resolutions, 0, "nothing resolves on the tick of the kill")
	assert_true(guard.body.movement_locked, "the dead guard stands still where it fell")
	assert_true(finisher.body.movement_locked, "and so does the finisher, watching it")
	await step_seconds(_rules.kill_beat_seconds + 0.2)

	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "the round is lost from the tower")
	assert_eq_int(_resolutions, 1, "resolved exactly once")
	assert_same(_controller.get_seat_participant(), finisher, "the finisher takes the tower")
	assert_true(finisher.is_shooter, "as the shooter")
	assert_false(finisher.is_finisher, "and is no longer hunting")
	assert_eq_int(_controller.get_round_number(), rounds_before + 1, "a new round is armed")


func _on_round_resolved(outcome: int) -> void:
	_resolutions += 1
	_last_outcome = outcome
