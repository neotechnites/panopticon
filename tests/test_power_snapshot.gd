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
	var watched: int = 0
	var worst: float = 0.0
	for _tick: int in WATCH_TICKS:
		await step_ticks(1)
		var view: CatView = power_of(b_links, HOST_SEAT).get_cat_view()
		if view == null or not power_of(b_links, HOST_SEAT).state.out:
			continue
		var yaw: float = _host_yaw_at(b.replicator.get_view_time())
		if not is_finite(yaw):
			continue
		watched += 1
		worst = maxf(worst, absf(rad_to_deg(angle_difference(view.global_basis.get_euler().y, yaw))))
		# Upright: the cat is axis-locked to its yaw on the host, so any tilt drawn here is wrong.
		assert_almost_eq(view.global_basis.y.dot(Vector3.UP), 1.0, 0.001, "B draws the flying cat upright")
	print("    flying cat: %d ticks watched, worst %.2f degrees from the host's at B's drawn time" % [watched, worst])
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


## The host cat's yaw at fractional host tick [param time], from the worlds the host sent; NAN outside them.
func _host_yaw_at(time: float) -> float:
	var ring: NetReplicator = host.replicator
	for i: int in range(1, ring._ring_count):
		var from: PlayerState = ring._slot(i - 1).find_seat(HOST_SEAT)
		var to: PlayerState = ring._slot(i).find_seat(HOST_SEAT)
		if from == null or to == null or not to.power_out or not from.power_out:
			continue
		if float(ring._slot(i - 1).tick) <= time and time <= float(ring._slot(i).tick):
			var span: float = float(ring._slot(i).tick - ring._slot(i - 1).tick)
			return lerp_angle(from.anchor_yaw, to.anchor_yaw, (time - float(ring._slot(i - 1).tick)) / maxf(span, 1.0))
	return NAN
