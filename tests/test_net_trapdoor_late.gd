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
