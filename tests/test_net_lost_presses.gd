extends NetPowerRig

## A client's one-tick key against a run of lost packets: the press is still one edge on the host,
## however many packets in a row were lost (every unacknowledged command rides every packet), and
## a jittery, reordering line costs the prediction no more than the base build's did.

const LOSSES: Array[int] = [3, 5, 10]
## Reconcile error the base build (6fbdbc67) measured on the jittery line below, in metres: the least of 3 runs.
const BASE_JITTER_ERROR: float = 0.1887


func test_a_jump_tap_survives_three_five_and_ten_lost_packets() -> void:
	if not await stand_up(0.0, 1):
		return
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var jumps: Array[int] = [0]
	copy.jumped.connect(func() -> void: jumps[0] += 1)
	for lost: int in LOSSES:
		await step_ticks(60)
		jumps[0] = 0
		@warning_ignore("missing_await")
		black_out(a_wire, lost)
		a_keys.tap(&"jump_pressed")
		await step_ticks(lost + 60)
		assert_eq_int(jumps[0], 1, "a jump tapped into %d lost packets jumps once on the host" % lost)


func test_a_slide_tap_survives_three_five_and_ten_lost_packets() -> void:
	if not await stand_up(0.0, 1):
		return
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var slides: Array[int] = [0]
	copy.slide_started.connect(func(_speed: float) -> void: slides[0] += 1)
	copy.slide_enabled = true
	body_of(a_links, A_SEAT).slide_enabled = true
	for lost: int in LOSSES:
		a_keys.held.move_direction = Vector2(0.0, 1.0)
		await step_ticks(90)
		slides[0] = 0
		@warning_ignore("missing_await")
		black_out(a_wire, lost)
		a_keys.held.slide_held = true
		a_keys.tap(&"slide_pressed")
		await step_ticks(lost + 30)
		a_keys.held.slide_held = false
		a_keys.held.move_direction = Vector2.ZERO
		await step_ticks(60)
		assert_eq_int(slides[0], 1, "a slide tapped into %d lost packets opens once on the host" % lost)


func test_a_power_tap_survives_three_five_and_ten_lost_packets() -> void:
	if not await stand_up(0.0, 1):
		return
	var power: RunnerPower = power_of(host_links, A_SEAT)
	for lost: int in LOSSES:
		await step_ticks(30)
		var starts: Array[int] = [0]
		var was: bool = false
		@warning_ignore("missing_await")
		black_out(a_wire, lost)
		a_keys.tap_slot(MatchRules.RunnerAbility.BUBBLE_SHIELD)
		for _tick: int in lost + 40:
			await step_ticks(1)
			var up: bool = int(power.get_active()) != MatchRules.RunnerAbility.NONE
			starts[0] += int(up and not was)
			was = up
		assert_eq_int(starts[0], 1, "a shield tapped into %d lost packets is raised once on the host" % lost)
		await until(func() -> bool: return all_draw(A_SEAT, MatchRules.RunnerAbility.NONE))


func test_a_jittery_reordering_line_costs_prediction_no_more_than_before() -> void:
	if not await stand_up(0.0, 80):
		return
	for wire: LossyPeer in [a_wire, host_wire]:
		wire.conditions.jitter_ms = 20.0
		wire.conditions.jitter_reorders = true
		wire.conditions.reorder = 0.02
		wire.conditions.reorder_ms = 40.0
	var worst: Array[float] = [0.0]
	var counted: Array[int] = [0]
	a_links[A_SEAT].prediction_corrected.connect(func(metres: float, snapped: bool) -> void:
		if not snapped:
			worst[0] = maxf(worst[0], metres)
		counted[0] += 1)
	a_keys.held.move_direction = Vector2(0.0, 1.0)
	await step_ticks(120)
	worst[0] = 0.0
	counted[0] = 0
	for i: int in 6:
		a_keys.held.move_direction = Vector2(sin(float(i)), cos(float(i)))
		await step_ticks(60)
	a_keys.held.move_direction = Vector2.ZERO
	print("          RECONCILE at 80 ms +-20, 2%% reorder: worst %.4f m over %d corrections (base %.4f)" % [
		worst[0], counted[0], BASE_JITTER_ERROR])
	assert_gt(float(counted[0]), 20.0, "there were corrections to measure")
	assert_le(worst[0], BASE_JITTER_ERROR, "the worst correction is no worse than the base build's")
