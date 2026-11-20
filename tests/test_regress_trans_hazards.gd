extends TestCase
## Playtest and solo regressions in the maps' hazards, across machines: hell's lava, the pits, marble's trapdoor.
## S-07 (guard spawn floating), S-08 (hopping on lava), S-11 (a ghost in the pit), S-14 (the trapdoor) and PT1-02 (the export's rifle).

const Rig: GDScript = preload("res://tests/support/net_session_rig.gd")

const HOST: int = 0
const CLIENT: int = 1
const HELL: StringName = &"bentham_ring"
const MARBLE: StringName = &"marble"
const CROSS_TICKS: int = 30
const RULES_PATH: String = "res://match/rules/default_match_rules.tres"
const LAVA_RIVER: NodePath = ^"Sections/S2_LavaShelf/TrapVolume4"
const SHOT_DOOR: NodePath = ^"Elements/SectionB/Trapdoor1"
const ON_DOOR_LOCAL: Vector3 = Vector3(0.0, 0.05, 0.3)
## How far over solid floor a guard's spawn marker may stand.
const SPAWN_FLOAT_METRES: float = 0.05
## The authored drop-in over the floor is 0.25 to 0.32 m on every map; the floating guard stood 0.6 m up.
const SPAWN_DROP_METRES: float = 0.4
const GUARD_SETTLE_TICKS: int = 45
const STALL_SEED: int = 20260930
const STALL_MATCH_TICKS: int = 5400
const STALL_TICKS: int = 600
const STALL_METRES: float = 0.5
## A ghost put back on the line is drawn this near the start marker, wherever on the line it stands.
const START_REACH_METRES: float = 12.0

var _rig: RefCounted = null
var _log: Logger = null
var _world: BotMatchWorld = null


func before_each() -> void:
	_rig = Rig.new()
	_log = Rig.ErrorLog.new()
	OS.add_logger(_log)


func after_each() -> void:
	if _log != null:
		OS.remove_logger(_log)
		_log = null
	if _rig != null:
		_rig.close()
		_rig = null
	if _world != null:
		_world.queue_free()
		_world = null


func test_the_export_keeps_text_scenes_and_the_match_scene_holds_its_rifle() -> void:
	var project: String = FileAccess.get_file_as_string("res://project.godot")
	assert_true(
		project.contains("export/convert_text_resources_to_binary=false"),
		"project.godot keeps text scenes as text in an export",
	)
	var scene: Node3D = (load("res://match/match.tscn") as PackedScene).instantiate() as Node3D
	var rifle: Rifle = scene.get_node_or_null("Player/Head/Rifle") as Rifle
	assert_not_null(rifle, "match.tscn holds Player/Head/Rifle")
	var controller: MatchController = scene.get_node_or_null("MatchController") as MatchController
	assert_not_null(controller, "and a MatchController")
	if controller != null and rifle != null:
		assert_same(scene.get_node_or_null(controller.get_path_to(rifle) if controller.is_inside_tree() else ^"Player/Head/Rifle"), rifle, "the rifle is reachable by path")
		assert_same(controller.rifle, rifle, "the match's rifle is that one")
		assert_not_null(controller.player, "the match has its player body")
	scene.free()


func test_the_guard_spawn_stands_on_solid_floor_on_every_map() -> void:
	for map: MapDefinition in MapCatalog.all():
		var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
		rules.map_id = map.id
		rules.prisoner_count = 1
		rules.open_with_race = false
		rules.open_with_tower_brawl = false
		_world = BotMatchWorld.new()
		add_child(_world)
		_world.build(rules)
		var controller: MatchController = _world.get_controller()
		controller.start_match()
		await step_ticks(GUARD_SETTLE_TICKS)
		var spawn: Marker3D = controller.arena.get_node_or_null(controller.spawn_marker_path) as Marker3D
		var guard: MatchParticipant = controller.get_seat_participant()
		if assert_not_null(spawn, "%s has a TowerSpawn" % map.id) and assert_not_null(guard, "%s has a guard" % map.id):
			var at: Vector3 = spawn.global_position
			var space: PhysicsDirectSpaceState3D = controller.arena.get_world_3d().direct_space_state
			var down: Dictionary = space.intersect_ray(
				PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, 1, [guard.body.get_rid()])
			)
			if assert_false(down.is_empty(), "%s: there is floor under the guard's spawn at %s" % [map.id, at]):
				var floor_y: float = (down["position"] as Vector3).y
				assert_between(at.y - floor_y, -SPAWN_FLOAT_METRES, SPAWN_DROP_METRES, "%s: the guard's spawn is a short drop over the floor" % map.id)
				assert_true(guard.body.is_on_floor(), "%s: the placed guard stands on the floor" % map.id)
				assert_almost_eq(guard.body.global_position.y, floor_y, SPAWN_FLOAT_METRES, "%s: the placed guard's feet are at floor height" % map.id)
		remove_child(_world)
		_world.free()
		_world = null
		await step_ticks(2)


