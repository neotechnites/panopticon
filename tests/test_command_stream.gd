extends TestCase

## The host half of the command stream on simulated lines (DESIGN 3.3): a client's [CommandStream.Outbox]
## packs every unacknowledged command, a [NetConditions] wire carries them, and the host's
## [CommandStream] runs them at its ticks while its acknowledgements go back the other way.

const TICK_MS: float = 1000.0 / 60.0
const SNAPSHOT_EVERY: int = 2


## One client and the host's stream for it. The client makes [member rate] commands a host tick
## while awake; [member burst] more at once on the tick it wakes, as Godot runs up to eight
## physics steps on the frame after a stall.
class Line:
	extends RefCounted

	var outbox: CommandStream.Outbox = CommandStream.Outbox.new()
	var stream: CommandStream = CommandStream.new()
	var up: NetConditions = NetConditions.new(1)
	var down: NetConditions = NetConditions.new(2)
	var rate: float = 1.0
	var tick: int = 0
	var made: float = 0.0
	var asleep_until: int = -1
	var burst: int = 0
	## Newest sequence the client has sent, and the most the host has ever acknowledged.
	var sent: int = -1
	var worst_ack_ahead: int = 0
	## Per host tick: commands run, and the backlog the tick started with.
	var ran: PackedInt32Array = PackedInt32Array()
	var backlog: PackedInt32Array = PackedInt32Array()
	var skipped: int = 0
	var first_arrival: int = -1
	var first_run_after: int = -1

	func step() -> void:
		var now: float = float(tick) * TICK_MS
		if tick >= asleep_until:
			var due: int = 0
			made += rate
			while made >= 1.0:
				made -= 1.0
				due += 1
			if tick == asleep_until and asleep_until >= 0:
				due += burst
			for _i: int in due:
				_send(now)
		var arrived: bool = false
		for packet: PackedByteArray in up.pop_due(now):
			arrived = arrived or stream.receive(packet, tick) >= 0
		if arrived and first_arrival < 0 and asleep_until >= 0 and tick >= asleep_until:
			first_arrival = tick
		var ack_before: int = stream.get_ack()
		var run_before: int = stream.get_run_total()
		var count: int = stream.commands_due()
		backlog.append(stream.get_backlog())
		for _i: int in count:
			stream.next_command(TICK_MS / 1000.0)
		ran.append(stream.get_run_total() - run_before)
		skipped += (stream.get_ack() - ack_before) - (stream.get_run_total() - run_before)
		if first_arrival >= 0 and first_run_after < 0 and stream.get_run_total() > run_before:
			first_run_after = tick
		worst_ack_ahead = maxi(worst_ack_ahead, stream.get_ack() - sent)
		stream.end_tick()
		if tick % SNAPSHOT_EVERY == 0:
			var ack: PackedByteArray = PackedByteArray()
			ack.resize(8)
			ack.encode_s64(0, stream.get_ack())
			down.push(1, false, ack, now)
		for packet: PackedByteArray in down.pop_due(now):
			outbox.acknowledge(packet.decode_s64(0))
		tick += 1

	func _send(now: float) -> void:
		var command: MoveIntent = MoveIntent.new()
		command.move_direction = Vector2(0.0, 1.0)
		sent = outbox.push(command)
		up.push(1, false, outbox.pack(1, -1), now)

	func run(ticks: int) -> void:
		for _i: int in ticks:
			step()

	func close() -> void:
		stream.free()


var _lines: Array[Line] = []


func after_each() -> void:
	for line: Line in _lines:
		line.close()
	_lines.clear()


func _line(delay_ms: float) -> Line:
	var line: Line = Line.new()
	line.up.delay_ms = delay_ms
	line.down.delay_ms = delay_ms
	_lines.append(line)
	return line


func _starved_share(line: Line, from: int) -> float:
	var starved: int = 0
	for i: int in range(from, line.ran.size()):
		starved += int(line.ran[i] == 0)
	return float(starved) / float(maxi(line.ran.size() - from, 1))


