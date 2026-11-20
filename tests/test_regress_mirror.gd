extends TestCase
## Playtest regressions in how a body is drawn on the other machines: the run, the death, the limp body,
## the finale, the flop and the shirt. The shipped match scene on real sockets, two and four machines, hell and marble.

const Rig = preload("res://tests/support/net_match_rig.gd")
const BANK_PATH: String = "res://audio/placeholder_bank.tres"

const HOST: int = 0
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
## Ticks for a reliable event and the snapshots behind it to cross loopback and be drawn.
const CROSS_TICKS: int = 30
## The same on a bad line: time is compressed fiftyfold, so 3 real ms each way is 150 ms of play.
const BAD_LINE_TICKS: int = 120
const BAD_LINE_LOSS: float = 0.1
const BAD_LINE_DELAY_MS: int = 3
## Ticks a driven body is given to reach its run and clear the start line.
const RUN_UP_TICKS: int = 45
const RUN_WATCH_TICKS: int = 20
## Furthest a limp part may lie from the pelvis of a body shot standing, metres: hip to foot is under a metre.
const LIMP_REACH_METRES: float = 1.2
## The same for a body shot at a run or thrown in the finale: it lands harder, and is still one body.
const MOVING_REACH_METRES: float = 1.35
## A limp part's scale must stay within this of 1: a part built on a collapsed bone is a degenerate body.
const PART_SCALE_SLACK: float = 0.05

var _rig: Rig = null
var _cross: int = CROSS_TICKS
var _clients: int = 1
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	_rig = Rig.new()
	_cross = CROSS_TICKS
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	if _rig != null:
		_rig.close()
		_rig = null


## Host, [param clients] clients and one bot in a running round on [param map]; [param guard_seat] holds the tower.
func _start(clients: int, guard_seat: int, map: StringName, bad_line: bool = false) -> bool:
	_clients = clients
	if bad_line:
		_rig.wire_loss = BAD_LINE_LOSS
		_rig.wire_delay_ms = BAD_LINE_DELAY_MS
		_cross = BAD_LINE_TICKS
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	# A finale kill must turn the round over, not end the match.
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().map_id = map
	if not await _rig.launch(clients + 2, guard_seat):
		fail("the match never started on every peer")
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
		if not assert_eq_string(String(controller.get_rules().map_id), String(map), "peer %d stands on the map asked for" % peer):
			return false
	await step_ticks(_cross)
	return true


## The slot of the one bot in every roster here.
func _bot_slot() -> int:
	return _clients + 1


## The peer that plays [param slot], or -1 for a bot's.
func _owner_of(slot: int) -> int:
	for peer: int in _rig.peer_count():
		if _rig.local_slot(peer) == slot:
			return peer
	return -1


## Stand everybody but [param keep_slot] still on the host, where they are simulated; a bot guard holds its fire.
func _hold_the_field(keep_slot: int = -1) -> void:
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, _rig.participant(HOST, keep_slot) if keep_slot >= 0 else null)
	var seat: MatchParticipant = host.get_seat_participant()
	if seat != null and not seat.is_human():
		host.call(&"_silence_tower_brain", seat)


## Whether [param peer] draws [param slot] as a limp body.
func _limp(peer: int, slot: int) -> bool:
	return bool(_rig.ragdoll(peer, slot).call(&"is_active"))


func _lies_dead(peer: int, slot: int) -> bool:
	var avatar: PrisonerAvatar = _rig.avatar(peer, slot)
	return _limp(peer, slot) or bool(avatar.get(&"_dead"))


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


func _every_peer_sees_limp(slot: int, why: String) -> bool:
	var seen: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _limp(peer, slot):
				return false
		return true)
	if not seen:
		for peer: int in _rig.peer_count():
			assert_true(_limp(peer, slot), "peer %d draws slot %d limp %s" % [peer, slot, why])
	return seen


## The host's ghost in [param slot] is back in the world, and the peers have heard.
func _respawned(slot: int) -> bool:
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool:
		return host_side.is_ghost and not host.is_awaiting_respawn(host_side) and moves(host_side.body)
	):
		fail("the host never put slot %d back as a ghost" % slot)
		return false
	await step_ticks(_cross)
	return true


