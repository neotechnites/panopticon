extends TestCase

## GHOSTS: what a shot prisoner becomes, and what a catch is worth.
##
## Canon, in the author's words: [i]"A shot prisoner becomes a ghost: faster than
## the living, cannot be shot, must catch up to a living player and take their
## spot."[/i] It exists to satisfy one hard constraint -- nobody sits out -- so
## the assertions below are about the three things that constraint actually
## needs: the shot player is still in the world, they are still driving a body,
## and there is something they can do that changes the round.
##
## [b]Everything here runs the real match scene[/b]
##
## [code]scenes/match/match.tscn[/code] on a private copy of the shipped rules,
## which already play [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP]. The
## copy is still the point: the shipped [code].tres[/code] is one instance for
## the whole process, and a test that retuned it would hand every later test in
## the same process a different game.
##
## [b]Why a catch is forced rather than run[/b]
##
## Waiting for a ghost to genuinely close on a prisoner is tens of simulated
## seconds of chasing, and what it would prove is that the pursuit steering
## works, which is [RingRunner]'s business. The RULE under test is the swap. So
## the ghost's body is put where a chase would have taken it -- with its
## collision already off, which it is, so nothing is dragged -- and the match is
## left to notice, on its own clock, through the same
## [method MatchController._tick_ghosts] a real chase arrives at. That the chase
## itself moves a ghost at all is asserted separately, off the intent seam.

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## Ticks of running used where a test needs a prisoner with real progress.
const RUNNING_TICKS: int = 90

## Depth below which a body is unambiguously parked out of the world rather than
## standing somewhere low. [constant MatchController.PEN_DEPTH_METRES] is -100,
## and the deck is at y=0.
const PARKED_DEPTH_METRES: float = -50.0

## Ticks the two-body speed comparison is driven for. Long enough for both to
## reach their target speed -- the shipped ground acceleration takes about a
## fifth of a second -- and short enough to stay on a flat floor.
const SPEED_TICKS: int = 120

## Height of the private floor the speed comparison runs on. Clear of the arena
## by a kilometre; see the test for why that is load-bearing.
const TEST_FLOOR_Y: float = 1000.0

## How close two angles about the ring axis must be to count as the same bearing.
## The placement is arithmetic off one marker, so this is float noise.
const START_ANGLE_TOLERANCE: float = 1e-3

## The body capsule is 0.8 m across, so two bodies whose centres are further
## apart than this are not inside one another.
const BODY_WIDTH_METRES: float = 0.8

## How far from the start a prisoner must have run before it is shot, for "it was
## moved back" to be a claim about anything.
const CLEAR_OF_THE_START_METRES: float = 5.0

## The running surface: the inner kerb is at r=36 and the outer wall at r=60.
const DECK_INNER_RADIUS: float = 36.0
const DECK_OUTER_RADIUS: float = 60.0

## Ticks a respawn hold is polled for before a test gives up on it. A second
## clear of the shipped three, so a hold that never expires fails as a hold and
## not as a timeout somebody has to go and read.
const HOLD_BUDGET_TICKS: int = 240

## Ticks of slack allowed on a measured three second hold. A clock stepped in
## whole physics frames cannot land on a designer's number exactly, and the
## claim under test is "three seconds", not "180 frames".
const HOLD_TOLERANCE_TICKS: float = 3.0

## Fraction of the ghost's speed advantage the measurement must actually show.
## The comparison is of two identical bodies under identical intent, so the only
## difference is the scale; the slack is for the acceleration ramp, not for a
## disagreement about the number.
const SPEED_MARGIN: float = 0.9

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _ghost_rules: GhostProfile
var _participants: Array[MatchParticipant] = []
var _human: MatchParticipant

var _resolutions: int = 0
var _last_outcome: int = -1
var _ghosted: Array[MatchParticipant] = []
var _respawned: Array[MatchParticipant] = []
var _catches: int = 0
var _last_catch_ghost: MatchParticipant
var _last_catch_caught: MatchParticipant


func before_each() -> void:
	_match = TestFixtures.make_match()

	# The rules are handed over before the instance enters the tree:
	# MatchController arms the match from _ready and the rule set has to be the
	# one it arms on.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_ghost_rules = _rules.ghost_profile
	_controller.rules = _rules

	add_child(_match)

	_controller.round_resolved.connect(_on_round_resolved)
	_controller.runner_ghosted.connect(_on_runner_ghosted)
	_controller.ghost_respawned.connect(_on_ghost_respawned)
	_controller.ghost_caught.connect(_on_ghost_caught)

	_participants = _controller.get_participants()
	_human = _participants[0]

	# The shipped match opens with a race. Hand it to the human through the same
	# seam the match scores on, so every test below starts from a round with a
	# known shooter instead of from a 35 second lap.
	_human.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


# --- Becoming a ghost ---------------------------------------------------------

