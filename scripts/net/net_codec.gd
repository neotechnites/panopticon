class_name NetCodec
extends RefCounted

## The wire format: [MoveIntent], [WorldSnapshot] and the lobby roster to and
## from bytes.
##
## Everything crossing the network goes through here, for three reasons.
##
## [b]Size.[/b] Godot will happily send a [Dictionary] over an RPC, and it
## costs several times what these do -- an intent is 21 bytes packed and about
## 120 as a variant dictionary, sent 60 times a second per player. Small
## lobbies do not make that free; they make it invisible until someone is on a
## bad connection.
##
## [b]Validation.[/b] A client's packet is hostile input. Byte arrays have to
## be length-checked before they are read, and doing that in one place means it
## cannot be forgotten in a second place. Decoding never trusts the payload: a
## wrong length returns failure and the caller drops the packet. Note what this
## does [i]not[/i] do -- it does not bound the values inside a well-formed
## packet. A client can still send a pitch of a thousand radians; clamping
## that is the authority's job, in [PlayerController], because the sane range
## comes from [MovementProfile] and the codec has no business knowing about
## tunables. The one exception is [method sanitise_name], and it is here
## because a display name has no sane range to consult -- only a length and a
## rule about control characters, both of which are properties of the wire.
##
## [b]Stability.[/b] One file to read when the format has to change, and one
## place to put a version byte when it does. There is no version byte today:
## there are no shipped clients to be incompatible with, and a field added
## before release costs nothing.
##
## Decoding writes into a caller-owned object and returns a [bool], rather than
## allocating and returning a new one, so the per-tick path allocates nothing
## but the [PackedByteArray] itself.
##
## [b]Quantisation[/b]
##
## A snapshot body carries no float. Position and velocity are centimetres in
## an [code]i16[/code], angles are a fixed fraction of a turn, timers are
## tenths. That is 28 bytes a body against 46 for the same fields as floats,
## and the error it costs -- five millimetres of position, five millimetres a
## second of speed -- is under the noise floor of a body that is drawn
## interpolated and corrected thirty times a second.
##
## The one place it is NOT free is a predicting client: reconciliation measures
## its own guess against the authority's quantised answer, so five millimetres
## of the error it reports is the wire and not the prediction. That is two
## orders under [member NetSettings.prediction_snap_metres] and is why the
## quantisation is this coarse and not coarser.
##
## [b]What is deliberately not here[/b]
##
## Nothing about delta compression. Every field of every
## body goes every snapshot. At eight players that is about 210 bytes a packet,
## which is cheap; it is listed as a gap rather than a feature because it is a
## habit that stops being cheap at a player count this game will never reach.

## Bytes of command packet header: u16 epoch, u32 newest sequence, u8 command count, u32 snap ack
## (the newest snapshot tick the sender decoded, or [constant NO_ACK]).
const COMMAND_HEADER_SIZE: int = 11

## Most commands one packet may carry: every unacknowledged one, up to about half a second.
const MAX_COMMANDS: int = 32

## What a command's view time is relative to: 64ths of a tick from the packet's snap ack.
const VIEW_TIME_STEPS: float = 64.0
const _VIEW_TIME_NONE: int = -32768

## Bytes of snapshot header: u32 tick, u32 scene epoch, u8 body count.
const SNAPSHOT_HEADER_SIZE: int = 9

## Bytes per body inside a snapshot: u8 seat, 3 i16 of position, 3 i16 of
## velocity, u16 yaw, i16 pitch, u16 view base, 2 flag bytes, u8 running ability, u8 tenths left
## on it, u8 tenths of its cooldown, u8 hit points and u32 acknowledged intent
## tick. The seat is a byte and not a peer id because seats are what bodies are
## named by -- see [PlayerState].
##
## The size IS the version: [method unpack_snapshot] refuses any payload that is
## not a header plus a whole number of bodies this wide, so a build that grew a
## field cannot half-read one that did not.
##
## Then u8 tenths of speed boost left and u8 tenths of its multiplier.
const SNAPSHOT_BODY_SIZE: int = 31

## Centimetres to the metre: the unit position and velocity are sent in.
##
## An [code]i16[/code] of centimetres reaches 327 metres either way, against a
## ring 60 metres across and a kill volume well inside that, and rounds to five
## millimetres. A body that somehow leaves the box is clamped to its edge rather
## than wrapped, because a body at the far wall is a wrong a client can see past
## and a body teleported to the opposite one is not.
const QUANT_CENTIMETRE: float = 100.0

