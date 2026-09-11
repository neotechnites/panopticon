extends TestCase

## [MovementAudioListener]: footsteps, jump, landing and slide, turned into
## positional audio for every [PlayerController] in the scene.
##
## [b]Why the director is built by hand instead of using the scene's own
## [code]scenes/audio/game_audio.tscn[/code].[/b] These tests want to force
## [constant AudioDirector.Activation.ALWAYS] (a headless run otherwise switches
## the director off, exactly as it should in play) and to inspect voices
## directly -- the same reason [code]tests/test_hit_feedback.gd[/code] builds its
## own [FxCameraKick] and [FxHitReaction] rather than instancing the shipped fx
## rig. The bank is the real shipped one, [b]duplicated[/b] (deep) rather than
## loaded and used as-is -- see [TestFixtures]'s rule against mutating a shared
## resource, which the footstep-cadence test below needs to do (zeroing
## [member AudioCue.min_retrigger_seconds] so the cadence being measured is the
## listener's distance pacing and not the cue's own rate limit).
##
## [b]Why events are counted through [signal AudioDirector.event_played] rather
## than read off the voice pool.[/b] A voice is reclaimed and reused; the pool at
## any instant undercounts how many times something actually played. The signal
## fires once per post and cannot miss one -- the same technique
## [code]scripts/audio/audio_system_check.gd[/code] uses for the same reason.

const BANK_PATH: String = "res://scenes/audio/placeholder_bank.tres"

## Height this file's floor sits at. Large and file-specific so a body that
## drifts never lands on something another test file left behind.
const FLOOR_Y: float = 940.0

## Ticks of full-forward intent to reach the profile's own ground speed --
## identical to [code]tests/test_movement.gd[/code]'s own [code]_run_up[/code],
## which measured that 110 ticks is enough.
const RUN_UP_TICKS: int = 110

var _profile: MovementProfile
var _bank: AudioBank
var _director: AudioDirector
var _tuning: MovementAudioTuning
var _listener: MovementAudioListener


func before_each() -> void:
	_profile = TestFixtures.movement_profile()

	# Deep duplicate: the bank's cues are Resources of their own, and a shallow
	# duplicate would leave this file mutating the very objects
	# scenes/audio/placeholder_bank.tres loads for the shipped game.
	_bank = (load(BANK_PATH) as AudioBank).duplicate(true) as AudioBank

	_director = AudioDirector.new()
	_director.name = "Director"
	_director.bank = _bank
	_director.activation = AudioDirector.Activation.ALWAYS
	add_child(_director)

	_tuning = MovementAudioTuning.new()
	_listener = MovementAudioListener.new()
	_listener.name = "MovementAudio"
	_listener.director = _director
	_listener.tuning = _tuning
	add_child(_listener)

	add_child(TestFixtures.make_floor(FLOOR_Y))


## Take the director's two anti-stacking filters off the movement cues on this
## file's private bank, for the tests that COUNT posts.
##
## [b]Neither filter is measured in the units these tests work in.[/b]
## [method AudioDirector._passes_limits] rejects a repeat within
## [member AudioCue.min_retrigger_seconds] of the last one -- compared against
## [method Time.get_ticks_msec], which is WALL time, while everything counted
## below is counted over PHYSICS ticks the harness steps through far faster than
## real time -- and rejects a second post of the same event inside one
## [method Engine.get_process_frames], of which a headless run draws far fewer
## per physics tick than a played game does. Both are mixing rules for a game
## running at 1:1; against a fast-forwarded simulation they throttle a footstep
## stream to a flat count that is the same for a walk and a sprint. Measured
## through them, a body covering twice the ground posted 30 footsteps where it
## had taken 53 strides, and the pacing under test was invisible.
##
## Only the tests that count call this. [method test_a_slide_posts_its_own_cues_and_no_footsteps]
## deliberately does not: it asserts an ABSENCE over a short window, which the
## shipped limits can only ever help to be true, and it has no reason to run on
## a bank the shipped game does not have.
func _unlimit_movement_cues() -> void:
	for event: StringName in AudioEvents.ALL:
		if not String(event).begins_with("movement."):
			continue
		var cue: AudioCue = _bank.get_cue(event)
		if cue != null:
			cue.min_retrigger_seconds = 0.0
			cue.allow_same_frame = true