## What is wrong with [param peer]'s limp copy of [param slot], or "" when it is one whole, finite, full-size body.
func _limp_fault(peer: int, slot: int, reach: float) -> String:
	var ragdoll: Node = _rig.ragdoll(peer, slot)
	var parts: PackedVector3Array = ragdoll.call(&"part_positions")
	for index: int in parts.size():
		if not parts[index].is_finite():
			return "part %d is not finite" % index
		if parts[index].distance_to(parts[0]) > reach:
			return "part %d lies %.2f m from the pelvis" % [index, parts[index].distance_to(parts[0])]
	for child: Node in ragdoll.find_children("*", "PhysicalBone3D", true, false):
		var scale: Vector3 = (child as PhysicalBone3D).global_basis.get_scale()
		if absf(scale.x - 1.0) > PART_SCALE_SLACK or absf(scale.y - 1.0) > PART_SCALE_SLACK or absf(scale.z - 1.0) > PART_SCALE_SLACK:
			return "%s is scaled %v" % [child.name, scale]
	return ""


## The first thing wrong with how any peer draws the corpse in [param slot] against [param alive], or "".
func _corpse_fault(slot: int, alive: Array, reach: float) -> String:
	for peer: int in _rig.peer_count():
		var worn: Array[Material] = _worn(peer, slot)
		for index: int in worn.size():
			if worn[index] != alive[peer][index]:
				return "peer %d: surface %d of the corpse changed material" % [peer, index - 1]
		var colour: Color = _rig.controller(peer).get_body_color(_rig.participant(peer, slot))
		if not is_equal_approx(colour.a, 1.0):
			return "peer %d: the corpse is drawn at alpha %.2f" % [peer, colour.a]
		if _limp(peer, slot):
			var fault: String = _limp_fault(peer, slot, reach)
			if fault != "":
				return "peer %d: %s" % [peer, fault]
	return ""


# --- PT1-03: a running body is drawn running --------------------------------------

## Whether [param peer] draws [param slot] as a body running on the ground.
func _drawn_running(peer: int, slot: int) -> bool:
	var avatar: PrisonerAvatar = _rig.avatar(peer, slot)
	return bool(avatar.get(&"_running")) and not bool(avatar.get(&"_in_air")) and not bool(avatar.get(&"_dead"))


## Every peer comes to draw [param slot] running, and none draws it dead while the others catch up.
func _every_peer_draws_the_run(slot: int, what: String) -> void:
	var seen: Array[bool] = []
	seen.resize(_rig.peer_count())
	var lay_dead: Array[bool] = [false]
	var all: bool = await _rig.wait_for(func() -> bool:
		var every: bool = true
		for peer: int in _rig.peer_count():
			var mirror: PlayerController = _rig.body(peer, slot)
			if _lies_dead(peer, slot):
				lay_dead[0] = true
			if _drawn_running(peer, slot) and mirror.is_grounded() and mirror.get_horizontal_speed() > 2.0:
				seen[peer] = true
			every = every and seen[peer]
		return every)
	for peer: int in _rig.peer_count():
		assert_true(all or seen[peer], "peer %d draws %s running on the floor" % [peer, what])
	assert_false(lay_dead[0], "no peer draws %s dead while it runs" % what)


## [param runner] runs, is shot, and runs again as a ghost; every machine draws each of the three.
func _watch_a_run(clients: int, map: StringName, runner: int) -> void:
	var guard: int = 1 if runner == HOST else 0
	if not await _start(clients, guard, map):
		return
	var slot: int = _rig.local_slot(runner)
	# Everybody runs: a body left standing on the line stands where the ghost comes back.
	for peer: int in _rig.peer_count():
		if peer != guard:
			_rig.drive(peer, Vector2(0.0, 1.0))
	await _every_peer_draws_the_run(slot, "the living body")
	await step_ticks(RUN_UP_TICKS)
	for peer: int in _rig.peer_count():
		_rig.drive(peer, Vector2.ZERO)
	_shoot(slot)
	if not await _every_peer_sees_limp(slot, "when it is shot"):
		return
	if not await _respawned(slot):
		return
	for peer: int in _rig.peer_count():
		assert_false(_lies_dead(peer, slot), "peer %d: the respawned body is not left lying" % peer)
	_rig.drive(runner, Vector2(0.0, 1.0))
	await _every_peer_draws_the_run(slot, "the ghost")


