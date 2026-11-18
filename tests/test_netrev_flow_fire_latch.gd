extends TestCase
## Review proof (match flow): a remote player's click made as a RUNNER is never latched on the host
## and spent as a rifle shot when that player later takes the tower: a command's fire edge is its own.

const Rig: GDScript = preload("res://tests/support/net_match_rig.gd")
const HOST: int = 0
const CLIENT: int = 1
const CROSS_TICKS: int = 30

var _rig: RefCounted = null
var _shots: Array[int] = [0]


var _saved_hz: int = 0
var _saved_scale: float = 1.0


func before_each() -> void:
	_rig = Rig.new()
	_shots = [0]
	# Real time, as NetPowerRig runs: one click is one packet a tick, not a burst a frame.
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


func _start_round() -> bool:
	if not await _rig.connect_peers(self, 1):
		fail("handshake")
		return false
	_rig.settings().rounds_to_win_match = 5
	if not await _rig.launch(3, 0):
		fail("launch")
		return false
	for peer: int in _rig.sessions.size():
		var controller: MatchController = _rig.controller(peer)
		if not await _rig.wait_for(func() -> bool: return controller.get_phase() == MatchController.Phase.ROUND):
			fail("peer %d never reached the round" % peer)
			return false
	await step_ticks(CROSS_TICKS)
	return true


func _client_input() -> BotIntentSource:
	return (_rig.matches[CLIENT].get_node("Player") as PlayerController).intent_source as BotIntentSource


## The client's left mouse button, once: fire and shove share it (project.godot).
func _client_clicks() -> void:
	var input: BotIntentSource = _client_input()
	input.command.fire_pressed = true
	input.command.shove_pressed = true
	# physics_frame is emitted before the nodes tick: two awaits is one polled tick.
	await step_ticks(2)
	var mine: PlayerController = _rig.matches[CLIENT].get_node("Player") as PlayerController
	var slot_dbg: int = _rig.local_slot(CLIENT)
	var link_dbg: PlayerNetLink = _rig.net_match(HOST).call(&"_link_of_slot", slot_dbg)
	var own_link: PlayerNetLink = _rig.net_match(CLIENT).get_local_link()
	var stream: CommandStream = _rig.sessions[HOST].replicator.stream_for(link_dbg.owner_peer_id)
	print("PROOF dbg input=%s client_intent_fire=%s phys=%s predicting=%s host_ack=%d owner=%d" % [
		str(input), str(mine.get_intent().fire_pressed), str(mine.is_physics_processing()),
		str(own_link.is_predicting()), stream.get_ack(), link_dbg.owner_peer_id])
	input.command.fire_pressed = false
	input.command.shove_pressed = false


## The host hands the tower to the client's seat and arms the next round; shots are counted from here.
func _client_takes_the_tower() -> void:
	var host: MatchController = _rig.controller(HOST)
	var slot: int = _rig.local_slot(CLIENT)
	host.rifle.fired.connect(func(_origin: Vector3, _end: Vector3) -> void: _shots[0] += 1)
	host.take_seat(host.get_participants()[slot])
	host.start_round()
	assert_same(host.get_seat_participant(), host.get_participants()[slot], "the client's seat holds the tower")


func test_control_a_client_that_never_clicked_fires_nothing_on_taking_the_tower() -> void:
	if not await _start_round():
		return
	TestFixtures.pin_the_field(_rig.controller(HOST), null)
	await step_ticks(60)
	_client_takes_the_tower()
	await step_ticks(120)
	print("PROOF control shots=%d" % _shots[0])
	assert_eq_int(_shots[0], 0, "nobody pressed anything: no shot")


func test_a_click_made_as_a_runner_is_not_a_shot_when_that_player_takes_the_tower() -> void:
	if not await _start_round():
		return
	var host: MatchController = _rig.controller(HOST)
	TestFixtures.pin_the_field(host, null)
	# One click as a runner (a shove swing), then hands off for two full seconds.
	await _client_clicks()
	await step_ticks(120)
	var slot: int = _rig.local_slot(CLIENT)
	var link: PlayerNetLink = _rig.net_match(HOST).call(&"_link_of_slot", slot)
	print("PROOF fire down on the host's copy before the seat change: %s" % str(link.controller.get_intent().fire_held))
	_client_takes_the_tower()
	var fired_at: int = -1
	for tick: int in 120:
		await step_ticks(1)
		if _shots[0] > 0 and fired_at < 0:
			fired_at = tick
	print("PROOF shots=%d first at tick %d after start_round (settle is %d frames)" % [
		_shots[0], fired_at, MatchController.SETTLE_PHYSICS_FRAMES])
	assert_eq_int(_shots[0], 0, "the client pressed nothing in the tower: the rifle does not fire")
