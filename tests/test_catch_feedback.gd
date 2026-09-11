extends TestCase

## THE CATCH, from both ends of it.
##
## The ghost catch is what makes a round three-sided, and until [FxCatchReaction]
## existed it produced nothing on either screen: one frame you were running, the
## next you were a ghost, with no idea what had happened or who had done it. The
## claims below are the four ways that could plausibly have been fixed wrongly:
##
## [codeblock]
## 1. IT FIRES FOR BOTH.   The ghost who closed the distance is told they took a
##                         spot; the prisoner whose spot it was is told they
##                         died. Two different reactions, not one shared one.
## 2. IT IS NOT THE SHOT.  Being caught must never read as being shot. Different
##                         colour, different shape, different length, different
##                         camera, different cue -- and the rifle's own reaction
##                         stays down throughout.
## 3. IT NAMES SOMEBODY.   The frame is drawn in the OTHER participant's stable
##                         RunnerPalette colour, at full alpha, so a glance
##                         answers "who".
## 4. IT IS INERT FOR BOTS. Bots catch and are caught constantly. A catch with no
##                         human in it must run the identical path and produce
##                         nothing: no camera, no frame, no cue.
## [/codeblock]
##
## And the fifth, which is the constraint the whole job was given under: none of
## it changes the catch. The swap, the radius, the grace, the conserved counts
## and the carried lap are re-asserted here with the feedback layer live, off the
## same seams [code]tests/test_ghosts.gd[/code] asserts them off with it absent.
##
## [b]Why the nodes are built here rather than found in the scene[/b]
##
## The one shipped in [code]scenes/match/match.tscn[/code] is
## [code]headless_inert[/code] and switches itself off in a test run, which is
## right -- a sweep has no screen to draw on. So the logic is tested on an
## instance built with that turned off, pointed at the same live
## [MatchController]; that the SHIPPED one is wired at all, and inert, is
## asserted separately off the scene. [FxSpectatorView] and [MatchDeathScreen]
## are tested the same way for the same reason.
##
## [b]Why the effect nodes are stepped by hand[/b]
##
## [FxCatchReaction] and [FxCameraKick] run on [method Node._process] because
## they are rendered quantities, and the runner drives
## [signal SceneTree.physics_frame]. Both expose a public
## [code]tick(delta)[/code], so every test here calls
## [code]set_process(false)[/code] and steps them itself at the shipped physics
## delta.
##
## [b]Why a catch is forced rather than run[/b]
##
## Same reasoning as [code]tests/test_ghosts.gd[/code]: waiting for a ghost to
## genuinely close on a prisoner is tens of simulated seconds and what it proves
## is that the pursuit steering works. The ghost's body is put where a chase
## would have taken it and the match is left to notice on its own clock, through
## the same [method MatchController._tick_ghosts] a real chase arrives at.

const CATCH_PROFILE_PATH: String = "res://resources/fx/default_catch_profile.tres"
const FEEDBACK_PROFILE_PATH: String = "res://scenes/fx/default_feedback_profile.tres"
const BANK_PATH: String = "res://scenes/audio/placeholder_bank.tres"
const CAMERA_PATH: NodePath = ^"Head/Camera"
const SHIPPED_REACTION_PATH: String = "FeedbackRig/CatchReaction"

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## Ticks a respawn hold is polled for before a test gives up on it. A second
## clear of the shipped three.
const HOLD_BUDGET_TICKS: int = 240

## How close two colour channels must be to be the same colour.
const COLOR_TOLERANCE: float = 1e-4

## Metres of camera offset below which nothing has moved. The kick composes in
## single precision off a base read back from a Transform3D.
const OFFSET_TOLERANCE: float = 1e-5

## Radians of camera rotation below which the view has not turned.
const ANGLE_TOLERANCE: float = 1e-5

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _human: MatchParticipant

var _profile: CatchProfile
var _feedback: FeedbackProfile
var _kick: FxCameraKick
var _reaction: FxCatchReaction
var _hit_reaction: FxHitReaction

var _made: Array[Color] = []
var _taken: Array[Color] = []


