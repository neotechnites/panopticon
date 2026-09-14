class_name ENetTransport
extends NetTransport

## [NetTransport] over raw UDP, using [ENetMultiplayerPeer] and Godot's
## high-level multiplayer API.
##
## This is the development, headless-bot and CI backend, and its one
## non-negotiable property is that it works with [b]no Steam client running at
## all[/b]. The bot harness is how this project answers design questions, and a
## harness that cannot start without a storefront logged in is a harness that
## does not run on CI, does not run on a fresh machine and eventually does not
## run at all. Nothing in this file may ever grow a dependency on
## [SteamTransport].
##
## It also ships as a usable LAN backend. What it is not is a public-internet
## backend: it needs a reachable address, which means port forwarding, and it
## shows the host's IP to everyone who joins. Both are [SteamTransport]'s job.
##
## [b]Multiplayer API binding[/b]
##
## The peer is installed on [member Node.multiplayer], which is the
## [MultiplayerAPI] that owns this node's branch of the tree -- normally the
## scene tree's default one. A test or tool that wants two independent sessions
## inside one process gives each branch its own API with
## [method SceneTree.set_multiplayer] and puts one of these under each; this
## file needs no special case for it, and tools/_scratch/net_loopback_check.gd
## does exactly that.

## Port used when nothing else is specified. Unassigned by IANA, and outside
## the ephemeral range macOS and Linux hand out, so a host will not fight a
## random outbound socket for it.
const DEFAULT_PORT: int = 27960

## ENet channels to open on the socket, at both ends.
##
## [b]This must be set, and the default of zero is a trap.[/b] An ENet peer
## created with no explicit channel count opens only the three Godot uses for
## its own transfer modes, and every packet an [code]@rpc[/code] sends on a
## custom channel is then dropped by the sender with
## [code]Unable to send packet on channel N, max channels: 0[/code] on stderr
## and no failure anywhere a script can see. The session connects, the lobby
## replicates on channel 0, and movement silently never arrives -- which reads
## as a bug in the replication code rather than as a socket that was never
## opened wide enough.
##
## Godot numbers a custom channel [code]n[/code] as ENet channel
## [code]n + 2[/code], after the three it reserves, so the count is
## [constant NetTransport.MAX_RPC_CHANNEL] + 3. Host and client must agree: a
## mismatch is a connection that establishes and then loses packets in one
## direction only.
const ENET_CHANNEL_COUNT: int = NetTransport.MAX_RPC_CHANNEL + 3

## Retransmissions of one reliable packet before ENet starts counting against
## the timeout window. ENet's own default; it is the window that this project
## shortens, not the persistence.
const TIMEOUT_RETRANSMISSIONS: int = 32

## Largest payload this project puts in one packet, in bytes.
##
## Every path worth playing on carries a 1200 byte datagram without
## fragmenting, and a fragmented UDP datagram is lost whole when any one of its
## fragments is. The snapshot -- the only per-tick message whose size grows with
## the player count -- is about 210 bytes at the full eight, so the headroom is
## a factor of five and the number is here to be asserted against rather than
## approached.
const SAFE_PAYLOAD_BYTES: int = 1200

## The peer currently installed on the multiplayer API, or null when offline.
var _peer: ENetMultiplayerPeer = null

## Whether this node's handlers are attached to the multiplayer API. Bound at
## host/join and released at leave, so a transport that is offline is not
## holding connections to an API another branch of the tree may be using.
var _bound: bool = false


func backend_name() -> String:
	return "ENet"


func host(port: int, max_players: int = MAX_PLAYERS) -> Error:
	leave()

	var players: int = clampi(max_players, 1, MAX_PLAYERS)
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	# create_server() counts clients, not players: the listen server is not one
	# of its own clients.
	var error: Error = peer.create_server(port, players - 1, ENET_CHANNEL_COUNT)
	if error != OK:
		push_error("ENetTransport could not host on port %d: %s" % [port, error_string(error)])
		_set_state(ConnectionState.FAILED)
		return error

	_bind()
	_peer = peer
	_apply_compression(peer)
	multiplayer.multiplayer_peer = peer
	_set_state(ConnectionState.HOSTING)
	return OK


func join(address: String, port: int) -> Error:
	leave()

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port, ENET_CHANNEL_COUNT)
	if error != OK:
		push_error("ENetTransport could not reach %s:%d: %s" % [address, port, error_string(error)])
		_set_state(ConnectionState.FAILED)
		return error

	_bind()
	_peer = peer
	_apply_compression(peer)
	multiplayer.multiplayer_peer = peer
	# CONNECTING, not CONNECTED: create_client() only opens a socket. The
	# handshake completes some frames later, on connected_to_server, and until
	# it does an rpc_id() to the authority goes nowhere.
	_set_state(ConnectionState.CONNECTING)
	return OK


