extends TestCase
## A machine whose match scene stands after a power began draws that power as the others do, and
## stops drawing it when they do: all five, on a bot's body and on a client's, hell and marble.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const EARLY: int = 1
const LATE: int = 2
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const NONE: int = MatchRules.RunnerAbility.NONE
## Ticks for reliable events and the snapshots behind them to cross loopback and be drawn.
const CROSS_TICKS: int = 30

var _rig: RefCounted = null
## The slot whose body runs the power.
var _slot: int = 0
## The rules a test lengthened a power on, and the length they shipped with.
var _lengthened: MatchRules = null
var _shipped_seconds: float = 0.0


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _lengthened != null:
		_lengthened.ability_duration_seconds = _shipped_seconds
		_lengthened = null
	if _rig != null:
		_rig.close()
		_rig = null


## Host, an early client and a late one, plus a bot, in a round on [param map] with the host in
## the tower; the power will run on the early client's body or, with [param on_bot], the bot's.
func _start(map: StringName, on_bot: bool) -> bool:
	if not await _rig.connect_peers(self, 2):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().map_id = map
	var late: Array[int] = [LATE]
	if not await _rig.launch(4, 0, late):
		fail("the match never started")
		return false
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("the host never reached the round")
		return false
	await step_ticks(CROSS_TICKS)
	_lengthened = host.get_rules()
	_shipped_seconds = _lengthened.ability_duration_seconds
	_lengthened.ability_duration_seconds = 600.0
	_slot = 3 if on_bot else _rig.local_slot(EARLY)
	TestFixtures.pin_the_field(host, null)
	return assert_true(_rig.participant(HOST, _slot).is_running, "the body the power runs on is a living runner")


func _power(peer: int) -> RunnerPower:
	return RunnerPower.of(_rig.body(peer, _slot))


func _cats_drawn(peer: int) -> int:
	return 1 if _power(peer).get_cat_view() != null else 0


## What [param peer] has standing in its world for [param which] on the body's power.
func _draws(peer: int, which: int) -> bool:
	var power: RunnerPower = _power(peer)
	var body: PlayerController = _rig.body(peer, _slot)
	match which:
		SHIELD:
			return power.get_shield() != null
		HOLOGRAM:
			return power.get_hologram() != null
		ARMOR:
			# A mirror draws the lock; only the machines running the body hold it.
			return power.get_shell() != null
		CAMO:
			var mesh: MeshInstance3D = RunnerPower._avatar_mesh(body)
			var worn: BaseMaterial3D = mesh.material_override as BaseMaterial3D if mesh != null else null
			return worn != null and worn.albedo_color.is_equal_approx(RunnerPower.CAMO_COLOR)
		CAT:
			return _cats_drawn(peer) == 1
	return false


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


## Start [param which] on the host, bind the late machine under it, and hold it to what the others draw.
func _a_late_machine_draws(which: int, map: StringName, on_bot: bool) -> void:
	if not await _start(map, on_bot):
		return
	if which == ARMOR:
		# The lock lasts as long as its key is down: the body's owner holds it.
		var keys: BotIntentSource = (_rig.matches[EARLY].get_node("Player") as PlayerController).intent_source as BotIntentSource
		keys.command.ability_held = true
		var copy: PlayerController = _rig.body(HOST, _slot)
		if not await _rig.wait_for(func() -> bool: return copy.get_intent().ability_held):
			fail("the held key never reached the host")
			return
	if not assert_true(_power(HOST).activate(which as MatchRules.RunnerAbility), "the host starts the power"):
		return
	var early_has_it: bool = await _rig.wait_for(func() -> bool:
		return int(_power(EARLY).get_shown()) == which and _draws(EARLY, which))
	if not assert_true(early_has_it, "the machine already in the match draws it"):
		return
	# Long enough for a shield's runner or a hologram to have gone somewhere since it began.
	await step_ticks(CROSS_TICKS)
	if not await _rig.bind_late(LATE):
		fail("the late machine never bound")
		return
	var late_has_it: bool = await _rig.wait_for(func() -> bool:
		return int(_power(LATE).get_shown()) == which and _draws(LATE, which))
	assert_eq_int(int(_power(LATE).get_shown()), which, "the late machine shows the power running")
	assert_true(late_has_it, "and draws what it puts in the world")
	if not late_has_it:
		return
	await step_ticks(CROSS_TICKS)
	assert_eq_int(int(_power(HOST).get_active()), which, "the power is still running on the host")
	if which == SHIELD:
		var off: float = _power(LATE).get_shield().global_position.distance_to(_power(HOST).get_shield().global_position)
		assert_lt(off, 0.05, "the late machine's shield stands where the host's does")
	if which == HOLOGRAM:
		# The hologram runs on: one built where it began and never moved would be left behind.
		var ran: float = _power(HOST).get_decoy().global_position.distance_to(_rig.body(HOST, _slot).global_position)
		assert_gt(ran, 3.0, "the hologram has run on from its runner")
		# Each machine draws at its own playout clock: where the host had it in a world it sent.
		for machine: int in [EARLY, LATE]:
			var gap: float = _from_hosts_worlds(_power(machine).get_hologram().global_position)
			assert_lt(gap, 0.3, "machine %d's hologram is where the host's was (%.2f m off, %.1f m from its runner)" % [machine, gap, ran])
	# The host ends it: the late machine is left drawing nothing.
	if which == CAT:
		_power(HOST).state.cooking = true
		_power(HOST).state.remaining_ticks = 3
	else:
		_power(HOST).cancel()
	var over: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if int(_power(peer).get_shown()) != NONE or _draws(peer, which):
				return false
		return true)
	for peer: int in _rig.peer_count():
		assert_eq_int(int(_power(peer).get_shown()), NONE, "peer %d shows no power once the host's is over" % peer)
		assert_false(_draws(peer, which), "peer %d has nothing of it left in its world" % peer)
	assert_true(over, "every machine let go of it")


