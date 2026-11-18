extends NetPowerRig

## The speed pick-up across three machines: one orb per machine at the same node path, the
## host alone awards it, and its boost reaches the body's owner and every mirror.

const PICKUP_SCENE_PATH: String = "res://props/speed_powerup.tscn"
## One detection layer per machine: the three share a physics world, and each orb may see
## only the bodies of its own machine.
const LAYER: Array[int] = [1 << 10, 1 << 11, 1 << 12]
const HOST: int = 0
const A: int = 1
const B: int = 2
const MACHINE: PackedStringArray = ["host", "A", "B"]
## Four metres ahead of seat 1 (bodies face -Z), and somewhere nobody walks.
const NEAR: Vector3 = Vector3(6.0, 1.0, -4.0)
const NEAR_HOST_SEAT: Vector3 = Vector3(0.0, 1.0, -4.0)
const FAR: Vector3 = Vector3(-80.0, 1.0, 80.0)
const FORWARD: Vector2 = Vector2(0.0, 1.0)
const MULTIPLIER: float = 3.0
## Ticks let pass after connecting, so nothing is pressed while a new connection is still settling.
const SETTLE_TICKS: int = 180

## Where each machine's orb goes, and whether it can detect that machine's bodies.
var spots: Array[Vector3] = [NEAR, NEAR, NEAR]
var sees: Array[bool] = [true, true, true]
var seconds: float = 7.0
var size: Vector3 = Vector3(1.5, 2.0, 1.5)
var pickups: Array[SpeedPowerup] = []


## One seat watched for a number of ticks: per tick, the boost each machine has on its body.
class Run extends RefCounted:
	var left: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var scale: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	## The owner's position by its own intent tick, and the host's copy by the intent tick it had run.
	var own_at: Dictionary[int, Vector3] = {}
	var host_at: Dictionary[int, Vector3] = {}
	var host_at_on: Dictionary[int, int] = {}
	## Corrections to the owner's prediction: the tick index, the miss in metres, whether it snapped.
	var corrected_on: PackedInt32Array = PackedInt32Array()
	var missed: PackedFloat32Array = PackedFloat32Array()
	var snapped: PackedInt32Array = PackedInt32Array()
	## The most boost the owner's own body was ever told it has, on any tick.
	var own_peak: float = 0.0

	## The first tick from [param from] on which [param machine] has a boost, or -1.
	func first_on(machine: int, from: int = 0) -> int:
		for i: int in range(maxi(from, 0), left[machine].size()):
			if left[machine][i] > 0.0:
				return i
		return -1

	## The first tick from [param from] on which [param machine] has none, or -1.
	func first_off(machine: int, from: int) -> int:
		for i: int in range(maxi(from, 0), left[machine].size()):
			if left[machine][i] <= 0.0:
				return i
		return -1

	func size() -> int:
		return left[0].size()


func test_the_host_awards_the_orb_once_and_it_goes_on_all_three() -> void:
	if not await _stand_up_with_pickups():
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 90)
	var taken: int = run.first_on(HOST)
	if not assert_gt(float(taken), -1.0, "the host gave A's body the boost when it reached the orb"):
		return
	assert_almost_eq(run.left[HOST][taken], seconds, 0.05, "for the orb's full time")
	assert_almost_eq(
		run.left[HOST][taken + 30], run.left[HOST][taken] - 0.5, 0.05,
		"and gave it once: 30 ticks on, half a second of it is spent",
	)
	for machine: int in 3:
		assert_false(pickups[machine].orb.visible, "the orb is gone on %s" % MACHINE[machine])


func test_the_orb_goes_on_machines_that_did_not_see_it_touched() -> void:
	sees = [true, false, false]
	if not await _stand_up_with_pickups():
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 70)
	assert_gt(float(run.first_on(HOST)), -1.0, "the host gave A's body the boost")
	for machine: int in 3:
		assert_false(pickups[machine].orb.visible, "the orb is gone on %s" % MACHINE[machine])


