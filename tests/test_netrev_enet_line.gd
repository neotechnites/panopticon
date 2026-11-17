extends NetPowerRig

## The host's declared bandwidth: as shipped a joining client's intents all arrive. With `undo` the
## host is put back to what ENetMultiplayerPeer.create_server left (incoming bandwidth = channels + 2);
## that half is a by-hand A/B (242 of 300 arrive on 4.7.2), not a test, since it asserts an engine bug.

func _count(undo: bool, label: String) -> void:
	await until(func() -> bool: return Time.get_ticks_msec() > 2500, 3000)
	if undo:
		host.connection_state_changed.connect(func(state: NetTransport.ConnectionState) -> void:
			if state == NetTransport.ConnectionState.HOSTING:
				var enet: ENetMultiplayerPeer = host.transport.get(&"_peer")
				enet.host.bandwidth_limit(ENetTransport.ENET_CHANNEL_COUNT + 2, 0))
	if not await stand_up():
		return
	var arrived: Array[int] = [0]
	host_links[A_SEAT].intent_received.connect(func(_peer: int, _tick: int) -> void: arrived[0] += 1)
	var enet_a: ENetMultiplayerPeer = a.transport.get(&"_peer")
	var to_host: ENetPacketPeer = enet_a.get_peer(1)
	var low: int = 99
	var low_limit: int = 99
	for _tick: int in 300:
		await step_ticks(1)
		low = mini(low, int(to_host.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)))
		low_limit = mini(low_limit, int(to_host.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT)))
	print("PROOF %s: of 300 ticks the host received %d; client throttle low %d, limit low %d (of 32)" % [label, arrived[0], low, low_limit])
	if undo:
		assert_true(arrived[0] < 295, "with line 99 undone the loss returns: %d of 300" % arrived[0])
		assert_eq_int(low_limit, 1, "and the client's throttle limit is cut to 1/32")
	else:
		assert_ge(float(arrived[0]), 295.0, "at HEAD the host received")
		assert_eq_int(low_limit, 32, "and the client's throttle limit never left 32")


func test_head_as_shipped() -> void:
	await _count(false, "HEAD")