func before_each() -> void:
	_match = TestFixtures.make_match()

	# The rules are handed over before the instance enters the tree:
	# MatchController arms the match from _ready.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_controller.rules = _rules
	add_child(_match)

	_human = _controller.get_human_participant()

	# The shipped match opens with a race. Hand the tower to a BOT, not to the
	# human, through the same seam the match scores on -- every test here needs
	# the human out on the ring, where they can catch and be caught.
	var opener: MatchParticipant = _first_bot()
	if opener != null:
		opener.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	_stand_the_tower_down()

	_profile = (load(CATCH_PROFILE_PATH) as CatchProfile).duplicate() as CatchProfile
	_feedback = (load(FEEDBACK_PROFILE_PATH) as FeedbackProfile).duplicate() as FeedbackProfile
	# THE HIT STOP IS OFF. It writes Engine.time_scale, which the runner itself
	# has raised to drive the simulation faster than real time, and a stop left
	# running by a test that failed halfway would slow every test after it in the
	# same process. Nothing here is supposed to trigger one; this is belt and
	# braces on a global.
	_feedback.hit_stop_enabled = false

	_kick = _make_kick(_human.body)
	_reaction = _make_reaction(_human.body, _kick)
	# The rifle's own reaction, on the same body, so "being caught does not look
	# like being shot" can be asserted rather than assumed.
	_hit_reaction = _make_hit_reaction(_human.body, _kick)


# --- The ghost who catches ----------------------------------------------------

## You closed the distance and took a life back, and the game says so.
func test_the_ghost_who_catches_is_told_they_took_a_spot() -> void:
	var quarry: MatchParticipant = await _human_catches()
	assert_not_null(quarry, "there was a prisoner for the human's ghost to take")
	if quarry == null:
		return

	assert_eq_int(_made.size(), 1, "the taker's half fired once")
	assert_eq_int(_taken.size(), 0, "and the victim's half did not fire on this screen")
	assert_eq_int(
		int(_reaction.get_side()), int(FxCatchReaction.CatchSide.TAKE),
		"the reaction knows which side of the catch this player was on",
	)
	assert_true(_reaction.is_reacting(), "something is on screen")
	assert_gt(_reaction.get_alpha(), 0.0, "and it is visible")

	# WHO. The frame is the prisoner whose spot was taken, in their own colour.
	_assert_is_palette_color(_reaction.get_color(), quarry, "the taker sees the caught player's colour")
	_assert_is_palette_color(_made[0], quarry, "and the cue is handed the same colour")

	# The camera got the kill-confirm punch and NOTHING ELSE. See the companion
	# assertion in the caught test: a turn is what tells the two apart.
	assert_true(_kick.is_active(), "the camera acknowledged it")
	_kick.tick(SIM_DELTA)
	assert_gt(
		absf(_kick.get_position_offset().z), OFFSET_TOLERANCE,
		"taking a spot punches the camera",
	)
	assert_le(
		_kick.get_rotation_offset().length(), ANGLE_TOLERANCE,
		"and does not turn it: you did this, it did not happen to you",
	)


## The burst is short, and it opens OUTWARD. The player is alive again, at
## running pace, holding a spot somebody else ran for, and the one thing they now
## need is the ring.
func test_the_taker_gets_the_screen_straight_back() -> void:
	var quarry: MatchParticipant = await _human_catches()
	if quarry == null:
		fail("there was a prisoner for the human's ghost to take")
		return

	var first: float = _reaction.get_thickness_fraction()
	assert_gt(first, 0.0, "the burst starts thick, at the edges")
	_reaction.tick(SIM_DELTA * 4.0)
	assert_lt(
		_reaction.get_thickness_fraction(), first,
		"and retreats off the screen rather than closing in",
	)

	_reaction.tick(_profile.get_take_seconds())
	assert_false(_reaction.is_reacting(), "it is gone inside its configured length")
	assert_eq_int(
		int(_reaction.get_side()), int(FxCatchReaction.CatchSide.NONE),
		"and leaves no side behind it",
	)
	assert_almost_eq(_reaction.get_alpha(), 0.0, 1e-6, "with nothing left on screen")


# --- The prisoner who is caught -----------------------------------------------

