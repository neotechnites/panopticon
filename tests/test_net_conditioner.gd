extends TestCase

## The test network: [NetConditions] produces each distribution it is set for, and [LossyPeer]
## applies it to real ENet packets, one independent path per peer. Each test prints what it measured.

const N: int = 20000
const SPACING_MS: float = 10.0
const PORT_WAIT_MS: int = 4000


## Push [param count] items one every [param spacing_ms] on path 1 (every [param reliable_every]th
## reliable) and run the clock until the link is empty. Returns [seq, sent_ms, arrived_ms, reliable]
## in arrival order.
func _carry(c: NetConditions, count: int, spacing_ms: float, reliable_every: int = 0) -> Array:
	var arrived: Array = []
	var sent: int = 0
	while sent < count or c.pending() > 0:
		var next_send: float = float(sent) * spacing_ms if sent < count else INF
		var now: float = minf(next_send, c.next_due())
		for item: Array in c.pop_due(now):
			arrived.append([item[0], item[1], now, item[2]])
		if sent < count and next_send <= now:
			var reliable: bool = reliable_every > 0 and sent % reliable_every == 0
			c.push(1, reliable, [sent, now, reliable], now)
			sent += 1
	return arrived


func _delays(arrived: Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	for a: Array in arrived:
		out.append(float(a[2]) - float(a[1]))
	return out


func _mean(values: PackedFloat64Array) -> float:
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(maxi(values.size(), 1))


func _sd(values: PackedFloat64Array) -> float:
	var m: float = _mean(values)
	var total: float = 0.0
	for v: float in values:
		total += (v - m) * (v - m)
	return sqrt(total / float(maxi(values.size() - 1, 1)))


func _share(values: PackedFloat64Array, low: float, high: float) -> float:
	var inside: int = 0
	for v: float in values:
		if v >= low and v < high:
			inside += 1
	return float(inside) / float(maxi(values.size(), 1))


## Sequence numbers that never arrived, out of [param count].
func _missing(arrived: Array, count: int) -> PackedInt32Array:
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(count)
	for a: Array in arrived:
		seen[int(a[0])] = 1
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in count:
		if seen[i] == 0:
			out.append(i)
	return out


## Lengths of the runs of consecutive missing sequence numbers.
func _runs(missing: PackedInt32Array) -> PackedFloat64Array:
	var runs: PackedFloat64Array = PackedFloat64Array()
	var length: int = 0
	for i: int in missing.size():
		length = length + 1 if i > 0 and missing[i] == missing[i - 1] + 1 else 1
		if i == missing.size() - 1 or missing[i + 1] != missing[i] + 1:
			runs.append(length)
	return runs


## RFC 4737: an item is reordered when it arrives after one sent later; its extent is how many
## items sent after it arrived before it.
func _reordered(arrived: Array) -> PackedFloat64Array:
	var extents: PackedFloat64Array = PackedFloat64Array()
	var arrived_before: Dictionary[int, bool] = {}
	var highest: int = -1
	for a: Array in arrived:
		var seq: int = int(a[0])
		if seq < highest:
			var extent: int = 0
			for later: int in range(seq + 1, highest + 1):
				extent += 1 if arrived_before.has(later) else 0
			extents.append(extent)
		highest = maxi(highest, seq)
		arrived_before[seq] = true
	return extents


func _histogram(values: PackedFloat64Array, low: float, high: float, bins: int) -> String:
	var line: PackedStringArray = PackedStringArray()
	var width: float = (high - low) / float(bins)
	for b: int in bins:
		line.append("%.0f-%.0f:%.3f" % [low + b * width, low + (b + 1) * width,
			_share(values, low + b * width, low + (b + 1) * width)])
	return " ".join(line)


# --- Delay and jitter ---------------------------------------------------------

func test_uniform_jitter_spreads_flat_around_the_delay() -> void:
	var c: NetConditions = NetConditions.new(11)
	c.delay_ms = 50.0
	c.jitter_ms = 20.0
	c.jitter_reorders = true
	var d: PackedFloat64Array = _delays(_carry(c, N, SPACING_MS))
	print("          UNIFORM 50 +- 20 ms: mean %.2f sd %.2f (uniform sd %.2f) | %s" % [_mean(d), _sd(d),
		20.0 / sqrt(3.0), _histogram(d, 30.0, 70.0, 4)])
	assert_almost_eq(_mean(d), 50.0, 0.5, "the mean is the delay")
	assert_almost_eq(_sd(d), 20.0 / sqrt(3.0), 0.3, "the spread is a uniform one's")
	assert_almost_eq(_share(d, 30.0, 70.0 + 1e-6), 1.0, 1e-9, "nothing outside delay +- jitter")
	for b: int in 4:
		assert_almost_eq(_share(d, 30.0 + 10.0 * b, 40.0 + 10.0 * b), 0.25, 0.015, "flat: quarter %d holds a quarter" % b)


func test_normal_jitter_is_a_bell_around_the_delay() -> void:
	var c: NetConditions = NetConditions.new(12)
	c.delay_ms = 80.0
	c.jitter_ms = 10.0
	c.jitter = NetConditions.Jitter.NORMAL
	c.jitter_reorders = true
	var d: PackedFloat64Array = _delays(_carry(c, N, SPACING_MS))
	var one: float = _share(d, 70.0, 90.0)
	var two: float = _share(d, 60.0, 100.0)
	var three: float = _share(d, 50.0, 110.0)
	print("          NORMAL 80 sd 10 ms: mean %.2f sd %.2f within 1/2/3 sd %.4f %.4f %.4f | %s" % [_mean(d), _sd(d),
		one, two, three, _histogram(d, 50.0, 110.0, 6)])
	assert_almost_eq(_mean(d), 80.0, 0.3, "the mean is the delay")
	assert_almost_eq(_sd(d), 10.0, 0.25, "the standard deviation is the jitter")
	assert_almost_eq(one, 0.6827, 0.015, "68% within one deviation")
	assert_almost_eq(two, 0.9545, 0.008, "95% within two")
	assert_almost_eq(three, 0.9973, 0.002, "99.7% within three")


func test_jitter_never_sends_a_packet_back_in_time() -> void:
	var c: NetConditions = NetConditions.new(13)
	c.delay_ms = 5.0
	c.jitter_ms = 10.0
	c.jitter = NetConditions.Jitter.NORMAL
	c.jitter_reorders = true
	var d: PackedFloat64Array = _delays(_carry(c, 5000, SPACING_MS))
	var lowest: float = INF
	for v: float in d:
		lowest = minf(lowest, v)
	assert_ge(lowest, 0.0, "a delay is clamped at zero, as netem clamps it")


func test_jitter_keeps_a_path_in_order_unless_it_is_allowed_to_reorder() -> void:
	var c: NetConditions = NetConditions.new(14)
	c.delay_ms = 40.0
	c.jitter_ms = 20.0
	var fifo: Array = _carry(c, N, SPACING_MS)
	var free_c: NetConditions = NetConditions.new(14)
	free_c.delay_ms = 40.0
	free_c.jitter_ms = 20.0
	free_c.jitter_reorders = true
	var free: Array = _carry(free_c, N, SPACING_MS)
	var d: PackedFloat64Array = _delays(fifo)
	var lowest: float = INF
	for v: float in d:
		lowest = minf(lowest, v)
	print("          FIFO 40 +- 20 ms at %.0f ms spacing: %d reordered, mean %.2f sd %.2f; free: %d reordered (%.3f)" % [
		SPACING_MS, _reordered(fifo).size(), _mean(d), _sd(d), _reordered(free).size(),
		float(_reordered(free).size()) / float(N)])
	assert_eq_int(_reordered(fifo).size(), 0, "in-order jitter reorders nothing")
	assert_ge(lowest, 20.0 - 1e-6, "and never delivers sooner than its own draw")
	assert_gt(_sd(d), 5.0, "while still spreading the delay")
	assert_gt(float(_reordered(free).size()), float(N) * 0.05, "free jitter does reorder")


func test_remembered_jitter_keeps_its_marginal_and_the_path_in_order() -> void:
	for dist: NetConditions.Jitter in [NetConditions.Jitter.NORMAL, NetConditions.Jitter.UNIFORM]:
		for spacing: float in [10.0, 40.0]:
			var c: NetConditions = NetConditions.new(15)
			c.delay_ms = 80.0
			c.jitter_ms = 20.0
			c.jitter = dist
			c.jitter_tau_ms = 200.0
			var count: int = int(2000000.0 / spacing)
			var arrived: Array = _carry(c, count, spacing)
			var d: PackedFloat64Array = _delays(arrived)
			var want_sd: float = 20.0 if dist == NetConditions.Jitter.NORMAL else 20.0 / sqrt(3.0)
			var lag: int = int(100.0 / spacing)
			var name: String = "normal" if dist == NetConditions.Jitter.NORMAL else "uniform"
			print("          OU %s 80 / 20 ms, tau 200 ms, at %.0f ms spacing: mean %.2f sd %.2f (want %.2f), corr at 100 ms %.3f (exp -0.5 = 0.607), %d reordered | %s" % [
				name, spacing, _mean(d), _sd(d), want_sd, _autocorrelation(d, lag), _reordered(arrived).size(),
				_histogram(d, 40.0, 120.0, 8)])
			assert_eq_int(_reordered(arrived).size(), 0, "%s at %.0f ms: in order" % [name, spacing])
			assert_almost_eq(_mean(d), 80.0, 1.5, "%s at %.0f ms: the mean is the delay" % [name, spacing])
			assert_almost_eq(_sd(d), want_sd, want_sd * 0.06, "%s at %.0f ms: the marginal spread, whatever the rate" % [name, spacing])
			assert_almost_eq(_autocorrelation(d, lag), exp(-0.5), 0.07, "%s at %.0f ms: remembers itself for tau" % [name, spacing])


func _autocorrelation(values: PackedFloat64Array, lag: int) -> float:
	var m: float = _mean(values)
	var top: float = 0.0
	var bottom: float = 0.0
	for i: int in values.size():
		bottom += (values[i] - m) * (values[i] - m)
		if i + lag < values.size():
			top += (values[i] - m) * (values[i + lag] - m)
	return top / maxf(bottom, 1e-9)


# --- Loss ---------------------------------------------------------------------

func test_bernoulli_loss_replays_the_drops_the_first_conditioner_made() -> void:
	var c: NetConditions = NetConditions.new(7)
	c.loss = 0.2
	var missing: PackedInt32Array = _missing(_carry(c, N, SPACING_MS), N)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var expected: PackedInt32Array = PackedInt32Array()
	for i: int in N:
		if rng.randf() < 0.2:
			expected.append(i)
	print("          BERNOULLI 0.20: lost %.4f, mean run %.3f (geometric 1.25)" % [
		float(missing.size()) / N, _mean(_runs(missing))])
	assert_true(missing == expected, "the same seed drops the same packets as one randf() per packet")
	assert_almost_eq(float(missing.size()) / N, 0.2, 0.01, "at the rate asked for")
	assert_almost_eq(_mean(_runs(missing)), 1.25, 0.05, "in independent drops")


func test_bursts_follow_the_gilbert_elliott_link_in_time() -> void:
	# Bad spells of 100 ms on average, every second on average: 10% of the time, so 10% lost.
	for spacing: float in [10.0, 40.0]:
		var c: NetConditions = NetConditions.new(21)
		c.burst_ms = 100.0
		c.burst_gap_ms = 900.0
		var count: int = int(500000.0 / spacing)
		var missing: PackedInt32Array = _missing(_carry(c, count, spacing), count)
		var runs: PackedFloat64Array = _runs(missing)
		# Seen every [spacing] ms, a bad spell stays bad with the two-state chance below: geometric runs.
		var stay: float = 0.1 + 0.9 * exp(-(1.0 / 900.0 + 1.0 / 100.0) * spacing)
		var expected_run: float = 1.0 / (1.0 - stay)
		print("          GILBERT-ELLIOTT 100/900 ms at %.0f ms spacing: lost %.4f, mean run %.2f packets = %.0f ms (expected %.2f); runs of 1: %.3f" % [
			spacing, float(missing.size()) / count, _mean(runs), _mean(runs) * spacing, expected_run,
			_share(runs, 1.0, 1.5)])
		assert_almost_eq(float(missing.size()) / count, 0.1, 0.02, "10%% lost at %.0f ms spacing" % spacing)
		assert_almost_eq(_mean(runs), expected_run, expected_run * 0.15, "in runs a 100 ms spell makes at %.0f ms" % spacing)
		assert_almost_eq(_share(runs, 1.0, 1.5), 1.0 - stay, 0.05,
			"geometric: the share of single losses at %.0f ms" % spacing)


func test_a_partly_lossy_bad_spell_mixes_with_good_state_loss() -> void:
	var c: NetConditions = NetConditions.new(22)
	c.burst_ms = 200.0
	c.burst_gap_ms = 1800.0
	c.burst_loss = 0.5
	c.loss = 0.02
	var count: int = 60000
	var lost: float = float(_missing(_carry(c, count, SPACING_MS), count).size()) / count
	print("          GILBERT-ELLIOTT bad 50%% good 2%%: lost %.4f (stationary %.4f)" % [lost, 0.1 * 0.5 + 0.9 * 0.02])
	assert_almost_eq(lost, 0.1 * 0.5 + 0.9 * 0.02, 0.015, "the stationary mix of both states")


func test_every_path_has_its_own_link() -> void:
	var c: NetConditions = NetConditions.new(23)
	c.burst_ms = 100.0
	c.burst_gap_ms = 400.0
	var lost: Array[Dictionary] = [{}, {}]
	for i: int in 20000:
		var now: float = float(i) * SPACING_MS
		for path: int in 2:
			if c.push(path + 1, false, i, now) == 0:
				lost[path][i] = true
		c.pop_due(now)
	var shared: int = 0
	for i: int in lost[0]:
		shared += 1 if lost[1].has(i) else 0
	print("          TWO PATHS: lost %d and %d, both %d" % [lost[0].size(), lost[1].size(), shared])
	assert_almost_eq(float(lost[0].size()) / 20000.0, 0.2, 0.04, "path 1 at the stationary rate")
	assert_almost_eq(float(lost[1].size()) / 20000.0, 0.2, 0.04, "path 2 at the stationary rate")
	assert_lt(float(shared), float(lost[0].size()) * 0.4, "and their bursts are not the same bursts")


# --- Duplication and reordering -----------------------------------------------

func test_duplicates_are_separate_packets_on_the_wire() -> void:
	var c: NetConditions = NetConditions.new(31)
	c.duplicate = 0.1
	c.delay_ms = 30.0
	c.jitter_ms = 10.0
	c.jitter_reorders = true
	var arrived: Array = _carry(c, N, SPACING_MS, 2)
	var copies: Dictionary[int, Array] = {}
	for a: Array in arrived:
		if not copies.has(int(a[0])):
			copies[int(a[0])] = []
		copies[int(a[0])].append(float(a[2]))
	var doubled: int = 0
	var apart: float = 0.0
	var reliable_doubled: int = 0
	for seq: int in copies:
		if copies[seq].size() == 2:
			if seq % 2 == 0:
				reliable_doubled += 1
			doubled += 1
			apart += absf(float(copies[seq][0]) - float(copies[seq][1]))
	var unreliable: float = float(N) / 2.0
	print("          DUPLICATE 0.10: %.4f of unreliable packets twice, copies %.1f ms apart on average" % [
		float(doubled) / unreliable, apart / maxf(doubled, 1.0)])
	assert_eq_int(reliable_doubled, 0, "a reliable packet never arrives twice")
	assert_almost_eq(float(doubled) / unreliable, 0.1, 0.008, "a tenth of unreliable packets arrive twice")
	assert_gt(apart / maxf(doubled, 1.0), 5.0, "each copy has its own delay")


func test_reordering_holds_a_packet_back_by_time_while_the_rest_stay_in_order() -> void:
	var c: NetConditions = NetConditions.new(32)
	c.delay_ms = 20.0
	c.reorder = 0.05
	c.reorder_ms = 50.0
	var arrived: Array = _carry(c, N, SPACING_MS)
	var extents: PackedFloat64Array = _reordered(arrived)
	var in_order: Array = []
	for a: Array in arrived:
		if not _was_held(a, c):
			in_order.append(a)
	# Overtaken by the packets sent strictly inside the next 50 ms that were not held themselves.
	var overtakers: float = (ceilf(50.0 / SPACING_MS) - 1.0) * (1.0 - 0.05)
	print("          REORDER 0.05 by 50 ms at %.0f ms spacing: %.4f reordered, mean extent %.2f packets (expected %.2f)" % [
		SPACING_MS, float(extents.size()) / N, _mean(extents), overtakers])
	assert_almost_eq(float(extents.size()) / N, 0.05, 0.006, "5% of packets arrive after a later one")
	assert_almost_eq(_mean(extents), overtakers, 0.2, "overtaken by the packets sent in the next 50 ms")
	assert_eq_int(_reordered(in_order).size(), 0, "nothing else is out of order")


func _was_held(a: Array, c: NetConditions) -> bool:
	return float(a[2]) - float(a[1]) > c.delay_ms + c.reorder_ms * 0.5


func test_reliable_packets_are_only_ever_late() -> void:
	var c: NetConditions = NetConditions.new(33)
	c.loss = 0.5
	c.burst_ms = 100.0
	c.burst_gap_ms = 100.0
	c.duplicate = 0.5
	c.reorder = 0.5
	c.reorder_ms = 50.0
	c.delay_ms = 30.0
	c.jitter_ms = 30.0
	c.jitter_reorders = true
	var reliable: Array[int] = []
	for a: Array in _carry(c, 6000, SPACING_MS, 3):
		if bool(a[3]):
			reliable.append(int(a[0]))
	var expected: Array[int] = []
	for i: int in range(0, 6000, 3):
		expected.append(i)
	assert_true(reliable == expected, "every reliable packet arrives once, in the order sent")


func test_adding_a_condition_moves_no_other_condition_draws() -> void:
	var plain: NetConditions = NetConditions.new(41)
	plain.loss = 0.2
	var more: NetConditions = NetConditions.new(41)
	more.loss = 0.2
	more.jitter_ms = 15.0
	more.delay_ms = 20.0
	more.duplicate = 0.0
	more.reorder = 0.1
	more.reorder_ms = 30.0
	assert_true(_missing(_carry(plain, 5000, SPACING_MS), 5000) == _missing(_carry(more, 5000, SPACING_MS), 5000),
		"jitter and reordering leave the same packets lost")


func test_a_forgotten_path_delivers_nothing_more() -> void:
	var c: NetConditions = NetConditions.new(42)
	c.delay_ms = 100.0
	for i: int in 10:
		c.push(1, false, i, float(i))
		c.push(2, false, i, float(i))
	c.forget(1)
	var out: Array = c.pop_due(1000.0)
	assert_eq_int(out.size(), 10, "only the other path's packets are still in flight")


func test_options_read_as_the_runners_write_them() -> void:
	var c: NetConditions = NetConditions.from_options({"loss": "0.1", "delay-ms": "40", "jitter-ms": "12",
		"jitter-dist": "normal", "jitter-tau-ms": "200", "jitter-reorders": "true", "burst-ms": "150", "burst-gap-ms": "2850",
		"burst-loss": "0.8", "dup": "0.05", "reorder": "0.02", "reorder-ms": "60"})
	assert_eq_string(c.describe(), "loss=0.100 delay-ms=40.0 jitter-ms=12.0 jitter-dist=normal jitter-tau-ms=200.0 jitter-reorders=true burst-ms=150.0 burst-gap-ms=2850.0 burst-loss=0.800 dup=0.050 reorder=0.020 reorder-ms=60.0",
		"every option lands where it is named")
	assert_false(NetConditions.from_options({}).is_conditioned(), "no option is a clean line")


# --- LossyPeer on real sockets ------------------------------------------------

func _wait(predicate: Callable, peers: Array, timeout_ms: int = PORT_WAIT_MS) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for p: MultiplayerPeer in peers:
			p.poll()
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


## A server wrapped in [param wire] and two raw clients connected to it. Empty on failure.
func _three(wire_of: Callable) -> Array:
	var port: int = NetFixtures.reserve_port()
	var server: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if port < 0 or server.create_server(port, 4) != OK:
		return []
	var wire: LossyPeer = wire_of.call(server)
	var clients: Array[ENetMultiplayerPeer] = []
	for _i: int in 2:
		var client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		client.create_client("127.0.0.1", port)
		clients.append(client)
	var up: bool = await _wait(func() -> bool:
		return wire.reachable_peers().size() == 2 and clients[0].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
			and clients[1].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, [wire, clients[0], clients[1]])
	return [wire, clients[0], clients[1]] if up else []


func _close(peers: Array) -> void:
	for p: MultiplayerPeer in peers:
		p.close()


func test_a_broadcast_takes_an_independent_path_to_every_peer() -> void:
	var peers: Array = await _three(func(real: MultiplayerPeer) -> LossyPeer:
		var w: LossyPeer = LossyPeer.new(real, 0.25, 5)
		w.conditions.duplicate = 0.2
		return w)
	if not assert_eq_int(peers.size(), 3, "a wrapped server and two clients connect on loopback"):
		_close(peers)
		return
	var wire: LossyPeer = peers[0]
	var got: Array[Dictionary] = [{}, {}]
	var counts: Array[int] = [0, 0]
	const SENT: int = 600
	for seq: int in SENT:
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(4)
		bytes.encode_u32(0, seq)
		wire.set_target_peer(0)
		wire.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		wire.transfer_channel = 0
		wire.put_packet(bytes)
		if seq % 20 == 19:
			await _drain(peers, got, counts)
	await _wait(func() -> bool: return false, peers, 300)
	await _drain(peers, got, counts)
	var ids: Array[int] = wire.reachable_peers()
	var delivered: Array[int] = [int(wire.conditions.stats(ids[0]).get("delivered", 0.0)),
		int(wire.conditions.stats(ids[1]).get("delivered", 0.0))]
	print("          LOSSYPEER broadcast at 25%% loss, 20%% duplication: client A %d packets (%d distinct), B %d (%d distinct); wire says %d and %d" % [
		counts[0], got[0].size(), counts[1], got[1].size(), delivered[0], delivered[1]])
	assert_eq_int(counts[0] + counts[1], delivered[0] + delivered[1], "every copy the wire let through arrived, and nothing else")
	for i: int in 2:
		assert_between(float(got[i].size()) / SENT, 0.65, 0.85, "client %d heard about 75%% of the packets" % i)
		assert_gt(float(counts[i] - got[i].size()), SENT * 0.08, "and some twice")
	var same: int = 0
	for seq: int in got[0]:
		same += 1 if got[1].has(seq) else 0
	assert_lt(float(same), float(got[0].size()) * 0.9, "the two paths lost different packets")
	_close(peers)


func _drain(peers: Array, got: Array[Dictionary], counts: Array[int]) -> void:
	for _frame: int in 3:
		for p: MultiplayerPeer in peers:
			p.poll()
		for i: int in 2:
			var client: ENetMultiplayerPeer = peers[i + 1]
			while client.get_available_packet_count() > 0:
				var packet: PackedByteArray = client.get_packet()
				got[i][packet.decode_u32(0)] = true
				counts[i] += 1
		await get_tree().process_frame


func test_a_frozen_peer_reads_and_sends_nothing_until_it_thaws() -> void:
	var peers: Array = await _three(func(real: MultiplayerPeer) -> LossyPeer: return LossyPeer.new(real))
	if not assert_eq_int(peers.size(), 3, "a wrapped server and two clients connect on loopback"):
		_close(peers)
		return
	var wire: LossyPeer = peers[0]
	var client: ENetMultiplayerPeer = peers[1]
	wire.freeze(400.0)
	var bytes: PackedByteArray = PackedByteArray([1, 2, 3, 4])
	for _i: int in 5:
		wire.set_target_peer(0)
		wire.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		wire.put_packet(bytes)
		client.set_target_peer(1)
		client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		client.put_packet(bytes)
	var heard_early: bool = await _wait(func() -> bool:
		return client.get_available_packet_count() > 0 or wire.get_available_packet_count() > 0, peers, 250)
	assert_true(wire.is_frozen(), "still frozen after 250 ms of a 400 ms freeze")
	assert_false(heard_early, "a frozen machine sends nothing and reads nothing")
	var heard: bool = await _wait(func() -> bool:
		return client.get_available_packet_count() >= 5 and wire.get_available_packet_count() >= 5, peers, 1500)
	assert_true(heard, "once thawed, what it sent leaves and what it was sent is read")
	_close(peers)
