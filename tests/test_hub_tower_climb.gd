extends TestCase

## A body walks in the hub tower's door, up tower_interior.glb's stair and out of
## the stairwell into the guard room. That proves tower_hollow.glb is cut where
## the interior needs it (the room-floor collider has the hole) and that the
## shipped hub wires the hollow rock into the tower's RockArches slot.
##
## The body is the shipped player capsule (radius 0.4, height 1.8) under the
## shipped movement profile, driven by forward-and-turn intent tick by tick:
## straight in through the passage, then along the stair's walking line -- the
## middle of the 2 m clear tread, the wall found by a ray each tick -- and
## finally straight in off the top tread. Not one tick may leave it standing.

const HUB_SCENE_PATH: String = "res://scenes/hub/hub.tscn"

## Tower-local numbers from tools/modelling/tower_hollow_build.py's log.
const COURTYARD_Y: float = -36.4      # the tower's foot, where the door is
const DOOR_X: float = 13.0            # in the porch mouth (porch 12.62..13.52, bearing 0 = +X)
const SHAFT_ENTRY_R: float = 6.0      # inside this radius the passage is behind the body
const WALL_OFFSET: float = 1.3        # the walking line is this far in from the shaft wall
const MIN_STEP: float = 0.05          # metres a walking body covers in a tick, at the least
const ROOM_FLOOR_Y: float = 1.68      # his floor at the stairwell
const HOLE_INNER_R: float = 3.98      # the stairwell's inner edge
const HOLE_MID_R: float = 5.2         # ...and its middle, at the middle of its bearings
const HOLE_BEARING_DEG: float = 143.0 # Blender bearing, ccw from +X seen from above
const THROAT_FROM_DEG: float = 103.1  # where the throat under the floor begins

const MAX_TICKS: int = 60 * 60
const STALL_TICKS: int = 60 * 3

var _hub: Node3D
var _tower: Node3D
var _body: PlayerController
var _input: BotIntentSource
var _wall_r: float = 0.0


func before_each() -> void:
	_hub = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	_hub.name = "Hub"
	TestFixtures.silence_human_input(_hub)
	(_hub.get_node("HubLobby") as HubLobby).changes_scene = false
	var player: PlayerController = _hub.get_node("Player") as PlayerController
	var idle: BotIntentSource = BotIntentSource.new()
	idle.name = "BotInput"
	idle.shove_enabled = false
	player.add_child(idle)
	player.intent_source = idle
	for path: String in ["HubWorld/WorldEnvironment", "GameAudio"]:
		var node: Node = _hub.get_node_or_null(path)
		if node != null:
			node.free()
	add_child(_hub)
	_tower = _hub.get_node("HubWorld/Tower") as Node3D

	_body = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	_input = TestFixtures.bot_input_of(_body)
	_input.shove_enabled = false
	add_child(_body)
	_body.global_position = _tower.to_global(Vector3(DOOR_X, COURTYARD_Y + 0.05, 0.0))


func after_each() -> void:
	HubLobby.returns_to_hub = false


# --- The wiring ---------------------------------------------------------------