func test_a_running_client_is_drawn_running_dead_and_running_again_two_peers_hell() -> void:
	await _watch_a_run(1, HELL, 1)


func test_a_running_host_is_drawn_running_dead_and_running_again_two_peers_marble() -> void:
	await _watch_a_run(1, MARBLE, HOST)


func test_a_running_client_is_drawn_running_dead_and_running_again_four_peers_marble() -> void:
	await _watch_a_run(3, MARBLE, 2)


func test_a_running_host_is_drawn_running_dead_and_running_again_four_peers_hell() -> void:
	await _watch_a_run(3, HELL, HOST)


# --- PT3-03: a hologram a machine only mirrors runs --------------------------------

## [param sender] sends a hologram out; every machine that mirrors it draws it running on the floor.
func _watch_a_hologram(clients: int, map: StringName, sender: int) -> void:
	# At real time: a mirrored hologram's drawn speed is measured against the wall clock.
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	if not await _start(clients, 1 if sender == HOST else 0, map):
		return
	_hold_the_field()
	var slot: int = _rig.local_slot(sender)
	assert_true(RunnerPower.of(_rig.body(HOST, slot)).activate(MatchRules.RunnerAbility.HOLOGRAM), "the host runs the hologram")
	var seen: Array[bool] = []
	seen.resize(_rig.peer_count())
	var all: bool = await _rig.wait_for(func() -> bool:
		var every: bool = true
		for peer: int in _rig.peer_count():
			var view: HologramView = RunnerPower.of(_rig.body(peer, slot)).get_hologram()
			if view != null and view.get_clip() == HologramView.RUN_CLIP \
					and Vector2(view.get_velocity().x, view.get_velocity().z).length() > 2.0:
				seen[peer] = true
			every = every and seen[peer]
		return every)
	for peer: int in _rig.peer_count():
		assert_true(all or seen[peer], "peer %d draws the hologram running on the floor" % peer)


func test_a_clients_hologram_runs_on_every_peer_two_peers_marble() -> void:
	await _watch_a_hologram(1, MARBLE, 1)


func test_a_clients_hologram_runs_on_every_peer_four_peers_hell() -> void:
	await _watch_a_hologram(3, HELL, 2)


func test_the_hosts_hologram_runs_on_every_peer_four_peers_marble() -> void:
	await _watch_a_hologram(3, MARBLE, HOST)


# --- PT1-05: a client's death view and the footsteps it hears ---------------------

## The last client is shot: it gets the death screen, the camera and a countdown, and they hand back.
func _watch_a_death_view(clients: int, map: StringName) -> void:
	if not await _start(clients, 0, map):
		return
	var victim: int = clients
	var slot: int = _rig.local_slot(victim)
	var mirror: MatchController = _rig.controller(victim)
	var screen: MatchDeathScreen = _rig.matches[victim].get_node("DeathScreen") as MatchDeathScreen
	var view: FxSpectatorView = _rig.matches[victim].get_node("SpectatorView") as FxSpectatorView
	_hold_the_field()
	assert_false(screen.is_showing(), "no death screen on a living client")
	_shoot(slot)
	var mine: MatchParticipant = _rig.participant(victim, slot)
	if not await _rig.wait_for(func() -> bool: return screen.is_showing() and view.is_active()):
		assert_true(screen.is_showing(), "the shot client is shown the death screen")
		assert_true(view.is_active(), "the shot client is given the death camera")
		return
	assert_eq_int(int(mirror.get_spectating_state(mine)), int(MatchController.Spectating.RESPAWNING), "it knows it waits on a respawn")
	var first: float = mirror.get_respawn_hold_remaining(mine)
	assert_gt(first, 0.0, "the countdown has time on it")
	await step_ticks(30)
	assert_lt(mirror.get_respawn_hold_remaining(mine), first, "and it runs down")
	for peer: int in range(1, _rig.peer_count()):
		if peer == victim:
			continue
		var other: MatchDeathScreen = _rig.matches[peer].get_node("DeathScreen") as MatchDeathScreen
		assert_false(other.is_showing(), "peer %d was not shot and is shown no death screen" % peer)
	if not await _respawned(slot):
		return
	assert_false(screen.is_showing(), "the death screen hands back at the respawn")
	assert_false(view.is_active(), "and so does the camera")