func test_a_jittery_reordering_line_discards_nothing_and_stops_starving() -> void:
	var line: Line = _line(80.0)
	line.up.jitter_ms = 20.0
	line.up.jitter_reorders = true
	line.up.reorder = 0.02
	line.up.reorder_ms = 40.0
	line.run(30 * 60)
	var starved: float = _starved_share(line, 120)
	print("          JITTER 80 ms +-20, 2%% reorder: target %d, %.2f%% starved after 2 s, %d skipped, %d run" % [
		line.stream.get_target(), starved * 100.0, line.skipped, line.stream.get_run_total()])
	assert_eq_int(line.skipped, 0, "no real command is ever discarded")
	assert_lt(starved, 0.01, "past the first two seconds the seat waits on under 1% of ticks")
	assert_ge(float(line.stream.get_run_total()), float(line.sent) - 12.0, "and keeps up with the client")


func test_a_client_frozen_three_seconds_moves_on_its_own_input_soon_after_waking() -> void:
	var line: Line = _line(30.0)
	line.run(120)
	line.asleep_until = line.tick + 180
	line.burst = 7
	line.run(180 + 240)
	print("          FREEZE 3 s: first packet at tick %d, first command run at %d, target %d" % [
		line.first_arrival, line.first_run_after, line.stream.get_target()])
	assert_true(line.first_arrival >= 0, "the woken client's packets arrived")
	assert_le(
		float(line.first_run_after - line.first_arrival), float(line.stream.get_target() + 2),
		"its body moves on its own commands within target + 2 ticks of the first one arriving",
	)
	assert_le(float(line.worst_ack_ahead), 0.0, "and the host never acknowledges a command the client did not send")


func test_a_post_freeze_surplus_is_drained_within_two_seconds() -> void:
	var line: Line = _line(30.0)
	line.run(120)
	line.asleep_until = line.tick + 180
	line.burst = 7
	line.run(180)
	var woke: int = line.tick
	line.run(240)
	var settled: int = -1
	for i: int in range(woke, line.backlog.size()):
		if line.backlog[i] <= line.stream.get_target() + 1:
			var stays: bool = true
			for j: int in range(i, mini(i + 30, line.backlog.size())):
				stays = stays and line.backlog[j] <= line.stream.get_target() + 1
			if stays:
				settled = i
				break
	print("          FREEZE surplus: woke at %d, backlog back to target+1 at %d" % [woke, settled])
	assert_true(settled >= 0 and settled - woke <= 120, "the surplus the wake burst left is gone within 2 s")


func test_a_bursting_client_cannot_outrun_the_ledger() -> void:
	var line: Line = _line(20.0)
	line.rate = 3.0
	var worst: float = -INF
	var most: int = 0
	for _i: int in 600:
		line.step()
		var bound: float = float(line.stream.get_elapsed()) * (1.0 + CommandStream.LEDGER_SLOPE) + CommandStream.LEDGER_BURST
		worst = maxf(worst, float(line.stream.get_run_total()) - bound)
		most = maxi(most, line.ran[line.ran.size() - 1])
	print("          BURST x3: %d run in %d ticks, worst margin %.1f, most a tick %d" % [
		line.stream.get_run_total(), line.stream.get_elapsed(), worst, most])
	assert_le(worst, 0.0, "a client making commands three times as fast runs no more than elapsed x (1 + 1/30) + 16")
	assert_le(float(most), 2.0, "and never more than two a tick")


func test_a_client_clock_half_a_percent_fast_holds_its_buffer_for_ten_minutes() -> void:
	var line: Line = _line(50.0)
	line.rate = 1.005
	line.run(10 * 60 * 60)
	var target: int = line.stream.get_target()
	var deepest: int = 0
	for i: int in range(120, line.backlog.size()):
		deepest = maxi(deepest, line.backlog[i])
	print("          CLOCK +0.5%%: target %d, deepest backlog %d over 10 min, %d skipped" % [target, deepest, line.skipped])
	assert_le(float(deepest), float(target + 1), "the backlog stays within target + 1")
	assert_eq_int(line.skipped, 0, "and the extra commands are run, not thrown away")


