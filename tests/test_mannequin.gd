extends TestCase

## The Debug menu's mannequin in the shipped hub: each routine moves it, each switch changes its layers,
## a real shove and a real rifle reach it, and removing it leaves nothing behind.

const HUB_SCENE_PATH: String = "res://hub/hub.tscn"

var _hub: Node3D = null
var _controller: MatchController = null
var _stage: MannequinStage = null


func before_each() -> void:
	_hub = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	TestFixtures.silence_human_input(_hub)
	(_hub.get_node("HubLobby") as HubLobby).changes_scene = false
	var body: PlayerController = _hub.get_node("Player") as PlayerController
	var input: BotIntentSource = BotIntentSource.new()
	input.name = "BotInput"
	input.shove_enabled = false
	body.add_child(input)
	body.intent_source = input
	for path: String in ["HubWorld/WorldEnvironment", "GameAudio"]:
		var node: Node = _hub.get_node_or_null(path)
		if node != null:
			node.free()
	add_child(_hub)
	_controller = _hub.get_node("MatchController") as MatchController


func after_each() -> void:
	HubLobby.returns_to_hub = false


func _spawn() -> PlayerController:
	await step_seconds(0.3)
	_stage = MannequinStage.find(_hub, _controller, true)
	var body: PlayerController = _stage.spawn()
	await step_seconds(0.6)
	return body


func _avatar(body: PlayerController) -> PrisonerAvatar:
	return body.get_node("Avatar") as PrisonerAvatar


## Runs [param routine] for [param seconds]; returns the furthest the body got from where it started.
func _run(body: PlayerController, routine: MannequinIntent.Routine, seconds: float) -> float:
	var start: Vector3 = body.global_position
	_stage.run(routine)
	var furthest: float = 0.0
	for _i: int in int(seconds * SIM_HZ):
		await step_ticks(1)
		furthest = maxf(furthest, body.global_position.distance_to(start))
	return furthest


func test_a_mannequin_stands_in_front_of_the_player_and_is_seated() -> void:
	var body: PlayerController = await _spawn()
	if not assert_not_null(body, "a mannequin spawns"):
		return
	var player: PlayerController = _controller.player
	assert_between(body.global_position.distance_to(player.global_position), 1.0, 6.0, "a few metres from the player")
	assert_true(body.is_on_floor(), "standing on the floor")
	var facing: Vector3 = -body.global_transform.basis.z
	var toward: Vector3 = (player.global_position - body.global_position) * Vector3(1.0, 0.0, 1.0)
	assert_gt(facing.dot(toward.normalized()), 0.9, "facing him")
	assert_eq_int(_controller.get_participants().size(), 2, "seated beside the player, so a real shove reaches it")
	assert_eq_int(_controller.get_participants_ref().size(), 2, "and it is a participant")


func test_every_routine_moves_the_body() -> void:
	var body: PlayerController = await _spawn()
	if not assert_not_null(body, "a mannequin spawns"):
		return
	var yaw: float = body.rotation.y
	await _run(body, MannequinIntent.Routine.LOOK, 1.0)
	assert_gt(absf(angle_difference(yaw, body.rotation.y)) + absf(body.get_view_angles().y), 0.2, "look turns the view")
	assert_gt(await _run(body, MannequinIntent.Routine.WALK, 1.0), 0.4, "walk moves it")
	assert_gt(await _run(body, MannequinIntent.Routine.SPRINT, 1.0), 2.0, "sprint moves it fast")
	var floor_y: float = body.global_position.y
	_stage.run(MannequinIntent.Routine.JUMP)
	var highest: float = floor_y
	for _i: int in 90:
		await step_ticks(1)
		highest = maxf(highest, body.global_position.y)
	assert_gt(highest - floor_y, 0.3, "jump leaves the floor")
	assert_gt(await _run(body, MannequinIntent.Routine.SLOPE, 1.0), 0.5, "slope walks somewhere (the slope or its fallback)")
	assert_gt(await _run(body, MannequinIntent.Routine.LEDGE, 1.0), 0.3, "ledge moves it (the ledge or its fallback)")
	var pitch: float = body.get_view_angles().y
	await _run(body, MannequinIntent.Routine.GUARD, 1.0)
	assert_true(body.is_guard, "guard makes it the guard")
	assert_not_null(_stage._rifle_of(body), "with a rifle in its hands")
	assert_not_null(_avatar(body).get(&"_held") as Object, "which the avatar holds")
	assert_gt(absf(body.get_view_angles().y - pitch), 0.1, "sweeping the aim")
	await _run(body, MannequinIntent.Routine.STAND, 0.2)
	assert_null(_stage._rifle_of(body), "the rifle goes with the routine")
	var gap: float = body.global_position.distance_to(_controller.player.global_position)
	await _run(body, MannequinIntent.Routine.FOLLOW, 2.0)
	assert_lt(body.global_position.distance_to(_controller.player.global_position), maxf(gap, 3.0), "follow closes on him")
	await _run(body, MannequinIntent.Routine.STAND, 1.5)
	assert_lt(body.get_horizontal_speed(), 0.5, "stop stands it still")