func test_a_shot_client_gets_its_death_view_two_peers_marble() -> void:
	await _watch_a_death_view(1, MARBLE)


func test_a_shot_client_gets_its_death_view_four_peers_hell() -> void:
	await _watch_a_death_view(3, HELL)


func test_a_shot_client_gets_its_death_view_four_peers_marble() -> void:
	await _watch_a_death_view(3, MARBLE)


## A movement listener of [param peer]'s own, counting the footsteps it posts.
func _listen_on(peer: int, heard: Array[int]) -> void:
	var bank: AudioBank = (load(BANK_PATH) as AudioBank).duplicate(true) as AudioBank
	var cue: AudioCue = bank.get_cue(AudioEvents.MOVEMENT_FOOTSTEP)
	cue.min_retrigger_seconds = 0.0
	cue.allow_same_frame = true
	var director: AudioDirector = AudioDirector.new()
	director.bank = bank
	director.activation = AudioDirector.Activation.ALWAYS
	_rig.matches[peer].add_child(director)
	director.event_played.connect(func(event: StringName, _positional: bool) -> void:
		if event == AudioEvents.MOVEMENT_FOOTSTEP:
			heard[0] += 1)
	var listener: MovementAudioListener = MovementAudioListener.new()
	listener.director = director
	listener.tuning = MovementAudioTuning.new()
	listener.search_root = _rig.matches[peer]
	_rig.matches[peer].add_child(listener)


## A client hears the host's runner, then its own body, as footsteps on its own machine.
func _watch_footsteps(clients: int, map: StringName) -> void:
	if not await _start(clients, _clients_bot_guard(clients), map):
		return
	var listener: int = clients
	_hold_the_field()
	var heard: Array[int] = [0]
	_listen_on(listener, heard)
	await step_ticks(CROSS_TICKS)
	assert_eq_int(heard[0], 0, "nobody moves, nobody is heard")
	_rig.body(HOST, 0).movement_locked = false
	_rig.drive(HOST, Vector2(0.0, 1.0))
	await step_ticks(RUN_UP_TICKS + RUN_WATCH_TICKS)
	_rig.drive(HOST, Vector2.ZERO)
	var of_the_host: int = heard[0]
	assert_gt(float(of_the_host), 0.0, "the client hears the host's runner, a body it only mirrors")
	await step_ticks(CROSS_TICKS)
	var settled: int = heard[0]
	_rig.body(HOST, _rig.local_slot(listener)).movement_locked = false
	_rig.drive(listener, Vector2(0.0, 1.0))
	await step_ticks(RUN_UP_TICKS + RUN_WATCH_TICKS)
	assert_gt(float(heard[0] - settled), 0.0, "and its own footsteps when it runs")


## The seat of the bot, for a round every human runs in.
func _clients_bot_guard(clients: int) -> int:
	return clients + 1


func test_a_client_hears_footsteps_two_peers_hell() -> void:
	await _watch_footsteps(1, HELL)


func test_a_client_hears_footsteps_four_peers_marble() -> void:
	await _watch_footsteps(3, MARBLE)


# --- PT3-02, PT3-10a, S-01: the rifle kill, limp and unchanged on every machine --------