func test_a_late_machine_draws_a_running_shield_on_a_clients_body_hell() -> void:
	await _a_late_machine_draws(SHIELD, HELL, false)


func test_a_late_machine_draws_a_running_shield_on_a_bots_body_marble() -> void:
	await _a_late_machine_draws(SHIELD, MARBLE, true)


func test_a_late_machine_draws_a_running_hologram_on_a_clients_body_hell() -> void:
	await _a_late_machine_draws(HOLOGRAM, HELL, false)


func test_a_late_machine_draws_a_running_hologram_on_a_bots_body_marble() -> void:
	await _a_late_machine_draws(HOLOGRAM, MARBLE, true)


func test_a_late_machine_draws_a_running_armor_lock_on_a_clients_body_marble() -> void:
	await _a_late_machine_draws(ARMOR, MARBLE, false)


func test_a_late_machine_draws_a_running_armor_lock_on_a_clients_body_hell() -> void:
	await _a_late_machine_draws(ARMOR, HELL, false)


func test_a_late_machine_draws_a_running_camo_on_a_clients_body_hell() -> void:
	await _a_late_machine_draws(CAMO, HELL, false)


func test_a_late_machine_draws_a_running_camo_on_a_bots_body_marble() -> void:
	await _a_late_machine_draws(CAMO, MARBLE, true)


func test_a_late_machine_draws_a_held_cat_grenade_on_a_clients_body_marble() -> void:
	await _a_late_machine_draws(CAT, MARBLE, false)


func test_a_late_machine_draws_a_held_cat_grenade_on_a_bots_body_hell() -> void:
	await _a_late_machine_draws(CAT, HELL, true)


## The hologram's own power outlives it when the rifle shatters it: a machine that binds then is
## shown the power and no hologram, as the others are.
func test_a_late_machine_draws_no_hologram_that_was_shot_away_before_it_bound() -> void:
	if not await _start(HELL, true):
		return
	if not assert_true(_power(HOST).activate(HOLOGRAM as MatchRules.RunnerAbility), "the host starts the hologram"):
		return
	if not await _rig.wait_for(func() -> bool: return _power(EARLY).get_hologram() != null):
		fail("the machine already in the match never drew it")
		return
	RunnerPower.shatter(_power(HOST).get_decoy())
	if not await _rig.wait_for(func() -> bool: return _power(EARLY).get_hologram() == null):
		fail("the shot hologram never left the early machine")
		return
	if not await _rig.bind_late(LATE):
		fail("the late machine never bound")
		return
	await step_ticks(CROSS_TICKS * 2)
	assert_eq_int(int(_power(HOST).get_active()), HOLOGRAM, "the power still counts as running on the host")
	for peer: int in _rig.peer_count():
		assert_null(_power(peer).get_hologram(), "peer %d draws no hologram" % peer)
