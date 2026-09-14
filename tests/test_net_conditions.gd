extends TestCase

## What the netcode does on a line that is not a LAN: 150 ms round trip, jitter,
## 5% loss, and a host that hitches for half a second.
##
## [b]Why the packets are moved by hand.[/b] Loopback has no latency and drops
## nothing, so the only way to find out what a bad line costs is to carry the
## real bytes over a wire this file owns. Both sessions are real and really
## connected -- a client is a client because a host told it so -- and everything
## crossing the wire below goes through [NetCodec] and through the same
## [method PlayerNetLink.accept_intent_payload] the RPC lands in, so the format
## and the authority's guards are exercised rather than stepped around.
##
## The host's seat 0 is owned by a peer id nobody has, which is what stops the
## client's own RPCs arriving instantly beside the delayed copies.
##
## Two bodies, because the two playback paths are different code. Seat 0 is the
## client's own and is PREDICTED. Seat 1 is a bot on the host and is MIRRORED
## through the jitter buffer, which is the path a pop shows up in.

## One packet in flight, up or down.
class Wire extends RefCounted:
	var due: int = 0
	var payload: PackedByteArray = PackedByteArray()


## One way, in ticks. 5 at 60 Hz is 83 ms, so a round trip is 167 ms plus the
## snapshot interval -- the brief's 150 ms, rounded to the tick.
const LATENCY_TICKS: int = 5

## Ticks of jitter added per packet when a test asks for it.
const JITTER_TICKS: int = 2

## Fraction of packets dropped when a test asks for loss.
const LOSS: float = 0.05

## Ticks between snapshots: 30 Hz on the 60 Hz simulation, as shipped.
const SNAPSHOT_EVERY: int = 2

## Ticks run before anything is measured.
const WARMUP_TICKS: int = 90

## Ticks each measurement window runs for.
const WINDOW_TICKS: int = 300

const START_OWN: Vector3 = Vector3(0.0, 0.1, 0.0)
const START_MIRROR: Vector3 = Vector3(6.0, 0.1, 0.0)

var _host: NetSession
var _client: NetSession
var _host_own: PlayerNetLink
var _host_mirror: PlayerNetLink
var _client_own: PlayerNetLink
var _client_mirror: PlayerNetLink
var _profile: MovementProfile

var _tick: int = 0
var _running: bool = false
var _up: Array[Wire] = []
var _down: Array[Wire] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _jitter: int = 0
var _loss: float = 0.0
## True while the host is pretending to hitch: it simulates but sends nothing.
var _host_stalled: bool = false

var _outgoing: WorldSnapshot = WorldSnapshot.new()
var _incoming: WorldSnapshot = WorldSnapshot.new()
var _last_down_tick: int = -1

## Corrections handed to the predicted body since the last [method _measure].
var _corrections: PackedFloat32Array = PackedFloat32Array()
var _snaps: int = 0

## Intent ticks the authority has actually SIMULATED, and how many were sent.
var _applied_ticks: int = 0
var _last_applied: int = -1
var _sent_packets: int = 0

## Per-tick travel of the mirrored body on the client, for pops and freezes.
var _steps: PackedFloat32Array = PackedFloat32Array()
var _last_mirror_position: Vector3 = Vector3.ZERO
var _have_mirror_position: bool = false


func before_each() -> void:
	_rng.seed = 20260914
	# After the links (50) and the replicator (100), so a packet captured here
	# is the one this tick actually produced.
	process_physics_priority = 200
	_profile = TestFixtures.movement_profile()
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	add_child(TestFixtures.make_floor(0.0))


func after_each() -> void:
	_running = false
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


# --- The wire -----------------------------------------------------------------

