class_name LobbySeat
extends RefCounted

## One place in the lobby: who is in it, what they will be when the match
## starts, and whether they are ready to start.
##
## [b]A seat is an identity, and it is the identity the wire uses[/b]
##
## Everything below the lobby keys off [member index] and not off a peer id.
## That is not tidiness, it is the requirement: this project's matches are
## filled out with bots, because Ryan tests alone, and a bot has no peer id. If
## a body on the wire were named by the peer driving it, a bot's body could not
## be named at all, and "a seat filled by a bot and a seat filled by a remote
## human are interchangeable" would be a comment rather than a fact.
##
## So the seat index is the name of the body, and [member peer_id] is a
## separate question -- "whose packets am I allowed to take for this body" --
## whose answer is legitimately zero.
##
## [b]A seat is not a participant[/b]
##
## [MatchParticipant] is the match's idea of a player: lives, turns in the
## tower, which brain is switched on. This is the lobby's idea of a player,
## which exists before any of that does and stops mattering the moment the
## match layer builds a participant from it. The overlap is deliberate and
## small: an index, a name, and whether the thing is human.

## Who or what is in this seat.
enum Occupancy {
	## Nobody. The seat exists -- there are always
	## [constant NetTransport.MAX_PLAYERS] of them -- and can be filled.
	EMPTY,
	## A person, local or remote. [member peer_id] says which machine.
	HUMAN,
	## A bot, simulated on the authority. [member peer_id] is 0: no machine
	## sends input for this body, so no packet may ever drive it.
	BOT,
}

## What this seat plays when the match starts.
##
## Only the OPENING assignment. The tower changes hands constantly once a match
## is running -- a prisoner who reaches the end takes it -- and the lobby does
## not follow it there; ask the match layer who is in the tower now.
enum Role {
	## Not decided. The normal state in the lobby, and the correct state at
	## launch when [member MatchRules.open_with_race] is on and the opening
	## race is what decides who takes the seat.
	UNASSIGNED,
	## Starts in the tower with the rifle.
	GUARD,
	## Starts on the line and runs the ring.
	PRISONER,
}

## Position in [member NetLobby.seats]. Fixed for the life of the lobby, and
## the name of this seat's body everywhere below the lobby.
var index: int = 0

var occupancy: Occupancy = Occupancy.EMPTY

## The machine whose intent packets may drive this seat's body, or 0 for a body
## nothing remote drives -- an empty seat, a bot, or (on the authority's own
## view of itself) a seat the host plays locally.
##
## Checked by hand against the RPC sender in [PlayerNetLink]. This is the one
## test that stops a peer driving somebody else's body, so it is a peer id and
## never a role: roles move during a match and this must not.
var peer_id: int = 0

## What the HUD calls whoever is here. Free-form text from a peer, so it
## arrives truncated and stripped -- see [method NetCodec.sanitise_name].
var display_name: String = ""

var role: Role = Role.UNASSIGNED

## Whether this seat has said it is ready to start.
##
## A bot is always ready: it has no keyboard to press a button with, and a
## lobby that waits for one would never start. [method NetLobby.set_ready] is
## what enforces that, so a seat read straight off the wire cannot lie about it.
var is_ready: bool = false


func is_occupied() -> bool:
	return occupancy != Occupancy.EMPTY


func is_human() -> bool:
	return occupancy == Occupancy.HUMAN


func is_bot() -> bool:
	return occupancy == Occupancy.BOT


## Empty this seat completely. Used when a peer leaves and when the lobby is
## torn down; never leaves a stale name or peer id behind for the next occupant
## to inherit.
func clear() -> void:
	occupancy = Occupancy.EMPTY
	peer_id = 0
	display_name = ""
	role = Role.UNASSIGNED
	is_ready = false


func copy_from(other: LobbySeat) -> void:
	index = other.index
	occupancy = other.occupancy
	peer_id = other.peer_id
	display_name = other.display_name
	role = other.role
	is_ready = other.is_ready


## One line, for logs and the harness.
func describe() -> String:
	if not is_occupied():
		return "seat %d: empty" % index
	return "seat %d: %s %s (peer %d, %s%s)" % [
		index,
		String(Occupancy.keys()[occupancy]),
		display_name,
		peer_id,
		String(Role.keys()[role]),
		", ready" if is_ready else "",
	]
