extends TestCase
## Death, ragdoll, ghost and finale as every peer sees them: the shipped match scene on real sockets.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
## Ticks for a reliable event and the snapshots behind it to cross loopback and be drawn.
const CROSS_TICKS: int = 30
## The same on a bad line: the runner compresses time fiftyfold, so 3 real ms each way is 150 ms of play.
const BAD_LINE_TICKS: int = 120
const BAD_LINE_LOSS: float = 0.1
const BAD_LINE_DELAY_MS: int = 3

var _rig: RefCounted = null
var _cross: int = CROSS_TICKS
var _bad_line: bool = false
## The guard's round speed for the match, m/s; 0 leaves the shipped shot.
var _shot_speed: float = 0.0


func before_each() -> void:
	_rig = Rig.new()
	_cross = CROSS_TICKS
	_bad_line = false
	_shot_speed = 0.0


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


## Host in the tower, one client and one bot on the ring, the round running on both machines.
func _start_round(clients: int = 1, seats: int = 3, guard_seat: int = 0, late: Array[int] = []) -> bool:
	if _bad_line:
		_rig.wire_loss = BAD_LINE_LOSS
		_rig.wire_delay_ms = BAD_LINE_DELAY_MS
		_cross = BAD_LINE_TICKS
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	# A finale kill must turn the round over, not end the match.
	_rig.settings().rounds_to_win_match = 3
	if _shot_speed > 0.0:
		_rig.settings().guard_projectile_speed = _shot_speed
	if not await _rig.launch(seats, guard_seat, late):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.sessions.size():
		if late.has(peer):
			continue
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(_cross)
	return true


func test_a_killed_client_runs_again_as_a_ghost_on_its_own_machine() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(host, host.get_participants()[slot])
	assert_true(host.convert_participant(host.get_participants()[slot]), "the host converts the client's runner")
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	if not await _rig.wait_for(func() -> bool: return mine.is_ghost):
		fail("the client never learned it died")
		return
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	if not await _rig.wait_for(
		func() -> bool: return host_side.is_ghost and host_side.body.is_physics_processing()
	):
		fail("the host never woke the ghost")
		return
	await step_ticks(_cross)
	assert_true(mine.body.is_physics_processing(), "the client's own ghost is simulated again after its respawn")
	var from: Vector3 = host_side.body.global_position
	_rig.drive(CLIENT, Vector2(0.0, 1.0))
	await step_ticks(90)
	assert_gt(host_side.body.global_position.distance_to(from), 1.0, "and the ghost the client drives moves on the host")


## Every material the drawn body wears, surface by surface, as [param peer] holds it.
func _worn(peer: int, slot: int) -> Array[Material]:
	var mesh: MeshInstance3D = _rig.avatar(peer, slot).mesh
	var worn: Array[Material] = [mesh.material_override]
	for index: int in mesh.mesh.get_surface_count():
		worn.append(mesh.get_surface_override_material(index))
	return worn


## A rifle hit on [param slot], landed on the host as the rifle lands one.
func _shoot(slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	var body: PlayerController = _rig.body(HOST, slot)
	host.rifle.show_remote_hit(body, body.global_position + Vector3.UP, Vector3.BACK)


## True once every peer draws [param slot] limp; fails naming the peers that do not.
func _every_peer_sees_limp(slot: int, why: String) -> bool:
	var seen: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.ragdoll(peer, slot).is_active():
				return false
		return true)
	if not seen:
		for peer: int in _rig.peer_count():
			assert_true(_rig.ragdoll(peer, slot).is_active(), "peer %d draws slot %d limp %s" % [peer, slot, why])
	return seen


## The host's ghost in [param slot] is back in the world, and the peers have heard.
func _respawned(slot: int) -> bool:
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool:
		return host_side.is_ghost and not host.is_awaiting_respawn(host_side) and host_side.body.is_physics_processing()
	):
		fail("the host never put slot %d back as a ghost" % slot)
		return false
	await step_ticks(_cross)
	return true


