extends NetPowerRig

## A hologram is in the lag-compensation history (DESIGN 8, 8 + seat): a shot is traced at it where the
## shooter drew it, a client's as far back as its view and the host's at its playout.

const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
## One way, on the host's sends: B draws the world at least this far behind the host.
const DELAY_MS: int = 100
const EYE_HEIGHT: float = 1.5
const CHEST_HEIGHT: float = 0.9


func test_a_clients_shot_at_a_running_hologram_hits_it_where_it_was_drawn() -> void:
	if not await _a_running_hologram(DELAY_MS):
		return
	await get_tree().process_frame
	var decoy: PlayerController = power_of(host_links, A_SEAT).get_decoy()
	var drawn: Vector3 = power_of(b_links, A_SEAT).get_hologram().global_position
	var view_time: float = b.replicator.get_view_time()
	var behind: float = float(host.replicator.get_tick()) - view_time
	print("    hologram: B draws it %.1f ticks behind, %.2f m from the host's" % [behind, _flat(decoy.global_position - drawn)])
	assert_gt(behind * 1000.0 / float(Engine.physics_ticks_per_second), float(DELAY_MS), "B draws it 100 ms behind or more")
	assert_gt(_flat(decoy.global_position - drawn), 0.8, "the host's hologram has run well on from where B draws it")
	assert_same(_fire_at(drawn, view_time), decoy, "B's shot, traced at B's view, hits the hologram B drew")


func test_the_host_draws_a_remote_hologram_at_its_playout_and_hits_it_there() -> void:
	if not await _a_running_hologram(0):
		return
	# The host's hologram on each tick, as physics left it, against which its drawing is held.
	var decoy: PlayerController = power_of(host_links, A_SEAT).get_decoy()
	var stood: Dictionary[int, Vector3] = {}
	var keep: Callable = func() -> void: stood[host.replicator.get_tick()] = decoy.global_position
	get_tree().physics_frame.connect(keep)
	await step_ticks(4)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().physics_frame.disconnect(keep)
	var drawn: Vector3 = power_of(host_links, A_SEAT).get_hologram().global_position
	var view_time: float = host.replicator.get_view_time()
	var early: int = floori(view_time)
	if not assert_true(stood.has(early) and stood.has(early + 1), "the host drew a tick it ran"):
		return
	var expected: Vector3 = stood[early].lerp(stood[early + 1], view_time - float(early))
	assert_lt(_flat(decoy.global_position - drawn), _flat(decoy.global_position - expected) + 0.05, "drawn behind")
	assert_lt(_flat(expected - drawn), 0.05, "the host draws A's hologram at its playout, as it draws A")
	assert_same(_fire_at(drawn, view_time), decoy, "and its shot there, traced at its view, hits it")


## A's hologram, running on every machine; [param delay_ms] on the host's sends.
func _a_running_hologram(delay_ms: int) -> bool:
	rules.ability_duration_seconds = 30.0
	if not await stand_up(0.0, delay_ms):
		return false
	a_keys.tap_slot(HOLOGRAM)
	var out: bool = await until(func() -> bool:
		return power_of(host_links, A_SEAT).get_decoy() != null and power_of(b_links, A_SEAT).get_hologram() != null \
			and power_of(host_links, A_SEAT).get_hologram() != null)
	if not assert_true(out, "A's hologram is out on the host and drawn on B"):
		return false
	await step_ticks(30)
	var decoy: PlayerController = power_of(host_links, A_SEAT).get_decoy()
	return assert_gt(_flat(decoy.velocity), 3.0, "the hologram runs")


## The host's rifle, from its own body's eye, fired at the chest of a body drawn at [param feet] with the
## shooter's [param view_time]; what it hit, or null.
func _fire_at(feet: Vector3, view_time: float) -> Node3D:
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
	var eye: Vector3 = shooter.global_position + Vector3.UP * EYE_HEIGHT
	rifle.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(feet + Vector3.UP * CHEST_HEIGHT)
	assert_true(rifle.try_fire(view_time), "the rifle fires")
	rifle.queue_free()
	return struck[0] if not struck.is_empty() else null


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
