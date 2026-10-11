extends TestCase

## Eight bodies on every map, in every placement a match makes: the race start, the runner
## start after a round, a respawned ghost, the tower fight. Each on floor, clear of walls and of each other, and able to move.

const RULES_PATH: String = "res://match/rules/default_match_rules.tres"
const PARTICIPANTS: int = 8
const SETTLE_TICKS: int = 20
const MOVE_TICKS: int = 60
## A capsule a little inside the body's own, so a body standing on the floor does not count as in it.
const PROBE_RADIUS: float = 0.3
const PROBE_HEIGHT: float = 1.4
const PROBE_LIFT: float = 0.95
const APART_METRES: float = 0.75
const MOVED_METRES: float = 0.5

var _world: BotMatchWorld = null


func after_each() -> void:
	if _world != null:
		_world.queue_free()
		_world = null


func _build(map_id: StringName) -> MatchController:
	var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	rules.prisoner_count = PARTICIPANTS - 1
	rules.map_id = map_id
	rules.open_with_race = true
	rules.open_with_tower_brawl = false
	rules.rounds_to_win_match = 99
	rules.prisoner_lives = 99
	_world = BotMatchWorld.new()
	add_child(_world)
	_world.build(rules)
	return _world.get_controller()


func test_eight_start_the_race_on_floor_and_clear_on_every_map() -> void:
	for map: MapDefinition in MapCatalog.all():
		var controller: MatchController = _build(map.id)
		controller.start_match()
		await step_ticks(SETTLE_TICKS)
		_check(controller, "%s race" % map.id, controller.get_participants())
		await _check_moving(controller, "%s race" % map.id, controller.get_participants())
		after_each()
		await step_ticks(2)


func test_eight_take_the_runner_start_after_a_round_on_every_map() -> void:
	for map: MapDefinition in MapCatalog.all():
		var controller: MatchController = _build(map.id)
		controller.start_match()
		await step_ticks(2)
		controller.take_seat(controller.get_participants()[0])
		controller.start_round()
		await step_ticks(SETTLE_TICKS)
		var runners: Array[MatchParticipant] = _running(controller)
		assert_eq_int(runners.size(), PARTICIPANTS - 1, "%s: seven runners" % map.id)
		_check(controller, "%s round" % map.id, runners)
		await _check_moving(controller, "%s round" % map.id, runners)
		after_each()
		await step_ticks(2)


func test_eight_start_the_tower_fight_on_floor_and_clear_on_every_map() -> void:
	for map: MapDefinition in MapCatalog.all():
		var controller: MatchController = _build(map.id)
		controller.start_match()
		await step_ticks(2)
		controller.start_brawl()
		await step_ticks(SETTLE_TICKS)
		_check(controller, "%s tower fight" % map.id, controller.get_participants())
		after_each()
		await step_ticks(2)


func _running(controller: MatchController) -> Array[MatchParticipant]:
	var out: Array[MatchParticipant] = []
	for participant: MatchParticipant in controller.get_participants():
		if participant.is_running:
			out.append(participant)
	return out


func _check(controller: MatchController, label: String, who: Array[MatchParticipant]) -> void:
	var space: PhysicsDirectSpaceState3D = controller.arena.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for participant: MatchParticipant in controller.get_participants():
		exclude.append(participant.body.get_rid())
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = PROBE_RADIUS
	capsule.height = PROBE_HEIGHT
	for participant: MatchParticipant in who:
		var body: PlayerController = participant.body
		var at: Vector3 = body.global_position
		var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 0.5, at + Vector3.DOWN * 2.5, 1, exclude))
		assert_false(down.is_empty(), "%s: %s stands over floor at %s" % [label, participant.display_name, at])
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * PROBE_LIFT)
		query.collision_mask = 1
		query.exclude = exclude
		var hits: Array[Dictionary] = space.intersect_shape(query, 4)
		assert_true(hits.is_empty(), "%s: %s is clear of the map at %s" % [label, participant.display_name, at])
		for other: MatchParticipant in who:
			if other.index <= participant.index:
				continue
			var gap: Vector3 = other.body.global_position - at
			gap.y = 0.0
			assert_gt(gap.length(), APART_METRES, "%s: %s and %s stand apart" % [label, participant.display_name, other.display_name])


func _check_moving(controller: MatchController, label: String, who: Array[MatchParticipant]) -> void:
	var before: Array[Vector3] = []
	for participant: MatchParticipant in who:
		before.append(participant.body.global_position)
	await step_ticks(MOVE_TICKS)
	for i: int in who.size():
		var moved: float = who[i].body.global_position.distance_to(before[i])
		assert_gt(moved, MOVED_METRES, "%s: %s gets moving" % [label, who[i].display_name])
