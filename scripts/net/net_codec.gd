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
## packet. A client can still send a look delta of a thousand radians; clamping
## that is the authority's job, in [PlayerNetLink], because the sane range
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
## [b]What is deliberately not here[/b]
##
## Nothing about lag compensation, delta compression or acknowledgement. Every
## field of every body goes every snapshot. At eight players that is about 300
## bytes a packet, which is cheap; it is listed as a gap rather than a
## feature because it is a habit that stops being cheap at a player count this
## game will never reach.

## Bytes in a packed intent: u32 tick, 4 floats, a flag byte, the ability slot
## and a second flag byte.
const INTENT_SIZE: int = 23

## Bytes of snapshot header: u32 tick, u8 body count.
const SNAPSHOT_HEADER_SIZE: int = 5

## Bytes per body inside a snapshot: u8 seat, 8 floats, 1 flag byte. The seat is
## a byte and not a peer id because seats are what bodies are named by -- see
## [PlayerState].
const SNAPSHOT_BODY_SIZE: int = 34

## Bytes of roster header: u8 phase, u8 seat count.
const ROSTER_HEADER_SIZE: int = 2

## Bytes of the fixed part of a roster seat: u8 index, u8 occupancy, u8 role,
## u8 flags, u32 peer id, u8 name length. The name follows, that many bytes.
const ROSTER_SEAT_FIXED_SIZE: int = 9

const _FLAG_JUMP_PRESSED: int = 1 << 0
const _FLAG_JUMP_HELD: int = 1 << 1
# Bit 2 was sprint, which the game no longer has. The bit is left unused rather
# than reclaimed: the remaining flags keep the positions they have always had,
# so a build of this codec cannot disagree with another about what bit 3 means.
const _FLAG_SLIDE_PRESSED: int = 1 << 3
const _FLAG_SLIDE_HELD: int = 1 << 4
const _FLAG_FIRE_PRESSED: int = 1 << 2
const _FLAG_FIRE_HELD: int = 1 << 5
const _FLAG_ABILITY_PRESSED: int = 1 << 6
const _FLAG_ABILITY_HELD: int = 1 << 7
## Second flag byte. The first is full; new intent bits start here.
const _FLAG2_SHOVE_PRESSED: int = 1 << 0
const _FLAG_ON_FLOOR: int = 1 << 0
const _FLAG_SEAT_READY: int = 1 << 0

## Ticks are unsigned 32-bit on the wire and wrap there.
const TICK_MODULUS: int = 1 << 32


# --- Intent: client to authority ----------------------------------------------

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
	if intent.slide_pressed:
		flags |= _FLAG_SLIDE_PRESSED
	if intent.slide_held:
		flags |= _FLAG_SLIDE_HELD
	if intent.fire_pressed:
		flags |= _FLAG_FIRE_PRESSED
	if intent.fire_held:
		flags |= _FLAG_FIRE_HELD
	if intent.ability_pressed:
		flags |= _FLAG_ABILITY_PRESSED
	if intent.ability_held:
		flags |= _FLAG_ABILITY_HELD
	buffer.put_u8(flags)
	buffer.put_u8(clampi(intent.ability_slot, 0, 4))
	buffer.put_u8(_FLAG2_SHOVE_PRESSED if intent.shove_pressed else 0)
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
	var slot: int = buffer.get_u8()
	var flags2: int = buffer.get_u8()
	# NaN and infinity survive a float round-trip and poison a physics body on
	# contact, so they are rejected here rather than clamped: there is no
	# sensible value to substitute, and a peer sending them is not playing.
	if not (is_finite(move_x) and is_finite(move_y) and is_finite(look_x) and is_finite(look_y)):
		return -1
	out.move_direction = Vector2(move_x, move_y)
	out.look_delta = Vector2(look_x, look_y)
	out.jump_pressed = (flags & _FLAG_JUMP_PRESSED) != 0
	out.jump_held = (flags & _FLAG_JUMP_HELD) != 0
	out.slide_pressed = (flags & _FLAG_SLIDE_PRESSED) != 0
	out.slide_held = (flags & _FLAG_SLIDE_HELD) != 0
	out.fire_pressed = (flags & _FLAG_FIRE_PRESSED) != 0
	out.fire_held = (flags & _FLAG_FIRE_HELD) != 0
	out.ability_pressed = (flags & _FLAG_ABILITY_PRESSED) != 0
	out.ability_held = (flags & _FLAG_ABILITY_HELD) != 0
	out.ability_slot = clampi(slot, 0, 4)
	out.shove_pressed = (flags2 & _FLAG2_SHOVE_PRESSED) != 0
	out.normalise()
	return tick


# --- Snapshot: authority to everyone ------------------------------------------

static func pack_snapshot(snapshot: WorldSnapshot) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(snapshot.tick % TICK_MODULUS)
	buffer.put_u8(snapshot.count)
	for i: int in snapshot.count:
		var state: PlayerState = snapshot.states[i]
		buffer.put_u8(state.seat_index)
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
	var count: int = buffer.get_u8()
	if count > NetTransport.MAX_PLAYERS:
		return false
	if payload.size() != SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_BODY_SIZE:
		return false

	out.clear()
	out.tick = tick
	for _i: int in count:
		var state: PlayerState = out.next_slot()
		var seat_index: int = buffer.get_u8()
		var position: Vector3 = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
		var velocity: Vector3 = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
		var yaw: float = buffer.get_float()
		var pitch: float = buffer.get_float()
		var flags: int = buffer.get_u8()
		if not (position.is_finite() and velocity.is_finite() and is_finite(yaw) and is_finite(pitch)):
			out.clear()
			return false
		state.seat_index = seat_index
		state.tick = tick
		state.position = position
		state.velocity = velocity
		state.yaw = yaw
		state.pitch = pitch
		state.on_floor = (flags & _FLAG_ON_FLOOR) != 0
		out.commit()
	return true


# --- Roster: authority to everyone --------------------------------------------

## Pack the lobby phase and the whole seat table.
##
## The WHOLE table, every time, even to change one seat's ready flag. It is
## about 200 bytes and it is sent when somebody joins, leaves or presses ready
## -- a handful of times a match. Buying a delta encoding with the possibility
## of two machines disagreeing about who is in the game would be a bad trade at
## any price, and this one is free.
static func pack_roster(phase: int, seats: Array[LobbySeat], max_name_bytes: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(phase)
	buffer.put_u8(seats.size())
	for seat: LobbySeat in seats:
		var name_bytes: PackedByteArray = sanitise_name(seat.display_name, max_name_bytes).to_utf8_buffer()
		buffer.put_u8(seat.index)
		buffer.put_u8(int(seat.occupancy))
		buffer.put_u8(int(seat.role))
		buffer.put_u8(_FLAG_SEAT_READY if seat.is_ready else 0)
		buffer.put_u32(seat.peer_id)
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


## Every scalar export of [param rules] as bytes. Reliable-channel sized, not
## per-tick sized.
static func pack_rules(rules: MatchRules) -> PackedByteArray:
	var fields: Dictionary = {}
	for field: String in rules_field_names(rules):
		var value: Variant = rules.get(field)
		fields[field] = String(value) if typeof(value) == TYPE_STRING_NAME else value
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
	return true


## Copy every scalar export from one rules object onto another.
static func copy_rules(from: MatchRules, to: MatchRules) -> void:
	if from == null or to == null or from == to:
		return
	for field: String in rules_field_names(from):
		to.set(field, from.get(field))
