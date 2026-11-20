extends TestCase

## Phase 6: a trap door's cycle is a prop record, so a peer that stands mid-cycle sees the host's phase.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const MARBLE: StringName = &"marble"
const DOOR: NodePath = ^"Elements/SectionB/Trapdoor1"
const HOST: int = 0
const LATE: int = 2
const OPEN_TICKS: int = 60

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _door(peer: int) -> TrapDoor:
	return _rig.controller(peer).arena.get_node_or_null(DOOR) as TrapDoor


func test_a_peer_standing_mid_trap_cycle_sees_the_door_at_the_hosts_phase() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return
	_rig.settings().map_id = MARBLE
	var late: Array[int] = [LATE]
	if not await _rig.launch(4, HOST, late):
		fail("the match never started")
		return
	var host: TrapDoor = _door(HOST)
	if not assert_not_null(host, "the host's marble has the door"):
		return
	assert_true(host.pull(), "the host trips the door")
	await step_ticks(OPEN_TICKS)
	if not assert_true(host.is_open(), "it is open on the host"):
		return
	if not await _rig.bind_late(LATE):
		fail("the late peer never bound")
		return
	await step_ticks(20)
	var mine: TrapDoor = _door(LATE)
	if not assert_not_null(mine, "the late peer's marble has the door"):
		return
	print("PROOF trapdoor late: host phase %d, late phase %d" % [host.get_phase(), mine.get_phase()])
	assert_eq_int(int(mine.get_phase()), int(host.get_phase()), "the late peer's door is at the host's phase")
	assert_true(mine.is_open(), "so it stands open there too")
	var closed: bool = await _rig.wait_for(func() -> bool: return host.is_armed() and mine.is_armed(), 15000)
	assert_true(closed, "and both re-arm")


## Every phase of one cycle over a bad line, as a client draws it and as its leaves collide there: each phase once, in order.
func test_a_client_steps_through_each_phase_of_a_cycle_once() -> void:
	# A jittery, lossy line from the host: the playout clock bends, and records arrive unevenly.
	var line: NetConditions = NetConditions.new(11)
	line.delay_ms = 40.0
	line.jitter_ms = 30.0
	line.loss = 0.05
	_rig.wire_conditions[HOST] = line
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return
	_rig.settings().map_id = MARBLE
	if not await _rig.launch(3, HOST):
		fail("the match never started")
		return
	await step_ticks(30)
	var host: TrapDoor = _door(HOST)
	var mine: TrapDoor = _door(1)
	if not assert_true(host != null and mine != null, "both marbles have the door"):
		return
	var leaf: AnimatableBody3D = mine.find_children("*Body", "AnimatableBody3D", false, false)[0] as AnimatableBody3D
	var phases: Array[int] = [int(mine.get_phase())]
	var layers: Array[int] = [leaf.collision_layer]
	var sample: Callable = func() -> void:
		if int(mine.get_phase()) != phases[-1]:
			phases.append(int(mine.get_phase()))
		if leaf.collision_layer != layers[-1]:
			layers.append(leaf.collision_layer)
	get_tree().physics_frame.connect(sample)
	get_tree().process_frame.connect(sample)
	assert_true(host.pull(), "the host trips the door")
	var done: bool = await _rig.wait_for(func() -> bool: return phases.size() > 1 and host.is_armed() and mine.is_armed(), 20000)
	await step_ticks(30)
	get_tree().physics_frame.disconnect(sample)
	get_tree().process_frame.disconnect(sample)
	assert_true(done, "the cycle ran out on both")
	var cycle: Array[int] = [
		TrapDoor.Phase.ARMED, TrapDoor.Phase.WARN, TrapDoor.Phase.DROP, TrapDoor.Phase.OPEN,
		TrapDoor.Phase.CLOSE, TrapDoor.Phase.COOLDOWN, TrapDoor.Phase.ARMED,
	]
	assert_eq_string(str(phases), str(cycle), "the client entered each phase once, in order")
	assert_eq_string(str(layers), str([1, 0, 1]), "its leaves stopped holding once and held again once")