## Largest magnitude a quantised metre value can carry, given the unit above.
const QUANT_METRE_LIMIT: float = 327.0

## Steps a full turn of yaw is divided into. A tenth of a milliradian, which is
## finer than a body's facing can be seen to be wrong.
const _YAW_STEPS: int = 1 << 16

## Radians to the step for pitch, which is signed and never leaves a half turn.
const _PITCH_SCALE: float = 10000.0

## Bytes of roster header: u8 phase, u16 scene epoch, u8 seat count.
const ROSTER_HEADER_SIZE: int = 4

## Scene epochs wrap here; 0 is never a live epoch (Quake's serverId).
const EPOCH_MODULUS: int = 1 << 16

## Bytes of the fixed part of a roster seat: u8 index, u8 occupancy, u8 role,
## u8 flags, u32 peer id, u16 standing epoch, u8 name length. The name follows, that many bytes.
const ROSTER_SEAT_FIXED_SIZE: int = 11

## A command's changed mask: which fields follow, against the command before it in the packet.
const _CMD_BUTTONS: int = 1 << 0
const _CMD_MOVE: int = 1 << 1
const _CMD_VIEW: int = 1 << 2
const _CMD_VIEW_TIME: int = 1 << 3
const _MOVE_STEPS: float = 127.0
const _FLAG_ON_FLOOR: int = 1 << 0
## The rest of the snapshot flag byte: what a mirror cannot work out for itself
## because it runs no physics and takes no match decisions.
const _FLAG_IS_FINISHER: int = 1 << 1
const _FLAG_IS_ARMED: int = 1 << 2
# Bit 3 was a single "jumped" flag. It is now the low bit of the counter below,
# which is the same thing plus the ability to survive a dropped snapshot.
const _FLAG_SLIDING: int = 1 << 4
const _FLAG_CROUCHING: int = 1 << 5
## Second snapshot flag byte; the first is full.
const _FLAG2_EMOTING: int = 1 << 0
const _FLAG2_EMOTE_ALT: int = 1 << 1
## Bits 2-3 of the second flag byte: the shove swing counter, a counter for the jump's reason.
const SHOVE_COUNTER_MODULUS: int = 4
const _FLAG2_SHOVE_SHIFT: int = 2
const _BOOST_TENTHS_MAX: int = 255

## Where the jump counter sits in the flag byte: bits 3, 6 and 7.
##
## [b]A counter, not a flag.[/b] A jump is an EDGE and the snapshot channel is
## unreliable at half the simulation rate, so a flag loses the jump whenever its
## snapshot is dropped and merges two jumps that fell in one interval. A
## counter that wraps every eight lets the receiver fire once per increment,
## which is right across a dropped snapshot and right across a double hop, and
## costs no byte -- the bits were already spare.
const JUMP_COUNTER_MODULUS: int = 8
const _JUMP_BIT_POSITIONS: Array[int] = [3, 6, 7]
const _FLAG_SEAT_READY: int = 1 << 0

## Highest [enum MatchRules.RunnerAbility] value the wire carries.
const _MAX_ABILITY: int = 5

## Ceiling on a quantised timer, and on hit points: one byte each.
const _ABILITY_TENTHS_MAX: int = 255
const _HEALTH_MAX: int = 255

## Ticks are unsigned 32-bit on the wire and wrap there.
const TICK_MODULUS: int = 1 << 32

## A u32 acknowledgement of nothing: [member PlayerState.cmd_ack] or a command packet's snap ack of -1.
const NO_ACK: int = 0xFFFFFFFF


# --- Commands: client to authority -------------------------------------------

