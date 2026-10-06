extends TestCase

## Hell's lava kills a runner who touches it, hopping or not: the S2 and S4 rivers,
## the S5 lake and the sea under the tower, in the real match on the shipped map.

const SETTLE_TICKS: int = 60

## A second and a half: ten grace periods, and two full bunny hops.
const CATCH_TICKS: int = 90

## Where the sea is touched: inside the pit, over the lava at y -11.05.
const SEA_POINT: Vector3 = Vector3(30.0, -10.5, 0.0)

var _match: Node3D
var _arena: Node3D
var _controller: MatchController


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = TestFixtures.match_rules()
	add_child(_match)
	_arena = _match.get_node("Arena") as Node3D
	# The human takes the tower, so the round is on and the bots are prisoners.
	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


func test_hopping_on_the_s2_river_kills() -> void:
	await _assert_hopping_dies_on(^"Sections/S2_LavaShelf/TrapVolume4")


func test_hopping_on_the_s4_river_kills() -> void:
	await _assert_hopping_dies_on(^"Sections/S4_DemonRun/TrapVolume5")


func test_hopping_on_the_s5_lake_kills() -> void:
	await _assert_hopping_dies_on(^"Sections/S5_WallRun/TrapVolume3")


func test_touching_the_sea_kills() -> void:
	var victim: MatchParticipant = _hopping_victim(SEA_POINT)
	assert_true(await _caught(victim), "a prisoner on the sea dies")


## Drop a bunny-hopping prisoner onto the lava under [param trap_path] and expect a death.
func _assert_hopping_dies_on(trap_path: NodePath) -> void:
	var trap: TrapVolume = _arena.get_node_or_null(trap_path) as TrapVolume
	if not assert_not_null(trap, "%s is on the map" % trap_path):
		return
	var victim: MatchParticipant = _hopping_victim(trap.global_position + Vector3.UP * 0.3)
	assert_true(await _caught(victim), "a prisoner hopping on %s dies" % trap_path)


## A live prisoner, its brain stood down, held jump and forward, placed at [param at].
func _hopping_victim(at: Vector3) -> MatchParticipant:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	TestFixtures.pin_the_field(_controller, victim)
	victim.brain.set_physics_process(false)
	var command: MoveIntent = victim.brain.input.command
	command.clear()
	command.move_direction = Vector2(0.0, 1.0)
	command.jump_held = true
	command.jump_pressed = true
	victim.body.velocity = Vector3.ZERO
	victim.body.global_position = at
	return victim


func _caught(victim: MatchParticipant) -> bool:
	for _tick: int in CATCH_TICKS:
		if _controller.is_awaiting_respawn(victim) or not victim.is_running:
			return true
		await step_ticks(1)
	return false
