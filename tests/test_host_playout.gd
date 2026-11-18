extends NetPowerRig

## The host draws every body but its own [constant NetReplicator.HOST_PLAYOUT_TICKS] behind, out of
## the samples it sends (DESIGN 8, R2): a remote seat's wait is never drawn raw on the host, and the
## host's own shot rewinds to the world it drew, as a client's does. Render-only, so physics
## interpolation must stay off.

## A lateral run at the dev turbo: far enough in the playout delay that a live trace misses.
const BOT_SEAT: int = 2
const BOT_AT: Vector3 = Vector3(-12.0, 0.1, -14.0)
const EYE_HEIGHT: float = 1.5
## Ticks between two lost command packets on A's line.
const LOSS_EVERY: int = 45


func test_the_project_keeps_physics_interpolation_off() -> void:
	assert_false(
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"Godot's own interpolation stays off: the host's playout is the only thing that moves an avatar",
	)


func test_a_remote_seats_wait_is_not_drawn_raw_on_the_host() -> void:
	if not await stand_up(0.0, 1):
		return
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var link: PlayerNetLink = host_links[A_SEAT]
	var stream: CommandStream = host.replicator.stream_for(a.get_local_peer_id())
	a_keys.held.move_direction = Vector2(0.0, 1.0)
	await step_ticks(30)
	var starved_before: int = stream.get_starved_total()
	var nominal: float = copy.profile.ground_speed * SIM_DELTA
	# The travel of each tick, raw (the collider, as the host simulates it) and as the host draws it.
	var raw: PackedFloat32Array = PackedFloat32Array()
	var drawn: PackedFloat32Array = PackedFloat32Array()
	var last_body: Vector3 = copy.global_position
	var last_drawn: Vector3 = Vector3.INF
	for tick: int in 600:
		# One packet in every 45 lost: the seat waits a tick, then holds one more than it needs and drains it.
		a_wire.conditions.loss = 1.0 if tick % LOSS_EVERY == LOSS_EVERY - 1 else 0.0
		await step_ticks(1)
		# Half a tick into the frame, as a drawn frame between two physics ticks would be.
		host.replicator.draw_host_at(float(host.replicator.get_tick()) - NetReplicator.HOST_PLAYOUT_TICKS + 0.5)
		var here: Vector3 = link.drawn_position()
		raw.append(_flat(copy.global_position - last_body))
		if last_drawn.is_finite():
			drawn.append(_flat(here - last_drawn))
		last_body = copy.global_position
		last_drawn = here
	a_wire.conditions.loss = 0.0
	a_keys.held.move_direction = Vector2.ZERO
	var waits: int = stream.get_starved_total() - starved_before
	print("          PLAYOUT: %d waits; least travel in a tick %.3f m raw, %.3f m drawn; worst change between ticks %.3f m raw, %.3f m drawn (a tick at run speed is %.3f m); fastest drawn tick %.3f m" % [
		waits, _least(raw), _least(drawn), _worst_change(raw), _worst_change(drawn), nominal, _most(drawn)])
	assert_gt(float(waits), 0.0, "the line made the seat wait")
	assert_lt(_least(raw), nominal * 0.05, "so its body stood still for a tick while it ran")
	assert_ge(_least(drawn), nominal * 0.45, "but the host never drew it stopping: a wait is half a tick of travel at worst")
	assert_lt(_worst_change(drawn), _worst_change(raw), "and drew its speed changing less than it changed")
	assert_le(_most(drawn), nominal * 2.05, "nor drew it faster than its commands can run")


func _worst_change(steps: PackedFloat32Array) -> float:
	var worst: float = 0.0
	for i: int in range(1, steps.size()):
		worst = maxf(worst, absf(steps[i] - steps[i - 1]))
	return worst


func _least(steps: PackedFloat32Array) -> float:
	var least: float = INF
	for step: float in steps:
		least = minf(least, step)
	return least


func _most(steps: PackedFloat32Array) -> float:
	var most: float = 0.0
	for step: float in steps:
		most = maxf(most, step)
	return most


func test_a_host_shot_at_a_moving_bot_drawn_behind_hits() -> void:
	if not await stand_up():
		return
	var bot: PlayerNetLink = NetFixtures.add_seat_body(host, BOT_SEAT, 0, profile, true)
	bot.controller.collision_layer = 1
	bot.controller.collision_mask = 1
	bot.controller.global_position = BOT_AT
	var legs: BotIntentSource = bot.local_source as BotIntentSource
	legs.command.move_direction = Vector2(1.0, 0.0)
	legs.command.turbo_held = true
	await step_ticks(30)
	var shooter: PlayerController = body_of(host_links, HOST_SEAT)
	var rifle: Rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(rifle)
	rifle.profile = TestFixtures.weapon_profile()
	add_child(rifle)
	rifle.set_physics_process(false)
	rifle.shooter_body = shooter
	rifle.lag_back = host.replicator.rewind_ticks
	rifle.lag_trace = host.replicator.trace
	var struck: Array[Node3D] = []
	rifle.target_hit.connect(func(collider: Node3D, _at: Vector3, _n: Vector3) -> void: struck.append(collider))

	host.replicator.draw_host_at(float(host.replicator.get_tick()) - NetReplicator.HOST_PLAYOUT_TICKS)
	var drawn: Vector3 = bot.drawn_position()
	var live: Vector3 = bot.controller.global_position
	var eye: Vector3 = shooter.global_position + Vector3.UP * EYE_HEIGHT
	rifle.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(drawn + Vector3.UP * 0.9)
	print("          HOST SHOT: bot drawn %.2f m behind where it runs" % _flat(live - drawn))
	assert_gt(_flat(live - drawn), 0.8, "the bot is drawn well behind its collider")
	assert_true(rifle.try_fire(MoveIntent.LIVE_WORLD), "a live trace fires")
	assert_false(struck.has(bot.controller), "and, aimed at the drawn bot, misses the live one")
	await step_ticks(1)
	struck.clear()
	host.replicator.draw_host_at(float(host.replicator.get_tick()) - NetReplicator.HOST_PLAYOUT_TICKS)
	drawn = bot.drawn_position()
	rifle.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(drawn + Vector3.UP * 0.9)
	while not rifle.can_fire():
		rifle.tick(SIM_DELTA)
	assert_true(rifle.try_fire(host.replicator.get_view_time()), "the host's shot carries the time it drew")
	assert_true(struck.has(bot.controller), "and hits the bot where the host drew it")
	rifle.queue_free()


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
