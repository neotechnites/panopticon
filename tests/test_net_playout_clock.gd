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
## The host's own time, which stops while it stalls; the most a snapshot is held up on the line.
var _host_seconds: float = 0.0
var _host_stalled: bool = false
var _jitter_max_seconds: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Snapshots on the line: [arrival seconds, tick].
var _line: Array[Array] = []


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


## The host's present tick: it ran every tick of its own time.
func _host_tick() -> int:
	return _base_tick + floori(_host_seconds / SIM_DELTA)


## One client frame of [param seconds], in Godot's order: capped physics steps, poll, idle; the idle
## frame may itself stall for [param stall_after_poll] seconds before drawing.
func _frame(seconds: float, stall_after_poll: float = 0.0) -> void:
	_real_seconds += seconds
	if not _host_stalled:
		_host_seconds += seconds
	_owed_seconds += seconds
	var steps: int = mini(floori(_owed_seconds / SIM_DELTA), Engine.max_physics_steps_per_frame)
	# Godot drops what the cap did not run.
	_owed_seconds = minf(_owed_seconds - float(steps) * SIM_DELTA, SIM_DELTA)
	for _i: int in steps:
		_client.replicator._physics_process(SIM_DELTA)
	var newest: int = _host_tick() - _host_tick() % SNAPSHOT_EVERY
	var tick: int = _sent_tick + SNAPSHOT_EVERY if _sent_tick >= 0 else newest
	while tick <= newest:
		_line.append([_real_seconds + _rng.randf() * _jitter_max_seconds, tick])
		_sent_tick = tick
		tick += SNAPSHOT_EVERY
	_line.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	while not _line.is_empty() and float(_line[0][0]) <= _real_seconds:
		var packet: Array = _line.pop_front()
		var taken: bool = _client.replicator.receive_snapshot(_snapshot(int(packet[1])))
		# Overtaken on a jittery line, an older snapshot is refused; on a clean one every one is taken.
		assert_true(taken or _jitter_max_seconds > 0.0, "the snapshot for tick %d is taken" % int(packet[1]))
	var polled: float = _real_seconds * SIM_HZ
	_real_seconds += stall_after_poll
	_host_seconds += stall_after_poll
	_owed_seconds += stall_after_poll
	_client.replicator.play_back(_real_seconds * SIM_HZ, polled)


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
	await _ride_out_a_long_frame(false)


## The stall after the poll: the frame draws before it has looked for what came in meanwhile.
func test_a_stall_between_the_poll_and_the_draw_is_not_taken_for_a_starved_line() -> void:
	await _ride_out_a_long_frame(true)


func _ride_out_a_long_frame(after_poll: bool) -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	var settled: float = 0.0
	for i: int in SETTLE_FRAMES:
		_frame(SIM_DELTA)
		if i >= SETTLE_FRAMES - 60:
			settled += _behind() / 60.0
	var depth: float = _client.replicator.get_delay_ticks()
	if after_poll:
		_frame(SIM_DELTA, HITCH_SECONDS)
	else:
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


func test_a_client_draws_behind_its_newest_snapshot_from_the_first() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	var nearest: float = INF
	for i: int in 60:
		_frame(SIM_DELTA)
		nearest = minf(nearest, float(_client.replicator.get_latest_tick()) - _client.replicator.get_view_time())
	assert_ge(nearest, 0.0, "a buffer still filling never draws past the newest snapshot it holds")
	assert_between(_behind(), 2.0, 4.0, "and the clock kept its delay while it filled")


## A jittery line deepens the buffer; the host then stalls, so the clock waits at the edge of what it holds.
## When the host comes back the clock is far ahead of its target, and must slow, never step back.
func test_the_drawn_tick_never_steps_back_after_a_starve() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	_rng.seed = 7940
	_jitter_max_seconds = 0.25
	var last: float = -INF
	var rewound: float = 0.0
	for i: int in 1200:
		_host_stalled = i % 400 >= 340
		_frame(SIM_DELTA)
		var view: float = _client.replicator.get_view_time()
		rewound = maxf(rewound, last - view)
		last = maxf(last, view)
	print("          worst step back of the drawn tick: %.2f ticks" % rewound)
	assert_le(rewound, 0.0, "the drawn tick never goes backwards")


func test_a_hit_stop_slows_remote_bodies_with_the_world_then_catches_up() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	for i: int in SETTLE_FRAMES:
		_frame(SIM_DELTA)
	var before: float = _behind()
	var base: float = Engine.time_scale
	var was_physics: bool = NetReplicator.ticks_from_physics
	# Wall-clock mode, as shipped: the runner otherwise has physics carry the slow-down.
	NetReplicator.ticks_from_physics = false
	Engine.time_scale = 0.12
	for i: int in 6:
		_frame(SIM_DELTA)
	var during: float = _behind()
	Engine.time_scale = base
	for i: int in 60:
		_frame(SIM_DELTA)
	NetReplicator.ticks_from_physics = was_physics
	print("          hit stop: %.1f ticks behind before, %.1f at its end, %.1f a second later" % [before, during, _behind()])
	assert_gt(during - before, 4.0, "the remote world slows with the local one")
	assert_le(absf(_behind() - before), 0.5, "and is back on time a second later")

