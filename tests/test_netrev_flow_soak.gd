extends TestCase
## Review soak (match flow): random host decisions for many rounds; after each, every peer must
## converge on the host's phase, round, seat, finisher and each participant's role.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const STEPS: int = 70

var _rig: RefCounted = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _start(clients: int, seats: int, guard: int, late: Array[int] = []) -> bool:
	if not await _rig.connect_peers(self, clients):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 4
	if not await _rig.launch(seats, guard, late):
		fail("launch")
		return false
	return true


func _state_of(peer: int) -> String:
	var controller: MatchController = _rig.controller(peer)
	var seat: MatchParticipant = controller.get_seat_participant()
	var finisher: MatchParticipant = controller.get_finisher()
	var winner: MatchParticipant = controller.get_match_winner()
	var out: String = "%s r%d seat%d fin%d out%d win%d |" % [
		controller.get_phase_name(), controller.get_round_number(), seat.index if seat != null else -1,
		finisher.index if finisher != null else -1, int(controller.get_outcome()), winner.index if winner != null else -1]
	for p: MatchParticipant in controller.get_participants():
		out += " %d:%s%s%s%s%s" % [p.index, "R" if p.is_running else "-", "G" if p.is_ghost else "-",
			"S" if p.is_shooter else "-", "F" if p.is_finisher else "-", "h" if p.is_human() else "b"]
	return out


func _peers() -> Array[int]:
	var live: Array[int] = []
	for peer: int in _rig.peer_count():
		if _rig.matches[peer] != null and _rig.sessions[peer].is_established():
			live.append(peer)
	return live


func _agree(step: int, what: String) -> bool:
	var agreed: bool = await _rig.wait_for(func() -> bool:
		var want: String = _state_of(HOST)
		for peer: int in _peers():
			if _state_of(peer) != want:
				return false
		return true, 3000)
	if not agreed:
		fail("step %d after '%s': peers never agreed" % [step, what])
		for peer: int in _peers():
			print("PROOF soak DIVERGED step %d after %s peer %d: %s" % [step, what, peer, _state_of(peer)])
	return agreed


## One random decision on the host, made through the same doors play uses. Returns its name.
func _decide() -> String:
	var host: MatchController = _rig.controller(HOST)
	var people: Array[MatchParticipant] = host.get_participants()
	if host.is_match_over():
		host.restart()
		return "restart"
	if host.get_phase() == MatchController.Phase.RACE:
		var racer: MatchParticipant = people[_rng.randi_range(0, people.size() - 1)]
		if _rng.randf() < 0.5:
			host.handle_fall(racer, true)
			return "race fall %d" % racer.index
		host.call(&"_on_participant_arrived", 1.0, 1.0, racer)
		return "race won by %d" % racer.index
	if host.get_phase() != MatchController.Phase.ROUND:
		return "wait (%s)" % host.get_phase_name()
	var pick: MatchParticipant = people[_rng.randi_range(0, people.size() - 1)]
	var roll: float = _rng.randf()
	if roll < 0.30:
		if pick.is_running:
			host.apply_hit(pick)
			return "hit %d" % pick.index
	elif roll < 0.45:
		host.handle_fall(pick, _rng.randf() < 0.5)
		return "fall %d" % pick.index
	elif roll < 0.60:
		if pick.is_ghost and host.call(&"_ghost_is_in_the_world", pick):
			for other: MatchParticipant in people:
				if other.is_running and not other.is_finisher:
					host.call(&"_swap_with_ghost", pick, other)
					return "catch %d takes %d" % [pick.index, other.index]
	elif roll < 0.75:
		if pick.is_running and host.get_finisher() == null:
			host.call(&"_on_participant_arrived", 1.0, 1.0, pick)
			return "arrive %d" % pick.index
	elif roll < 0.88:
		if host.get_finisher() != null:
			host.throw_guard(host.get_seat_participant(), Vector3.FORWARD)
			return "finale"
	else:
		for other: MatchParticipant in people:
			if other.is_running:
				host.convert_participant(other)
		return "ring cleared"
	return "nothing"


func _soak(seed_value: int, leaver_at: int, late_peer: int) -> void:
	_rng.seed = seed_value
	var decisions: Dictionary[String, int] = {}
	for step: int in STEPS:
		if step == leaver_at:
			_rig.sessions[1].leave()
			await step_ticks(20)
			if not await _agree(step, "client 1 leaves"):
				return
		if step == 12 and late_peer >= 0:
			if not await _rig.bind_late(late_peer):
				fail("late peer never bound")
				return
			if not await _agree(step, "late peer binds"):
				return
		var what: String = _decide()
		var kind: String = what.split(" ")[0]
		decisions[kind] = int(decisions.get(kind, 0)) + 1
		await step_ticks(_rng.randi_range(1, 40))
		if not await _agree(step, what):
			return
	print("PROOF soak seed %d ok: %s final %s" % [seed_value, str(decisions), _state_of(HOST)])
	assert_true(true, "every step converged")


func test_soak_guard_opening_three_humans_two_bots() -> void:
	if not await _start(2, 5, 0):
		return
	await _soak(11, -1, -1)


func test_soak_race_opening_three_humans_one_bot() -> void:
	if not await _start(2, 4, -1):
		return
	await _soak(23, -1, -1)


func test_soak_with_a_client_leaving_midway() -> void:
	if not await _start(2, 5, 1):
		return
	await _soak(37, 25, -1)


func test_soak_four_humans_with_a_late_peer() -> void:
	if not await _start(3, 5, 0, [3]):
		return
	await _soak(41, 40, 3)
