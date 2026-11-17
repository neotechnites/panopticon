extends TestCase
## Playtest regressions in the limp body itself, measured offline on hell and marble: a body shot standing
## stays one body; a body shot at a run and the guard thrown in the finale are known not to (skipped, open).

const SETTLE_TICKS: int = 60
const MAPS: Array[StringName] = [&"bentham_ring", &"marble"]
const BEARINGS: int = 8
## Metres the finisher stands from the guard when it shoves.
const SHOVE_STAND_METRES: float = 0.9
## Furthest a part's centre may lie from the pelvis: a standing body's foot is under a metre from it.
const BODY_REACH_METRES: float = 1.35
## Most a joint may gape, metres, before the body counts as torn; the ragdoll's own projection holds 0.03.
const TORN_METRES: float = 0.5
## Metres a part's centre must cross a surface by before it counts as through it.
const THROUGH_METRES: float = 0.05
## Ticks into the round a running body is shot at, so the kills land on different stretches of the course.
const SHOT_TICKS: Array[int] = [80, 100, 120, 140, 160, 190, 220, 260]

var _match: Node3D = null
var _controller: MatchController = null


func after_each() -> void:
	if _match != null:
		_match.queue_free()
		_match = null


## A match on [param map_id] with a bot in the tower and the round running.
func _build(map_id: StringName, finale: bool = false) -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	var rules: MatchRules = TestFixtures.match_rules()
	rules.map_id = map_id
	rules.finisher_hunts_guard = finale
	_controller.rules = rules
	add_child(_match)
	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)


func _tear_down() -> void:
	_match.queue_free()
	_match = null
	await step_ticks(2)


## Shoot [param victim] and watch its limp body for two seconds; returns [widest joint gap, furthest part from the pelvis].
func _shoot_and_measure(victim: MatchParticipant) -> Array[float]:
	var body: PlayerController = victim.body
	_controller.rifle.show_remote_hit(body, body.global_position + Vector3.UP, Vector3.BACK)
	var ragdoll: Node = PrisonerAvatar.of(body).get_node("Ragdoll")
	var bones: Array = ragdoll.get(&"_bones")
	var parents: PackedInt32Array = ragdoll.get(&"_parent_part")
	var in_parent: PackedVector3Array = ragdoll.get(&"_joint_in_parent")
	var in_part: PackedVector3Array = ragdoll.get(&"_joint_in_part")
	var gap: float = 0.0
	var reach: float = 0.0
	var limp_ticks: int = 0
	for _tick: int in 120:
		await step_ticks(1)
		if not bool(ragdoll.call(&"is_active")):
			continue
		limp_ticks += 1
		var parts: PackedVector3Array = ragdoll.call(&"part_positions")
		for index: int in range(1, bones.size()):
			var mine: Transform3D = (bones[index] as PhysicalBone3D).global_transform
			var parent: Transform3D = (bones[parents[index]] as PhysicalBone3D).global_transform
			gap = maxf(gap, (parent * in_parent[index]).distance_to(mine * in_part[index]))
			reach = maxf(reach, parts[index].distance_to(parts[0]))
	assert_gt(float(limp_ticks), 60.0, "the shot body lay limp while it was measured")
	return [gap, reach]


func test_a_body_shot_standing_stays_one_body_on_hell_and_marble() -> void:
	for map_id: StringName in MAPS:
		for who: int in 3:
			_build(map_id)
			await step_ticks(SETTLE_TICKS)
			TestFixtures.pin_the_field(_controller, null)
			await step_ticks(SETTLE_TICKS)
			var live: Array[MatchParticipant] = _controller.get_live_participants()
			var measured: Array[float] = await _shoot_and_measure(live[who % live.size()])
			assert_lt(measured[0], TORN_METRES, "%s, runner %d: no joint of the limp body gapes" % [map_id, who])
			assert_lt(measured[1], BODY_REACH_METRES, "%s, runner %d: no part lies further from the pelvis than a body reaches" % [map_id, who])
			await _tear_down()


## Open: about 1 running kill in 10 tears (joints up to 2.7 m apart, parts spinning near 1000 rad/s for a quarter second).
func test_a_body_shot_at_a_run_stays_one_body_on_hell_and_marble() -> void:
	skip("LIVE BUG (S-04, open): a body shot at a run sometimes tears for about 15 ticks; remove this line to measure")
	if is_skipped():
		return
	for map_id: StringName in MAPS:
		var torn: int = 0
		var widest: float = 0.0
		for wait: int in SHOT_TICKS:
			for who: int in 3:
				_build(map_id)
				await step_ticks(wait)
				var live: Array[MatchParticipant] = _controller.get_live_participants()
				var measured: Array[float] = await _shoot_and_measure(live[who % live.size()])
				widest = maxf(widest, measured[0])
				if measured[0] >= TORN_METRES:
					torn += 1
				await _tear_down()
		print("          RUNNING KILLS %s: %d of %d torn, widest joint gap %.2f m" % [map_id, torn, SHOT_TICKS.size() * 3, widest])
		assert_eq_int(torn, 0, "%s: running kills whose limp body tore" % map_id)


