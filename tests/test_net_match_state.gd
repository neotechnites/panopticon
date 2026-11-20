extends TestCase
## The match record in the snapshot (DESIGN Phase 5): what a mirror converges on, on real sockets.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
const LATE: int = 2
const CROSS_TICKS: int = 30
const LOSSY_TICKS: int = 120
## Metres a mirror's ragdoll may start from where the host held the body when it died.
const DEATH_SPOT_METRES: float = 0.05

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _start_round(clients: int, seats: int, late: Array[int] = [], loss: float = 0.0, lives: int = 1) -> bool:
	_rig.wire_loss = loss
	if not await _rig.connect_peers(self, clients):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().prisoner_lives = lives
	if not await _rig.launch(seats, 0, late):
		fail("the match never started")
		return false
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return false
	await step_ticks(CROSS_TICKS)
	return true


func _shoot(slot: int) -> void:
	var body: PlayerController = _rig.body(HOST, slot)
	_rig.controller(HOST).rifle.show_remote_hit(body, body.global_position + Vector3.UP, Vector3.BACK)


func _banner(peer: int) -> RoundTransitionScreen:
	for node: Node in _rig.matches[peer].find_children("*", "", true, false):
		if node is RoundTransitionScreen:
			return node as RoundTransitionScreen
	return null


## Respawn delay 0: a death and its respawn land in one tick, and the mirror's own ghost must run on.
func test_respawn_delay_zero_never_leaves_a_mirrors_ghost_frozen() -> void:
	if not await _start_round(1, 3):
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	host.get_ghost_profile().respawn_delay_seconds = 0.0
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	var respawns: Array[int] = [0]
	mirror.ghost_respawned.connect(func(p: MatchParticipant) -> void: respawns[0] += int(p.index == slot))
	_shoot(slot)
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	var back: bool = await _rig.wait_for(func() -> bool: return mine.is_ghost and moves(mine.body))
	assert_true(back, "the shot client's ghost runs again on its own machine at once")
	assert_eq_int(respawns[0], 1, "and the mirror placed it on the start line once")
	# A ghost already in the world dies and is back inside one tick: only the life counter shows it.
	assert_true(host.handle_fall(_rig.participant(HOST, slot)), "the host rules the ghost's fall")
	var again: bool = await _rig.wait_for(func() -> bool: return respawns[0] == 2)
	assert_true(again, "the mirror saw the fall and the respawn inside one interval (respawns %d)" % respawns[0])
	await step_ticks(CROSS_TICKS)
	assert_false(mirror.is_awaiting_respawn(mine), "nothing holds the mirror's ghost")
	assert_true(moves(mine.body), "and it runs")
	var host_body: PlayerController = _rig.body(HOST, slot)
	assert_lt(mine.body.global_position.distance_to(host_body.global_position), 1.5, "where the host has it")


## Bind [param peer] late with its round card live (it is inert headless), and wait for its match.
func _bind_late_shown(peer: int) -> bool:
	_rig.matches[peer] = _rig.call(&"_bind", _rig.sessions[peer])
	var banner: RoundTransitionScreen = _banner(peer)
	assert_not_null(banner, "the match scene has its round card")
	if banner != null:
		banner.headless_inert = false
	return await _rig.wait_for(func() -> bool: return _rig.net_match(peer).has_started())


## A late peer lands in a round silently, in the host's world: no round card, the tower as the host has it.
func test_a_late_peer_lands_in_the_round_silently_with_the_hosts_structure() -> void:
	var late: Array[int] = [LATE]
	if not await _start_round(2, 4, late):
		return
	var host: MatchController = _rig.controller(HOST)
	if not await _bind_late_shown(LATE):
		fail("the late peer never bound")
		return
	await step_ticks(CROSS_TICKS)
	var mirror: MatchController = _rig.controller(LATE)
	var banner: RoundTransitionScreen = _banner(LATE)
	assert_eq_int(mirror.get_round_number(), host.get_round_number(), "the late peer is in the host's round")
	assert_false(banner.is_showing(), "and is not shown the start of a round already running")
	assert_eq_int(int(mirror.is_tower_open()), int(host.is_tower_open()), "its tower stands as the host's does")
	# Presentation is only held for the landing: the next round is announced.
	host.take_seat(host.get_participants()[1])
	host.start_round()
	var shown: bool = await _rig.wait_for(func() -> bool: return banner.is_showing())
	assert_true(shown, "the next round's card is shown on the late peer")