func _stand_up() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	var client_id: int = _client.get_local_peer_id()
	# An owner the client is not, so its real RPCs are refused by the sender
	# check and the only intent the host sees is the one carried below.
	var stand_in: int = client_id + 1

	_host_own = NetFixtures.add_seat_body(_host, 0, stand_in, _profile, false)
	_host_mirror = NetFixtures.add_seat_body(_host, 1, 0, _profile, true)
	_client_own = NetFixtures.add_seat_body(_client, 0, client_id, _profile, true)
	_client_mirror = NetFixtures.add_seat_body(_client, 1, 0, _profile, false)
	# No registered body, no snapshot: the host's own replicator stays quiet and
	# this file owns the downward traffic.
	_host.replicator.unregister(_host_own)
	_host.replicator.unregister(_host_mirror)

	for link: PlayerNetLink in [_host_own, _host_mirror, _client_own, _client_mirror]:
		link.controller.collision_layer = 0
		link.controller.collision_mask = 1
	_host_own.controller.global_position = START_OWN
	_client_own.controller.global_position = START_OWN
	_host_mirror.controller.global_position = START_MIRROR
	_client_mirror.controller.global_position = START_MIRROR
	_client_own.prediction_corrected.connect(_on_corrected)

	await step_ticks(1)
	_running = true
	_run(Vector2(0.0, 1.0))
	await step_ticks(WARMUP_TICKS)
	var _warmup: Array = _measure()
	return true


## Drive both of this machine's own bodies with the same request.
func _run(direction: Vector2) -> void:
	for link: PlayerNetLink in [_client_own, _host_mirror]:
		var source: BotIntentSource = link.local_source as BotIntentSource
		if source != null:
			source.command.move_direction = direction


func _on_corrected(metres: float, snapped: bool) -> void:
	_corrections.append(metres)
	if snapped:
		_snaps += 1


## Everything measured since this was last called, and a clean slate.
##
## [worst correction, snaps, corrections, applied intent ticks, packets sent,
## worst mirrored step, frozen mirrored ticks, mirrored step deviation].
func _measure() -> Array:
	var worst: float = 0.0
	for metres: float in _corrections:
		worst = maxf(worst, metres)
	var worst_step: float = 0.0
	var total_step: float = 0.0
	var frozen: int = 0
	for step: float in _steps:
		worst_step = maxf(worst_step, step)
		total_step += step
		if step < 0.0005:
			frozen += 1
	# How UNEVEN the body's travel was, which is what a pop actually is: a mean
	# tells you it got there, and the spread tells you whether it was watchable.
	var mean_step: float = total_step / float(maxi(_steps.size(), 1))
	var variance: float = 0.0
	for step: float in _steps:
		variance += (step - mean_step) * (step - mean_step)
	var deviation: float = sqrt(variance / float(maxi(_steps.size(), 1)))
	var result: Array = [
		worst, _snaps, _corrections.size(), _applied_ticks, _sent_packets, worst_step, frozen,
		deviation,
	]
	_corrections.clear()
	_steps.clear()
	_snaps = 0
	_applied_ticks = 0
	_sent_packets = 0
	return result


func _physics_process(_delta: float) -> void:
	if not _running:
		return
	_tick += 1
	_deliver_up()
	_deliver_down()
	_send_up()
	if _tick % SNAPSHOT_EVERY == 0 and not _host_stalled:
		_send_down()
	# One drawn frame per tick: the runner's idle frames are far rarer than its
	# compressed physics ticks, so playback is driven here instead of being left
	# to _process, which would sample the clock a hundred ticks at a time.
	_client.replicator.play_back(SIM_DELTA)
	_note_mirror_step()
	_note_applied_intent()


func _due() -> int:
	return _tick + LATENCY_TICKS + (_rng.randi_range(0, _jitter) if _jitter > 0 else 0)


func _dropped() -> bool:
	return _loss > 0.0 and _rng.randf() < _loss


## The real packet the client's link built this tick.
func _send_up() -> void:
	var payload: PackedByteArray = _client_own.get_last_intent_packet()
	if payload.is_empty():
		return
	_sent_packets += 1
	if _dropped():
		return
	var packet: Wire = Wire.new()
	packet.due = _due()
	packet.payload = payload.duplicate()
	_up.append(packet)


func _deliver_up() -> void:
	var held: Array[Wire] = []
	for packet: Wire in _up:
		if packet.due > _tick:
			held.append(packet)
			continue
		_host_own.accept_intent_payload(_host_own.owner_peer_id, packet.payload)
	_up = held


