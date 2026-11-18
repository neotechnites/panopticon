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
## [b]Stability.[/b] One file to read when the format has to change; [constant SNAPSHOT_VERSION]
## goes into the build fingerprint, so two builds that disagree are refused at join.
##
## Decoding writes into a caller-owned object and returns a [bool], rather than
## allocating and returning a new one, so the per-tick path allocates nothing
## but the [PackedByteArray] itself.
##
## The snapshot is coded against the last world the receiver acknowledged (Quake 3, Gaffer's
## [i]Snapshot Compression[/i]): only what changed is sent, and with no baseline the whole world is.

## Bytes of command packet header: u16 epoch, u32 newest sequence, u8 command count (bit 7: a snap ack
## follows), u32 snap ack (the newest snapshot tick the sender decoded).
const COMMAND_HEADER_SIZE: int = 11
const _COUNT_HAS_SNAP_ACK: int = 0x80

## Most commands one packet may carry: every unacknowledged one, up to about half a second.
const MAX_COMMANDS: int = 32

## What a command's view time is relative to: 64ths of a tick from the packet's snap ack.
const VIEW_TIME_STEPS: float = 64.0
const _VIEW_TIME_NONE: int = -32768

## Bytes of snapshot header: u16 epoch, u32 tick, u32 baseline tick, u32 cmd ack, i8 cmd buffer,
## u8 flags, u8 event count (DESIGN 3.4).
const SNAPSHOT_HEADER_SIZE: int = 17
## Bumped whenever the snapshot layout changes: two builds must agree on it (the fingerprint).
const SNAPSHOT_VERSION: int = 2
## No snapshot reaches this, inside ENet's and SDR's MTU: a fragment lost is the whole packet lost.
const MAX_SNAPSHOT_BYTES: int = 1200
## Host ticks a second: the unit of every tick and end tick on the wire.
const TICK_RATE: int = 60

const _SNAP_FULL: int = 1 << 0
const _SNAP_CMD_ACK: int = 1 << 1
const _SNAP_MATCH: int = 1 << 2
const _SNAP_BODIES: int = 1 << 3
const _SNAP_OWNER: int = 1 << 4
const _SNAP_PROPS: int = 1 << 5

## A body record's fields, one bit each in its u16 mask.
const BODY_POSITION: int = 1 << 0
const BODY_VELOCITY: int = 1 << 1
const BODY_YAW: int = 1 << 2
const BODY_PITCH: int = 1 << 3
const BODY_VIEW_BASE: int = 1 << 4
const BODY_FLAGS: int = 1 << 5
const BODY_HEALTH: int = 1 << 6
const BODY_POWER: int = 1 << 7
const BODY_ANCHOR: int = 1 << 8
const BODY_BOOST: int = 1 << 9
const BODY_WEAPON: int = 1 << 10
const _BODY_FIELDS: int = (1 << 11) - 1
const _BODY_BYTES: PackedInt32Array = [6, 6, 2, 2, 2, 2, 1, 5, 8, 3, 4]

## Floats per group of the owner block, each group with its own u8 mask.
const _OWNER_GROUP: int = 8
const _OWNER_SHIFT: int = 3

## Bytes of an event's header: u16 id, u8 type, u8 age in ticks behind the snapshot.
const EVENT_HEADER_SIZE: int = 4
## Payload bytes per [enum NetEvents.Type], fixed: the size is the version.
const EVENT_PAYLOAD: PackedInt32Array = [0, 37, 17, 13, 13, 3, 13]

## Most bytes a match record or a prop record may be.
const MAX_RECORD_BYTES: int = 255

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
## A body's flag word: six poses, then the jump (3 b), shove (2 b) and placement (3 b) counters.
const _FLAG_ON_FLOOR: int = 1 << 0
const _FLAG_SLIDING: int = 1 << 1
const _FLAG_CROUCHING: int = 1 << 2
const _FLAG_EMOTING: int = 1 << 3
const _FLAG_EMOTE_ALT: int = 1 << 4
const _FLAG_IS_ARMED: int = 1 << 5
const _FLAG_IS_FINISHER: int = 1 << 6
const _JUMP_SHIFT: int = 7
const _SHOVE_SHIFT: int = 10
const _PLACED_SHIFT: int = 12
const JUMP_COUNTER_MODULUS: int = 8
const SHOVE_COUNTER_MODULUS: int = 4
const PLACED_COUNTER_MODULUS: int = 8
## The power byte: which power (3 b), then whether its hologram is out and whether it has an anchor.
const _POWER_DECOY: int = 1 << 3
const _POWER_ANCHOR: int = 1 << 4
const _BOOST_TENTHS_MAX: int = 255
const _FLAG_SEAT_READY: int = 1 << 0

