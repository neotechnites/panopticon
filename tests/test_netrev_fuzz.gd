extends NetPowerRig

## Review: hostile bytes into every decode path a client can reach on the host, and the
## client-side decoders too. A script error anywhere shows in the log; the bodies must stay finite.


func _random_bytes(rng: RandomNumberGenerator, size: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(size)
	for i: int in size:
		out[i] = rng.randi() & 0xFF
	return out


func test_rv_fuzz_intent_decode_and_accept() -> void:
	if not await stand_up():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 794
	var a_id: int = a.get_local_peer_id()
	var scratch: Array[MoveIntent] = []
	for _i: int in NetCodec.MAX_COMMANDS:
		scratch.append(MoveIntent.new())
	var decoded: int = 0
	# Pure decode: every size from 0 to 140, random content, and real headers over hostile commands.
	for round_index: int in 4000:
		var size: int = rng.randi_range(0, 140)
		var payload: PackedByteArray = _random_bytes(rng, size)
		if round_index % 3 == 0 and size > NetCodec.COMMAND_HEADER_SIZE:
			payload[6] = rng.randi_range(1, NetCodec.MAX_COMMANDS)
		var count: int = NetCodec.unpack_commands(payload, scratch, rng.randi_range(-1, 1000))
		decoded += count
		for i: int in count:
			var got: MoveIntent = scratch[i]
			assert_true(got.move_direction.is_finite() and got.view_angles.is_finite() and (is_finite(got.view_time) or got.view_time == MoveIntent.LIVE_WORLD), "a decoded command is finite")
			assert_true(got.move_direction.length() <= 1.0001, "its move is in the unit disc")
			assert_true(got.buttons == (got.buttons & MoveIntent.BUTTON_MASK) and got.pressed == 0, "its levels are masked and it carries no edge")
		NetCodec.command_epoch(payload)
		NetCodec.command_snap_ack(payload)
	# Through the host's real receive path, with the right epoch stamped so the bodies are reached.
	var epoch: int = host.replicator.get_scene()
	var accepted: int = 0
	for tick: int in 400:
		for _n: int in 4:
			var payload: PackedByteArray = _random_bytes(rng, rng.randi_range(NetCodec.COMMAND_HEADER_SIZE, 140))
			payload.encode_u16(0, epoch)
			payload.encode_u32(2, 100000 + tick * 4 + _n)
			payload[6] = rng.randi_range(1, NetCodec.MAX_COMMANDS)
			host.replicator.take_commands(a_id, payload)
			accepted += 1
		await step_ticks(1)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	print("PROOF fuzz: %d random commands decoded, %d hostile packets through receive; host copy at %s vel %s" % [decoded, accepted, str(copy.global_position), str(copy.velocity)])
	assert_true(copy.global_position.is_finite() and copy.velocity.is_finite(), "the host's copy is still finite")
	assert_true(absf(copy.rotation.x) < 0.001 and is_finite(copy.rotation.y), "and upright")
	if copy.head != null:
		assert_true(absf(copy.head.rotation.x) <= PI / 2.0 + 0.01, "its pitch is clamped: %f" % copy.head.rotation.x)


func test_rv_fuzz_client_side_decoders() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 795
	var snapshot: WorldSnapshot = WorldSnapshot.new()
	var state: PlayerState = PlayerState.new()
	var seats: Array[LobbySeat] = []
	var took: Array[int] = [0, 0, 0]
	for round_index: int in 6000:
		var size: int = rng.randi_range(0, 300)
		if round_index % 2 == 0:
			size = NetCodec.SNAPSHOT_HEADER_SIZE + rng.randi_range(0, 8) * NetCodec.SNAPSHOT_BODY_SIZE
		var payload: PackedByteArray = _random_bytes(rng, size)
		if round_index % 2 == 0 and size >= NetCodec.SNAPSHOT_HEADER_SIZE:
			payload[8] = (size - NetCodec.SNAPSHOT_HEADER_SIZE) / NetCodec.SNAPSHOT_BODY_SIZE
		if NetCodec.unpack_snapshot(payload, snapshot):
			took[0] += 1
			for seat: int in 8:
				var found: PlayerState = snapshot.find_seat(seat)
				if found != null:
					assert_true(found.position.is_finite() and found.velocity.is_finite() and is_finite(found.yaw), "snapshot state finite")
					assert_true(found.shove_counter >= 0 and found.shove_counter < 4 and found.boost_remaining >= 0.0 and found.boost_multiplier >= 0.0, "new fields in range")
		if NetCodec.unpack_decoy_move(_random_bytes(rng, rng.randi_range(0, 24)), state) >= 0:
			took[1] += 1
		if NetCodec.unpack_roster(_random_bytes(rng, rng.randi_range(0, 260)), seats, 24) >= 0:
			took[2] += 1
	print("PROOF fuzz: client decoders took snapshot/decoy/roster %s of 6000 random payloads each" % str(took))
	assert_true(took[0] > 0, "some well-sized snapshots decoded")
