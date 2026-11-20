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


## With a few ticks each way every replay spans several commands: each one replayed once this machine has
## heard of the pull must meet the leaves as the host's run of it did, across OPEN to CLOSE and every boundary.
func test_a_replay_across_a_door_boundary_meets_the_leaves_as_the_host_did() -> void:
	for peer: int in 2:
		var line: NetConditions = NetConditions.new(21 + peer)
		# Real milliseconds under the suite's compressed clock: about 6 ticks.
		line.delay_ms = 2.0
		_rig.wire_conditions[peer] = line
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return
	_rig.settings().map_id = MARBLE
	if not await _rig.launch(3, HOST):
		fail("the match never started")
		return
	var own_link: PlayerNetLink = _rig.net_match(1).get_local_link()
	if not await _rig.wait_for(func() -> bool: return own_link.is_predicting() and _rig.sessions[1].replicator.outbox.get_acked() >= 0):
		fail("the client's commands never ran on the host")
		return
	await step_ticks(120)
	var host: TrapDoor = _door(HOST)
	var mine: TrapDoor = _door(1)
	var slot: int = _rig.local_slot(1)
	var own: PlayerController = _rig.body(1, slot)
	var host_leaf: AnimatableBody3D = host.find_children("*Body", "AnimatableBody3D", false, false)[0] as AnimatableBody3D
	var leaf: AnimatableBody3D = mine.find_children("*Body", "AnimatableBody3D", false, false)[0] as AnimatableBody3D
	# Each command is known by its sequence: on the host by the stream's acknowledgement after the tick
	# that ran it, here by the predicted slot its replay ran from.
	var seat: int = _rig.sessions[1].lobby.get_local_seat_index()
	var host_link: PlayerNetLink = _rig.net_match(HOST).call(&"_link_for_seat", seat)
	var stream: CommandStream = host_link.replicator.stream_for(host_link.owner_peer_id)
	var at_host: Dictionary[int, int] = {}
	var replayed: Array[Array] = []
	var pending: Array[Array] = []
	var host_tick: Dictionary[int, int] = {}
	var host_runs: Array[int] = []
	var host_body: PlayerController = _rig.body(HOST, slot)
	var host_step: Callable = host_body.match_step
	host_body.match_step = func(intent: MoveIntent, swung: bool, authority: bool) -> void:
		host_runs.append(host_leaf.collision_layer)
		host_step.call(intent, swung, authority)
	var ran_on: Dictionary[int, int] = {}
	var last_ack: Array[int] = [-1]
	## The host tick of the pull: a replay counts once this machine holds a snapshot that has it.
	var pulled_at: Array[int] = [1 << 40]
	var own_step: Callable = own.match_step
	own.match_step = func(intent: MoveIntent, swung: bool, authority: bool) -> void:
		if own.replaying:
			pending.append([_rig.sessions[1].replicator.get_latest_tick(), leaf.collision_layer])
		own_step.call(intent, swung, authority)
	var sample: Callable = func() -> void:
		# Every command the host ran last tick, as its run met the leaves, the tick, and how many that tick ran.
		var ack: int = stream.get_ack()
		var tick: int = host_link.replicator.get_tick()
		if last_ack[0] >= 0 and host_runs.size() == ack - last_ack[0]:
			ran_on[tick] = host_runs.size()
			for i: int in host_runs.size():
				at_host[last_ack[0] + 1 + i] = host_runs[i]
				host_tick[last_ack[0] + 1 + i] = tick
		host_runs.clear()
		last_ack[0] = ack
		# A replay runs every slot still unacknowledged, in order, and drops the rest: what is left is it.
		if pending.size() == int(own_link.get(&"_predicted_count")):
			for i: int in pending.size():
				if pending[i][0] >= pulled_at[0]:
					replayed.append([int((own_link.call(&"_slot", i) as RefCounted).get(&"seq")), pending[i][1], pending[i][0]])
		pending.clear()
	get_tree().physics_frame.connect(sample)
	assert_true(host.pull(), "the host trips the door")
	pulled_at[0] = host_link.replicator.get_tick()
	var done: bool = await _rig.wait_for(func() -> bool: return host.is_armed() and mine.is_armed() and host.get_phase() == TrapDoor.Phase.ARMED, 20000)
	await step_ticks(60)
	get_tree().physics_frame.disconnect(sample)
	own.match_step = own_step
	host_body.match_step = host_step
	assert_true(done, "the cycle ran out on both")
	# The client places a command one host tick per command after the snapshot it replays from. Exempt is
	# only a command behind a host tick in that span that ran none or two; every other must match exactly.
	var wrong: Array[Array] = []
	var seen: Dictionary[int, bool] = {}
	for run: Array in replayed:
		if at_host.has(run[0]):
			seen[run[1]] = true
			if at_host[run[0]] != run[1] and _one_a_tick(ran_on, run[2], host_tick[run[0]]):
				wrong.append([run[0], run[1], at_host[run[0]]])
	assert_true(seen.has(0) and seen.has(1), "replays ran with the leaves open and shut: %s (%d replayed, %d host runs, e.g. %s / %s)" % [
		str(seen.keys()), replayed.size(), at_host.size(), str(replayed.slice(0, 3)), str(at_host.keys().slice(0, 3))])
	assert_eq_int(wrong.size(), 0, "every replayed command met the leaves as the host's run did: %s" % str(wrong.slice(0, 12)))



## True when the host ran exactly one command on every tick after [param from] up to [param to].
func _one_a_tick(ran_on: Dictionary[int, int], from: int, to: int) -> bool:
	for tick: int in range(from + 1, to + 1):
		if ran_on.get(tick, 1) != 1:
			return false
	return true
