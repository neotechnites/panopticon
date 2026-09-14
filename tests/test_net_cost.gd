extends TestCase

## What replication actually costs: bytes on a real socket, and microseconds on
## the host and on a client.
##
## Two sessions, two UDP sockets, eight seats, one of them owned by the client.
## Bytes are read out of ENet's own counters rather than computed from the
## codec, so RPC headers, channel bookkeeping and ENet's own framing are all in
## the number. Rates are derived from the tick the traffic is paced against --
## not from the wall clock, because the runner compresses simulated time and a
## socket has not heard about it.
##
## The assertions are budgets, deliberately loose. The numbers are the point and
## they are printed.

const SEATS: int = 8

## Ticks the measurement window runs for. 240 at 60 Hz is 4 simulated seconds,
## which is 120 snapshots -- enough that one packet either way does not move the
## average.
const MEASURE_TICKS: int = 240

## Ticks run before the counters are read, so the handshake, the first roster
## and the first snapshot are not in the window.
const SETTLE_TICKS: int = 40

## Iterations each microbenchmark runs. Large enough that the clock's resolution
## is not the measurement.
const BENCH_ITERATIONS: int = 500

## Upper bound on one snapshot's wire cost to one peer, in bytes. A packet over
## this is a packet that could fragment on a path with a small MTU; the real
## number is a quarter of it and the headroom is deliberate.
const SNAPSHOT_WIRE_BUDGET: int = 1200

var _host: NetSession
var _client: NetSession
var _host_links: Array[PlayerNetLink] = []
var _client_links: Array[PlayerNetLink] = []
var _profile: MovementProfile
var _snapshots: int = 0


func before_each() -> void:
	_profile = TestFixtures.movement_profile()
	_host = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_client = NetFixtures.make_peer(self, "Client", NetFixtures.settings())
	add_child(TestFixtures.make_floor(0.0))


func after_each() -> void:
	_host_links.clear()
	_client_links.clear()
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()


## Connect, put eight bodies on each machine and get them running.
func _stand_up() -> bool:
	var port: int = await NetFixtures.host_and_wait(self, _host)
	if port < 0:
		return false
	if not await NetFixtures.join_and_wait(self, _client, _host, port):
		return false
	var client_id: int = _client.get_local_peer_id()

	for seat: int in SEATS:
		# Seat 0 is the client's; the rest are bots, which is what the wire
		# cannot tell apart and the whole design rests on.
		var owner: int = client_id if seat == 0 else 0
		_host_links.append(NetFixtures.add_seat_body(_host, seat, owner, _profile, seat != 0))
		_client_links.append(NetFixtures.add_seat_body(_client, seat, owner, _profile, seat == 0))
	for links: Array in [_host_links, _client_links]:
		for i: int in links.size():
			var link: PlayerNetLink = links[i]
			link.controller.collision_layer = 0
			link.controller.collision_mask = 1
			# Spread out, so eight bodies are not one body eight times over --
			# a snapshot of identical rows is not a snapshot this game sends.
			link.controller.global_position = Vector3(float(i) * 3.0 - 10.0, 0.1, 0.0)

	_host.replicator.snapshot_sent.connect(func(_t: int, _c: int) -> void: _snapshots += 1)
	await step_ticks(2)
	_drive_everyone()
	await step_ticks(SETTLE_TICKS)
	return true


## Keep every body moving and turning, so no field of a snapshot is constant.
func _drive_everyone() -> void:
	for links: Array in [_host_links, _client_links]:
		for i: int in links.size():
			var link: PlayerNetLink = links[i]
			var source: BotIntentSource = link.local_source as BotIntentSource
			if source == null:
				continue
			var angle: float = float(i) * 0.7
			source.command.move_direction = Vector2(sin(angle), cos(angle))
			source.command.look_delta.x = 0.004


# --- Bandwidth ----------------------------------------------------------------

## Run a window and print what it cost. Returns the bytes one snapshot took on
## the wire, ENet's own framing included.
func _measure_window(label: String) -> float:
	var _reset_host: Dictionary = _host.transport.take_wire_stats()
	var _reset_client: Dictionary = _client.transport.take_wire_stats()
	_snapshots = 0
	await step_ticks(MEASURE_TICKS)
	var host_stats: Dictionary = _host.transport.take_wire_stats()
	var client_stats: Dictionary = _client.transport.take_wire_stats()

	assert_false(host_stats.is_empty(), "the ENet backend reports its own counters")
	assert_gt(float(_snapshots), 10.0, "the host actually sent snapshots in the window")

	var snapshot_hz: float = float(_host.get_settings().snapshot_hz)
	var down_bytes: int = int(host_stats.get("sent_bytes", 0))
	var down_packets: int = int(host_stats.get("sent_packets", 0))
	var per_snapshot: float = float(down_bytes) / float(_snapshots)
	var down_rate: float = per_snapshot * snapshot_hz

	var up_bytes: int = int(client_stats.get("sent_bytes", 0))
	var up_packets: int = int(client_stats.get("sent_packets", 0))
	var per_intent: float = float(up_bytes) / float(maxi(up_packets, 1))
	var up_rate: float = float(up_bytes) / (float(MEASURE_TICKS) * SIM_DELTA)

	# One client is measured; a full lobby is the host talking to seven of them.
	var host_upstream: float = down_rate * float(SEATS - 1)

	print("          %s" % label)
	print("            DOWN %d B/snapshot over %d packets -> %.1f kB/s per client, %.1f kB/s host upstream at %d seats" % [
		int(per_snapshot), down_packets, down_rate / 1000.0, host_upstream / 1000.0, SEATS,
	])
	print("            UP   %d B/packet over %d packets -> %.1f kB/s per client" % [
		int(per_intent), up_packets, up_rate / 1000.0,
	])
	print("            on 4G: %.2f Mbit/s up from the host, %.3f Mbit/s up from a client" % [
		host_upstream * 8.0 / 1e6, up_rate * 8.0 / 1e6,
	])
	return per_snapshot