## A round on [param map] with the host in the tower, every machine in it.
func _start_round(map: StringName, clients: int) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("the loopback handshake did not complete")
		return false
	_rig.settings().rounds_to_win_match = 3
	_rig.settings().map_id = map
	if not await _rig.launch(clients + 3, HOST):
		fail("the match never started on every machine")
		return false
	for peer: int in _rig.peer_count():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	for peer: int in range(1, _rig.peer_count()):
		var link: PlayerNetLink = _rig.net_match(peer).get_local_link()
		if not await _rig.wait_for(func() -> bool: return link.is_predicting()):
			fail("peer %d's own body was never placed" % peer)
			return false
	await step_ticks(CROSS_TICKS)
	TestFixtures.pin_the_field(_rig.controller(HOST), null)
	return true


func _client_input() -> BotIntentSource:
	return (_rig.matches[CLIENT].get_node("Player") as PlayerController).intent_source as BotIntentSource


## Every machine has [param slot] dead of [param cause]; false after failing.
func _every_machine_has_it_dead(slot: int, cause: MatchParticipant.DeathCause, why: String) -> bool:
	var seen: bool = await _rig.wait_for(func() -> bool:
		for peer: int in _rig.peer_count():
			if not _rig.participant(peer, slot).is_ghost:
				return false
		return true)
	for peer: int in _rig.peer_count():
		var who: MatchParticipant = _rig.participant(peer, slot)
		assert_true(who.is_ghost, "%s: peer %d has slot %d dead" % [why, peer, slot])
		assert_false(who.is_running, "%s: peer %d has it out of the round" % [why, peer])
	assert_eq_int(int(_rig.participant(HOST, slot).death_cause), int(cause), "%s: the host's cause of death" % why)
	assert_eq_int(int(_rig.participant(_owner_of(slot), slot).death_cause), int(cause), "%s: the cause its own machine is told" % why)
	return seen and not is_failed()


## The machine whose own body [param slot] is.
func _owner_of(slot: int) -> int:
	for peer: int in _rig.peer_count():
		if _rig.local_slot(peer) == slot:
			return peer
	return HOST


## The host put [param slot] back in the world as a ghost and its own machine drives it.
func _back_as_a_ghost(slot: int) -> bool:
	var host: MatchController = _rig.controller(HOST)
	var host_side: MatchParticipant = _rig.participant(HOST, slot)
	if not await _rig.wait_for(func() -> bool:
		return host_side.is_ghost and not host.is_awaiting_respawn(host_side) and moves(host_side.body), 8000):
		fail("the host never put slot %d back as a ghost" % slot)
		return false
	await step_ticks(CROSS_TICKS)
	var owner: int = _owner_of(slot)
	return assert_true(moves(_rig.body(owner, slot)), "slot %d's own machine drives its ghost again" % slot)


func _start_point(peer: int) -> Vector3:
	var controller: MatchController = _rig.controller(peer)
	return (controller.arena.get_node(controller.start_marker_path) as Marker3D).global_position


## The middle of the map's pit, as the host's kill volume has it.
func _pit_point() -> Vector3:
	for node: Node in _rig.controller(HOST).arena.find_children("*", "Area3D", true, false):
		if node is KillVolume:
			for child: Node in node.get_children():
				if child is CollisionShape3D:
					return (child as CollisionShape3D).global_position
	return Vector3.INF


