class_name NetTransport
extends Node

## What PANOPTICON needs from a network backend, and nothing more.
##
## The game is server-authoritative on a [b]player-hosted listen server[/b]:
## one player's machine simulates the match and every other machine is a
## terminal onto it. There are no dedicated servers, so there is no fixed
## address and no always-on process -- the authority is whichever player
## pressed Host.
##
## Two backends implement this interface:
##
## - [ENetTransport] -- real UDP sockets, used for development, headless bot
##   matches and CI. It must run with no Steam client present at all, because
##   the bot harness is how this project produces evidence and the harness
##   cannot depend on a storefront being logged in.
## - [SteamTransport] -- the shipping backend: free relay, NAT traversal, no IP
##   address exposed to strangers. It is a stub today; see that file.
##
## [b]Authority binds to a peer, never to a role[/b]
##
## The tower seat changes hands constantly -- a prisoner who reaches the end
## takes it and the round restarts. Authority must not follow it. If it did,
## the simulation would migrate hosts every time somebody scored, which is a
## full state transfer and a stall in the middle of live play, several times a
## match. So authority is [member AUTHORITY_PEER_ID], fixed at the moment
## [method host] is called and unchanged for the lifetime of the session no
## matter who is in the tower. Nothing in this file, [NetSession] or
## [PlayerNetLink] reads the tower role, and nothing in the match layer may
## ever be allowed to call [method Node.set_multiplayer_authority] in response
## to one.
##
## [b]Implementing a backend[/b]
##
## Override [method host], [method join], [method leave] and
## [method get_local_peer_id]. Drive the rest by calling
## [method _set_state] and by emitting [signal peer_connected] /
## [signal peer_disconnected]; the base class owns the state variable, the
## readable names and the authority test so two backends cannot disagree about
## what "connected" means.

## A peer joined the session. On the authority this fires for every client. On
## a client it fires for the authority and for the other clients, because the
## high-level API introduces peers to each other.
signal peer_connected(peer_id: int)

## A peer left, gracefully or otherwise. On a client, the authority leaving is
## the end of the session: [method leave] has already been run by the time this
## is emitted for [member AUTHORITY_PEER_ID].
signal peer_disconnected(peer_id: int)

## The connection state changed. Carries the new state; the old one is gone by
## the time this runs.
signal connection_state_changed(state: ConnectionState)

## Where the session stands. Exhaustive, and the only vocabulary the rest of
## the game gets for "are we online".
enum ConnectionState {
	## No peer at all. Also the state of a single-player or bot-harness run,
	## which is why [method is_authority] answers true here.
	OFFLINE,
	## This machine is the listen server. Authoritative, and accepting joins.
	HOSTING,
	## A join is in flight. Not yet authoritative over anything, and not yet
	## able to send.
	CONNECTING,
	## Joined, and receiving the authority's simulation.
	CONNECTED,
	## The last host or join attempt failed, or the authority vanished.
	## Deliberately distinct from [constant OFFLINE]: a client whose connection
	## broke must not silently promote itself to authority.
	FAILED,
}

## The peer id of the authority, for as long as any session exists.
##
## One, always. Godot's high-level API reserves 1 for the server end of the
## peer, and because the listen server is the process that called
## [method host], the host is 1 on every machine's view of the session.
## Client-to-authority messages are addressed to this constant rather than to
## whoever currently holds the tower -- see the class docs.
const AUTHORITY_PEER_ID: int = 1

## Highest custom [code]@rpc[/code] channel this project uses.
##
## Channel 0 is the default one, and everything rare and reliable rides it --
## the lobby roster. The two per-tick streams get channels of their own so that
## a burst of one cannot delay the other: intent on 1, world snapshots on 2. A
## backend has to open enough channels to carry them, and see
## [constant ENetTransport.ENET_CHANNEL_COUNT] for the trap in doing that.
const MAX_RPC_CHANNEL: int = 2

## Hard cap on players in one session, authority included.
##
## Matches run 1v1 to 1v7 and are tuned for 1v1-1v3. Small lobbies are a design
## commitment, not a limitation: the whole netcode assumes it can broadcast an
## unshared snapshot to every peer every tick without thinking about bandwidth.
const MAX_PLAYERS: int = 8

