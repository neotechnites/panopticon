extends NetPowerRig

## A rig's freeze ([NetWires.freeze]) stops one machine for real: nothing it sends arrives and it reads
## nothing, then it carries on. The in-process half of the test network's freeze of X ms on either end.

const FREEZE_MS: float = 700.0


func _real_wait(ms: int) -> void:
	var until_ms: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until_ms:
		await get_tree().process_frame


func test_a_frozen_host_says_nothing_until_it_thaws() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var before: int = a.replicator.get_latest_tick()
	assert_gt(float(before), 0.0, "A is hearing the host's snapshots")
	freeze(host, FREEZE_MS)
	await _real_wait(100)
	var frozen_at: int = a.replicator.get_latest_tick()
	await _real_wait(int(FREEZE_MS) - 250)
	assert_true(wires.of(host).is_frozen(), "the host is still frozen")
	assert_eq_int(a.replicator.get_latest_tick(), frozen_at, "and A has heard no snapshot since it froze")
	await _real_wait(500)
	assert_false(wires.of(host).is_frozen(), "the freeze ends")
	assert_gt(float(a.replicator.get_latest_tick()), float(frozen_at), "and the host's snapshots flow again")


func test_a_frozen_client_reads_nothing_and_sends_nothing_until_it_thaws() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var heard_before: int = a.replicator.get_latest_tick()
	var a_id: int = a.get_local_peer_id()
	var from_a: Array[int] = [0]
	host_links[1].intent_received.connect(func(_peer: int, _tick: int) -> void: from_a[0] += 1)
	freeze(a, FREEZE_MS)
	await _real_wait(150)
	var a_heard: int = a.replicator.get_latest_tick()
	var host_heard: int = from_a[0]
	await _real_wait(int(FREEZE_MS) - 300)
	assert_eq_int(a.replicator.get_latest_tick(), a_heard, "a frozen client reads no snapshot")
	assert_eq_int(from_a[0], host_heard, "and the host hears no intent from it")
	await _real_wait(500)
	assert_gt(float(a.replicator.get_latest_tick()), float(maxi(a_heard, heard_before)), "thawed, it reads again")
	assert_gt(float(from_a[0]), float(host_heard), "and sends again")
	assert_true(a_id > 0, "on the same connection")
