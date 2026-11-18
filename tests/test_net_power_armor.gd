extends "res://tests/support/net_power_wired_rig.gd"

## The armor lock held by a client: the host holds the body still and immune, everyone draws the
## shell, and the presser's own prediction is not dragged about as the lock starts and ends.

const NONE: int = MatchRules.RunnerAbility.NONE
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const FORWARD: Vector2 = Vector2(0.0, 1.0)
## The worst correction a lock's start and end may cost the presser at 60 ms, in metres.
const LOCK_CORRECTION_METRES: float = 0.05

var _worst_correction: float = 0.0
var _snaps: int = 0
var _corrections: int = 0
var _host_locks: int = 0
var _host_holograms: int = 0
var _host_last: int = NONE


func test_locking_and_unlocking_at_a_run_does_not_rubber_band_the_presser() -> void:
	if not await stand_up(0.0, 60):
		return
	# Past a connection's first seconds, so the press is not inside ENet's opening pass.
	await step_ticks(150)
	a_keys.held.move_direction = FORWARD
	await step_ticks(60)
	a_links[A_SEAT].prediction_corrected.connect(_on_corrected)
	a_keys.held.ability_held = true
	a_keys.tap_slot(ARMOR)
	await step_ticks(30)
	assert_eq_int(drawn(A_SEAT)[0], ARMOR, "the host has A locked 30 ticks into the hold")
	a_keys.held.ability_held = false
	await step_ticks(60)
	a_links[A_SEAT].prediction_corrected.disconnect(_on_corrected)
	print(
		"    lock at a run, 60 ms: worst correction %.4f m, %d snap(s), %d snapshots answered"
		% [_worst_correction, _snaps, _corrections]
	)
	assert_gt(float(_corrections), 20.0, "the host answered A's prediction through the lock")
	assert_eq_int(_snaps, 0, "times A's body was snapped as the lock started and ended")
	assert_lt(
		_worst_correction, LOCK_CORRECTION_METRES,
		"metres A's prediction was out by as the lock started and ended",
	)
	assert_eq_int(drawn(A_SEAT)[0], NONE, "the lock is over on the host after the release")


func test_a_held_lock_holds_the_body_on_the_host_and_frees_it_on_release() -> void:
	if not await stand_up():
		return
	var on_host: PlayerController = body_of(host_links, A_SEAT)
	a_keys.held.move_direction = FORWARD
	a_keys.held.ability_held = true
	a_keys.tap_slot(ARMOR)
	var up: bool = await until(func() -> bool: return all_draw(A_SEAT, ARMOR))
	assert_true(up, "the held lock is up on host, A and B: %s" % str(drawn(A_SEAT)))
	var held_at: Vector3 = on_host.global_position
	await step_ticks(20)
	assert_lt(
		on_host.global_position.distance_to(held_at), 0.01,
		"metres the host's copy of A moved in 20 ticks of a held lock with forward down",
	)
	assert_true(on_host.is_movement_locked(), "the host holds A's body while the key is down")
	assert_true(power_of(host_links, A_SEAT).is_hit_immune(), "A is immune on the host while locked")
	assert_eq_int(drawn(A_SEAT)[2], ARMOR, "B draws A's lock while the key is down")
	assert_eq_int(_live_nodes(body_of(b_links, A_SEAT), "ArmorShell"), 1, "shells B draws on A")
	a_keys.held.ability_held = false
	var ticks: int = await _ticks_until_all_none(60)
	assert_le(float(ticks), 30.0, "ticks from release until host, A and B all draw nothing")
	assert_false(power_of(host_links, A_SEAT).is_hit_immune(), "A can be hit again after release")
	var freed_at: Vector3 = on_host.global_position
	await step_ticks(20)
	assert_gt(
		on_host.global_position.distance_to(freed_at), 1.0,
		"metres the host's copy of A ran in the 20 ticks after release",
	)
	assert_eq_int(_shells_anywhere(), 0, "shells left on any machine after release")


func test_a_one_tick_tap_of_the_lock_ends_everywhere() -> void:
	if not await stand_up():
		return
	await step_ticks(1)
	a_keys.tap_slot(ARMOR)
	await step_ticks(2)
	assert_eq_int(drawn(A_SEAT)[1], NONE, "a tap's lock is over on A the tick after it")
	await step_ticks(30)
	assert_true(all_draw(A_SEAT, NONE), "a tapped lock ended on host, A and B: %s" % str(drawn(A_SEAT)))
	assert_eq_int(_shells_anywhere(), 0, "shells left on any machine after a tapped lock")
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		assert_false(body_of(links, A_SEAT).is_movement_locked(), "a tapped lock left a copy of A held")
	a_keys.held.move_direction = FORWARD
	var from: Vector3 = body_of(host_links, A_SEAT).global_position
	await step_ticks(20)
	assert_gt(
		body_of(host_links, A_SEAT).global_position.distance_to(from), 1.0,
		"metres the host's copy of A ran after a tapped lock",
	)


