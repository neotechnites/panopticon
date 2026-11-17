class_name RemoteIntentSource
extends IntentSource

## An [IntentSource] filled in by a network peer instead of by a device or by
## AI.
##
## This is the point of the intent seam paying off. [PlayerController] asks an
## [IntentSource] for a [MoveIntent] and applies physics to it; it cannot tell
## whether the struct came from a keyboard, from a bot, or -- now -- from a
## socket. A remote player's body on the listen server therefore runs the
## identical movement code as the local one, with no networked variant of the
## controller and no second copy of the Quake acceleration routines to drift
## out of step with the first.
##
## Only the authority owns one of these. A client does not simulate other
## players' bodies at all; it is handed [PlayerState] snapshots. See
## [PlayerNetLink].
##
## Edge semantics match [BotIntentSource]: [method poll] consumes the one-tick
## fields, so a jump or a slide that arrived in one packet fires on one tick
## and not forever after. Sustained fields persist, which is what makes the source
## survive the packet loss it is guaranteed to see -- a dropped packet means
## the body keeps walking the way it was walking, which is right, rather than
## stopping dead for one tick, which reads as a stutter and is wrong.
##
## Packets are taken one per tick from a short queue rather than latest-wins;
## see [constant BUFFER_SIZE] for why that matters to the sender.

## Ticks without a packet before this source gives up and reports no intent.
##
## Persisting the last input is correct across a dropped packet and disastrous
## across a dropped [i]player[/i]: a peer that stops sending -- alt-tabbed,
## crashed, or deliberately holding forward and pulling the cable -- would
## otherwise sprint into the distance forever with nothing driving it. After
## this many authority ticks with nothing received, held buttons are released
## and the body coasts to a stop under friction, which is also exactly what a
## human who let go of the keys looks like.
##
## Twelve ticks is 200 ms at 60 Hz: long enough to ride out a burst of loss on
## a bad connection, short enough that a disconnect is over before anyone can
## use it.
##
## Overwritten from [member NetSettings.stale_intent_ticks] by [PlayerNetLink]
## the first time a client's packet arrives, so the shipped number lives with
## the other network numbers. The default here is what a source used outside a
## session -- a test, a replay -- gets.
@export_range(2, 120, 1) var stale_after_ticks: int = 12

## The most recent intent received, held between packets.
var command: MoveIntent = MoveIntent.new()

## Wire tick of the last packet accepted, or -1 before the first one.
var last_tick: int = -1

## Wire tick of the last packet the body has actually SIMULATED, or -1. Not the
## same as [member last_tick] -- a packet accepted between two physics ticks has
## not moved anything yet -- and it is this one a predicting client is
## acknowledged with, or it would drop an input the authority never ran.
var applied_tick: int = -1

## Packets accepted and not yet simulated, oldest first. One is taken per tick.
##
## [b]A queue, not a latest-wins slot.[/b] Jitter delivers two packets between
## one pair of ticks about as often as it delivers none, and keeping only the
## newer of the two throws away an input the player made -- a jump, a look
## delta, a slide -- which is the one thing this whole path exists not to do.
## It also breaks the arithmetic a predicting client depends on: the client
## simulated one tick per intent, so an intent the authority skipped leaves its
## acknowledgement describing a different number of ticks than the client
## replayed, and the difference comes back as a correction every time.
##
## Four deep, and the oldest is dropped rather than the newest when it
## overflows, so a client whose clock runs fast cannot buy itself an ever
## growing lead in input delay.
const BUFFER_SIZE: int = 4
var _buffer: Array[MoveIntent] = []
var _buffer_ticks: PackedInt32Array = PackedInt32Array()
var _buffer_start: int = 0
var _buffer_count: int = 0

## Authority ticks since a packet was accepted.
var _ticks_since_packet: int = 0

## True once staleness has zeroed the command, so it is only zeroed once.
var _stale: bool = false

## The sender's press counts as of the last command run, or -1 before one: see [member MoveIntent.press_counts].
var _seen_presses: int = -1
## The sender's [member MoveIntent.emote_state] as of the last command run, or -1 before one.
var _seen_emote: int = -1
## Presses counted and not yet handed to the body, per [enum MoveIntent.Press]; one is spent a tick.
var _owed: PackedByteArray = PackedByteArray()
## The slot each owed power press was made with, oldest first: as many as [member _owed] has of POWER.
var _owed_slots: PackedByteArray = PackedByteArray()
const _OWED_MAX: int = MoveIntent.PRESS_MODULUS - 1

## A trigger press that arrived and has not been taken by the rifle yet, and the tick the
## sender was drawing when it pressed (see [member MoveIntent.view_tick]).
var _fire_latched: bool = false
var fire_view_tick: int = -1


## Take a decoded packet. Returns false if it is older than one already
## applied, which is how out-of-order UDP delivery is discarded -- an unreliable
## channel reorders, and applying a stale packet after a newer one rewinds the
## player's input for a tick.
func accept(tick: int, intent: MoveIntent) -> bool:
	if last_tick >= 0 and not NetCodec.is_newer_tick(tick, last_tick):
		return false
	last_tick = tick
	if _buffer.is_empty():
		_buffer.resize(BUFFER_SIZE)
		_buffer_ticks.resize(BUFFER_SIZE)
		for i: int in BUFFER_SIZE:
			_buffer[i] = MoveIntent.new()
	if _buffer_count >= BUFFER_SIZE:
		# Arriving faster than the simulation consumes. The oldest goes, so the
		# delay this queue adds stays bounded.
		_buffer_start = (_buffer_start + 1) % BUFFER_SIZE
		_buffer_count -= 1
	var slot: int = (_buffer_start + _buffer_count) % BUFFER_SIZE
	_buffer[slot].copy_from(intent)
	_buffer_ticks[slot] = tick
	_buffer_count += 1
	_ticks_since_packet = 0
	_stale = false
	return true