func _send_down() -> void:
	_outgoing.clear()
	for link: PlayerNetLink in [_host_own, _host_mirror]:
		var slot: PlayerState = _outgoing.next_slot()
		link.sample_state(slot)
		slot.tick = _tick
		_outgoing.commit()
	_outgoing.tick = _tick
	if _dropped():
		return
	var packet: Wire = Wire.new()
	packet.due = _due()
	packet.payload = NetCodec.pack_snapshot(_outgoing)
	_down.append(packet)


func _deliver_down() -> void:
	var held: Array[Wire] = []
	for packet: Wire in _down:
		if packet.due > _tick:
			held.append(packet)
			continue
		if not NetCodec.unpack_snapshot(packet.payload, _incoming):
			continue
		if _last_down_tick >= 0 and not NetCodec.is_newer_tick(_incoming.tick, _last_down_tick):
			continue
		_last_down_tick = _incoming.tick
		_client.replicator.apply_snapshot(_incoming)
	_down = held


## How far the mirrored body moved on this drawn frame.
func _note_mirror_step() -> void:
	var here: Vector3 = _client_mirror.controller.global_position
	if _have_mirror_position:
		_steps.append(_last_mirror_position.distance_to(here))
	_last_mirror_position = here
	_have_mirror_position = true


## Count the intent ticks the authority has actually simulated. A tick that
## brings no packet repeats the last command and does not advance this, which is
## exactly the input the player made and the game did not act on.
func _note_applied_intent() -> void:
	var source: RemoteIntentSource = _host_own.get_remote_source()
	if source == null or source.applied_tick == _last_applied:
		return
	_last_applied = source.applied_tick
	_applied_ticks += 1


# --- Tests --------------------------------------------------------------------

func test_repeating_the_last_intent_buys_back_a_lossy_line() -> void:
	_jitter = JITTER_TICKS
	_loss = LOSS
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return

	# One intent a packet: the shipped behaviour before this, and what every
	# dropped packet costs.
	_client.get_settings().intent_redundancy = 1
	await step_ticks(WINDOW_TICKS)
	var alone: Array = _measure()

	_client.get_settings().intent_redundancy = 2
	await step_ticks(WINDOW_TICKS)
	var repeated: Array = _measure()

	var alone_rate: float = float(int(alone[3])) / float(maxi(int(alone[4]), 1))
	var repeated_rate: float = float(int(repeated[3])) / float(maxi(int(repeated[4]), 1))
	print("          INTENT at %.0f%% loss: %.1f%% simulated alone, %.1f%% repeated" % [
		_loss * 100.0, alone_rate * 100.0, repeated_rate * 100.0,
	])

	assert_lt(alone_rate, 0.95, "one intent a packet loses what the line loses, and then some")
	assert_gt(
		repeated_rate,
		1.0 - _loss,
		"repeating the previous tick puts MORE input into the simulation than the wire delivered packets, which only a repeat can do",
	)
	assert_gt(
		repeated_rate - alone_rate,
		0.1,
		"and it is worth a tenth of the player's input on this line",
	)


func test_prediction_holds_at_a_hundred_and_fifty_millisecond_round_trip_with_loss() -> void:
	_jitter = JITTER_TICKS
	_loss = LOSS
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return

	await step_ticks(WINDOW_TICKS)
	var measured: Array = _measure()
	var per_tick: float = _client_own.controller.get_horizontal_speed() * SIM_DELTA
	print("          PREDICTION at %d ms RTT, %.0f%% loss: worst %.4f m over %d corrections, %d snaps (a tick of travel is %.4f m)" % [
		int(float(LATENCY_TICKS * 2) * SIM_DELTA * 1000.0),
		_loss * 100.0, float(measured[0]), int(measured[2]), int(measured[1]), per_tick,
	])

	assert_gt(float(int(measured[2])), 20.0, "there were corrections to measure")
	# The bound is derived rather than written down: jitter and a dropped
	# snapshot cost ticks of travel, and the fix is that they cost no more than
	# that. See test_prediction for the same bound on a clean wire.
	assert_lt(
		float(measured[0]),
		per_tick * float(JITTER_TICKS + SNAPSHOT_EVERY + 3),
		"a bad line costs ticks of travel, not metres",
	)
	assert_eq_int(int(measured[1]), 0, "and nothing had to be snapped")


