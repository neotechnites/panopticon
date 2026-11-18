class_name CommandStream
extends IntentSource

## One seat's commands on the host, from its peer's packets: the body's [IntentSource] there.
##
## Every real command runs exactly once, in order, at a physics tick, and the host never
## invents a numbered one (Quake 3 / Source usercmds). A starved seat WAITS a tick instead of
## guessing, which is how its buffer grows under jitter; a seat whose buffer has stayed fuller
## than its line needs for a second runs one extra command a tick until it is not (Overwatch's
## target-depth buffer, with the seat's clock bending instead of the client's). See DESIGN 3.3.
##
## The client half is [CommandStream.Outbox]: it numbers this machine's commands and packs
## every unacknowledged one into each packet.

enum State { PRIMING, RUNNING, PAUSED }

## Commands held ahead of the last one run, by sequence. One past it is not stored.
const RING: int = 64
## The buffer depth a line earns: twice its measured arrival jitter in commands, within these.
const TARGET_MIN: int = 1
const TARGET_MAX: int = 4
## The ledger: never more than elapsed x (1 + SLOPE) + BURST commands run this epoch.
const LEDGER_SLOPE: float = 1.0 / 30.0
const LEDGER_BURST: int = 16
## Ticks of backlog the drain looks back over: one second.
const WINDOW_TICKS: int = 60
## Real ticks between two host ticks that make a stall: more than Godot catches up in one frame.
const HOST_STALL_TICKS: int = 8
const _JITTER_ALPHA: float = 0.1

## Starved ticks before a running stream pauses; [member NetSettings.stale_intent_ticks].
var stale_after_ticks: int = 12
## Most commands one tick runs; [member NetSettings.cmd_budget].
var cmd_budget: int = 2

var _state: State = State.PRIMING
var _ring: Array[MoveIntent] = []
var _held: PackedInt64Array = PackedInt64Array()
## The newest sequence run (the acknowledgement), and the newest any packet named; -1 for none.
var _last_run: int = -1
var _newest_seen: int = -1
## The last real command run: edges are taken against it, and a released tick keeps its view.
var _last: MoveIntent = MoveIntent.new()
var _released: MoveIntent = MoveIntent.new()
var _out: MoveIntent = MoveIntent.new()
var _decoded: Array[MoveIntent] = []
## Real commands still to hand out this tick, from [method commands_due].
var _due_real: int = 0
var _from_pause: bool = false
var _starved: int = 0
var _starved_total: int = 0
var _run_total: int = 0
## The ledger's clock: ticks since the first command, host ticks or real time if that ran further.
var _elapsed: int = 0
var _wall_start: int = -1
var _wall_last: int = -1
## [member _elapsed] when the newest packet was taken.
var _seen_at: int = 0
var _target: int = TARGET_MIN
var _jitter: float = 0.0
var _arrived_tick: int = -1
var _arrived_seq: int = -1
## Backlog at the start of each of the last [constant WINDOW_TICKS] ticks.
var _window: PackedByteArray = PackedByteArray()
var _window_at: int = 0
var _window_count: int = 0


func _init() -> void:
	_ring.resize(RING)
	for i: int in RING:
		_ring[i] = MoveIntent.new()
	_held.resize(RING)
	_decoded.resize(NetCodec.MAX_COMMANDS)
	for i: int in NetCodec.MAX_COMMANDS:
		_decoded[i] = MoveIntent.new()
	_window.resize(WINDOW_TICKS)
	reset()


## Forget everything: a new scene epoch, or a new peer. The next packet starts the stream.
func reset() -> void:
	_state = State.PRIMING
	_held.fill(-1)
	_last_run = -1
	_newest_seen = -1
	_wall_start = -1
	_wall_last = -1
	_seen_at = 0
	_last.clear()
	_due_real = 0
	_from_pause = false
	_starved = 0
	_starved_total = 0
	_run_total = 0
	_elapsed = 0
	_target = TARGET_MIN
	_jitter = 0.0
	_arrived_tick = -1
	_arrived_seq = -1
	# A new stream has a second of nothing behind it: it earns a drain like any other line.
	_window.fill(0)
	_window_at = 0
	_window_count = WINDOW_TICKS