## One rifle kill of [param slot], watched every tick from the hit to the respawn on every peer.
## [param reach] bounds the limp body: tighter for a victim shot standing than for one shot at a run.
func _watch_a_rifle_kill(slot: int, reach: float = LIMP_REACH_METRES) -> void:
	var owner: int = _owner_of(slot)
	if owner >= 0:
		assert_true(_rig.avatar(owner, slot).is_head_hidden(), "the player looks out of this body: its head is collapsed")
	var alive: Array = []
	for peer: int in _rig.peer_count():
		alive.append(_worn(peer, slot))
	_shoot(slot)
	var host: MatchController = _rig.controller(HOST)
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	assert_true(host_side.is_ghost, "the hit converts slot %d on the host" % slot)
	_hold_the_field()
	host.call(&"_silence_brain", host_side)
	if owner >= 0:
		# Read on the first frame after the one it went limp in, before the view rules run again.
		var frames: int = 0
		while not _limp(owner, slot) and frames < 4000:
			await get_tree().process_frame
			frames += 1
		assert_true(_limp(owner, slot), "the player's own machine draws its body limp")
		assert_false(_rig.avatar(owner, slot).is_head_hidden(), "and it went limp on full-size bones, the head no longer collapsed")
	if not await _every_peer_sees_limp(slot, "after the rifle kill"):
		return
	var fault: String = ""
	var limp_ticks: int = 0
	while host.is_awaiting_respawn(host_side) and fault == "" and limp_ticks < 600:
		fault = _corpse_fault(slot, alive, reach)
		for peer: int in _rig.peer_count():
			if fault == "" and limp_ticks < 60 and not _limp(peer, slot):
				fault = "peer %d stopped drawing the body limp %d ticks after it fell" % [peer, limp_ticks]
		limp_ticks += 1
		await step_ticks(1)
	assert_eq_string(fault, "", "the corpse from the hit to the respawn")
	assert_gt(float(limp_ticks), 60.0, "the corpse was watched for more than a second")
	if not await _respawned(slot):
		return
	for peer: int in _rig.peer_count():
		assert_false(_lies_dead(peer, slot), "peer %d: slot %d stands at the start line" % [peer, slot])
		assert_lt(_rig.controller(peer).get_body_color(_rig.participant(peer, slot)).a, 1.0, "peer %d: the respawned ghost wears the ghost colour" % peer)


func test_a_shot_client_is_one_limp_unchanged_body_two_peers_hell() -> void:
	if await _start(1, 0, HELL):
		await _watch_a_rifle_kill(1)


func test_a_shot_host_is_one_limp_unchanged_body_two_peers_marble() -> void:
	if await _start(1, 1, MARBLE):
		await _watch_a_rifle_kill(0)


func test_a_shot_client_is_one_limp_unchanged_body_four_peers_marble() -> void:
	if await _start(3, 0, MARBLE):
		await _watch_a_rifle_kill(3)


func test_a_shot_host_is_one_limp_unchanged_body_four_peers_hell() -> void:
	if await _start(3, 2, HELL):
		await _watch_a_rifle_kill(0)


func test_a_shot_bot_is_one_limp_unchanged_body_four_peers_hell() -> void:
	if not await _start(3, 0, HELL):
		return
	_hold_the_field()
	await step_ticks(CROSS_TICKS)
	await _watch_a_rifle_kill(_bot_slot())


func test_a_running_client_shot_over_a_bad_line_is_limp_on_four_peers_marble() -> void:
	if not await _start(3, 0, MARBLE, true):
		return
	_hold_the_field(2)
	# Running when it is hit, so snapshots still in flight carry the run past the death.
	_rig.drive(2, Vector2(0.0, 1.0))
	await step_ticks(_cross)
	await _watch_a_rifle_kill(2, MOVING_REACH_METRES)


func test_a_running_host_shot_over_a_bad_line_is_limp_on_two_peers_hell() -> void:
	if not await _start(1, 1, HELL, true):
		return
	_hold_the_field(0)
	_rig.drive(HOST, Vector2(0.0, 1.0))
	await step_ticks(_cross)
	await _watch_a_rifle_kill(0, MOVING_REACH_METRES)


# --- PT3-04, S-02, S-18: the finale on every machine ------------------------------------

## The tower's colliders and their layers, as [param peer] holds them.
func _tower_layers(peer: int) -> Dictionary:
	var layers: Dictionary = {}
	var tower: Node = _rig.controller(peer).call(&"_tower_node")
	for node: Node in tower.find_children("*", "StaticBody3D", true, false):
		layers[node] = (node as StaticBody3D).collision_layer
	return layers


## Every slot's shirt colour as [param peer] draws it.
func _shirts(peer: int) -> Array[Color]:
	var shirts: Array[Color] = []
	for who: MatchParticipant in _rig.controller(peer).get_participants():
		shirts.append(_rig.controller(peer).get_body_color(who))
	return shirts


