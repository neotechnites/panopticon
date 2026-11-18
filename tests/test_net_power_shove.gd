extends NetPowerRig

## The shove swing across three machines. There is no match here: every body's swing gate is
## priced with a flat cooldown in its place, so a swing is the gate's and lands on nobody.

const SHOVE: StringName = &"shove_pressed"
## Ticks let pass after connecting, so a press is not made while a new connection is still settling.
const SETTLE_TICKS: int = 180
## The stand-in match's price of a swing: 15 ticks, so taps 25 ticks apart each swing.
const COOLDOWN_SECONDS: float = 0.25


func test_the_hosts_swing_is_drawn_once_on_each_client() -> void:
	if not await _stand_up_settled():
		return
	var on_a: Array[int] = _count_swings(body_of(a_links, HOST_SEAT))
	var on_b: Array[int] = _count_swings(body_of(b_links, HOST_SEAT))
	body_of(host_links, HOST_SEAT).shoved.emit()
	await until(func() -> bool: return on_a[0] >= 1 and on_b[0] >= 1, 1000)
	await step_ticks(30)
	assert_eq_int(on_a[0], 1, "A's mirror of the host swung once for the host's one swing")
	assert_eq_int(on_b[0], 1, "B's mirror of the host swung once for the host's one swing")


func test_five_host_swings_at_30_percent_loss_are_five_on_each_client() -> void:
	if not await _stand_up_settled(0.3, 0):
		return
	var on_a: Array[int] = _count_swings(body_of(a_links, HOST_SEAT))
	var on_b: Array[int] = _count_swings(body_of(b_links, HOST_SEAT))
	for _i: int in 5:
		body_of(host_links, HOST_SEAT).shoved.emit()
		await step_ticks(20)
	await until(func() -> bool: return on_a[0] >= 5 and on_b[0] >= 5, 1000)
	await step_ticks(30)
	assert_gt(float(host_wire.dropped), 10.0, "the host's wire dropped packets: this run was lossy")
	assert_eq_int(on_a[0], 5, "A's mirror of the host swung five times for five swings")
	assert_eq_int(on_b[0], 5, "B's mirror of the host swung five times for five swings")


func test_a_clients_own_swing_is_drawn_on_the_tick_it_taps() -> void:
	if not await _stand_up_settled():
		return
	var own: Array[int] = _count_swings(body_of(a_links, A_SEAT))
	a_keys.tap(SHOVE)
	await step_ticks(2)
	assert_eq_int(own[0], 1, "A's own body swung within 2 ticks of A's tap, without the host")


func test_one_tap_is_one_swing_on_every_machine() -> void:
	if not await _stand_up_settled():
		return
	await _one_tap_one_swing("clean line")


func test_one_tap_is_one_swing_on_every_machine_at_60_ms() -> void:
	if not await _stand_up_settled(0.0, 60):
		return
	await _one_tap_one_swing("60 ms each way")


func test_three_taps_are_three_swings_on_every_machine() -> void:
	if not await _stand_up_settled():
		return
	var own: Array[int] = _count_swings(body_of(a_links, A_SEAT))
	var on_b: Array[int] = _count_swings(body_of(b_links, A_SEAT))
	var on_host: Array[int] = _count_swings(body_of(host_links, A_SEAT))
	for _i: int in 3:
		a_keys.tap(SHOVE)
		await step_ticks(25)
	await step_ticks(30)
	assert_eq_int(on_host[0], 3, "the host swung A's body three times for three taps")
	assert_eq_int(own[0], 3, "A's own body swung three times, none twice")
	assert_eq_int(on_b[0], 3, "B's mirror of A swung three times")