## A late peer binding inside the tower fight has the tower open from its first record, as the host has it.
func test_a_late_peer_in_the_tower_fight_has_the_tower_open() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().tower_brawl = true
	var late: Array[int] = [LATE]
	if not await _rig.launch(4, -1, late):
		fail("launch")
		return
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.BRAWL):
		fail("no tower fight")
		return
	for participant: MatchParticipant in host.get_participants():
		participant.body.movement_locked = true
	if not await _bind_late_shown(LATE):
		fail("the late peer never bound")
		return
	var mirror: MatchController = _rig.controller(LATE)
	assert_true(mirror.is_tower_open(), "the late peer's tower is open as soon as its match stands")
	assert_false(_banner(LATE).is_showing(), "and it lands without a card")


## 20 % of snapshots lost: every lasting fact still arrives, lives, causes and clocks included.
func test_lasting_state_survives_snapshot_loss() -> void:
	if not await _start_round(1, 3, [] as Array[int], 0.2, 2):
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = 2
	host.get_ghost_profile().respawn_delay_seconds = 600.0
	TestFixtures.pin_the_field(host, null)
	_shoot(slot)
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	assert_eq_int(host_side.lives, 1, "the first hit spends a life on the host")
	var spent: bool = await _rig.wait_for(func() -> bool: return mine.lives == 1)
	assert_true(spent, "and on the mirror over the lossy line (lives %d)" % mine.lives)
	host.handle_fall(host_side)
	var dead: bool = await _rig.wait_for(func() -> bool: return mine.is_ghost and mirror.is_awaiting_respawn(mine))
	assert_true(dead, "a fall into lava converts it on the mirror")
	assert_eq_int(int(mine.death_cause), int(MatchParticipant.DeathCause.LAVA), "and names the lava")
	await step_ticks(LOSSY_TICKS)
	var left: float = mirror.get_respawn_hold_remaining(mine)
	var host_left: float = host.get_respawn_hold_remaining(host_side)
	assert_lt(absf(left - host_left), 0.5, "the respawn clock agrees with the host's: %.2f against %.2f" % [left, host_left])


