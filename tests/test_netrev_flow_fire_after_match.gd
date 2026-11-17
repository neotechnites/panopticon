extends TestCase
## Review proof (match flow): a remote guard holding the trigger on the tick the match ends keeps
## firing on the host for as long as the result screen stands (its parked body's last intent is never re-polled).

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CLIENT: int = 1

var _rig: RefCounted = null
var _shots: Array[int] = [0]
var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	_rig = Rig.new()
	_shots = [0]
	_saved_hz = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale
	Engine.physics_ticks_per_second = int(SIM_HZ)
	Engine.time_scale = 1.0
	process_physics_priority = -100


func _physics_process(_delta: float) -> void:
	if _rig == null:
		return
	for session: NetSession in _rig.sessions:
		if session != null and session.multiplayer.has_multiplayer_peer():
			session.multiplayer.poll()


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_hz
	Engine.time_scale = _saved_scale
	if _rig != null:
		_rig.close()
		_rig = null


## Client in the tower (seat 1), host and a bot on the ring, one round wins the match.
func _start_round() -> bool:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 1
	if not await _rig.launch(3, 1):
		fail("launch")
		return false
	for peer: int in _rig.sessions.size():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(30)
	return true


func _client_input() -> BotIntentSource:
	return (_rig.matches[CLIENT].get_node("Player") as PlayerController).intent_source as BotIntentSource


func _end_the_match(holding: bool) -> void:
	var host: MatchController = _rig.controller(HOST)
	var guard: MatchParticipant = host.get_seat_participant()
	assert_eq_int(guard.index, _rig.local_slot(CLIENT), "the client holds the tower")
	TestFixtures.pin_the_field(host, guard)
	host.rifle.fired.connect(func(_origin: Vector3, _end: Vector3) -> void: _shots[0] += 1)
	var input: BotIntentSource = _client_input()
	if holding:
		# The killing click: button down.
		input.command.fire_pressed = true
		input.command.fire_held = true
		await step_ticks(2)
		input.command.fire_pressed = false
		if not await _rig.wait_for(func() -> bool: return _shots[0] >= 1):
			fail("the client's click never fired the host's rifle")
			return
	# That shot clears the ring (converted here as the rifle converts) while the button is still down.
	for participant: MatchParticipant in host.get_participants():
		if participant.is_running:
			host.convert_participant(participant)
	assert_true(host.is_match_over(), "the match is over on the host")
	await step_ticks(6)
	# Button up, a tenth of a second after the click; nothing is pressed from here on.
	input.command.fire_held = false
	var at_end: int = _shots[0]
	var reload: float = host.rifle.reload_seconds
	await step_ticks(int((reload * 3.0 + 2.0) * SIM_HZ))
	print("PROOF holding=%s reload=%.2fs shots at match end=%d, shots in the %.1f s after=%d, phase=%s" % [
		str(holding), reload, at_end, reload * 3.0 + 2.0, _shots[0] - at_end, host.get_phase_name()])
	assert_eq_int(_shots[0] - at_end, 0, "nobody is pressing anything and the match is over: the rifle is quiet")


func test_control_a_guard_not_holding_the_trigger_at_match_end_fires_nothing_after() -> void:
	if not await _start_round():
		return
	await _end_the_match(false)


func test_a_guard_holding_the_trigger_at_match_end_does_not_fire_on_the_result_screen() -> void:
	if not await _start_round():
		return
	await _end_the_match(true)