func _make_body(where: Vector3) -> PlayerController:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	body.position = where
	add_child(body)
	return body


# --- The bank -------------------------------------------------------------------

func test_the_bank_has_positional_cues_for_every_movement_event() -> void:
	var events: Array[StringName] = [
		AudioEvents.MOVEMENT_FOOTSTEP,
		AudioEvents.MOVEMENT_JUMP,
		AudioEvents.MOVEMENT_LAND,
		AudioEvents.MOVEMENT_SLIDE_START,
		AudioEvents.MOVEMENT_SLIDE_END,
	]
	for event: StringName in events:
		assert_true(AudioEvents.ALL.has(event), "%s is in the roll call" % event)
		assert_true(AudioEvents.POSITIONAL.has(event), "%s is positional" % event)
		var cue: AudioCue = _bank.get_cue(event)
		if not assert_not_null(cue, "the shipped bank carries a cue for %s" % event):
			continue
		assert_not_null(cue.stream, "%s has a stream behind it" % event)
		assert_true(cue.positional, "%s's cue is placed in the world" % event)
	assert_eq_int(_bank.missing_events().size(), 0, "the shipped bank is still complete")


# --- Landing ----------------------------------------------------------------------

## A landing posts positionally, at the body, and a harder impact plays louder.
##
## [signal PlayerController.landed] is emitted directly rather than dropping a
## body from a height: the direction under test is "the listener turns an
## impact speed into gain correctly", and driving that off a real fall would
## make the impact speed an output of the physics instead of a controlled input.
## [code]tests/test_hit_feedback.gd[/code] makes the identical call for
## [signal Rifle.target_hit].
func test_landing_posts_at_the_body_scaled_by_impact() -> void:
	var body: PlayerController = _make_body(Vector3(5.0, FLOOR_Y + 1.0, -3.0))
	await step_ticks(1)

	var soft: float = _tuning.landing_min_impact_speed + 0.01
	var hard: float = _tuning.landing_full_impact_speed

	_director.clear_rate_limits()
	body.landed.emit(soft)
	if not assert_eq_int(_director.get_active_voice_count(), 1, "the soft landing posted exactly one voice"):
		return
	assert_true(_director.get_active_events()[0] == AudioEvents.MOVEMENT_LAND, "it is the landing cue")
	assert_vec3_almost_eq(
		_director.get_active_positions()[0], body.global_position, 0.01,
		"posted at the body that landed, not the origin",
	)
	var soft_db: float = _director.get_active_volume_db(0)

	_director.stop_all()
	_director.clear_rate_limits()
	body.landed.emit(hard)
	if not assert_eq_int(_director.get_active_voice_count(), 1, "the hard landing posted exactly one voice"):
		return
	var hard_db: float = _director.get_active_volume_db(0)

	assert_gt(hard_db, soft_db, "a harder landing plays louder than a soft one off the same cue")

	_director.stop_all()
	_director.clear_rate_limits()
	body.landed.emit(_tuning.landing_min_impact_speed - 0.5)
	assert_eq_int(
		_director.get_active_voice_count(), 0,
		"a landing too soft to matter -- a step off a kerb -- posts nothing at all",
	)


# --- Footsteps ----------------------------------------------------------------