func leave() -> void:
	_teardown()
	_set_state(ConnectionState.OFFLINE)


func abort() -> void:
	# Overridden rather than inherited so that a timed-out join passes through
	# exactly one state change. The base class's leave()-then-fail would emit
	# OFFLINE first, and NetSession turns OFFLINE into session_ended(false) --
	# a clean shutdown, reported a frame before the failure that actually
	# happened.
	_teardown()
	_set_state(ConnectionState.FAILED)


func take_wire_stats() -> Dictionary:
	if _peer == null or _peer.host == null:
		return {}
	var host: ENetConnection = _peer.host
	return {
		"sent_bytes": int(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)),
		"received_bytes": int(host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)),
		"sent_packets": int(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)),
		"received_packets": int(host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)),
	}


func get_local_peer_id() -> int:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func kick_peer(peer_id: int) -> void:
	if _peer == null or get_connection_state() != ConnectionState.HOSTING:
		return
	# now = false: the queued disconnect lets ENet deliver the packets already
	# in flight and gives the far end a real disconnect rather than a silence
	# it has to time out. peer_disconnected arrives from the API as usual, so
	# the roster unwinds down the same path a voluntary leave does.
	_peer.disconnect_peer(peer_id, false)


func _exit_tree() -> void:
	# A transport removed from the tree has no API to poll it, so a peer left
	# installed here is a socket nobody services.
	leave()


# --- Multiplayer API handlers -------------------------------------------------

## Release the socket and the API, without deciding what state that leaves the
## transport in. Every path out of a live session goes through here; only the
## caller knows whether what happened was a shutdown or a failure.
func _teardown() -> void:
	_unbind()
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null


func _bind() -> void:
	if _bound or multiplayer == null:
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_bound = true


func _unbind() -> void:
	if not _bound or multiplayer == null:
		_bound = false
		return
	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	multiplayer.connection_failed.disconnect(_on_connection_failed)
	multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	_bound = false


## Compress every packet, if the settings ask for it.
##
## [b]Both ends or neither.[/b] A host that compresses and a client that does not
## share a connection that establishes and then reads rubbish, so this is driven
## from one field of [NetSettings] and applied identically on both sides. The
## range coder is the right one of ENet's choices here: the snapshot is eight
## near-identical records of quantised integers, which is the case an adaptive
## entropy coder is built for, and it costs microseconds.
func _apply_compression(peer: ENetMultiplayerPeer) -> void:
	if peer.host == null:
		return
	peer.host.compress(
		ENetConnection.COMPRESS_RANGE_CODER if get_settings().compress_traffic
		else ENetConnection.COMPRESS_NONE
	)


## Stop waiting for a peer that has gone silent, rather than ENet's own default.
##
## ENet gives a dead peer up to thirty seconds before it calls it gone. In a 1v1
## that is half a minute of a player standing in an empty ring waiting for
## somebody whose line died. The three numbers ENet wants are a retransmission
## limit and a floor and ceiling in milliseconds; the ceiling is what actually
## decides, and the floor is set to a quarter of it so a brief stall is not a
## disconnection.
func _apply_timeout(peer_id: int) -> void:
	if _peer == null:
		return
	var packet_peer: ENetPacketPeer = _peer.get_peer(peer_id)
	if packet_peer == null:
		return
	var ceiling_ms: int = int(get_settings().peer_timeout_seconds * 1000.0)
	packet_peer.set_timeout(TIMEOUT_RETRANSMISSIONS, ceiling_ms / 4, ceiling_ms)


func _on_peer_connected(peer_id: int) -> void:
	_apply_timeout(peer_id)
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	_apply_timeout(AUTHORITY_PEER_ID)
	_set_state(ConnectionState.CONNECTED)


func _on_connection_failed() -> void:
	# FAILED rather than OFFLINE, so is_authority() stays false: a client that
	# could not reach the host is not a host.
	_teardown()
	_set_state(ConnectionState.FAILED)


func _on_server_disconnected() -> void:
	# The authority is gone and the session is over. There is no host
	# migration: promoting a client would mean handing it a world it never
	# simulated, and no amount of state transfer makes the round it interrupts
	# fair. The match ends.
	_teardown()
	_set_state(ConnectionState.FAILED)
	peer_disconnected.emit(AUTHORITY_PEER_ID)