## Highest [enum MatchRules.RunnerAbility] value the wire carries.
const _MAX_ABILITY: int = 5

const _HEALTH_MAX: int = 255

## Ticks are unsigned 32-bit on the wire and wrap there.
const TICK_MODULUS: int = 1 << 32


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
	buffer.put_u8(used | (_COUNT_HAS_SNAP_ACK if snap_ack >= 0 else 0))
	buffer.put_u32(0 if snap_ack < 0 else snap_ack % TICK_MODULUS)
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


## [param command] made exactly what the host will decode and run: move and view at the wire's quantum,
## absolute, local-only keys dropped. A client predicts with this, so its replay is the host's run.
static func quantise_command(command: MoveIntent) -> void:
	command.move_direction = Vector2(quantise_move(command.move_direction)) / _MOVE_STEPS
	command.normalise()
	command.view_angles = Vector2(
		turn_of(quantise_turn(command.view_angles.x)), float(quantise_pitch(command.view_angles.y)) / _PITCH_SCALE
	)
	command.view_absolute = true
	command.look_delta = Vector2.ZERO
	command.buttons &= MoveIntent.BUTTON_MASK
	command.turbo_held = false
	command.godmode = false


## A command packet's header field, or -1 when [param payload] is too short to have one.
static func command_epoch(payload: PackedByteArray) -> int:
	return payload.decode_u16(0) if payload.size() >= COMMAND_HEADER_SIZE else -1


static func command_newest(payload: PackedByteArray) -> int:
	return payload.decode_u32(2) if payload.size() >= COMMAND_HEADER_SIZE else -1


## The packet's snap ack, or -1 for none or a short packet.
static func command_snap_ack(payload: PackedByteArray) -> int:
	if payload.size() < COMMAND_HEADER_SIZE or (payload.decode_u8(6) & _COUNT_HAS_SNAP_ACK) == 0:
		return -1
	return payload.decode_u32(7)


## Decode every command of [param payload] into [param out] (at least [constant MAX_COMMANDS]
## long), oldest first. View times are put on [param snap_tick], the receiver's own tick for the
## packet's snap ack (-1: none). Returns the count, or 0 for a malformed packet, leaving none written.
static func unpack_commands(payload: PackedByteArray, out: Array[MoveIntent], snap_tick: int) -> int:
	if payload.size() < COMMAND_HEADER_SIZE + 1 or out.size() < MAX_COMMANDS:
		return 0
	var count: int = payload.decode_u8(6) & ~_COUNT_HAS_SNAP_ACK
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
		command.view_angles = Vector2(turn_of(view.x), float(view.y) / _PITCH_SCALE)
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


# --- Snapshot: authority to one client ----------------------------------------

## What a snapshot says besides the world: read by [method unpack_snapshot], and written back by
## [method pack_snapshot] with how many of the offered events fitted.
class SnapshotInfo:
	extends RefCounted
	var epoch: int = 0
	var tick: int = 0
	## The tick this was coded against, or -1 for a full update (against the defaults).
	var baseline: int = -1
	## The newest of the receiver's commands the host had run, or -1.
	var cmd_ack: int = -1
	var cmd_buffer: int = 0
	## The seat the owner block is for, or -1 when there is none.
	var owner_seat: int = -1
	var event_count: int = 0


