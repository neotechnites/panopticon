extends "res://tests/support/net_hub_rig.gd"

## Phase 6: the hub's bodies are reconciled per seat, and a prop's id does not depend on the tree at bind.

const ORB_SCENE_PATH: String = "res://props/speed_powerup.tscn"
const JOIN_LOAD_TICKS: int = 60

## Per machine: the stand-in match its rounds-only gate follows, and the orb under that gate.
var _stubs: Array[PhaseStub] = [null, null, null]
var _orbs: Array[SpeedPowerup] = [null, null, null]


func after_each() -> void:
	super()
	for stub: PhaseStub in _stubs:
		if is_instance_valid(stub):
			stub.free()
	_stubs = [null, null, null]
	_orbs = [null, null, null]


func test_a_join_in_the_hub_moves_nobody_else() -> void:
	if not await stand_up(0.0, 0, 2):
		return
	if not await lift_hub_cat(A):
		return
	await step_ticks(30)
	var kept: Array[int] = _ids([body(HOST, HOST), body(HOST, A), body(A, HOST), body(A, A)])
	var host_at: Vector3 = body(HOST, HOST).global_position
	var a_at: Vector3 = body(HOST, A).global_position
	var placed: Array[int] = count(net(A).get_local_link().placed)
	if not await join_late(B, JOIN_LOAD_TICKS):
		return
	await step_ticks(30)
	var now: Array[int] = _ids([body(HOST, HOST), body(HOST, A), body(A, HOST), body(A, A)])
	assert_eq_string(str(now), str(kept), "the host and A keep every body they had (host's own, host's A, A's host, A's own)")
	assert_eq_int(placed[0], 0, "A's own body was not placed again")
	assert_lt(flat_distance(body(HOST, HOST).global_position, host_at), 0.5, "the host stayed put")
	assert_lt(flat_distance(body(HOST, A).global_position, a_at), 0.5, "A stayed put on the host")
	assert_true(HubCat.is_carrying(body(HOST, A)), "A still carries the hub cat on the host")
	assert_true(holds_locally(A), "and A is still offered the pet")
	assert_lt(
		cat(B, HUB_CAT).global_position.distance_to(cat(HOST, HUB_CAT).global_position), 0.6,
		"the joiner draws the cat in A's hands where the host has it",
	)


func test_a_leave_in_the_hub_recolours_nobody_and_each_machine_keeps_its_own_player() -> void:
	if not await stand_up():
		return
	await step_ticks(10)
	var before: Array[String] = [_shirt(HOST, HOST), _shirt(HOST, B), _shirt(B, HOST), _shirt(B, B)]
	leave(A)
	var freed: bool = await until(func() -> bool:
		return ctrl(HOST).get_participants().size() == 2 and ctrl(B).get_participants().size() == 2)
	if not assert_true(freed, "the host and B freed A's seat"):
		return
	await step_ticks(10)
	var after: Array[String] = [_shirt(HOST, HOST), _shirt(HOST, B), _shirt(B, HOST), _shirt(B, B)]
	assert_eq_string(str(after), str(before), "nobody's shirt changed colour when A left")
	assert_same(ctrl(B).get_human_participant().body, body(B, B), "B's own player is still B's body")
	assert_same(ctrl(HOST).get_human_participant().body, body(HOST, HOST), "and the host's is the host's")


## The colour [param machine] paints [param seat]'s shirt.
func _shirt(machine: int, seat: int) -> String:
	for participant: MatchParticipant in ctrl(machine).get_participants():
		if participant.body == body(machine, seat):
			return str(participant.home_body_material.get(&"albedo_color")) if participant.home_body_material != null else "none"
	return "missing"


func test_a_prop_behind_a_removed_phase_gate_keeps_its_id_on_a_late_binder() -> void:
	prepare_hub = _gate_an_orb
	if not await stand_up(0.0, 0, 2):
		return
	if not await join_late(B, JOIN_LOAD_TICKS):
		return
	for machine: int in 3:
		if not assert_false(_orbs[machine].is_inside_tree(), "machine %d's gate took its orb out at bind" % machine):
			return
	for machine: int in 3:
		_stubs[machine].enter(MatchController.Phase.ROUND)
	await step_ticks(10)
	for machine: int in 3:
		assert_true(_orbs[machine].is_inside_tree() and _orbs[machine].is_armed(), "machine %d's orb is back, armed" % machine)
	_orbs[HOST].call(&"_on_body_entered", body(HOST, HOST))
	assert_false(_orbs[HOST].is_armed(), "the host's orb is taken")
	var followed: bool = await until(func() -> bool: return not _orbs[A].is_armed() and not _orbs[B].is_armed())
	assert_true(followed, "A and the late binder B take the gated orb's record: A %s, B %s" % [
		str(_orbs[A].is_armed()), str(_orbs[B].is_armed())])


func test_an_orb_taken_before_a_late_binder_arrives_is_taken_on_it() -> void:
	prepare_hub = _gate_an_orb.bind(MatchController.Phase.ROUND)
	if not await stand_up(0.0, 0, 2):
		return
	await step_ticks(10)
	_orbs[HOST].call(&"_on_body_entered", body(HOST, HOST))
	if not assert_true(await until(func() -> bool: return not _orbs[A].is_armed()), "A takes the host's taken orb"):
		return
	if not await join_late(B, JOIN_LOAD_TICKS):
		return
	assert_true(_orbs[B].is_inside_tree(), "the late binder's gate holds its orb in the rounds")
	assert_true(await until(func() -> bool: return not _orbs[B].is_armed()), "the late binder draws the orb taken, from its record alone")


func _ids(bodies: Array[PlayerController]) -> Array[int]:
	var ids: Array[int] = []
	for found: PlayerController in bodies:
		ids.append(found.get_instance_id() if found != null else 0)
	return ids


## A rounds-only gate holding an orb, following a stand-in match in [param phase].
func _gate_an_orb(machine: int, hub: Node3D, phase: int = MatchController.Phase.RACE) -> void:
	var stub: PhaseStub = PhaseStub.new()
	stub.phase = phase
	_stubs[machine] = stub
	var gate: PhaseGate = PhaseGate.new()
	gate.name = "RoundsGate"
	gate.phase = PhaseGate.ROUNDS_ONLY
	gate.auto_discover = false
	gate.controller = stub
	var orb: SpeedPowerup = (load(ORB_SCENE_PATH) as PackedScene).instantiate() as SpeedPowerup
	orb.name = "Orb"
	orb.race_only = false
	orb.auto_discover = false
	orb.collision_mask = 0
	gate.add_child(orb)
	hub.get_node("HubWorld").add_child(gate)
	_orbs[machine] = orb


## What a [PhaseGate] needs of a match: [signal MatchController.structure_changed] and its phase.
class PhaseStub:
	extends Node

	signal structure_changed(phase: int)

	var phase: int = MatchController.Phase.RACE

	func get_phase() -> int:
		return phase

	func enter(next: int) -> void:
		phase = next
		structure_changed.emit(next)
