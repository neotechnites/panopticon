extends TestCase

## The tower fight between bots ends: two bots that line up on each other on the
## same tick must not trade shoves for ever.

const SEED: int = 20261117
## Long enough for dozens of exchanges; a fight still going is not going to end.
const FIGHT_SECONDS: float = 150.0
const APART_METRES: float = 2.0

var _steps_before: int = 0


func before_each() -> void:
	_steps_before = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 64


func after_each() -> void:
	Engine.max_physics_steps_per_frame = _steps_before


func test_two_bots_mirrored_across_the_room_still_finish_the_fight() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	rules.map_id = &"marble"
	rules.prisoner_count = 1
	rules.open_with_tower_brawl = true
	var world: BotMatchWorld = BotMatchWorld.new()
	add_child(world)
	world.build(rules, SEED)
	var controller: MatchController = world.get_controller()
	controller.start_match()
	BotMatchWorld.silence_local_input(world.get_runner_container())
	await step_ticks(MatchController.SETTLE_PHYSICS_FRAMES + 2)
	if not assert_eq_string(controller.get_phase_name(), "BRAWL", "the match opens with the tower fight"):
		world.free()
		return
	var participants: Array[MatchParticipant] = controller.get_participants()
	if not assert_eq_int(participants.size(), 2, "two bots are in it"):
		world.free()
		return
	# The livelock's own state: past the staggered start, mirrored about the room's
	# centre, each facing the other.
	var centre: Vector3 = participants[0].body.global_position.lerp(participants[1].body.global_position, 0.5)
	for index: int in 2:
		var body: PlayerController = participants[index].body
		var side: float = 1.0 if index == 0 else -1.0
		body.global_position = Vector3(centre.x + side * APART_METRES * 0.5, body.global_position.y, centre.z)
		body.velocity = Vector3.ZERO
		body.rotation = Vector3(0.0, side * PI * 0.5, 0.0)
	controller._brawl_elapsed = 10.0
	controller._brawl_bots.clear()
	var waited: float = 0.0
	while waited < FIGHT_SECONDS and controller.get_phase_name() == "BRAWL":
		await step_seconds(1.0)
		waited += 1.0
	assert_true(controller.get_phase_name() != "BRAWL", "the fight ended inside %d s" % int(FIGHT_SECONDS))
	world.free()