func test_a_lock_started_inside_a_blackout_still_locks_on_the_host() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(1)
	var dropped_before: int = a_wire.dropped
	@warning_ignore("missing_await")
	black_out(a_wire, 4)
	await step_ticks(2)
	a_keys.held.ability_held = true
	a_keys.tap_slot(ARMOR)
	await step_ticks(3)
	assert_ge(
		float(a_wire.dropped - dropped_before), 3.0,
		"the blackout dropped the press and the packet that repeats it",
	)
	var locked: bool = await until(
		func() -> bool: return power_of(host_links, A_SEAT).is_hit_immune(), 500
	)
	assert_true(locked, "the host locked A although the press itself never arrived")
	await step_ticks(20)
	assert_true(all_draw(A_SEAT, ARMOR), "the lock stands while held: %s" % str(drawn(A_SEAT)))
	assert_true(body_of(host_links, A_SEAT).is_movement_locked(), "the host holds A's body")
	a_keys.held.ability_held = false
	var ticks: int = await _ticks_until_all_none(60)
	assert_le(float(ticks), 30.0, "ticks from release until host, A and B all draw nothing")


func test_twenty_lock_hologram_lock_cycles_on_a_bad_line_end_clean() -> void:
	if not await stand_up(0.1, 40):
		return
	for _cycle: int in 20:
		await _press_and_watch_host(ARMOR, 10)
		await _press_and_watch_host(NONE, 1)
		await _press_and_watch_host(HOLOGRAM, 1)
		await _press_and_watch_host(ARMOR, 5)
		await _press_and_watch_host(NONE, 1)
	var ticks: int = await _ticks_until_all_none(240)
	print(
		"    20 cycles at 10%% loss, 40 ms: host ran %d lock(s), %d hologram(s); clean after %d tick(s)"
		% [_host_locks, _host_holograms, ticks]
	)
	assert_gt(float(a_wire.dropped), 0.0, "the line dropped packets: this run was lossy")
	assert_gt(float(_host_locks), 0.0, "the host ran armor locks during the cycles")
	assert_gt(float(_host_holograms), 0.0, "the host ran holograms during the cycles")
	assert_le(float(ticks), 120.0, "ticks after the last release until every machine draws nothing")
	await step_ticks(10)
	assert_eq_int(_shells_anywhere(), 0, "shells left on any machine after the cycles")
	for links: Array[PlayerNetLink] in [host_links, a_links, b_links]:
		assert_false(body_of(links, A_SEAT).is_movement_locked(), "the cycles left a copy of A held")
		assert_null(power_of(links, A_SEAT).get_decoy(), "the cycles left a hologram standing")


## Press [param which] (held, for the lock; NONE lets go) and count what the host starts meanwhile.
func _press_and_watch_host(which: int, ticks: int) -> void:
	var host_power: RunnerPower = power_of(host_links, A_SEAT)
	a_keys.held.ability_held = which == ARMOR
	if which != NONE:
		a_keys.tap_slot(which)
	for _tick: int in ticks:
		await step_ticks(1)
		var now: int = int(host_power.get_active())
		if now != _host_last and now == ARMOR:
			_host_locks += 1
		if now != _host_last and now == HOLOGRAM:
			_host_holograms += 1
		_host_last = now


func _on_corrected(metres: float, snapped: bool) -> void:
	_corrections += 1
	_worst_correction = maxf(_worst_correction, metres)
	if snapped:
		_snaps += 1


## Ticks until host, A and B all draw nothing for A's seat; [param limit] + 1 when they never do.
func _ticks_until_all_none(limit: int) -> int:
	for tick: int in limit:
		if all_draw(A_SEAT, NONE):
			return tick
		await step_ticks(1)
	return limit + 1


func _shells_anywhere() -> int:
	return (
		_live_nodes(host.get_parent(), "ArmorShell")
		+ _live_nodes(a.get_parent(), "ArmorShell")
		+ _live_nodes(b.get_parent(), "ArmorShell")
	)


## Nodes under [param root] whose name carries [param fragment] and that are not on their way out.
func _live_nodes(root: Node, fragment: String) -> int:
	var found: int = 0
	for node: Node in root.find_children("*%s*" % fragment, "", true, false):
		if not node.is_queued_for_deletion():
			found += 1
	return found