## One rifle kill of [param slot], watched from death to respawn on every peer.
func _watch_a_rifle_kill(slot: int) -> void:
	var before: Array = []
	for peer: int in _rig.peer_count():
		before.append(_worn(peer, slot))
	_shoot(slot)
	assert_true(_rig.participant(HOST, slot).is_ghost, "the hit converts slot %d on the host" % slot)
	# The ghost included, its chase called off: a chasing ghost's shove is a catch, and a swap ends the watch early.
	TestFixtures.pin_the_field(_rig.controller(HOST), null)
	_rig.controller(HOST).call(&"_silence_brain", _rig.participant(HOST, slot))
	if not await _every_peer_sees_limp(slot, "after the rifle kill"):
		return
	await step_ticks(60)
	for peer: int in _rig.peer_count():
		assert_true(_rig.ragdoll(peer, slot).is_active(), "peer %d still draws slot %d limp a second later" % [peer, slot])
		assert_true(_rig.participant(peer, slot).is_ghost, "peer %d holds slot %d as a ghost" % [peer, slot])
		var worn: Array[Material] = _worn(peer, slot)
		for index: int in worn.size():
			assert_same(worn[index], before[peer][index], "peer %d: the corpse of slot %d wears what it wore alive (surface %d)" % [peer, slot, index - 1])
	if not await _respawned(slot):
		return
	for peer: int in _rig.peer_count():
		assert_false(_rig.ragdoll(peer, slot).is_active(), "peer %d: slot %d is no corpse after its respawn" % [peer, slot])
		assert_false(_lies_dead(peer, slot), "peer %d: slot %d stands at the start line, not in the death pose" % [peer, slot])
		var colour: Color = _rig.controller(peer).get_body_color(_rig.participant(peer, slot))
		assert_lt(colour.a, 1.0, "peer %d: the respawned ghost in slot %d wears the ghost colour" % [peer, slot])


## Whether [param peer] draws [param slot] dead: limp, or on the death clip.
func _lies_dead(peer: int, slot: int) -> bool:
	var avatar: PrisonerAvatar = _rig.avatar(peer, slot)
	return _rig.ragdoll(peer, slot).is_active() or bool(avatar.get(&"_dead"))


func test_a_shot_client_goes_limp_on_every_peer_and_stands_again() -> void:
	if not await _start_round(2, 4):
		return
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, slot))
	await _watch_a_rifle_kill(slot)


func test_a_shot_bot_goes_limp_on_every_peer_and_stands_again() -> void:
	if not await _start_round(2, 4):
		return
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, 3))
	await _watch_a_rifle_kill(3)


func test_a_fallen_runner_plays_dead_on_every_peer_and_stands_again_without_moving() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	assert_true(host.handle_fall(_rig.participant(HOST, slot)), "the host rules the lava death")
	var dead: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _lies_dead(peer, slot):
				return false
		return true)
	for peer: int in _rig.peer_count():
		assert_true(dead or _lies_dead(peer, slot), "peer %d draws the lava death" % peer)
		assert_false(_rig.ragdoll(peer, slot).is_active(), "peer %d: a lava death is the clip, not a limp body" % peer)
	if not await _respawned(slot):
		return
	for peer: int in _rig.peer_count():
		assert_false(_lies_dead(peer, slot), "peer %d: the respawned ghost stands, though it has not moved" % peer)


func test_a_killed_client_is_shown_its_death_and_its_countdown() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	var screen: MatchDeathScreen = _rig.matches[CLIENT].get_node("DeathScreen") as MatchDeathScreen
	var view: FxSpectatorView = _rig.matches[CLIENT].get_node("SpectatorView") as FxSpectatorView
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	assert_false(screen.is_showing(), "no death screen on a living client")
	_shoot(slot)
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	if not await _rig.wait_for(func() -> bool: return screen.is_showing() and view.is_active()):
		assert_true(screen.is_showing(), "the client is shown the death screen")
		assert_true(view.is_active(), "the client is given the death camera")
		return
	assert_eq_int(
		int(mirror.get_spectating_state(mine)), int(MatchController.Spectating.RESPAWNING),
		"the client knows it is waiting on a respawn"
	)
	assert_eq_int(int(mine.death_cause), int(MatchParticipant.DeathCause.SHOT), "and that it was shot")
	var first: float = mirror.get_respawn_hold_remaining(mine)
	assert_gt(first, 0.0, "the countdown has time on it")
	await step_ticks(30)
	assert_lt(mirror.get_respawn_hold_remaining(mine), first, "and it runs down")
	if not await _respawned(slot):
		return
	assert_false(screen.is_showing(), "the death screen hands back at the respawn")
	assert_false(view.is_active(), "and so does the camera")