## [param count] commands, [param commands] oldest first, the newest being sequence
## [param newest_seq]; each delta-coded against the one before (Quake's MSG_WriteDeltaUsercmd).
## Levels, move, absolute view and view time; no edge is sent. [param snap_ack] is -1 for none.
static func pack_commands(
	epoch: int, newest_seq: int, snap_ack: int, commands: Array[MoveIntent], count: int
) -> PackedByteArray:
	var used: int = clampi(mini(count, commands.size()), 1, MAX_COMMANDS)
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u16(epoch % EPOCH_MODULUS)
	buffer.put_u32(newest_seq % TICK_MODULUS)
	buffer.put_u8(used)
	buffer.put_u32(NO_ACK if snap_ack < 0 else snap_ack % TICK_MODULUS)
	var buttons: int = 0
	var move: Vector2i = Vector2i.ZERO
	var view: Vector2i = Vector2i.ZERO
	var view_time: int = 0
	for i: int in used:
		var command: MoveIntent = commands[i]
		var b: int = command.buttons & MoveIntent.BUTTON_MASK
		var m: Vector2i = quantise_move(command.move_direction)
		var v: Vector2i = Vector2i(quantise_turn(command.view_angles.x), quantise_pitch(command.view_angles.y))
		var t: int = _VIEW_TIME_NONE
		if snap_ack >= 0 and is_finite(command.view_time):
			t = clampi(roundi((command.view_time - float(snap_ack)) * VIEW_TIME_STEPS), _VIEW_TIME_NONE + 1, 32767)
		var changed: int = (
			(_CMD_BUTTONS if b != buttons else 0) | (_CMD_MOVE if m != move else 0)
			| (_CMD_VIEW if v != view else 0) | (_CMD_VIEW_TIME if t != view_time else 0)
		)
		buffer.put_u8(changed)
		if (changed & _CMD_BUTTONS) != 0:
			buffer.put_u16(b)
		if (changed & _CMD_MOVE) != 0:
			buffer.put_8(m.x)
			buffer.put_8(m.y)
		if (changed & _CMD_VIEW) != 0:
			buffer.put_u16(v.x)
			buffer.put_16(v.y)
		if (changed & _CMD_VIEW_TIME) != 0:
			buffer.put_16(t)
		buttons = b
		move = m
		view = v
		view_time = t
	return buffer.data_array


## A command packet's header field, or -1 when [param payload] is too short to have one.
static func command_epoch(payload: PackedByteArray) -> int:
	return payload.decode_u16(0) if payload.size() >= COMMAND_HEADER_SIZE else -1


static func command_newest(payload: PackedByteArray) -> int:
	return payload.decode_u32(2) if payload.size() >= COMMAND_HEADER_SIZE else -1


## The packet's snap ack, or -1 for none or a short packet.
static func command_snap_ack(payload: PackedByteArray) -> int:
	if payload.size() < COMMAND_HEADER_SIZE:
		return -1
	var acked: int = payload.decode_u32(7)
	return -1 if acked == NO_ACK else acked


## Decode every command of [param payload] into [param out] (at least [constant MAX_COMMANDS]
## long), oldest first. View times are put on [param snap_tick], the receiver's own tick for the
## packet's snap ack (-1: none). Returns the count, or 0 for a malformed packet, leaving none written.
static func unpack_commands(payload: PackedByteArray, out: Array[MoveIntent], snap_tick: int) -> int:
	if payload.size() < COMMAND_HEADER_SIZE + 1 or out.size() < MAX_COMMANDS:
		return 0
	var count: int = payload.decode_u8(6)
	if count < 1 or count > MAX_COMMANDS:
		return 0
	var at: int = COMMAND_HEADER_SIZE
	var buttons: int = 0
	var move: Vector2i = Vector2i.ZERO
	var view: Vector2i = Vector2i.ZERO
	var view_time: int = 0
	for i: int in count:
		if at >= payload.size():
			return _unwritten(out, i)
		var changed: int = payload.decode_u8(at)
		at += 1
		var need: int = (
			(2 if (changed & _CMD_BUTTONS) != 0 else 0) + (2 if (changed & _CMD_MOVE) != 0 else 0)
			+ (4 if (changed & _CMD_VIEW) != 0 else 0) + (2 if (changed & _CMD_VIEW_TIME) != 0 else 0)
		)
		if (changed & ~0x0F) != 0 or at + need > payload.size():
			return _unwritten(out, i)
		if (changed & _CMD_BUTTONS) != 0:
			buttons = payload.decode_u16(at) & MoveIntent.BUTTON_MASK
			at += 2
		if (changed & _CMD_MOVE) != 0:
			move = Vector2i(payload.decode_s8(at), payload.decode_s8(at + 1))
			at += 2
		if (changed & _CMD_VIEW) != 0:
			view = Vector2i(payload.decode_u16(at), payload.decode_s16(at + 2))
			at += 4
		if (changed & _CMD_VIEW_TIME) != 0:
			view_time = payload.decode_s16(at)
			at += 2
		var command: MoveIntent = out[i]
		command.clear()
		command.buttons = buttons
		command.move_direction = Vector2(move) / _MOVE_STEPS
		command.normalise()
		command.view_angles = Vector2(
			wrapf(float(view.x) / float(_YAW_STEPS) * TAU, -PI, PI), float(view.y) / _PITCH_SCALE
		)
		command.view_absolute = true
		command.view_time = (
			MoveIntent.LIVE_WORLD if snap_tick < 0 or view_time == _VIEW_TIME_NONE
			else maxf(float(snap_tick) + float(view_time) / VIEW_TIME_STEPS, 0.0)
		)
	if at != payload.size():
		return _unwritten(out, count)
	return count


