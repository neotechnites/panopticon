extends TestCase
## Review proof: a hologram that is up when a peer's match binds late.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CLIENT: int = 1
const LATE: int = 2

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func test_rv_a_late_peer_sees_the_hologram_the_others_see() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return
	_rig.settings().rounds_to_win_match = 3
	var late: Array[int] = [LATE]
	if not await _rig.launch(4, 0, late):
		fail("the match never started")
		return
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return
	await step_ticks(30)
	TestFixtures.set_power_duration(600.0)
	TestFixtures.pin_the_field(host, null)
	var slot: int = 3
	var power: RunnerPower = RunnerPower.of(_rig.body(HOST, slot))
	# Through the seat: a pick the roster has not heard of is overruled by the next roster.
	_rig.hold(slot, MatchRules.RunnerAbility.HOLOGRAM)
	assert_true(power.activate(), "the host starts a bot runner's hologram")
	var early: RunnerPower = RunnerPower.of(_rig.body(CLIENT, slot))
	if not await _rig.wait_for(func() -> bool: return early.get_hologram() != null):
		fail("the peer that was there never saw the hologram")
		return
	if not await _rig.bind_late(LATE):
		fail("the late peer never bound")
		return
	await step_ticks(120)
	var mine: RunnerPower = RunnerPower.of(_rig.body(LATE, slot))
	print("PROOF late-hologram: host decoy=%s, early client decoy=%s, late client decoy=%s, late client shows power %d" % [
		str(power.get_decoy() != null), str(early.get_hologram() != null), str(mine.get_hologram() != null), int(mine.get_shown())])
	assert_true(power.get_decoy() != null, "the hologram is still up on the host")
	assert_true(mine.get_hologram() != null, "and the late peer draws it")


## A shield stands where it was raised, and its runner has moved on by the time the late peer binds.
func test_rv_a_late_peer_sees_a_shield_where_the_host_raised_it() -> void:
	if not await _rig.connect_peers(self, 2):
		fail("handshake")
		return
	_rig.settings().rounds_to_win_match = 3
	var late: Array[int] = [LATE]
	if not await _rig.launch(4, 0, late):
		fail("the match never started")
		return
	var host: MatchController = _rig.controller(HOST)
	if not await _rig.wait_for(func() -> bool: return host.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return
	await step_ticks(30)
	TestFixtures.set_power_duration(600.0)
	var slot: int = 3
	var power: RunnerPower = RunnerPower.of(_rig.body(HOST, slot))
	_rig.hold(slot, MatchRules.RunnerAbility.BUBBLE_SHIELD)
	assert_true(power.activate(), "the host raises a running bot's shield")
	var raised_at: Vector3 = power.get_shield().global_position
	await step_ticks(60)
	var ran: float = _rig.body(HOST, slot).global_position.distance_to(raised_at)
	if not await _rig.bind_late(LATE):
		fail("the late peer never bound")
		return
	var mine: RunnerPower = RunnerPower.of(_rig.body(LATE, slot))
	if not await _rig.wait_for(func() -> bool: return mine.get_shield() != null):
		fail("the late peer never drew the shield")
		return
	await step_ticks(10)
	var off: float = mine.get_shield().global_position.distance_to(raised_at)
	print("PROOF late-shield: the runner is %.1f m on from its shield; the late peer's copy stands %.2f m from the host's" % [ran, off])
	assert_gt(ran, 1.0, "the runner has left its shield behind")
	assert_lt(off, 0.05, "the late peer's shield stands where the host raised it")