var _state: ConnectionState = ConnectionState.OFFLINE


## Become the listen server on [param port]. Returns [constant OK], or an error
## and a state of [constant ConnectionState.FAILED].
##
## [param max_players] counts this machine, and is clamped to
## [constant MAX_PLAYERS].
func host(_port: int, _max_players: int = MAX_PLAYERS) -> Error:
	push_error("NetTransport.host() is abstract; use ENetTransport or SteamTransport.")
	return ERR_UNCONFIGURED


## Join a session. [param address] is backend-specific -- an IP or hostname for
## [ENetTransport], a lobby or Steam id for [SteamTransport] -- which is why it
## is a [String] and not a typed address.
##
## Returning [constant OK] means the attempt started, not that it succeeded.
## Success is [signal connection_state_changed] reaching
## [constant ConnectionState.CONNECTED]; failure is
## [constant ConnectionState.FAILED].
func join(_address: String, _port: int) -> Error:
	push_error("NetTransport.join() is abstract; use ENetTransport or SteamTransport.")
	return ERR_UNCONFIGURED


## Tear the session down and return to [constant ConnectionState.OFFLINE].
## Safe to call when already offline.
func leave() -> void:
	push_error("NetTransport.leave() is abstract; use ENetTransport or SteamTransport.")


## This machine's peer id, or 0 when there is no session.
func get_local_peer_id() -> int:
	return 0


## Disconnect one peer, leaving the session up. Authority only; callers are
## expected to have checked, and a backend that cannot do it may do nothing.
##
## There is exactly one caller today -- [NetLobby], for a peer that connected
## with nowhere to sit -- and deliberately no kick vote, no ban list and no
## reason on the wire. The peer sees the host go away, which is the whole truth
## in a game where the host IS the server.
func kick_peer(_peer_id: int) -> void:
	pass


## Tear the session down and land in [constant ConnectionState.FAILED] rather
## than [constant ConnectionState.OFFLINE].
##
## The difference matters and is the reason this is not just [method leave]:
## OFFLINE is authoritative -- it is what single player and the headless
## harness run in -- so a join that timed out and cleaned up with [method leave]
## would promote the machine that failed to connect into the authority over its
## own empty world. Used by [NetSession] when a connection attempt runs out of
## time.
func abort() -> void:
	leave()
	_set_state(ConnectionState.FAILED)


## True when this machine simulates the match.
##
## Two states qualify. [constant ConnectionState.HOSTING] is the listen server.
## [constant ConnectionState.OFFLINE] is a single-player or headless bot run,
## which is authoritative over itself -- so gameplay code never needs a
## "networking is off" special case; it just asks this.
##
## [constant ConnectionState.FAILED] is pointedly not on that list. A client
## that lost the host must not carry on as though its own copy of the world
## were the real one.
func is_authority() -> bool:
	return _state == ConnectionState.OFFLINE or _state == ConnectionState.HOSTING


## The current state.
func get_connection_state() -> ConnectionState:
	return _state


## True once the session can carry traffic, hosting or joined alike. The
## question most callers actually mean when they ask if they are connected.
func is_established() -> bool:
	return _state == ConnectionState.HOSTING or _state == ConnectionState.CONNECTED


## Human-readable state, for logs, the harness and a future debug overlay.
static func state_name(state: ConnectionState) -> String:
	match state:
		ConnectionState.OFFLINE:
			return "OFFLINE"
		ConnectionState.HOSTING:
			return "HOSTING"
		ConnectionState.CONNECTING:
			return "CONNECTING"
		ConnectionState.CONNECTED:
			return "CONNECTED"
		ConnectionState.FAILED:
			return "FAILED"
	return "UNKNOWN"


## Short name of the backend, for logs. Overridden by each implementation.
func backend_name() -> String:
	return "none"


## One line describing the session, for logs and the harness.
func describe() -> String:
	return "%s(state=%s, local_peer=%d, authority=%s)" % [
		backend_name(),
		state_name(_state),
		get_local_peer_id(),
		str(is_authority()),
	]


## Set the state and notify, exactly once per real change. For subclasses.
func _set_state(state: ConnectionState) -> void:
	if _state == state:
		return
	_state = state
	connection_state_changed.emit(_state)