## True when nothing has arrived for [member stale_after_ticks] ticks. The
## honest signal for "this peer has gone quiet"; a session-level timeout is a
## separate and much longer thing.
func is_stale() -> bool:
	return _stale


func poll(_delta: float) -> MoveIntent:
	_ticks_since_packet += 1
	var emote: int = -1
	if _buffer_count > 0:
		command.copy_from(_buffer[_buffer_start])
		applied_tick = _buffer_ticks[_buffer_start]
		_buffer_start = (_buffer_start + 1) % BUFFER_SIZE
		_buffer_count -= 1
		_count_presses(command)
		emote = _emote_change(command)
		if command.fire_pressed:
			# Latched as the command runs, so the shot goes with that command's aim and view tick.
			_fire_latched = true
			fire_view_tick = command.view_tick
	elif _ticks_since_packet > stale_after_ticks and not _stale:
		_stale = true
		command.clear()

	command.normalise()
	_intent.copy_from(command)
	_intent.emote_state = emote
	if command.emote_state >= 0:
		# A sender that says where its emote stands has run the toggle itself; it is not also tapping.
		_intent.emote_pressed = false
		_intent.emote_alt_pressed = false
	_spend_presses()
	# Consume the edges. Everything else stands until the next packet.
	command.jump_pressed = false
	command.slide_pressed = false
	command.fire_pressed = false
	command.ability_pressed = false
	command.ability_slot = 0
	command.shove_pressed = false
	command.cook_pressed = false
	command.emote_pressed = false
	command.emote_alt_pressed = false
	return _intent


## Count what [param from] says was pressed since the last command run: its own edges on the
## first, the advance of its counts after, so a press on a command that never arrived still lands.
func _count_presses(from: MoveIntent) -> void:
	if _owed.is_empty():
		_owed.resize(MoveIntent.PRESS_KEYS)
		_owed_slots.resize(_OWED_MAX)
	for key: int in MoveIntent.PRESS_KEYS:
		var pressed: int = 1 if from.presses(key) else 0
		if _seen_presses >= 0:
			pressed = posmod(
				MoveIntent.press_count(from.press_counts, key)
				- MoveIntent.press_count(_seen_presses, key),
				MoveIntent.PRESS_MODULUS,
			)
		if key == MoveIntent.Press.POWER:
			# This command's own press names its slot; one made on a lost command is the newest's,
			# and the one before that the prior's. Older than that the wire does not say.
			var newest: int = from.ability_slot if from.presses(key) else from.press_slot
			for i: int in pressed:
				var at: int = _owed[key] + i
				if at < _OWED_MAX:
					_owed_slots[at] = newest if i == pressed - 1 else from.press_slot_prior
		_owed[key] = mini(_owed[key] + pressed, _OWED_MAX)
	_seen_presses = from.press_counts


## Where [param from]'s sender says its emote stands, when that is news; -1 when it is not, or is
## the first word since a fresh start. A level, so what a lost command said costs nothing.
func _emote_change(from: MoveIntent) -> int:
	if from.emote_state < 0:
		return -1
	var changed: bool = _seen_emote >= 0 and from.emote_state != _seen_emote
	_seen_emote = from.emote_state
	return from.emote_state if changed else -1


## Hand the body one owed press of each key, as the edge it was made as.
func _spend_presses() -> void:
	if _owed.is_empty():
		return
	var power: bool = _spend(MoveIntent.Press.POWER)
	var slot: int = _owed_slots[0] if power else 0
	if power:
		# The next owed press's slot moves up to the front.
		for i: int in _OWED_MAX - 1:
			_owed_slots[i] = _owed_slots[i + 1]
	_intent.ability_slot = slot
	_intent.ability_pressed = power and slot == 0
	_intent.cook_pressed = _spend(MoveIntent.Press.COOK)
	_intent.shove_pressed = _spend(MoveIntent.Press.SHOVE)


func _spend(key: int) -> bool:
	if _owed[key] == 0:
		return false
	_owed[key] -= 1
	return true


## The pending trigger press, consumed.
func take_fire() -> bool:
	var pressed: bool = _fire_latched
	_fire_latched = false
	return pressed


func is_fire_held() -> bool:
	return command.fire_held and not _stale


## The body is not being run: let go of everything sent for it, so nothing waits for its return.
## The tick order stands, so a repeat of a dropped command is still refused.
func rest() -> void:
	command.clear()
	_buffer_start = 0
	_buffer_count = 0
	_fire_latched = false
	fire_view_tick = -1
	forget_presses()


## Forget everything received. For a peer leaving, or a round restarting.
func reset() -> void:
	rest()
	last_tick = -1
	applied_tick = -1
	_ticks_since_packet = 0
	_stale = false


## A fresh start: the next command's counts and emote state are a new baseline.
func forget_presses() -> void:
	_seen_presses = -1
	_seen_emote = -1
	_owed.fill(0)