## Take one command packet that arrived at host tick [param now]. Returns its newest sequence,
## or -1 when it is malformed or older than one already taken (the receiver's stale discard).
func receive(payload: PackedByteArray, now: int) -> int:
	var newest: int = NetCodec.command_newest(payload)
	if newest < 0 or (_newest_seen >= 0 and not NetCodec.is_newer_tick(newest, _newest_seen)):
		return -1
	if _newest_seen >= 0 and NetCodec.tick_delta(_newest_seen, newest) > _ledger_room(_elapsed - _seen_at) + NetCodec.MAX_COMMANDS:
		# More commands than real time since the last packet allows: a forged number, not a line.
		return -1
	var snap_ack: int = NetCodec.command_snap_ack(payload)
	var snap_tick: int = -1 if snap_ack < 0 else now - NetCodec.tick_delta(snap_ack, now)
	var count: int = NetCodec.unpack_commands(payload, _decoded, snap_tick)
	if count == 0:
		return -1
	var first: bool = _newest_seen < 0
	_newest_seen = newest
	_seen_at = _elapsed
	var oldest: int = newest - count + 1
	if first:
		_last_run = oldest - 1
		_elapsed = 0
		_seen_at = 0
		_wall_start = -1
	elif oldest > _last_run + 1 and _held[(_last_run + 1) % RING] != _last_run + 1:
		# The next command is missing and the sender is past its 32-command resend cap: it will
		# never come. Skip what is missing below its oldest; the backlog left is surplus, not jitter.
		while _last_run + 1 < oldest and _held[(_last_run + 1) % RING] != _last_run + 1:
			_last_run += 1
		_window_count = 0
	for i: int in count:
		var seq: int = oldest + i
		if seq <= _last_run or seq > _last_run + RING:
			continue
		var slot: int = seq % RING
		if _held[slot] != seq:
			_ring[slot].copy_from(_decoded[i])
			_held[slot] = seq
	_measure_jitter(newest, now)
	if _state == State.PAUSED:
		_state = State.PRIMING
		_from_pause = true
	return newest


## Decide this tick: 0 commands (priming, or starved and waiting), 1, or 2 while draining.
func commands_due() -> int:
	var backlog: int = get_backlog()
	_due_real = 0
	if _state == State.PRIMING:
		if backlog < _target:
			# At the start the body stays put; out of a pause it keeps falling on released keys.
			_sample(backlog)
			return 1 if _from_pause else 0
		_state = State.RUNNING
		_from_pause = false
		_starved = 0
	_sample(backlog)
	if _state == State.PAUSED:
		return 1
	if backlog == 0:
		_starved += 1
		_starved_total += 1
		if _starved > stale_after_ticks:
			_state = State.PAUSED
		return 0
	_starved = 0
	_due_real = 1
	var drain: bool = _window_min() > _target
	while drain and _due_real < cmd_budget and _due_real < backlog and _ledger_allows(_due_real + 1):
		_due_real += 1
	return _due_real


## The next command due: the next real one, its edges against the last run, or a released tick.
func next_command(_delta: float) -> MoveIntent:
	if _due_real <= 0:
		_released.clear()
		_released.view_angles = _last.view_angles
		_released.view_absolute = _last.view_absolute
		return _released
	_due_real -= 1
	var seq: int = _last_run + 1
	var slot: int = seq % RING
	_out.copy_from(_ring[slot])
	# Against the last one run, or against nothing at the start: as the client's own new source did.
	_out.derive_edges(_last.buttons)
	_last.copy_from(_ring[slot])
	_held[slot] = -1
	_last_run = seq
	_run_total += 1
	return _out


## One host tick has passed for this stream, run or not: the ledger's clock. [param wall_tick] is
## real time in ticks, so a host hitch the client lived through counts as time; -1 counts ticks.
func end_tick(wall_tick: int = -1) -> void:
	if _wall_start < 0:
		_wall_start = wall_tick
	if _wall_last >= 0 and wall_tick - _wall_last > HOST_STALL_TICKS:
		# The host stalled: the backlog its seats built meanwhile is the stall's, not their lines'.
		_window_count = 0
	_wall_last = wall_tick
	_elapsed = maxi(_elapsed + 1, wall_tick - _wall_start if wall_tick >= 0 else 0)