## Footsteps are paced by ground covered, not by a clock: over an equal run, a
## body sped up (the same mechanism [GhostProfile.speed_multiplier] drives)
## posts more of them, and for BOTH bodies the count times the stride length
## tracks the distance actually travelled -- the same rule, not a faster body
## getting a special case.
func test_footsteps_pace_by_distance_and_scale_with_speed() -> void:
	_unlimit_movement_cues()
	var heard: Array[StringName] = []
	var connection: Callable = func(event: StringName, _positional: bool) -> void:
		heard.append(event)
	_director.event_played.connect(connection)

	# Phase 1: ordinary pace.
	var walker: PlayerController = _make_body(Vector3(0.0, FLOOR_Y + 0.05, 0.0))
	await step_ticks(1)
	TestFixtures.bot_input_of(walker).command.move_direction = Vector2(0.0, 1.0)
	var walker_start: Vector3 = walker.global_position
	await step_ticks(240)
	var walker_distance: float = (walker.global_position - walker_start).length()
	var walker_count: int = heard.count(AudioEvents.MOVEMENT_FOOTSTEP)

	walker.queue_free()
	await step_ticks(2)
	heard.clear()

	# Phase 2: sped up exactly as a ghost is -- see MovementAudioTuning's note on
	# ghosts_make_movement_sound for why this is the mechanism worth reusing here.
	var sprinter: PlayerController = _make_body(Vector3(0.0, FLOOR_Y + 0.05, 0.0))
	sprinter.speed_scale = 2.0
	await step_ticks(1)
	TestFixtures.bot_input_of(sprinter).command.move_direction = Vector2(0.0, 1.0)
	var sprinter_start: Vector3 = sprinter.global_position
	await step_ticks(240)
	var sprinter_distance: float = (sprinter.global_position - sprinter_start).length()
	var sprinter_count: int = heard.count(AudioEvents.MOVEMENT_FOOTSTEP)

	_director.event_played.disconnect(connection)

	assert_gt(sprinter_distance, walker_distance, "sanity: the sped-up body actually covered more ground")
	assert_gt(sprinter_count, walker_count, "and posted footsteps more often over the same stretch of time")

	var stride: float = _tuning.footstep_stride_metres
	var slack: float = stride * 1.5
	assert_between(
		float(walker_count) * stride, walker_distance - slack, walker_distance + slack,
		"the walk's footstep count tracks the ground it actually covered",
	)
	assert_between(
		float(sprinter_count) * stride, sprinter_distance - slack, sprinter_distance + slack,
		"and so does the sprint's -- same pacing rule, not a special case for speed",
	)


## A slide covers real ground and posts its own start/end cues, but none of
## that ground turns into footsteps -- the machine-gun failure mode
## [MovementAudioTuning.footstep_stride_metres]'s docs name explicitly.
func test_a_slide_posts_its_own_cues_and_no_footsteps() -> void:
	var heard: Array[StringName] = []
	var connection: Callable = func(event: StringName, _positional: bool) -> void:
		heard.append(event)
	_director.event_played.connect(connection)

	var body: PlayerController = _make_body(Vector3(0.0, FLOOR_Y + 0.05, 0.0))
	await step_ticks(1)
	var bot_input: BotIntentSource = TestFixtures.bot_input_of(body)
	bot_input.command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(RUN_UP_TICKS)
	if not assert_true(
		body.get_horizontal_speed() >= _profile.slide_min_entry_speed,
		"fast enough to open a slide",
	):
		return

	heard.clear()
	var slide_start_position: Vector3 = body.global_position
	bot_input.hold_slide(true)
	await step_ticks(20)
	bot_input.hold_slide(false)
	await step_ticks(5)
	_director.event_played.disconnect(connection)

	var slide_distance: float = (body.global_position - slide_start_position).length()
	assert_gt(
		slide_distance, _tuning.footstep_stride_metres * 1.5,
		"the slide covered more ground than one stride, so there was something to (wrongly) pace",
	)
	assert_eq_int(
		heard.count(AudioEvents.MOVEMENT_FOOTSTEP), 0,
		"none of that ground produced a footstep",
	)
	assert_true(heard.has(AudioEvents.MOVEMENT_SLIDE_START), "the slide opening posted its own cue")
	assert_true(heard.has(AudioEvents.MOVEMENT_SLIDE_END), "and closing posted the other one")


