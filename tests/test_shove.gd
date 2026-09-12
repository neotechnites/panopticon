extends TestCase

## THE SHOVE: one prisoner throwing another off a block, out of cover, or into
## the lava.
##
## Run on the real [code]scenes/match/match.tscn[/code] and on a private copy of
## the shipped rules, because the shove is a rule of the match and is resolved by
## [MatchController] on the authority -- a client only sends the tap.
##
## The first test drives the whole seam a player does: a tap on the intent, the
## controller noticing it on its own tick, the victim launched on theirs. The
## rest ask [method MatchController.apply_shove] directly, which is the same
## decision without a round of physics in the way.

## Ticks to let the round the race arms settle before it is measured.
const SETTLE_TICKS: int = 60

## Where a victim is stood, in metres in front of the shover. Inside the shipped
## two metre reach, and clear of the 0.8 m body capsule.
const REACH_METRES: float = 1.2

## And where one is stood to be out of reach.
const OUT_OF_REACH_METRES: float = 6.0

## Horizontal speed a launched body must still carry the tick after. One tick of
## ground friction is already off it, so this is the shipped 7 m/s minus slack.
const LAUNCHED_SPEED: float = 4.0

## Speed below which a body has not been thrown anywhere.
const STILL_SPEED: float = 0.5

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _shoves: Array[MatchParticipant] = []


func before_each() -> void:
	_match = TestFixtures.make_match()
	# Before the instance enters the tree: MatchController arms from _ready.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_controller.rules = _rules

	add_child(_match)
	_controller.participant_shoved.connect(_on_participant_shoved)

	# Win the race on the spot, so a round with a guard and live prisoners is
	# armed and every body is standing where the round put it.
	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)

	# The bots take free shoves off each other on the start line, which is what
	# BotIntentSource is meant to do and is not what these tests are about. Every
	# test below is about the RULE, so the opportunism is switched off here and
	# every tap below is made by hand.
	for participant: MatchParticipant in _controller.get_participants():
		var input: BotIntentSource = participant.body.intent_source as BotIntentSource
		if input != null:
			input.shove_enabled = false
		participant.shove_cooldown_remaining = 0.0
	_shoves.clear()


## A tap with a prisoner in front launches them along the shover's facing.
func test_a_shove_launches_the_prisoner_in_front() -> void:
	var live: Array[MatchParticipant] = _controller.get_live_participants()
	var shover: MatchParticipant = live[0]
	var victim: MatchParticipant = live[1]
	_still(shover)
	_still(victim)
	var forward: Vector3 = _face(shover, victim, REACH_METRES)

	_tap_shove(shover)
	# Two ticks: the controller rules on the tap on the first, and the launch it
	# leaves behind is spent by the victim's body on the second.
	await step_ticks(2)

	assert_eq_int(_shoves.size(), 1, "one shove was resolved")
	assert_same(_shoves[0], victim, "and it landed on the prisoner in front")
	var thrown: Vector3 = victim.body.velocity
	assert_gt(
		Vector2(thrown.x, thrown.z).length(), LAUNCHED_SPEED,
		"the victim is carrying the shove's horizontal impulse",
	)
	assert_gt(thrown.y, 0.0, "and has been lifted off the ground with it")
	var heading: Vector3 = Vector3(thrown.x, 0.0, thrown.z).normalized()
	assert_gt(heading.dot(forward), 0.9, "along the shover's forward, not sideways")


## A prisoner six metres away is nobody's business.
func test_a_prisoner_out_of_reach_is_not_shoved() -> void:
	var live: Array[MatchParticipant] = _controller.get_live_participants()
	var shover: MatchParticipant = live[0]
	var victim: MatchParticipant = live[1]
	_still(shover)
	_still(victim)
	_face(shover, victim, OUT_OF_REACH_METRES)

	assert_null(_controller.apply_shove(shover), "there is nobody in reach to shove")
	await step_ticks(2)
	assert_eq_int(_shoves.size(), 0, "and nothing was announced")
	assert_lt(victim.body.velocity.length(), STILL_SPEED, "the victim never moved")


## A ghost is not a body in the round: it cannot be shoved, and it cannot shove.
func test_a_ghost_is_neither_shover_nor_victim() -> void:
	var live: Array[MatchParticipant] = _controller.get_live_participants()
	var shover: MatchParticipant = live[0]
	var ghost: MatchParticipant = live[1]
	_still(shover)

	while ghost.is_running:
		_controller.apply_hit(ghost)
	assert_true(ghost.is_ghost, "the shot prisoner is a ghost")

	_still(ghost)
	_face(shover, ghost, REACH_METRES)
	assert_null(_controller.apply_shove(shover), "a ghost is not there to be shoved")

	_face(ghost, shover, REACH_METRES)
	assert_null(_controller.apply_shove(ghost), "and a ghost cannot shove")
	assert_eq_int(_shoves.size(), 0, "no shove happened either way")


## One shove, then the cooldown, then another.
func test_the_cooldown_holds_the_second_shove_back() -> void:
	var live: Array[MatchParticipant] = _controller.get_live_participants()
	var shover: MatchParticipant = live[0]
	var victim: MatchParticipant = live[1]
	_still(shover)
	_still(victim)
	_face(shover, victim, REACH_METRES)

	assert_same(_controller.apply_shove(shover), victim, "the first shove lands")
	assert_almost_eq(
		shover.shove_cooldown_remaining, _rules.shove_cooldown_seconds, 1e-3,
		"and spends the whole cooldown",
	)

	_face(shover, victim, REACH_METRES)
	assert_null(_controller.apply_shove(shover), "a second shove on the same tick is refused")

	await step_seconds(_rules.shove_cooldown_seconds + 0.1)
	_still(shover)
	_still(victim)
	_face(shover, victim, REACH_METRES)
	assert_same(_controller.apply_shove(shover), victim, "once the cooldown is out, it lands again")


# --- Helpers ------------------------------------------------------------------

## Stop [param participant]'s brain and body, so a test measures the shove and
## not the lap the bot was running.
func _still(participant: MatchParticipant) -> void:
	if participant.brain != null:
		participant.brain.set_physics_process(false)
		if participant.brain.input != null:
			participant.brain.input.command.clear()
	participant.body.velocity = Vector3.ZERO
	participant.shove_cooldown_remaining = 0.0


## Stand [param victim] [param metres] in front of [param shover] and point the
## shover at them. Returns the shover's flat forward.
func _face(shover: MatchParticipant, victim: MatchParticipant, metres: float) -> Vector3:
	var here: Vector3 = shover.body.global_position
	var forward: Vector3 = -shover.body.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	victim.body.global_position = here + forward * metres
	victim.body.velocity = Vector3.ZERO
	return forward


## Press shove on [param participant]'s own intent source, as a hand would.
func _tap_shove(participant: MatchParticipant) -> void:
	var input: BotIntentSource = participant.body.intent_source as BotIntentSource
	assert_not_null(input, "the body is driven by a BotIntentSource")
	input.command.shove_pressed = true


func _on_participant_shoved(_shover: MatchParticipant, victim: MatchParticipant) -> void:
	_shoves.append(victim)