## [param world] against [param base] (null: full) for the client in [param owner_seat] (-1: none), with
## the [param events] that fit; [param info] gives cmd ack and buffer, gets back the event count.
static func pack_snapshot(
	world: WorldSnapshot, base: WorldSnapshot, owner_seat: int, events: Array[NetEvents.Entry], info: SnapshotInfo
) -> PackedByteArray:
	var full: bool = base == null
	var from: WorldSnapshot = _defaults() if full else base
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u16(world.epoch % EPOCH_MODULUS)
	buffer.put_u32(world.tick % TICK_MODULUS)
	buffer.put_u32(0 if full else from.tick % TICK_MODULUS)
	buffer.put_u32(maxi(info.cmd_ack, 0) % TICK_MODULUS)
	buffer.put_8(clampi(info.cmd_buffer, -128, 127))
	buffer.put_u8(0)
	buffer.put_u8(0)
	var flags: int = (_SNAP_FULL if full else 0) | (_SNAP_CMD_ACK if info.cmd_ack >= 0 else 0)
	if world.match_record != from.match_record:
		flags |= _SNAP_MATCH
		buffer.put_u8(world.match_record.size())
		buffer.put_data(world.match_record)
	var changed: int = 0
	for seat: int in NetTransport.MAX_PLAYERS:
		if world.has_seat(seat) and (not from.has_seat(seat) or body_changes(world.states[seat], from.states[seat]) != 0):
			changed |= 1 << seat
	if changed != 0 or world.present != from.present:
		flags |= _SNAP_BODIES
		buffer.put_u8(world.present)
		buffer.put_u8(changed)
		for seat: int in NetTransport.MAX_PLAYERS:
			if (changed & (1 << seat)) != 0:
				var was: PlayerState = from.states[seat] if from.has_seat(seat) else _default_body()
				_put_body(buffer, world.states[seat], was, world.tick)
	if owner_seat >= 0 and owner_seat < NetTransport.MAX_PLAYERS and world.has_seat(owner_seat):
		if full or not world.owners[owner_seat].equals(from.owners[owner_seat]):
			flags |= _SNAP_OWNER
			buffer.put_u8(owner_seat)
			_put_owner(buffer, world.owners[owner_seat].values, from.owners[owner_seat].values)
	var props: PackedInt32Array = PackedInt32Array()
	for i: int in world.prop_ids.size():
		if world.prop_records[i] != from.find_prop(world.prop_ids[i]):
			props.append(i)
	if not props.is_empty():
		flags |= _SNAP_PROPS
		buffer.put_u8(props.size())
		for i: int in props:
			buffer.put_u16(world.prop_ids[i] & 0xFFFF)
			buffer.put_u8(world.prop_records[i].size())
			buffer.put_data(world.prop_records[i])
	var count: int = 0
	for entry: NetEvents.Entry in events:
		if count >= 255 or buffer.get_size() + EVENT_HEADER_SIZE + entry.payload.size() > MAX_SNAPSHOT_BYTES - 1:
			break
		buffer.put_u16(entry.seq & 0xFFFF)
		buffer.put_u8(int(entry.type))
		buffer.put_u8(clampi(tick_delta(entry.tick, world.tick), 0, 255))
		buffer.put_data(entry.payload)
		count += 1
	info.event_count = count
	var bytes: PackedByteArray = buffer.data_array
	bytes[15] = flags
	bytes[16] = count
	if bytes.size() >= MAX_SNAPSHOT_BYTES:
		push_error("NetCodec: a snapshot reached %d bytes; it would fragment." % bytes.size())
	return bytes


## A snapshot's epoch, tick and baseline tick (-1: a full update), or -1 each for a short payload.
static func snapshot_epoch(payload: PackedByteArray) -> int:
	return payload.decode_u16(0) if payload.size() >= SNAPSHOT_HEADER_SIZE else -1


static func snapshot_tick(payload: PackedByteArray) -> int:
	return payload.decode_u32(2) if payload.size() >= SNAPSHOT_HEADER_SIZE else -1


static func snapshot_baseline(payload: PackedByteArray) -> int:
	if payload.size() < SNAPSHOT_HEADER_SIZE or (payload.decode_u8(15) & _SNAP_FULL) != 0:
		return -1
	return payload.decode_u32(6)


