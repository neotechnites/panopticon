extends TestCase
## Playtest ledger PT1-04, PT2-05, PT3-01: the five powers in the shipped match scene on real sockets,
## pressed by a client and by the host, seen by every peer, at two and four machines, on hell and marble.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const NONE: int = MatchRules.RunnerAbility.NONE
## Ticks for a press, its reliable events and the snapshots behind them to cross loopback and be drawn.
const CROSS_TICKS: int = 30

var _rig: RefCounted = null
## The machine pressing, and the seat its body holds.
var _presser: int = 0
var _slot: int = 0


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## [param peers] machines and one bot in a round on [param map]; [param presser] runs, another human guards.
func _start_round(peers: int, map: StringName, presser: int, late: Array[int] = []) -> bool:
	if not await _rig.connect_peers(self, peers - 1):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().map_id = map
	if not await _rig.launch(peers + 1, 1 if presser == HOST else 0, late):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.peer_count():
		if late.has(peer):
			continue
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
		assert_eq_string(String(controller.get_rules().map_id), String(map), "peer %d stands on the map asked for" % peer)
	await step_ticks(CROSS_TICKS)
	_presser = presser
	_slot = _rig.local_slot(presser)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, _slot))
	return assert_true(_rig.participant(HOST, _slot).is_running, "the presser is a living runner on the host")


## The keys of the pressing machine's own player.
func _keys() -> MoveIntent:
	var player: PlayerController = _rig.matches[_presser].get_node("Player") as PlayerController
	return (player.intent_source as BotIntentSource).command


## One tick of a number key, as a finger makes it; [param hold] leaves the power key down after it.
func _tap(which: int, hold: bool = false) -> void:
	var keys: MoveIntent = _keys()
	# From the top of a tick, so the body reads the key exactly once whatever was awaited before.
	await step_ticks(1)
	keys.ability_slot = which
	keys.ability_held = true
	await step_ticks(1)
	keys.ability_slot = 0
	keys.ability_held = hold


func _release() -> void:
	_keys().ability_held = false


func _power(peer: int) -> RunnerPower:
	return RunnerPower.of(_rig.body(peer, _slot))


## True once every machine draws [param which] on the presser's body; fails naming those that do not.
func _every_peer_shows(which: int, why: String) -> bool:
	var seen: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if int(_power(peer).get_shown()) != which:
				return false
		return true)
	if not seen:
		for peer: int in _rig.peer_count():
			assert_eq_int(int(_power(peer).get_shown()), which, "peer %d draws power %d %s" % [peer, which, why])
	return seen


## Every machine stops drawing a power within [param ticks]: ended by the key or the shot, not by its clock.
func _ends_within(ticks: int, why: String) -> bool:
	for _i: int in ticks:
		await step_ticks(1)
		var over: bool = true
		for peer: int in _rig.peer_count():
			over = over and int(_power(peer).get_shown()) == NONE
		if over:
			return true
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_power(peer).get_shown()), NONE, "peer %d draws no power %s" % [peer, why])
	return false


## The power stays up on every machine for [param ticks]: not one frame and gone.
func _stays_up(which: int, ticks: int) -> void:
	for _i: int in ticks / 5:
		await step_ticks(5)
		for peer: int in _rig.peer_count():
			assert_eq_int(int(_power(peer).get_shown()), which, "peer %d still draws power %d" % [peer, which])
		if is_failed():
			return


## What a rifle round flown at the presser from above stops on, on the host.
func _round_from_above() -> Node3D:
	var body: PlayerController = _rig.body(HOST, _slot)
	var centre: Vector3 = body.global_position + Vector3.UP * 0.9
	var hit: Dictionary = _rig.controller(HOST).rifle.call(&"_cast", centre + Vector3.UP * 7.0, centre)
	return hit.get("collider", null) as Node3D


## Land the host rifle's round on [param collider], as the rifle reports one.
func _land_on(collider: Node3D) -> void:
	var at: Vector3 = _rig.body(HOST, _slot).global_position + Vector3.UP
	_rig.controller(HOST).rifle.target_hit.emit(collider, at, Vector3.UP)


func _alive_everywhere(why: String) -> void:
	for peer: int in _rig.peer_count():
		var who: MatchParticipant = _rig.participant(peer, _slot)
		assert_true(who.is_running and not who.is_ghost, "peer %d: the presser is alive %s" % [peer, why])


## The cats [param peer] draws for the presser; the host also holds the real one.
func _cats_drawn(peer: int) -> int:
	return 1 if _power(peer).get_cat_view() != null else 0


func _host_cat() -> CatGrenade:
	return _power(HOST).get_cat()


## Blasts [param peer] is playing in its scene now.
func _blasts(peer: int) -> int:
	var played: int = 0
	for node: Node in _rig.controller(peer).get_parent().find_children("*", "AudioStreamPlayer3D", true, false):
		if (node as AudioStreamPlayer3D).stream == CatView.EXPLOSION_SOUND and not node.is_queued_for_deletion():
			played += 1
	return played


