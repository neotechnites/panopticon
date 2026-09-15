extends TestCase

## The run cycle keeps cycling: a body that runs for longer than one 0.7 s
## clip is still taking strides, on every prisoner there is.
##
## The glTF's Run clip imports as a one-shot and PrisonerAvatar only re-plays
## a clip on a transition, so before the fix a bot on a long straight froze on
## the last frame of its first stride and slid along the deck ("they stop
## animating and start just floating"). The clip is one resource shared by
## every instance of the model, which is why the check runs on two bodies and
## on the raw model: the fix has to hold for a body nobody has looked at yet.

const AVATAR_SCENE: String = "res://scenes/player/prisoner_avatar.tscn"
const MODEL_SCENE: String = "res://assets/models/prisoner2.glb"
## Well past one 0.7 s cycle at full pace.
const RUN_TICKS: int = 150


func test_the_run_clip_loops_on_the_imported_model() -> void:
	var model: Node = (load(MODEL_SCENE) as PackedScene).instantiate()
	add_child(model)
	var player: AnimationPlayer = _player_of(model)
	assert_not_null(player, "the model carries its AnimationPlayer")
	assert_true(player.has_animation(&"Run"), "and the Run clip")
	assert_eq_int(
		player.get_animation(&"Run").loop_mode, Animation.LOOP_LINEAR,
		"Run is imported looping (assets/models/prisoner2.glb.import asks for it)"
	)
	model.queue_free()


func test_every_body_keeps_striding_past_one_cycle() -> void:
	var floor_body: StaticBody3D = TestFixtures.make_floor(0.0)
	add_child(floor_body)
	var bodies: Array[PlayerController] = []
	for index: int in 2:
		var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
		body.position = Vector3(float(index) * 3.0, 0.1, 0.0)
		add_child(body)
		bodies.append(body)
	await step_ticks(5)
	for body: PlayerController in bodies:
		var avatar: PrisonerAvatar = _avatar_of(body)
		assert_not_null(avatar, "%s wears a PrisonerAvatar" % body.name)
		assert_eq_int(
			avatar.animation.get_animation(avatar.run_clip).loop_mode, Animation.LOOP_LINEAR,
			"%s's Run clip loops once the avatar is ready" % body.name
		)
	# Run them, and keep running: the clip has cycled more than once by the end.
	for body: PlayerController in bodies:
		TestFixtures.bot_input_of(body).command.move_direction = Vector2(0.0, 1.0)
	var positions: Array[float] = []
	await step_ticks(RUN_TICKS / 2)
	for body: PlayerController in bodies:
		var avatar: PrisonerAvatar = _avatar_of(body)
		positions.append(avatar.animation.current_animation_position)
	await step_ticks(RUN_TICKS / 2)
	for index: int in bodies.size():
		var body: PlayerController = bodies[index]
		var avatar: PrisonerAvatar = _avatar_of(body)
		assert_gt(body.get_horizontal_speed(), 1.0, "%s is running" % body.name)
		assert_eq_string(String(avatar.animation.current_animation), String(avatar.run_clip), "%s is on the run clip" % body.name)
		assert_true(avatar.animation.is_playing(), "%s's run clip is still playing after %d ticks" % [body.name, RUN_TICKS])
		var clip_length: float = avatar.animation.get_animation(avatar.run_clip).length
		assert_lt(avatar.animation.current_animation_position, clip_length, "%s's playhead is inside the clip, not parked on its end" % body.name)
		assert_true(
			not is_equal_approx(avatar.animation.current_animation_position, positions[index]),
			"%s's playhead moved between the two samples (%.3f -> %.3f)" % [body.name, positions[index], avatar.animation.current_animation_position]
		)


func _avatar_of(body: Node) -> PrisonerAvatar:
	for node: Node in body.find_children("*", "PrisonerAvatar", true, false):
		return node as PrisonerAvatar
	return null


func _player_of(from: Node) -> AnimationPlayer:
	for node: Node in from.find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null