## Decode [param payload] onto [param base] (null: full; else the tick it names) into [param out],
## [param info] and [param events]. False for a malformed packet or wrong baseline.
static func unpack_snapshot(
	payload: PackedByteArray, base: WorldSnapshot, out: WorldSnapshot, info: SnapshotInfo, events: Array[NetEvents.Entry]
) -> bool:
	if payload.size() < SNAPSHOT_HEADER_SIZE:
		return false
	var flags: int = payload.decode_u8(15)
	var full: bool = (flags & _SNAP_FULL) != 0
	if (flags & ~0x3F) != 0 or full != (base == null):
		return false
	if not full and base.tick % TICK_MODULUS != payload.decode_u32(6):
		return false
	info.epoch = payload.decode_u16(0)
	info.tick = payload.decode_u32(2)
	info.baseline = -1 if full else payload.decode_u32(6)
	info.cmd_ack = payload.decode_u32(10) if (flags & _SNAP_CMD_ACK) != 0 else -1
	info.cmd_buffer = payload.decode_s8(14)
	info.event_count = payload.decode_u8(16)
	info.owner_seat = -1
	out.copy_from(_defaults() if full else base)
	out.tick = info.tick
	out.epoch = info.epoch
	var at: int = SNAPSHOT_HEADER_SIZE
	if (flags & _SNAP_MATCH) != 0:
		if at >= payload.size() or at + 1 + payload.decode_u8(at) > payload.size():
			return false
		out.match_record = payload.slice(at + 1, at + 1 + payload.decode_u8(at))
		at += 1 + out.match_record.size()
	if (flags & _SNAP_BODIES) != 0:
		if at + 2 > payload.size():
			return false
		var was_present: int = out.present
		out.present = payload.decode_u8(at)
		var changed: int = payload.decode_u8(at + 1)
		at += 2
		if (changed & ~out.present) != 0:
			return false
		for seat: int in NetTransport.MAX_PLAYERS:
			var state: PlayerState = out.states[seat]
			var bit: int = 1 << seat
			if (out.present & bit) == 0 or (was_present & bit) == 0:
				# Gone, or new: a new body is coded against the defaults, so it must be in the changed set.
				state.clear()
				if (out.present & bit) != 0 and (changed & bit) == 0:
					return false
			state.seat_index = seat
			state.tick = info.tick
			if (changed & bit) != 0:
				at = _get_body(payload, at, state, info.tick)
				if at < 0:
					return false
	else:
		for seat: int in NetTransport.MAX_PLAYERS:
			out.states[seat].tick = info.tick
	if (flags & _SNAP_OWNER) != 0:
		if at + 1 > payload.size() or payload.decode_u8(at) >= NetTransport.MAX_PLAYERS:
			return false
		info.owner_seat = payload.decode_u8(at)
		at = _get_owner(payload, at + 1, out.owners[info.owner_seat].values)
		if at < 0:
			return false
		out.owner_valid |= 1 << info.owner_seat
	if (flags & _SNAP_PROPS) != 0:
		if at + 1 > payload.size():
			return false
		var count: int = payload.decode_u8(at)
		at += 1
		for _i: int in count:
			if at + 3 > payload.size() or at + 3 + payload.decode_u8(at + 2) > payload.size():
				return false
			var length: int = payload.decode_u8(at + 2)
			out.set_prop(payload.decode_u16(at), payload.slice(at + 3, at + 3 + length))
			at += 3 + length
	while events.size() < info.event_count:
		events.append(NetEvents.Entry.new())
	for i: int in info.event_count:
		if at + EVENT_HEADER_SIZE > payload.size():
			return false
		var type: int = payload.decode_u8(at + 2)
		if type <= 0 or type >= EVENT_PAYLOAD.size():
			return false
		var size: int = EVENT_PAYLOAD[type]
		if at + EVENT_HEADER_SIZE + size > payload.size():
			return false
		var entry: NetEvents.Entry = events[i]
		entry.seq = payload.decode_u16(at)
		entry.type = type as NetEvents.Type
		entry.tick = (info.tick - payload.decode_u8(at + 3) + TICK_MODULUS) % TICK_MODULUS
		entry.payload = payload.slice(at + EVENT_HEADER_SIZE, at + EVENT_HEADER_SIZE + size)
		at += EVENT_HEADER_SIZE + size
	return at == payload.size()


## Which of [param a]'s fields differ from [param b]'s, as a body mask.
static func body_changes(a: PlayerState, b: PlayerState) -> int:
	var mask: int = 0
	if a.position != b.position:
		mask |= BODY_POSITION
	if a.velocity != b.velocity:
		mask |= BODY_VELOCITY
	if a.yaw != b.yaw:
		mask |= BODY_YAW
	if a.pitch != b.pitch:
		mask |= BODY_PITCH
	if a.view_base != b.view_base:
		mask |= BODY_VIEW_BASE
	if _body_flags(a) != _body_flags(b):
		mask |= BODY_FLAGS
	if a.health != b.health:
		mask |= BODY_HEALTH
	if (
		a.ability != b.ability or a.decoy_alive != b.decoy_alive or a.has_anchor != b.has_anchor
		or a.ability_end_tick != b.ability_end_tick or a.cooldown_end_tick != b.cooldown_end_tick
	):
		mask |= BODY_POWER
	if a.has_anchor and (a.anchor_position != b.anchor_position or a.anchor_yaw != b.anchor_yaw or not b.has_anchor):
		mask |= BODY_ANCHOR
	if a.boost_multiplier != b.boost_multiplier or a.boost_end_tick != b.boost_end_tick:
		mask |= BODY_BOOST
	if (
		a.weapon_state != b.weapon_state or a.weapon_scoped != b.weapon_scoped
		or a.weapon_end_tick != b.weapon_end_tick or a.weapon_charge != b.weapon_charge
	):
		mask |= BODY_WEAPON
	return mask


