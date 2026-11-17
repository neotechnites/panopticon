extends TestCase
## Playtest regressions in the limp body itself, measured offline on hell and marble: a body shot standing or
## at a run, and the guard thrown in the finale, stay one body on the map's side of every surface.

const SETTLE_TICKS: int = 60
const MAPS: Array[StringName] = [&"bentham_ring", &"marble"]
const BEARINGS: int = 8
## Metres the finisher stands from the guard when it shoves.
const SHOVE_STAND_METRES: float = 0.9
## Furthest a part's centre may lie from the pelvis: a standing body's foot is under a metre from it.
const BODY_REACH_METRES: float = 1.35
## A body is torn when a joint gapes this wide, metres, for more than [constant SLIP_TICKS] ticks running. The solver
## lets a joint slip for a single tick about once in 750 hard landings; the drawn skeleton keeps its lengths through it.
const TORN_METRES: float = 0.5
const SLIP_TICKS: int = 2
## No joint gapes a body's reach on any tick, and none is still this far apart, metres, once the body has lain two seconds.
const SETTLED_GAP_METRES: float = 0.2
## Fastest the pelvis, which carries the whole drawn body, may spin, rad/s. The torn body's ran near 1000.
const PELVIS_MOST_SPIN: float = 150.0
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

## Each jointed part of [param ragdoll] as [part, parent part, joint point in the parent, joint point in the part], from the rest pose.
func _joints_of(ragdoll: Node) -> Array:
	var parts: Array = ragdoll.get(&"_bones")
	var skeleton: Skeleton3D = (parts[0] as PhysicalBone3D).get_parent().get_parent() as Skeleton3D
	var by_bone: Dictionary = {}
	var at_rest: Dictionary = {}
	for part: PhysicalBone3D in parts:
		var bone: int = skeleton.find_bone(String(part.get(&"bone_name")))
		by_bone[bone] = part
		at_rest[part] = skeleton.get_bone_global_rest(bone) * part.body_offset
	var joints: Array = []
	for bone: int in by_bone:
		var part: PhysicalBone3D = by_bone[bone]
		var above: int = skeleton.get_bone_parent(bone)
		while above >= 0 and not by_bone.has(above):
			above = skeleton.get_bone_parent(above)
		if above < 0:
			continue
		var parent: PhysicalBone3D = by_bone[above]
		var in_part: Vector3 = part.joint_offset.origin
		joints.append([part, parent, (at_rest[parent] as Transform3D).affine_inverse() * (at_rest[part] as Transform3D) * in_part, in_part])
	return joints


## The widest any joint of [param joints] gapes now, metres.
func _widest_gap(joints: Array) -> float:
	var gap: float = 0.0
	for joint: Array in joints:
		var parent_end: Vector3 = (joint[1] as PhysicalBone3D).global_transform * (joint[2] as Vector3)
		gap = maxf(gap, parent_end.distance_to((joint[0] as PhysicalBone3D).global_transform * (joint[3] as Vector3)))
	return gap


## How many of [param now]'s part centres went through a surface of [param mask] on the way from [param before].
func _surfaces_crossed(space: PhysicsDirectSpaceState3D, before: PackedVector3Array, now: PackedVector3Array, mask: int, bodies: Array[RID]) -> int:
	var through: int = 0
	for index: int in now.size():
		if before[index].distance_to(now[index]) < THROUGH_METRES:
			continue
		# Front faces only: a centre that crosses into a wall or the rock went through it.
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(before[index], now[index], mask, bodies)
		query.hit_back_faces = false
		query.hit_from_inside = false
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(now[index]) > THROUGH_METRES:
			through += 1
	return through


## Every body's collider in the match: no surface to a limp part.
func _body_rids() -> Array[RID]:
	var bodies: Array[RID] = []
	for participant: MatchParticipant in _controller.get_participants():
		bodies.append(participant.body.get_rid())
	return bodies