## Every peer draws every slot in the host's colour for it, each slot its own, all solid.
func _assert_shirts_agree(why: String) -> Array[Color]:
	var on_host: Array[Color] = _shirts(HOST)
	for slot: int in on_host.size():
		assert_almost_eq(on_host[slot].a, 1.0, 0.001, "slot %d is solid %s" % [slot, why])
		for other: int in slot:
			assert_false(on_host[slot].is_equal_approx(on_host[other]), "slots %d and %d wear different shirts %s" % [other, slot, why])
	for peer: int in range(1, _rig.peer_count()):
		var here: Array[Color] = _shirts(peer)
		for slot: int in on_host.size():
			assert_true(here[slot].is_equal_approx(on_host[slot]), "peer %d draws slot %d in the host's colour for it %s" % [peer, slot, why])
	return on_host


## The host arms [param finisher_slot], who shoves the guard out; watched to the next round on every peer.
func _watch_a_finale(guard_slot: int, finisher_slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	_hold_the_field(finisher_slot)
	var shirts: Array[Color] = _assert_shirts_agree("before the finale")
	var towers: Array[Dictionary] = []
	var alive: Array = []
	var hits: Array[int] = [0]
	for peer: int in _rig.peer_count():
		towers.append(_tower_layers(peer))
		alive.append(_worn(peer, guard_slot))
		_rig.controller(peer).rifle.target_hit.connect(func(_c: Node3D, _at: Vector3, _n: Vector3) -> void: hits[0] += 1)
	var guard_owner: int = _owner_of(guard_slot)
	# [told, collapsed]: whether the guard's own machine started his limp body on bones first person had collapsed.
	var thrown: Array[bool] = [false, false]
	if guard_owner >= 0:
		var own: PrisonerAvatar = _rig.avatar(guard_owner, guard_slot)
		assert_true(own.is_head_hidden() and own.are_arms_hidden(), "the guard looks out of his body, head and arms collapsed")
		_rig.controller(guard_owner).kill_beat_started.connect(func(_guard: MatchParticipant, _seconds: float, _throw: Vector3) -> void:
			thrown[0] = true
			thrown[1] = own.is_head_hidden() or own.is_spine_hidden() or own.are_arms_hidden())
	var finisher: MatchParticipant = _rig.participant(HOST, finisher_slot)
	host.call(&"_arm_the_finisher", finisher)
	if not await _rig.wait_for(func() -> bool: return moves(finisher.body)):
		fail("the finisher never landed in the tower")
		return
	for peer: int in _rig.peer_count():
		var mirrored: MatchParticipant = _rig.participant(peer, finisher_slot)
		if not await _rig.wait_for(func() -> bool: return mirrored.is_finisher):
			fail("peer %d never learned who the finisher is" % peer)
			return
		assert_false(mirrored.body.is_armed, "peer %d: the finisher carries no rifle" % peer)
	var round_before: int = host.get_round_number()
	assert_same(host.apply_shove(finisher), _rig.participant(HOST, guard_slot), "the finisher's shove takes the guard")
	if not await _every_peer_sees_limp(guard_slot, "on the finale shove"):
		return
	var held: Array[Vector3] = []
	for peer: int in _rig.peer_count():
		held.append(_rig.body(peer, guard_slot).global_position)
	var until: float = host.get_rules().kill_beat_seconds * 0.25
	var fault: String = ""
	var watched: int = 0
	while float(host.get(&"_kill_beat_remaining")) > until and fault == "":
		await step_ticks(1)
		if float(host.get(&"_kill_beat_remaining")) <= 0.0:
			break
		watched += 1
		for peer: int in _rig.peer_count():
			if fault != "":
				break
			var guard: PlayerController = _rig.body(peer, guard_slot)
			if not _limp(peer, guard_slot):
				fault = "peer %d: the guard stood up inside the beat" % peer
			elif not guard.movement_locked or not _rig.body(peer, finisher_slot).movement_locked:
				fault = "peer %d: a body has its controls inside the beat" % peer
			elif moves(guard):
				fault = "peer %d: the guard's capsule is simulated inside the beat" % peer
			elif guard.global_position.distance_to(held[peer]) > 0.5:
				fault = "peer %d: the guard's capsule left the tower" % peer
			elif _rig.controller(peer).is_tower_open():
				fault = "peer %d: the tower opened" % peer
		if fault == "":
			fault = _corpse_fault(guard_slot, alive, MOVING_REACH_METRES)
	assert_eq_string(fault, "", "the kill beat on every peer")
	assert_gt(float(watched), 30.0, "the beat was watched for more than half a second")
	assert_eq_int(hits[0], 0, "rifle hits shown for a guard who was shoved, not shot")
	if guard_owner >= 0:
		assert_true(thrown[0], "the guard's own machine was told of the throw")
		assert_false(thrown[1], "and his body went limp on full-size bones")
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_round_number() == round_before + 1):
			fail("peer %d never saw the next round" % peer)
			return
	await step_ticks(_cross)
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		assert_same(controller.get_seat_participant(), _rig.participant(peer, finisher_slot), "peer %d: the finisher holds the tower" % peer)
		assert_false(_lies_dead(peer, guard_slot), "peer %d: the thrown guard stands on the ring" % peer)
		assert_false(_rig.body(peer, guard_slot).movement_locked, "peer %d: the old guard has its controls back" % peer)
		assert_false(_rig.body(peer, finisher_slot).movement_locked, "peer %d: and so has the new one" % peer)
		assert_true(_rig.participant(peer, guard_slot).is_running, "peer %d: the old guard runs this round" % peer)
		var layers: Dictionary = _tower_layers(peer)
		for wall: Node in layers:
			assert_eq_int(int(layers[wall]), int(towers[peer][wall]), "peer %d: %s collides as it did" % [peer, wall.name])
		var own: int = _rig.local_slot(peer)
		assert_true(moves(_rig.body(peer, own)), "peer %d simulates its own body in the new round" % peer)
	var after: Array[Color] = _assert_shirts_agree("after the tower changed hands")
	for slot: int in shirts.size():
		assert_true(after[slot].is_equal_approx(shirts[slot]), "slot %d wears the shirt it wore before the tower changed hands" % slot)