func test_a_shot_host_goes_limp_on_every_peer_and_stands_again() -> void:
	if not await _start_round(2, 4, 1):
		return
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, 0))
	await _watch_a_rifle_kill(0)


func test_a_client_is_told_what_killed_it() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	assert_true(host.handle_fall(_rig.participant(HOST, 1)), "the host rules a lava death")
	assert_true(host.handle_fall(_rig.participant(HOST, 2), true), "and a fall into the pit")
	if not await _rig.wait_for(func() -> bool:
		return _rig.participant(2, 1).is_ghost and _rig.participant(1, 2).is_ghost and _rig.participant(1, 1).is_ghost):
		fail("the deaths never reached the clients")
		return
	for peer: int in [1, 2]:
		assert_eq_int(int(_rig.participant(peer, 1).death_cause), int(MatchParticipant.DeathCause.LAVA), "peer %d knows slot 1 died in lava" % peer)
		assert_eq_int(int(_rig.participant(peer, 2).death_cause), int(MatchParticipant.DeathCause.FELL), "peer %d knows slot 2 fell" % peer)


func test_a_client_ghost_that_falls_again_is_held_and_shown_its_respawn() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, slot))
	_shoot(slot)
	if not await _respawned(slot):
		return
	var mine: MatchParticipant = _rig.participant(CLIENT, slot)
	assert_true(mine.body.is_physics_processing(), "the client's ghost is running")
	assert_true(host.handle_fall(_rig.participant(HOST, slot)), "the host rules the ghost's fall into lava")
	if not await _rig.wait_for(func() -> bool: return mirror.is_awaiting_respawn(mine)):
		fail("the client was never told its ghost fell: no hold, no countdown, no death view")
		return
	assert_false(mine.body.is_physics_processing(), "the client's ghost is held where it fell")
	assert_eq_int(int(mine.death_cause), int(MatchParticipant.DeathCause.LAVA), "and the client knows it was the lava")
	if not await _respawned(slot):
		return
	assert_false(mirror.is_awaiting_respawn(mine), "the hold ends at the respawn")
	assert_true(mine.body.is_physics_processing(), "and the client's ghost runs again")


func test_a_late_peer_finds_a_ghost_already_back_in_the_world() -> void:
	if not await _start_round(2, 4, 0, [2]):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	_shoot(1)
	_shoot(2)
	if not await _respawned(2):
		return
	if not await _rig.bind_late(2):
		fail("the late peer never bound")
		return
	await step_ticks(_cross)
	var late: MatchController = _rig.controller(2)
	for slot: int in [1, 2]:
		var ghost: MatchParticipant = _rig.participant(2, slot)
		assert_true(ghost.is_ghost, "the late peer holds slot %d as a ghost" % slot)
		assert_false(late.is_awaiting_respawn(ghost), "and not as one still waiting on a respawn that already landed")
		assert_lt(late.get_body_color(ghost).a, 1.0, "wearing the ghost colour")
	assert_true(_rig.body(2, 2).is_physics_processing(), "the late peer's own ghost is simulated")
	assert_false(_lies_dead(2, 1), "and nobody lies dead at the start line")


## The tower's colliders and their layers, as [param peer] holds them.
func _tower_layers(peer: int) -> Dictionary:
	var layers: Dictionary = {}
	var tower: Node = _rig.controller(peer).call(&"_tower_node")
	for node: Node in tower.find_children("*", "StaticBody3D", true, false):
		layers[node] = (node as StaticBody3D).collision_layer
	return layers