## Something reached you. It is a death, and the game says that too.
func test_the_prisoner_who_is_caught_is_told_they_died() -> void:
	var taker: MatchParticipant = await _human_is_caught()
	assert_not_null(taker, "there was a ghost to take the human's spot")
	if taker == null:
		return

	assert_eq_int(_taken.size(), 1, "the victim's half fired once")
	assert_eq_int(_made.size(), 0, "and the taker's half did not fire on this screen")
	assert_eq_int(
		int(_reaction.get_side()), int(FxCatchReaction.CatchSide.CAUGHT),
		"the reaction knows which side of the catch this player was on",
	)
	assert_gt(_reaction.get_alpha(), 0.0, "and it is visible")

	# WHO. The frame is the ghost that took them, in their own colour -- at FULL
	# alpha, and not the 0.62 their body is wearing: the question the frame
	# answers is which player, not which role.
	_assert_is_palette_color(_reaction.get_color(), taker, "the victim sees the ghost's colour")
	# Guarded: an empty array here is a catch that did not happen, which the
	# check above has already reported. Indexing it anyway abandons the rest of
	# this function with an engine error and buries that report.
	if _taken.size() > 0:
		_assert_is_palette_color(_taken[0], taker, "and the cue is handed the same colour")
	assert_almost_eq(
		_reaction.get_color().a, 1.0, COLOR_TOLERANCE,
		"identity is the palette entry; translucency is a statement made on the body",
	)

	# The camera was turned AND pulled. Both channels, which is the signature the
	# taker's half deliberately does not have.
	assert_true(_kick.is_active(), "the camera acknowledged it")
	_kick.tick(SIM_DELTA)
	assert_gt(
		_kick.get_rotation_offset().length(), ANGLE_TOLERANCE,
		"being caught turns the view towards whatever reached you",
	)
	assert_gt(
		absf(_kick.get_position_offset().z), OFFSET_TOLERANCE,
		"and drags it backwards, which the rifle never does to a victim",
	)


## The frame CLOSES IN and is held. That is the gesture, and it is the opposite
## of the taker's.
func test_being_caught_closes_in_and_holds() -> void:
	var taker: MatchParticipant = await _human_is_caught()
	if taker == null:
		fail("there was a ghost to take the human's spot")
		return

	var first: float = _reaction.get_thickness_fraction()
	_reaction.tick(_profile.caught_close_seconds)
	var closed: float = _reaction.get_thickness_fraction()
	assert_gt(closed, first, "the frame grows inward rather than retreating")
	assert_almost_eq(
		closed, _profile.caught_thickness_fraction, 1e-4,
		"and reaches exactly the thickness the profile asks for",
	)
	assert_almost_eq(
		_reaction.get_alpha(), _profile.caught_alpha, 1e-4,
		"at full strength, and then it is HELD",
	)

	# Held right across the cut to the spectator camera, which is the whole
	# reason the hold exists. Read off SpectatorProfile rather than restated, so
	# a retuned delay retunes this assertion with it.
	var spectator: SpectatorProfile = load(
		"res://resources/fx/default_spectator_profile.tres"
	) as SpectatorProfile
	if spectator != null:
		assert_gt(
			_profile.get_caught_seconds(), spectator.enter_delay_seconds,
			"the frame outlives the cut to the spectator camera",
		)

	# One tick of slack past the arithmetic end: the total is summed in a
	# different association here than in CatchProfile.get_caught_seconds(), and
	# a single-precision ULP is not what this test is about.
	_reaction.tick(_profile.caught_hold_seconds + _profile.caught_fade_seconds + SIM_DELTA)
	assert_false(_reaction.is_reacting(), "and it is gone inside its configured length")


# --- Not the rifle ------------------------------------------------------------