## Snap [param state] to wire precision in place, its end ticks resolved on [param tick]: what the
## host keeps as a baseline is exactly what a client decodes.
static func quantise_state(state: PlayerState, tick: int) -> void:
	state.tick = tick
	state.position = quantised_metres(state.position)
	state.velocity = quantised_metres(state.velocity)
	state.yaw = turn_of(quantise_turn(state.yaw))
	state.pitch = float(quantise_pitch(state.pitch)) / _PITCH_SCALE
	state.view_base = turn_of(quantise_turn(state.view_base))
	state.jump_counter = posmod(state.jump_counter, JUMP_COUNTER_MODULUS)
	state.shove_counter = posmod(state.shove_counter, SHOVE_COUNTER_MODULUS)
	state.placed_counter = posmod(state.placed_counter, PLACED_COUNTER_MODULUS)
	state.health = clampi(state.health, 0, _HEALTH_MAX)
	state.ability = clampi(state.ability, 0, _MAX_ABILITY)
	state.ability_end_tick = _wire_end(state.ability_end_tick, tick)
	state.cooldown_end_tick = _wire_end(state.cooldown_end_tick, tick)
	if state.has_anchor:
		state.anchor_position = quantised_metres(state.anchor_position)
		state.anchor_yaw = turn_of(quantise_turn(state.anchor_yaw))
	else:
		state.anchor_position = Vector3.ZERO
		state.anchor_yaw = 0.0
	state.boost_end_tick = _wire_end(state.boost_end_tick, tick)
	state.boost_multiplier = (
		float(clampi(roundi(state.boost_multiplier * 10.0), 0, _BOOST_TENTHS_MAX)) * 0.1
		if state.boost_end_tick != 0 and is_finite(state.boost_multiplier) else 1.0
	)
	state.weapon_state = clampi(state.weapon_state, 0, 3)
	state.weapon_end_tick = _wire_end(state.weapon_end_tick, tick)
	state.weapon_charge = clampi(state.weapon_charge, 0, 255)


## The end tick [param seconds] after [param tick], as the wire can name it; 0 (none) when not in the future.
static func end_tick(tick: int, seconds: float) -> int:
	if not is_finite(seconds):
		return 0
	var ticks: int = roundi(seconds * float(TICK_RATE))
	return 0 if ticks <= 0 else _wire_end((tick + ticks) % TICK_MODULUS, tick)


## An end tick the wire can carry at [param tick]: 0 when none or past, within a half u16 ahead, never
## low 16 bits of 0 (which the wire reads as none).
static func _wire_end(end: int, tick: int) -> int:
	if end == 0:
		return 0
	var ahead: int = tick_delta(tick, end)
	if ahead <= 0:
		return 0
	end = (tick + mini(ahead, 32767)) % TICK_MODULUS
	return end + 1 if (end & 0xFFFF) == 0 else end


static func _put_end(buffer: StreamPeerBuffer, end: int) -> void:
	buffer.put_u16(end & 0xFFFF)


## A u16 end tick resolved to the instance nearest [param tick]; 0 stays none.
static func _resolve_end(wire: int, tick: int) -> int:
	if wire == 0:
		return 0
	var ahead: int = (wire - (tick & 0xFFFF) + 0x10000) % 0x10000
	if ahead >= 0x8000:
		ahead -= 0x10000
	return (tick + ahead + TICK_MODULUS) % TICK_MODULUS


static func _body_flags(state: PlayerState) -> int:
	return (
		(_FLAG_ON_FLOOR if state.on_floor else 0) | (_FLAG_SLIDING if state.sliding else 0)
		| (_FLAG_CROUCHING if state.crouching else 0) | (_FLAG_EMOTING if state.emoting else 0)
		| (_FLAG_EMOTE_ALT if state.emote_alt else 0) | (_FLAG_IS_ARMED if state.is_armed else 0)
		| (_FLAG_IS_FINISHER if state.is_finisher else 0)
		| (posmod(state.jump_counter, JUMP_COUNTER_MODULUS) << _JUMP_SHIFT)
		| (posmod(state.shove_counter, SHOVE_COUNTER_MODULUS) << _SHOVE_SHIFT)
		| (posmod(state.placed_counter, PLACED_COUNTER_MODULUS) << _PLACED_SHIFT)
	)


static func _put_body(buffer: StreamPeerBuffer, state: PlayerState, base: PlayerState, tick: int) -> void:
	var mask: int = body_changes(state, base)
	buffer.put_u16(mask)
	if (mask & BODY_POSITION) != 0:
		_put_metres(buffer, state.position)
	if (mask & BODY_VELOCITY) != 0:
		_put_metres(buffer, state.velocity)
	if (mask & BODY_YAW) != 0:
		buffer.put_u16(quantise_turn(state.yaw))
	if (mask & BODY_PITCH) != 0:
		buffer.put_16(quantise_pitch(state.pitch))
	if (mask & BODY_VIEW_BASE) != 0:
		buffer.put_u16(quantise_turn(state.view_base))
	if (mask & BODY_FLAGS) != 0:
		buffer.put_u16(_body_flags(state))
	if (mask & BODY_HEALTH) != 0:
		buffer.put_u8(state.health)
	if (mask & BODY_POWER) != 0:
		buffer.put_u8(state.ability | (_POWER_DECOY if state.decoy_alive else 0) | (_POWER_ANCHOR if state.has_anchor else 0))
		_put_end(buffer, state.ability_end_tick)
		_put_end(buffer, state.cooldown_end_tick)
	if (mask & BODY_ANCHOR) != 0:
		_put_metres(buffer, state.anchor_position)
		buffer.put_u16(quantise_turn(state.anchor_yaw))
	if (mask & BODY_BOOST) != 0:
		buffer.put_u8(roundi(state.boost_multiplier * 10.0))
		_put_end(buffer, state.boost_end_tick)
	if (mask & BODY_WEAPON) != 0:
		buffer.put_u8(state.weapon_state | (4 if state.weapon_scoped else 0))
		_put_end(buffer, state.weapon_end_tick)
		buffer.put_u8(state.weapon_charge)


