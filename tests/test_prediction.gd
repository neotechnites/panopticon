extends TestCase

## A client predicting its own body, against a host, over a wire with 80 ms of
## latency each way and jitter on top.
##
## [b]Why the packets are moved by hand.[/b] Loopback has no latency to speak
## of, and prediction is only interesting when the authority's answer is old.
## So the two [NetSession] scenes are real and really connected -- the client is
## a client because a host told it so -- but the per-tick traffic for the seat
## under test is carried by the delay lines below: the client's intent reaches
## the host [constant LATENCY_TICKS] ticks late, the host's snapshot reaches the
## client the same again, and both are sent through [NetCodec] on the way so the
## wire format is exercised rather than stepped around.
##
## The host's link is owned by a peer id nobody has, which is what stops the
## client's own RPCs arriving instantly alongside the delayed copies; the host's
## replicator has no registered bodies, so it sends no snapshots of its own.

## One packet in flight: an intent going up, or a packed snapshot coming down.
class Wire extends RefCounted:
	var due: int = 0
	var tick: int = 0
	var intent: MoveIntent = MoveIntent.new()
	var payload: PackedByteArray = PackedByteArray()


## One way, in ticks. 5 at 60 Hz is 83 ms, so a round trip is about 170 ms plus
## the snapshot interval -- a bad domestic connection, not a pathological one.
const LATENCY_TICKS: int = 5

## Ticks of jitter added on top, per packet, when a test asks for it. Enough to
## reorder an intent, which is what an unreliable channel does and what the
## receive path has to survive.
##
## Jitter costs accuracy and there is no prediction bug in that. The authority
## simulates one tick whatever arrives, so a tick that brings two intents leaves
## one unsimulated and a tick that brings none repeats the last -- either way
## the authority's answer for a given input tick is one tick of travel away from
## the client's, and the client is put right by that much. Closing that needs
## the client to pace its sending against the authority's clock, which is a
## different feature and is not here.
const JITTER_TICKS: int = 2


## Ticks between snapshots: 30 Hz on the 60 Hz simulation, as shipped.
const SNAPSHOT_EVERY: int = 2

## Ticks run before anything is measured, so the first snapshot -- which
## acknowledges no input and can only snap -- is not counted as an error.
const WARMUP_TICKS: int = 60

## How far out a prediction may be in steady running, in metres.
const ALLOWED_ERROR: float = 0.05

const START: Vector3 = Vector3(0.0, 0.1, 0.0)

var _host: NetSession
var _client: NetSession
var _host_link: PlayerNetLink
var _client_link: PlayerNetLink
var _profile: MovementProfile

var _tick: int = 0
var _running: bool = false
var _up: Array[Wire] = []
var _down: Array[Wire] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Yaw asked for per tick, in radians. Refilled every tick, because a source
## consumes a look delta the way the real ones do.
var _turn: float = 0.0

## Ticks of jitter this test wants. Zero is a wire that is merely slow.
var _jitter: int = 0
var _outgoing: WorldSnapshot = WorldSnapshot.new()
var _incoming: WorldSnapshot = WorldSnapshot.new()
var _last_delivered_tick: int = -1

## Every correction the client has been handed since [method _measure] was last
## called, in metres, and how many of them were snaps.
var _corrections: PackedFloat32Array = PackedFloat32Array()
var _snaps: int = 0


func before_each() -> void:
	_rng.seed = 20260914
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

## Connect, build one body on each machine and start pumping the delay lines.
## Returns false when the handshake did not complete, so a test can fail loudly
## rather than assert into a session that does not exist.
func _stand_up() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	var client_id: int = _client.get_local_peer_id()

	# An owner the client is not, so the client's own RPCs are refused by the
	# sender check and the only intent the host sees is the delayed one.
	_host_link = NetFixtures.add_seat_body(_host, 0, client_id + 1, _profile, false)
	_client_link = NetFixtures.add_seat_body(_client, 0, client_id, _profile, true)
	# No registered body, no snapshot: the host's own replicator stays quiet and
	# this test owns the downward traffic.
	_host.replicator.unregister(_host_link)

	for link: PlayerNetLink in [_host_link, _client_link]:
		# Off each other's layers and onto the floor's, so the two bodies stand
		# on the same ground in this one physics world without touching.
		link.controller.collision_layer = 0
		link.controller.collision_mask = 1
		link.controller.global_position = START
	_client_link.prediction_corrected.connect(_on_corrected)

	await step_ticks(1)
	_running = true
	await step_ticks(WARMUP_TICKS)
	# The first snapshot acknowledges no input and can only snap, and the body
	# spends a round trip afterwards getting back in step. None of that is what
	# these tests measure, so it is read off and thrown away here.
	var _warmup: Array = _measure()
	return true


func _on_corrected(metres: float, snapped: bool) -> void:
	_corrections.append(metres)
	if snapped:
		_snaps += 1


