extends TestCase

## H5: the speed orb in the shipped match scene (hell), through NetMatch: a late peer and a rematch.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _orb(peer: int) -> SpeedPowerup:
	for node: Node in (_rig.matches[peer] as Node).find_children("*", "Area3D", true, false):
		if node is SpeedPowerup:
			return node as SpeedPowerup
	return null


## In one process every orb's discovery walks up to the test case and finds the host's controller; re-point it.
func _own_controller(peer: int) -> void:
	var orb: SpeedPowerup = _orb(peer)
	var wrong: Node = orb.get("_controller")
	var right: MatchController = _rig.controller(peer)
	if wrong == right:
		return
	if wrong != null:
		wrong.disconnect(&"race_started", Callable(orb, "_on_race_started"))
		wrong.disconnect(&"round_started", Callable(orb, "_on_round_started"))
	orb.set("_controller", right)
	right.race_started.connect(Callable(orb, "_on_race_started"))
	right.round_started.connect(Callable(orb, "_on_round_started"))


func test_a_late_peer_in_the_race_finds_the_taken_orb_gone() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return
	var late: Array[int] = [2]
	if not await _rig.launch(3, -1, late):
		fail("the match never started")
		return
	for peer: int in [0, 1]:
		_own_controller(peer)
	var host: MatchController = _rig.controller(0)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.RACE):
		fail("no race, phase %d" % host.get_phase())
		return
	await step_ticks(30)
	var orb: SpeedPowerup = _orb(0)
	if not assert_true(orb != null and _orb(1) != null, "hell has the orb on both machines"):
		return
	print("PROOF h5: before take armed host=%s client1=%s" % [str(orb.is_armed()), str(_orb(1).is_armed())])
	var slot: int = _rig.local_slot(1)
	orb.call(&"_on_body_entered", _rig.body(0, slot))
	await step_ticks(30)
	print("PROOF h5: after take armed host=%s client1=%s boost host=%.2f client1-own=%.2f" % [
		str(orb.is_armed()), str(_orb(1).is_armed()),
		_rig.body(0, slot).get_speed_boost_remaining(), _rig.body(1, slot).get_speed_boost_remaining()])
	assert_false(orb.is_armed(), "host orb gone")
	assert_false(_orb(1).is_armed(), "client 1 orb gone")
	assert_gt(_rig.body(1, slot).get_speed_boost_remaining(), 1.0, "client 1 has the boost on its own body")
	if not await _rig.bind_late(2):
		fail("the late peer never bound")
		return
	await step_ticks(30)
	var late_phase: int = _rig.controller(2).get_phase()
	print("PROOF h5: late peer phase=%d (host %d) orb armed=%s visible=%s" % [late_phase, host.get_phase(), str(_orb(2).is_armed()), str(_orb(2).orb.visible if _orb(2).orb != null else false)])
	assert_false(_orb(2).is_armed(), "the late peer's orb is gone too")