## The rifle takes a prisoner's last life and they become a ghost, not a corpse.
##
## The whole point of the mechanic is that this is NOT a removal. Under
## [constant MatchRules.GhostBehaviour.NONE] the same hit hides the body, kills
## its collision, stops its physics and buries it 100 m under the deck; every one
## of those is asserted false here. The participant is still in the roster, still
## on the deck, still visible, and still being stepped -- which is what "no idle
## time" means in code.
func test_a_shot_prisoner_becomes_a_ghost() -> void:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var living_before: int = _controller.get_runners_remaining()
	assert_gt(float(living_before), 1.0, "the round has prisoners in it to shoot")

	assert_true(_controller.apply_hit(victim), "one hit finishes a prisoner at prisoner_lives 1")

	# Out of the round, into the third role.
	assert_false(victim.is_running, "a shot prisoner is no longer running")
	assert_false(victim.is_shooter, "a shot prisoner is not the shooter")
	assert_true(victim.is_ghost, "a shot prisoner is a ghost")
	assert_eq_string(victim.get_role_name(), "GHOST", "the role reads GHOST")
	assert_eq_int(
		_controller.get_runners_remaining(), living_before - 1,
		"the ring is one prisoner lighter",
	)
	assert_eq_int(_controller.get_ghosts_remaining(), 1, "and one ghost heavier")

	# Still a participant of the match, with everything a participant has.
	var roster: Array[MatchParticipant] = _controller.get_participants()
	assert_eq_int(roster.size(), _rules.get_participant_count(), "nobody left the match")
	assert_true(roster.has(victim), "the ghost is still on the roster")

	# THE PLACEMENT WAITS, and the body is inert while it does. This assertion
	# used to read "a ghost's body is still being stepped" immediately, and the
	# respawn hold made that false for three seconds: a held body has its physics
	# switched off so it cannot fall, act or be shot. What still has to be true --
	# and is asserted below -- is that it steps again once it LANDS. A ghost that
	# never got its physics back could not chase anything, which is the whole
	# mechanic.
	assert_false(
		victim.body.is_physics_processing(),
		"a held body is not stepped -- it cannot fall, act or be moved",
	)
	await _await_respawn(victim)

	# And the placement settles like every other one in this file. A ghost is put
	# back on the START LINE, which is a kinematic body being sent most of a lap,
	# so it spends two more physics frames off its collision before it is woken --
	# see MatchController._place_ghost_at_start and _hold_body. Everything below
	# is therefore asserted about a ghost that has landed.
	await step_ticks(SETTLE_TICKS)

	# And still in the WORLD -- this is the assertion that separates a ghost
	# from the park a converted runner gets.
	assert_gt(
		victim.body.global_position.y, PARKED_DEPTH_METRES,
		"a ghost is not buried in the pen",
	)
	assert_true(victim.body.visible, "a ghost is visible")
	assert_true(
		victim.body.is_physics_processing(),
		"and once it has landed a ghost's body is being stepped again",
	)
	assert_false(
		victim.body.is_in_group(MatchController.RUNNER_GROUP),
		"a ghost is not a legitimate target",
	)

	# Faster than the living, and doing something about it.
	assert_almost_eq(
		victim.body.speed_scale, _ghost_rules.speed_multiplier, 1e-6,
		"a ghost is driven at the ghost speed multiplier",
	)
	if victim.brain != null:
		assert_true(victim.brain.is_chasing(), "a ghosted bot is chasing")
		assert_true(victim.brain.is_physics_processing(), "a ghosted bot's brain is running")
		assert_not_null(victim.brain.get_chase_target(), "the chase is aimed at a living prisoner")

	assert_eq_int(_ghosted.size(), 1, "runner_ghosted is announced once")
	assert_same(_ghosted[0], victim, "runner_ghosted names the prisoner who was shot")

	# The round is still live: three prisoners minus one is not an empty ring.
	assert_false(_controller.is_resolved(), "one ghost does not resolve the round")


## A prisoner shot anywhere on the ring is put back on the start line, in a place
## of their own.
##
## Canon, in the author's words: [i]"a ghost shold be placed back at the start"[/i].
##
## The second half of that sentence is the hard half. The field is dealt sideways
## across the WIDTH of the track at one angle -- see
## [method MatchController._start_place_for] -- so "the start" is a line with
## bodies standing on it, and a ghost dropped on the marker itself would be
## dropped inside somebody. Both halves are asserted: the ghosts stand at the
## start line's own bearing, on the deck, and no ghost is inside any other body
## in the match. Two prisoners are shot rather than one, because one ghost cannot
## demonstrate that two of them are dealt apart.
func test_a_ghost_is_put_back_on_the_start_line() -> void:
	# Run the field well clear of the start first, or "it was moved back" is a
	# claim about a body that had not gone anywhere.
	await step_ticks(RUNNING_TICKS)

	var arena: Node3D = _match.get_node("Arena") as Node3D
	var centre: Vector3 = arena.global_position
	var start_point: Vector3 = (
		arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	).global_position
	var start_angle: float = _angle_about(centre, start_point)

	var first: MatchParticipant = _controller.get_live_participants()[0]
	var fell_at: Vector3 = first.body.global_position
	assert_gt(
		_flat(fell_at - start_point), CLEAR_OF_THE_START_METRES,
		"the prisoner is shot well away from the start line",
	)
	assert_true(_controller.apply_hit(first), "the prisoner is shot")

	var second: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(second), "and so is a second one")

	# THE PLACEMENT WAITS. For [member GhostProfile.respawn_delay_seconds] the
	# body stands frozen at the spot the rifle found it, and only then is it
	# moved -- so this is asserted on both sides of the hold. See
	# [code]test_a_killed_prisoner_waits_before_it_is_put_back[/code] for the
	# clock itself; here it is only got out of the way.
	assert_vec3_almost_eq(
		first.body.global_position, fell_at, 1e-3,
		"the instant it is shot the ghost is still standing where it fell",
	)
	await _await_respawn(first)
	await _await_respawn(second)

	assert_gt(
		_flat(first.body.global_position - fell_at), CLEAR_OF_THE_START_METRES,
		"the ghost did not stay where it fell",
	)

	for ghost: MatchParticipant in [first, second]:
		var here: Vector3 = ghost.body.global_position
		assert_almost_eq(
			absf(wrapf(_angle_about(centre, here) - start_angle, -PI, PI)), 0.0,
			START_ANGLE_TOLERANCE,
			"%s stands at the start line's own bearing" % ghost.display_name,
		)
		assert_between(
			_flat(here - centre), DECK_INNER_RADIUS, DECK_OUTER_RADIUS,
			"%s stands on the deck and not off the edge of it" % ghost.display_name,
		)

	# Nobody is inside anybody. Every other participant is checked, not just the
	# other ghost: the round's runners were dealt out of a field one smaller and
	# their places interleave with these, which is the whole reason a ghost is
	# dealt against the full roster.
	for ghost: MatchParticipant in [first, second]:
		for other: MatchParticipant in _controller.get_participants():
			if other == ghost:
				continue
			assert_gt(
				_flat(ghost.body.global_position - other.body.global_position),
				BODY_WIDTH_METRES,
				"%s is not standing inside %s" % [ghost.display_name, other.display_name],
			)

	# And it is still a ghost when the placement has woken, rather than a body
	# that was quietly put back in the round.
	await step_ticks(SETTLE_TICKS)
	assert_eq_int(_controller.get_ghosts_remaining(), 2, "both are still ghosts")
	assert_eq_int(
		_controller.get_runners_remaining(), _rules.prisoner_count - 2,
		"and neither is counted as a prisoner",
	)