## The worst correction since this was last called, and how many snaps. Clears
## what it read.
func _measure() -> Array:
	var worst: float = 0.0
	for metres: float in _corrections:
		worst = maxf(worst, metres)
	var counted: int = _corrections.size()
	var snapped: int = _snaps
	_corrections.clear()
	_snaps = 0
	return [worst, snapped, counted]


## Carry this tick's packets. Runs before every body in the tree, so an intent
## delivered here is one the host simulates on this tick and a snapshot
## delivered here is one the client reconciles against at the end of it.
func _physics_process(_delta: float) -> void:
	if not _running:
		return
	_tick += 1
	if _turn != 0.0:
		(_client_link.local_source as BotIntentSource).command.look_delta.x = _turn
	_deliver_up()
	_deliver_down()
	_send_up()
	if _tick % SNAPSHOT_EVERY == 0:
		_send_down()


func _due() -> int:
	return _tick + LATENCY_TICKS + (_rng.randi_range(0, _jitter) if _jitter > 0 else 0)


## The intent the client's body ran on its last tick, sent late.
func _send_up() -> void:
	var packet: Wire = Wire.new()
	packet.due = _due()
	packet.tick = _client_link.get_intent_tick()
	packet.intent.copy_from(_client_link.controller.get_intent())
	_up.append(packet)


func _deliver_up() -> void:
	var source: RemoteIntentSource = _host_link.get_remote_source()
	var held: Array[Wire] = []
	for packet: Wire in _up:
		if packet.due > _tick:
			held.append(packet)
			continue
		# Refused when jitter has already delivered a newer one, exactly as the
		# authority refuses a reordered packet off the socket.
		source.accept(packet.tick, packet.intent)
	_up = held


## The host's body as it stood at the end of its last tick, packed and sent late.
func _send_down() -> void:
	_outgoing.clear()
	_host_link.sample_state(_outgoing.next_slot())
	_outgoing.tick = _tick
	_outgoing.states[0].tick = _tick
	_outgoing.commit()
	var packet: Wire = Wire.new()
	packet.due = _due()
	packet.tick = _tick
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
		if _last_delivered_tick >= 0 and not NetCodec.is_newer_tick(_incoming.tick, _last_delivered_tick):
			continue
		_last_delivered_tick = _incoming.tick
		_client.replicator.apply_snapshot(_incoming)
	_down = held


## Drive both bodies with the same request. The client's body takes it as input;
## the host's body gets it a round trip later, off the wire.
func _both_run(direction: Vector2) -> void:
	var source: BotIntentSource = _client_link.local_source as BotIntentSource
	source.command.move_direction = direction


# --- Tests --------------------------------------------------------------------

func test_the_snapshot_carries_the_intent_the_authority_has_applied() -> void:
	var state: PlayerState = PlayerState.new()
	state.seat_index = 3
	state.last_intent_tick = 77
	var snapshot: WorldSnapshot = WorldSnapshot.new()
	snapshot.append(state)
	var packed: PackedByteArray = NetCodec.pack_snapshot(snapshot)
	assert_eq_int(
		packed.size(),
		NetCodec.SNAPSHOT_HEADER_SIZE + NetCodec.SNAPSHOT_BODY_SIZE,
		"the acknowledged tick is part of a body's fixed size",
	)

	var decoded: WorldSnapshot = WorldSnapshot.new()
	assert_true(NetCodec.unpack_snapshot(packed, decoded), "it decodes")
	assert_eq_int(decoded.states[0].last_intent_tick, 77, "and the acknowledgement survived")

	state.last_intent_tick = -1
	snapshot.clear()
	snapshot.append(state)
	assert_true(
		NetCodec.unpack_snapshot(NetCodec.pack_snapshot(snapshot), decoded),
		"a body the authority has run no input for decodes too",
	)
	assert_eq_int(
		decoded.states[0].last_intent_tick, -1, "and says so rather than claiming tick 0"
	)

	# The size is the version. A body from a build with one field fewer must be
	# refused whole, not read as a shorter body plus rubbish.
	var short: PackedByteArray = packed.duplicate()
	short.resize(short.size() - 4)
	assert_false(NetCodec.unpack_snapshot(short, decoded), "a body of the old size is refused")