func test_switches_change_the_layers() -> void:
	var body: PlayerController = await _spawn()
	if not assert_not_null(body, "a mannequin spawns"):
		return
	var skeleton: Node = _avatar(body).find_child("Skeleton3D", true, false)
	await step_seconds(0.5)
	for layer: StringName in MannequinStage.LAYERS:
		var node: Node = skeleton.get_node(NodePath(String(layer)))
		_stage.set_layer(layer, false)
		assert_false(_stage.is_layer_on(layer), "%s reads off" % layer)
		await step_seconds(0.5)
		assert_almost_eq(float(node.get(&"_gate")), 0.0, 0.001, "%s fades out" % layer)
		_stage.set_layer(layer, true)
		await step_seconds(0.5)
		assert_gt(float(node.get(&"_gate")), 0.5, "%s fades back in" % layer)
	_stage.set_ragdoll(false)
	assert_false(_stage.is_ragdoll_on(), "ragdoll reads off")
	_stage.set_ragdoll(true)
	assert_true(_stage.is_ragdoll_on(), "and back on")
	var before: float = Engine.time_scale
	_stage.set_slow(true)
	assert_almost_eq(Engine.time_scale, before * 0.25, 0.0001, "slow motion is a quarter")
	_stage.set_slow(false)
	assert_almost_eq(Engine.time_scale, before, 0.0001, "and back")


func test_a_real_shove_throws_it() -> void:
	var body: PlayerController = await _spawn()
	if not assert_not_null(body, "a mannequin spawns"):
		return
	_stage.shove_from(Vector3.LEFT)
	var fastest: float = 0.0
	for _i: int in 60:
		await step_ticks(1)
		fastest = maxf(fastest, body.velocity.length())
	assert_gt(fastest, 5.0, "a shove from the side throws it")
	await step_seconds(1.5)
	assert_eq_int(_controller.get_participants().size(), 2, "the pusher is gone")


func test_a_near_miss_flinches_and_a_hit_ragdolls_and_it_stands_back_up() -> void:
	var body: PlayerController = await _spawn()
	if not assert_not_null(body, "a mannequin spawns"):
		return
	var contact: Node = _avatar(body).find_child("BodyContact", true, false)
	var serial: int = Rifle.shot_serial()
	_stage.near_miss()
	var flinched: float = 0.0
	for _i: int in 60:
		await step_ticks(1)
		flinched = maxf(flinched, float(contact.get(&"_flinch_pull")))
	assert_gt(float(Rifle.shot_serial() - serial), 0.0, "a real round was fired")
	assert_gt(flinched, 0.0, "and it flinched")
	var ragdoll: Node = _avatar(body).get_node("Ragdoll")
	_stage.shoot()
	var limp: bool = false
	for _i: int in 90:
		await step_ticks(1)
		limp = limp or bool(ragdoll.call(&"is_active"))
	assert_true(limp, "a rifle hit goes limp")
	_stage.stand_up()
	await step_seconds(1.0)
	assert_false(bool(ragdoll.call(&"is_active")), "stand up ends the ragdoll")
	assert_false(bool(_avatar(body).get(&"_dead")), "and it is alive again")


func test_removing_leaves_no_nodes_behind() -> void:
	await step_seconds(0.3)
	_stage = MannequinStage.find(_hub, _controller, true)
	await step_seconds(0.1)
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var body: PlayerController = _stage.spawn()
	_stage.spawn()
	await step_seconds(0.3)
	_stage.run(MannequinIntent.Routine.GUARD)
	await step_seconds(0.3)
	assert_gt(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), float(baseline), "two mannequins add nodes")
	_stage.remove(body)
	_stage.remove_all()
	await step_seconds(0.2)
	assert_eq_int(_stage.get_child_count(), 0, "the stage is empty")
	assert_eq_int(_controller.get_participants().size(), 1, "only the player is seated")
	assert_eq_int(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), baseline, "and no node is left behind")