## A client holding jump on hell's lava river dies of it on every machine, then falls in the pit as a ghost and is put back.
func _a_hopping_client_dies_on_the_lava(clients: int) -> void:
	if not await _start_round(HELL, clients):
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	var river: TrapVolume = host.arena.get_node_or_null(LAVA_RIVER) as TrapVolume
	if not assert_not_null(river, "hell has its S2 lava river"):
		return
	var victim: MatchParticipant = _rig.participant(HOST, slot)
	victim.body.movement_locked = false
	var keys: BotIntentSource = _client_input()
	keys.command.move_direction = Vector2(0.0, 1.0)
	keys.command.jump_held = true
	keys.command.jump_pressed = true
	# The hop has to be the client's own, arrived over the wire, before the lava is under it.
	if not await _rig.wait_for(func() -> bool: return victim.body.get_intent().jump_held and not victim.body.is_on_floor()):
		fail("the client's held jump never reached the host")
		return
	victim.body.global_position = river.global_position + Vector3.UP * 0.3
	var airborne: Array[int] = [0]
	var count_air: Callable = func() -> void:
		if victim.is_running and not victim.body.is_on_floor():
			airborne[0] += 1
	get_tree().physics_frame.connect(count_air)
	var dead: bool = await _every_machine_has_it_dead(slot, MatchParticipant.DeathCause.LAVA, "hopping on the river")
	get_tree().physics_frame.disconnect(count_air)
	assert_gt(float(airborne[0]), 3.0, "the host's copy was hopping on the lava, not standing in it")
	if not dead:
		return
	keys.command.clear()
	if not await _back_as_a_ghost(slot):
		return
	await _a_ghost_falls_in_the_pit(slot)


## The ghost in [param slot] is dropped into the pit on the host and is back at the start on every machine.
func _a_ghost_falls_in_the_pit(slot: int) -> void:
	var host: MatchController = _rig.controller(HOST)
	var falls: Array[int] = []
	host.ghost_fell.connect(func(who: MatchParticipant) -> void: falls.append(who.index))
	var pit: Vector3 = _pit_point()
	if not assert_true(pit.is_finite(), "the map has a pit to fall in"):
		return
	var ghost: MatchParticipant = _rig.participant(HOST, slot)
	ghost.body.velocity = Vector3.ZERO
	ghost.body.global_position = pit
	if not await _rig.wait_for(func() -> bool: return not falls.is_empty()):
		fail("the pit did not catch the ghost at %s" % pit)
		return
	assert_eq_int(falls[0], slot, "it is that ghost the host rules fallen")
	if not await _back_as_a_ghost(slot):
		return
	await step_ticks(CROSS_TICKS)
	assert_eq_int(falls.size(), 1, "and it fell once, not for ever")
	for peer: int in _rig.peer_count():
		var seen: MatchParticipant = _rig.participant(peer, slot)
		assert_true(seen.is_ghost, "peer %d still has it a ghost" % peer)
		var at: Vector3 = seen.body.global_position
		assert_lt(at.distance_to(_start_point(peer)), START_REACH_METRES, "peer %d draws the ghost back at the start (at %s)" % [peer, at])
	# And it runs: the ghost its owner drives moves on the host.
	var from: Vector3 = ghost.body.global_position
	ghost.body.movement_locked = false
	_rig.drive(_owner_of(slot), Vector2(0.0, 1.0))
	await step_ticks(90)
	assert_gt(ghost.body.global_position.distance_to(from), 1.0, "the ghost its owner drives moves on the host")
	var first: String = _log.lines[0] if _log.count() > 0 else ""
	assert_eq_int(_log.count(), 0, "engine errors (first: %s)" % first)


func test_hell_two_machines_a_hopping_client_dies_on_the_lava_and_its_ghost_survives_the_pit() -> void:
	await _a_hopping_client_dies_on_the_lava(1)


func test_hell_four_machines_a_hopping_client_dies_on_the_lava_and_its_ghost_survives_the_pit() -> void:
	await _a_hopping_client_dies_on_the_lava(3)


## Every machine's copy of the door at [param path].
func _doors(path: NodePath) -> Array[TrapDoor]:
	var doors: Array[TrapDoor] = []
	for peer: int in _rig.peer_count():
		doors.append(_rig.controller(peer).arena.get_node_or_null(path) as TrapDoor)
	return doors