# --- Not being shot -----------------------------------------------------------

## A ghost cannot be hit by the guard's weapon.
##
## Asserted twice, because either one alone would be weak. The RULE check is
## that the match refuses the hit; the WORLD check is that the rifle's own
## raycast, run on the weapon profile's real hit mask, does not find the ghost
## standing where it plainly is. The living prisoner beside it is the control:
## the same query at the same height against a body that IS shootable has to come
## back with a hit, or the test proves nothing but a badly aimed ray.
func test_a_ghost_cannot_be_hit_by_the_rifle() -> void:
	var living: Array[MatchParticipant] = _controller.get_live_participants()
	var victim: MatchParticipant = living[0]
	var control: MatchParticipant = living[1]
	assert_true(_controller.apply_hit(victim), "the prisoner is shot once to make a ghost")
	assert_true(victim.is_ghost, "the victim is a ghost")

	# The rule: a second hit on a ghost is not a hit.
	assert_false(_controller.apply_hit(victim), "the match refuses a second hit on a ghost")
	assert_false(_controller.convert_participant(victim), "a ghost cannot be converted again")
	assert_eq_int(_controller.get_ghosts_remaining(), 1, "the refused hit made nothing happen")
	assert_eq_int(
		victim.body.collision_layer, 0,
		"and it is off every layer from the tick it was shot, all through its respawn hold",
	)

	# The world checks are made on the far side of the respawn hold, where the
	# ghost is standing in its own dealt lane on the start line. Fired at the
	# spot it was SHOT they would prove nothing: that spot is in the middle of
	# the running field, and a ray through it can cross a prisoner who merely
	# happened to be alongside.
	await _await_respawn(victim)

	# The world: the ray the rifle actually shoots passes through.
	var mask: int = _hit_mask()
	assert_gt(float(mask), 0.0, "the weapon profile has a hit mask to test against")
	assert_null(
		_participant_struck_at(victim.body.global_position, mask),
		"a ray through a ghost finds no participant",
	)
	assert_same(
		_participant_struck_at(control.body.global_position, mask), control,
		"the same ray through a LIVING prisoner does hit them",
	)
	assert_eq_int(
		victim.body.collision_layer, 0,
		"a ghost is held off every layer while its placement settles",
	)
	# The mask is the authored one, but only once the start-line placement has
	# been woken: a ghost is held off collision entirely for the two frames it
	# takes the physics server to catch up with where it was put.
	#
	# Polled tick by tick, and stopped the instant it wakes, rather than a flat
	# SETTLE_TICKS wait: a woken ghost's brain resumes its chase immediately,
	# and a straight second of that (SETTLE_TICKS is 60) is more than enough
	# ground for it to close on the living prisoner it is chasing -- which
	# would put the RAY below through a body the ghost was merely standing
	# near, and prove nothing about the ghost at all. Stopping the moment
	# [method PlayerController.is_physics_processing] turns true reads the
	# position [method MatchController._wake_ghost] just woke it at, before
	# a single further tick of motion.
	for _tick: int in SETTLE_TICKS:
		await step_ticks(1)
		if victim.body.is_physics_processing():
			break
	assert_true(victim.body.is_physics_processing(), "the ghost's placement woke within the budget")
	assert_eq_int(
		victim.body.collision_layer, MatchController.GHOST_HAZARD_LAYER,
		"once woken a ghost stands on the hazard layer, not on its own",
	)
	assert_eq_int(
		victim.body.collision_layer & mask, 0,
		"and that layer is outside the rifle's own hit mask -- still unshootable",
	)
	assert_eq_int(
		victim.body.collision_mask, control.body.collision_mask,
		"a ghost still collides with the world it walks on",
	)

	# The rule still holds once the ghost is actually standing on
	# GHOST_HAZARD_LAYER rather than on nothing: the first ray, above, only
	# proved layer 0 is unshootable, which is trivially true of any mask.
	assert_null(
		_participant_struck_at(victim.body.global_position, mask),
		"a ray through the WOKEN ghost, on its real hazard layer, still finds nobody",
	)


# --- The catch ----------------------------------------------------------------

