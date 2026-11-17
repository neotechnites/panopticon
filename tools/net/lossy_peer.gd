class_name LossyPeer
extends MultiplayerPeerExtension

## Harness-only network conditioner: wraps a real peer and puts this machine's sends through
## [member conditions], one independent path per remote peer. [method freeze] stops it servicing.

## What this machine's sends go through. Settable live; [method NetConditions.reseed] restarts it.
var conditions: NetConditions = null
## Unreliable packet copies this machine offered the wire, and how many the wire lost.
var sent: int:
	get:
		return int(conditions.stats().get("offered", 0.0))
var dropped: int:
	get:
		return int(conditions.stats().get("lost", 0.0))

var _real: MultiplayerPeer = null
var _target: int = 0
var _channel: int = 0
var _mode: TransferMode = TRANSFER_MODE_RELIABLE
## Remote peers this machine can reach, so a broadcast becomes one independent send per path.
var _peers: Dictionary[int, bool] = {}
var _thaw_ms: float = -1.0
## How often this peer is polled: a packet leaves on the poll nearest its due time, so the frame clock
## spreads delays by half a poll either way instead of adding up to a whole one.
var _poll_every_ms: float = 0.0
var _last_poll_ms: float = -1.0


func _init(real: MultiplayerPeer, loss: float = 0.0, rng_seed: int = 1, delay_ms: int = 0) -> void:
	_real = real
	conditions = NetConditions.new(rng_seed)
	conditions.loss = loss
	conditions.delay_ms = delay_ms
	# Bound methods, not lambdas: a lambda would hold this wrapper alive from its own real peer.
	_real.peer_connected.connect(_on_peer_connected)
	_real.peer_disconnected.connect(_on_peer_disconnected)


## Stop servicing the socket for [param ms]: nothing is read, sent or acknowledged, as in a machine
## stopped by a shader compile or a debugger. Sends made meanwhile leave when it thaws.
func freeze(ms: float) -> void:
	_thaw_ms = maxf(_thaw_ms, _now() + ms)


func is_frozen() -> bool:
	return _now() < _thaw_ms


## The peers this machine's sends can reach, ascending: one conditioned path each.
func reachable_peers() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_peers.keys())
	ids.sort()
	return ids


func _on_peer_connected(id: int) -> void:
	_peers[id] = true
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	_peers.erase(id)
	# What was still in flight to a peer that is gone goes nowhere, as on a real wire.
	conditions.forget(id)
	peer_disconnected.emit(id)


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var reliable: bool = _mode == TRANSFER_MODE_RELIABLE
	var now: float = _now()
	var paths: Array[int] = _paths_for(_target)
	if paths.is_empty():
		# Nobody known to reach yet: the engine's own answer (usually nothing to send to).
		return _send(_target, _channel, _mode, buffer)
	for path: int in paths:
		conditions.push(path, reliable, [path, _channel, _mode, buffer], now)
	if not is_frozen():
		_release(now)
	return OK


## One path per peer a send reaches: the engine's broadcast (0) and exclusion (-id) fanned out.
func _paths_for(target: int) -> Array[int]:
	var paths: Array[int] = []
	if target > 0:
		paths.append(target)
		return paths
	for peer: int in _peers:
		if peer != -target:
			paths.append(peer)
	return paths


func _release(now: float) -> void:
	for packet: Array in conditions.pop_due(now):
		_send(int(packet[0]), int(packet[1]), packet[2] as TransferMode, packet[3] as PackedByteArray)


func _send(target: int, channel: int, mode: TransferMode, buffer: PackedByteArray) -> Error:
	_real.set_target_peer(target)
	_real.transfer_channel = channel
	_real.transfer_mode = mode
	return _real.put_packet(buffer)


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000.0


func _get_packet_script() -> PackedByteArray:
	# The engine names the sender of the packet about to be read, so ask before reading it.
	var from: int = _real.get_packet_peer()
	if from > 0:
		_peers[from] = true
	return _real.get_packet()


func _get_available_packet_count() -> int:
	return 0 if is_frozen() else _real.get_available_packet_count()


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_packet_peer() -> int:
	return _real.get_packet_peer()


func _get_packet_mode() -> TransferMode:
	return _real.get_packet_mode()


func _get_packet_channel() -> int:
	return _real.get_packet_channel()


func _is_server() -> bool:
	return _real.get_unique_id() == 1


func _poll() -> void:
	if is_frozen():
		return
	var now: float = _now()
	if _last_poll_ms >= 0.0:
		_poll_every_ms = lerpf(_poll_every_ms, clampf(now - _last_poll_ms, 0.0, 100.0), 0.1)
	_last_poll_ms = now
	_release(now + 0.5 * _poll_every_ms)
	_real.poll()


func _close() -> void:
	_real.close()


func _disconnect_peer(peer: int, force: bool) -> void:
	_real.disconnect_peer(peer, force)


func _get_unique_id() -> int:
	return _real.get_unique_id()


func _set_refuse_new_connections(enable: bool) -> void:
	_real.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _real.refuse_new_connections


func _is_server_relay_supported() -> bool:
	return _real.is_server_relay_supported()


func _get_connection_status() -> ConnectionStatus:
	return _real.get_connection_status()
