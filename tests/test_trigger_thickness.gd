extends TestCase

## The trigger-thickness lint (DESIGN 3.3, C13, R4). A seat may run [member NetSettings.cmd_budget]
## commands in one physics step and an [Area3D] sees only where the body ends the step, so a body
## can pass a hazard between two looks. For each kill and trap volume of every shipped map, along
## each axis: the volume's thickness plus the body's own extent must cover cmd_budget commands of
## the fastest travel the scene allows there, read from [MovementProfile], the scene's orbs and pads
## and the rules' shove; down, the fall from the scene's top, unless ground inside the volume stops
## the body there. A failing volume is named. (No lap volume exists: laps are tracked along the ring.)

const PLAYER_SCENE: String = "res://characters/player/player.tscn"
const RULES_PATH: String = "res://match/rules/default_match_rules.tres"
const SETTINGS_PATH: String = "res://match/net/default_net_settings.tres"


func test_every_hazard_volume_is_too_thick_to_cross_between_two_looks() -> void:
	var profile: MovementProfile = TestFixtures.movement_profile()
	var rules: MatchRules = load(RULES_PATH) as MatchRules
	var budget: int = (load(SETTINGS_PATH) as NetSettings).cmd_budget
	var body: PlayerController = (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerController
	var capsule: CapsuleShape3D = (body.get_node(^"Collision") as CollisionShape3D).shape as CapsuleShape3D
	var width: float = capsule.radius * 2.0
	var height: float = minf(capsule.height, profile.crouch_height)
	body.free()
	var failures: PackedStringArray = PackedStringArray()
	var checked: int = 0
	for map: MapDefinition in MapCatalog.all():
		var scene: PackedScene = load(map.scene_path) as PackedScene
		if not assert_not_null(scene, "%s loads" % map.id):
			continue
		var arena: Node3D = scene.instantiate() as Node3D
		add_child(arena)
		await step_ticks(1)
		var across: Array = _fastest_across(arena, profile, rules)
		var top: float = _top(arena)
		for node: Node in arena.find_children("*", "Area3D", true, false):
			if not (node is KillVolume or node is TrapVolume):
				continue
			var box: AABB = _extent(node as Area3D)
			if box.size == Vector3.ZERO:
				continue
			checked += 1
			var fall: float = minf(profile.terminal_velocity, sqrt(2.0 * profile.get_effective_gravity() * maxf(top - box.position.y, 0.0)))
			var reach_across: float = float(budget) * float(across[0]) * SIM_DELTA
			var reach_down: float = float(budget) * fall * SIM_DELTA
			var thin: float = minf(box.size.x, box.size.z)
			var where: String = "%s %s" % [map.id, arena.get_path_to(node)]
			if thin + width < reach_across:
				failures.append("%s: %.2f m across + %.2f m of body < %.2f m (%s at %.1f m/s)" % [
					where, thin, width, reach_across, across[1], float(across[0])])
			if box.size.y + height < reach_down and not _floored(arena, box):
				failures.append("%s: %.2f m deep + %.2f m of body < %.2f m (falling at %.1f m/s)" % [
					where, box.size.y, height, reach_down, fall])
		arena.queue_free()
		await step_ticks(1)
	print("          LINT %d volumes over %d maps; %d too thin" % [checked, MapCatalog.all().size(), failures.size()])
	for line: String in failures:
		print("            " + line)
	assert_gt(float(checked), 0.0, "the maps' hazard volumes were found")
	assert_eq_string("\n".join(failures), "", "no hazard volume can be crossed between two looks")


## The fastest a body can cross ground in [param arena], and what gives it: run at the scene's
## biggest orb, the slide's cap, a pad's throw, or a shove.
func _fastest_across(arena: Node, profile: MovementProfile, rules: MatchRules) -> Array:
	var boost: float = 1.0
	for node: Node in arena.find_children("*", "Area3D", true, false):
		if node is SpeedPowerup:
			boost = maxf(boost, (node as SpeedPowerup).speed_multiplier)
	var best: Array = [profile.ground_speed * boost, "a run at x%.1f boost" % boost]
	if profile.slide_boost_speed_cap > float(best[0]):
		best = [profile.slide_boost_speed_cap, "a slide"]
	for node: Node in arena.find_children("*", "Area3D", true, false):
		if node is BoostPad:
			var pad: BoostPad = node as BoostPad
			var flat: float = pad.launch_speed * cos(deg_to_rad(pad.launch_angle_degrees))
			if flat > float(best[0]):
				best = [flat, "a pad's throw"]
	if rules.shove_impulse > float(best[0]):
		best = [rules.shove_impulse, "a shove"]
	return best


## True when solid ground stands inside [param box] under its middle: a body falling in stops there.
func _floored(arena: Node3D, box: AABB) -> bool:
	var middle: Vector3 = box.get_center()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(middle.x, box.end.y, middle.z), Vector3(middle.x, box.position.y, middle.z), 1
	)
	return not arena.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The world box of [param volume]'s shapes.
func _extent(volume: Area3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for child: Node in volume.get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder == null or holder.shape == null or holder.disabled:
			continue
		var local: AABB = holder.shape.get_debug_mesh().get_aabb()
		var world: AABB = holder.global_transform * local
		box = world if first else box.merge(world)
		first = false
	return box


## The highest point of anything drawn in [param arena]: the furthest a body can fall from.
func _top(arena: Node) -> float:
	var top: float = -INF
	for node: Node in arena.find_children("*", "GeometryInstance3D", true, false):
		var drawn: GeometryInstance3D = node as GeometryInstance3D
		top = maxf(top, (drawn.global_transform * drawn.get_aabb()).end.y)
	return top