## Marble: the host trips the trapdoor under a client; it opens on every machine and the client dies on every machine.
func _the_trapdoor_drops_a_client(clients: int) -> void:
	if not await _start_round(MARBLE, clients):
		return
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	var doors: Array[TrapDoor] = _doors(SHOT_DOOR)
	for peer: int in _rig.peer_count():
		if not assert_not_null(doors[peer], "peer %d's marble has the section B trapdoor" % peer):
			return
		assert_true(doors[peer].is_armed(), "peer %d's door starts armed" % peer)
	var victim: MatchParticipant = _rig.participant(HOST, slot)
	victim.body.movement_locked = false
	victim.body.velocity = Vector3.ZERO
	victim.body.global_position = doors[HOST].global_transform * ON_DOOR_LOCAL
	await step_ticks(CROSS_TICKS)
	assert_true(victim.is_running and not victim.is_ghost, "the closed door holds the client up alive")
	assert_almost_eq(victim.body.global_position.y, doors[HOST].global_position.y, 0.4, "at deck height")
	for peer: int in range(1, _rig.peer_count()):
		assert_false(doors[peer].pull(), "peer %d cannot trip the door itself" % peer)
	assert_true(doors[HOST].pull(), "the host trips the door")
	var open_everywhere: bool = await _rig.wait_for(func() -> bool:
		for door: TrapDoor in doors:
			if not door.is_open():
				return false
		return true)
	for peer: int in _rig.peer_count():
		assert_true(open_everywhere or doors[peer].is_open(), "peer %d sees the door go" % peer)
	if not await _every_machine_has_it_dead(slot, MatchParticipant.DeathCause.LAVA, "through the trapdoor"):
		return
	if not await _back_as_a_ghost(slot):
		return
	await _a_ghost_falls_in_the_pit(slot)


func test_marble_two_machines_the_trapdoor_drops_a_client_and_its_ghost_survives_the_pit() -> void:
	await _the_trapdoor_drops_a_client(1)


func test_marble_four_machines_the_trapdoor_drops_a_client_and_its_ghost_survives_the_pit() -> void:
	await _the_trapdoor_drops_a_client(3)


## Bots play hell and marble: no living runner that is free to move stands on one spot for ten seconds.
func test_no_living_bot_stands_frozen_for_ten_seconds_on_hell_or_marble() -> void:
	for map: StringName in [HELL, MARBLE]:
		var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
		rules.map_id = map
		rules.prisoner_count = 3
		rules.open_with_race = false
		rules.open_with_tower_brawl = false
		rules.rounds_to_win_match = 99
		_world = BotMatchWorld.new()
		add_child(_world)
		_world.build(rules, STALL_SEED)
		var controller: MatchController = _world.get_controller()
		controller.start_match()
		var anchors: Dictionary[int, Vector3] = {}
		var held: Dictionary[int, int] = {}
		var worst: int = 0
		for _tick: int in STALL_MATCH_TICKS:
			await step_ticks(1)
			for participant: MatchParticipant in controller.get_participants():
				var body: PlayerController = participant.body
				var free: bool = (
					participant.is_running and not participant.is_ghost and participant.brain != null
					and moves(body) and not body.movement_locked
					and controller.get_phase() == MatchController.Phase.ROUND and not controller.is_resolved()
				)
				var anchor: Vector3 = anchors.get(participant.index, Vector3.INF)
				if not free or not anchor.is_finite() or body.global_position.distance_to(anchor) > STALL_METRES:
					anchors[participant.index] = body.global_position
					held[participant.index] = 0
					continue
				held[participant.index] += 1
				worst = maxi(worst, held[participant.index])
				if held[participant.index] == STALL_TICKS:
					fail("%s: %s stood within %.1f m of %s for ten seconds, alive and free to move" % [map, participant.display_name, STALL_METRES, anchor])
		print("      %s: longest a free runner stood still was %.1f s" % [map, float(worst) / SIM_HZ])
		assert_lt(float(worst) / SIM_HZ, float(STALL_TICKS) / SIM_HZ, "%s: the longest any free runner stood still, in seconds" % map)
		assert_gt(float(worst), 0.0, "%s: runners were watched while free to move" % map)
		assert_ge(float(controller.get_round_number()), 1.0, "%s: a round was played" % map)
		remove_child(_world)
		_world.free()
		_world = null
		await step_ticks(2)