## A mirror's ragdoll starts where its body died, at playout time: the DEATH event's start on the body
## the record shows held, not on a body still drawn running towards the spot.
func test_a_mirrors_ragdoll_starts_where_the_body_died() -> void:
	if not await _start_round(1, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = 3
	var host_body: PlayerController = _rig.body(HOST, slot)
	var running: bool = await _rig.wait_for(func() -> bool: return host_body.get_horizontal_speed() > 3.0)
	assert_true(running, "the bot is running when it is shot")
	_shoot(slot)
	var died_at: Vector3 = host_body.global_position
	var ragdoll: Node = _rig.ragdoll(CLIENT, slot)
	var mirror_body: PlayerController = _rig.body(CLIENT, slot)
	var limp: bool = false
	for _tick: int in 120:
		await step_ticks(1)
		if bool(ragdoll.call(&"is_active")):
			limp = true
			break
	assert_true(limp, "the mirror draws the kill limp")
	var off: float = mirror_body.global_position.distance_to(died_at)
	print("PROOF ragdoll start: %.4f m from the host's death spot" % off)
	assert_lt(off, DEATH_SPOT_METRES, "the ragdoll starts %.3f m from where the host's body died" % off)


## The match ends while a ghost waits on its respawn: the host holds every body, and no mirror respawns it.
func test_a_ghost_waiting_when_the_match_ends_is_not_respawned_on_a_mirror() -> void:
	if not await _start_round(1, 3):
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = 2
	host.get_ghost_profile().respawn_delay_seconds = 600.0
	TestFixtures.pin_the_field(host, null)
	var respawns: Array[int] = [0]
	mirror.ghost_respawned.connect(func(_p: MatchParticipant) -> void: respawns[0] += 1)
	_shoot(slot)
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	if not await _rig.wait_for(func() -> bool: return mine.is_ghost and mirror.is_awaiting_respawn(mine)):
		fail("the mirror never held the dead runner")
		return
	host.call(&"_resolve", MatchController.Outcome.WIN)
	host.call(&"_win_match", host.get_seat_participant())
	var over: bool = await _rig.wait_for(func() -> bool: return mirror.is_match_over())
	assert_true(over, "the mirror sees the match end")
	await step_ticks(CROSS_TICKS)
	assert_eq_int(respawns[0], 0, "no ghost was put back on the start line by the end of the match")
	assert_true(_rig.ragdoll(CLIENT, slot).is_active(), "the corpse still lies where it fell")


## A ghost held for its respawn changes nothing lasting: its stopped grace must not resend the record.
func test_a_held_ghost_does_not_resend_the_match_record() -> void:
	if not await _start_round(1, 3):
		return
	var host: MatchController = _rig.controller(HOST)
	host.get_ghost_profile().respawn_delay_seconds = 3.0
	TestFixtures.pin_the_field(host, null)
	var slot: int = 2
	_shoot(slot)
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	await step_ticks(CROSS_TICKS)
	var arrived: Array[int] = [0]
	var counting: Callable = func(_record: PackedByteArray) -> void: arrived[0] += 1
	var replicator: NetReplicator = (_rig.sessions[CLIENT] as NetSession).replicator
	replicator.match_arrived.connect(counting)
	var snapshots: Array[int] = [0]
	var counting_snapshots: Callable = func(_tick: int, _count: int) -> void: snapshots[0] += 1
	replicator.snapshot_received.connect(counting_snapshots)
	await step_ticks(90)
	replicator.match_arrived.disconnect(counting)
	replicator.snapshot_received.disconnect(counting_snapshots)
	assert_true(host.is_awaiting_respawn(host_side), "the ghost was held throughout")
	assert_gt(float(snapshots[0]), 20.0, "snapshots arrived (%d)" % snapshots[0])
	assert_le(float(arrived[0]), float(snapshots[0]) * 0.1,
		"the match record changed in %d of %d snapshots while nothing lasting did" % [arrived[0], snapshots[0]])


## The client's own respawn: control back on the host's release tick, then no pull back to the line, no flick.
## The release step itself carries the commands sent while held, which the host runs released.
func test_an_own_respawn_returns_control_at_the_hosts_release_without_a_snap() -> void:
	if not await _start_round(1, 3):
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	host.get_ghost_profile().respawn_delay_seconds = 0.5
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	host.call(&"_silence_brain", _rig.participant(HOST, slot))
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	_shoot(slot)
	if not await _rig.wait_for(func() -> bool: return not moves(host_side.body) and not moves(mine.body)):
		fail("the shot client was never held on both machines")
		return
	_rig.drive(CLIENT, Vector2(0.0, 1.0))
	var host_free: int = -1
	var mine_free: int = -1
	var worst_step: float = 0.0
	var fastest_host: float = 0.0
	var worst_turn: float = 0.0
	var last: Vector3 = mine.body.global_position
	var last_host: Vector3 = host_side.body.global_position
	var last_yaw: float = mine.body.rotation.y
	for tick: int in 240:
		await step_ticks(1)
		if host_free < 0 and moves(host_side.body):
			host_free = tick
		if mine_free < 0 and moves(mine.body):
			mine_free = tick
		var here: Vector3 = mine.body.global_position
		if mine_free >= 0 and tick > mine_free:
			worst_step = maxf(worst_step, here.distance_to(last))
			worst_turn = maxf(worst_turn, absf(angle_difference(mine.body.rotation.y, last_yaw)))
		if host_free >= 0 and tick > host_free:
			fastest_host = maxf(fastest_host, host_side.body.global_position.distance_to(last_host))
		last = here
		last_host = host_side.body.global_position
		last_yaw = mine.body.rotation.y
		if mine_free >= 0 and tick > mine_free + 60:
			break
	_rig.drive(CLIENT, Vector2.ZERO)
	if not assert_true(host_free >= 0 and mine_free >= 0, "the host released the ghost (%d) and the client ran it (%d)" % [host_free, mine_free]):
		return
	assert_le(float(mine_free - host_free), 4.0, "the client has control %d ticks after the host's release" % (mine_free - host_free))
	assert_lt(worst_step, fastest_host * 1.5 + 0.05,
		"no snap once running: worst step %.3f m in a tick against the host's fastest %.3f" % [worst_step, fastest_host])
	assert_lt(worst_turn, 0.05, "no camera flick: worst turn %.3f rad in a tick" % worst_turn)