## The host arms [param finisher_slot], who shoves the guard out; watched to the next round on every peer.
func _watch_a_finale(guard_slot: int, finisher_slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, finisher_slot))
	var towers: Array[Dictionary] = []
	for peer: int in _rig.peer_count():
		towers.append(_tower_layers(peer))
	var finisher: MatchParticipant = _rig.participant(HOST, finisher_slot)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return finisher.body.is_physics_processing()):
		fail("the finisher never landed in the tower")
		return
	for peer: int in _rig.peer_count():
		var mirrored: MatchParticipant = _rig.participant(peer, finisher_slot)
		if not await _rig.wait_for(func() -> bool: return mirrored.is_finisher):
			fail("peer %d never learned who the finisher is" % peer)
			return
	var round_before: int = host.get_round_number()
	var beat_ticks: int = int(host.get_rules().kill_beat_seconds * SIM_HZ)
	assert_same(host.apply_shove(finisher), _rig.participant(HOST, guard_slot), "the finisher's shove takes the guard")
	if not await _every_peer_sees_limp(guard_slot, "on the finale shove"):
		return
	var held: Array[Vector3] = []
	for peer: int in _rig.peer_count():
		held.append(_rig.body(peer, guard_slot).global_position)
	# Most of the beat, measured on the host's clock: the guard stays down and both bodies stay put.
	var until: float = host.get_rules().kill_beat_seconds * 0.25
	while float(host.get(&"_kill_beat_remaining")) > until:
		await step_ticks(4)
		for peer: int in _rig.peer_count():
			if float(host.get(&"_kill_beat_remaining")) <= 0.0:
				break
			assert_true(_rig.ragdoll(peer, guard_slot).is_active(), "peer %d: the guard stays limp through the beat" % peer)
			assert_true(_rig.body(peer, guard_slot).movement_locked, "peer %d: the guard has no controls in the beat" % peer)
			assert_true(_rig.body(peer, finisher_slot).movement_locked, "peer %d: nor has the finisher" % peer)
			assert_false(_rig.body(peer, guard_slot).is_physics_processing(), "peer %d: the guard's capsule is held" % peer)
			assert_lt(_rig.body(peer, guard_slot).global_position.distance_to(held[peer]), 0.5, "peer %d: and it has not fallen out of the tower" % peer)
			assert_false(_rig.controller(peer).is_tower_open(), "peer %d: the tower stays solid" % peer)
		if is_failed():
			return
	assert_gt(float(beat_ticks), 0.0, "the shipped rules hold a kill beat")
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_round_number() == round_before + 1):
			fail("peer %d never saw the next round" % peer)
			return
	await step_ticks(_cross)
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_same(controller.get_seat_participant(), _rig.participant(peer, finisher_slot), "peer %d: the finisher holds the tower" % peer)
		assert_false(_rig.ragdoll(peer, guard_slot).is_active(), "peer %d: the thrown guard is no corpse in the new round" % peer)
		assert_false(_lies_dead(peer, guard_slot), "peer %d: and stands on the ring" % peer)
		assert_false(_rig.body(peer, guard_slot).movement_locked, "peer %d: the old guard has its controls back" % peer)
		assert_false(_rig.body(peer, finisher_slot).movement_locked, "peer %d: and so has the new one" % peer)
		assert_true(_rig.participant(peer, guard_slot).is_running, "peer %d: the old guard runs this round" % peer)
		var layers: Dictionary = _tower_layers(peer)
		for wall: Node in layers:
			assert_eq_int(int(layers[wall]), int(towers[peer][wall]), "peer %d: %s collides as it did" % [peer, wall.name])
	for peer: int in _rig.peer_count():
		var own: int = _rig.local_slot(peer)
		assert_true(_rig.body(peer, own).is_physics_processing(), "peer %d simulates its own body in the new round" % peer)


func test_a_client_guard_thrown_by_the_host_stays_down_for_the_beat() -> void:
	if not await _start_round(2, 4, 1):
		return
	await _watch_a_finale(1, 0)


func test_a_host_guard_thrown_by_a_client_stays_down_for_the_beat() -> void:
	if not await _start_round(2, 4, 0):
		return
	await _watch_a_finale(0, 1)


func test_a_bot_guard_thrown_by_a_bot_is_seen_by_every_peer() -> void:
	if not await _start_round(2, 5, 3):
		return
	await _watch_a_finale(3, 4)


