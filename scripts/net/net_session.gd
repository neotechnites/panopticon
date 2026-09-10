class_name NetSession
extends Node

## The session: one transport, the list of who is in it, the settings
## everything below runs on, and the answer to "am I the authority".
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
## [b]Three nodes, three jobs[/b]
##
## The session scene composes this node with its backend and its two consumers,
## and the split is worth stating because it is what keeps each of them small:
##
## - [NetTransport] -- sockets. Who is connected, and nothing about the game.
## - [NetLobby] -- who is playing, in which seat, and whether the match may
##   start.
## - [NetReplicator] -- the per-tick traffic: intent up, snapshots down.
##
## [b]What this is not[/b]
##
## No matchmaking, no chat, no reconnect and no host migration. A session is
## created, played and destroyed.

## A peer joined. On the authority, one per client. On a client, one for the
## authority and one for each other client already present.
signal peer_joined(peer_id: int)

## A peer left. On a client, the authority leaving is the end of the session.
signal peer_left(peer_id: int)

## The session's state changed. Forwarded verbatim from the transport.
signal connection_state_changed(state: NetTransport.ConnectionState)

## The session became usable -- hosting, or a join that completed. The hook for
## the lobby to open and the match layer to spawn bodies.
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

## Ports, rates and timeouts. Optional in the sense that the session builds a
## default rather than refusing to run -- but a session sharing one settings
## resource with its lobby and its replicator is the point, so leave it wired.
@export var settings: NetSettings

## The seat table and the match-flow state machine. Optional: a tool or a test
## that only wants a socket does not need one.
@export var lobby: NetLobby

## The per-tick traffic pump. Optional for the same reason as [member lobby].
@export var replicator: NetReplicator

## Everyone in the session, this machine included, in join order with the
## authority first. Rebuilt from transport signals, never from the multiplayer
## API's own list, so a backend that numbers peers differently only has to
## satisfy the [NetTransport] contract.
var _peers: PackedInt32Array = PackedInt32Array()

## When the join in flight started, from [method Time.get_ticks_msec], or -1
## when none is.
##
## [b]Wall clock, deliberately.[/b] See
## [member NetSettings.connect_timeout_seconds]: the headless test runner
## compresses simulated time fiftyfold and a socket has not heard about it.
var _connect_started_ms: int = -1


func _ready() -> void:
	if settings == null:
		# A default rather than a refusal: every field on it has a shipping
		# value, and a session that will not start because nobody wired a
		# resource is a worse failure than one that starts on the defaults.
		settings = NetSettings.new()
	if transport == null:
		push_error("NetSession has no transport; it can neither host nor join.")
		set_process(false)
		return
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.connection_state_changed.connect(_on_connection_state_changed)


func _process(_delta: float) -> void:
	if _connect_started_ms < 0:
		return
	if get_connection_state() != NetTransport.ConnectionState.CONNECTING:
		_connect_started_ms = -1
		return
	var elapsed_ms: int = Time.get_ticks_msec() - _connect_started_ms
	if elapsed_ms < int(settings.connect_timeout_seconds * 1000.0):
		return
	# Not push_error: a host who is not home is an ordinary outcome of pressing
	# Join, and the UI's job to report. FAILED rather than OFFLINE, so nothing
	# downstream mistakes an unreachable host for single player.
	_connect_started_ms = -1
	transport.abort()


## Become the listen server. [param port] and [param max_players] default to
## [member settings]; [param max_players] counts this machine, so matches run 2
## to [constant NetTransport.MAX_PLAYERS].
func host(port: int = -1, max_players: int = -1) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	var listen_port: int = port if port > 0 else settings.port
	var players: int = max_players if max_players > 0 else settings.get_effective_max_players()
	return transport.host(listen_port, players)


## Join a session. [param address] is an IP or hostname for [ENetTransport]; a
## lobby or Steam id for a Steam backend, where [param port] is ignored.
func join(address: String, port: int = -1) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	var error: Error = transport.join(address, port if port > 0 else settings.port)
	if error == OK:
		_connect_started_ms = Time.get_ticks_msec()
	return error


## Leave, whether hosting or joined. Safe to call when there is no session.
func leave() -> void:
	_connect_started_ms = -1
	if transport == null:
		return
	transport.leave()


## Disconnect a peer. Authority only, and a no-op anywhere else -- a client
## cannot throw anybody out of somebody else's game.
##
## The lobby uses this for a peer that connected with nowhere to sit. There is
## no vote, no ban list and no reason string on the wire: the peer simply sees
## the host go away, which is honest enough for a game where the host IS the
## server.
func kick_peer(peer_id: int) -> void:
	if transport == null or not is_authority() or peer_id == NetTransport.AUTHORITY_PEER_ID:
		return
	transport.kick_peer(peer_id)


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


## The settings this session and everything under it runs on. Never null after
## [method Node._ready]; see there for why a default is built rather than
## demanded.
func get_settings() -> NetSettings:
	if settings == null:
		settings = NetSettings.new()
	return settings


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
			_connect_started_ms = -1
			_peers = PackedInt32Array([NetTransport.AUTHORITY_PEER_ID])
			connection_state_changed.emit(state)
			session_established.emit()
			return
		NetTransport.ConnectionState.CONNECTED:
			# peer_connected(1) may or may not have arrived first depending on
			# the backend, so add both ends explicitly and let the has() guard
			# in _on_peer_connected absorb the duplicate.
			_connect_started_ms = -1
			var local_id: int = get_local_peer_id()
			if not _peers.has(NetTransport.AUTHORITY_PEER_ID):
				_peers.append(NetTransport.AUTHORITY_PEER_ID)
			if local_id != 0 and not _peers.has(local_id):
				_peers.append(local_id)
			connection_state_changed.emit(state)
			session_established.emit()
			return
		NetTransport.ConnectionState.OFFLINE:
			_connect_started_ms = -1
			_peers = PackedInt32Array()
			connection_state_changed.emit(state)
			session_ended.emit(false)
			return
		NetTransport.ConnectionState.FAILED:
			_connect_started_ms = -1
			_peers = PackedInt32Array()
			connection_state_changed.emit(state)
			session_ended.emit(true)
			return
	connection_state_changed.emit(state)
