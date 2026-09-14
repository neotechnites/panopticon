extends TestCase

## THE RULE TABLE: which body hides itself, and who decides.
##
## One body in the match is the VIEWED one -- the body the current camera is
## looking out of. It hides its own head, its spine unless a shove is playing,
## and its upper arms while it is armed. Every other body is drawn whole, on a
## layer the cameras keep. Nothing in that sentence mentions the human, and that
## is the point: a camera on a bot's head, on a spectated teammate or on a replay
## seat gets the same treatment the local player gets.
##
## [codeblock]
## claim            viewed body      hidden on it      every other body
## none, own camera the local human  head, spine       whole
## a bot's body     that bot         head, spine       whole, human included
## null (free cam)  nobody           nothing           whole
## [/codeblock]
##
## The HUD is bound to the same answer, so riding a bot reads that bot's seat.

## Ticks to let the opening race settle before anything is measured.
const SETTLE_TICKS: int = 30

## The cull mask every camera in the game inherits from player.tscn.
const CAMERA_CULL_MASK: int = 1048573

var _match: Node3D
var _controller: MatchController
var _hud: MatchHud
var _human: MatchParticipant
var _human_avatar: PrisonerAvatar


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = TestFixtures.match_rules()
	add_child(_match)
	_hud = _match.get_node("HUD/Root") as MatchHud
	await step_ticks(SETTLE_TICKS)
	_human = _controller.get_human_participant()
	_human_avatar = _avatar_of(_human)


## The claim is static: a case that failed halfway must not leave one standing.
func after_each() -> void:
	PrisonerAvatar.release_viewed_body()


# --- The rule table -----------------------------------------------------------

## No claim: the body whose own camera is current is the viewed one.
func test_the_local_human_hides_itself_and_every_bot_stays_whole() -> void:
	_tick_every_body()
	assert_true(_human_avatar.is_viewed_first_person(), "the human is looking out of their body")
	assert_true(_human_avatar.is_head_hidden(), "so their own head is collapsed")
	assert_true(_human_avatar.is_spine_hidden(), "and their torso with it")
	_assert_whole(_bots(), "a bot nobody is looking out of")


## The capture tool's case, and a spectated teammate's: the claim moves the whole
## rule to a body that is not the human's, and the human's body comes back.
func test_a_ridden_bot_hides_itself_and_the_human_body_comes_back() -> void:
	var bot: MatchParticipant = _bots()[0]
	PrisonerAvatar.set_viewed_body(bot.body)
	_tick_every_body()

	var ridden: PrisonerAvatar = _avatar_of(bot)
	assert_true(ridden.is_viewed_first_person(), "the bot is the body being looked out of")
	assert_true(ridden.is_head_hidden(), "its own head is collapsed")
	assert_true(ridden.is_spine_hidden(), "and its spine")
	assert_gt(
		float(ridden.mesh.layers & CAMERA_CULL_MASK),
		0.0,
		"on a layer the camera riding it keeps",
	)

	assert_false(_human_avatar.is_viewed_first_person(), "the human is not the viewed body")
	_assert_whole([_human] + _bots().slice(1), "every body that is not the ridden one")


## The upper arms are the armed body's rule, and they follow the claim too.
func test_the_arms_rule_follows_the_claim_onto_an_armed_body() -> void:
	var bot: MatchParticipant = _bots()[0]
	var ridden: PrisonerAvatar = _avatar_of(bot)

	PrisonerAvatar.set_viewed_body(bot.body)
	bot.body.is_armed = false
	ridden.tick_first_person()
	assert_false(ridden.are_arms_hidden(), "an unarmed body keeps its arms")

	bot.body.is_armed = true
	ridden.tick_first_person()
	assert_true(ridden.are_arms_hidden(), "an armed one does not draw them across the lens")

	PrisonerAvatar.release_viewed_body()
	ridden.tick_first_person()
	assert_false(ridden.are_arms_hidden(), "and a body nobody rides has them back")


## A camera of its own: nobody is viewed, so no body hides any part of itself.
func test_a_detached_camera_leaves_every_body_whole() -> void:
	PrisonerAvatar.set_viewed_body(null)
	_tick_every_body()
	assert_null(PrisonerAvatar.get_viewed_body(), "no body holds the view")
	_assert_whole([_human] + _bots(), "every body in the match")


# --- The HUD ------------------------------------------------------------------

## The readout follows the view, not the seat marked human.
func test_the_hud_binds_to_the_viewed_seat() -> void:
	assert_same(
		_controller.get_viewed_participant(), _human, "the human's own view is their own seat",
	)

	var bot: MatchParticipant = _bots()[0]
	PrisonerAvatar.set_viewed_body(bot.body)
	assert_same(_controller.get_viewed_participant(), bot, "riding a bot reads that bot's seat")

	bot.is_shooter = true
	_hud.tick()
	assert_true(_hud.get_role() == MatchHud.Role.GUARD, "and the role is the ridden body's")

	PrisonerAvatar.release_viewed_body()
	assert_same(_controller.get_viewed_participant(), _human, "letting go hands it back")


# --- Fixtures -----------------------------------------------------------------

## Step the rules on every body at once, without waiting on a render frame.
func _tick_every_body() -> void:
	for participant: MatchParticipant in _controller.get_participants():
		var avatar: PrisonerAvatar = _avatar_of(participant)
		if avatar != null:
			avatar.tick_first_person()


func _avatar_of(participant: MatchParticipant) -> PrisonerAvatar:
	if participant == null or participant.body == null:
		return null
	return participant.body.get_node_or_null(^"Avatar") as PrisonerAvatar


func _bots() -> Array[MatchParticipant]:
	var found: Array[MatchParticipant] = []
	for participant: MatchParticipant in _controller.get_participants():
		if not participant.is_human() and participant.body != null:
			found.append(participant)
	return found


## Nothing collapsed, and drawn on a layer a camera keeps.
func _assert_whole(who: Array, what: String) -> void:
	for participant: MatchParticipant in who:
		var avatar: PrisonerAvatar = _avatar_of(participant)
		if avatar == null:
			continue
		assert_false(avatar.is_head_hidden(), "%s keeps its head" % what)
		assert_false(avatar.is_spine_hidden(), "%s keeps its spine" % what)
		assert_false(avatar.are_arms_hidden(), "%s keeps its arms" % what)
		assert_gt(float(avatar.mesh.layers & CAMERA_CULL_MASK), 0.0, "%s is drawn" % what)