func test_a_shot_client_goes_limp_on_every_peer_over_a_bad_line() -> void:
	_bad_line = true
	if not await _start_round(2, 4):
		return
	var slot: int = _rig.local_slot(CLIENT)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, slot))
	# Running when it is hit, so snapshots still in flight carry the run past the death.
	_rig.drive(CLIENT, Vector2(0.0, 1.0))
	await step_ticks(_cross)
	await _watch_a_rifle_kill(slot)


func test_a_running_bot_shot_over_a_bad_line_goes_limp_on_every_peer() -> void:
	_bad_line = true
	if not await _start_round(2, 4):
		return
	await step_ticks(_cross)
	TestFixtures.pin_the_field(_rig.controller(HOST), _rig.participant(HOST, 3))
	await _watch_a_rifle_kill(3)


func test_a_finale_over_a_bad_line_holds_on_every_peer() -> void:
	_bad_line = true
	if not await _start_round(2, 4, 1):
		return
	await _watch_a_finale(1, 0)


## Stand [param victim_slot] a pace in front of [param shover_slot] on the host, both still.
func _stand_in_front(shover_slot: int, victim_slot: int) -> void:
	var shover: PlayerController = _rig.body(HOST, shover_slot)
	var victim: PlayerController = _rig.body(HOST, victim_slot)
	var forward: Vector3 = -shover.global_transform.basis.z
	forward.y = 0.0
	victim.global_position = shover.global_position + forward.normalized() * 1.0
	victim.velocity = Vector3.ZERO


## Every peer draws [param victim_slot] flopping and nobody else, then sees it get up.
func _watch_a_shove(shover_slot: int, victim_slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	_stand_in_front(shover_slot, victim_slot)
	await step_ticks(_cross)
	assert_same(
		host.apply_shove(_rig.participant(HOST, shover_slot)), _rig.participant(HOST, victim_slot),
		"the host lands the shove on slot %d" % victim_slot
	)
	var flopped: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.avatar(peer, victim_slot).is_flopping():
				return false
		return true)
	for peer: int in _rig.peer_count():
		assert_true(flopped or _rig.avatar(peer, victim_slot).is_flopping(), "peer %d draws the shoved body flop" % peer)
		for slot: int in host.get_participants().size():
			if slot != victim_slot:
				assert_false(_rig.avatar(peer, slot).is_flopping(), "peer %d: slot %d was not shoved and does not flop" % [peer, slot])
	var up: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if _rig.avatar(peer, victim_slot).is_flopping():
				return false
		return true)
	assert_true(up, "and every peer sees it get up")


func test_a_shoved_runner_flops_on_every_peer() -> void:
	if not await _start_round(2, 4):
		return
	TestFixtures.pin_the_field(_rig.controller(HOST), null)
	# A client shoves the other client; then the bot is shoved by a client.
	await _watch_a_shove(1, 2)
	await _watch_a_shove(2, 3)


func test_a_body_shoved_in_the_hub_flops_on_every_peer() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("the loopback handshake did not complete")
		return
	_rig.bind_hubs()
	await step_ticks(_cross)
	for peer: int in _rig.peer_count():
		assert_eq_int(_rig.controller(peer).get_participants().size(), 3, "peer %d stands three people in the hub" % peer)
	if is_failed():
		return
	# The host shoves a client, a client shoves the host, a client shoves the other client.
	await _watch_a_shove(0, 1)
	await _watch_a_shove(1, 0)
	await _watch_a_shove(2, 1)


## Metres a client's replayed round may stray from the path the host's round flew.
const ARC_TOLERANCE_METRES: float = 0.3
## Shots the arc test may take to get one clear of the tower, and the ticks of flight that counts as clear.
const SHOT_ATTEMPTS: int = 8
const LONG_FLIGHT_TICKS: int = 30


