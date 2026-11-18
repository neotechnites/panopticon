extends TestCase

## A client guard predicts its own fire gate (DESIGN 3.4 weapon, 7): its shot is drawn on its own
## screen on the tick its command fires, ahead of the host, and the host's SHOT cue skips it so the
## shot is drawn once.

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


func test_a_client_guards_shot_is_drawn_on_its_own_screen_when_it_fires() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return
	var seat: int = (_rig.sessions[CLIENT] as NetSession).lobby.get_local_seat_index()
	if not await _rig.launch(3, seat):
		fail("the match never started")
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	if not await _rig.wait_for(func() -> bool:
		var guard: MatchParticipant = host.get_seat_participant()
		return host.get_phase() == MatchController.Phase.ROUND and mirror.get_phase() == MatchController.Phase.ROUND \
			and guard != null and guard.index == slot and mirror.rifle.can_fire()):
		fail("the client never stood in the tower with a ready rifle")
		return
	await step_ticks(30)
	var drawn: Array[int] = []
	var fired: Array[int] = []
	mirror.rifle.fired.connect(func(_o: Vector3, _e: Vector3) -> void: drawn.append(Engine.get_physics_frames()))
	host.rifle.fired.connect(func(_o: Vector3, _e: Vector3) -> void: fired.append(Engine.get_physics_frames()))
	var input: BotIntentSource = (_rig.matches[CLIENT].get_node("Player") as PlayerController).intent_source as BotIntentSource
	var pressed_at: int = Engine.get_physics_frames()
	input.command.fire_pressed = true
	await step_ticks(3)
	input.command.fire_pressed = false
	var shot: bool = await _rig.wait_for(func() -> bool: return not fired.is_empty())
	await step_ticks(60)
	print("PROOF own-shot: pressed at frame %d; drawn on the client at %s, fired on the host at %s" % [pressed_at, str(drawn), str(fired)])
	if not assert_true(shot, "the host fired the client's shot"):
		return
	if not assert_false(drawn.is_empty(), "the client drew a shot"):
		return
	assert_le(float(drawn[0] - pressed_at), 2.0, "on the tick its command fired, not a round trip later")
	assert_lt(float(drawn[0]), float(fired[0]), "ahead of the host running the command")
	assert_eq_int(drawn.size(), fired.size(), "once per shot: the host's cue skipped the shooter")


func test_a_client_guards_reload_is_heard_once_however_often_it_is_replayed() -> void:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return
	var seat: int = (_rig.sessions[CLIENT] as NetSession).lobby.get_local_seat_index()
	if not await _rig.launch(3, seat):
		fail("the match never started")
		return
	var host: MatchController = _rig.controller(HOST)
	var mirror: MatchController = _rig.controller(CLIENT)
	var slot: int = _rig.local_slot(CLIENT)
	if not await _rig.wait_for(func() -> bool:
		var guard: MatchParticipant = host.get_seat_participant()
		return host.get_phase() == MatchController.Phase.ROUND and guard != null and guard.index == slot \
			and mirror.rifle.can_fire()):
		fail("the client never stood in the tower with a ready rifle")
		return
	await step_ticks(30)
	var cues: Dictionary[String, int] = {"started": 0, "finished": 0, "host": 0}
	mirror.rifle.reload_started.connect(func(_d: float) -> void: cues["started"] += 1)
	mirror.rifle.reload_finished.connect(func() -> void: cues["finished"] += 1)
	host.rifle.reload_finished.connect(func() -> void: cues["host"] += 1)
	var input: BotIntentSource = (_rig.matches[CLIENT].get_node("Player") as PlayerController).intent_source as BotIntentSource
	input.command.fire_pressed = true
	await step_ticks(3)
	input.command.fire_pressed = false
	var reloaded: bool = await _rig.wait_for(func() -> bool: return cues["host"] > 0 and cues["finished"] > 0)
	await step_ticks(60)
	if not assert_true(reloaded, "the shot's reload ran out on the host and on the client"):
		return
	# Every snapshot until the host acknowledges the shot replays the gate through the reload.
	assert_eq_int(cues["started"], 1, "the client heard its reload start once")
	assert_eq_int(cues["finished"], 1, "and end once")
