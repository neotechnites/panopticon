extends "res://tests/support/net_power_wired_rig.gd"

## What a power leaves behind: nothing when its body is freed, one drawing per power on a client
## however the flags got there, and a hologram that is a target, never a runner, built once.

const NONE: int = MatchRules.RunnerAbility.NONE
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
## How late B draws other bodies in the re-press tests: a jittery line's buffer, in ticks.
const B_DELAY_TICKS: int = 12


func test_the_hosts_body_freed_under_its_shield_leaves_no_shield() -> void:
	if not await stand_up():
		return
	host_keys.tap_power(SHIELD)
	await until(func() -> bool: return all_draw(HOST_SEAT, SHIELD))
	assert_eq_int(_live_nodes(host.get_parent(), "BubbleShield"), 1, "the host raised one shield")
	_free_body(body_of(host_links, HOST_SEAT))
	await step_ticks(3)
	assert_eq_int(
		_live_nodes(host.get_parent(), "BubbleShield"), 0,
		"shields left on the host after the body that raised one was freed",
	)


func test_the_hosts_body_freed_while_its_hologram_runs_leaves_no_hologram() -> void:
	if not await stand_up():
		return
	host_keys.tap_power(HOLOGRAM)
	await until(func() -> bool: return all_draw(HOST_SEAT, HOLOGRAM))
	assert_eq_int(_decoys_under(host.get_parent()), 1, "the host sent out one hologram")
	_free_body(body_of(host_links, HOST_SEAT))
	await step_ticks(3)
	assert_eq_int(
		_decoys_under(host.get_parent()), 0,
		"holograms left on the host after the body that sent one was freed",
	)


func test_a_mirror_freed_under_its_shield_leaves_no_shield_on_that_client() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(SHIELD)
	await until(func() -> bool: return all_draw(A_SEAT, SHIELD))
	assert_eq_int(_live_nodes(b.get_parent(), "BubbleShield"), 1, "B drew A's shield")
	_free_body(body_of(b_links, A_SEAT))
	await step_ticks(3)
	assert_eq_int(
		_live_nodes(b.get_parent(), "BubbleShield"), 0,
		"shields left on B after its copy of the body under one was freed",
	)
	assert_eq_int(_live_nodes(host.get_parent(), "BubbleShield"), 1, "the host's shield stands")


func test_a_mirror_freed_while_its_hologram_runs_leaves_no_hologram_on_that_client() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(HOLOGRAM)
	await until(func() -> bool: return _holograms_under(b.get_parent()) == 1)
	assert_eq_int(_holograms_under(b.get_parent()), 1, "B drew A's hologram")
	_free_body(body_of(b_links, A_SEAT))
	await step_ticks(3)
	assert_eq_int(
		_holograms_under(b.get_parent()), 0,
		"holograms left on B after its copy of the body that sent one was freed",
	)
	# The host's hologram keeps moving: its positions must find nothing to build on B.
	await step_ticks(20)
	assert_eq_int(_holograms_under(b.get_parent()), 0, "holograms a late position rebuilt on B")


func test_a_presented_armor_lock_refuses_a_second_start() -> void:
	if not await stand_up():
		return
	var power: RunnerPower = power_of(b_links, A_SEAT)
	var body: PlayerController = body_of(b_links, A_SEAT)
	_present(power, ARMOR)
	var started: bool = TestFixtures.fire(power, MatchRules.RunnerAbility.ARMOR_LOCK)
	assert_false(started, "a press under a presented armor lock starts nothing")
	assert_eq_int(_live_nodes(body, "ArmorShell"), 1, "shells on the body while the lock is drawn")
	_present(power, NONE)
	assert_eq_int(_live_nodes(body, "ArmorShell"), 0, "shells on the body once the lock is over")


func test_a_presented_shield_refuses_a_second_start() -> void:
	if not await stand_up():
		return
	var power: RunnerPower = power_of(b_links, A_SEAT)
	_present(power, SHIELD)
	var started: bool = TestFixtures.fire(power, MatchRules.RunnerAbility.BUBBLE_SHIELD)
	assert_false(started, "a press under a presented shield starts nothing")
	assert_eq_int(
		_live_nodes(b.get_parent(), "BubbleShield"), 1, "shields on B while one is drawn"
	)
	_present(power, NONE)
	assert_eq_int(
		_live_nodes(b.get_parent(), "BubbleShield"), 0, "shields on B once the shield is over"
	)