func test_a_client_running_flat_out_predicts_within_five_centimetres() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return

	assert_true(
		_client_link.is_predicting(), "the client simulates its own body rather than mirroring it"
	)
	assert_true(
		_client_link.controller.is_physics_processing(), "which means its physics is running"
	)

	var from: Vector3 = _client_link.controller.global_position
	_both_run(Vector2(0.0, 1.0))
	await step_ticks(120)
	var measured: Array = _measure()

	assert_gt(
		from.distance_to(_client_link.controller.global_position),
		5.0,
		"the client's own body actually went somewhere",
	)
	assert_gt(float(int(measured[2])), 10.0, "and was corrected against a good few snapshots")
	assert_lt(
		float(measured[0]),
		ALLOWED_ERROR,
		"the worst the prediction was ever out by, in metres, at 170 ms round trip",
	)
	assert_eq_int(int(measured[1]), 0, "and nothing had to be snapped")

	# Turning, which is the half of prediction that replays: every rewind turns
	# by every unacknowledged look delta again, so a body that ends up facing
	# somewhere else than the authority has it facing is one that has been
	# turned twice per correction.
	_turn = 0.01
	await step_ticks(60)
	assert_gt(absf(_host_link.controller.rotation.y), 0.4, "the host turned the body a good way")
	# The client leads by exactly the turning the authority has not answered for
	# yet -- a round trip of it, no more. Turning twice per correction would
	# show up here as a lead several times this bound and growing.
	var lead: float = absf(_client_link.controller.rotation.y - _host_link.controller.rotation.y)
	assert_le(
		lead,
		float(LATENCY_TICKS + SNAPSHOT_EVERY + 2) * _turn,
		"the client leads the authority's facing by the flight time and nothing more",
	)
	_turn = 0.0
	var _turned: Array = _measure()

	# And again with the wire jittering, which costs a tick of travel per
	# disordered arrival and must cost nothing else. See JITTER_TICKS.
	_jitter = JITTER_TICKS
	await step_ticks(120)
	var jittered: Array = _measure()
	# The bound is derived rather than written down: a packet that arrives up to
	# JITTER_TICKS ticks out of step costs that many ticks of travel and must
	# cost nothing else, whatever the movement profile is tuned to.
	var per_tick: float = _client_link.controller.get_horizontal_speed() * SIM_DELTA
	assert_lt(
		float(jittered[0]),
		per_tick * float(JITTER_TICKS + 1),
		"jitter costs ticks of travel (%.3f m each), not metres" % per_tick,
	)
	assert_eq_int(int(jittered[1]), 0, "and still nothing had to be snapped")

	# The numbers this file exists to produce, on the record for whoever tunes
	# this next.
	print("          worst correction: %.4f m steady, %.4f m jittered, over %d and %d snapshots" % [
		float(measured[0]), float(jittered[0]), int(measured[2]), int(jittered[2]),
	])


func test_a_launch_on_the_host_arrives_once_and_does_not_oscillate() -> void:
	_jitter = JITTER_TICKS
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	_both_run(Vector2(0.0, 1.0))
	await step_ticks(60)
	var _settled: Array = _measure()

	# The boost pad's own call, made where boost pads are made: on the host.
	_host_link.controller.launch(Vector3(0.0, 12.0, -14.0))
	await step_ticks(30)
	var arrival: Array = _measure()
	assert_le(
		float(int(arrival[1])), 1.0, "a launch the client could not know about snaps at most once"
	)
	assert_gt(
		_client_link.controller.global_position.y,
		START.y + 0.5,
		"and the client is off the ground with the host",
	)

	# A snap drops the buffer, and the round trip it takes to fill again is not
	# what this is measuring.
	await step_ticks(30)
	var _recovery: Array = _measure()

	# The launch is over; what is left is ordinary running, and a correction
	# that fought itself would show up here as the errors failing to settle.
	await step_ticks(60)
	var after: Array = _measure()
	assert_lt(
		float(after[0]),
		_client.get_settings().prediction_snap_metres * 0.75,
		"the client settled back onto the host's path",
	)
	assert_eq_int(int(after[1]), 0, "with nothing left to snap")


func test_a_host_side_kill_snaps_the_client_instead_of_sliding_it() -> void:
	_jitter = JITTER_TICKS
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	_both_run(Vector2(0.0, 1.0))
	await step_ticks(60)
	var _settled: Array = _measure()

	# What a kill does to a body: the match takes it somewhere else and stops
	# it. Nothing about that is predictable from the client's own input.
	var grave: Vector3 = Vector3(0.0, START.y, -60.0)
	_host_link.controller.global_position = grave
	_host_link.controller.velocity = Vector3.ZERO

	# One snapshot interval, one latency, one jitter, and a tick to act on it.
	var flight: int = SNAPSHOT_EVERY + LATENCY_TICKS + _jitter + 2
	await step_ticks(flight)
	var landed: Array = _measure()
	assert_gt(float(int(landed[1])), 0.0, "the correction was taken as a snap, not a drift")
	# Where the host put it, PLUS the running the client has done since. A snap
	# REPLAYS the unacknowledged input rather than deleting it -- see
	# PlayerNetLink -- so the body lands at the grave carrying a round trip of
	# the player's own running, and then keeps running for what is left of the
	# wait. The bound is those two stretches and not zero. What it is not is the
	# sixty metres the body would still be short of if the snap had not landed.
	var carried: int = flight + LATENCY_TICKS + SNAPSHOT_EVERY + _jitter
	var travelled: float = _client_link.controller.get_horizontal_speed() * SIM_DELTA * float(carried)
	assert_lt(
		_client_link.controller.global_position.distance_to(grave),
		maxf(travelled, 1.0),
		"and the client's body is where the host put it, carried on by what it has run since",
	)
	assert_lt(
		_client_link.controller.view_offset.length(),
		_client.get_settings().prediction_snap_metres * 0.1,
		"with the view taken with the body rather than left behind smoothing a snap away",
	)