func test_a_tap_inside_the_cooldown_swings_on_no_machine() -> void:
	if not await _stand_up_settled(0.0, 60):
		return
	var own: Array[int] = _count_swings(body_of(a_links, A_SEAT))
	var on_b: Array[int] = _count_swings(body_of(b_links, A_SEAT))
	var on_host: Array[int] = _count_swings(body_of(host_links, A_SEAT))
	a_keys.tap(SHOVE)
	await step_ticks(5)
	a_keys.tap(SHOVE)
	await step_ticks(90)
	assert_eq_int(own[0], 1, "A's own gate refused the second tap, inside its cooldown")
	assert_eq_int(on_host[0], 1, "and the host's gate, running the same commands, refused it too")
	assert_eq_int(on_b[0], 1, "so B's mirror of A swung once")


func test_an_armed_body_does_not_predict_a_swing() -> void:
	if not await _stand_up_settled():
		return
	var own_body: PlayerController = body_of(a_links, A_SEAT)
	var own: Array[int] = _count_swings(own_body)
	# The host says who is armed; A's copy follows it on every snapshot.
	body_of(host_links, A_SEAT).is_armed = true
	var armed: bool = await until(func() -> bool: return own_body.is_armed, 1000)
	assert_true(armed, "A's own body was told it is armed")
	a_keys.tap(SHOVE)
	await step_ticks(10)
	assert_eq_int(own[0], 0, "an armed body draws no swing of its own for a shove tap")
	body_of(host_links, A_SEAT).is_armed = false
	var unarmed: bool = await until(func() -> bool: return not own_body.is_armed, 1000)
	assert_true(unarmed, "A's own body was told it is no longer armed")
	a_keys.tap(SHOVE)
	await step_ticks(2)
	assert_eq_int(own[0], 1, "and unarmed again it does")


# --- Helpers ------------------------------------------------------------------

func _stand_up_settled(loss: float = 0.0, delay_ms: int = 0) -> bool:
	if not await stand_up(loss, delay_ms):
		return false
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		for link: PlayerNetLink in links:
			link.controller.swing_cost = func() -> float: return COOLDOWN_SECONDS
	await step_ticks(SETTLE_TICKS)
	return true


## A one-cell counter of the swings [param body] emits from now on.
func _count_swings(body: PlayerController) -> Array[int]:
	var count: Array[int] = [0]
	body.shoved.connect(func() -> void: count[0] += 1)
	return count


func _one_tap_one_swing(line: String) -> void:
	var own: Array[int] = _count_swings(body_of(a_links, A_SEAT))
	var on_b: Array[int] = _count_swings(body_of(b_links, A_SEAT))
	var on_host: Array[int] = _count_swings(body_of(host_links, A_SEAT))
	a_keys.tap(SHOVE)
	await step_ticks(40)
	assert_eq_int(on_host[0], 1, "%s: the host swung A's body once for one tap" % line)
	assert_eq_int(own[0], 1, "%s: A's own body swung once, not again on the host's answer" % line)
	assert_eq_int(on_b[0], 1, "%s: B's mirror of A swung once" % line)
	await step_ticks(60)
	assert_eq_int(own[0], 1, "%s: and A's own body draws nothing more for it later" % line)
	assert_eq_int(on_b[0], 1, "%s: nor does B's mirror" % line)


# --- Wire shim: the rig swaps the peer after the handshake, which empties the API's peer list ---

func _condition(session: NetSession, loss: float, rng_seed: int, delay_ms: int) -> LossyPeer:
	var known: PackedInt32Array = session.multiplayer.get_peers()
	var wire: LossyPeer = super(session, loss, rng_seed, delay_ms)
	for id: int in known:
		if not session.multiplayer.get_peers().has(id):
			wire.peer_connected.emit(id)
	return wire


func after_each() -> void:
	super()
	# The wire's forwarding lambdas hold it alive past exit; let go of them.
	for wire: LossyPeer in [a_wire, host_wire]:
		if wire == null:
			continue
		var real: MultiplayerPeer = wire.get("_real") as MultiplayerPeer
		for forwarded: Signal in [real.peer_connected, real.peer_disconnected]:
			for link: Dictionary in forwarded.get_connections():
				forwarded.disconnect(link["callable"] as Callable)