## The tower's arches slot is the hollow rock, live, with its collider; the
## carved rock is off; the interior sits at identity under the same node.
func test_the_hub_tower_is_the_hollow_arches_rock() -> void:
	var variant: TowerVariant = _tower as TowerVariant
	if not assert_not_null(variant, "the tower carries TowerVariant"):
		return
	assert_eq_int(variant.variant, 1, "variant 1, the arches slot, is live")

	var arches: Node3D = _tower.get_node("RockArches") as Node3D
	assert_true(
		arches.scene_file_path.ends_with("tower_hollow.glb"),
		"RockArches is tower_hollow.glb, not %s" % arches.scene_file_path
	)
	assert_true(arches.visible, "the hollow rock is drawn")
	var rock_body: StaticBody3D = arches.get_node_or_null("TowerCollision") as StaticBody3D
	if assert_not_null(rock_body, "its -colonly collider came through the import"):
		assert_eq_int(rock_body.collision_layer, 1, "and collides")

	var carved: Node3D = _tower.get_node("Rock") as Node3D
	assert_false(carved.visible, "the carved rock is hidden")
	var carved_body: StaticBody3D = carved.get_node_or_null("TowerCollision") as StaticBody3D
	if assert_not_null(carved_body, "the carved rock still has its collider"):
		assert_eq_int(carved_body.collision_layer, 0, "switched off")

	var interior: Node3D = _tower.get_node("Interior") as Node3D
	assert_true(interior.transform.is_equal_approx(Transform3D.IDENTITY), "the interior is at identity")
	var stair_shape: CollisionShape3D = interior.get_node_or_null("TowerInteriorCollision/CollisionShape3D") as CollisionShape3D
	if not assert_not_null(stair_shape, "with its stair collider"):
		return
	# Its wall faces in and is one-sided, and a one-sided face still blocks a body
	# coming from behind: the wall must have no face across the doorway.
	var faces: PackedVector3Array = (stair_shape.shape as ConcavePolygonShape3D).get_faces()
	var across_the_door: int = 0
	for i: int in range(0, faces.size(), 3):
		var c: Vector3 = (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		if c.x > 5.9 and c.x < 6.8 and absf(c.z) < 0.6 and c.y > COURTYARD_Y + 0.2 and c.y < COURTYARD_Y + 2.0:
			across_the_door += 1
	assert_eq_int(across_the_door, 0, "the interior's collider wall is open at the door")


## Straight down over the stairwell nothing of the rock's collider is left, and
## beside it, and short of it under the throat, his floor still is.
func test_the_room_floor_collider_is_open_over_the_stairwell() -> void:
	await step_ticks(1)
	var rock_body: StaticBody3D = _tower.get_node("RockArches/TowerCollision") as StaticBody3D
	var over_hole: Object = _first_hit_under(HOLE_BEARING_DEG, HOLE_MID_R)
	assert_true(
		over_hole != rock_body,
		"over the stairwell the first thing under the room is not the rock's floor (%s)" % _name_of(over_hole)
	)
	assert_same(_first_hit_under(HOLE_BEARING_DEG, HOLE_INNER_R - 0.8), rock_body, "inside the stairwell's edge his floor stays")
	assert_same(_first_hit_under(THROAT_FROM_DEG - 8.0, HOLE_MID_R), rock_body, "and so does the floor short of the throat")


## What a ray dropped through the room floor at this Blender bearing and radius
## hits first, or null.
func _first_hit_under(bearing_degrees: float, radius: float) -> Object:
	var theta: float = deg_to_rad(bearing_degrees)
	var top: Vector3 = _tower.to_global(
		Vector3(radius * cos(theta), ROOM_FLOOR_Y + 1.0, -radius * sin(theta))
	)
	var space: PhysicsDirectSpaceState3D = _tower.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		top, top + Vector3(0.0, -3.0, 0.0), 1
	)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.has("collider"):
		return null
	return hit.get("collider") as Object


func _name_of(object: Object) -> String:
	var node: Node = object as Node
	return "nothing" if node == null else String(node.get_path())


# --- The climb ----------------------------------------------------------------