## Read one body's changed fields onto [param state] at [param at]; the offset after, or -1.
static func _get_body(payload: PackedByteArray, at: int, state: PlayerState, tick: int) -> int:
	if at + 2 > payload.size():
		return -1
	var mask: int = payload.decode_u16(at)
	at += 2
	if (mask & ~_BODY_FIELDS) != 0:
		return -1
	var need: int = 0
	for bit: int in _BODY_BYTES.size():
		if (mask & (1 << bit)) != 0:
			need += _BODY_BYTES[bit]
	if at + need > payload.size():
		return -1
	if (mask & BODY_POSITION) != 0:
		state.position = metres_at(payload, at)
		at += 6
	if (mask & BODY_VELOCITY) != 0:
		state.velocity = metres_at(payload, at)
		at += 6
	if (mask & BODY_YAW) != 0:
		state.yaw = turn_of(payload.decode_u16(at))
		at += 2
	if (mask & BODY_PITCH) != 0:
		state.pitch = float(payload.decode_s16(at)) / _PITCH_SCALE
		at += 2
	if (mask & BODY_VIEW_BASE) != 0:
		state.view_base = turn_of(payload.decode_u16(at))
		at += 2
	if (mask & BODY_FLAGS) != 0:
		var flags: int = payload.decode_u16(at)
		at += 2
		state.on_floor = (flags & _FLAG_ON_FLOOR) != 0
		state.sliding = (flags & _FLAG_SLIDING) != 0
		state.crouching = (flags & _FLAG_CROUCHING) != 0
		state.emoting = (flags & _FLAG_EMOTING) != 0
		state.emote_alt = (flags & _FLAG_EMOTE_ALT) != 0
		state.is_armed = (flags & _FLAG_IS_ARMED) != 0
		state.is_finisher = (flags & _FLAG_IS_FINISHER) != 0
		state.jump_counter = (flags >> _JUMP_SHIFT) & (JUMP_COUNTER_MODULUS - 1)
		state.shove_counter = (flags >> _SHOVE_SHIFT) & (SHOVE_COUNTER_MODULUS - 1)
		state.placed_counter = (flags >> _PLACED_SHIFT) & (PLACED_COUNTER_MODULUS - 1)
	if (mask & BODY_HEALTH) != 0:
		state.health = payload.decode_u8(at)
		at += 1
	if (mask & BODY_POWER) != 0:
		var power: int = payload.decode_u8(at)
		# A power from a build with more of them than this one is drawn as none rather than refused.
		state.ability = power & 7 if (power & 7) <= _MAX_ABILITY else 0
		state.decoy_alive = (power & _POWER_DECOY) != 0
		state.has_anchor = (power & _POWER_ANCHOR) != 0
		state.ability_end_tick = _resolve_end(payload.decode_u16(at + 1), tick)
		state.cooldown_end_tick = _resolve_end(payload.decode_u16(at + 3), tick)
		at += 5
		if not state.has_anchor:
			state.anchor_position = Vector3.ZERO
			state.anchor_yaw = 0.0
	if (mask & BODY_ANCHOR) != 0:
		state.anchor_position = metres_at(payload, at)
		state.anchor_yaw = turn_of(payload.decode_u16(at + 6))
		at += 8
	if (mask & BODY_BOOST) != 0:
		state.boost_end_tick = _resolve_end(payload.decode_u16(at + 1), tick)
		state.boost_multiplier = float(payload.decode_u8(at)) * 0.1 if state.boost_end_tick != 0 else 1.0
		at += 3
	if (mask & BODY_WEAPON) != 0:
		var weapon: int = payload.decode_u8(at)
		state.weapon_state = weapon & 3
		state.weapon_scoped = (weapon & 4) != 0
		state.weapon_end_tick = _resolve_end(payload.decode_u16(at + 1), tick)
		state.weapon_charge = payload.decode_u8(at + 3)
		at += 4
	return at


