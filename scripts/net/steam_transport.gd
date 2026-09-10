class_name SteamTransport
extends NetTransport

## The shipping backend -- [b]not implemented[/b]. Every call fails loudly.
##
## This file exists so that the shape of the seam is settled now, while it is
## free, rather than during a store submission. It is a specification with a
## refusal attached, not a placeholder to be quietly filled in with something
## that half works.
##
## [b]Why Steam at all[/b]
##
## PANOPTICON is hosted by a player, so a joining machine has to reach a
## residential connection: NAT, carrier-grade NAT, no port forwarding, and a
## host IP address handed to strangers who did not ask for it and should not
## have it. Steam's networking solves all of that -- relay fallback, NAT
## punching, identity by Steam id -- for no money, which matters because this
## project has no budget for dedicated servers and rented boxes would sit idle
## most of the day anyway.
##
## [b]Why it is a stub[/b]
##
## There is no Steam app id yet, and the integration library (GodotSteam, or an
## equivalent binding of ISteamNetworkingSockets) is not installed. Writing the
## real thing now would produce code nobody can run, which is the same as code
## nobody can trust. [ENetTransport] carries development, the bot harness and
## CI in the meantime, and neither it nor anything under scripts/net/ may take
## a dependency on this file.
##
## [b]What the real implementation must satisfy[/b]
##
## 1. [b]Be a [MultiplayerPeer].[/b] Everything above this class -- [NetSession],
##    [PlayerNetLink], every [code]@rpc[/code] -- talks to
##    [member MultiplayerAPI.multiplayer_peer] and nothing else. The backend is
##    a peer implementation (GodotSteam's SteamMultiplayerPeer, or a custom
##    [MultiplayerPeerExtension] over ISteamNetworkingMessages). If replacing
##    this stub requires changing anything outside this file, the seam was
##    drawn in the wrong place and the fix is here, not there.
## 2. [b]Peer id 1 is the host.[/b] [constant NetTransport.AUTHORITY_PEER_ID]
##    is assumed by every [code]rpc_id[/code] call in this directory. A backend
##    that numbers peers by Steam id must map the host to 1 and keep a
##    stable, session-lifetime id for everyone else. Ids must not be reused
##    within a session.
## 3. [b]Authority is bound at host time and never moves.[/b] The tower seat
##    changes hands whenever a prisoner scores; the host does not. Nothing in a
##    Steam backend may re-elect an authority in response to a lobby-owner
##    change, and no Steam lobby callback may be wired to
##    [method Node.set_multiplayer_authority].
## 4. [b]Initialise Steam before hosting or joining, and fail cleanly when it
##    is absent.[/b] [method host] and [method join] must return an error, set
##    [constant NetTransport.ConnectionState.FAILED] and leave the game
##    playable rather than aborting, when the client is not running, the user
##    is not logged in, or the app id is wrong.
## 5. [b]Pump the Steam callbacks every frame[/b] (Steamworks
##    [code]run_callbacks()[/code]) from [method Node._process] here. The
##    high-level API polls the peer, but it does not pump Steamworks, and the
##    peer will never see a connection request if nobody does.
## 6. [b]Join by identity, not address.[/b] [method join]'s [param address] is a
##    lobby id or a Steam id rendered as a string, and [param port] is
##    meaningless -- accept it and ignore it, so the interface stays one
##    interface. Steam invites and the "join game" flow arrive as callbacks,
##    which this class turns into the same [method join] call.
## 7. [b]Emit the same signals in the same order[/b] as [ENetTransport]:
##    CONNECTING on a join attempt, CONNECTED on the handshake completing,
##    [signal NetTransport.peer_connected] per peer, FAILED on the host
##    vanishing, and a [signal NetTransport.peer_disconnected] for
##    [constant NetTransport.AUTHORITY_PEER_ID] with it. Order is part of the
##    contract; [NetSession] is written against it.
## 8. [b]Free the session on [method leave] and on tree exit[/b] -- close the
##    relay connections and leave the Steam lobby. A leaked lobby is visible to
##    other players and outlives the process.
##
## Verifying it is not optional either: the loopback check under
## tools/_scratch/ tests [ENetTransport] in one process, and no equivalent is
## possible here (two Steam sessions need two logged-in accounts). The real
## backend needs a two-machine manual test, written down, before it is trusted.

const NOT_IMPLEMENTED: String = (
	"SteamTransport is a stub: there is no Steam app id and no Steamworks "
	+ "binding installed. Use ENetTransport for development, bot matches and CI. "
	+ "See scripts/net/steam_transport.gd for what a real backend must satisfy."
)


func backend_name() -> String:
	return "Steam(stub)"


func host(_port: int, _max_players: int = MAX_PLAYERS) -> Error:
	push_error(NOT_IMPLEMENTED)
	_set_state(ConnectionState.FAILED)
	return ERR_UNAVAILABLE


func join(_address: String, _port: int) -> Error:
	push_error(NOT_IMPLEMENTED)
	_set_state(ConnectionState.FAILED)
	return ERR_UNAVAILABLE


func leave() -> void:
	# Deliberately silent and deliberately not FAILED. Tearing down a session
	# that never existed is not an error, and shutdown paths call this
	# unconditionally.
	_set_state(ConnectionState.OFFLINE)


func get_local_peer_id() -> int:
	return 0


## Always false. A stub that reported authority would let a match start on a
## backend that cannot carry a single packet.
func is_authority() -> bool:
	return false
