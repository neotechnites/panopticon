extends TestCase
## The MATCH section's record: every field of a [MatchState] survives the wire, and a bad record is refused.


func _state() -> MatchState:
	var state: MatchState = MatchState.new()
	state.tick = 7000
	state.started = true
	state.phase = int(MatchController.Phase.ROUND)
	state.round_number = 4
	state.guard = 2
	state.finisher = 1
	state.winner = MatchState.NONE
	state.outcome = int(MatchController.Outcome.LOSS)
	state.match_serial = 3
	state.resolve_count = 9
	state.last_outcome = int(MatchController.Outcome.WIN)
	state.hold_end_tick = 7600
	state.hold_paused_ticks = 345
	state.kill_beat_serial = 2
	state.kill_beat_guard = 2
	state.kill_beat_throw = Vector3(12.5, -0.25, -3.0)
	state.brawl_end_tick = 0
	state.brawl_winner = 0
	state.resize(4)
	for i: int in 4:
		var entry: MatchState.Entry = state.participants[i]
		entry.running = i == 0
		entry.ghost = i == 1
		entry.held = i == 1
		entry.shooter = i == 2
		entry.finisher = i == 3
		entry.life = 250 + i
		entry.rounds_won = i
		entry.turns_in_tower = i * 2
		entry.lives = 3 - i
		entry.respawn_end_tick = 7180 if i == 1 else 0
		entry.grace_end_tick = 7090 + i
		entry.death_cause = int(MatchParticipant.DeathCause.LAVA)
	return state


func test_every_field_round_trips() -> void:
	var sent: MatchState = _state()
	var bytes: PackedByteArray = NetCodec.pack_match_state(sent)
	assert_eq_int(bytes.size(), NetCodec.MATCH_HEADER_SIZE + 4 * NetCodec.MATCH_PARTICIPANT_SIZE, "the record's size is its layout")
	var got: MatchState = MatchState.new()
	assert_true(NetCodec.unpack_match_state(bytes, sent.tick, got), "a whole record decodes")
	for field: String in [
		"started", "phase", "round_number", "guard", "finisher", "winner", "outcome", "match_serial", "resolve_count",
		"last_outcome", "hold_end_tick", "hold_paused_ticks", "kill_beat_serial", "kill_beat_guard", "brawl_end_tick", "brawl_winner",
	]:
		assert_eq_string(str(got.get(field)), str(sent.get(field)), field)
	assert_vec3_almost_eq(got.kill_beat_throw, sent.kill_beat_throw, 0.006, "the finale's throw")
	for i: int in 4:
		for field: String in [
			"running", "ghost", "shooter", "held", "finisher", "life", "rounds_won", "turns_in_tower", "lives",
			"respawn_end_tick", "grace_end_tick", "death_cause",
		]:
			assert_eq_string(str(got.participants[i].get(field)), str(sent.participants[i].get(field)), "%s of %d" % [field, i])
	assert_almost_eq(got.seconds_to(got.participants[1].respawn_end_tick), 3.0, 0.001, "an end tick reads back as seconds")


func test_a_match_not_started_has_no_record_and_a_bad_one_is_refused() -> void:
	var state: MatchState = _state()
	state.started = false
	assert_eq_int(NetCodec.pack_match_state(state).size(), 0, "nothing to say before the match starts")
	var got: MatchState = MatchState.new()
	assert_false(NetCodec.unpack_match_state(PackedByteArray(), 1, got), "an empty record is no match")
	var bytes: PackedByteArray = NetCodec.pack_match_state(_state())
	bytes.resize(bytes.size() - 1)
	assert_false(NetCodec.unpack_match_state(bytes, 1, got), "a short record is refused")
	assert_false(got.started, "and leaves nothing half read")