func test_a_presented_camo_refuses_a_second_start_and_gives_the_skin_back() -> void:
	if not await stand_up():
		return
	var power: RunnerPower = power_of(b_links, A_SEAT)
	var mesh: MeshInstance3D = _skin_of(body_of(b_links, A_SEAT))
	if not assert_not_null(mesh, "the fixture body has a mesh for camo to tint"):
		return
	var worn: Material = mesh.material_override
	_present(power, CAMO)
	assert_true(mesh.material_override != worn, "presented camo tints the body")
	var started: bool = TestFixtures.fire(power, MatchRules.RunnerAbility.ACTIVE_CAMO)
	assert_false(started, "a press under presented camo starts nothing")
	_present(power, NONE)
	assert_same(mesh.material_override, worn, "the body wears what it wore before the camo")


func test_presenting_a_predicted_power_leaves_one_drawing_and_one_flag() -> void:
	if not await stand_up():
		return
	var power: RunnerPower = power_of(b_links, A_SEAT)
	var body: PlayerController = body_of(b_links, A_SEAT)
	assert_true(TestFixtures.fire(power, MatchRules.RunnerAbility.ARMOR_LOCK, false), "the lock starts on a press")
	power.sync_visuals(power.state)
	_present(power, ARMOR)
	assert_eq_int(_live_nodes(body, "ArmorShell"), 1, "shells after the host confirmed the lock")
	assert_eq_int(int(power.get_shown()), ARMOR, "the confirmed lock is drawn")
	_present(power, NONE)
	assert_eq_int(_live_nodes(body, "ArmorShell"), 0, "shells once the host says it is over")
	assert_eq_int(int(power.get_shown()), NONE, "nothing drawn once the host says it is over")
	assert_false(body.is_movement_locked(), "the body is free once the host says it is over")
	assert_true(TestFixtures.fire(power, MatchRules.RunnerAbility.BUBBLE_SHIELD, false), "a shield starts on a press")
	power.sync_visuals(power.state)
	_present(power, CAMO)
	assert_eq_int(
		_live_nodes(b.get_parent(), "BubbleShield"), 0,
		"shields left when the host ran a different power than the one predicted",
	)
	_present(power, NONE)


## [param power]'s body as a record says it stands: running [param which] (NONE: nothing), drawn.
func _present(power: RunnerPower, which: int) -> void:
	var record: PlayerState = PlayerState.new()
	record.tick = 1000
	record.ability = which
	record.power_active = which != NONE
	record.ability_end_tick = 1060 if which != NONE else 0
	record.anchor_position = power.body.global_position + Vector3.UP * RunnerPower.SHIELD_RISE if which == SHIELD else Vector3.ZERO
	power.take_record(record)
	power.sync_visuals(power.state)


func test_a_hologram_is_a_decoy_and_not_a_runner_on_every_machine() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(HOLOGRAM)
	var built: bool = await until(
		func() -> bool:
			return (
				power_of(host_links, A_SEAT).get_decoy() != null
				and power_of(host_links, A_SEAT).get_hologram() != null
				and power_of(a_links, A_SEAT).get_hologram() != null
				and power_of(b_links, A_SEAT).get_hologram() != null
			)
	)
	if not assert_true(built, "A's hologram stands on the host and is drawn on host, A and B"):
		return
	var decoy: PlayerController = power_of(host_links, A_SEAT).get_decoy()
	assert_false(decoy.is_in_group(MatchController.RUNNER_GROUP), "the host's hologram is listed as a runner")
	assert_true(decoy.is_in_group(RunnerPower.DECOY_GROUP), "the host's hologram is listed as a decoy")
	assert_null(PrisonerAvatar.of(decoy), "the host's hologram body draws nothing itself")
	for machine: NetSession in [a, b]:
		assert_eq_int(_decoys_under(machine.get_parent()), 0, "%s holds no hologram body to hit" % machine.get_parent().name)
	var listed: int = 0
	for node: Node in get_tree().get_nodes_in_group(MatchController.RUNNER_GROUP):
		if node.is_in_group(RunnerPower.DECOY_GROUP):
			listed += 1
	assert_eq_int(listed, 0, "decoys anywhere in the runner group")


