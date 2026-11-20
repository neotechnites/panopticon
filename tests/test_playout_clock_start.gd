extends NetPowerRig

## A client's playout clock from its first snapshot: it draws behind the newest snapshot it holds
## while its buffer fills, never past it (the clock once started clamped to an empty buffer's zero).

const WATCH_FRAMES: int = 40


func test_a_client_draws_behind_its_newest_snapshot_from_the_first() -> void:
	if not await stand_up(0.0, 0, true):
		return
	var first: Array[int] = []
	b.replicator.snapshot_received.connect(func(tick: int, _count: int) -> void:
		if first.is_empty():
			first.append(tick))
	if not await stand_late():
		fail("B never stood")
		return
	if not assert_true(await until(func() -> bool: return not first.is_empty()), "B took a snapshot"):
		return
	var nearest: float = INF
	var drawn: int = 0
	for _frame: int in WATCH_FRAMES:
		await get_tree().process_frame
		var view_time: float = b.replicator.get_view_time()
		if not is_finite(view_time):
			continue
		drawn += 1
		nearest = minf(nearest, float(b.replicator.get_latest_tick()) - view_time)
	print("    playout start: %d frames drawn, nearest %.3f ticks behind the newest snapshot" % [drawn, nearest])
	assert_gt(float(drawn), float(WATCH_FRAMES) * 0.5, "B drew at its playout clock")
	assert_ge(nearest, 0.0, "B never draws past the newest snapshot it holds")