# --- A bot is a human, as far as this is concerned ------------------------------

## Drives one body through [BotIntentSource] and a second directly through
## [method PlayerController.set_intent] -- the same seam
## [code]tests/test_movement.gd[/code]'s [code]_drive[/code] uses, which is
## exactly what a human device, a network replay or [code]tests/test_movement.gd[/code]
## itself looks like from the controller's side, since [PlayerController] never
## reads [Input] either way -- and asserts the two post an IDENTICAL sequence of
## movement events for an identical script of inputs. Neither
## [MovementAudioListener] nor the controller it watches can tell the two apart,
## which is the whole point: a bot in a real match must sound exactly like the
## human it can replace in the tower.
func test_a_bot_and_a_directly_driven_body_post_the_same_events() -> void:
	# Counted, and compared post for post: a filter that drops a repeat on a
	# clock neither body shares makes the two sequences differ for reasons that
	# have nothing to do with what drove them.
	_unlimit_movement_cues()
	var bot_events: Array[StringName] = await _script_movement_events(true)
	var driven_events: Array[StringName] = await _script_movement_events(false)

	assert_gt(bot_events.size(), 0, "the bot actually posted something")
	assert_eq_int(driven_events.size(), bot_events.size(), "and the directly-driven body posted exactly as much")
	for i: int in mini(bot_events.size(), driven_events.size()):
		check(
			bot_events[i] == driven_events[i],
			"event %d: bot posted %s, directly-driven body posted %s" % [i, bot_events[i], driven_events[i]],
		)


## Runs one body through run-up, a jump, a landing and a slide, and returns the
## exact sequence of [AudioEvents] movement names it posted, in order.
## [param use_intent_source] picks which of the two equivalent control paths
## drives it; see [method test_a_bot_and_a_directly_driven_body_post_the_same_events].
func _script_movement_events(use_intent_source: bool) -> Array[StringName]:
	var heard: Array[StringName] = []
	var connection: Callable = func(event: StringName, _positional: bool) -> void:
		if AudioEvents.POSITIONAL.has(event) and String(event).begins_with("movement."):
			heard.append(event)
	_director.event_played.connect(connection)

	var body: PlayerController = _make_body(Vector3(0.0, FLOOR_Y + 0.05, 0.0))
	var bot_input: BotIntentSource = null
	var intent: MoveIntent = MoveIntent.new()
	intent.move_direction = Vector2(0.0, 1.0)
	if use_intent_source:
		bot_input = TestFixtures.bot_input_of(body)
		bot_input.command.move_direction = Vector2(0.0, 1.0)
	else:
		body.intent_source = null
		body.set_intent(intent)
	await step_ticks(1)

	# Run up to speed.
	for _tick: int in RUN_UP_TICKS:
		if not use_intent_source:
			body.set_intent(intent)
		await step_ticks(1)

	# Jump, then wait for it to land.
	if use_intent_source:
		bot_input.command.jump_pressed = true
	else:
		intent.jump_pressed = true
		body.set_intent(intent)
		intent.jump_pressed = false
	await step_ticks(1)
	for _tick: int in 60:
		if not use_intent_source:
			body.set_intent(intent)
		if body.is_on_floor():
			break
		await step_ticks(1)

	# Re-establish ground speed, then slide.
	for _tick: int in RUN_UP_TICKS:
		if not use_intent_source:
			body.set_intent(intent)
		await step_ticks(1)
	if use_intent_source:
		bot_input.hold_slide(true)
	else:
		intent.slide_pressed = true
		intent.slide_held = true
		body.set_intent(intent)
		intent.slide_pressed = false
	await step_ticks(20)
	if use_intent_source:
		bot_input.hold_slide(false)
	else:
		intent.slide_held = false
		body.set_intent(intent)
	await step_ticks(5)

	_director.event_played.disconnect(connection)
	body.queue_free()
	await step_ticks(2)
	return heard