## Being caught must never be mistaken for being shot.
##
## Both are this player dying, and only the presentation says which. Every axis
## on which they could have been confused is asserted apart here.
func test_being_caught_does_not_look_like_being_shot() -> void:
	var taker: MatchParticipant = await _human_is_caught()
	if taker == null:
		fail("there was a ghost to take the human's spot")
		return

	# The shot's own reaction never came up. It cannot: a catch does not go
	# through the rifle, and this is the assertion that the two paths stayed
	# separate rather than one being wired into the other for convenience.
	assert_false(_hit_reaction.is_reacting(), "the rifle's reaction is not playing")
	assert_almost_eq(_hit_reaction.get_flash_alpha(), 0.0, 1e-6, "there is no white flash")

	# Colour, not white. Shot feedback is FeedbackProfile.flash_color, a white;
	# a catch is somebody's palette entry.
	var caught_colour: Color = _reaction.get_color()
	assert_true(
		not (
			is_equal_approx(caught_colour.r, caught_colour.g)
			and is_equal_approx(caught_colour.g, caught_colour.b)
		),
		"the catch frame carries a hue, where the shot flash is white",
	)

	# A frame, not a fill: the middle of the screen is never painted, because a
	# player who has just been caught is about to be shown their own body.
	assert_lt(
		_profile.caught_thickness_fraction, 0.5,
		"the catch leaves the centre of the screen clear",
	)

	# And it is an order of magnitude longer. The shot is over before the player
	# has finished reacting to it; the catch has to survive a camera change.
	assert_gt(
		_profile.get_caught_seconds(), _feedback.flash_seconds * 2.0,
		"the catch outlasts the shot flash by a wide margin",
	)

	# Different cue, and the bank has something to play for it.
	assert_true(
		AudioEvents.PLAYER_CATCH_TAKEN != AudioEvents.PLAYER_HIT_TAKEN,
		"being caught and being shot are two different events in the audio contract",
	)
	var bank: AudioBank = load(BANK_PATH) as AudioBank
	assert_not_null(bank, "the placeholder bank loads")
	if bank != null:
		assert_eq_int(bank.missing_events().size(), 0, "and is still complete")
		assert_true(bank.can_play(AudioEvents.PLAYER_CATCH_TAKEN), "with a cue for being caught")
		assert_true(bank.can_play(AudioEvents.PLAYER_CATCH_MADE), "and one for making the catch")


# --- Bots ---------------------------------------------------------------------

## A catch between two bots is the ordinary business of a round, and it produces
## NOTHING on the human's screen.
##
## The identical path: the same signal, the same handler, the same node. What
## differs is that neither participant is this body, so it returns before it
## reads a colour -- no camera call, no signal, no frame, and no error.
func test_a_catch_between_two_bots_is_inert() -> void:
	var ghost: MatchParticipant = await _bot_ghost()
	assert_not_null(ghost, "a bot was made into a ghost")
	if ghost == null:
		return
	var quarry: MatchParticipant = _first_live_bot()
	assert_not_null(quarry, "and another bot was still running to be caught")
	if quarry == null:
		return

	_put_ghost_on(ghost, quarry)
	await step_ticks(MatchController.SETTLE_PHYSICS_FRAMES + 2)

	# The catch really happened. Without this the rest is vacuous.
	assert_eq_int(_controller.get_catch_count(), 1, "the match performed the swap")
	assert_true(quarry.is_ghost, "the caught bot is the ghost now")
	assert_true(ghost.is_running, "and the bot that caught it is running")

	# And the human's rig did not move.
	assert_eq_int(_made.size(), 0, "no cue for a catch that was not mine")
	assert_eq_int(_taken.size(), 0, "in either direction")
	assert_false(_reaction.is_reacting(), "nothing is on screen")
	assert_eq_int(
		int(_reaction.get_side()), int(FxCatchReaction.CatchSide.NONE), "and no side was chosen"
	)
	assert_almost_eq(_reaction.get_alpha(), 0.0, 1e-6, "with no opacity to fade")
	assert_almost_eq(_reaction.get_thickness_fraction(), 0.0, 1e-6, "and no thickness to draw")
	assert_false(_kick.is_active(), "the camera was never touched")
	assert_true(_kick.is_at_rest(), "and is sitting exactly on its base")

	# Stepping it is a no-op too, rather than a slow decay of something invisible.
	_reaction.tick(SIM_DELTA)
	assert_false(_reaction.is_reacting(), "and a tick afterwards changes nothing")


# --- The catch itself is untouched --------------------------------------------