func _shield() -> void:
	var host: MatchController = _rig.controller(HOST)
	assert_same(host.resolve_participant(_round_from_above()), _rig.participant(HOST, _slot), "an open round from above lands on the presser")
	await _tap(SHIELD)
	if not await _every_peer_shows(SHIELD, "after the press"):
		return
	await _stays_up(SHIELD, 60)
	for peer: int in _rig.peer_count():
		var shield: StaticBody3D = _power(peer).get_shield()
		assert_true(shield != null and shield.is_inside_tree(), "peer %d has the bubble in its world" % peer)
	var stopped_on: Node3D = _round_from_above()
	assert_same(stopped_on, _power(HOST).get_shield(), "on the host the same round stops on the bubble")
	_land_on(stopped_on)
	await step_ticks(CROSS_TICKS)
	_alive_everywhere("behind the shield")
	if not await _every_peer_shows(NONE, "once the shield runs out"):
		return
	for peer: int in _rig.peer_count():
		assert_null(_power(peer).get_shield(), "peer %d: no bubble is left behind" % peer)
	assert_same(host.resolve_participant(_round_from_above()), _rig.participant(HOST, _slot), "and the round lands on the presser again")


## Metres from [param at] to the nearest place the host's worlds put the presser's hologram.
func _from_hosts_worlds(at: Vector3) -> float:
	var replicator: NetReplicator = (_rig.sessions[HOST] as NetSession).replicator
	var seat: int = PlayerNetLink.of(_rig.body(HOST, _slot)).seat_index
	var nearest: float = INF
	for i: int in replicator._ring_count:
		var state: PlayerState = replicator._slot(i).find_seat(seat)
		if state != null and state.power_out:
			nearest = minf(nearest, at.distance_to(state.anchor_position))
	return nearest


func _hologram() -> void:
	# The pinned field stands on the start line ahead; a hologram stops against a body like anyone else.
	for other: MatchParticipant in _rig.controller(HOST).get_participants():
		if other.index != _slot and other.is_running and other.body.movement_locked:
			other.body.global_position += Vector3.UP * 5.0
	await step_ticks(CROSS_TICKS)
	await _tap(HOLOGRAM)
	if not await _every_peer_shows(HOLOGRAM, "after the press") and int(_power(HOST).get_active()) != HOLOGRAM:
		return
	var all_have_one: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if _power(peer).get_hologram() == null:
				return false
		return _power(HOST).get_decoy() != null)
	for peer: int in _rig.peer_count():
		assert_true(all_have_one or _power(peer).get_hologram() != null, "peer %d draws the hologram in its world" % peer)
	if not all_have_one:
		return
	var decoy: PlayerController = _power(HOST).get_decoy()
	assert_true(decoy.is_in_group(RunnerPower.DECOY_GROUP), "the host's hologram is a target for the guard")
	assert_false(decoy.is_in_group(MatchController.RUNNER_GROUP), "and not a runner")
	var from: Vector3 = decoy.global_position
	# Short of the field it runs into on hell: the clients draw it from the playout clock on.
	await step_ticks(12)
	assert_gt(decoy.global_position.distance_to(from), 1.0, "the hologram runs on the host")
	assert_gt(decoy.velocity.length(), 1.0, "and is still running when the clients are asked")
	for peer: int in range(1, _rig.peer_count()):
		var copy: HologramView = _power(peer).get_hologram()
		if assert_not_null(copy, "peer %d still has it" % peer):
			# Drawn at the playout clock, like the bodies: where the host had it in a world it sent.
			assert_lt(_from_hosts_worlds(copy.global_position), 0.5, "peer %d draws it where the host had it, a buffer late" % peer)
			assert_eq_string(String(copy.get_clip()), String(HologramView.RUN_CLIP), "peer %d draws it running, not standing in the air pose" % peer)
	_land_on(decoy)
	# Counted in ticks, well inside the hologram's own time: it must go because it was shot.
	await step_ticks(2)
	assert_null(_power(HOST).get_decoy(), "the shot hologram shatters on the host")
	await step_ticks(CROSS_TICKS)
	assert_eq_int(int(_power(HOST).get_active()), HOLOGRAM, "with the power's time still running")
	for peer: int in _rig.peer_count():
		assert_null(_power(peer).get_hologram(), "peer %d: the shot hologram is gone" % peer)
	_alive_everywhere("after its hologram took the round")
	await _every_peer_shows(NONE, "once the hologram's time is up")