static func _unwritten(out: Array[MoveIntent], written: int) -> int:
	for i: int in written:
		out[i].clear()
	return 0


# --- Snapshot: authority to everyone ------------------------------------------

static func pack_snapshot(snapshot: WorldSnapshot) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(snapshot.tick % TICK_MODULUS)
	buffer.put_u32(snapshot.scene & 0xFFFFFFFF)
	buffer.put_u8(snapshot.count)
	for i: int in snapshot.count:
		var state: PlayerState = snapshot.states[i]
		buffer.put_u8(state.seat_index)
		_put_metres(buffer, state.position)
		_put_metres(buffer, state.velocity)
		buffer.put_u16(quantise_turn(state.yaw))
		buffer.put_16(quantise_pitch(state.pitch))
		buffer.put_u16(quantise_turn(state.view_base))
		var flags: int = _pack_jump_counter(state.jump_counter)
		if state.on_floor:
			flags |= _FLAG_ON_FLOOR
		if state.is_finisher:
			flags |= _FLAG_IS_FINISHER
		if state.is_armed:
			flags |= _FLAG_IS_ARMED
		if state.sliding:
			flags |= _FLAG_SLIDING
		if state.crouching:
			flags |= _FLAG_CROUCHING
		buffer.put_u8(flags)
		buffer.put_u8(
			(_FLAG2_EMOTING if state.emoting else 0)
			| (_FLAG2_EMOTE_ALT if state.emote_alt else 0)
			| (posmod(state.shove_counter, SHOVE_COUNTER_MODULUS) << _FLAG2_SHOVE_SHIFT)
		)
		buffer.put_u8(clampi(state.ability, 0, _MAX_ABILITY))
		buffer.put_u8(clampi(
			int(state.ability_remaining * 10.0), 0, _ABILITY_TENTHS_MAX
		))
		buffer.put_u8(clampi(
			int(state.cooldown_remaining * 10.0), 0, _ABILITY_TENTHS_MAX
		))
		buffer.put_u8(clampi(state.health, 0, _HEALTH_MAX))
		buffer.put_u8(clampi(int(ceilf(state.boost_remaining * 10.0)), 0, _BOOST_TENTHS_MAX))
		buffer.put_u8(clampi(roundi(state.boost_multiplier * 10.0), 0, _BOOST_TENTHS_MAX))
		buffer.put_u32(
			NO_ACK if state.cmd_ack < 0
			else state.cmd_ack % TICK_MODULUS
		)
	return buffer.data_array


## Decode into [param out]. Returns false if [param payload] is not a
## well-formed snapshot, in which case [param out] is left cleared rather than
## half-filled -- a snapshot that describes three of five bodies is worse than
## no snapshot, because the two it omits would be drawn at last tick's position
## as though they had stopped.
static func unpack_snapshot(payload: PackedByteArray, out: WorldSnapshot) -> bool:
	if payload.size() < SNAPSHOT_HEADER_SIZE:
		return false
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = payload
	var tick: int = buffer.get_u32()
	var scene: int = buffer.get_u32()
	var count: int = buffer.get_u8()
	if count > NetTransport.MAX_PLAYERS:
		return false
	if payload.size() != SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_BODY_SIZE:
		return false

	out.clear()
	out.tick = tick
	out.scene = scene
	for _i: int in count:
		var state: PlayerState = out.next_slot()
		var seat_index: int = buffer.get_u8()
		var position: Vector3 = _get_metres(buffer)
		var velocity: Vector3 = _get_metres(buffer)
		var yaw: float = float(buffer.get_u16()) / float(_YAW_STEPS) * TAU
		var pitch: float = float(buffer.get_16()) / _PITCH_SCALE
		var view_base: float = wrapf(float(buffer.get_u16()) / float(_YAW_STEPS) * TAU, -PI, PI)
		var flags: int = buffer.get_u8()
		var flags2: int = buffer.get_u8()
		# An ability byte from a build with more powers than this one is clamped
		# rather than refused: it costs one body's effect, not the whole world's
		# positions.
		var ability: int = mini(buffer.get_u8(), _MAX_ABILITY)
		var ability_tenths: int = buffer.get_u8()
		var cooldown_tenths: int = buffer.get_u8()
		var health: int = buffer.get_u8()
		var boost_tenths: int = buffer.get_u8()
		var boost_scale_tenths: int = buffer.get_u8()
		var acked: int = buffer.get_u32()
		state.seat_index = seat_index
		state.tick = tick
		state.position = position
		state.velocity = velocity
		state.yaw = yaw
		state.pitch = pitch
		state.view_base = view_base
		state.on_floor = (flags & _FLAG_ON_FLOOR) != 0
		state.ability = ability
		state.ability_remaining = float(ability_tenths) * 0.1
		state.cooldown_remaining = float(cooldown_tenths) * 0.1
		state.health = health
		state.cmd_ack = -1 if acked == NO_ACK else acked
		state.is_finisher = (flags & _FLAG_IS_FINISHER) != 0
		state.is_armed = (flags & _FLAG_IS_ARMED) != 0
		state.jump_counter = _unpack_jump_counter(flags)
		state.sliding = (flags & _FLAG_SLIDING) != 0
		state.crouching = (flags & _FLAG_CROUCHING) != 0
		state.emoting = (flags2 & _FLAG2_EMOTING) != 0
		state.emote_alt = (flags2 & _FLAG2_EMOTE_ALT) != 0
		state.shove_counter = (flags2 >> _FLAG2_SHOVE_SHIFT) & (SHOVE_COUNTER_MODULUS - 1)
		state.boost_remaining = float(boost_tenths) * 0.1
		state.boost_multiplier = float(boost_scale_tenths) * 0.1 if boost_tenths > 0 else 1.0
		out.commit()
	return true