## Every claim [code]tests/test_ghosts.gd[/code] makes about the swap, re-made
## with the feedback layer live and listening.
##
## The whole job was given under one constraint -- announce what already happens,
## change nothing about it -- and this is the test of that constraint rather than
## of anything this work added.
func test_the_swap_itself_is_unchanged() -> void:
	await step_ticks(SETTLE_TICKS)

	var ghost: MatchParticipant = await _bot_ghost()
	if ghost == null:
		fail("a bot was made into a ghost")
		return

	var living_before: int = _controller.get_runners_remaining()
	var ghosts_before: int = _controller.get_ghosts_remaining()
	var removed_before: int = _controller.get_runners_removed()
	var carried: float = _human.tracker.get_progress()

	if not _require_human_is_running():
		return
	_put_ghost_on(ghost, _human)
	await step_ticks(MatchController.SETTLE_PHYSICS_FRAMES + 2)

	assert_eq_int(_taken.size(), 1, "the human was caught, and knows it")

	# Roles traded.
	assert_true(ghost.is_running, "the ghost is a living prisoner now")
	assert_false(ghost.is_ghost, "and is no longer a ghost")
	assert_true(_human.is_ghost, "the caught prisoner is the ghost now")
	assert_false(_human.is_running, "and is no longer running")

	# Conserved, both ways: a catch cannot move the shooter's win condition.
	assert_eq_int(
		_controller.get_runners_remaining(), living_before,
		"a catch does not change how many prisoners are running",
	)
	assert_eq_int(
		_controller.get_ghosts_remaining(), ghosts_before,
		"a catch does not change how many ghosts there are",
	)
	assert_eq_int(
		_controller.get_runners_removed(), removed_before,
		"a catch is not a conversion",
	)
	assert_eq_int(_controller.get_catch_count(), 1, "the match counted one catch")

	# The spot really was taken, with the lap that came with it.
	assert_true(
		ghost.body.is_in_group(MatchController.RUNNER_GROUP),
		"the incoming prisoner is a legitimate target",
	)
	assert_false(
		_human.body.is_in_group(MatchController.RUNNER_GROUP),
		"and the outgoing one is not",
	)
	assert_almost_eq(
		ghost.tracker.get_progress(), carried, 0.02,
		"the lap the caught prisoner had run came with the spot",
	)

	# And the grace still holds, so the frame on screen is not describing a swap
	# that is about to oscillate back.
	assert_gt(_human.ghost_grace_remaining, 0.0, "a freshly made ghost is on its catch grace")
	await step_ticks(2)
	assert_eq_int(_controller.get_catch_count(), 1, "the swap did not oscillate")
	assert_eq_int(_taken.size(), 1, "and the announcement did not repeat")


# --- The resource -------------------------------------------------------------

## Every number is on the [CatchProfile], including the off switch -- and the off
## switch really is one.
func test_the_layer_can_be_switched_off_from_the_resource() -> void:
	_profile.enabled = false

	var taker: MatchParticipant = await _human_is_caught()
	if taker == null:
		fail("there was a ghost to take the human's spot")
		return

	assert_eq_int(_taken.size(), 0, "nothing was announced")
	assert_false(_reaction.is_reacting(), "nothing is on screen")
	assert_false(_kick.is_active(), "and the camera was not touched")
	assert_almost_eq(_profile.get_caught_seconds(), 0.0, 1e-6, "the length reads as zero")
	assert_almost_eq(_profile.get_take_seconds(), 0.0, 1e-6, "on both halves")

	# The catch still happened. The switch is a presentation switch and nothing
	# else, which is the point of testing it at all.
	assert_true(_human.is_ghost, "the human was still caught")
	assert_eq_int(_controller.get_catch_count(), 1, "and the match still counted it")


## The shipped resource exists, loads as a [CatchProfile], and is the one the
## rig points at.
func test_the_shipped_profile_is_a_resource() -> void:
	var shipped: CatchProfile = load(CATCH_PROFILE_PATH) as CatchProfile
	assert_not_null(shipped, "resources/fx/default_catch_profile.tres loads")
	if shipped == null:
		return
	assert_true(shipped.enabled, "and ships switched on")
	assert_gt(shipped.get_caught_seconds(), 0.0, "with a length for the victim's half")
	assert_gt(shipped.get_take_seconds(), 0.0, "and one for the taker's")


# --- The shipped node ---------------------------------------------------------