func test_the_client_that_took_it_keeps_the_boost() -> void:
	if not await _stand_up_with_pickups():
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 110)
	var taken: int = run.first_on(HOST)
	if not assert_gt(float(taken), -1.0, "the host gave A's body the boost"):
		return
	var later: int = taken + 30
	assert_gt(run.left[A][later], 0.0, "30 ticks after the pick-up A's own body still has the boost")
	assert_almost_eq(run.scale[A][later], MULTIPLIER, 0.06, "at the orb's multiplier")
	assert_almost_eq(
		run.left[A][later], run.left[HOST][later], 0.3, "with the time left the host is counting"
	)
	var got: int = run.first_on(A)
	if not assert_gt(float(got), -1.0, "A's own body was given the boost"):
		return
	assert_le(float(got - taken), 15.0, "within 15 ticks of the host awarding it")
	assert_eq_int(
		run.first_off(A, got), -1, "and from then to the end of the watch it never dropped it"
	)


func test_the_boosted_run_is_predicted_at_40_ms() -> void:
	seconds = 4.0
	if not await _stand_up_with_pickups(0.0, 40):
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 190)
	var taken: int = run.first_on(HOST)
	if not assert_gt(float(taken), -1.0, "the host gave A's body the boost"):
		return
	assert_gt(run.left[HOST][taken + 140], 0.0, "the boost was still running at the end of the watch")
	var worst_miss: float = 0.0
	var snaps: int = 0
	var corrections: int = 0
	for i: int in run.corrected_on.size():
		if run.corrected_on[i] <= taken + 20 or run.corrected_on[i] > taken + 140:
			continue
		corrections += 1
		worst_miss = maxf(worst_miss, run.missed[i])
		snaps += run.snapped[i]
	assert_gt(float(corrections), 30.0, "A's prediction was checked against the host all the way")
	assert_eq_int(snaps, 0, "no correction after the first 20 ticks of the boost is a snap")
	assert_lt(worst_miss, 0.05, "and none finds A's prediction off by more than 5 cm")
	# Same input, same place: the host's copy after A's tick T against A's own body after T.
	var worst_gap: float = 0.0
	var compared: int = 0
	for tick: int in run.host_at:
		if not run.own_at.has(tick) or run.host_at_on[tick] <= taken + 20:
			continue
		compared += 1
		worst_gap = maxf(worst_gap, run.host_at[tick].distance_to(run.own_at[tick]))
	assert_gt(float(compared), 100.0, "the host ran over 100 of A's boosted ticks")
	assert_lt(worst_gap, 1.5, "after those 20 ticks A's own body and the host's copy stay within 1.5 m, tick for tick")


func test_the_boost_ends_on_the_client_when_it_ends_on_the_host() -> void:
	seconds = 1.5
	if not await _stand_up_with_pickups():
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 190)
	var taken: int = run.first_on(HOST)
	var got: int = run.first_on(A)
	if not assert_gt(float(taken), -1.0, "the host gave A's body the boost"):
		return
	if not assert_gt(float(got), -1.0, "A's own body was given the boost"):
		return
	var host_end: int = run.first_off(HOST, taken)
	var own_end: int = run.first_off(A, got)
	assert_gt(float(host_end), -1.0, "the boost ended on the host")
	assert_gt(float(own_end), -1.0, "the boost ended on A")
	assert_between(float(host_end - taken), 88.0, 92.0, "it ran its 1.5 s on the host")
	assert_le(absf(float(own_end - host_end)), 30.0, "A's ended within 30 ticks of the host's")
	assert_eq_int(run.first_on(A, own_end), -1, "and did not come back on A")
	assert_eq_int(run.first_on(HOST, host_end), -1, "nor on the host")
	assert_almost_eq(run.scale[A][run.size() - 1], 1.0, 0.001, "A's own body is back to plain speed")