## A ghost that reaches a living prisoner takes their spot, and the swap
## conserves the count.
##
## [b]Conservation is the assertion that matters.[/b] A catch that produced two
## living prisoners would be a revive and would make the shooter's win condition
## unreachable; one that produced none would be a kill the rifle did not earn.
## It is a trade, so the number of living prisoners and the number of ghosts are
## both the same on either side of it, and only the NAMES have moved.
func test_a_ghost_catching_a_prisoner_swaps_their_roles() -> void:
	# Give the ring real progress first, so the transfer has something to carry.
	await step_ticks(RUNNING_TICKS)

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot to make the ghost")
	# A held ghost cannot catch anybody -- that is asserted on its own below --
	# so the respawn is run out first and the CATCH is what this test measures.
	await _await_respawn(victim)

	var quarry: MatchParticipant = _controller.get_live_participants()[0]
	assert_gt(quarry.tracker.get_progress(), 0.0, "the quarry has a lap worth taking")
	var carried_progress: float = quarry.tracker.get_progress()

	var living_before: int = _controller.get_runners_remaining()
	var ghosts_before: int = _controller.get_ghosts_remaining()

	_put_ghost_on(victim, quarry, true)
	# Long enough for the placement settle to expire and the ghost to be woken:
	# a ghost inside its settle is skipped by MatchController._tick_ghosts, so
	# the catch cannot land until the body is back in the world. Derived from the
	# controller's own constant rather than a magic 2.
	await step_ticks(MatchController.SETTLE_PHYSICS_FRAMES + 2)

	# The trade.
	assert_eq_int(_catches, 1, "ghost_caught is announced once")
	assert_same(_last_catch_ghost, victim, "the ghost who caught is the one who took the spot")
	assert_same(_last_catch_caught, quarry, "the prisoner who was caught is the one who lost it")
	assert_eq_int(_controller.get_catch_count(), 1, "the match counted one catch")

	assert_true(victim.is_running, "the ghost is a living prisoner now")
	assert_false(victim.is_ghost, "and is no longer a ghost")
	assert_true(quarry.is_ghost, "the caught prisoner is the ghost now")
	assert_false(quarry.is_running, "and is no longer running")

	# Conserved, both ways.
	assert_eq_int(
		_controller.get_runners_remaining(), living_before,
		"a catch does not change how many prisoners are running",
	)
	assert_eq_int(
		_controller.get_ghosts_remaining(), ghosts_before,
		"a catch does not change how many ghosts there are",
	)
	assert_eq_int(
		_controller.get_runners_removed(), 1,
		"a catch is not a conversion; only the rifle's one hit counts",
	)

	# The spot really was taken: the lap, and the target group.
	assert_true(
		victim.body.is_in_group(MatchController.RUNNER_GROUP),
		"the incoming prisoner is a legitimate target",
	)
	assert_false(
		quarry.body.is_in_group(MatchController.RUNNER_GROUP),
		"the outgoing prisoner is not",
	)
	assert_almost_eq(
		victim.tracker.get_progress(), carried_progress, 0.02,
		"the lap the caught prisoner had run came with the spot",
	)
	assert_true(victim.tracker.is_counting(), "the incoming prisoner is being scored")
	assert_false(quarry.tracker.is_counting(), "the outgoing prisoner is not")

	# Both bodies swapped what they ARE, not just what they are called.
	assert_almost_eq(victim.body.speed_scale, 1.0, 1e-6, "a living prisoner runs at living pace")
	assert_almost_eq(
		quarry.body.speed_scale, _ghost_rules.speed_multiplier, 1e-6,
		"the new ghost runs at ghost pace",
	)
	assert_eq_int(quarry.body.collision_layer, 0, "the new ghost cannot be shot")
	assert_gt(float(victim.body.collision_layer), 0.0, "the new prisoner can be")
	if victim.brain != null:
		assert_false(victim.brain.is_chasing(), "the incoming prisoner stopped chasing")
	if quarry.brain != null:
		assert_true(quarry.brain.is_chasing(), "the outgoing prisoner started")

	# And the grace holds: the prisoner who was just caught cannot take the spot
	# straight back, which is the whole reason the grace exists.
	assert_gt(
		quarry.ghost_grace_remaining, 0.0,
		"a freshly made ghost is on its catch grace",
	)
	await step_ticks(2)
	assert_eq_int(_catches, 1, "the swap did not oscillate on the next tick")


## The grace is a clock, and when it runs out the catch happens.
##
## The pair above is left standing on top of each other. Run the grace off and
## the match takes the spot back, which is the honest demonstration that the
## grace delays a catch rather than cancelling one -- and the reason a round of
## two bodies in contact does not simply lock.
func test_the_catch_grace_expires_and_the_catch_then_happens() -> void:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot to make the ghost")
	await _await_respawn(victim)
	var quarry: MatchParticipant = _controller.get_live_participants()[0]

	# The grace is untouched by the respawn hold it just sat through: a held
	# ghost is skipped by [method MatchController._tick_ghosts] entirely, so its
	# catch clock starts when it is put back and not when it died. Spending the
	# grace on three seconds of standing still would leave a ghost able to catch
	# on the frame it lands.
	assert_almost_eq(
		victim.ghost_grace_remaining, _ghost_rules.catch_grace_seconds, 1e-3,
		"the respawn hold did not spend the catch grace",
	)

	# The freshly shot ghost is on its grace and may not catch anybody yet.
	_put_ghost_on(victim, quarry, false)
	assert_gt(victim.ghost_grace_remaining, 0.0, "the shot prisoner is on its grace")
	await step_ticks(2)
	assert_eq_int(_catches, 0, "a ghost inside its grace catches nobody")

	await step_seconds(_ghost_rules.catch_grace_seconds + 0.2)
	assert_gt(float(_catches), 0.0, "once the grace is spent the catch lands")


# --- Faster than the living ---------------------------------------------------

## A ghost moves faster than a living prisoner under IDENTICAL intent.
##
## Two bodies from the same scene, on the same floor, on private copies of the
## same [MovementProfile], driven by the same [MoveIntent] through the same
## [BotIntentSource] -- so the only difference in the experiment is
## [member PlayerController.speed_scale], which is the one thing a ghost changes.
## Measured on the body's own horizontal speed and on the ground it actually
## covered, because a target speed that never reaches the velocity is not pace.
func test_a_ghost_moves_faster_than_a_living_prisoner() -> void:
	# A KILOMETRE UP, and not for fun. [method before_each] leaves a whole live
	# match parented to this case -- an arena, four bodies and a shooter standing
	# on the tower spawn at the origin -- so a test floor laid at y=0 would be
	# laid through the deck, and a body put down at the origin would be put down
	# inside the shooter. Depenetration then throws both across the world and the
	# measurement reads 20 m/s of ejection instead of 8 m/s of walking, which is
	# exactly what it read the first time this was written. The experiment gets
	# its own altitude, where nothing else is.
	var floor_body: StaticBody3D = TestFixtures.make_floor(TEST_FLOOR_Y)
	add_child(floor_body)

	var living: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	var ghost: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	living.position = Vector3(0.0, TEST_FLOOR_Y + 1.0, 0.0)
	ghost.position = Vector3(20.0, TEST_FLOOR_Y + 1.0, 0.0)
	add_child(living)
	add_child(ghost)
	ghost.speed_scale = _ghost_rules.speed_multiplier
	assert_gt(_ghost_rules.speed_multiplier, 1.0, "canon says a ghost is faster than the living")

	await step_ticks(SETTLE_TICKS)
	var living_from: Vector3 = living.global_position
	var ghost_from: Vector3 = ghost.global_position

	# The identical intent, written into both bodies every tick through the seam
	# a human's keyboard writes into.
	var living_input: BotIntentSource = TestFixtures.bot_input_of(living)
	var ghost_input: BotIntentSource = TestFixtures.bot_input_of(ghost)
	for _tick: int in SPEED_TICKS:
		living_input.command.move_direction = Vector2(0.0, 1.0)
		ghost_input.command.move_direction = Vector2(0.0, 1.0)
		await step_ticks(1)

	var living_speed: float = living.get_horizontal_speed()
	var ghost_speed: float = ghost.get_horizontal_speed()
	assert_gt(living_speed, 0.0, "the living prisoner is moving at all")
	assert_gt(ghost_speed, living_speed, "the ghost is faster than the living")
	assert_almost_eq(
		ghost_speed / living_speed, _ghost_rules.speed_multiplier, 0.05,
		"the ghost is faster by the multiplier, not by an accident",
	)

	var living_metres: float = _flat(living.global_position - living_from)
	var ghost_metres: float = _flat(ghost.global_position - ghost_from)
	assert_gt(
		ghost_metres,
		living_metres * (1.0 + (_ghost_rules.speed_multiplier - 1.0) * SPEED_MARGIN),
		"the ghost covered more ground for the same input",
	)