# --- Quantisation -------------------------------------------------------------

## Three axes as centimetres in an [code]i16[/code], clamped to the box.
static func _put_metres(buffer: StreamPeerBuffer, value: Vector3) -> void:
	buffer.put_16(quantise_metres(value.x))
	buffer.put_16(quantise_metres(value.y))
	buffer.put_16(quantise_metres(value.z))


static func _get_metres(buffer: StreamPeerBuffer) -> Vector3:
	return Vector3(
		float(buffer.get_16()) / QUANT_CENTIMETRE,
		float(buffer.get_16()) / QUANT_CENTIMETRE,
		float(buffer.get_16()) / QUANT_CENTIMETRE,
	)


## One metre value as centimetres. NaN and infinity become zero rather than a
## clamped extreme: a body at the far wall is a wrong somebody can see past, and
## there is no honest value to round a NaN towards.
static func quantise_metres(value: float) -> int:
	if not is_finite(value):
		return 0
	return clampi(roundi(value * QUANT_CENTIMETRE), -32768, 32767)


## A move as the wire carries it: 1/127ths an axis, so -1, 0 and 1 are exact, and never outside
## the unit circle the decoder clamps to, so the host runs the quantum the client sent.
static func quantise_move(direction: Vector2) -> Vector2i:
	if not direction.is_finite():
		return Vector2i.ZERO
	var scaled: Vector2 = direction.limit_length(1.0) * _MOVE_STEPS
	var steps: Vector2i = Vector2i(roundi(scaled.x), roundi(scaled.y))
	if steps.length_squared() > roundi(_MOVE_STEPS * _MOVE_STEPS):
		steps = Vector2i(int(scaled.x), int(scaled.y))
	return steps


static func quantise_pitch(radians: float) -> int:
	return clampi(roundi(radians * _PITCH_SCALE), -32768, 32767) if is_finite(radians) else 0


## One angle as a fraction of a full turn, in a [code]u16[/code].
static func quantise_turn(radians: float) -> int:
	if not is_finite(radians):
		return 0
	return int(fposmod(radians, TAU) / TAU * float(_YAW_STEPS)) % _YAW_STEPS


static func _pack_jump_counter(counter: int) -> int:
	var value: int = posmod(counter, JUMP_COUNTER_MODULUS)
	var flags: int = 0
	for bit: int in _JUMP_BIT_POSITIONS.size():
		if (value & (1 << bit)) != 0:
			flags |= 1 << _JUMP_BIT_POSITIONS[bit]
	return flags


static func _unpack_jump_counter(flags: int) -> int:
	var value: int = 0
	for bit: int in _JUMP_BIT_POSITIONS.size():
		if (flags & (1 << _JUMP_BIT_POSITIONS[bit])) != 0:
			value |= 1 << bit
	return value


# --- Roster: authority to everyone --------------------------------------------