func test_a_late_snapshot_builds_no_hologram_after_it_ended() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(HOLOGRAM)
	var up: bool = await until(func() -> bool: return all_draw(A_SEAT, HOLOGRAM))
	assert_true(up, "A's hologram ran: %s" % str(drawn(A_SEAT)))
	# A world the host sent while the hologram stood, to arrive again after it is over.
	var alive: WorldSnapshot = WorldSnapshot.new()
	alive.copy_from(host.replicator._newest())
	if not assert_true(alive.find_seat(A_SEAT).power_out, "the host's world carries the hologram"):
		return
	var over: bool = await until(
		func() -> bool:
			return (
				all_draw(A_SEAT, NONE)
				and power_of(a_links, A_SEAT).get_hologram() == null
				and power_of(b_links, A_SEAT).get_hologram() == null
			)
	)
	assert_true(over, "A's hologram ended on every machine")
	var no_events: Array[NetEvents.Entry] = []
	var late: PackedByteArray = NetCodec.pack_snapshot(alive, null, -1, no_events, NetCodec.SnapshotInfo.new())
	for machine: NetSession in [a, b]:
		assert_false(machine.replicator.receive_snapshot(late), "a client takes a world older than the one it holds")
	await step_ticks(10)
	assert_eq_int(
		_holograms_under(a.get_parent()) + _holograms_under(b.get_parent()), 0,
		"holograms on the clients after the power ended",
	)


func test_the_hosts_hologram_pressed_again_the_tick_the_last_ended_is_placed_once_on_b() -> void:
	await _repress_the_tick_it_ended(HOST_SEAT)


func test_a_clients_hologram_pressed_again_the_tick_the_last_ended_is_placed_once_on_b() -> void:
	await _repress_the_tick_it_ended(A_SEAT)


func test_powers_running_at_stand_down_come_down_quietly() -> void:
	if not await stand_up():
		return
	a_keys.held.ability_held = true
	a_keys.tap_power(ARMOR)
	host_keys.tap_power(HOLOGRAM)
	var up: bool = await until(
		func() -> bool: return all_draw(A_SEAT, ARMOR) and all_draw(HOST_SEAT, HOLOGRAM)
	)
	assert_true(up, "an armor lock and a hologram are running as the session comes down")
	assert_eq_int(_holograms_under(b.get_parent()), 1, "B is drawing the host's hologram")


func test_a_shield_and_a_held_cat_at_stand_down_come_down_quietly() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(CAT)
	host_keys.tap_power(SHIELD)
	var up: bool = await until(
		func() -> bool: return all_draw(A_SEAT, CAT) and all_draw(HOST_SEAT, SHIELD)
	)
	assert_true(up, "a held cat and a shield are running as the session comes down")
	a_keys.tap(&"cook_pressed")
	await step_ticks(10)
	assert_eq_int(drawn(A_SEAT)[0], CAT, "the cat is cooking as the session comes down")


## The owner of [param seat] presses 2, and again on the first tick its hologram is over. B draws
## the world a jitter buffer late, so the last hologram's ending is drawn after the new one is built.
func _repress_the_tick_it_ended(seat: int) -> void:
	b.get_settings().interpolation_delay_ticks = B_DELAY_TICKS
	if not await stand_up():
		return
	var keys: PressSource = host_keys if seat == HOST_SEAT else a_keys
	var owner_links: Array[PlayerNetLink] = host_links if seat == HOST_SEAT else a_links
	var owner_power: RunnerPower = power_of(owner_links, seat)
	var host_power: RunnerPower = power_of(host_links, seat)
	var b_power: RunnerPower = power_of(b_links, seat)
	# Past a connection's first seconds, so a client's press is not inside ENet's opening pass.
	await step_ticks(150)
	keys.tap_power(HOLOGRAM)
	var up: bool = await until(func() -> bool: return all_draw(seat, HOLOGRAM))
	assert_true(up, "the first hologram ran: %s" % str(drawn(seat)))
	var ended: bool = false
	for _tick: int in 240:
		await step_ticks(1)
		if int(owner_power.get_shown()) == NONE:
			ended = true
			break
	if not assert_true(ended, "the first hologram ended on its owner's machine"):
		return
	var old: HologramView = b_power.get_hologram()
	var old_id: int = old.get_instance_id() if old != null else 0
	keys.tap_power(HOLOGRAM)
	var built: Dictionary[int, bool] = {}
	for _tick: int in 30:
		await step_ticks(1)
		var now: HologramView = b_power.get_hologram()
		if now != null and now.get_instance_id() != old_id:
			built[now.get_instance_id()] = true
	var on_host: PlayerController = host_power.get_decoy()
	var on_b: HologramView = b_power.get_hologram()
	if not assert_not_null(on_host, "the host runs the second hologram"):
		return
	if not assert_not_null(on_b, "B draws the second hologram 30 ticks after the press"):
		return
	# B draws the world a buffer late: its hologram stands where the host's stood in the worlds it holds.
	var apart: float = INF
	for i: int in host.replicator._ring_count:
		var state: PlayerState = host.replicator._slot(i).find_seat(seat)
		if state != null and state.power_out:
			apart = minf(apart, on_b.global_position.distance_to(state.anchor_position))
	print("    second hologram: B is %.3f m from the host's at B's drawn time, built %d time(s)" % [apart, built.size()])
	assert_lt(apart, 0.5, "metres between B's copy of the second hologram and the host's, a buffer late")
	assert_eq_int(built.size(), 1, "times B built the second hologram")