func _armor() -> void:
	var host: MatchController = _rig.controller(HOST)
	var who: MatchParticipant = _rig.participant(HOST, _slot)
	# Long enough that only letting go can be what ends it below.
	_power(HOST).rules.ability_duration_seconds = 30.0
	await _tap(ARMOR, true)
	if not await _every_peer_shows(ARMOR, "while the key is held"):
		_release()
		return
	await _stays_up(ARMOR, 45)
	for peer: int in _rig.peer_count():
		assert_not_null(_rig.body(peer, _slot).get_node_or_null("ArmorShell"), "peer %d draws the shell" % peer)
	assert_true(_power(HOST).is_hit_immune(), "the host holds the body immune")
	var held_at: Vector3 = who.body.global_position
	_rig.drive(_presser, Vector2(0.0, 1.0))
	_land_on(who.body)
	assert_false(host.apply_hit(who), "a rifle hit on the locked body is refused")
	await step_ticks(45)
	_alive_everywhere("under the armor lock")
	assert_lt(who.body.global_position.distance_to(held_at), 0.3, "the locked body does not walk on the host")
	_rig.drive(_presser, Vector2.ZERO)
	_release()
	if not await _ends_within(300, "within five seconds of the key being let go"):
		return
	for peer: int in _rig.peer_count():
		assert_null(_rig.body(peer, _slot).get_node_or_null("ArmorShell"), "peer %d: no shell is left behind" % peer)
	assert_false(_rig.body(HOST, _slot).is_movement_locked(), "the host frees the body")
	assert_false(_rig.body(_presser, _slot).is_movement_locked(), "and so does the machine that owns it")


## The material the drawn body wears whole, on [param peer].
func _skin(peer: int) -> Material:
	return _rig.avatar(peer, _slot).mesh.material_override


func _camo() -> void:
	var before: Array[Material] = []
	for peer: int in _rig.peer_count():
		before.append(_skin(peer))
	await _tap(CAMO)
	if not await _every_peer_shows(CAMO, "after the press"):
		return
	await _stays_up(CAMO, 60)
	assert_true(_power(HOST).is_camouflaged(), "the host hides the body from the guard's eye")
	for peer: int in _rig.peer_count():
		var worn: BaseMaterial3D = _skin(peer) as BaseMaterial3D
		if assert_not_null(worn, "peer %d paints the body" % peer):
			assert_true(worn.albedo_color.is_equal_approx(RunnerPower.CAMO_COLOR), "peer %d paints it the camo colour" % peer)
	if not await _every_peer_shows(NONE, "once the camo runs out"):
		return
	for peer: int in _rig.peer_count():
		assert_same(_skin(peer), before[peer], "peer %d: the body wears its own skin again" % peer)


## Carry the cat on every machine; false when it never showed.
func _carry_the_cat() -> bool:
	await _tap(CAT)
	if not await _every_peer_shows(CAT, "after the press"):
		return false
	var drawn: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if _cats_drawn(peer) != 1:
				return false
		return _host_cat() != null)
	assert_not_null(_host_cat(), "the host holds one cat")
	for peer: int in _rig.peer_count():
		assert_true(drawn or _cats_drawn(peer) == 1, "peer %d draws one cat, got %d" % [peer, _cats_drawn(peer)])
	return drawn


## The cat is gone and the power over on every machine.
func _the_cat_is_gone(why: String) -> void:
	var gone: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if _cats_drawn(peer) != 0:
				return false
		return _host_cat() == null)
	assert_null(_host_cat(), "the host's cat is gone %s" % why)
	for peer: int in _rig.peer_count():
		assert_true(gone or _cats_drawn(peer) == 0, "peer %d draws no cat %s, got %d" % [peer, why, _cats_drawn(peer)])
	await _every_peer_shows(NONE, why)


func _cat() -> void:
	if not await _carry_the_cat():
		return
	await _stays_up(CAT, 30)
	assert_false(_power(HOST).state.cooking, "an uncooked cat's fuse does not run")
	assert_almost_eq(_power(HOST).get_remaining(), CatGrenade.FUSE_SECONDS, 0.001, "and its fuse is whole")
	var body: PlayerController = _rig.body(HOST, _slot)
	var stood: Vector3 = body.global_position
	await step_ticks(1)
	_keys().cook_pressed = true
	await step_ticks(1)
	_keys().cook_pressed = false
	if not await _rig.wait_for(func() -> bool: return _host_cat() != null and _power(HOST).state.cooking):
		fail("the cook key never lit the cat on the host")
		return
	var far: Array[float] = [0.0]
	var heard: Array[bool] = []
	heard.resize(_rig.peer_count())
	heard.fill(false)
	var listen: Callable = func() -> void:
		for peer: int in _rig.peer_count():
			heard[peer] = heard[peer] or _blasts(peer) > 0
	if not await _rig.wait_for(func() -> bool:
		far[0] = maxf(far[0], body.global_position.distance_to(stood))
		listen.call()
		return _host_cat() == null):
		fail("the cooked cat never went off")
		return
	for _i: int in 40:
		await step_ticks(1)
		far[0] = maxf(far[0], body.global_position.distance_to(stood))
		listen.call()
	assert_gt(far[0], 0.5, "the blast in the hand throws its holder on the host")
	for peer: int in _rig.peer_count():
		assert_true(heard[peer], "peer %d plays the blast" % peer)
	await _the_cat_is_gone("after the blast")
	_alive_everywhere("after its own cat went off")
	# Then one thrown with the shove key.
	if not await _carry_the_cat():
		return
	var cat: CatGrenade = _host_cat()
	await step_ticks(1)
	_keys().shove_pressed = true
	if not await _rig.wait_for(func() -> bool: return is_instance_valid(cat) and cat.carrier == null):
		fail("the shove key never threw the cat on the host")
		return
	assert_true(_power(HOST).state.cooking, "a thrown cat is lit")
	await _the_cat_is_gone("after the thrown cat went off")