## Pack the lobby phase and the whole seat table.
##
## The WHOLE table, every time, even to change one seat's ready flag. It is
## about 200 bytes and it is sent when somebody joins, leaves or presses ready
## -- a handful of times a match. Buying a delta encoding with the possibility
## of two machines disagreeing about who is in the game would be a bad trade at
## any price, and this one is free.
static func pack_roster(
	phase: int, seats: Array[LobbySeat], max_name_bytes: int, epoch: int = 0
) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(phase)
	buffer.put_u16(epoch % EPOCH_MODULUS)
	buffer.put_u8(seats.size())
	for seat: LobbySeat in seats:
		var name_bytes: PackedByteArray = sanitise_name(seat.display_name, max_name_bytes).to_utf8_buffer()
		buffer.put_u8(seat.index)
		buffer.put_u8(int(seat.occupancy))
		buffer.put_u8(int(seat.role))
		buffer.put_u8(_FLAG_SEAT_READY if seat.is_ready else 0)
		buffer.put_u32(seat.peer_id)
		buffer.put_u16(seat.standing_epoch % EPOCH_MODULUS)
		buffer.put_u8(name_bytes.size())
		buffer.put_data(name_bytes)
	return buffer.data_array


## Decode into [param out_seats], resizing it to what arrived. Returns the
## phase, or -1 when the payload is malformed, in which case [param out_seats]
## is untouched.
##
## Decoded into a scratch array first and only copied over on success, because
## a client that half-applies a truncated roster ends up showing a lobby that
## never existed and has no way to notice.
static func unpack_roster(
	payload: PackedByteArray, out_seats: Array[LobbySeat], max_name_bytes: int
) -> int:
	if payload.size() < ROSTER_HEADER_SIZE:
		return -1
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = payload
	var phase: int = buffer.get_u8()
	buffer.get_u16()
	var seat_count: int = buffer.get_u8()
	if seat_count > NetTransport.MAX_PLAYERS:
		return -1

	var decoded: Array[LobbySeat] = []
	for _i: int in seat_count:
		if buffer.get_available_bytes() < ROSTER_SEAT_FIXED_SIZE:
			return -1
		var seat: LobbySeat = LobbySeat.new()
		seat.index = buffer.get_u8()
		var occupancy: int = buffer.get_u8()
		var role: int = buffer.get_u8()
		var flags: int = buffer.get_u8()
		seat.peer_id = buffer.get_u32()
		seat.standing_epoch = buffer.get_u16()
		var name_length: int = buffer.get_u8()
		if buffer.get_available_bytes() < name_length:
			return -1
		if seat.index >= seat_count or occupancy > int(LobbySeat.Occupancy.BOT) or role > int(LobbySeat.Role.PRISONER):
			# An index outside the table, or an enum value this build does not
			# have, is a peer talking a format this one does not speak.
			return -1
		seat.occupancy = occupancy as LobbySeat.Occupancy
		seat.role = role as LobbySeat.Role
		seat.is_ready = (flags & _FLAG_SEAT_READY) != 0
		# get_data() hands back [error, bytes] as an untyped Array; the length
		# was checked above, so the read cannot short-count and only the bytes
		# are wanted.
		var name_bytes: PackedByteArray = buffer.get_data(name_length)[1]
		seat.display_name = sanitise_name(name_bytes.get_string_from_utf8(), max_name_bytes)
		decoded.append(seat)

	out_seats.resize(decoded.size())
	for i: int in decoded.size():
		if out_seats[i] == null:
			out_seats[i] = LobbySeat.new()
		out_seats[i].copy_from(decoded[i])
	return phase


## The scene epoch a roster names. Read only after [method unpack_roster] took it.
static func roster_epoch(payload: PackedByteArray) -> int:
	return payload.decode_u16(1)


# --- Gamestate: authority to a late client ------------------------------------

## Ints in the gamestate header: phase, round, seat, finisher, outcome, winner, participants.
const GAMESTATE_HEADER: int = 7
## Ints per participant: flags (running, ghost, shooter), rounds won, turns in the tower.
const GAMESTATE_PARTICIPANT: int = 3
const GAMESTATE_RUNNING: int = 1
const GAMESTATE_GHOST: int = 2
const GAMESTATE_SHOOTER: int = 4
## A ghost still held where it died; clear on a ghost, its respawn has already landed.
const GAMESTATE_HELD: int = 8