# --- The round still ends -----------------------------------------------------

## With ghosts on, a round still resolves exactly once, both ways.
##
## The companion to [code]test_round.gd[/code]'s
## [code]test_a_round_resolves_exactly_once[/code], and the reason it exists is
## the trap: a mechanic that keeps returning prisoners to the ring could make a
## round unfinishable. It cannot, and this is why -- a catch is a TRADE, so it
## never raises the number of living prisoners, and only the rifle ever lowers
## it. The two exits of a round are therefore exactly where they were.
func test_a_round_with_ghosts_still_resolves_exactly_once() -> void:
	# --- exit one: somebody arrives, with a ghost on the ring ---
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a ghost is made before the arrival")
	assert_eq_int(_controller.get_ghosts_remaining(), 1, "there is a ghost on the ring")

	var scorer: MatchParticipant = _controller.get_live_participants()[0]
	scorer.tracker.lap_finished.emit(12.0, 96.0)

	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "one arrival is a loss")
	assert_eq_int(_resolutions, 1, "the resolution is announced once")
	assert_eq_int(_controller.get_resolve_count(), 1, "exactly one resolution for one round")
	assert_same(_controller.get_seat_participant(), scorer, "the scorer took the tower")
	assert_eq_int(_controller.get_round_number(), 2, "the seat change restarted the round")

	# The restart brought the ghost back as a prisoner. A ghost that survived a
	# round restart would be a body nobody could shoot, forever.
	assert_eq_int(_controller.get_ghosts_remaining(), 0, "no ghost survives a round restart")
	assert_true(victim.is_running, "the ghost is a running prisoner again")
	assert_almost_eq(victim.body.speed_scale, 1.0, 1e-6, "and back to living pace")
	assert_eq_int(
		_controller.get_runners_remaining(), _rules.prisoner_count,
		"a full ring runs the restarted round",
	)
	await step_ticks(SETTLE_TICKS)
	assert_gt(
		float(victim.body.collision_layer), 0.0,
		"the returned prisoner can be shot again once the placement has woken",
	)

	# --- exit two: the tower converts the whole ring, ghosts and all ---
	for prisoner: MatchParticipant in _controller.get_live_participants():
		_controller.apply_hit(prisoner)

	assert_eq_int(
		int(_controller.get_outcome()), int(MatchController.Outcome.WIN),
		"an empty ring is still a win when the ring is full of ghosts",
	)
	assert_eq_int(_controller.get_resolve_count(), 2, "two rounds played, two resolutions")
	assert_eq_int(_resolutions, 2, "two rounds played, two announcements")
	assert_true(_controller.is_match_over(), "converting the ring still ends the match")
	assert_eq_int(
		_controller.get_ghosts_remaining(), _rules.prisoner_count,
		"the whole ring is ghosts at the moment the match ends",
	)

	# And it STAYS over. Ghosts standing on top of live prisoners at the whistle
	# must not produce a catch, a fourth resolution or a new round.
	var rounds_before: int = _controller.get_round_number()
	for ghost: MatchParticipant in _controller.get_ghost_participants():
		ghost.ghost_grace_remaining = 0.0
	await step_ticks(SETTLE_TICKS)
	assert_eq_int(_catches, 0, "a won match produces no catches")
	assert_eq_int(_controller.get_resolve_count(), 2, "no third resolution")
	assert_eq_int(_controller.get_round_number(), rounds_before, "no further round was armed")


## A ghost cannot win a round, take the seat, or be counted as a prisoner.
##
## The other half of "the count is conserved": a ghost is out of every tally the
## match rules on. It is a separate test because each of these is a different
## code path that could independently start counting them.
func test_a_ghost_counts_for_nothing_until_it_catches() -> void:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot to make the ghost")

	assert_false(
		_controller.get_live_participants().has(victim),
		"a ghost is not a live participant",
	)
	assert_eq_int(
		_controller.get_lives_left(victim), 0,
		"a ghost has no lives to spend",
	)

	# A ghost's tracker is stopped, so it cannot arrive -- but if something else
	# reported an arrival for it, the match must not hand it the tower.
	var seat_before: MatchParticipant = _controller.get_seat_participant()
	var rounds_before: int = _controller.get_round_number()
	victim.tracker.lap_finished.emit(12.0, 96.0)
	assert_same(_controller.get_seat_participant(), seat_before, "a ghost cannot take the seat")
	assert_eq_int(_controller.get_round_number(), rounds_before, "and cannot restart the round")
	assert_eq_int(_controller.get_resolve_count(), 0, "and cannot resolve the round")


# --- The respawn hold ---------------------------------------------------------