func test_a_dropped_shot_lands_on_a_client_where_the_host_landed_it() -> void:
	# The shipped shot is instant; the arc belongs to a match played with a travelling round.
	_shot_speed = 60.0
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	var rifle: Rifle = host.rifle
	if not assert_true(rifle.is_travelling_shot(), "the guard's shot travels, so it has an arc to replay"):
		return
	_rig.body(HOST, 0).head.rotation.x = 0.0
	await step_ticks(_cross)
	var host_end: Array[Vector3] = []
	var client_ends: Dictionary = {}
	rifle.missed.connect(func(end_point: Vector3) -> void: host_end.append(end_point))
	rifle.target_hit.connect(func(_c: Node3D, at: Vector3, _n: Vector3) -> void: host_end.append(at))
	for peer: int in range(1, _rig.peer_count()):
		var mirror_rifle: Rifle = _rig.controller(peer).rifle
		client_ends[peer] = []
		mirror_rifle.missed.connect(func(end_point: Vector3) -> void: client_ends[peer].append(end_point))
		mirror_rifle.target_hit.connect(func(_c: Node3D, at: Vector3, _n: Vector3) -> void: client_ends[peer].append(at))
	# The scope wanders, and some shots meet the window frame: fire until one flies long enough to drop.
	var host_path: PackedVector3Array = PackedVector3Array()
	var client_paths: Dictionary = {}
	for _attempt: int in SHOT_ATTEMPTS:
		host_end.clear()
		host_path.clear()
		for peer: int in range(1, _rig.peer_count()):
			client_ends[peer].clear()
			client_paths[peer] = PackedVector3Array()
		if not await _rig.wait_for(func() -> bool: return rifle.can_fire()):
			fail("the host's rifle never came ready")
			return
		assert_true(rifle.try_fire(), "the host fires")
		var ticks: int = 0
		while ticks < 600 and (host_end.is_empty() or client_ends[1].is_empty() or client_ends[2].is_empty()):
			var flying: Array = rifle.get(&"_projectiles")
			if not flying.is_empty() and is_instance_valid(flying[0]):
				host_path.append((flying[0] as Node3D).global_position)
			for peer: int in range(1, _rig.peer_count()):
				var shown: Array = _rig.controller(peer).rifle.get(&"_visual_rounds")
				# Only while the host's round is in the air: past its landing a replay flies on until it is told.
				if host_end.is_empty() and not shown.is_empty() and is_instance_valid(shown[0]):
					client_paths[peer].append((shown[0] as Node3D).global_position)
			await step_ticks(1)
			ticks += 1
		if host_path.size() >= LONG_FLIGHT_TICKS:
			break
	if not assert_false(host_end.is_empty(), "the host's round landed"):
		return
	if not assert_ge(float(host_path.size()), float(LONG_FLIGHT_TICKS), "a round was in the air long enough to drop"):
		return
	host_path.append(host_end[0])
	var straight: Vector3 = host_path[0].lerp(host_end[0], 0.5)
	assert_gt(_distance_to_path(straight, host_path), 1.0, "and its flight is an arc, not the straight line to where it landed")
	for peer: int in range(1, _rig.peer_count()):
		if not assert_false(client_ends[peer].is_empty(), "peer %d is told where the round landed" % peer):
			continue
		assert_vec3_almost_eq(client_ends[peer][0], host_end[0], 0.001, "peer %d lands it where the host did" % peer)
		var path: PackedVector3Array = client_paths[peer]
		assert_gt(float(path.size()), 10.0, "peer %d drew the round in flight" % peer)
		var worst: float = 0.0
		for point: Vector3 in path:
			worst = maxf(worst, _distance_to_path(point, host_path))
		assert_le(worst, ARC_TOLERANCE_METRES, "peer %d's replayed round flies the host's arc" % peer)


## Metres from [param point] to the polyline through [param path].
func _distance_to_path(point: Vector3, path: PackedVector3Array) -> float:
	var best: float = INF
	for i: int in range(1, path.size()):
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(point, path[i - 1], path[i])
		best = minf(best, point.distance_to(closest))
	return best


## Client 1 leaves; true once the host and the other client both hold its seat as a bot's.
func _client_one_drops(slot: int) -> bool:
	_rig.sessions[1].leave()
	var carried: bool = await _rig.wait_for(func() -> bool:
		return not _rig.participant(HOST, slot).is_human() and not _rig.participant(2, slot).is_human())
	assert_true(carried, "the dropped client's seat is a bot's on the host and on the client left")
	return carried