## The whole match state a client binding late converges to (Quake's gamestate). Indices are
## participant slots, -1 for none.
static func pack_gamestate(controller: MatchController) -> PackedInt32Array:
	var participants: Array[MatchParticipant] = controller.get_participants()
	var out: PackedInt32Array = PackedInt32Array([
		int(controller.get_phase()), controller.get_round_number(),
		_slot_or_none(controller.get_seat_participant()), _slot_or_none(controller.get_finisher()),
		int(controller.get_outcome()), _slot_or_none(controller.get_match_winner()), participants.size(),
	])
	for p: MatchParticipant in participants:
		var flags: int = (GAMESTATE_RUNNING if p.is_running else 0) | (GAMESTATE_GHOST if p.is_ghost else 0)
		flags |= GAMESTATE_HELD if p.respawn_hold_remaining > 0.0 else 0
		out.append(flags | (GAMESTATE_SHOOTER if p.is_shooter else 0))
		out.append(p.rounds_won)
		out.append(p.turns_in_tower)
	return out


## True when [param state] is a whole gamestate for [param participant_count] participants.
static func is_gamestate(state: PackedInt32Array, participant_count: int) -> bool:
	return (
		state.size() == GAMESTATE_HEADER + participant_count * GAMESTATE_PARTICIPANT
		and state.size() >= GAMESTATE_HEADER and state[6] == participant_count
	)


static func _slot_or_none(p: MatchParticipant) -> int:
	return p.index if p != null else -1


## A display name fit to store, draw and send on: no control characters, no
## surrounding whitespace, and no longer than [param max_bytes] of UTF-8.
##
## Applied on the way out as well as on the way in. Trusting one's own UI to
## have validated is how a name that was fine in the text field arrives as
## something else after a copy-paste, and the host is the machine that has to
## live with it.
static func sanitise_name(raw: String, max_bytes: int) -> String:
	var cleaned: String = ""
	for index: int in raw.length():
		var code: int = raw.unicode_at(index)
		# C0 and C1 control ranges, plus DEL. Newlines and escape sequences in
		# a name are how a lobby list becomes a place to draw things nobody
		# typed.
		if code < 0x20 or (code >= 0x7F and code <= 0x9F):
			continue
		cleaned += String.chr(code)
	cleaned = cleaned.strip_edges()

	# Truncate by CHARACTER and measure in BYTES, so a name of emoji cannot be
	# cut through the middle of a code point and arrive as a replacement glyph.
	while cleaned.to_utf8_buffer().size() > max_bytes and cleaned.length() > 0:
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	return cleaned


# --- Ordering -----------------------------------------------------------------

## True when [param candidate] is newer than [param reference], allowing for
## the tick wrapping at [constant TICK_MODULUS].
##
## Straight [code]>[/code] would treat the single wrap in a two-year session as
## every subsequent packet being ancient. The comparison is the standard
## sequence-number one: the halfway point of the space decides which side of
## the wrap a value is on.
static func is_newer_tick(candidate: int, reference: int) -> bool:
	var difference: int = (candidate - reference + TICK_MODULUS) % TICK_MODULUS
	return difference != 0 and difference < (TICK_MODULUS >> 1)


## Ticks from [param earlier] to [param later], across the wrap. Negative when
## [param later] is in fact the earlier of the two.
##
## What interpolation needs: the gap between the two snapshots it is sliding
## between, expressed so that a wrap does not turn a 2 tick gap into four
## billion.
static func tick_delta(earlier: int, later: int) -> int:
	var difference: int = (later - earlier + TICK_MODULUS) % TICK_MODULUS
	if difference >= (TICK_MODULUS >> 1):
		return difference - TICK_MODULUS
	return difference


# --- Match rules --------------------------------------------------------------

## Exported scalar fields of [MatchRules] (int, float, bool, String,
## StringName). Resource-typed exports stay local: both builds ship them.
static func rules_field_names(rules: MatchRules) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in rules.get_property_list():
		var usage: int = int(entry.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var kind: int = int(entry.get("type", TYPE_NIL))
		if kind in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME]:
			names.append(String(entry.get("name", "")))
	return names


## [PackedFloat32Array] exports of [MatchRules], which [method rules_field_names] never picks up
## on its own, so they are packed here by name.
const _PACKED_RULES_FIELDS: Array[String] = ["reload_seconds_by_turn", "sniper_by_visit"]

