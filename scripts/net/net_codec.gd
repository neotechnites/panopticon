class_name NetCodec
extends RefCounted

## The wire format: [MoveIntent] and [PlayerState] to and from bytes.
##
## Everything crossing the network goes through here, for three reasons.
##
## [b]Size.[/b] Godot will happily send a [Dictionary] over an RPC, and it
## costs several times what these do -- an intent is 21 bytes packed and about
## 120 as a variant dictionary, sent 60 times a second per player. Small
## lobbies do not make that free; they make it invisible until someone is on a
## bad connection.
##
## [b]Validation.[/b] A client's intent packet is hostile input. Byte arrays
## have to be length-checked before they are read, and doing that in one place
## means it cannot be forgotten in a second place. Decoding never trusts the
## payload: a wrong length returns failure and the caller drops the packet.
## Note what this does [i]not[/i] do -- it does not bound the values inside a
## well-formed packet. A client can still send a look delta of a thousand
## radians; clamping that is the authority's job, in [PlayerNetLink], because
## the sane range comes from [MovementProfile] and the codec has no business
## knowing about tunables.
##
## [b]Stability.[/b] One file to read when the format has to change, and one
## place to put a version byte when it does. There is no version byte today:
## there are no shipped clients to be incompatible with, and a field added
## before release costs nothing.
##
## Decoding writes into a caller-owned object and returns a [bool], rather than
## allocating and returning a new one, so the per-tick path allocates nothing
## but the [PackedByteArray] itself.

## Bytes in a packed intent: u32 tick, 4 floats, 1 flag byte.
const INTENT_SIZE: int = 21

## Bytes in a packed state: u32 peer id, u32 tick, 8 floats, 1 flag byte.
const STATE_SIZE: int = 41

const _FLAG_JUMP_PRESSED: int = 1 << 0
const _FLAG_JUMP_HELD: int = 1 << 1
const _FLAG_SPRINT_HELD: int = 1 << 2
const _FLAG_SLIDE_PRESSED: int = 1 << 3
const _FLAG_SLIDE_HELD: int = 1 << 4
const _FLAG_ON_FLOOR: int = 1 << 0

## Ticks are unsigned 32-bit on the wire and wrap there.
const TICK_MODULUS: int = 1 << 32


static func pack_intent(tick: int, intent: MoveIntent) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(tick % TICK_MODULUS)
	buffer.put_float(intent.move_direction.x)
	buffer.put_float(intent.move_direction.y)
	buffer.put_float(intent.look_delta.x)
	buffer.put_float(intent.look_delta.y)
	var flags: int = 0
	if intent.jump_pressed:
		flags |= _FLAG_JUMP_PRESSED
	if intent.jump_held:
		flags |= _FLAG_JUMP_HELD
	if intent.sprint_held:
		flags |= _FLAG_SPRINT_HELD
	if intent.slide_pressed:
		flags |= _FLAG_SLIDE_PRESSED
	if intent.slide_held:
		flags |= _FLAG_SLIDE_HELD
	buffer.put_u8(flags)
	return buffer.data_array


## Decode into [param out]. Returns the tick, or -1 if [param payload] is not a
## well-formed intent, in which case [param out] is untouched.
##
## Returning the tick separately keeps [MoveIntent] free of a network field:
## it is the input struct the whole game shares, and the bot harness has no
## tick to put in it.
static func unpack_intent(payload: PackedByteArray, out: MoveIntent) -> int:
	if payload.size() != INTENT_SIZE:
		return -1
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = payload
	var tick: int = buffer.get_u32()
	var move_x: float = buffer.get_float()
	var move_y: float = buffer.get_float()
	var look_x: float = buffer.get_float()
	var look_y: float = buffer.get_float()
	var flags: int = buffer.get_u8()
	# NaN and infinity survive a float round-trip and poison a physics body on
	# contact, so they are rejected here rather than clamped: there is no
	# sensible value to substitute, and a peer sending them is not playing.
	if not (is_finite(move_x) and is_finite(move_y) and is_finite(look_x) and is_finite(look_y)):
		return -1
	out.move_direction = Vector2(move_x, move_y)
	out.look_delta = Vector2(look_x, look_y)
	out.jump_pressed = (flags & _FLAG_JUMP_PRESSED) != 0
	out.jump_held = (flags & _FLAG_JUMP_HELD) != 0
	out.sprint_held = (flags & _FLAG_SPRINT_HELD) != 0
	out.slide_pressed = (flags & _FLAG_SLIDE_PRESSED) != 0
	out.slide_held = (flags & _FLAG_SLIDE_HELD) != 0
	out.normalise()
	return tick


static func pack_state(state: PlayerState) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(state.peer_id)
	buffer.put_u32(state.tick % TICK_MODULUS)
	buffer.put_float(state.position.x)
	buffer.put_float(state.position.y)
	buffer.put_float(state.position.z)
	buffer.put_float(state.velocity.x)
	buffer.put_float(state.velocity.y)
	buffer.put_float(state.velocity.z)
	buffer.put_float(state.yaw)
	buffer.put_float(state.pitch)
	buffer.put_u8(_FLAG_ON_FLOOR if state.on_floor else 0)
	return buffer.data_array


## Decode into [param out]. Returns false if [param payload] is not a
## well-formed state, in which case [param out] is untouched.
static func unpack_state(payload: PackedByteArray, out: PlayerState) -> bool:
	if payload.size() != STATE_SIZE:
		return false
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = payload
	var peer_id: int = buffer.get_u32()
	var tick: int = buffer.get_u32()
	var position: Vector3 = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
	var velocity: Vector3 = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
	var yaw: float = buffer.get_float()
	var pitch: float = buffer.get_float()
	var flags: int = buffer.get_u8()
	if not (position.is_finite() and velocity.is_finite() and is_finite(yaw) and is_finite(pitch)):
		return false
	out.peer_id = peer_id
	out.tick = tick
	out.position = position
	out.velocity = velocity
	out.yaw = yaw
	out.pitch = pitch
	out.on_floor = (flags & _FLAG_ON_FLOOR) != 0
	return true


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