## The owner block: a u8 mask of groups of [constant _OWNER_GROUP] floats, a u8 mask per group sent,
## then each changed float as its exact f32.
static func _put_owner(buffer: StreamPeerBuffer, values: PackedFloat32Array, base: PackedFloat32Array) -> void:
	var group_count: int = (values.size() + _OWNER_GROUP - 1) >> _OWNER_SHIFT
	var groups: int = 0
	for i: int in values.size():
		if values[i] != base[i]:
			groups |= 1 << (i >> _OWNER_SHIFT)
	buffer.put_u8(groups)
	for group: int in group_count:
		if (groups & (1 << group)) == 0:
			continue
		var mask: int = 0
		for bit: int in _OWNER_GROUP:
			var index: int = (group << _OWNER_SHIFT) + bit
			if index < values.size() and values[index] != base[index]:
				mask |= 1 << bit
		buffer.put_u8(mask)
		for bit: int in _OWNER_GROUP:
			if (mask & (1 << bit)) != 0:
				buffer.put_float(values[(group << _OWNER_SHIFT) + bit])


static func _get_owner(payload: PackedByteArray, at: int, values: PackedFloat32Array) -> int:
	var group_count: int = (values.size() + _OWNER_GROUP - 1) >> _OWNER_SHIFT
	if at + 1 > payload.size():
		return -1
	var groups: int = payload.decode_u8(at)
	at += 1
	if groups >= (1 << group_count):
		return -1
	for group: int in group_count:
		if (groups & (1 << group)) == 0:
			continue
		if at + 1 > payload.size():
			return -1
		var mask: int = payload.decode_u8(at)
		at += 1
		for bit: int in _OWNER_GROUP:
			if (mask & (1 << bit)) == 0:
				continue
			var index: int = (group << _OWNER_SHIFT) + bit
			if index >= values.size() or at + 4 > payload.size():
				return -1
			values[index] = payload.decode_float(at)
			at += 4
	return at


static var _default_world: WorldSnapshot = null
static var _default_state: PlayerState = null


## The world a full update is coded against: no bodies, zero state, no records.
static func _defaults() -> WorldSnapshot:
	if _default_world == null:
		_default_world = WorldSnapshot.new()
	return _default_world


static func _default_body() -> PlayerState:
	if _default_state == null:
		_default_state = PlayerState.new()
	return _default_state


# --- Quantisation -------------------------------------------------------------

## Three axes as centimetres in an [code]i16[/code], clamped to the box.
static func _put_metres(buffer: StreamPeerBuffer, value: Vector3) -> void:
	buffer.put_16(quantise_metres(value.x))
	buffer.put_16(quantise_metres(value.y))
	buffer.put_16(quantise_metres(value.z))


## Three i16 centimetres of [param payload] at [param at], as metres.
static func metres_at(payload: PackedByteArray, at: int) -> Vector3:
	return Vector3(
		float(payload.decode_s16(at)) / QUANT_CENTIMETRE,
		float(payload.decode_s16(at + 2)) / QUANT_CENTIMETRE,
		float(payload.decode_s16(at + 4)) / QUANT_CENTIMETRE,
	)