func test_a_client_guard_thrown_by_the_host_two_peers_hell() -> void:
	if await _start(1, 1, HELL):
		await _watch_a_finale(1, 0)


func test_a_host_guard_thrown_by_a_client_two_peers_marble() -> void:
	if await _start(1, 0, MARBLE):
		await _watch_a_finale(0, 1)


func test_a_client_guard_thrown_by_a_client_four_peers_marble() -> void:
	if await _start(3, 3, MARBLE):
		await _watch_a_finale(3, 1)


func test_a_host_guard_thrown_by_a_client_four_peers_hell() -> void:
	if await _start(3, 0, HELL):
		await _watch_a_finale(0, 2)


func test_a_client_guard_thrown_by_a_bot_over_a_bad_line_four_peers_hell() -> void:
	if await _start(3, 2, HELL, true):
		await _watch_a_finale(2, _bot_slot())


# --- PT3-05, S-05: the shove, the flop and the shover's own arms -----------------------

## Stand [param victim_slot] a pace in front of [param shover_slot] on the host, both still.
func _stand_in_front(shover_slot: int, victim_slot: int) -> void:
	var shover: PlayerController = _rig.body(HOST, shover_slot)
	var victim: PlayerController = _rig.body(HOST, victim_slot)
	var forward: Vector3 = -shover.global_transform.basis.z
	forward.y = 0.0
	victim.global_position = shover.global_position + forward.normalized() * 1.0
	victim.velocity = Vector3.ZERO