## Every scalar export of [param rules] as bytes, plus the [constant _PACKED_RULES_FIELDS].
## Reliable-channel sized, not per-tick sized.
static func pack_rules(rules: MatchRules) -> PackedByteArray:
	var fields: Dictionary = {}
	for field: String in rules_field_names(rules):
		var value: Variant = rules.get(field)
		fields[field] = String(value) if typeof(value) == TYPE_STRING_NAME else value
	for field: String in _PACKED_RULES_FIELDS:
		fields[field] = rules.get(field)
	return var_to_bytes(fields)


## Decode [method pack_rules] output onto [param out]. Unknown or mistyped
## fields are dropped; false when the payload is not a rules dictionary.
static func unpack_rules(payload: PackedByteArray, out: MatchRules) -> bool:
	var decoded: Variant = bytes_to_var(payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		return false
	var fields: Dictionary = decoded
	for field: String in rules_field_names(out):
		if not fields.has(field):
			continue
		var current: Variant = out.get(field)
		var value: Variant = fields[field]
		match typeof(current):
			TYPE_INT:
				if typeof(value) == TYPE_INT:
					out.set(field, value)
			TYPE_FLOAT:
				if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)):
					out.set(field, float(value))
			TYPE_BOOL:
				if typeof(value) == TYPE_BOOL:
					out.set(field, value)
			TYPE_STRING:
				if typeof(value) == TYPE_STRING:
					out.set(field, value)
			TYPE_STRING_NAME:
				if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
					out.set(field, StringName(String(value)))
	for field: String in _PACKED_RULES_FIELDS:
		var raw: Variant = fields.get(field)
		if typeof(raw) != TYPE_PACKED_FLOAT32_ARRAY:
			continue
		var values: PackedFloat32Array = raw
		var all_finite: bool = true
		for value: float in values:
			if not is_finite(value):
				all_finite = false
				break
		if all_finite:
			out.set(field, values)
	return true


## Copy every scalar export from one rules object onto another, plus the
## [constant _PACKED_RULES_FIELDS].
static func copy_rules(from: MatchRules, to: MatchRules) -> void:
	if from == null or to == null or from == to:
		return
	for field: String in rules_field_names(from):
		to.set(field, from.get(field))
	for field: String in _PACKED_RULES_FIELDS:
		to.set(field, from.get(field))


# --- Decoy: authority to everyone ---------------------------------------------

## Wire version of the decoy transform, in its own byte.
##
## The one message added after the rest of the format was first written, and
## the only one a build can meet without knowing whether it speaks it: it
## arrives on a channel of its own, from a host that may be older than the
## client reading it. A wrong version is dropped rather than decoded.
const DECOY_VERSION: int = 2

## Bytes in a packed decoy transform: u8 version, u8 seat and epoch, 3 i16 of
## position and a u16 yaw. Ten, and it is sized against the TICK rather than the
## snapshot: the hologram streams at the simulation rate because it is a body
## the tower is shooting at, so it is the one message whose size is multiplied
## by sixty.
const DECOY_MOVE_SIZE: int = 10

## Spawns before the epoch wraps. Five bits, beside the three a seat needs: it
## only has to outlive a stale packet, not a match.
const DECOY_EPOCH_MODULUS: int = 32

const _DECOY_SEAT_BITS: int = 3
const _DECOY_SEAT_MASK: int = (1 << _DECOY_SEAT_BITS) - 1

## One hologram's transform. [param epoch] names the spawn it belongs to, so a
## packet overtaken by its own despawn can be told from a live one.
static func pack_decoy_move(
	seat_index: int, epoch: int, position: Vector3, yaw: float
) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(DECOY_VERSION)
	buffer.put_u8(
		(seat_index & _DECOY_SEAT_MASK)
		| ((epoch % DECOY_EPOCH_MODULUS) << _DECOY_SEAT_BITS)
	)
	_put_metres(buffer, position)
	buffer.put_u16(quantise_turn(yaw))
	return buffer.data_array


## Decode into [param out], filling its seat, position and yaw. Returns the
## epoch, or -1 when the payload is not a decoy transform this build speaks.
static func unpack_decoy_move(payload: PackedByteArray, out: PlayerState) -> int:
	if payload.size() != DECOY_MOVE_SIZE:
		return -1
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = payload
	if buffer.get_u8() != DECOY_VERSION:
		return -1
	var tag: int = buffer.get_u8()
	var position: Vector3 = _get_metres(buffer)
	var yaw: float = float(buffer.get_u16()) / float(_YAW_STEPS) * TAU
	out.seat_index = tag & _DECOY_SEAT_MASK
	out.position = position
	out.yaw = yaw
	return tag >> _DECOY_SEAT_BITS
