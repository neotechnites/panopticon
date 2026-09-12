extends TestCase

## Probe: the finisher's rifle draws a tracer when it fires.

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_rules.finisher_hunts_guard = true
	_controller.rules = _rules
	add_child(_match)


func after_each() -> void:
	_match.queue_free()


func test_finisher_rifle_draws_a_tracer() -> void:
	var participants: Array[MatchParticipant] = _controller.get_participants()
	participants[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(60)
	var finisher: MatchParticipant = _controller.get_live_participants()[0]
	finisher.tracker.lap_finished.emit(12.0, 96.0)
	await step_ticks(5)
	var weapon: Rifle = _controller.get_finisher_rifle()
	assert_not_null(weapon, "armed")
	var before: int = get_tree().root.find_children("*", "Tracer", true, false).size()
	weapon.tick(5.0)
	var fired: bool = weapon.try_fire()
	assert_true(fired, "try_fire fired (state %s)" % weapon.get_state_name())
	await step_ticks(1)
	var after: int = get_tree().root.find_children("*", "Tracer", true, false).size()
	assert_gt(after, before, "a tracer was spawned (before %d after %d, parent %s)" % [before, after, weapon.get_parent().name])