func _run(which: int, peers: int, map: StringName, presser: int) -> void:
	if not await _start_round(peers, map, presser):
		return
	match which:
		SHIELD: await _shield()
		HOLOGRAM: await _hologram()
		ARMOR: await _armor()
		CAMO: await _camo()
		CAT: await _cat()


# --- PT1-04 / PT2-05: a client's power runs on the host, works, and is drawn on every machine ---

func test_two_machines_hell_a_clients_shield() -> void: await _run(SHIELD, 2, HELL, 1)
func test_two_machines_hell_a_clients_hologram() -> void: await _run(HOLOGRAM, 2, HELL, 1)
func test_two_machines_hell_a_clients_armor_lock() -> void: await _run(ARMOR, 2, HELL, 1)
func test_two_machines_hell_a_clients_camo() -> void: await _run(CAMO, 2, HELL, 1)
func test_two_machines_hell_a_clients_cat() -> void: await _run(CAT, 2, HELL, 1)
func test_two_machines_marble_a_clients_shield() -> void: await _run(SHIELD, 2, MARBLE, 1)
func test_two_machines_marble_a_clients_hologram() -> void: await _run(HOLOGRAM, 2, MARBLE, 1)
func test_two_machines_marble_a_clients_armor_lock() -> void: await _run(ARMOR, 2, MARBLE, 1)
func test_two_machines_marble_a_clients_camo() -> void: await _run(CAMO, 2, MARBLE, 1)
func test_two_machines_marble_a_clients_cat() -> void: await _run(CAT, 2, MARBLE, 1)
func test_four_machines_hell_the_last_clients_shield() -> void: await _run(SHIELD, 4, HELL, 3)
func test_four_machines_hell_the_last_clients_hologram() -> void: await _run(HOLOGRAM, 4, HELL, 3)
func test_four_machines_hell_the_last_clients_armor_lock() -> void: await _run(ARMOR, 4, HELL, 3)
func test_four_machines_hell_the_last_clients_camo() -> void: await _run(CAMO, 4, HELL, 3)
func test_four_machines_hell_the_last_clients_cat() -> void: await _run(CAT, 4, HELL, 3)
func test_four_machines_marble_the_last_clients_shield() -> void: await _run(SHIELD, 4, MARBLE, 3)
func test_four_machines_marble_the_last_clients_hologram() -> void: await _run(HOLOGRAM, 4, MARBLE, 3)
func test_four_machines_marble_the_last_clients_armor_lock() -> void: await _run(ARMOR, 4, MARBLE, 3)
func test_four_machines_marble_the_last_clients_camo() -> void: await _run(CAMO, 4, MARBLE, 3)
func test_four_machines_marble_the_last_clients_cat() -> void: await _run(CAT, 4, MARBLE, 3)

# --- PT1-04: the host's power is drawn on every client ---

func test_two_machines_hell_the_hosts_shield() -> void: await _run(SHIELD, 2, HELL, HOST)
func test_two_machines_hell_the_hosts_hologram() -> void: await _run(HOLOGRAM, 2, HELL, HOST)
func test_two_machines_hell_the_hosts_armor_lock() -> void: await _run(ARMOR, 2, HELL, HOST)
func test_two_machines_hell_the_hosts_camo() -> void: await _run(CAMO, 2, HELL, HOST)
func test_two_machines_hell_the_hosts_cat() -> void: await _run(CAT, 2, HELL, HOST)
func test_two_machines_marble_the_hosts_shield() -> void: await _run(SHIELD, 2, MARBLE, HOST)
func test_two_machines_marble_the_hosts_hologram() -> void: await _run(HOLOGRAM, 2, MARBLE, HOST)
func test_two_machines_marble_the_hosts_armor_lock() -> void: await _run(ARMOR, 2, MARBLE, HOST)
func test_two_machines_marble_the_hosts_camo() -> void: await _run(CAMO, 2, MARBLE, HOST)
func test_two_machines_marble_the_hosts_cat() -> void: await _run(CAT, 2, MARBLE, HOST)
func test_four_machines_hell_the_hosts_shield() -> void: await _run(SHIELD, 4, HELL, HOST)
func test_four_machines_hell_the_hosts_hologram() -> void: await _run(HOLOGRAM, 4, HELL, HOST)
func test_four_machines_hell_the_hosts_armor_lock() -> void: await _run(ARMOR, 4, HELL, HOST)
func test_four_machines_hell_the_hosts_camo() -> void: await _run(CAMO, 4, HELL, HOST)
func test_four_machines_hell_the_hosts_cat() -> void: await _run(CAT, 4, HELL, HOST)
func test_four_machines_marble_the_hosts_shield() -> void: await _run(SHIELD, 4, MARBLE, HOST)
func test_four_machines_marble_the_hosts_hologram() -> void: await _run(HOLOGRAM, 4, MARBLE, HOST)
func test_four_machines_marble_the_hosts_armor_lock() -> void: await _run(ARMOR, 4, MARBLE, HOST)
func test_four_machines_marble_the_hosts_camo() -> void: await _run(CAMO, 4, MARBLE, HOST)
func test_four_machines_marble_the_hosts_cat() -> void: await _run(CAT, 4, MARBLE, HOST)


