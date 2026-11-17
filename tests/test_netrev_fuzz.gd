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
	var link: PlayerNetLink = host_links[A_SEAT]
	var a_id: int = a.get_local_peer_id()
	var scratch: MoveIntent = MoveIntent.new()
	var decoded: int = 0
	# Pure decode: every size from 0 to 140, random content, and well-formed sizes with hostile content.
	for round_index: int in 4000:
		var size: int = rng.randi_range(0, 140)
		if round_index % 3 == 0:
			size = NetCodec.INTENT_HEADER_SIZE + rng.randi_range(1, 4) * NetCodec.INTENT_BODY_SIZE
		var payload: PackedByteArray = _random_bytes(rng, size)
		if round_index % 3 == 0 and size > 6:
			payload[6] = (size - NetCodec.INTENT_HEADER_SIZE) / NetCodec.INTENT_BODY_SIZE
		for index: int in range(-1, 6):
			if NetCodec.unpack_intent_at(payload, index, scratch) >= 0:
				decoded += 1
				assert_true(scratch.move_direction.is_finite() and scratch.view_angles.is_finite(), "a decoded intent is finite")
				assert_true(scratch.ability_slot >= 0 and scratch.ability_slot <= 5 and scratch.press_slot >= 0 and scratch.press_slot <= 5, "slots are in range")
				assert_true(scratch.press_counts >= 0 and scratch.press_counts <= MoveIntent.PRESS_COUNTS_MASK, "press counts are masked")
		NetCodec.intent_epoch(payload)
	# Through the host's real accept path, with the right epoch stamped so the bodies are reached.
	var epoch: int = host.replicator.get_scene()
	var accepted: int = 0
	for tick: int in 400:
		for _n: int in 4:
			var count: int = rng.randi_range(1, 4)
			var payload: PackedByteArray = _random_bytes(rng, NetCodec.INTENT_HEADER_SIZE + count * NetCodec.INTENT_BODY_SIZE)
			payload.encode_u32(0, 100000 + tick * 4 + _n)
			payload.encode_u16(4, epoch)
			payload[6] = count
			link.accept_intent_payload(a_id, payload)
			accepted += 1
		await step_ticks(1)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	print("PROOF fuzz: %d random intents decoded, %d hostile packets through accept; host copy at %s vel %s" % [decoded, accepted, str(copy.global_position), str(copy.velocity)])
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
