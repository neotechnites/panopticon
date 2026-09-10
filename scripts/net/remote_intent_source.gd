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

## Authority ticks since a packet was accepted.
var _ticks_since_packet: int = 0

## True once staleness has zeroed the command, so it is only zeroed once.
var _stale: bool = false


## Take a decoded packet. Returns false if it is older than one already
## applied, which is how out-of-order UDP delivery is discarded -- an unreliable
## channel reorders, and applying a stale packet after a newer one rewinds the
## player's input for a tick.
func accept(tick: int, intent: MoveIntent) -> bool:
	if last_tick >= 0 and not NetCodec.is_newer_tick(tick, last_tick):
		return false
	last_tick = tick
	command.copy_from(intent)
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
	if _ticks_since_packet > stale_after_ticks and not _stale:
		_stale = true
		command.clear()

	command.normalise()
	_intent.copy_from(command)
	# Consume the edges. Everything else stands until the next packet.
	command.jump_pressed = false
	command.slide_pressed = false
	command.look_delta = Vector2.ZERO
	return _intent


## Forget everything received. For a peer leaving, or a round restarting.
func reset() -> void:
	command.clear()
	last_tick = -1
	_ticks_since_packet = 0
	_stale = false
