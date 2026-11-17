extends NetPowerRig

## Review suspects (presses on a bad line), each run here to prove or clear it.

const NONE: int = MatchRules.RunnerAbility.NONE
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM


## Two different power keys inside one burst of loss: the host owes both presses, each as its own key.
func test_two_power_keys_inside_one_blackout_run_as_the_keys_they_were() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(1)
	@warning_ignore("missing_await")
	black_out(a_wire, 12)
	await step_ticks(2)
	a_keys.tap_slot(SHIELD)
	await step_ticks(6)
	a_keys.tap_slot(HOLOGRAM)
	await step_ticks(1)
	var predicted: int = int(power_of(a_links, A_SEAT).get_active())
	await step_ticks(5)
	var settled: bool = await until(func() -> bool: return drawn(A_SEAT)[0] != NONE)
	await step_ticks(20)
	print("PROOF two-keys: A predicted %d; after the blackout host/A/B draw %s (shield=%d hologram=%d)" % [
		predicted, str(drawn(A_SEAT)), SHIELD, HOLOGRAM])
	assert_true(settled, "the host ran a power")
	assert_eq_int(predicted, SHIELD, "A's own machine ran the first key it pressed")
	assert_eq_int(drawn(A_SEAT)[0], SHIELD, "and so did the host")
	assert_eq_int(drawn(A_SEAT)[1], SHIELD, "which A still draws")


## The emote toggled on then off inside one burst of loss: the wire says where A's toggle stands, so
## the host, which heard neither tap, never has it up, and A's own body is never put back up.
func test_an_emote_put_up_and_down_inside_a_blackout_ends_down_everywhere() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	@warning_ignore("missing_await")
	black_out(a_wire, 14)
	await step_ticks(2)
	a_keys.tap(&"emote_pressed")
	await step_ticks(6)
	assert_true(mine.is_emoting(), "A's own emote is up on its own machine")
	a_keys.tap(&"emote_pressed")
	await step_ticks(2)
	assert_false(mine.is_emoting(), "and down again on the second tap")
	var came_back: int = 0
	var copy: PlayerController = body_of(host_links, A_SEAT)
	var host_up: int = 0
	for _tick: int in 60:
		await step_ticks(1)
		if mine.is_emoting():
			came_back += 1
		if copy.is_emoting():
			host_up += 1
	print("PROOF emote-flicker: in the second after, A's own emote was up on %d ticks; the host's copy on %d" % [came_back, host_up])
	assert_eq_int(host_up, 0, "the host's copy is never up for an emote it did not see go up")
	assert_eq_int(came_back, 0, "and A's own body is never put back up")
	assert_false(mine.is_emoting(), "and it ends down on A's machine")
	assert_false(copy.is_emoting(), "and on the host")


## One emote tap inside a burst of loss: once up on A's machine it stays up while the host catches up.
func test_an_emote_put_up_inside_a_blackout_does_not_drop() -> void:
	if not await stand_up(0.0, 1):
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	@warning_ignore("missing_await")
	black_out(a_wire, 8)
	await step_ticks(2)
	a_keys.tap(&"emote_pressed")
	await step_ticks(2)
	assert_true(mine.is_emoting(), "A's own emote is up on its own machine")
	var dropped: int = 0
	for _tick: int in 60:
		await step_ticks(1)
		if not mine.is_emoting():
			dropped += 1
	var copy: PlayerController = body_of(host_links, A_SEAT)
	print("PROOF emote-drop: in the second after, A's own emote was down on %d ticks; host copy emoting=%s" % [dropped, str(copy.is_emoting())])
	assert_eq_int(dropped, 0, "the emote never drops on the machine that started it")
	assert_true(copy.is_emoting(), "and the host has it up")


## The slot of the power press before the newest rides the intent beside every other field.
func test_the_prior_press_slot_survives_the_intent_round_trip() -> void:
	var sent: MoveIntent = MoveIntent.new()
	sent.shove_pressed = true
	sent.aim_held = true
	sent.cook_pressed = true
	sent.emote_pressed = true
	sent.emote_alt_pressed = true
	sent.ability_slot = 2
	sent.press_slot = 2
	sent.press_slot_prior = 5
	var intents: Array[MoveIntent] = [sent]
	var got: MoveIntent = MoveIntent.new()
	var payload: PackedByteArray = NetCodec.pack_intents(7, intents, 1, 1)
	assert_eq_int(payload.size(), NetCodec.INTENT_SIZE, "the intent is no bigger for it")
	assert_eq_int(NetCodec.unpack_intent_at(payload, 0, got), 7, "it decodes")
	assert_eq_int(got.press_slot_prior, 5, "the prior slot")
	assert_eq_int(got.press_slot, 2, "the newest slot")
	assert_eq_int(got.ability_slot, 2, "this tick's slot")
	assert_true(got.shove_pressed and got.aim_held and got.cook_pressed and got.emote_pressed and got.emote_alt_pressed, "and the flags it shares a byte with")
	sent.press_slot_prior = 0
	sent.emote_alt_pressed = false
	NetCodec.unpack_intent_at(NetCodec.pack_intents(8, intents, 1, 1), 0, got)
	assert_eq_int(got.press_slot_prior, 0, "none")
	assert_false(got.emote_alt_pressed, "and no flag made of it")