func test_the_wire_cost_of_eight_seats_is_measured_and_within_budget() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	var per_snapshot: float = await _measure_window("compressed, as shipped")

	assert_lt(
		per_snapshot,
		float(SNAPSHOT_WIRE_BUDGET),
		"a snapshot fits in one datagram on any path worth playing on",
	)
	# The codec's own arithmetic, so a body that grew a field is caught here as
	# well as in the codec test.
	assert_le(
		NetCodec.SNAPSHOT_HEADER_SIZE + SEATS * NetCodec.SNAPSHOT_BODY_SIZE,
		SNAPSHOT_WIRE_BUDGET,
		"and so does the payload the codec builds",
	)


func test_compression_is_worth_its_microseconds() -> void:
	# Both ends or neither: a host that compresses and a client that does not
	# have a connection that establishes and then reads rubbish. Turned off
	# here to price what it is worth, which is the only way to know whether to
	# keep paying for it.
	_host.get_settings().compress_traffic = false
	_client.get_settings().compress_traffic = false
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return
	var plain: float = await _measure_window("uncompressed, for comparison")

	assert_gt(
		plain,
		float(NetCodec.SNAPSHOT_HEADER_SIZE + SEATS * NetCodec.SNAPSHOT_BODY_SIZE),
		"an uncompressed snapshot is at least the payload the codec built",
	)
	assert_lt(
		plain, float(SNAPSHOT_WIRE_BUDGET), "and still fits in one datagram without the coder"
	)


# --- CPU ----------------------------------------------------------------------

func test_the_replicator_costs_microseconds_a_tick_at_eight_seats() -> void:
	if not await _stand_up():
		fail("the loopback handshake did not complete")
		return

	var snapshot: WorldSnapshot = WorldSnapshot.new()
	for link: PlayerNetLink in _host_links:
		link.sample_state(snapshot.next_slot())
		snapshot.commit()
	snapshot.tick = 1000

	# The host's per-tick work: read eight bodies, pack them.
	var started: int = Time.get_ticks_usec()
	for _i: int in BENCH_ITERATIONS:
		snapshot.clear()
		for link: PlayerNetLink in _host_links:
			link.sample_state(snapshot.next_slot())
			snapshot.commit()
		var _packed: PackedByteArray = NetCodec.pack_snapshot(snapshot)
	var host_usec: float = float(Time.get_ticks_usec() - started) / float(BENCH_ITERATIONS)

	# The client's per-snapshot work: unpack eight bodies and take them.
	var payload: PackedByteArray = NetCodec.pack_snapshot(snapshot)
	var incoming: WorldSnapshot = WorldSnapshot.new()
	started = Time.get_ticks_usec()
	for i: int in BENCH_ITERATIONS:
		incoming.clear()
		assert_true(NetCodec.unpack_snapshot(payload, incoming), "the benchmark payload decodes")
		incoming.tick = 2000 + i
		_client.replicator.apply_snapshot(incoming)
	var client_usec: float = float(Time.get_ticks_usec() - started) / float(BENCH_ITERATIONS)

	# And the client's per-DRAWN-FRAME work, which is the one that runs at the
	# frame rate rather than the snapshot rate.
	started = Time.get_ticks_usec()
	for _i: int in BENCH_ITERATIONS:
		_client.replicator.play_back(SIM_DELTA)
	var playback_usec: float = float(Time.get_ticks_usec() - started) / float(BENCH_ITERATIONS)

	print("          CPU host %.1f us/snapshot, client %.1f us/snapshot, playback %.1f us/frame, at %d seats" % [
		host_usec, client_usec, playback_usec, SEATS,
	])

	# A 60 Hz tick is 16667 us. Replication may have a per cent of it and no
	# more; the real numbers are far under this and the budget is here to catch
	# a change of order, not to be approached.
	assert_lt(host_usec, 167.0, "the host's snapshot costs under 1% of a tick")
	assert_lt(client_usec, 167.0, "and so does the client's")
	assert_lt(playback_usec, 167.0, "and so does a frame of playback")