## The newest sequence run: the seat's acknowledgement, -1 before any.
func get_ack() -> int:
	return _last_run


## Commands held in order after the last run, up to the first one missing.
func get_backlog() -> int:
	var count: int = 0
	while count < RING and _held[(_last_run + 1 + count) % RING] == _last_run + 1 + count:
		count += 1
	return count


func get_state() -> State:
	return _state


func get_target() -> int:
	return _target


func get_starved_total() -> int:
	return _starved_total


func get_run_total() -> int:
	return _run_total


func get_elapsed() -> int:
	return _elapsed


## Mean backlog over the last second less the target: what a client clock could be told to fix.
func get_cmd_buffer() -> float:
	var total: int = 0
	for i: int in _window_count:
		total += _window[(_window_at - 1 - i + WINDOW_TICKS) % WINDOW_TICKS]
	return float(total) / float(maxi(_window_count, 1)) - float(_target)


func _ledger_allows(commands: int) -> bool:
	return _run_total + commands <= _ledger_room(_elapsed)


## The most commands [param ticks] of real time can make: ticks x (1 + 1/30) + 16.
func _ledger_room(ticks: int) -> int:
	return floori(float(ticks) * (1.0 + LEDGER_SLOPE)) + LEDGER_BURST


## The least backlog since the window's last second began, or since a discontinuity emptied it.
func _window_min() -> int:
	var least: int = 255
	for i: int in _window_count:
		least = mini(least, _window[(_window_at - 1 - i + WINDOW_TICKS) % WINDOW_TICKS])
	return least


func _sample(backlog: int) -> void:
	_window[_window_at] = mini(backlog, 255)
	_window_at = (_window_at + 1) % WINDOW_TICKS
	_window_count = mini(_window_count + 1, WINDOW_TICKS)


## Arrival jitter in ticks: how far each packet's arrival strays from the commands it advanced by.
func _measure_jitter(newest: int, now: int) -> void:
	if _arrived_seq >= 0:
		var expected: int = NetCodec.tick_delta(_arrived_seq, newest)
		var observed: int = now - _arrived_tick
		_jitter = lerpf(_jitter, absf(float(observed - expected)), _JITTER_ALPHA)
		_target = clampi(ceili(2.0 * _jitter), TARGET_MIN, TARGET_MAX)
	_arrived_seq = newest
	_arrived_tick = now


## The client half: this machine's commands, numbered, kept until the host has run them.
class Outbox:
	extends RefCounted

	var _ring: Array[MoveIntent] = []
	var _send: Array[MoveIntent] = []
	var _next: int = 0
	var _acked: int = -1

	func _init() -> void:
		_ring.resize(CommandStream.RING)
		for i: int in CommandStream.RING:
			_ring[i] = MoveIntent.new()
		_send.resize(NetCodec.MAX_COMMANDS)

	## Number [param command] and keep a copy. Returns its sequence.
	func push(command: MoveIntent) -> int:
		var seq: int = _next
		_ring[seq % CommandStream.RING].copy_from(command)
		_next += 1
		return seq

	## The host has run everything up to [param ack].
	func acknowledge(ack: int) -> void:
		if ack >= 0 and (_acked < 0 or NetCodec.is_newer_tick(ack, _acked)) and ack < _next:
			_acked = ack

	## Every command since the newest acknowledgement, at most [constant NetCodec.MAX_COMMANDS], as
	## one packet; empty when there is none.
	func pack(epoch: int, snap_ack: int) -> PackedByteArray:
		var first: int = maxi(_acked + 1, _next - NetCodec.MAX_COMMANDS)
		var count: int = _next - first
		if count <= 0:
			return PackedByteArray()
		for i: int in count:
			_send[i] = _ring[(first + i) % CommandStream.RING]
		return NetCodec.pack_commands(epoch, _next - 1, snap_ack, _send, count)

	## A new scene: nothing sent for the last one is waiting to be run.
	func flush() -> void:
		_acked = _next - 1

	## The sequence the next command will get.
	func next_seq() -> int:
		return _next

	func get_acked() -> int:
		return _acked