## Shoot [param victim] and watch its limp body for two seconds; returns [widest joint gap, furthest part
## from the pelvis, map surfaces a part passed through, most ticks running a joint gaped [constant TORN_METRES],
## fastest pelvis spin, joint gap at the end].
func _shoot_and_measure(victim: MatchParticipant) -> Array[float]:
	var body: PlayerController = victim.body
	_controller.rifle.show_remote_hit(body, body.global_position + Vector3.UP, Vector3.BACK)
	var ragdoll: Node = PrisonerAvatar.of(body).get_node("Ragdoll")
	var joints: Array = _joints_of(ragdoll)
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var bodies: Array[RID] = _body_rids()
	var gap: float = 0.0
	var reach: float = 0.0
	var through: int = 0
	var limp_ticks: int = 0
	var gaping: int = 0
	var longest: int = 0
	var spin: float = 0.0
	var last_gap: float = 0.0
	var pelvis: PhysicalBone3D = (ragdoll.get(&"_bones") as Array)[0]
	var before: PackedVector3Array = PackedVector3Array()
	for _tick: int in 120:
		await step_ticks(1)
		if not bool(ragdoll.call(&"is_active")):
			continue
		limp_ticks += 1
		var parts: PackedVector3Array = ragdoll.call(&"part_positions")
		var now_gap: float = _widest_gap(joints)
		gap = maxf(gap, now_gap)
		last_gap = now_gap
		spin = maxf(spin, pelvis.angular_velocity.length())
		gaping = gaping + 1 if now_gap >= TORN_METRES else 0
		longest = maxi(longest, gaping)
		for index: int in range(1, parts.size()):
			reach = maxf(reach, parts[index].distance_to(parts[0]))
		if not before.is_empty():
			# What the parts land on: a shot-only hitbox a runner walks through is no surface.
			through += _surfaces_crossed(space, before, parts, int(ragdoll.get(&"collision_mask")), bodies)
		before = parts
	assert_gt(float(limp_ticks), 60.0, "the shot body lay limp while it was measured")
	return [gap, reach, float(through), float(longest), spin, last_gap]


func test_a_body_shot_standing_stays_one_body_on_hell_and_marble() -> void:
	for map_id: StringName in MAPS:
		for who: int in 3:
			_build(map_id)
			await step_ticks(SETTLE_TICKS)
			TestFixtures.pin_the_field(_controller, null)
			await step_ticks(SETTLE_TICKS)
			var live: Array[MatchParticipant] = _controller.get_live_participants()
			var measured: Array[float] = await _shoot_and_measure(live[who % live.size()])
			assert_le(measured[3], float(SLIP_TICKS), "%s, runner %d: no joint of the limp body stays apart" % [map_id, who])
			assert_lt(measured[1], BODY_REACH_METRES, "%s, runner %d: no part lies further from the pelvis than a body reaches" % [map_id, who])
			assert_eq_int(int(measured[2]), 0, "%s, runner %d: no part passes through the map" % [map_id, who])
			await _tear_down()


## A running body carries its speed into the ground: it stays one body and on the map's side of every surface.
func test_a_body_shot_at_a_run_stays_one_body_on_hell_and_marble() -> void:
	for map_id: StringName in MAPS:
		var torn: int = 0
		var through: int = 0
		var widest: float = 0.0
		var reach: float = 0.0
		var spin: float = 0.0
		var settled: float = 0.0
		for wait: int in SHOT_TICKS:
			for who: int in 3:
				_build(map_id)
				await step_ticks(wait)
				var live: Array[MatchParticipant] = _controller.get_live_participants()
				var measured: Array[float] = await _shoot_and_measure(live[who % live.size()])
				widest = maxf(widest, measured[0])
				reach = maxf(reach, measured[1])
				spin = maxf(spin, measured[4])
				settled = maxf(settled, measured[5])
				if int(measured[3]) > SLIP_TICKS:
					torn += 1
				through += int(measured[2])
				await _tear_down()
		print("          RUNNING KILLS %s: %d of %d torn, widest joint gap %.2f m (%.2f m settled), furthest part %.2f m, pelvis spin %.0f rad/s, %d surfaces passed through" % [map_id, torn, SHOT_TICKS.size() * 3, widest, settled, reach, spin, through])
		assert_eq_int(torn, 0, "%s: running kills whose limp body tore" % map_id)
		assert_lt(widest, BODY_REACH_METRES, "%s: no joint gapes a body's reach on any tick" % map_id)
		assert_lt(settled, SETTLED_GAP_METRES, "%s: every joint is back together once the body lies" % map_id)
		assert_lt(reach, BODY_REACH_METRES, "%s: no part lies further from the pelvis than a body reaches" % map_id)
		assert_lt(spin, PELVIS_MOST_SPIN, "%s: the limp body does not whirl" % map_id)
		assert_eq_int(through, 0, "%s: surfaces a running kill's limp body passed through" % map_id)


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