## The node in [code]scenes/match/match.tscn[/code] is wired, and is inert in a
## headless run.
##
## Both halves matter. Unwired, the catch is silent again and no test above would
## notice, because every test above builds its own. Not inert, a bot sweep pays
## for feedback nobody is there to see.
func test_the_shipped_reaction_is_wired_and_inert() -> void:
	var shipped: FxCatchReaction = _match.get_node_or_null(SHIPPED_REACTION_PATH) as FxCatchReaction
	assert_not_null(shipped, "the match scene ships an FxCatchReaction in the feedback rig")
	if shipped == null:
		return
	assert_true(shipped.is_inert(), "and it switches itself off with no display server")
	assert_same(shipped.controller, _controller, "it is pointed at this match")
	assert_same(shipped.body, _human.body, "and at the human's body, not at a bot's")
	assert_not_null(shipped.profile, "it carries a CatchProfile")
	assert_not_null(shipped.camera_kick, "and shares the rig's one FxCameraKick")


## Switch every AI tower brain off for the rest of the case.
##
## [b]Not tidiness -- the tower is a second, uncontrolled way for the human to
## die, and this file's whole subject is the OTHER one.[/b] [method before_each]
## hands the seat to a bot precisely so the human is out on the ring, and a
## human with no display server has no input device: they stand on the start pad
## for the length of the case, in the open, in front of a [TowerShooter] that
## acquires, tracks and fires on its own [method Node._physics_process]. Every
## fixture below then spends up to [constant HOLD_BUDGET_TICKS] ticks waiting out
## a respawn hold, which is four simulated seconds of a stationary target. When
## the rifle got there first the human was already a ghost before the catch was
## forced, the catch could not happen -- a ghost cannot be caught -- and the
## failure landed on the catch assertions rather than on the shot that caused it.
## [method _require_human_is_running] is the guard that says so out loud if this
## is ever walked back.
##
## The brains, not the participants: nothing about the seat, the round or the
## rifle changes, so the catch still arrives through exactly the
## [method MatchController._tick_ghosts] path a played match arrives at.
func _stand_the_tower_down() -> void:
	for participant: MatchParticipant in _controller.get_participants():
		if participant.tower_brain != null:
			participant.tower_brain.set_physics_process(false)


## Assert the human is still a running prisoner, so a failed catch below is
## reported as a failed catch and not as six confusing assertions about a colour.
func _require_human_is_running() -> bool:
	return assert_true(
		_human.is_running and not _human.is_ghost,
		"the human is still a running prisoner when the catch is forced",
	)


# --- Fixtures -----------------------------------------------------------------

## Make the human a ghost, put them on a living prisoner, and let the match
## notice. Returns the prisoner whose spot was taken, or null.
func _human_catches() -> MatchParticipant:
	assert_true(_controller.apply_hit(_human), "the human is shot to make the ghost")
	await _await_respawn(_human)
	var quarry: MatchParticipant = _first_live_bot()
	if quarry == null:
		return null
	_put_ghost_on(_human, quarry)
	await step_ticks(MatchController.SETTLE_PHYSICS_FRAMES + 2)
	return quarry


## Make a bot a ghost, put it on the human, and let the match notice. Returns the
## ghost that took the spot, or null.
func _human_is_caught() -> MatchParticipant:
	var ghost: MatchParticipant = await _bot_ghost()
	if ghost == null:
		return null
	if not _require_human_is_running():
		return null
	_put_ghost_on(ghost, _human)
	await step_ticks(MatchController.SETTLE_PHYSICS_FRAMES + 2)
	return ghost


## Shoot a running bot and wait out its respawn hold, so it is a ghost that is in
## the world and able to catch. A held ghost catches nobody -- that is asserted
## in [code]tests/test_ghosts.gd[/code] and is not this file's business.
func _bot_ghost() -> MatchParticipant:
	var victim: MatchParticipant = _first_live_bot()
	if victim == null:
		return null
	if not _controller.apply_hit(victim):
		return null
	await _await_respawn(victim)
	return victim