# --- PT3-01: a client on key 3 through everything a round does to its body ---

## The presser's body answers its own keys again on the host and on its own machine.
func _walks_again(why: String) -> void:
	var body: PlayerController = _rig.body(HOST, _slot)
	if not await _rig.wait_for(func() -> bool: return moves(body)):
		fail("the host never woke the presser %s" % why)
		return
	await step_ticks(CROSS_TICKS)
	await _every_peer_shows(NONE, why)
	assert_false(body.is_movement_locked(), "the host holds no lock on the body %s" % why)
	assert_false(_rig.body(_presser, _slot).is_movement_locked(), "nor does its own machine %s" % why)
	var from: Vector3 = body.global_position
	_rig.drive(_presser, Vector2(0.0, 1.0))
	await step_ticks(90)
	_rig.drive(_presser, Vector2.ZERO)
	assert_gt(body.global_position.distance_to(from), 1.0, "and the presser walks on the host %s" % why)


## Lock, be shot and shoved, let go; die; mash the key dead and held; lock again as a ghost.
func _lock_through_a_death(peers: int, map: StringName) -> void:
	if not await _start_round(peers, map, peers - 1):
		return
	var host: MatchController = _rig.controller(HOST)
	var who: MatchParticipant = _rig.participant(HOST, _slot)
	var bot: MatchParticipant = _rig.participant(HOST, peers)
	await _tap(ARMOR, true)
	if not await _every_peer_shows(ARMOR, "while the key is held"):
		return
	for _i: int in 3:
		_land_on(who.body)
		await step_ticks(5)
	# The bot stands behind the locked body and shoves it.
	bot.body.global_position = who.body.global_position + who.body.global_transform.basis.z * 1.0
	bot.body.rotation.y = who.body.rotation.y
	await step_ticks(2)
	host.apply_shove(bot)
	await step_ticks(CROSS_TICKS)
	_alive_everywhere("shot and shoved under the lock")
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_power(peer).get_shown()), ARMOR, "peer %d still draws the lock" % peer)
	_release()
	if not await _every_peer_shows(NONE, "after the key is let go"):
		return
	await step_ticks(CROSS_TICKS)
	# Shot for real, and the key hammered while the body is held dead.
	who.body.movement_locked = true
	who.body.velocity = Vector3.ZERO
	await step_ticks(CROSS_TICKS)
	_land_on(who.body)
	assert_true(who.is_ghost, "an unlocked body is converted by the same hit")
	# The test's hold for the shot is the test's to let go: no power frees a body the match holds.
	who.body.movement_locked = false
	for _i: int in 6:
		await _tap(ARMOR, true)
		await step_ticks(7)
	_release()
	if not await _rig.wait_for(func() -> bool:
		return not host.is_awaiting_respawn(who) and moves(who.body), 8000):
		fail("the host never put the dead presser back as a ghost")
		return
	await step_ticks(CROSS_TICKS)
	for peer: int in _rig.peer_count():
		assert_true(_rig.participant(peer, _slot).is_ghost, "peer %d holds the presser as a ghost" % peer)
	_release()
	await step_ticks(CROSS_TICKS)
	# As a ghost: whatever the host rules, every machine agrees, and letting go ends it.
	await _tap(ARMOR, true)
	await step_ticks(CROSS_TICKS)
	var ruled: int = int(_power(HOST).get_active())
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_power(peer).get_shown()), ruled, "peer %d draws what the host ruled for a ghost's key 3" % peer)
	_release()
	await _walks_again("as a ghost after the lock")


func test_two_machines_hell_a_client_locks_through_shots_a_shove_and_its_own_death() -> void:
	await _lock_through_a_death(2, HELL)


func test_four_machines_marble_a_client_locks_through_shots_a_shove_and_its_own_death() -> void:
	await _lock_through_a_death(4, MARBLE)