## One finale throw along [param bearing] radians; returns [furthest part from the pelvis, surfaces passed
## through, widest joint gap, most ticks running a joint gaped [constant TORN_METRES], limp ticks, fastest pelvis spin].
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
		return [0.0, 0, 0.0, 0, 0, 0.0]
	var ragdoll: Node = PrisonerAvatar.of(guard.body).get_node("Ragdoll")
	var space: PhysicsDirectSpaceState3D = guard.body.get_world_3d().direct_space_state
	var bodies: Array[RID] = _body_rids()
	var joints: Array = _joints_of(ragdoll)
	var reach: float = 0.0
	var through: int = 0
	var gap: float = 0.0
	var gaping: int = 0
	var longest: int = 0
	var limp_ticks: int = 0
	var spin: float = 0.0
	var pelvis: PhysicalBone3D = (ragdoll.get(&"_bones") as Array)[0]
	var before: PackedVector3Array = ragdoll.call(&"part_positions")
	for _tick: int in int(_controller.get_rules().kill_beat_seconds * SIM_HZ) - 2:
		await step_ticks(1)
		if not bool(ragdoll.call(&"is_active")):
			break
		limp_ticks += 1
		spin = maxf(spin, pelvis.angular_velocity.length())
		var now: PackedVector3Array = ragdoll.call(&"part_positions")
		for index: int in now.size():
			reach = maxf(reach, now[index].distance_to(now[0]))
		# Every layer: the tower's walls and the rock alike.
		through += _surfaces_crossed(space, before, now, 0xFFFFFFFF, bodies)
		var now_gap: float = _widest_gap(joints)
		gap = maxf(gap, now_gap)
		gaping = gaping + 1 if now_gap >= TORN_METRES else 0
		longest = maxi(longest, gaping)
		before = now
	await _tear_down()
	return [reach, through, gap, longest, limp_ticks, spin]


func _throw_every_way(map_id: StringName) -> void:
	for step: int in BEARINGS:
		var bearing: float = TAU * float(step) / float(BEARINGS)
		var result: Array = await _throw(map_id, bearing)
		var label: String = "%s, bearing %d deg" % [map_id, roundi(rad_to_deg(bearing))]
		print("          FINALE %s: furthest part %.2f m from the pelvis, widest joint gap %.2f m, pelvis spin %.0f rad/s, %d surfaces passed through" % [label, result[0], result[2], result[5], result[1]])
		assert_gt(float(result[4]), 60.0, "%s: the thrown guard lay limp while he was measured" % label)
		assert_lt(float(result[2]), BODY_REACH_METRES, "%s: no joint gapes a body's reach on any tick" % label)
		assert_lt(float(result[5]), PELVIS_MOST_SPIN, "%s: the thrown guard does not whirl" % label)
		assert_le(float(result[0]), BODY_REACH_METRES, "%s: the thrown guard stays one body" % label)
		assert_le(float(result[3]), float(SLIP_TICKS), "%s: no joint of the thrown guard stays apart" % label)
		assert_eq_int(int(result[1]), 0, "%s: no part of him passes through the tower or the map" % label)


func test_the_thrown_guard_stays_whole_and_inside_the_world_on_hell() -> void:
	await _throw_every_way(MAPS[0])


func test_the_thrown_guard_stays_whole_and_inside_the_world_on_marble() -> void:
	await _throw_every_way(MAPS[1])


## A shoved runner's flop on the real maps: its limbs hang on a torso pinned to the capsule and stay one body.
func test_a_shoved_runner_flops_as_one_body_on_hell_and_marble() -> void:
	for map_id: StringName in MAPS:
		for who: int in 3:
			_build(map_id)
			await step_ticks(SHOT_TICKS[who])
			var live: Array[MatchParticipant] = _controller.get_live_participants()
			var body: PlayerController = live[who % live.size()].body
			var avatar: PrisonerAvatar = PrisonerAvatar.of(body)
			var ragdoll: Node = avatar.get_node("Ragdoll")
			var joints: Array = _joints_of(ragdoll)
			var along: Vector3 = -body.global_transform.basis.z
			body.launch(Vector3(along.x, 0.0, along.z).normalized() * 16.0 + Vector3.UP * 7.0, 1.4)
			avatar.shove_hit()
			var flop_ticks: int = 0
			var reach: float = 0.0
			var gaping: int = 0
			var longest: int = 0
			var widest: float = 0.0
			for _tick: int in 180:
				await step_ticks(1)
				if not bool(ragdoll.call(&"is_flopping")):
					if flop_ticks > 0:
						break
					continue
				flop_ticks += 1
				var parts: PackedVector3Array = ragdoll.call(&"part_positions")
				for index: int in range(1, parts.size()):
					reach = maxf(reach, parts[index].distance_to(parts[0]))
				var gap: float = _widest_gap(joints)
				widest = maxf(widest, gap)
				gaping = gaping + 1 if gap >= TORN_METRES else 0
				longest = maxi(longest, gaping)
			print("          FLOP %s, runner %d: %d ticks limp, furthest part %.2f m, widest joint gap %.2f m" % [map_id, who, flop_ticks, reach, widest])
			assert_gt(float(flop_ticks), 10.0, "%s, runner %d: the shoved runner went limp" % [map_id, who])
			assert_lt(reach, BODY_REACH_METRES, "%s, runner %d: no limb flies off the flopping body" % [map_id, who])
			assert_le(float(longest), float(SLIP_TICKS), "%s, runner %d: no joint of the flopping body stays apart" % [map_id, who])
			await _tear_down()
