extends TestCase

## The hub tower's door passage is as clear to the eye as it is to the capsule.
##
## The shipped player body walks the door axis from 4 m outside the rock face to
## 4 m inside the shaft wall. Every tick it must move, and every tick its capsule
## must stay clear of every DRAWN triangle in the corridor -- not the collider,
## the triangles Ryan sees. A passage the collider opens where the model is not
## cut reads as walking through rock, and that is the bug this guards.

const HUB_SCENE_PATH: String = "res://scenes/hub/hub.tscn"

## Tower-local, from tools/modelling/tower_interior_build.py's log: bearing 0 is
## +X, the courtyard floor is the tower's foot, the rock face is at x 13.02 and
## the lining at 6.42.
const COURTYARD_Y: float = -36.4
const ROCK_FACE_X: float = 13.02
const LINING_X: float = 6.42
const START_X: float = ROCK_FACE_X + 4.0
const END_X: float = LINING_X - 4.0

## The capsule the player scene carries: radius 0.4, height 1.8, feet at origin.
const BODY_RADIUS: float = 0.4
const BODY_HEIGHT: float = 1.8

## A drawn face wholly below this is ground: the floor a capsule rests on by
## definition, the doorstep, and the lip of the plinth his feet clear.
const UNDERFOOT: float = 0.10

## Export rounding and the reveal's own tolerance; below this a touch is contact
## with the surface he is walking past, not a triangle through his chest.
const SKIN: float = 0.02

const MIN_STEP: float = 0.05
const MAX_TICKS: int = 60 * 40

var _hub: Node3D
var _tower: Node3D
var _body: PlayerController
var _input: BotIntentSource
var _corridor: Array[PackedVector3Array] = []


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
	_body.global_position = _tower.to_global(Vector3(START_X, COURTYARD_Y + 0.05, 0.0))
	_corridor = _gather_corridor()


func after_each() -> void:
	HubLobby.returns_to_hub = false


## In and clear. The walk ends 4 m inside the shaft wall having never stopped
## and never had a drawn triangle inside the capsule.
func test_the_door_passage_is_clear_to_the_eye_and_to_the_body() -> void:
	await step_ticks(5)
	assert_gt(float(_corridor.size()), 0.0, "the corridor holds drawn triangles to test against")
	assert_true(_body.is_on_floor(), "the body starts on the courtyard")

	var ticks: int = 0
	var worst: float = INF
	var worst_at: Vector3 = Vector3.ZERO
	var arrived: bool = false
	while ticks < MAX_TICKS:
		var local: Vector3 = _tower.to_local(_body.global_position)
		if local.x <= END_X:
			arrived = true
			break
		var before: Vector3 = _body.global_position
		_drive()
		await step_ticks(1)
		ticks += 1
		var clearance: float = _capsule_clearance()
		if clearance < worst:
			worst = clearance
			worst_at = _tower.to_local(_body.global_position)
		if clearance < -SKIN:
			fail("a drawn triangle is %.3f m inside the capsule at tower-local %s" % [
				-clearance, _tower.to_local(_body.global_position)
			])
			break
		if ticks > 10 and (_body.global_position - before).length() < MIN_STEP:
			fail("blocked after %d ticks at tower-local %s" % [ticks, local])
			break

	_input.command.move_direction = Vector2.ZERO
	assert_true(arrived, "the walk reached 4 m inside the shaft wall in %d ticks" % ticks)
	var end: Vector3 = _tower.to_local(_body.global_position)
	assert_lt(absf(end.z), 1.0, "and stayed on the passage axis (z %.2f)" % end.z)
	assert_almost_eq(end.y, COURTYARD_Y, 0.3, "at courtyard level")
	print("      walked in %d ticks, worst clearance %.3f m at %s" % [ticks, worst, worst_at])


## Every drawn triangle in the hub that lies in the door corridor, in global
## space. Nothing outside it can reach a capsule that stays inside it.
func _gather_corridor() -> Array[PackedVector3Array]:
	var box: AABB = AABB(
		_tower.to_global(Vector3(END_X - 0.6, COURTYARD_Y - 0.3, -2.2)),
		Vector3(START_X - END_X + 1.2, 3.6, 4.4)
	).abs()
	var out: Array[PackedVector3Array] = []
	for node: Node in _hub.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if not mesh_node.is_visible_in_tree() or mesh_node.mesh == null:
			continue
		var to_global_xf: Transform3D = mesh_node.global_transform
		var faces: PackedVector3Array = mesh_node.mesh.get_faces()
		for i: int in range(0, faces.size(), 3):
			var a: Vector3 = to_global_xf * faces[i]
			var b: Vector3 = to_global_xf * faces[i + 1]
			var c: Vector3 = to_global_xf * faces[i + 2]
			if box.intersects(AABB(a, Vector3.ZERO).expand(b).expand(c)):
				out.append(PackedVector3Array([a, b, c]))
	return out


## How far the nearest corridor triangle is from the capsule's surface, negative
## when it is inside. Ground under his feet does not count.
func _capsule_clearance() -> float:
	var feet: Vector3 = _body.global_position
	var low: Vector3 = feet + Vector3(0.0, BODY_RADIUS, 0.0)
	var high: Vector3 = feet + Vector3(0.0, BODY_HEIGHT - BODY_RADIUS, 0.0)
	var nearest: float = INF
	for tri: PackedVector3Array in _corridor:
		if maxf(tri[0].y, maxf(tri[1].y, tri[2].y)) < feet.y + UNDERFOOT:
			continue
		nearest = minf(nearest, _segment_to_triangle(low, high, tri))
		if nearest <= 0.0:
			break
	return nearest - BODY_RADIUS


## Distance from segment [param p0]-[param p1] to a triangle, 0 when it pierces.
func _segment_to_triangle(p0: Vector3, p1: Vector3, tri: PackedVector3Array) -> float:
	if Geometry3D.segment_intersects_triangle(p0, p1, tri[0], tri[1], tri[2]) != null:
		return 0.0
	var best: float = INF
	for i: int in 3:
		var pair: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
			p0, p1, tri[i], tri[(i + 1) % 3]
		)
		best = minf(best, pair[0].distance_to(pair[1]))
	for point: Vector3 in [p0, p1]:
		best = minf(best, _point_to_triangle(point, tri))
	return best


## Distance from a point to a triangle's face, ignoring its edges.
func _point_to_triangle(point: Vector3, tri: PackedVector3Array) -> float:
	var normal: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
	if normal.length_squared() < 1e-12:
		return INF
	normal = normal.normalized()
	var offset: float = (point - tri[0]).dot(normal)
	var projected: Vector3 = point - normal * offset
	for i: int in 3:
		var edge: Vector3 = tri[(i + 1) % 3] - tri[i]
		if edge.cross(projected - tri[i]).dot(normal) < 0.0:
			return INF
	return absf(offset)


## Face down the passage (-X, the tower carries no rotation) and walk.
func _drive() -> void:
	var direction: Vector3 = Vector3(-1.0, 0.0, 0.0)
	var wanted: float = atan2(-direction.x, -direction.z)
	var turn: float = wrapf(wanted - _body.rotation.y, -PI, PI)
	_input.aim(-turn / SIM_DELTA, 0.0, SIM_DELTA)
	_input.command.move_direction = Vector2(0.0, 1.0)