func test_a_client_that_drops_while_dead_comes_back_as_a_bot_ghost() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, 1))
	_shoot(1)
	if not await _rig.wait_for(func() -> bool: return _rig.participant(2, 1).is_ghost):
		fail("the death never reached the other client")
		return
	assert_true(host.is_awaiting_respawn(_rig.participant(HOST, 1)), "the client is still held where it died")
	if not await _client_one_drops(1):
		return
	var ghost: MatchParticipant = _rig.participant(HOST, 1)
	assert_true(host.is_awaiting_respawn(ghost), "the hold outlives the player")
	assert_false(ghost.body.is_physics_processing(), "and the body stays held where it died, not simulated")
	if not await _respawned(1):
		return
	assert_true(ghost.brain != null and ghost.brain.is_chasing(), "and it chases, as a bot's ghost does")
	await step_ticks(_cross)
	var seen: MatchParticipant = _rig.participant(2, 1)
	assert_true(seen.is_ghost, "the client left holds it as a ghost")
	assert_false(_rig.controller(2).is_awaiting_respawn(seen), "back in the world")
	assert_false(_lies_dead(2, 1), "standing, not lying where the player left it")
	assert_lt(_rig.controller(2).get_body_color(seen).a, 1.0, "in the ghost colour")


func test_a_finisher_that_drops_is_carried_on_by_a_bot_that_hunts_the_guard() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	var finisher: MatchParticipant = _rig.participant(HOST, 1)
	TestFixtures.pin_the_field(host, finisher)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return _rig.participant(2, 1).is_finisher and finisher.body.is_physics_processing()):
		fail("the finisher never reached the tower on every peer")
		return
	if not await _client_one_drops(1):
		return
	assert_true(finisher.is_finisher, "the bot is still the finisher")
	assert_true(finisher.brain != null and finisher.brain.is_chasing(), "and it hunts")
	assert_same(finisher.brain.get_chase_target(), _rig.body(HOST, 0), "the guard, not the field")
	var round_before: int = host.get_round_number()
	if not await _rig.wait_for(func() -> bool: return host.get_round_number() > round_before, 8000):
		fail("the bot finisher never threw the guard out")
		return
	var mirror: MatchController = _rig.controller(2)
	if not await _rig.wait_for(func() -> bool: return mirror.get_round_number() == host.get_round_number()):
		fail("the client left never saw the next round")
		return
	assert_same(mirror.get_seat_participant(), _rig.participant(2, 1), "the client left sees the bot take the tower")


## Every peer holds [param slot] as a living runner in its own colour, awake where it should be.
func _assert_runs(slot: int, why: String) -> void:
	for peer: int in _rig.peer_count():
		var who: MatchParticipant = _rig.participant(peer, slot)
		assert_true(who.is_running and not who.is_ghost, "peer %d: slot %d runs %s" % [peer, slot, why])
		assert_false(_rig.controller(peer).is_awaiting_respawn(who), "peer %d: slot %d waits on no respawn %s" % [peer, slot, why])
		assert_almost_eq(_rig.controller(peer).get_body_color(who).a, 1.0, 0.001, "peer %d: slot %d is solid %s" % [peer, slot, why])
		assert_false(_lies_dead(peer, slot), "peer %d: slot %d is on its feet %s" % [peer, slot, why])
		assert_eq_int(who.body.collision_layer, who.home_collision_layer, "peer %d: slot %d collides as a runner %s" % [peer, slot, why])
		if _rig.local_slot(peer) == slot or peer == HOST:
			assert_true(who.body.is_physics_processing(), "peer %d simulates slot %d %s" % [peer, slot, why])