## Door, passage, stair, stairwell, room. Fails on the first three seconds
## without progress, and says where.
func test_a_body_walks_in_the_door_up_the_stair_and_into_the_room() -> void:
	await step_ticks(5)
	var start: Vector3 = _tower.to_local(_body.global_position)
	assert_almost_eq(start.y, COURTYARD_Y, 0.15, "the body stands at the door on the courtyard")

	var phase: String = "passage"
	var best: float = -INF
	var stall: int = 0
	var ticks: int = 0
	var lowest_on_stair: float = INF
	var stuck_ticks: int = 0
	while ticks < MAX_TICKS:
		var local: Vector3 = _tower.to_local(_body.global_position)
		var r: float = Vector2(local.x, local.z).length()
		var direction: Vector3
		var progress: float
		var next_phase: String = phase
		match phase:
			"passage":
				direction = Vector3(-1.0, 0.0, 0.0)
				progress = -local.x
				if r < SHAFT_ENTRY_R:
					next_phase = "stair"
			"stair":
				direction = _stair_direction(local, r)
				progress = local.y
				lowest_on_stair = minf(lowest_on_stair, local.y)
				if local.y >= ROOM_FLOOR_Y + 0.02:
					next_phase = "room"
			_:
				direction = -Vector3(local.x, 0.0, local.z).normalized()
				progress = -r
				if r < HOLE_INNER_R - 1.0:
					break
		var before: Vector3 = _body.global_position
		_drive(direction)
		await step_ticks(1)
		ticks += 1
		if ticks > 10 and (_body.global_position - before).length() < MIN_STEP:
			stuck_ticks += 1
		if next_phase != phase:
			phase = next_phase
			best = -INF
			stall = 0
		elif progress > best + 0.01:
			best = progress
			stall = 0
		else:
			stall += 1
			if stall > STALL_TICKS:
				fail("stuck in the %s after %d ticks at tower-local %s (r %.2f), %s" % [
					phase, ticks, local, r, _blocker_ahead(direction),
				])
				break

	_input.command.move_direction = Vector2.ZERO
	await step_ticks(10)
	var end: Vector3 = _tower.to_local(_body.global_position)
	var end_r: float = Vector2(end.x, end.z).length()
	assert_eq_string(phase, "room", "the climb reached the room (ended in the %s)" % phase)
	assert_eq_int(stuck_ticks, 0, "no tick left the body standing still (%d ticks in all)" % ticks)
	print("      climbed in %d ticks (%.1f s), %d stuck" % [ticks, ticks / SIM_HZ, stuck_ticks])
	assert_almost_eq(lowest_on_stair, COURTYARD_Y, 0.3, "the stair was climbed from the courtyard")
	assert_almost_eq(end.y, ROOM_FLOOR_Y, 0.25, "the body stands on the guard-room floor")
	assert_true(end_r < HOLE_INNER_R - 0.9, "and is inside the room, past the stairwell (r %.2f)" % end_r)
	assert_true(_body.is_on_floor(), "on its feet")


## The stair's way round: along the wall counter-clockwise (seen from above in
## Blender, which is the interior's frame), held 0.6 m in from it.
func _stair_direction(local: Vector3, r: float) -> Vector3:
	var theta: float = atan2(-local.z, local.x)
	var radial: Vector3 = Vector3(cos(theta), 0.0, -sin(theta))
	var tangent: Vector3 = Vector3(-sin(theta), 0.0, -cos(theta))
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	if space != null:
		var from: Vector3 = _body.global_position + Vector3(0.0, 0.9, 0.0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + radial * 3.5, 1
		)
		query.exclude = [_body.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.has("position"):
			_wall_r = r + ((hit.get("position") as Vector3) - from).dot(radial)
	if _wall_r <= 0.0:
		_wall_r = r + WALL_OFFSET
	var pull: float = clampf((_wall_r - WALL_OFFSET - r) * 2.0, -0.8, 0.8)
	return (tangent + radial * pull).normalized()


## What the body is touching, for a failure message.
func _blocker_ahead(_direction: Vector3) -> String:
	var out: String = "on_floor=%s velocity=%s" % [_body.is_on_floor(), _body.velocity]
	for i: int in _body.get_slide_collision_count():
		var touch: KinematicCollision3D = _body.get_slide_collision(i)
		for c: int in touch.get_collision_count():
			out += "; %s at %s from the feet, normal %s" % [
				_name_of(touch.get_collider(c)).get_file(),
				touch.get_position(c) - _body.global_position, touch.get_normal(c),
			]
	return out


## Turn toward [param direction] through look intent and walk forward.
func _drive(direction: Vector3) -> void:
	var wanted: float = atan2(-direction.x, -direction.z)
	var turn: float = wrapf(wanted - _body.rotation.y, -PI, PI)
	# look_delta is radians per tick; the body applies rotate_y(-look_delta.x)
	_input.aim(-turn / SIM_DELTA, 0.0, SIM_DELTA)
	_input.command.move_direction = Vector2(0.0, 1.0)