## Death waits. The author's ruling: [i]"add a 3 second respawn timer. weather
## youre alive or already a ghost."[/i]
##
## Measured, in ticks, off the match's own clock rather than asserted off the
## resource -- a delay that the controller read and then never served would pass
## a resource check and fail a player.
func test_a_killed_prisoner_waits_before_it_is_put_back() -> void:
	# Run the field clear of the start, or "it had not been moved yet" is a claim
	# about a body standing where it would end up anyway.
	await step_ticks(RUNNING_TICKS)

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var fell_at: Vector3 = victim.body.global_position
	assert_true(_controller.apply_hit(victim), "the prisoner is shot")

	assert_true(_controller.is_awaiting_respawn(victim), "the hold is armed on the tick of death")
	assert_almost_eq(
		_controller.get_respawn_hold_remaining(victim),
		_ghost_rules.respawn_delay_seconds, 1e-6,
		"and armed at its full length",
	)
	assert_eq_int(_respawned.size(), 0, "nothing has been put back yet")

	var waited_ticks: int = 0
	for _tick: int in HOLD_BUDGET_TICKS:
		await step_ticks(1)
		waited_ticks += 1
		if not _controller.is_awaiting_respawn(victim):
			break
		# Frozen, for every frame of it. Asserted inside the loop rather than at
		# the ends, because a body that drifted and came back would pass a check
		# made only at the ends.
		if victim.body.global_position.distance_to(fell_at) > 1e-3:
			fail("the held body moved %.3f m at tick %d" % [
				victim.body.global_position.distance_to(fell_at), waited_ticks,
			])
			break

	assert_false(_controller.is_awaiting_respawn(victim), "the hold ran out within the budget")
	assert_almost_eq(
		float(waited_ticks) * SIM_DELTA, _ghost_rules.respawn_delay_seconds,
		HOLD_TOLERANCE_TICKS * SIM_DELTA,
		"the hold is the profile's own duration, and the shipped one is three seconds",
	)
	assert_eq_int(_respawned.size(), 1, "ghost_respawned is announced once, at the end of it")
	if _respawned.size() == 1:
		assert_same(_respawned[0], victim, "for the participant who was held")

	# And the placement it was waiting for actually happened.
	var arena: Node3D = _match.get_node("Arena") as Node3D
	var centre: Vector3 = arena.global_position
	var start_point: Vector3 = (
		arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D
	).global_position
	assert_almost_eq(
		absf(wrapf(
			_angle_about(centre, victim.body.global_position)
			- _angle_about(centre, start_point),
			-PI, PI,
		)),
		0.0, START_ANGLE_TOLERANCE,
		"and when it ended they were put down at the start line's own bearing",
	)


## The shipped ruling is three seconds, and it is a number in a resource.
func test_the_shipped_hold_is_three_seconds_and_lives_on_the_profile() -> void:
	var shipped: GhostProfile = load(TestFixtures.GHOST_PROFILE_PATH) as GhostProfile
	if not assert_not_null(shipped, "the shipped ghost profile loads"):
		return
	assert_almost_eq(
		shipped.respawn_delay_seconds, 3.0, 1e-6,
		"the shipped respawn hold is the three seconds the author asked for",
	)
	assert_almost_eq(
		GhostProfile.new().respawn_delay_seconds, 3.0, 1e-6,
		"and a profile built from nothing gets the same default, not a zero",
	)


## What the body may do while it waits: nothing at all.
##
## Four separate refusals, because each is a different code path that could
## independently start saying yes: it cannot be shot, cannot be converted again,
## cannot fall, and cannot be moved by anything -- its own brain included.
func test_the_held_body_can_do_nothing_at_all() -> void:
	await step_ticks(RUNNING_TICKS)

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var fell_at: Vector3 = victim.body.global_position
	assert_true(_controller.apply_hit(victim), "the prisoner is shot")
	assert_true(_controller.is_awaiting_respawn(victim), "and is being held")

	var mask: int = _hit_mask()
	assert_gt(float(mask), 0.0, "the weapon profile has a hit mask to test against")

	# Sampled through the middle of the hold rather than once, so a body that
	# became solid again halfway through cannot hide between two checks.
	for _tick: int in int(_ghost_rules.respawn_delay_seconds * SIM_HZ * 0.5):
		await step_ticks(1)
		if not _controller.is_awaiting_respawn(victim):
			fail("the hold ended early")
			break
		# NOT SHOOTABLE: off every collision layer, so the rifle's own ray
		# cannot find it.
		if victim.body.collision_layer != 0:
			fail("the held body was back on collision layer %d" % victim.body.collision_layer)
			break
		# NOT ACTING and NOT FALLING: its physics is switched off, so no intent
		# from any brain and no gravity reaches it.
		if victim.body.is_physics_processing():
			fail("the held body was being stepped")
			break
		if victim.body.velocity.length() > 1e-6:
			fail("the held body was carrying velocity %v" % victim.body.velocity)
			break

	assert_true(_controller.is_awaiting_respawn(victim), "still held halfway through")
	assert_vec3_almost_eq(
		victim.body.global_position, fell_at, 1e-3,
		"and has not fallen, drifted or been walked anywhere",
	)
	assert_null(
		_participant_struck_at(victim.body.global_position, mask),
		"the rifle's own ray finds nobody where the held body is standing",
	)

	# NOT A TARGET, and not killable twice.
	assert_false(
		victim.body.is_in_group(MatchController.RUNNER_GROUP),
		"a held body is not in the group the tower shoots at",
	)
	assert_false(_controller.apply_hit(victim), "a second hit on a held body is refused")
	assert_false(
		_controller.convert_participant(victim), "and so is a second conversion"
	)
	assert_eq_int(_ghosted.size(), 1, "the death was announced exactly once")


## NOT CATCHABLE, and it cannot catch either.
##
## The catch is the one thing a ghost can do that changes the round, so a ghost
## that could do it from inside its own respawn hold would be taking somebody's
## spot from a body that is not in the world yet. It is put on a prisoner with
## its grace already spent -- which is every condition a catch needs except
## being placed -- and nothing happens.
func test_a_held_ghost_can_neither_catch_nor_be_caught() -> void:
	await step_ticks(RUNNING_TICKS)

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot to make the ghost")
	assert_true(_controller.is_awaiting_respawn(victim), "and is being held")

	var quarry: MatchParticipant = _controller.get_live_participants()[0]
	_put_ghost_on(victim, quarry, true)
	assert_almost_eq(victim.ghost_grace_remaining, 0.0, 1e-6, "with no grace left to stop it")

	await step_ticks(int(_ghost_rules.respawn_delay_seconds * SIM_HZ * 0.5))

	assert_true(_controller.is_awaiting_respawn(victim), "the hold is still running")
	assert_eq_int(_catches, 0, "and a held ghost standing on a prisoner catches nobody")
	assert_eq_int(_controller.get_catch_count(), 0, "the match counted no catch")

	# The other direction is structural: a catch only ever names a RUNNING
	# participant, and a held body is not one.
	assert_false(victim.is_running, "a held body is not a legitimate quarry")