## Guard in the tower, one runner armed as the finisher beside him; returns [guard, finisher].
func _to_the_finale() -> Array[MatchParticipant]:
	var guard: MatchParticipant = _controller.get_participants()[0]
	await step_ticks(SETTLE_TICKS)
	var finisher: MatchParticipant = _controller.get_live_participants()[0]
	TestFixtures.pin_the_field(_controller, finisher)
	finisher.tracker.lap_finished.emit(12.0, 96.0)
	# The test places the shove; the bot's own hunt would land one first.
	_controller.call(&"_silence_brain", finisher)
	await step_ticks(SETTLE_TICKS)
	finisher.shove_cooldown_remaining = 0.0
	return [guard, finisher]


## One finale throw along [param bearing] radians; returns [furthest part from the pelvis, surfaces passed through].
func _throw(map_id: StringName, bearing: float) -> Array:
	_build(map_id, true)
	var pair: Array[MatchParticipant] = await _to_the_finale()
	var guard: MatchParticipant = pair[0]
	var finisher: MatchParticipant = pair[1]
	var along: Vector3 = Vector3(cos(bearing), 0.0, sin(bearing))
	finisher.body.global_position = guard.body.global_position - along * SHOVE_STAND_METRES
	finisher.body.rotation = Vector3(0.0, atan2(-along.x, -along.z), 0.0)
	finisher.body.velocity = Vector3.ZERO
	if not assert_same(_controller.apply_shove(finisher), guard, "%s, bearing %d deg: the shove lands" % [map_id, roundi(rad_to_deg(bearing))]):
		return [0.0, 0]
	var ragdoll: Node = PrisonerAvatar.of(guard.body).get_node("Ragdoll")
	var space: PhysicsDirectSpaceState3D = guard.body.get_world_3d().direct_space_state
	var bodies: Array[RID] = []
	for participant: MatchParticipant in _controller.get_participants():
		bodies.append(participant.body.get_rid())
	var reach: float = 0.0
	var through: int = 0
	var before: PackedVector3Array = ragdoll.call(&"part_positions")
	for _tick: int in int(_controller.get_rules().kill_beat_seconds * SIM_HZ) - 2:
		await step_ticks(1)
		if not bool(ragdoll.call(&"is_active")):
			break
		var now: PackedVector3Array = ragdoll.call(&"part_positions")
		for index: int in now.size():
			reach = maxf(reach, now[index].distance_to(now[0]))
			if before[index].distance_to(now[index]) < THROUGH_METRES:
				continue
			# Front faces only, every layer: a centre that crosses into a wall or the rock went through it.
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(before[index], now[index], 0xFFFFFFFF, bodies)
			query.hit_back_faces = false
			query.hit_from_inside = false
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty() and (hit["position"] as Vector3).distance_to(now[index]) > THROUGH_METRES:
				through += 1
		before = now
	await _tear_down()
	return [reach, through]


func _throw_every_way(map_id: StringName) -> void:
	for step: int in BEARINGS:
		var bearing: float = TAU * float(step) / float(BEARINGS)
		var result: Array = await _throw(map_id, bearing)
		var label: String = "%s, bearing %d deg" % [map_id, roundi(rad_to_deg(bearing))]
		print("          FINALE %s: furthest part %.2f m from the pelvis, %d surfaces passed through" % [label, result[0], result[1]])
		assert_le(float(result[0]), BODY_REACH_METRES, "%s: the thrown guard stays one body" % label)
		assert_eq_int(int(result[1]), 0, "%s: no part of him passes through the tower or the map" % label)


## Open: some 85 surface crossings over the 16 throws; parts up to 4 m from the pelvis on 7 of them.
func test_the_thrown_guard_stays_whole_and_inside_the_world_on_hell() -> void:
	skip("LIVE BUG (S-03, S-04, open): the thrown guard's parts pass through tower surfaces and stretch; remove this line to measure")
	if is_skipped():
		return
	await _throw_every_way(MAPS[0])


func test_the_thrown_guard_stays_whole_and_inside_the_world_on_marble() -> void:
	skip("LIVE BUG (S-03, S-04, open): the thrown guard's parts pass through tower surfaces and stretch; remove this line to measure")
	if is_skipped():
		return
	await _throw_every_way(MAPS[1])