## [param value] as the wire carries it: each axis to the centimetre, within the box.
static func quantised_metres(value: Vector3) -> Vector3:
	return Vector3(
		float(quantise_metres(value.x)) / QUANT_CENTIMETRE,
		float(quantise_metres(value.y)) / QUANT_CENTIMETRE,
		float(quantise_metres(value.z)) / QUANT_CENTIMETRE,
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


## One angle as the nearest step of a full turn, in a [code]u16[/code].
static func quantise_turn(radians: float) -> int:
	if not is_finite(radians):
		return 0
	return roundi(fposmod(radians, TAU) / TAU * float(_YAW_STEPS)) % _YAW_STEPS


## The angle a u16 turn names, in [-PI, PI): [method quantise_turn] gives back [param steps].
static func turn_of(steps: int) -> float:
	return wrapf(float(steps) / float(_YAW_STEPS) * TAU, -PI, PI)


# --- Events: payloads of the snapshot's event ring -------------------------------

## A shot: which rifle, its origin and end, then the reload, round speed and gravity it carried.
## Points are exact f32: a hit is drawn where the host's ray met the body.
static func pack_shot(which: int, origin: Vector3, end_point: Vector3, reload: float, speed: float, gravity: float) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(which)
	_put_point(buffer, origin)
	_put_point(buffer, end_point)
	buffer.put_float(reload if is_finite(reload) else 0.0)
	buffer.put_float(speed if is_finite(speed) else -1.0)
	buffer.put_float(gravity if is_finite(gravity) else -1.0)
	return buffer.data_array


## A hit: which rifle, the seat struck (0xFF: no body), the point and the surface normal.
static func pack_hit(which: int, seat: int, at: Vector3, normal: Vector3) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(which)
	buffer.put_u8(seat if seat >= 0 and seat < NetTransport.MAX_PLAYERS else 0xFF)
	_put_point(buffer, at)
	_put_unit(buffer, normal)
	return buffer.data_array


## A miss, a landed shove or a cat blast: one byte (rifle, victim seat, kind) and a point.
static func pack_point(byte: int, at: Vector3) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(byte)
	_put_point(buffer, at)
	return buffer.data_array


## The shover's own kick: the flat direction it pushed in.
static func pack_kick(forward: Vector3) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_unit(buffer, forward)
	return buffer.data_array


static func event_point(payload: PackedByteArray, at: int) -> Vector3:
	var point: Vector3 = Vector3(payload.decode_float(at), payload.decode_float(at + 4), payload.decode_float(at + 8))
	return point if point.is_finite() else Vector3.ZERO


## The seat [param entry] is about (the body struck or shoved), or -1.
static func event_subject(entry: NetEvents.Entry) -> int:
	match entry.type:
		NetEvents.Type.HIT:
			return entry.payload[1]
		NetEvents.Type.SHOVE_LANDED:
			return entry.payload[0]
	return -1


static func _put_point(buffer: StreamPeerBuffer, v: Vector3) -> void:
	var point: Vector3 = v if v.is_finite() else Vector3.ZERO
	buffer.put_float(point.x)
	buffer.put_float(point.y)
	buffer.put_float(point.z)


static func event_unit(payload: PackedByteArray, at: int) -> Vector3:
	return Vector3(payload.decode_s8(at), payload.decode_s8(at + 1), payload.decode_s8(at + 2)) / 127.0


static func _put_unit(buffer: StreamPeerBuffer, v: Vector3) -> void:
	var unit: Vector3 = v.normalized() if v.is_finite() and v.length_squared() > 0.0 else Vector3.ZERO
	buffer.put_8(roundi(unit.x * 127.0))
	buffer.put_8(roundi(unit.y * 127.0))
	buffer.put_8(roundi(unit.z * 127.0))


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


# --- Match record: the MATCH section --------------------------------------------

## The match record's header: phase, round, guard, finisher, outcome, winner (slots, 0xFF none), started.
const MATCH_HEADER_SIZE: int = 7
## Bytes per participant: flags (running, ghost, shooter, held), rounds won, turns in the tower.
const MATCH_PARTICIPANT_SIZE: int = 3
const MATCH_RUNNING: int = 1
const MATCH_GHOST: int = 2
const MATCH_SHOOTER: int = 4
## A ghost still held where it died; clear on a ghost, its respawn has already landed.
const MATCH_HELD: int = 8


## The match as a late binder converges on it (Quake's gamestate), or empty before it has started.
static func pack_match(controller: MatchController, started: bool) -> PackedByteArray:
	var participants: Array[MatchParticipant] = controller.get_participants()
	var out: PackedByteArray = PackedByteArray()
	if not started or participants.size() > NetTransport.MAX_PLAYERS:
		return out
	out.resize(MATCH_HEADER_SIZE + participants.size() * MATCH_PARTICIPANT_SIZE)
	out[0] = int(controller.get_phase())
	out[1] = clampi(controller.get_round_number(), 0, 255)
	out[2] = _slot_byte(controller.get_seat_participant())
	out[3] = _slot_byte(controller.get_finisher())
	out[4] = int(controller.get_outcome())
	out[5] = _slot_byte(controller.get_match_winner())
	out[6] = participants.size()
	for i: int in participants.size():
		var p: MatchParticipant = participants[i]
		var at: int = MATCH_HEADER_SIZE + i * MATCH_PARTICIPANT_SIZE
		out[at] = (
			(MATCH_RUNNING if p.is_running else 0) | (MATCH_GHOST if p.is_ghost else 0)
			| (MATCH_SHOOTER if p.is_shooter else 0) | (MATCH_HELD if p.respawn_hold_remaining > 0.0 else 0)
		)
		out[at + 1] = clampi(p.rounds_won, 0, 255)
		out[at + 2] = clampi(p.turns_in_tower, 0, 255)
	return out


## True when [param record] is a whole match record for [param participant_count] participants.
static func is_match_record(record: PackedByteArray, participant_count: int) -> bool:
	return (
		record.size() == MATCH_HEADER_SIZE + participant_count * MATCH_PARTICIPANT_SIZE
		and record[6] == participant_count
	)


## A slot byte read back: -1 for none.
static func match_slot(record: PackedByteArray, at: int) -> int:
	return -1 if record[at] == 0xFF else record[at]


static func _slot_byte(p: MatchParticipant) -> int:
	return clampi(p.index, 0, 254) if p != null else 0xFF


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