func test_the_boost_and_the_orb_get_through_30_percent_loss() -> void:
	seconds = 1.5
	sees = [true, false, false]
	if not await _stand_up_with_pickups(0.3, 0):
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 220)
	var taken: int = run.first_on(HOST)
	if not assert_gt(float(taken), -1.0, "the host gave A's body the boost"):
		return
	assert_gt(float(host_wire.dropped), 10.0, "the host's wire dropped packets: this run was lossy")
	var host_end: int = run.first_off(HOST, taken)
	for machine: int in [A, B]:
		var seen: int = run.first_on(machine)
		if not assert_gt(float(seen), -1.0, "%s shows the boost on A's body" % MACHINE[machine]):
			continue
		assert_le(float(seen - taken), 30.0, "%s hears of it within 30 ticks" % MACHINE[machine])
		var ended: int = run.first_off(machine, seen)
		assert_gt(float(ended), -1.0, "it ends on %s" % MACHINE[machine])
		assert_le(absf(float(ended - host_end)), 30.0, "within 30 ticks of ending on the host")
		assert_eq_int(run.first_on(machine, ended), -1, "and does not come back on %s" % MACHINE[machine])
	for machine: int in 3:
		assert_false(pickups[machine].orb.visible, "the orb is gone on %s" % MACHINE[machine])


func test_a_third_peer_is_told_the_boost_while_it_runs() -> void:
	seconds = 1.5
	sees = [true, false, false]
	if not await _stand_up_with_pickups():
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 190)
	var taken: int = run.first_on(HOST)
	var seen: int = run.first_on(B)
	if not assert_gt(float(taken), -1.0, "the host gave A's body the boost"):
		return
	if not assert_gt(float(seen), -1.0, "B's mirror of A reports the boost"):
		return
	assert_le(float(seen - taken), 20.0, "within 20 ticks of the host awarding it")
	assert_almost_eq(run.scale[B][seen + 5], MULTIPLIER, 0.06, "at the orb's multiplier")
	var host_end: int = run.first_off(HOST, taken)
	var mirror_end: int = run.first_off(B, seen)
	assert_gt(float(mirror_end), -1.0, "the boost ended on B's mirror")
	assert_le(absf(float(mirror_end - host_end)), 30.0, "within 30 ticks of ending on the host")


func test_a_client_walking_through_its_own_orb_alone_gets_nothing() -> void:
	spots = [FAR, NEAR, FAR]
	if not await _stand_up_with_pickups():
		return
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 70)
	var own: PlayerController = body_of(a_links, A_SEAT)
	assert_lt(own.global_position.z, NEAR.z - 2.0, "A walked through where its own orb is")
	assert_almost_eq(run.own_peak, 0.0, 0.0001, "A's own body was never boosted, not for a tick")
	assert_eq_int(run.first_on(A), -1, "A's machine never shows a boost on its body")
	assert_eq_int(run.first_on(HOST), -1, "the host, whose orb is elsewhere, awarded nothing")
	assert_eq_int(run.first_on(B), -1, "B's mirror of A shows no boost")
	for machine: int in 3:
		assert_true(pickups[machine].orb.visible, "the orb is still there on %s" % MACHINE[machine])


func test_the_hosts_own_pick_up_is_told_to_both_clients() -> void:
	seconds = 1.5
	spots = [NEAR_HOST_SEAT, NEAR_HOST_SEAT, NEAR_HOST_SEAT]
	sees = [true, false, false]
	if not await _stand_up_with_pickups():
		return
	host_keys.held.move_direction = FORWARD
	var run: Run = await _watch(HOST_SEAT, 190)
	var taken: int = run.first_on(HOST)
	if not assert_gt(float(taken), -1.0, "the host's own body took the boost"):
		return
	var host_end: int = run.first_off(HOST, taken)
	for machine: int in [A, B]:
		var seen: int = run.first_on(machine)
		if not assert_gt(float(seen), -1.0, "%s's mirror of the host reports the boost" % MACHINE[machine]):
			continue
		assert_le(float(seen - taken), 20.0, "%s hears of it within 20 ticks" % MACHINE[machine])
		assert_le(
			absf(float(run.first_off(machine, seen) - host_end)), 30.0,
			"and it ends on %s within 30 ticks of ending on the host" % MACHINE[machine],
		)
		assert_false(pickups[machine].orb.visible, "the orb is gone on %s" % MACHINE[machine])