## A ghost a hazard returns to the start waits exactly as long. [i]"weather youre
## alive or already a ghost."[/i]
##
## The fall is the second route into the one door -- see
## [method MatchController.handle_fall] -- and this is the half of the ruling
## that is easy to miss, because a ghost was never alive to be killed.
func test_a_ghost_returned_by_a_hazard_waits_too() -> void:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot to make a ghost")
	await _await_respawn(victim)
	await step_ticks(SETTLE_TICKS)
	assert_true(victim.is_ghost, "the victim is a settled, woken ghost")
	assert_false(_controller.is_awaiting_respawn(victim), "with its first hold spent")

	var respawns_before: int = _respawned.size()
	var deaths_before: int = _ghosted.size()
	var fell_at: Vector3 = victim.body.global_position

	assert_true(_controller.handle_fall(victim), "the hazard answers for the ghost")

	assert_true(
		_controller.is_awaiting_respawn(victim),
		"a ghost put back by a hazard is held, exactly as a fresh kill is",
	)
	assert_almost_eq(
		_controller.get_respawn_hold_remaining(victim),
		_ghost_rules.respawn_delay_seconds, 1e-6,
		"for the same full three seconds",
	)
	assert_eq_int(
		_ghosted.size(), deaths_before,
		"and it is not announced as a second death -- it was already a ghost",
	)
	assert_false(victim.body.is_physics_processing(), "the body is inert while it waits")
	assert_eq_int(victim.body.collision_layer, 0, "and off every layer, hazards included")
	assert_vec3_almost_eq(
		victim.body.global_position, fell_at, 1e-3, "and has not been moved yet",
	)

	await _await_respawn(victim)
	assert_eq_int(
		_respawned.size(), respawns_before + 1,
		"and once the hold ran out it was put back",
	)
	assert_true(victim.is_ghost, "still a ghost -- a hazard cannot kill one twice")


## A bot is held exactly as long as the human, because nothing in the hold reads
## which they are.
##
## The tower is handed to a BOT first, through the same lap-finished seam
## [method before_each] uses to hand it to the human, so that the human is a
## prisoner and can be shot at all.
func test_a_bot_and_a_human_are_held_for_the_same_time() -> void:
	var bot_seat: MatchParticipant = _controller.get_live_participants()[0]
	bot_seat.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)

	if not assert_same(_controller.get_seat_participant(), bot_seat, "a bot holds the tower"):
		return
	if not assert_true(_human.is_running, "and the human is a prisoner who can be shot"):
		return

	var bot: MatchParticipant = null
	for candidate: MatchParticipant in _controller.get_live_participants():
		if not candidate.is_human():
			bot = candidate
			break
	if not assert_not_null(bot, "there is a bot prisoner to compare against"):
		return

	assert_true(_controller.apply_hit(_human), "the human is shot")
	assert_true(_controller.apply_hit(bot), "and so is a bot, on the same tick")

	assert_almost_eq(
		_controller.get_respawn_hold_remaining(_human),
		_controller.get_respawn_hold_remaining(bot), 1e-6,
		"both are held for exactly the same time",
	)

	# And both come back, in the same frame, through the same door.
	await _await_respawn(_human)
	assert_false(_controller.is_awaiting_respawn(bot), "the bot's hold ended on the same tick")
	assert_eq_int(_respawned.size(), 2, "both were put back")


## Zero turns the hold off and restores the instant placement, which is what a
## headless sweep that cannot afford three seconds of dead air per conversion
## sets.
func test_a_zero_delay_places_the_ghost_immediately() -> void:
	await step_ticks(RUNNING_TICKS)
	_ghost_rules.respawn_delay_seconds = 0.0

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var fell_at: Vector3 = victim.body.global_position
	assert_true(_controller.apply_hit(victim), "the prisoner is shot")

	assert_false(_controller.is_awaiting_respawn(victim), "nothing is being held")
	assert_eq_int(_respawned.size(), 1, "the placement happened on the tick of death")
	assert_gt(
		_flat(victim.body.global_position - fell_at), CLEAR_OF_THE_START_METRES,
		"and the ghost is no longer where it fell",
	)


# --- Which way a ghost runs ---------------------------------------------------

## A ghost chases DOWN THE TRACK, even when the field is past the halfway point.
##
## [b]The bug this pins, in the author's words:[/b] [i]"the bots go the wrong way
## when the person in first is past the halfway point and they are ghosts."[/i]
##
## A ghost is dealt back onto the start line and the field it is hunting is
## somewhere round the ring in front of it. The chase used to steer at the
## quarry's body -- a straight line -- and a straight line to anybody more than
## half a lap ahead points BACKWARDS along the course and through the pit in the
## middle of the deck, so the ghost turned round and ran against the direction of
## play into the inner kerb. The arc is the distance a ghost can actually cover,
## so the arc is what it steers on now: see [method RingRunner._chase_aim_point].
##
## The quarries are parked deliberately past halfway, at bearings chosen to be
## clear of the cover bands and the traps, and the assertion is about the sign of
## the ghost's own progress round the ring. Nothing here measures a catch: at
## most of a lap away there is no catch to measure, which is exactly the
## situation the bug lived in.
func test_a_ghost_past_halfway_still_chases_the_way_the_lap_runs() -> void:
	var centre: Vector3 = (_match.get_node("Arena") as Node3D).global_position

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot and becomes a ghost")
	await _await_respawn(victim)
	await step_ticks(SETTLE_TICKS)
	if not assert_true(victim.brain != null and victim.brain.is_chasing(), "the ghost is chasing"):
		return

	# The rest of the field, parked well past the halfway point. Bearings on the
	# clear channel at r=44.5 and away from Cover07_204deg, Trap04_218deg and
	# Cover08_232deg, so nothing here is standing inside the map.
	var bearings: Array[float] = [deg_to_rad(200.0), deg_to_rad(245.0)]
	var quarries: Array[MatchParticipant] = _controller.get_live_participants()
	for index: int in quarries.size():
		var quarry: MatchParticipant = quarries[index]
		if quarry.brain != null:
			quarry.brain.set_physics_process(false)
		quarry.body.set_physics_process(false)
		quarry.body.velocity = Vector3.ZERO
		var bearing: float = bearings[index % bearings.size()]
		# On the first gallery's deck: the ring is lifted, so the arena centre is
		# no longer the height a prisoner stands at.
		var route: RingRoute = _controller.get_route()
		var deck: float = centre.y if route == null else route.deck_height(0)
		quarry.body.global_position = Vector3(
			centre.x + cos(bearing) * _controller.get_rules().track_radius,
			deck + 1.0,
			centre.z + sin(bearing) * _controller.get_rules().track_radius,
		)

	# The straight line to either of them now runs backwards round the ring and
	# across the pit; the arc to either runs forwards. Which the ghost takes is
	# the whole test.
	var opened_at: float = _angle_about(centre, victim.body.global_position)
	if assert_not_null(victim.brain.get_chase_target(), "the chase is aimed at a living prisoner"):
		var aim_point: Vector3 = victim.brain.get_chase_aim_point()
		var aim_arc: float = wrapf(
			(_angle_about(centre, aim_point) - opened_at) * RingRunner.TRAVEL_SIGN, -PI, PI
		)
		assert_gt(aim_arc, 0.0, "the ghost steers at a point AHEAD of it, the way the lap runs")
		var aim_radius: float = Vector2(aim_point.x - centre.x, aim_point.z - centre.z).length()
		assert_between(
			aim_radius, DECK_INNER_RADIUS, DECK_OUTER_RADIUS,
			"and at a point on the deck, not across the pit in the middle of it",
		)

	await step_ticks(RUNNING_TICKS)

	var travelled: float = wrapf(
		(_angle_about(centre, victim.body.global_position) - opened_at) * RingRunner.TRAVEL_SIGN,
		-PI, PI,
	)
	assert_gt(
		travelled, 0.0,
		"a ghost with the field past halfway must still run the way the lap runs, not back down it",
	)
	# A metre and a half of arc in a second and a half is a walk, not float
	# noise on a body standing still against the kerb -- which is what the bug
	# actually looked like from outside.
	assert_gt(
		travelled * _controller.get_rules().track_radius, 1.5,
		"and it must actually be running, not grinding along the inner kerb",
	)