## The key held through the finale's kill beat and into the next round.
func _lock_through_a_finale(peers: int, map: StringName) -> void:
	if not await _start_round(peers, map, peers - 1):
		return
	var host: MatchController = _rig.controller(HOST)
	var finisher: MatchParticipant = _rig.participant(HOST, peers)
	await _tap(ARMOR, true)
	if not await _every_peer_shows(ARMOR, "while the key is held"):
		return
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return moves(finisher.body)):
		fail("the finisher never landed in the tower")
		return
	var round_before: int = host.get_round_number()
	# The bot finisher hunts the guard itself; the shove is forced only if it has not landed one yet.
	if float(host.get(&"_kill_beat_remaining")) <= 0.0 and host.get_round_number() == round_before:
		host.apply_shove(finisher)
	if not await _rig.wait_for(func() -> bool:
		return float(host.get(&"_kill_beat_remaining")) > 0.0 or host.get_round_number() > round_before, 8000):
		fail("the finisher never threw the guard out")
		_release()
		return
	# Hammer the key through the beat as well as hold it.
	while host.get_round_number() == round_before:
		await _tap(ARMOR, true)
		await step_ticks(9)
		if float(host.get(&"_kill_beat_remaining")) <= 0.0 and host.get_round_number() == round_before:
			await step_ticks(CROSS_TICKS)
			if host.get_round_number() == round_before:
				fail("the kill beat ended and the round did not turn over")
				_release()
				return
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_round_number() == round_before + 1):
			fail("peer %d never saw the next round" % peer)
			_release()
			return
	await step_ticks(CROSS_TICKS)
	# Still holding: the machines agree on whatever the host has in the new round.
	var ruled: int = int(_power(HOST).get_active())
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_power(peer).get_shown()), ruled, "peer %d draws what the host holds across the round" % peer)
	_release()
	TestFixtures.pin_the_field(host, _rig.participant(HOST, _slot))
	await _walks_again("in the round after the finale")
	_alive_everywhere("in the new round")


func test_two_machines_hell_a_client_holds_the_lock_through_the_kill_beat_and_the_next_round() -> void:
	await _lock_through_a_finale(2, HELL)


func test_four_machines_marble_a_client_holds_the_lock_through_the_kill_beat_and_the_next_round() -> void:
	await _lock_through_a_finale(4, MARBLE)


## A scored lap turns the round over with the key down.
func _lock_through_a_scored_round(peers: int, map: StringName) -> void:
	if not await _start_round(peers, map, peers - 1):
		return
	var host: MatchController = _rig.controller(HOST)
	_power(HOST).rules.ability_duration_seconds = 120.0
	await _tap(ARMOR, true)
	if not await _every_peer_shows(ARMOR, "while the key is held"):
		return
	var round_before: int = host.get_round_number()
	host.call(&"_score_and_restart", _rig.participant(HOST, peers))
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool:
			return controller.get_round_number() == round_before + 1 and controller.get_phase() == MatchController.Phase.ROUND, 8000):
			fail("peer %d never reached the next round" % peer)
			_release()
			return
	await step_ticks(CROSS_TICKS)
	# The key is still down and was not pressed again: nothing carries over from the last round.
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_power(peer).get_shown()), NONE, "peer %d: the new round starts with no power running" % peer)
		assert_null(_rig.body(peer, _slot).get_node_or_null("ArmorShell"), "peer %d: and no shell" % peer)
	_release()
	_presser = peers - 1
	_slot = _rig.local_slot(_presser)
	if _rig.participant(HOST, _slot).is_shooter:
		return
	TestFixtures.pin_the_field(host, _rig.participant(HOST, _slot))
	await _walks_again("in the round after a scored lap")


func test_two_machines_hell_a_client_holds_the_lock_across_a_scored_round() -> void:
	await _lock_through_a_scored_round(2, HELL)


func test_four_machines_marble_a_client_holds_the_lock_across_a_scored_round() -> void:
	await _lock_through_a_scored_round(4, MARBLE)


func test_a_client_that_leaves_mid_lock_leaves_no_lock_on_the_machines_that_stay() -> void:
	if not await _start_round(3, HELL, 1):
		return
	await _tap(ARMOR, true)
	if not await _every_peer_shows(ARMOR, "while the key is held"):
		return
	var slot: int = _slot
	_rig.sessions[1].leave()
	if not await _rig.wait_for(func() -> bool:
		return not _rig.participant(HOST, slot).is_human() and not _rig.participant(2, slot).is_human()):
		fail("the seat was never handed to a bot")
		return
	var stayed: bool = await _rig.wait_for(func() -> bool:
		for peer: int in [0, 2]:
			if int(RunnerPower.of(_rig.body(peer, slot)).get_shown()) != NONE:
				return false
		return true)
	for peer: int in [0, 2]:
		assert_true(stayed, "peer %d: the lock ends with the player who held it" % peer)
		assert_null(_rig.body(peer, slot).get_node_or_null("ArmorShell"), "peer %d: no shell is left on the bot" % peer)
	assert_false(_rig.body(HOST, slot).movement_locked, "and the bot that takes the seat can move")


