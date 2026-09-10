class_name NetSession
extends Node

## The lobby: one transport, the list of who is in it, and the answer to "am I
## the authority".
##
## Everything above the transport talks to this and not to [NetTransport]
## directly. It exists so that swapping [ENetTransport] for [SteamTransport] is
## one exported reference and no other change, and so there is exactly one
## object in the tree that knows the roster.
##
## [b]Authority[/b]
##
## [method get_authority_peer_id] is [constant NetTransport.AUTHORITY_PEER_ID],
## always, for the whole life of the session. It is a method rather than a
## constant reference at each call site because that is the line callers must
## not cross: the tower seat moves between players constantly -- a prisoner who
## reaches the end takes it and the round restarts -- and the host does not
## move with it. Anything that wants to know who is in the tower asks the match
## layer. Anything that wants to know where to send a packet asks this.
##
## [b]What this is not[/b]
##
## No lobby UI, no matchmaking, no chat, no reconnect, no host migration, and
## no ready-up. A session is created, played and destroyed.

## A peer joined. On the authority, one per client. On a client, one for the
## authority and one for each other client already present.
signal peer_joined(peer_id: int)

## A peer left. On a client, the authority leaving is the end of the session.
signal peer_left(peer_id: int)

## The session's state changed. Forwarded verbatim from the transport.
signal connection_state_changed(state: NetTransport.ConnectionState)

## The session became usable -- hosting, or a join that completed. The hook for
## the match layer to spawn bodies.
signal session_established()

## The session ended, gracefully or by losing the host. [param failed] is true
## when it was not this machine's choice.
signal session_ended(failed: bool)

## The backend. Assign an [ENetTransport] for development, bot matches and CI;
## a [SteamTransport] for shipping, once one exists.
##
## Nothing else in the game may hold a reference to a transport. Route through
## this node instead, or the day the backend changes there are two places to
## change it and one of them will be missed.
@export var transport: NetTransport

## Everyone in the session, this machine included, in join order with the
## authority first. Rebuilt from transport signals, never from the multiplayer
## API's own list, so a backend that numbers peers differently only has to
## satisfy the [NetTransport] contract.
var _peers: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	if transport == null:
		push_error("NetSession has no transport; it can neither host nor join.")
		return
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.connection_state_changed.connect(_on_connection_state_changed)


## Become the listen server. [param max_players] counts this machine: matches
## run 1v1 to 1v7, so 2 to [constant NetTransport.MAX_PLAYERS].
func host(port: int, max_players: int = NetTransport.MAX_PLAYERS) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	return transport.host(port, max_players)


## Join a session. [param address] is an IP or hostname for [ENetTransport]; a
## lobby or Steam id for a Steam backend, where [param port] is ignored.
func join(address: String, port: int) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	return transport.join(address, port)


## Leave, whether hosting or joined. Safe to call when there is no session.
func leave() -> void:
	if transport == null:
		return
	transport.leave()


## True when this machine simulates the match: hosting, or offline. See
## [method NetTransport.is_authority] -- offline counts, so single-player and
## the headless bot harness need no special case.
func is_authority() -> bool:
	return transport != null and transport.is_authority()


## The peer that simulates the match, for the life of the session. Never the
## tower.
func get_authority_peer_id() -> int:
	return NetTransport.AUTHORITY_PEER_ID


## This machine's peer id, or 0 when offline.
func get_local_peer_id() -> int:
	return transport.get_local_peer_id() if transport != null else 0


## True when [param peer_id] is this machine.
func is_local_peer(peer_id: int) -> bool:
	return peer_id != 0 and peer_id == get_local_peer_id()


## Everyone in the session, including this machine. A copy: mutating it does
## not change the roster.
func get_peer_ids() -> PackedInt32Array:
	return _peers.duplicate()


## How many are in the session.
func get_peer_count() -> int:
	return _peers.size()


func has_peer(peer_id: int) -> bool:
	return _peers.has(peer_id)


func get_connection_state() -> NetTransport.ConnectionState:
	return transport.get_connection_state() if transport != null else NetTransport.ConnectionState.OFFLINE


## True once traffic can flow, hosting or joined alike.
func is_established() -> bool:
	return transport != null and transport.is_established()


## One line, for logs and the harness.
func describe() -> String:
	if transport == null:
		return "NetSession(no transport)"
	return "NetSession(%s, peers=%s)" % [transport.describe(), str(_peers)]


# --- Roster -------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if _peers.has(peer_id):
		return
	_peers.append(peer_id)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var index: int = _peers.find(peer_id)
	if index == -1:
		return
	_peers.remove_at(index)
	peer_left.emit(peer_id)


func _on_connection_state_changed(state: NetTransport.ConnectionState) -> void:
	match state:
		NetTransport.ConnectionState.HOSTING:
			# The host is peer 1 and is in its own session from the first
			# frame; there is no handshake with itself to wait for.
			_peers = PackedInt32Array([NetTransport.AUTHORITY_PEER_ID])
			connection_state_changed.emit(state)
			session_established.emit()
			return
		NetTransport.ConnectionState.CONNECTED:
			# peer_connected(1) may or may not have arrived first depending on
			# the backend, so add both ends explicitly and let the has() guard
			# in _on_peer_connected absorb the duplicate.
			var local_id: int = get_local_peer_id()
			if not _peers.has(NetTransport.AUTHORITY_PEER_ID):
				_peers.append(NetTransport.AUTHORITY_PEER_ID)
			if local_id != 0 and not _peers.has(local_id):
				_peers.append(local_id)
			connection_state_changed.emit(state)
			session_established.emit()
			return
		NetTransport.ConnectionState.OFFLINE:
			_peers = PackedInt32Array()
			connection_state_changed.emit(state)
			session_ended.emit(false)
			return
		NetTransport.ConnectionState.FAILED:
			_peers = PackedInt32Array()
			connection_state_changed.emit(state)
			session_ended.emit(true)
			return
	connection_state_changed.emit(state)
