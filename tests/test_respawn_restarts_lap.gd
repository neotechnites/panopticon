extends TestCase

## A prisoner with a life to spare is put back on the start line, and the lap
## starts again with them: the tracker at zero, the bot's brain on a fresh run.

const SEED: int = 20261117
const SETTLE_TICKS: int = 30
## How far into the lap the prisoner is shot, degrees: past the half turn, where
## the move back to the line wraps the wrong way round.
const SHOT_AT_DEGREES: float = 250.0

var _world: BotMatchWorld = null
var _controller: MatchController = null


func before_each() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	rules.prisoner_lives = 2
	rules.open_with_race = false
	_world = BotMatchWorld.new()
	add_child(_world)
	_world.build(rules, SEED)
	_controller = _world.get_controller()
	_controller.start_match()
	BotMatchWorld.silence_local_input(_world.get_runner_container())
	await step_ticks(SETTLE_TICKS)


func after_each() -> void:
	_world.free()


func test_a_spent_life_restarts_the_lap_count() -> void:
	var victim: MatchParticipant = _runner()
	if not assert_not_null(victim, "a bot is running the round"):
		return
	_put_into_the_lap(victim)
	await step_ticks(2)
	victim.tracker._travelled_arc = deg_to_rad(SHOT_AT_DEGREES)
	assert_false(_controller.apply_hit(victim), "a prisoner with a life left is not converted")
	await step_ticks(SETTLE_TICKS)
	assert_lt(victim.tracker.get_progress(), 0.1, "back on the line, the lap is counted from the line")
	assert_false(victim.tracker.has_finished(), "and nothing has been finished")


func test_a_spent_life_puts_a_bot_brain_back_on_a_fresh_run() -> void:
	var victim: MatchParticipant = _runner()
	if not assert_not_null(victim, "a bot is running the round") or not assert_not_null(victim.brain, "with a brain"):
		return
	var bake: RingBake = victim.brain.get_navigation()
	if not assert_true(bake != null and bake.get_link_count() > 0, "the map has a link to cross"):
		return
	_put_into_the_lap(victim)
	await step_ticks(2)
	victim.brain._begin_cross(bake.get_link(0), RunnerBrain.Cross.TAKEOFF)
	assert_false(_controller.apply_hit(victim), "a prisoner with a life left is not converted")
	await step_ticks(SETTLE_TICKS)
	assert_eq_string(victim.brain.get_state_name(), "RUN", "the brain is running, not finishing a crossing it was shot out of")
	assert_lt(absf(victim.brain.get_travelled_arc()), 0.2, "and it counts its lap from the line")
	assert_true(victim.is_running, "the prisoner is still in the round")


func _runner() -> MatchParticipant:
	for participant: MatchParticipant in _controller.get_participants():
		if participant.is_running and not participant.is_shooter:
			return participant
	return null


## Stand [param victim] on the lane [constant SHOT_AT_DEGREES] round from the start.
func _put_into_the_lap(victim: MatchParticipant) -> void:
	var route: RingRoute = _controller.get_route()
	var centre: Vector3 = _controller.arena.global_position
	var here: Vector3 = victim.body.global_position
	var angle: float = atan2(here.z - centre.z, here.x - centre.x) + deg_to_rad(SHOT_AT_DEGREES) * RingRoute.TRAVEL_SIGN
	var bake: RingBake = victim.brain.get_navigation() if victim.brain != null else null
	var point: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * route.lane_radius(0)
	point.y = here.y
	if bake != null and bake.is_ready():
		point = bake.snap(point) + Vector3.UP * 0.1
	victim.body.global_position = point
	victim.body.velocity = Vector3.ZERO