# --- The cooldown, a hologram met by a late machine, a rule flipped mid-match ---

## A cooldown on the host's rules: the next press is refused everywhere, the owner is shown the wait, then it runs.
func _cooldown(peers: int, map: StringName) -> void:
	if not await _start_round(peers, map, peers - 1):
		return
	var rules: MatchRules = _power(HOST).rules
	rules.ability_duration_seconds = 1.0
	rules.ability_cooldown_seconds = 4.0
	await _tap(SHIELD)
	if not await _every_peer_shows(SHIELD, "after the press"):
		return
	if not await _every_peer_shows(NONE, "once the shield runs out"):
		return
	assert_gt(_power(HOST).get_cooldown_remaining(), 2.0, "the host counts the cooldown")
	var owner: RunnerPower = _power(_presser)
	if not await _rig.wait_for(func() -> bool: return owner.get_cooldown_remaining() > 0.0):
		fail("the machine that owns the power was never told the cooldown")
		return
	var presser: NetSession = _rig.sessions[_presser] as NetSession
	var pressed_on: int = presser.replicator.outbox.next_seq()
	await _tap(SHIELD)
	var host_session: NetSession = _rig.sessions[HOST] as NetSession
	if _presser != HOST and not await _rig.wait_for(func() -> bool:
		return host_session.replicator.stream_for(presser.get_local_peer_id()).get_ack() >= pressed_on):
		fail("the press inside the cooldown never reached the host")
		return
	for _i: int in 6:
		await step_ticks(5)
		assert_eq_int(int(_power(HOST).get_active()), NONE, "the host refuses a press inside the cooldown")
		for peer: int in _rig.peer_count():
			if peer != _presser:
				assert_eq_int(int(_power(peer).get_shown()), NONE, "peer %d draws nothing for the refused press" % peer)
	if not await _rig.wait_for(func() -> bool:
		return _power(HOST).get_cooldown_remaining() <= 0.0 and owner.get_cooldown_remaining() <= 0.0, 8000):
		fail("the cooldown never ran out on the host and the owner")
		return
	await _every_peer_shows(NONE, "when the cooldown is over")
	await _tap(SHIELD)
	await _every_peer_shows(SHIELD, "on the press after the cooldown")


func test_two_machines_hell_a_cooldown_refuses_the_next_press_and_is_shown_to_its_owner() -> void:
	await _cooldown(2, HELL)


func test_four_machines_marble_a_cooldown_refuses_the_next_press_and_is_shown_to_its_owner() -> void:
	await _cooldown(4, MARBLE)


func test_a_machine_that_binds_while_a_hologram_runs_draws_it_and_ends_with_none() -> void:
	if not await _start_round(3, HELL, HOST, [2]):
		return
	for other: MatchParticipant in _rig.controller(HOST).get_participants():
		if other.index != _slot and other.is_running and other.body.movement_locked:
			other.body.global_position += Vector3.UP * 5.0
	await _tap(HOLOGRAM)
	if not await _rig.wait_for(func() -> bool: return _power(HOST).get_decoy() != null and _power(1).get_hologram() != null):
		fail("the hologram never showed on the machines already in the match")
		return
	if not await _rig.bind_late(2):
		fail("the late machine never bound")
		return
	await step_ticks(CROSS_TICKS)
	var sees_it: bool = _power(2).get_hologram() != null
	if not await _rig.wait_for(func() -> bool: return int(_power(HOST).get_active()) == NONE, 8000):
		fail("the hologram never ended on the host")
		return
	await step_ticks(CROSS_TICKS)
	for peer: int in _rig.peer_count():
		assert_null(_power(peer).get_hologram(), "peer %d: no hologram is left when its time is up" % peer)
		assert_eq_int(int(_power(peer).get_shown()), NONE, "peer %d draws no power" % peer)
	assert_true(sees_it, "the machine that bound while it ran drew it")


## Flip the host's Crouch and Slide in its debug menu, as a hand on the two checkboxes does.
func _flip_movement_in_the_debug_menu(want: bool) -> void:
	var host: MatchController = _rig.controller(HOST)
	var menu: DebugMenu = (load("res://ui/debug_menu.tscn") as PackedScene).instantiate() as DebugMenu
	host.add_child(menu)
	menu.set("_edits", host)
	menu.call("_build_movement", host)
	var flipped: int = 0
	for found: Node in menu.find_children("*", "CheckBox", true, false):
		var check: CheckBox = found as CheckBox
		if check.text == "DEBUG_CROUCH" or check.text == "DEBUG_SLIDE":
			check.button_pressed = want
			flipped += 1
	assert_eq_int(flipped, 2, "the debug menu offers the two toggles")
	menu.queue_free()