# --- Helpers ------------------------------------------------------------------

## Put [param ghost] where a chase would have taken it: in [param quarry]'s own
## spot.
##
## [b]In the spot, not merely within the catch radius.[/b] Every prisoner runs
## one track, so a second into a round the field is running together and a body
## placed a fraction of the catch radius off the quarry may well be nearer to
## somebody else -- and [method MatchController._catchable_from] rules on the
## NEAREST living prisoner, which is the mechanic. Standing on the quarry's own
## spot is the only placement that names the quarry unambiguously.
##
## Safe to do by hand precisely because a ghost is already off every collision
## layer and mask-wise cannot carry anything -- moving a body with collision live
## is the trap [method MatchController._hold_body] documents, and this is the one
## state in which it does not apply. The brain is stood down first so it does not
## steer away from the spot on the next tick.
func _put_ghost_on(
	ghost: MatchParticipant, quarry: MatchParticipant, spend_grace: bool
) -> void:
	# Both bodies are stopped where they stand. The quarry too: it is running at
	# 8 m/s and would otherwise leave the catch radius long before a grace clock
	# measured in seconds ran out, which would test the chase rather than the
	# rule. Nothing about the catch reads velocity.
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
	if spend_grace:
		ghost.ghost_grace_remaining = 0.0


## Wait out [param participant]'s respawn hold and return on the tick it expires
## -- which is the tick [method MatchController._finish_respawn] wrote the new
## position and before the placement's own two-frame settle has woken anything.
##
## Polled rather than slept for a flat [member GhostProfile.respawn_delay_seconds]
## so that a test which retunes the delay, or turns it off, needs no second edit.
func _await_respawn(participant: MatchParticipant) -> void:
	for _tick: int in HOLD_BUDGET_TICKS:
		if not _controller.is_awaiting_respawn(participant):
			return
		await step_ticks(1)


## The participant a rifle-mask ray through [param point] strikes, or null.
##
## Fired horizontally through the point from four metres out, at chest height,
## which crosses the body capsule whatever direction it happens to be facing.
##
## [b]Eight bearings rather than one.[/b] A single fixed line was enough while
## the prisoners ran the track in the open, and stopped being enough the moment
## they started playing the cover game in front of a human guard: a living
## prisoner tucked against a cover box has that box between it and one bearing
## in four, and a ray that hit the box read as "nobody is here" -- which is the
## exact opposite of what a POSITIVE control is for. Any bearing that reaches
## the body is proof the body is shootable; only a point that is unreachable
## from all eight is reported as empty, which makes the negative assertions --
## the ones about the ghost -- strictly harder to pass than they were.
func _participant_struck_at(point: Vector3, mask: int) -> MatchParticipant:
	var space: PhysicsDirectSpaceState3D = _controller.get_viewport().world_3d.direct_space_state
	var chest: Vector3 = point + Vector3(0.0, 0.9, 0.0)
	for step: int in 8:
		var bearing: float = TAU * float(step) / 8.0
		var reach: Vector3 = Vector3(cos(bearing), 0.0, sin(bearing)) * 4.0
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			chest + reach, chest - reach
		)
		query.collision_mask = mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var struck: MatchParticipant = _controller.resolve_participant(
			hit.get("collider") as Node3D
		)
		if struck != null:
			return struck
	return null


## The hit mask the match's own rifle shoots on, read off the live weapon rather
## than restated, so a retuned weapon profile retunes this test with it.
func _hit_mask() -> int:
	var rifle: Rifle = _match.get_node_or_null("Player/Head/Rifle") as Rifle
	if rifle == null or rifle.profile == null:
		return 0
	return rifle.profile.hit_mask


func _flat(delta: Vector3) -> float:
	return Vector2(delta.x, delta.z).length()


## Bearing of [param point] about the ring axis at [param centre].
func _angle_about(centre: Vector3, point: Vector3) -> float:
	return atan2(point.z - centre.z, point.x - centre.x)


func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	_resolutions += 1
	_last_outcome = int(outcome)


func _on_runner_ghosted(participant: MatchParticipant) -> void:
	_ghosted.append(participant)


func _on_ghost_respawned(participant: MatchParticipant) -> void:
	_respawned.append(participant)


func _on_ghost_caught(ghost: MatchParticipant, caught: MatchParticipant) -> void:
	_catches += 1
	_last_catch_ghost = ghost
	_last_catch_caught = caught