## Stand [param ghost] on [param quarry] and spend its grace, so the next tick of
## [method MatchController._tick_ghosts] rules on the catch.
##
## Mirrors the helper in [code]tests/test_ghosts.gd[/code], and is safe for the
## same reason: a ghost is already off every collision layer and mask-wise cannot
## carry anything, which is the one state in which moving a body by hand is not
## the trap [method MatchController._hold_body] documents. Both brains are stood
## down first so neither steers off the spot on the next tick.
##
## Note what this leaves the two bodies in: THE SAME PLACE. So the reach
## direction [FxCatchReaction] derives degenerates to
## [constant Vector3.ZERO] and [method FxCameraKick.strike] falls back on its own
## fixed off-axis whip -- which is exactly the path a real catch at the bottom of
## [member GhostProfile.catch_radius_metres] takes, and is why the camera
## assertions above are made on "the view turned" rather than on a bearing.
func _put_ghost_on(ghost: MatchParticipant, quarry: MatchParticipant) -> void:
	if ghost.brain != null:
		ghost.brain.end_chase()
	if quarry.brain != null:
		quarry.brain.set_physics_process(false)
	ghost.body.set_physics_process(false)
	quarry.body.set_physics_process(false)
	ghost.body.velocity = Vector3.ZERO
	quarry.body.velocity = Vector3.ZERO
	ghost.body.collision_mask = 0
	ghost.body.global_position = quarry.body.global_position
	ghost.ghost_grace_remaining = 0.0


## Wait out [param participant]'s respawn hold. Polled rather than slept for a
## flat delay so a retuned profile needs no second edit here.
func _await_respawn(participant: MatchParticipant) -> void:
	for _tick: int in HOLD_BUDGET_TICKS:
		if not _controller.is_awaiting_respawn(participant):
			return
		await step_ticks(1)


func _first_bot() -> MatchParticipant:
	for participant: MatchParticipant in _controller.get_participants():
		if not participant.is_human():
			return participant
	return null


## The first AI prisoner still running. Deliberately not the human: every
## fixture here needs the two sides of a catch to be nameable.
func _first_live_bot() -> MatchParticipant:
	for participant: MatchParticipant in _controller.get_live_participants():
		if not participant.is_human():
			return participant
	return null


func _assert_is_palette_color(
	actual: Color, participant: MatchParticipant, message: String
) -> void:
	var expected: Color = _controller.get_runner_palette().color_for_index(participant.index)
	assert_almost_eq(actual.r, expected.r, COLOR_TOLERANCE, "%s -- red" % message)
	assert_almost_eq(actual.g, expected.g, COLOR_TOLERANCE, "%s -- green" % message)
	assert_almost_eq(actual.b, expected.b, COLOR_TOLERANCE, "%s -- blue" % message)


## The one licence [code]scenes/fx/feedback_rig.tscn[/code]'s own header grants:
## a test that needs the logic to actually run without a display server says so.
func _make_kick(body: PlayerController) -> FxCameraKick:
	var kick: FxCameraKick = FxCameraKick.new()
	kick.name = "CameraKick_%d" % body.get_instance_id()
	kick.headless_inert = false
	kick.profile = _feedback
	kick.camera = body.get_node(CAMERA_PATH) as Camera3D
	add_child(kick)
	kick.set_process(false)
	return kick


func _make_reaction(body: PlayerController, kick: FxCameraKick) -> FxCatchReaction:
	var reaction: FxCatchReaction = FxCatchReaction.new()
	reaction.name = "CatchReaction_%d" % body.get_instance_id()
	reaction.headless_inert = false
	reaction.profile = _profile
	reaction.controller = _controller
	reaction.body = body
	reaction.camera_kick = kick
	add_child(reaction)
	reaction.set_process(false)
	reaction.catch_made.connect(_on_catch_made)
	reaction.catch_taken.connect(_on_catch_taken)
	return reaction


func _make_hit_reaction(body: PlayerController, kick: FxCameraKick) -> FxHitReaction:
	var reaction: FxHitReaction = FxHitReaction.new()
	reaction.name = "HitReaction_%d" % body.get_instance_id()
	reaction.headless_inert = false
	reaction.profile = _feedback
	# Read off the controller's own export and NOT off a path into the scene.
	# There is one rifle in a match and MatchController reparents it onto
	# whoever holds the tower -- a bot does, in every test here -- so
	# Player/Head/Rifle is stale by the time this runs.
	reaction.rifle = _controller.rifle
	reaction.body = body
	reaction.camera_kick = kick
	add_child(reaction)
	reaction.set_process(false)
	return reaction


func _on_catch_made(caught_color: Color) -> void:
	_made.append(caught_color)


func _on_catch_taken(ghost_color: Color) -> void:
	_taken.append(ghost_color)
