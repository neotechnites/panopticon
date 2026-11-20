extends NetPowerRig

## Powers as state in the snapshot (DESIGN 9): a peer that stands mid-power draws it from its first
## snapshot alone, a flying cat turns as the host's does, and a raise is drawn where its body is.

const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
## Frames B is given after its first snapshot: its playout clock starts on that one.
const FIRST_DRAW_FRAMES: int = 3
const ORIENTATION_DEGREES: float = 5.0
const WATCH_TICKS: int = 40


func test_a_peer_standing_mid_shield_draws_it_from_its_first_snapshot() -> void:
	await _stands_mid_power(SHIELD)


func test_a_peer_standing_mid_hologram_draws_it_from_its_first_snapshot() -> void:
	await _stands_mid_power(HOLOGRAM)


func test_a_peer_standing_mid_cat_draws_it_from_its_first_snapshot() -> void:
	await _stands_mid_power(CAT)


## A runs [param which]; B stands only then. B draws nothing of it before its first snapshot, whose
## full update carries the power, and draws it as soon as that snapshot is drawn.
func _stands_mid_power(which: int) -> void:
	rules.ability_duration_seconds = 30.0
	if not await stand_up(0.0, 0, true):
		return
	a_keys.tap_slot(which)
	if not assert_true(await until(func() -> bool: return _draws(host_links, which) and _draws(a_links, which)),
			"A's power is drawn on the host and on A"):
		return
	await step_ticks(30)
	assert_false(_draws(b_links, which), "B, not yet standing, draws nothing of it")
	var first: Array[bool] = []
	b.replicator.snapshot_received.connect(func(_tick: int, _count: int) -> void:
		if first.is_empty():
			var state: PlayerState = b.replicator._newest().find_seat(A_SEAT)
			first.append(b.replicator.last_baseline < 0 and state != null and state.power_active and state.ability == which))
	if not await stand_late():
		fail("B never stood")
		return
	if not assert_true(await until(func() -> bool: return not first.is_empty()), "B took a snapshot"):
		return
	assert_true(first[0], "B's first snapshot is a full update that carries A's power")
	var drawn: bool = false
	for _frame: int in FIRST_DRAW_FRAMES:
		await get_tree().process_frame
		if _draws(b_links, which):
			drawn = true
			break
	assert_true(drawn, "B draws A's power within %d frames of its first snapshot" % FIRST_DRAW_FRAMES)
	assert_eq_int(int(power_of(b_links, A_SEAT).get_shown()), which, "and shows it running")


func test_a_flying_cats_orientation_matches_the_hosts() -> void:
	if not await stand_up():
		return
	host_keys.tap_slot(CAT)
	if not assert_true(await until(func() -> bool: return _draws(b_links, CAT, HOST_SEAT)), "B draws the host's cat"):
		return
	var host_power: RunnerPower = power_of(host_links, HOST_SEAT)
	if not assert_true(host_power.throw_cat(), "the host throws its cat"):
		return
	# The host's cat as the host has it on every tick (60 Hz), against which B's 30 Hz copy is held.
	var host_yaw: Dictionary[int, float] = {}
	var watched: int = 0
	var worst: float = 0.0
	for _tick: int in WATCH_TICKS:
		await step_ticks(1)
		if host_power.state.out:
			host_yaw[host.replicator.get_tick()] = host_power.state.pose_yaw
		var view: CatView = power_of(b_links, HOST_SEAT).get_cat_view()
		if view == null or not power_of(b_links, HOST_SEAT).state.out:
			continue
		var yaw: float = _yaw_at(host_yaw, b.replicator.get_view_time())
		if not is_finite(yaw):
			continue
		watched += 1
		worst = maxf(worst, absf(rad_to_deg(angle_difference(view.global_basis.get_euler().y, yaw))))
	var turns: Array[float] = host_yaw.values()
	var spun: float = absf(angle_difference(turns[0], turns[mini(10, turns.size() - 1)])) if turns.size() > 1 else 0.0
	print("    flying cat: %d ticks watched, worst %.2f degrees from the host's at B's drawn time" % [watched, worst])
	assert_gt(rad_to_deg(spun), ORIENTATION_DEGREES * 2.0, "the host's cat spins in flight, so a stale yaw would show")
	assert_gt(float(watched), 10.0, "B drew the cat in flight")
	assert_lt(worst, ORIENTATION_DEGREES, "B's flying cat faces the way the host's did at B's drawn time")


func test_a_shield_raise_is_drawn_where_its_body_is_drawn() -> void:
	rules.ability_duration_seconds = 5.0
	if not await stand_up():
		return
	a_keys.held.move_direction = Vector2(0.0, 1.0)
	await step_ticks(45)
	var runner: PlayerController = body_of(host_links, A_SEAT)
	if not assert_gt(runner.velocity.length(), 3.0, "A is running on the host"):
		return
	a_keys.tap_slot(SHIELD)
	var drawn_body: Vector3 = Vector3.INF
	for _frame: int in 600:
		await get_tree().process_frame
		if power_of(b_links, A_SEAT).get_shield() != null:
			drawn_body = body_of(b_links, A_SEAT).global_position
			break
	if not assert_true(drawn_body.is_finite(), "B drew A's shield"):
		return
	var raised_at: Vector3 = power_of(b_links, A_SEAT).get_shield().global_position - Vector3.UP * RunnerPower.SHIELD_RISE
	var heading: Vector3 = Vector3(runner.velocity.x, 0.0, runner.velocity.z).normalized()
	var ahead: float = (drawn_body - raised_at).dot(heading)
	var per_tick: float = Vector3(runner.velocity.x, 0.0, runner.velocity.z).length() / float(Engine.physics_ticks_per_second)
	print("    shield raise: B drew A's body %.3f m past the raise on its first shield frame (%.3f m a tick)" % [ahead, per_tick])
	assert_gt(ahead, -0.02, "B draws the shield no sooner than it draws the body reach the raise")
	assert_lt(ahead, per_tick * 2.0 + 0.02, "and no later than the frame the body passes it")


## True while [param links]' machine draws [param which] for [param seat].
func _draws(links: Array[PlayerNetLink], which: int, seat: int = A_SEAT) -> bool:
	var power: RunnerPower = power_of(links, seat)
	match which:
		SHIELD:
			return power.get_shield() != null
		HOLOGRAM:
			return power.get_hologram() != null
		CAT:
			return power.get_cat_view() != null
	return false


## The yaw in [param by_tick] at fractional tick [param time], between the two ticks around it; NAN outside.
func _yaw_at(by_tick: Dictionary[int, float], time: float) -> float:
	var before: int = floori(time)
	if not by_tick.has(before) or not by_tick.has(before + 1):
		return NAN
	return lerp_angle(by_tick[before], by_tick[before + 1], time - float(before))