func test_the_jitter_buffer_takes_the_pop_out_of_a_mirrored_body() -> void:
	_jitter = JITTER_TICKS
	_loss = LOSS
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return

	# The buffer at its floor and no extrapolation: one snapshot interval of
	# delay, restarted on every arrival, which is what this replicator did
	# before it had a clock.
	var settings: NetSettings = _client.get_settings()
	settings.max_interpolation_jitter_ticks = 0
	settings.max_extrapolation_seconds = 0.0
	await step_ticks(WINDOW_TICKS)
	var fixed: Array = _measure()

	settings.max_interpolation_jitter_ticks = 8
	settings.max_extrapolation_seconds = 0.15
	# The buffer adapts to what it measures, so it is given a window to settle
	# before the window that is read.
	await step_ticks(WINDOW_TICKS)
	var _settling: Array = _measure()
	await step_ticks(WINDOW_TICKS)
	var adaptive: Array = _measure()

	var expected_step: float = _host_mirror.controller.get_horizontal_speed() * SIM_DELTA
	print("          MIRROR at %d ms RTT, %.0f%% loss, %d ticks jitter (a tick of travel is %.4f m):" % [
		int(float(LATENCY_TICKS * 2) * SIM_DELTA * 1000.0), _loss * 100.0, JITTER_TICKS,
		expected_step,
	])
	print("            fixed    worst step %.4f m, spread %.4f m, %d frozen frames" % [
		float(fixed[5]), float(fixed[7]), int(fixed[6]),
	])
	print("            adaptive worst step %.4f m, spread %.4f m, %d frozen frames" % [
		float(adaptive[5]), float(adaptive[7]), int(adaptive[6]),
	])
	print("          buffer settled at %.2f ticks of delay on %.1f ms of measured jitter" % [
		_client.replicator.get_delay_ticks(), _client.replicator.get_jitter_seconds() * 1000.0,
	])

	# The spread, not the worst frame. A pop is unevenness: the body covering
	# two ticks of ground in one frame and none in the next. The worst single
	# frame is bounded by the snapshot interval either way and says little.
	assert_lt(
		float(adaptive[7]),
		float(fixed[7]),
		"the clock draws the body at a steadier speed than a slide restarted per packet",
	)
	assert_le(
		float(int(adaptive[6])),
		float(int(fixed[6])),
		"and freezes the body on no more frames",
	)
	# The bound that matters on its own: a frame may not move a body further
	# than a few ticks of its own running. Above that it is a teleport.
	assert_lt(
		float(adaptive[5]),
		expected_step * 6.0,
		"no frame moves the mirrored body further than a few ticks of travel",
	)


func test_a_five_hundred_millisecond_host_hitch_is_ridden_out() -> void:
	_jitter = JITTER_TICKS
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	var _settled: Array = _measure()

	# The host simulates through the hitch and sends nothing: a frame that took
	# half a second, a garbage collection, a scene loading.
	_host_stalled = true
	await step_ticks(30)
	var during: Array = _measure()
	_host_stalled = false
	await step_ticks(60)
	var after: Array = _measure()

	var expected_step: float = _host_mirror.controller.get_horizontal_speed() * SIM_DELTA
	print("          HITCH 500 ms: worst mirrored step %.4f m during, %.4f m after; %d snaps during, %d after" % [
		float(during[5]), float(after[5]), int(during[1]), int(after[1]),
	])

	assert_lt(
		float(during[5]),
		expected_step * 3.0,
		"the mirrored body sails on rather than jumping while nothing arrives",
	)
	assert_lt(
		float(after[5]),
		expected_step * 8.0,
		"and is put right without teleporting when the host comes back",
	)
	assert_le(
		float(int(after[1])), 1.0, "the predicted body takes at most one snap on the way back"
	)
	assert_true(
		_client_own.is_predicting(),
		"and the client is still predicting its own body afterwards",
	)