func test_a_ghost_catch_swaps_the_two_on_every_peer() -> void:
	if not await _start_round(2, 4):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	# Off the start place the ghost comes back to: the places are shared, and it would land on a head.
	_stand_in_front(3, 2)
	_shoot(1)
	if not await _respawned(1):
		return
	var ghost: MatchParticipant = _rig.participant(HOST, 1)
	if not await _rig.wait_for(func() -> bool: return ghost.ghost_grace_remaining <= 0.0):
		fail("the ghost's catch grace never ran out")
		return
	_stand_in_front(1, 2)
	await step_ticks(_cross)
	assert_same(host.apply_shove(ghost), _rig.participant(HOST, 2), "the ghost's shove lands on the other client")
	if not await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.participant(peer, 2).is_ghost or _rig.participant(peer, 1).is_ghost:
				return false
		return true):
		fail("the swap never reached every peer")
		return
	var caught_view: MatchController = _rig.controller(2)
	assert_eq_int(
		int(caught_view.get_spectating_state(_rig.participant(2, 2))), int(MatchController.Spectating.RESPAWNING),
		"the caught client is shown its respawn"
	)
	assert_false(_rig.body(2, 2).is_physics_processing(), "and is held on its own machine")
	if not await _respawned(2):
		return
	_assert_runs(1, "after its catch")
	for peer: int in _rig.peer_count():
		var caught: MatchParticipant = _rig.participant(peer, 2)
		assert_true(caught.is_ghost and not caught.is_running, "peer %d: the caught client is the ghost now" % peer)
		assert_lt(_rig.controller(peer).get_body_color(caught).a, 1.0, "peer %d: in the ghost colour" % peer)
		assert_false(_lies_dead(peer, 2), "peer %d: and on its feet at the start line" % peer)
	assert_true(_rig.body(2, 2).is_physics_processing(), "the caught client drives its ghost")
	assert_eq_int(host.get_catch_count(), 1, "one catch")


func test_a_new_round_puts_every_ghost_and_corpse_back_on_its_feet() -> void:
	if not await _start_round(2, 5, 0):
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	# A respawned ghost, a body still held where it was shot, and one that fell: then the round turns over.
	_shoot(1)
	if not await _respawned(1):
		return
	_shoot(3)
	assert_true(host.handle_fall(_rig.participant(HOST, 4)), "the host rules a lava death")
	if not await _every_peer_sees_limp(3, "before the round turns over"):
		return
	var round_before: int = host.get_round_number()
	host.call(&"_score_and_restart", _rig.participant(HOST, 2))
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_round_number() == round_before + 1):
			fail("peer %d never saw the next round" % peer)
			return
	await step_ticks(_cross)
	for peer: int in _rig.peer_count():
		assert_same(_rig.controller(peer).get_seat_participant(), _rig.participant(peer, 2), "peer %d: the scorer holds the tower" % peer)
		assert_eq_int(_rig.controller(peer).get_ghost_participants().size(), 0, "peer %d: no ghost outlives its round" % peer)
	for slot: int in [0, 1, 3, 4]:
		_assert_runs(slot, "in the new round")
		for peer: int in _rig.peer_count():
			assert_false(_rig.ragdoll(peer, slot).is_active(), "peer %d: slot %d left no corpse behind" % [peer, slot])


func test_a_racer_who_falls_is_out_on_every_peer_and_runs_the_first_round() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("the loopback handshake did not complete")
		return
	_rig.settings().rounds_to_win_match = 3
	if not await _rig.launch(4, -1):
		fail("the match never started on every peer")
		return
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.RACE):
			fail("peer %d never reached the opening race" % peer)
			return
	await step_ticks(_cross)
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	assert_true(host.handle_fall(_rig.participant(HOST, 1)), "the host rules the client's fall")
	if not await _rig.wait_for(func() -> bool:
		return not _rig.participant(1, 1).is_running and not _rig.participant(2, 1).is_running):
		fail("the fall never reached the clients")
		return
	for peer: int in _rig.peer_count():
		assert_false(_rig.body(peer, 1).visible, "peer %d: the racer who fell is out of sight" % peer)
		assert_false(_rig.participant(peer, 1).is_ghost, "peer %d: and no ghost, the race has no guard" % peer)
	assert_eq_int(
		int(_rig.controller(1).get_spectating_state(_rig.participant(1, 1))), int(MatchController.Spectating.ELIMINATED),
		"the client who fell is told it is out"
	)
	# A racer arrives: the tower is theirs and the first round starts.
	host.take_seat(_rig.participant(HOST, 3))
	host.start_round()
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the first round" % peer)
			return
	await step_ticks(_cross)
	for slot: int in [0, 1, 2]:
		_assert_runs(slot, "in the first round")
		for peer: int in _rig.peer_count():
			assert_true(_rig.body(peer, slot).visible, "peer %d: slot %d is drawn" % [peer, slot])