## Every machine's copy of every body may crouch and slide, or may not, as the host's rules say.
func _movement_is(want: bool, why: String) -> void:
	for peer: int in _rig.peer_count():
		for who: MatchParticipant in _rig.controller(peer).get_participants():
			assert_true(
				who.body.slide_enabled == want and who.body.crouch_enabled == want,
				"peer %d, slot %d: crouch and slide are %s %s" % [peer, who.index, "on" if want else "off", why],
			)


func test_the_hosts_mid_match_crouch_and_slide_flip_reaches_a_client() -> void:
	if not await _start_round(2, HELL, 1):
		return
	var want: bool = not _rig.controller(HOST).get_rules().slide_enabled
	_movement_is(not want, "before the flip")
	_flip_movement_in_the_debug_menu(want)
	await step_ticks(CROSS_TICKS)
	assert_true(_rig.sessions[1].lobby.get_rules().slide_enabled == want, "the client holds the host's rules as edited")
	_movement_is(want, "after the flip")
	_flip_movement_in_the_debug_menu(not want)
	await step_ticks(CROSS_TICKS)
	_movement_is(not want, "after it is flipped back")


## The same line carries every rule: the run speed a client's own body predicts with follows the host's edit.
func test_the_hosts_mid_match_run_speed_edit_reaches_a_clients_bodies() -> void:
	if not await _start_round(2, MARBLE, 1):
		return
	var host: MatchController = _rig.controller(HOST)
	var shipped: float = host.get_rules().runner_speed_multiplier
	var faster: float = shipped + 0.5
	# What the debug menu's Run speed slider does.
	host.get_rules().runner_speed_multiplier = faster
	host.debug_refresh_pace()
	host.rules_edited.emit()
	await step_ticks(CROSS_TICKS)
	for peer: int in _rig.peer_count():
		assert_almost_eq(
			_rig.sessions[peer].lobby.get_rules().runner_speed_multiplier, faster, 0.001,
			"peer %d holds the host's rules as edited" % peer,
		)
		for who: MatchParticipant in _rig.controller(peer).get_participants():
			if who.is_running and not who.is_ghost:
				assert_almost_eq(who.body.run_speed_scale, faster, 0.001, "peer %d, slot %d runs at the edited speed" % [peer, who.index])
	# The scene's rules are one cached resource: the next test starts from the shipped number.
	host.get_rules().runner_speed_multiplier = shipped


func test_a_machine_that_binds_after_the_hosts_flip_runs_by_it() -> void:
	if not await _start_round(3, MARBLE, 1, [2]):
		return
	var want: bool = not _rig.controller(HOST).get_rules().slide_enabled
	_flip_movement_in_the_debug_menu(want)
	await step_ticks(CROSS_TICKS)
	if not await _rig.bind_late(2):
		fail("the late machine never bound")
		return
	await step_ticks(CROSS_TICKS)
	# The late machine's own word of the rules: its lobby's copy, which its scene read as it stood up.
	var told: MatchRules = _rig.sessions[2].lobby.get_rules()
	assert_true(told.slide_enabled == want and told.crouch_enabled == want, "the late machine's lobby holds the host's rules as edited")
	_movement_is(want, "on a machine that bound after the flip")


# --- PT2-05: what camo is for, in the shipped scene with the AI in the tower ---

func test_the_ai_guard_cannot_make_out_a_camouflaged_runner_past_the_camo_range() -> void:
	var scene: Node3D = TestFixtures.make_match()
	var controller: MatchController = scene.get_node("MatchController") as MatchController
	controller.rules = TestFixtures.match_rules()
	controller.rules.ability_duration_seconds = 2.0
	add_child(scene)
	var runner: MatchParticipant = controller.get_participants()[0]
	var keys: BotIntentSource = BotIntentSource.new()
	keys.shove_enabled = false
	runner.body.add_child(keys)
	runner.body.intent_source = keys
	controller.get_participants()[1].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(30)
	var guard: TowerShooter = controller.get_participants()[1].tower_brain
	if not assert_not_null(guard, "an AI holds the tower"):
		return
	guard.set_physics_process(false)
	var eye: Vector3 = guard.call(&"_eye_position")
	assert_gt(eye.distance_to(runner.body.global_position), RunnerPower.CAMO_VISIBLE_RANGE + 2.0, "the runner stands past the camo range")
	assert_true(bool(guard.call(&"_is_discernible", runner.body)), "a plain runner can be made out")
	keys.command.ability_slot = CAMO
	await step_ticks(1)
	keys.command.ability_slot = 0
	await step_ticks(2)
	assert_true(RunnerPower.of(runner.body).is_camouflaged(), "the camo is on")
	assert_false(bool(guard.call(&"_is_discernible", runner.body)), "the camouflaged runner cannot be made out from the tower")
	await step_seconds(2.5)
	assert_true(bool(guard.call(&"_is_discernible", runner.body)), "and can again when the camo runs out")