func _command() -> MoveIntent:
	var command: MoveIntent = MoveIntent.new()
	command.move_direction = Vector2(0.0, 1.0)
	return command


## One host tick at real-time tick [param wall], running what is due; the commands run.
func _host_tick(stream: CommandStream, wall: int) -> int:
	var count: int = stream.commands_due()
	for _i: int in count:
		stream.next_command(TICK_MS / 1000.0)
	stream.end_tick(wall)
	return count


func test_a_sender_past_its_resend_cap_is_resynced_to_what_it_still_sends() -> void:
	var outbox: CommandStream.Outbox = CommandStream.Outbox.new()
	var stream: CommandStream = CommandStream.new()
	outbox.push(_command())
	stream.receive(outbox.pack(1, -1), 0)
	_host_tick(stream, -1)
	# The host hears nothing for 100 ticks while the client makes 100 more; it resends only the newest 32.
	for _i: int in 100:
		outbox.push(_command())
		_host_tick(stream, -1)
	assert_ge(float(stream.receive(outbox.pack(1, -1), 1)), 0.0, "the packet is taken")
	assert_eq_int(stream.get_ack(), outbox.next_seq() - 1 - NetCodec.MAX_COMMANDS, "the stream resyncs to just before the oldest it was sent")
	assert_eq_int(stream.get_backlog(), NetCodec.MAX_COMMANDS, "and holds every command it was sent")
	stream.free()


func test_a_sequence_further_ahead_than_real_time_is_refused() -> void:
	var stream: CommandStream = CommandStream.new()
	var commands: Array[MoveIntent] = [_command()]
	stream.receive(NetCodec.pack_commands(1, 0, -1, commands, 1), 0)
	for tick: int in 10:
		stream.receive(NetCodec.pack_commands(1, tick + 1, -1, commands, 1), tick)
		_host_tick(stream, -1)
	var ack: int = stream.get_ack()
	assert_eq_int(stream.receive(NetCodec.pack_commands(1, 5000, -1, commands, 1), 10), -1, "a number 5000 ahead after 10 ticks is a forgery")
	assert_ge(float(stream.receive(NetCodec.pack_commands(1, 11, -1, commands, 1), 10)), 0.0, "and the real next packet is still taken")
	_host_tick(stream, -1)
	assert_gt(float(stream.get_ack()), float(ack), "so the seat runs on")
	stream.free()


func test_a_host_stall_counts_as_time_and_its_backlog_drains() -> void:
	var outbox: CommandStream.Outbox = CommandStream.Outbox.new()
	var stream: CommandStream = CommandStream.new()
	var wall: int = 1000
	for _tick: int in 120:
		outbox.push(_command())
		stream.receive(outbox.pack(1, -1), wall)
		outbox.acknowledge(stream.get_ack())
		_host_tick(stream, wall)
		wall += 1
	var elapsed: int = stream.get_elapsed()
	# The host stops for half a second; the client goes on and its 30 commands land at once.
	for _i: int in 30:
		outbox.push(_command())
		stream.receive(outbox.pack(1, -1), wall)
		wall += 1
	_host_tick(stream, wall)
	assert_ge(float(stream.get_elapsed() - elapsed), 30.0, "the stall the client lived through is time on the ledger")
	var settled: int = -1
	for tick: int in 60:
		wall += 1
		outbox.push(_command())
		stream.receive(outbox.pack(1, -1), wall)
		outbox.acknowledge(stream.get_ack())
		_host_tick(stream, wall)
		if settled < 0 and stream.get_backlog() <= stream.get_target() + 1:
			settled = tick
	print("          HOST STALL 30 ticks: backlog back to target+1 %d ticks after" % settled)
	assert_true(settled >= 0 and settled <= 40, "and the backlog it left drains at once, not a second later")
	stream.free()
