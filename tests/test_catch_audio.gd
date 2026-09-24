extends TestCase

## PLAYER_CATCH_MADE, positional at last.
##
## [method MatchController.apply_shove] posts this cue at the victim's position
## for EVERY shove that lands, bot or human -- in a bot-heavy match that is
## roughly twice a second -- and until now the cue played flat, so it blasted
## the whole ring at full volume for every catch and shove anywhere in the
## arena. The fix lives entirely in the shipped bank's [AudioCue.positional]
## flag; this file proves it against the real production wiring
## ([code]match/match.tscn[/code]'s own GameAudio director and bank)
## rather than a synthetic one, the same way [code]tests/test_shove.gd[/code]
## drives [method MatchController.apply_shove] directly.
##
## The local player's OWN catch is a different post entirely --
## [signal FxCatchReaction.catch_made], relayed by [MatchAudioListener] through
## [method AudioDirector.post] with no position -- and a positional cue posted
## with no position always plays flat (see [AudioCue.positional]), so it must
## stay exactly as audible as before. The second test proves that directly,
## the way [code]tests/test_catch_feedback.gd[/code] builds its own
## non-headless-inert [FxCatchReaction] to exercise logic a screen-less run
## would otherwise switch off.

const CATCH_PROFILE_PATH: String = "res://match/feedback/default_catch_profile.tres"
const SETTLE_TICKS: int = 60
const REACH_METRES: float = 1.2
const FAR_FROM_LISTENER_METRES: float = 60.0

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _director: AudioDirector


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_controller.rules = _rules
	add_child(_match)

	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)

	# Same reason test_shove.gd switches this off: every shove below is tapped
	# by hand, and a bot taking a free one on its own would confuse the count.
	for participant: MatchParticipant in _controller.get_participants():
		var input: BotIntentSource = participant.body.intent_source as BotIntentSource
		if input != null:
			input.shove_enabled = false
		participant.shove_cooldown_remaining = 0.0

	# The shipped director, forced on. Headless AUTO would otherwise switch it
	# off and there would be no voices to inspect; it is already the real
	# static _instance -- the first (and only) director this scene adds -- so
	# apply_shove's static AudioDirector.post_event_at reaches it exactly as it
	# does in a played match, off the real shipped bank.
	_director = _match.get_node("GameAudio") as AudioDirector
	_director.activation = AudioDirector.Activation.ALWAYS


## A shove/catch landing 60 m from the human plays positionally and with a
## range that falls short of 60 m -- not flat, and not audible to a listener
## that far away.
func test_a_distant_shove_is_positional_and_falls_short_of_60_metres() -> void:
	var live: Array[MatchParticipant] = _controller.get_live_participants()
	var shover: MatchParticipant = live[0]
	var victim: MatchParticipant = live[1]
	shover.body.velocity = Vector3.ZERO
	victim.body.velocity = Vector3.ZERO
	shover.shove_cooldown_remaining = 0.0

	var human: MatchParticipant = _controller.get_human_participant()
	var far_spot: Vector3 = human.body.global_position + Vector3(FAR_FROM_LISTENER_METRES, 0.0, 0.0)
	shover.body.global_position = far_spot
	var forward: Vector3 = -shover.body.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	victim.body.global_position = far_spot + forward * REACH_METRES
	victim.body.velocity = Vector3.ZERO

	_director.clear_rate_limits()
	if not assert_same(_controller.apply_shove(shover), victim, "the shove lands, 60 m from the human"):
		return

	assert_eq_int(_director.get_active_voice_count(), 1, "one voice for the catch/shove cue")
	assert_eq_int(_director.get_active_positional_count(), 1, "placed in the world, not flat")
	var points: PackedVector3Array = _director.get_active_positions()
	assert_true(
		points.size() == 1 and points[0].is_equal_approx(victim.body.global_position),
		"placed at the victim, not the origin",
	)

	var cue: AudioCue = _director.active_bank().get_cue(AudioEvents.PLAYER_CATCH_MADE)
	if not assert_not_null(cue, "the bank still carries player.catch_made"):
		return
	assert_true(cue.positional, "player.catch_made is positional now")
	assert_lt(
		cue.max_distance, FAR_FROM_LISTENER_METRES,
		"and its range falls short of 60 m, so a listener there hears nothing",
	)


## FxCatchReaction's own signal -- the local player's "I made that catch" --
## still posts flat, full volume, regardless of the fix above.
func test_the_local_players_own_catch_still_plays_flat() -> void:
	var human: MatchParticipant = _controller.get_human_participant()
	var reaction: FxCatchReaction = FxCatchReaction.new()
	reaction.headless_inert = false
	reaction.profile = load(CATCH_PROFILE_PATH) as CatchProfile
	reaction.controller = _controller
	reaction.body = human.body
	add_child(reaction)
	reaction.set_process(false)

	var listener: MatchAudioListener = MatchAudioListener.new()
	listener.director = _director
	listener.auto_discover = false
	listener.catch_reaction = reaction
	add_child(listener)
	listener._connect_all()

	_director.clear_rate_limits()
	reaction.play_take(Color.RED)

	assert_eq_int(_director.get_active_voice_count(), 1, "the local catch posted one voice")
	assert_eq_int(
		_director.get_active_flat_count(), 1,
		"and it is flat -- full volume no matter how far anything else is",
	)