func test_two_bodies_reaching_the_orb_together_have_one_winner_on_every_machine() -> void:
	# Wide enough for both seats to walk into it side by side.
	size = Vector3(10.0, 2.0, 1.5)
	spots = [Vector3(3.0, 1.0, -4.0), Vector3(3.0, 1.0, -4.0), Vector3(3.0, 1.0, -4.0)]
	if not await _stand_up_with_pickups(0.0, 60):
		return
	host_keys.held.move_direction = FORWARD
	a_keys.held.move_direction = FORWARD
	var run: Run = await _watch(A_SEAT, 80)
	assert_almost_eq(run.own_peak, 0.0, 0.0001, "A, second to the orb on the host, was never boosted on its own machine")
	assert_eq_int(run.first_on(HOST), -1, "the host did not boost A's body")
	var names: PackedStringArray = PackedStringArray()
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		var first: bool = body_of(links, HOST_SEAT).get_speed_boost_remaining() > 0.0
		var second: bool = body_of(links, A_SEAT).get_speed_boost_remaining() > 0.0
		names.append("%s%s" % ["host-seat" if first else "", "A-seat" if second else ""])
	for machine: int in 3:
		assert_eq_string(names[machine], "host-seat", "who has the boost according to %s" % MACHINE[machine])


# --- Helpers ------------------------------------------------------------------

## Connect, settle, give each machine its own detection layer and put the three orbs down.
func _stand_up_with_pickups(loss: float = 0.0, delay_ms: int = 0) -> bool:
	if not await stand_up(loss, delay_ms):
		return false
	await step_ticks(SETTLE_TICKS)
	var sessions: Array[NetSession] = [host, a, b]
	var links_of: Array[Array] = [host_links, a_links, b_links]
	for machine: int in 3:
		for link: PlayerNetLink in links_of[machine]:
			link.controller.collision_layer = LAYER[machine]
		var pickup: SpeedPowerup = (load(PICKUP_SCENE_PATH) as PackedScene).instantiate() as SpeedPowerup
		pickup.name = "SpeedPowerup"
		pickup.race_only = false
		pickup.auto_discover = false
		pickup.duration_seconds = seconds
		pickup.speed_multiplier = MULTIPLIER
		pickup.size_metres = size
		pickup.collision_mask = LAYER[machine] if sees[machine] else 0
		sessions[machine].get_parent().add_child(pickup)
		pickup.global_position = spots[machine]
		pickups.append(pickup)
		# Bound as a scene prop, as NetMatch binds a loaded scene's.
		var props: Array[Node] = [pickup]
		sessions[machine].replicator.bind_props(props)
	await step_ticks(2)
	return true


## Watch [param seat] on all three machines for [param ticks] ticks.
func _watch(seat: int, ticks: int) -> Run:
	var run: Run = Run.new()
	var bodies: Array[PlayerController] = [
		body_of(host_links, seat), body_of(a_links, seat), body_of(b_links, seat),
	]
	var own_link: PlayerNetLink = a_links[A_SEAT]
	var own: PlayerController = own_link.controller
	var host_link: PlayerNetLink = host_links[A_SEAT]
	var now: Array[int] = [0]
	var on_boost: Callable = func(remaining: float) -> void: run.own_peak = maxf(run.own_peak, remaining)
	var on_corrected: Callable = func(metres: float, snapped: bool) -> void:
		run.corrected_on.append(now[0])
		run.missed.append(metres)
		run.snapped.append(1 if snapped else 0)
	own.speed_boost_changed.connect(on_boost)
	own_link.prediction_corrected.connect(on_corrected)
	for i: int in ticks:
		now[0] = i
		await step_ticks(1)
		for machine: int in 3:
			run.left[machine].append(bodies[machine].get_speed_boost_remaining())
			run.scale[machine].append(bodies[machine].get_speed_boost_multiplier())
		if bodies[HOST].get_speed_boost_remaining() > 0.0:
			# Kept only while boosted: that is the run being compared.
			var applied: int = host_link.replicator.stream_for(host_link.owner_peer_id).get_ack()
			run.host_at[applied] = host_link.controller.global_position
			run.host_at_on[applied] = i
		var sent: int = own_link.replicator.outbox.next_seq() - 1
		if not run.own_at.has(sent):
			run.own_at[sent] = own.global_position
	own.speed_boost_changed.disconnect(on_boost)
	own_link.prediction_corrected.disconnect(on_corrected)
	return run


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