func _free_body(body: PlayerController) -> void:
	body.get_parent().remove_child(body)
	body.queue_free()


## Live holograms under [param root].
func _decoys_under(root: Node) -> int:
	var found: int = 0
	for node: Node in get_tree().get_nodes_in_group(RunnerPower.DECOY_GROUP):
		if root.is_ancestor_of(node) and not node.is_queued_for_deletion():
			found += 1
	return found


## Holograms drawn under [param root].
func _holograms_under(root: Node) -> int:
	var found: int = 0
	for node: Node in root.find_children("*", "Node3D", true, false):
		if node is HologramView and not node.is_queued_for_deletion():
			found += 1
	return found


## Nodes under [param root] whose name carries [param fragment] and that are not on their way out.
func _live_nodes(root: Node, fragment: String) -> int:
	var found: int = 0
	for node: Node in root.find_children("*%s*" % fragment, "", true, false):
		if not node.is_queued_for_deletion():
			found += 1
	return found


## The mesh camo repaints: the avatar's, or the plain body mesh.
func _skin_of(body: PlayerController) -> MeshInstance3D:
	var avatar: PrisonerAvatar = body.get_node_or_null(^"Avatar") as PrisonerAvatar
	if avatar != null and avatar.mesh != null:
		return avatar.mesh
	return body.get_node_or_null(^"BodyMesh") as MeshInstance3D


func test_the_owners_own_hologram_is_built_once_and_goes_once() -> void:
	# A draws the world a jitter buffer late, so the record's hologram outlives the owner block's power.
	a.get_settings().interpolation_delay_ticks = B_DELAY_TICKS
	if not await stand_up():
		return
	var power: RunnerPower = power_of(a_links, A_SEAT)
	a_keys.tap_power(HOLOGRAM)
	var built: Dictionary[int, bool] = {}
	var gone_for: int = 0
	for _tick: int in 600:
		await step_ticks(1)
		var view: HologramView = power.get_hologram()
		if view != null:
			built[view.get_instance_id()] = true
			gone_for = 0
		elif not built.is_empty():
			gone_for += 1
			if gone_for > 60:
				break
	assert_false(built.is_empty(), "A drew its own hologram")
	# Its end is the owner block's before the record at the playout clock says so: never rebuilt between.
	assert_eq_int(built.size(), 1, "times A built its own hologram")


func test_a_power_presented_while_held_gives_way_to_the_owner_block() -> void:
	if not await stand_up():
		return
	var power: RunnerPower = power_of(a_links, A_SEAT)
	# Held between rounds, A's own body was drawn from an older record whose cat was still out.
	_present(power, CAT)
	assert_eq_int(int(power.get_shown()), CAT, "the record's cat is drawn while the body is mirrored")
	var owner_block: PredictedState = PredictedState.new()
	owner_block.capture(body_of(a_links, A_SEAT), null)
	owner_block.values.fill(0.0)
	power.state.restore(owner_block.values, PredictedState.POWER)
	await step_ticks(1)
	assert_eq_int(int(power.get_shown()), NONE, "once it predicts again, the host's exact state is what it shows")
	assert_null(power.get_cat_view(), "and no cat is drawn")
