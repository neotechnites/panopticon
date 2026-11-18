extends TestCase
## Review proof: a click a client made as a runner is still latched on the host when that
## client later takes the tower, and fires the rifle with no key down.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CLIENT: int = 1

var _rig: RefCounted = null


func before_each() -> void:
	_rig = Rig.new()


func after_each() -> void:
	if _rig != null:
		_rig.close()
		_rig = null


func _run(click_as_runner: bool) -> int:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return -1
	_rig.settings().rounds_to_win_match = 3
	if not await _rig.launch(3, 0):
		fail("the match never started")
		return -1
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	if not await _rig.wait_for(func() -> bool:
		return host.get_phase() == MatchController.Phase.ROUND and mirror.get_phase() == MatchController.Phase.ROUND):
		fail("no round")
		return -1
	await step_ticks(40)
	var slot: int = _rig.local_slot(CLIENT)
	var input: BotIntentSource = (_rig.matches[CLIENT].get_node("Player") as PlayerController).intent_source as BotIntentSource
	if click_as_runner:
		# One left click as a runner: the shove key and the trigger are the same button.
		# (Held over many ticks only because the runner's 50x clock drops most intent packets.)
		input.command.fire_pressed = true
		await step_ticks(100)
		input.command.fire_pressed = false
	await step_ticks(40)
	var shots: Array[int] = [0]
	host.rifle.fired.connect(func(_origin: Vector3, _end: Vector3) -> void: shots[0] += 1)
	# The tower changes hands: the client is the guard of a fresh match on the same scene.
	host.get_rules().opening_seat_index = slot
	host.restart()
	if not await _rig.wait_for(func() -> bool:
		var seat: MatchParticipant = host.get_seat_participant()
		return host.get_phase() == MatchController.Phase.ROUND and seat != null and seat.index == slot):
		fail("the client never took the tower")
		return -1
	await step_ticks(180)
	print("PROOF fire-latch: clicked=%s; shots fired in 3 s with the client in the tower and no key down: %d" % [str(click_as_runner), shots[0]])
	return shots[0]


func test_rv_control_no_click_no_shot() -> void:
	var shots: int = await _run(false)
	assert_eq_int(shots, 0, "control: a client that never clicked fires nothing on taking the tower")


func test_rv_a_runner_click_is_not_a_shot_a_round_later() -> void:
	var shots: int = await _run(true)
	assert_eq_int(shots, 0, "a click made as a runner fires nothing when the client takes the tower")
