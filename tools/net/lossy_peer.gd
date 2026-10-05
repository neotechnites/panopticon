class_name LossyPeer
extends MultiplayerPeerExtension

## Harness-only network conditioner (Source's net_fakeloss / net_fakelag): wraps a real peer,
## drops a fraction of outgoing unreliable packets and holds every outgoing packet delay_ms.

var _real: MultiplayerPeer = null
var _loss: float = 0.0
var _target: int = 0
var _channel: int = 0
var _mode: TransferMode = TRANSFER_MODE_RELIABLE
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _delay_ms: int = 0
## Held packets, in send order: [due_ms, target, channel, mode, bytes].
var _held: Array[Array] = []
## Unreliable packets this machine tried to send, and how many of them it dropped.
var sent: int = 0
var dropped: int = 0


func _init(real: MultiplayerPeer, loss: float, rng_seed: int = 1, delay_ms: int = 0) -> void:
	_real = real
	_loss = loss
	_delay_ms = delay_ms
	_rng.seed = rng_seed
	_real.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
	_real.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _mode != TRANSFER_MODE_RELIABLE:
		sent += 1
		if _rng.randf() < _loss:
			dropped += 1
			return OK
	if _delay_ms > 0:
		_held.append([Time.get_ticks_msec() + _delay_ms, _target, _channel, _mode, buffer])
		return OK
	return _send(_target, _channel, _mode, buffer)


func _send(target: int, channel: int, mode: TransferMode, buffer: PackedByteArray) -> Error:
	_real.set_target_peer(target)
	_real.transfer_channel = channel
	_real.transfer_mode = mode
	return _real.put_packet(buffer)


func _get_packet_script() -> PackedByteArray:
	return _real.get_packet()


func _get_available_packet_count() -> int:
	return _real.get_available_packet_count()


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
	var now: int = Time.get_ticks_msec()
	while not _held.is_empty() and int(_held[0][0]) <= now:
		var packet: Array = _held.pop_front()
		_send(int(packet[1]), int(packet[2]), packet[3] as TransferMode, packet[4] as PackedByteArray)
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