## Every peer draws the swing on [param shover_slot] and the flop on [param victim_slot] and on nobody else.
func _watch_a_shove(shover_slot: int, victim_slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	_stand_in_front(shover_slot, victim_slot)
	await step_ticks(_cross)
	var owner: int = _owner_of(shover_slot)
	if owner >= 0:
		assert_false(bool(_rig.avatar(owner, shover_slot).get(&"_fp_shoving")), "peer %d's own arms are down before it shoves" % owner)
	if owner > 0:
		# A client's swing is its own command: pressed on its machine, predicted there, run by the host.
		var landed: Array[MatchParticipant] = []
		var on_shove: Callable = func(_by: MatchParticipant, victim: MatchParticipant) -> void: landed.append(victim)
		host.participant_shoved.connect(on_shove)
		var keys: BotIntentSource = (_rig.matches[owner].get_node("Player") as PlayerController).intent_source as BotIntentSource
		keys.command.shove_pressed = true
		await step_ticks(1)
		keys.command.shove_pressed = false
		await _rig.wait_for(func() -> bool: return not landed.is_empty())
		host.participant_shoved.disconnect(on_shove)
		assert_true(
			landed.size() == 1 and landed[0] == _rig.participant(HOST, victim_slot),
			"the host lands slot %d's shove on slot %d" % [shover_slot, victim_slot],
		)
	else:
		assert_same(
			host.apply_shove(_rig.participant(HOST, shover_slot)), _rig.participant(HOST, victim_slot),
			"the host lands slot %d's shove on slot %d" % [shover_slot, victim_slot]
		)
	var swung: Array[bool] = []
	swung.resize(_rig.peer_count())
	var own_arms: Array[bool] = [false]
	var flopped: bool = await _rig.wait_for(func() -> bool:
		var every: bool = true
		for peer: int in _rig.peer_count():
			var shover: PrisonerAvatar = _rig.avatar(peer, shover_slot)
			if float(shover.get(&"_shove_remaining")) > 0.0:
				swung[peer] = true
			if peer == owner and bool(shover.get(&"_fp_shoving")):
				own_arms[0] = true
			if not _rig.avatar(peer, victim_slot).is_flopping() or not swung[peer]:
				every = false
		return every and (owner < 0 or own_arms[0]))
	for peer: int in _rig.peer_count():
		assert_true(flopped or _rig.avatar(peer, victim_slot).is_flopping(), "peer %d draws slot %d flop" % [peer, victim_slot])
		assert_true(swung[peer], "peer %d draws slot %d swing" % [peer, shover_slot])
		for slot: int in host.get_participants().size():
			if slot != victim_slot:
				assert_false(_rig.avatar(peer, slot).is_flopping(), "peer %d: slot %d was not shoved and does not flop" % [peer, slot])
	if owner >= 0:
		assert_true(own_arms[0], "peer %d, who shoved, sees its own arms push" % owner)
	var up: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if _rig.avatar(peer, victim_slot).is_flopping():
				return false
		return owner < 0 or not bool(_rig.avatar(owner, shover_slot).get(&"_fp_shoving")))
	assert_true(up, "every peer sees slot %d get up, and the shover's arms come down" % victim_slot)


## Everybody in the hub; the host shoves a client, a client the host, and the last client the first.
func _watch_hub_shoves(clients: int) -> void:
	_clients = clients
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return
	_rig.bind_hubs()
	await step_ticks(_cross)
	for peer: int in _rig.peer_count():
		assert_eq_int(_rig.controller(peer).get_participants().size(), clients + 1, "peer %d stands everybody in the hub" % peer)
	if is_failed():
		return
	await _watch_a_shove(0, 1)
	await _watch_a_shove(1, 0)
	await _watch_a_shove(clients, 0)


func test_a_hub_shove_flops_and_swings_on_two_peers() -> void:
	await _watch_hub_shoves(1)


func test_a_hub_shove_flops_and_swings_on_four_peers() -> void:
	await _watch_hub_shoves(3)


func test_a_match_shove_flops_and_swings_on_two_peers_marble() -> void:
	if not await _start(1, _clients_bot_guard(1), MARBLE):
		return
	_hold_the_field()
	await _watch_a_shove(1, 0)
	await _watch_a_shove(0, 1)


func test_a_match_shove_flops_and_swings_on_four_peers_hell() -> void:
	if not await _start(3, _clients_bot_guard(3), HELL):
		return
	_hold_the_field()
	await _watch_a_shove(3, 1)
	await _watch_a_shove(0, 2)
	await _watch_a_shove(2, 0)


# --- S-02: shirts ------------------------------------------------------------------

func test_every_peer_draws_every_shirt_alike_two_peers_marble() -> void:
	if await _start(1, 0, MARBLE):
		_assert_shirts_agree("in the first round")


func test_every_peer_draws_every_shirt_alike_four_peers_hell() -> void:
	if await _start(3, 1, HELL):
		_assert_shirts_agree("in the first round")
