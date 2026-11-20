extends TestCase

## The client's playout clock against Godot's main loop: a long frame runs at most
## max_physics_steps_per_frame physics steps, but the host's world went on for all of it.
##
## The main loop is driven by hand, so a frame's length is the test's to choose: each frame
## runs the capped physics steps, then the poll (every snapshot the host made meanwhile),
## then the idle frame, in Godot's order. The host is another machine: its tick follows real time.

## The frame that stalls: a navmesh bake or a scene load on the client.
const HITCH_SECONDS: float = 0.45
## Host ticks between snapshots: 30 Hz on the 60 Hz simulation, as shipped.
const SNAPSHOT_EVERY: int = 2
## Frames at 60 fps before the hitch, for the clock to settle and its depth to be read.
const SETTLE_FRAMES: int = 180
## How long after the hitch the clock must be back, and how close.
const RECOVERED_BY_SECONDS: float = 0.1
const RECOVERED_TICKS: float = 2.0
const SPEED: float = 8.0

var _host: NetSession
var _client: NetSession
var _mirror: PlayerNetLink
var _real_seconds: float = 0.0
var _owed_seconds: float = 0.0
var _base_tick: int = 0
var _sent_tick: int = -1


func before_each() -> void:
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


func _stand_up() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	if not await NetFixtures.stand(self, _host, [_client]):
		return false
	_mirror = NetFixtures.add_seat_body(_client, 1, 0, TestFixtures.movement_profile(), false)
	# This file is the client's main loop from here on.
	_client.replicator.set_physics_process(false)
	_client.replicator.set_process(false)
	_base_tick = 1000
	return true


## The host's present tick: it ran every tick of real time.
func _host_tick() -> int:
	return _base_tick + floori(_real_seconds / SIM_DELTA)


## One client frame of [param seconds], in Godot's order: capped physics steps, poll, idle.
func _frame(seconds: float) -> void:
	_real_seconds += seconds
	_owed_seconds += seconds
	var steps: int = mini(floori(_owed_seconds / SIM_DELTA), Engine.max_physics_steps_per_frame)
	# Godot drops what the cap did not run.
	_owed_seconds = minf(_owed_seconds - float(steps) * SIM_DELTA, SIM_DELTA)
	for _i: int in steps:
		_client.replicator._physics_process(SIM_DELTA)
	var newest: int = _host_tick() - _host_tick() % SNAPSHOT_EVERY
	var tick: int = _sent_tick + SNAPSHOT_EVERY if _sent_tick >= 0 else newest
	while tick <= newest:
		assert_true(_client.replicator.receive_snapshot(_snapshot(tick)), "the snapshot for tick %d is taken" % tick)
		_sent_tick = tick
		tick += SNAPSHOT_EVERY
	_client.replicator.play_back(_real_seconds * SIM_HZ)


func _snapshot(tick: int) -> PackedByteArray:
	var world: WorldSnapshot = WorldSnapshot.new()
	world.tick = tick
	world.epoch = _client.replicator.get_scene()
	var state: PlayerState = world.slot(1)
	state.position = Vector3(SPEED * float(tick - _base_tick) * SIM_DELTA, 0.1, 0.0)
	state.velocity = Vector3(SPEED, 0.0, 0.0)
	NetCodec.quantise_state(state, tick)
	return NetCodec.pack_snapshot(world, null, 0, [] as Array[NetEvents.Entry], NetCodec.SnapshotInfo.new())


## How many ticks behind the host's present the client draws.
func _behind() -> float:
	return float(_host_tick()) - _client.replicator.get_view_time()


func test_a_long_frame_does_not_leave_remote_bodies_drawn_late() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	var settled: float = 0.0
	for i: int in SETTLE_FRAMES:
		_frame(SIM_DELTA)
		if i >= SETTLE_FRAMES - 60:
			settled += _behind() / 60.0
	var depth: float = _client.replicator.get_delay_ticks()
	_frame(HITCH_SECONDS)
	var after: float = 0.0
	while after < RECOVERED_BY_SECONDS:
		_frame(SIM_DELTA)
		after += SIM_DELTA
	var excess: float = _behind() - settled
	print("          drawn %.1f ticks behind the host before a %d ms frame, %.1f ticks more %d ms after it" % [
		settled, int(HITCH_SECONDS * 1000.0), excess, int(RECOVERED_BY_SECONDS * 1000.0),
	])
	assert_between(settled, 0.0, 8.0, "the clock settled a few ticks behind the host")
	assert_le(absf(excess), RECOVERED_TICKS, "a long frame leaves the remote world drawn no later than before it")
	assert_le(_client.replicator.get_delay_ticks(), depth + 0.5, "and the stall is not taken for jitter on the line")
	var drawn_x: float = _mirror.controller.global_position.x
	var host_x: float = SPEED * (float(_host_tick() - _base_tick) - settled) * SIM_DELTA
	assert_le(absf(drawn_x - host_x), SPEED * RECOVERED_TICKS * SIM_DELTA, "and the body is drawn where that time puts it")
