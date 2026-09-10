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

	# And still in the WORLD -- this is the assertion that separates a ghost
	# from the park a converted runner gets.
	assert_gt(
		victim.body.global_position.y, PARKED_DEPTH_METRES,
		"a ghost is not buried in the pen",
	)
	assert_true(victim.body.visible, "a ghost is visible")
	assert_true(victim.body.is_physics_processing(), "a ghost's body is still being stepped")
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
		"a ghost is on no physics layer, so nothing can find it",
	)
	assert_eq_int(
		victim.body.collision_mask, control.body.collision_mask,
		"a ghost still collides with the world it walks on",
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

	var quarry: MatchParticipant = _controller.get_live_participants()[0]
	assert_gt(quarry.tracker.get_progress(), 0.0, "the quarry has a lap worth taking")
	var carried_progress: float = quarry.tracker.get_progress()

	var living_before: int = _controller.get_runners_remaining()
	var ghosts_before: int = _controller.get_ghosts_remaining()

	_put_ghost_on(victim, quarry, true)
	await step_ticks(2)

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
	var quarry: MatchParticipant = _controller.get_live_participants()[0]

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


## The participant a rifle-mask ray through [param point] strikes, or null.
##
## Fired horizontally through the point from four metres out, which crosses the
## body capsule at chest height whatever direction it happens to be facing.
func _participant_struck_at(point: Vector3, mask: int) -> MatchParticipant:
	var space: PhysicsDirectSpaceState3D = _controller.get_viewport().world_3d.direct_space_state
	var chest: Vector3 = point + Vector3(0.0, 0.9, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		chest + Vector3(0.0, 0.0, 4.0), chest + Vector3(0.0, 0.0, -4.0)
	)
	query.collision_mask = mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	return _controller.resolve_participant(hit.get("collider") as Node3D)


## The hit mask the match's own rifle shoots on, read off the live weapon rather
## than restated, so a retuned weapon profile retunes this test with it.
func _hit_mask() -> int:
	var rifle: Rifle = _match.get_node_or_null("Player/Head/Rifle") as Rifle
	if rifle == null or rifle.profile == null:
		return 0
	return rifle.profile.hit_mask


func _flat(delta: Vector3) -> float:
	return Vector2(delta.x, delta.z).length()


func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	_resolutions += 1
	_last_outcome = int(outcome)


func _on_runner_ghosted(participant: MatchParticipant) -> void:
	_ghosted.append(participant)


func _on_ghost_caught(ghost: MatchParticipant, caught: MatchParticipant) -> void:
	_catches += 1
	_last_catch_ghost = ghost
	_last_catch_caught = caught
