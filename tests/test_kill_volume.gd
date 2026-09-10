extends TestCase

## The kill box under the arena: what falling into the courtyard costs.
##
## Canon, in the author's words: [i]"we should have a kill box below"[/i]. The
## middle of PANOPTICON is a twelve metre drop with the guard's platform standing
## alone in it, and before this volume existed the courtyard floor CAUGHT people
## -- a prisoner who mistimed a jump and a guard who walked off their own stand
## both ended up alive at the bottom of a pit, out of the game without being out
## of it.
##
## [b]There is only one death in this game and the volume does not own it.[/b]
## The assertion that matters below is not that a faller dies but that they die
## the way the RIFLE kills: through [method MatchController.convert_participant],
## into a ghost, on the start line, counted as a conversion. A second death path
## would drift from the first the moment either changed.
##
## [b]The guard is the open question.[/b] A guard who falls is put back on the
## tower, unharmed -- see [method MatchController.handle_fall] for why, and note
## that it is a decision made in the absence of a ruling rather than a rule.
## These tests pin the behaviour that is implemented; they are not an argument
## that it is the right one.
##
## Everything here runs the real [code]scenes/match/match.tscn[/code] on a
## private copy of the shipped rules, which play
## [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP].

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## Ticks allowed for the volume to notice a body and the match to answer. An
## [Area3D] reports an overlap on a physics step, and the placement that follows
## settles for [constant MatchController.SETTLE_PHYSICS_FRAMES] more.
const FALL_TICKS: int = 12

## Where a body is put to make it fallen: the middle of the courtyard, below the
## volume's roof and above the floor it would otherwise stand on.
const DROP_HEIGHT_METRES: float = -8.0

## Top of the courtyard floor, in metres. [code]scenes/ring/test_ring.tscn[/code]
## puts the 1 m PitFloor slab at y=-12.5, so a body stands at -12.
const PIT_FLOOR_Y: float = -12.0

## How far from the tower spawn still counts as standing on the tower.
const SPAWN_TOLERANCE_METRES: float = 0.5

## How close two angles about the ring axis must be to count as the same bearing.
const START_ANGLE_TOLERANCE: float = 1e-3

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _rifle: Rifle

var _centre: Vector3 = Vector3.ZERO
var _start_point: Vector3 = Vector3.ZERO
var _tower_spawn: Vector3 = Vector3.ZERO

var _ghosted: Array[MatchParticipant] = []

## Where each ghost was standing on the tick it was made. Read from the signal
## rather than from the body afterwards, because a ghost is chasing from the
## moment it is placed and the claim under test is about the PLACEMENT.
var _ghosted_at: Array[Vector3] = []

var _resolutions: int = 0

## Races armed since before_each finished wiring. The only way to tell a restart
## from a race that simply never ended: the phase reads RACE either way.
var _races_started: int = 0


func before_each() -> void:
	_match = TestFixtures.make_match()

	# Handed over before the instance enters the tree: MatchController arms the
	# match from _ready and the rule set has to be the one it arms on.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_controller.rules = _rules

	add_child(_match)

	_controller.runner_ghosted.connect(_on_runner_ghosted)
	_controller.round_resolved.connect(_on_round_resolved)
	_controller.race_started.connect(_on_race_started)

	var arena: Node3D = _match.get_node("Arena") as Node3D
	_centre = arena.global_position
	_start_point = (arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D).global_position
	_tower_spawn = (arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D).global_position
	_rifle = _controller.rifle

	# The shipped match opens with a race. Hand it to the human through the same
	# seam the match scores on, so every test below starts from a round with a
	# known shooter instead of from a 35 second lap.
	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


# --- The volume itself --------------------------------------------------------

## The arena ships the volume, it fills the courtyard, and it takes nobody who is
## standing on the map.
##
## The extent is asserted against the exports rather than against numbers typed
## here: the shape is written from them on ready, so this proves the two agree
## and leaves the tuning free to move. What is checked absolutely is the two
## things the extent has to be true of -- it must contain the courtyard floor a
## body would otherwise stand on, and it must stop well short of the pen a
## converted body is parked in, or a parked body would be reported as falling
## forever.
func test_the_arena_ships_a_kill_volume_over_the_courtyard() -> void:
	var arena: Node3D = _match.get_node("Arena") as Node3D
	var volume: KillVolume = arena.get_node_or_null(^"KillBox") as KillVolume
	assert_not_null(volume, "the arena scene ships a kill volume")
	if volume == null:
		return

	assert_true(volume.monitoring, "it is watching for bodies")
	assert_eq_int(
		volume.collision_layer, 0,
		"and is on no layer of its own -- nothing else has to know it is there",
	)
	var body_layer: int = _controller.get_participants()[0].home_collision_layer
	assert_gt(
		float(volume.collision_mask & body_layer), 0.0,
		"but it does watch the layer a player body is on",
	)

	var holder: CollisionShape3D = _shape_holder(volume)
	assert_not_null(holder, "the volume has a shape to be")
	if holder == null:
		return
	var cylinder: CylinderShape3D = holder.shape as CylinderShape3D
	assert_not_null(cylinder, "sized from the exports on ready rather than left empty")
	if cylinder == null:
		return

	assert_almost_eq(cylinder.radius, volume.radius_metres, 1e-4, "the radius is the exported one")
	assert_almost_eq(cylinder.height, volume.depth_metres, 1e-4, "and the depth is too")

	var roof: float = holder.position.y + cylinder.height * 0.5
	var floor_y: float = holder.position.y - cylinder.height * 0.5
	assert_almost_eq(
		roof, -volume.roof_depth_metres, 1e-4,
		"and the roof hangs where the exported depth says",
	)
	assert_lt(roof, 0.0, "the roof is below the deck, so nobody standing on it is falling")
	assert_lt(
		floor_y, PIT_FLOOR_Y,
		"the volume reaches past the courtyard floor a body would otherwise stand on",
	)
	assert_gt(
		floor_y, MatchController.PEN_DEPTH_METRES,
		"and stops well above the pen a converted body is parked in",
	)

	# The round has been running for a second and nobody has fallen into it.
	assert_eq_int(_controller.get_ghosts_remaining(), 0, "it takes nobody who is on the deck")
	assert_eq_int(
		_controller.get_runners_remaining(), _rules.prisoner_count,
		"and the ring is still full",
	)


# --- A prisoner ---------------------------------------------------------------

## A prisoner who falls in dies the way the rifle kills: as a ghost, on the start
## line, counted as a conversion.
##
## Every assertion here is the assertion [code]test_ghosts.gd[/code] makes about
## a SHOT prisoner, and that is the point of it. If the volume ever grew a death
## of its own this test is what would notice.
func test_a_prisoner_who_falls_in_becomes_a_ghost() -> void:
	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var living_before: int = _controller.get_runners_remaining()
	assert_gt(float(living_before), 1.0, "the round has prisoners in it to lose")

	_put_in_the_courtyard(victim)
	await step_ticks(FALL_TICKS)

	assert_true(victim.is_ghost, "a prisoner who falls is a ghost")
	assert_false(victim.is_running, "and is out of the round")
	assert_eq_string(victim.get_role_name(), "GHOST", "the role reads GHOST")
	assert_eq_int(
		_controller.get_runners_remaining(), living_before - 1,
		"the ring is one prisoner lighter",
	)
	assert_eq_int(
		_controller.get_runners_removed(), 1,
		"and the match counted it as a conversion, exactly as it counts a rifle hit",
	)
	assert_eq_int(_ghosted.size(), 1, "runner_ghosted is announced once")
	assert_same(_ghosted[0], victim, "for the prisoner who fell")
	assert_eq_int(_resolutions, 0, "one fall does not resolve the round")

	# Out of the pit and back on the start line, which is where a ghost is made.
	assert_gt(
		victim.body.global_position.y, PIT_FLOOR_Y,
		"the faller is not left standing at the bottom of the courtyard",
	)
	assert_eq_int(_ghosted_at.size(), 1, "the placement was recorded")
	if _ghosted_at.size() == 1:
		assert_almost_eq(
			absf(wrapf(_angle_about(_ghosted_at[0]) - _angle_about(_start_point), -PI, PI)),
			0.0, START_ANGLE_TOLERANCE,
			"they were put down at the start line's own bearing",
		)
	assert_false(
		victim.body.is_in_group(MatchController.RUNNER_GROUP),
		"and are not a legitimate target",
	)
	assert_true(victim.body.is_physics_processing(), "the ghost's body is being stepped again")


# --- The guard ----------------------------------------------------------------

## A guard who falls in is put back on the tower, unharmed, and nothing else
## about the match moves.
##
## [b]This is the behaviour in the absence of a ruling, not a rule.[/b] Killing
## the seat holder would need answers nobody has given -- what an empty tower
## means, who gets it, whether the round survives -- and a guard left at the
## bottom of the pit is a round that can be neither won nor lost. So they are put
## back where they belong, and the assertions below are about how little else
## changes: no turn spent or earned, no round restarted, no runner touched, and
## the rifle never out of their hands.
func test_the_guard_who_falls_in_is_put_back_on_the_tower() -> void:
	var seat: MatchParticipant = _controller.get_seat_participant()
	assert_not_null(seat, "somebody holds the tower")
	if seat == null:
		return
	var turns_before: int = seat.turns_in_tower
	var round_before: int = _controller.get_round_number()
	var reload_before: float = _controller.get_current_reload_seconds()

	_put_in_the_courtyard(seat)
	await step_ticks(FALL_TICKS)

	assert_same(_controller.get_seat_participant(), seat, "the guard still holds the tower")
	assert_true(seat.is_shooter, "and is still the shooter")
	assert_false(seat.is_ghost, "a guard who falls is not made a ghost")
	assert_false(seat.is_running, "and is not put out on the track")
	assert_almost_eq(
		_flat_distance(seat.body.global_position, _tower_spawn), 0.0,
		SPAWN_TOLERANCE_METRES, "they are standing back on the tower",
	)
	assert_gt(
		seat.body.global_position.y, PIT_FLOOR_Y,
		"and not at the bottom of the courtyard",
	)

	assert_eq_int(seat.turns_in_tower, turns_before, "the fall neither spent nor earned a turn")
	assert_eq_int(_controller.get_round_number(), round_before, "and did not restart the round")
	assert_eq_int(_controller.get_resolve_count(), 0, "and resolved nothing")
	assert_eq_int(_resolutions, 0, "and announced nothing")
	assert_almost_eq(
		_controller.get_current_reload_seconds(), reload_before, 1e-4,
		"the reload is the one they already had",
	)
	assert_same(_rifle.get_parent(), seat.body.head, "the rifle never left their hands")

	assert_eq_int(
		_controller.get_runners_remaining(), _rules.prisoner_count,
		"and the ring is untouched",
	)
	assert_eq_int(_controller.get_ghosts_remaining(), 0, "nobody became a ghost")
	assert_true(seat.body.is_physics_processing(), "the guard is back on their feet")


# --- The opening race ---------------------------------------------------------

## A racer who falls in is OUT of the race.
##
## The author's ruling: [i]"if a racer falls durring the opening race they can be
## out."[/i] It replaced a respawn an agent had invented. OUT is the same parking
## a converted prisoner gets under
## [constant MatchRules.GhostBehaviour.NONE] -- body out of the world, brain
## stopped, tracker stopped -- and it is NOT a ghost: the race has no shooter, so
## there is nothing for a ghost to chase and nothing for a conversion to mean.
##
## What the rest of the field does is the other half of the claim, and it is
## asserted here too: one racer falling costs one racer, the race stays on, and
## the tower stays empty until somebody still running crosses the line.
func test_a_racer_who_falls_in_is_out_of_the_race() -> void:
	# Back to the top of the match: before_each handed the tower over to get a
	# round, and this is the one test that wants the race.
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)
	assert_eq_string(_controller.get_phase_name(), "RACE", "the match is racing")

	# A bot, because the human's body has nobody at the keyboard to drive it.
	var racer: MatchParticipant = _first_bot_racer()
	assert_not_null(racer, "the race has a bot in it")
	if racer == null:
		return
	var field: int = _controller.get_participants().size()
	assert_gt(field, 1, "there is a field to be removed from")

	_put_in_the_courtyard(racer)
	await step_ticks(FALL_TICKS)

	assert_false(racer.is_running, "the racer is out")
	assert_false(racer.is_ghost, "there is no shooter, so there is no ghost to become")
	assert_false(racer.body.visible, "their body is out of the world")
	assert_eq_int(racer.body.collision_layer, 0, "and cannot be touched")
	assert_false(racer.body.is_physics_processing(), "or move")
	assert_false(
		racer.body.is_in_group(MatchController.RUNNER_GROUP),
		"and is not a runner any more",
	)
	assert_lt(
		racer.body.global_position.y, PIT_FLOOR_Y,
		"they are parked in the pen, not standing at the bottom of the courtyard",
	)

	assert_eq_string(_controller.get_phase_name(), "RACE", "the race is still on")
	assert_eq_int(
		_controller.get_runners_remaining(), field - 1,
		"and it cost exactly the one racer",
	)
	assert_null(_controller.get_seat_participant(), "with still nobody in the tower")


## An out racer cannot cross the line, so they cannot take the tower.
##
## The arrival seam is where OUT has to bite or it is only cosmetic: the race is
## scored first-past-the-post through
## [signal MatchLapTracker.lap_finished], and a parked racer whose tracker still
## reported would win a race from the bottom of the pen.
func test_a_racer_who_is_out_cannot_take_the_tower() -> void:
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)

	var racer: MatchParticipant = _first_bot_racer()
	assert_not_null(racer, "the race has a bot in it")
	if racer == null:
		return

	_put_in_the_courtyard(racer)
	await step_ticks(FALL_TICKS)
	assert_false(racer.is_running, "the racer is out")

	# Fired by hand: the tracker has been stopped, which is the point -- this is
	# the loudest possible version of the report it can no longer make.
	racer.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(2)

	assert_eq_string(_controller.get_phase_name(), "RACE", "the race is still on")
	assert_null(_controller.get_seat_participant(), "and the tower is still empty")


## Every racer out means the match restarts.
##
## The rest of the author's ruling: [i]"if everyone goes out, the match
## restarts."[/i] With the whole field parked nobody can ever reach the end, so
## the race is unscoreable and the match would sit in it forever. The restart is
## counted off [signal MatchController.race_started] rather than inferred from
## the phase, because the phase is RACE both before and after and only the
## signal tells the two apart.
func test_the_match_restarts_when_every_racer_falls_out() -> void:
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)
	assert_eq_int(_races_started, 1, "one race has been armed")

	_put_the_whole_field_in_the_courtyard()
	await step_ticks(FALL_TICKS)

	assert_eq_int(_races_started, 2, "the match restarted the moment the field emptied")
	assert_eq_string(_controller.get_phase_name(), "RACE", "into another race")
	assert_eq_int(
		_controller.get_runners_remaining(), _controller.get_participants().size(),
		"with the whole field back on the line",
	)
	assert_null(_controller.get_seat_participant(), "and nobody in the tower")
	for participant: MatchParticipant in _controller.get_participants():
		assert_true(participant.body.visible, "%s is back in the world" % participant.display_name)
		assert_gt(
			participant.body.global_position.y, PIT_FLOOR_Y,
			"%s is out of the pen" % participant.display_name,
		)
		assert_almost_eq(
			participant.tracker.get_progress(), 0.0, 0.05,
			"%s has the whole lap to run again" % participant.display_name,
		)


# --- Helpers ------------------------------------------------------------------

## Put [param participant]'s body in the middle of the courtyard, below the deck.
##
## A teleport rather than a fall. Walking a body off the edge and waiting for
## gravity is twelve metres of simulation to prove something about a trigger
## volume, and the volume does not care how the body arrived. Safe to do by hand
## because the courtyard is empty: the trap
## [method MatchController._hold_body] documents needs something standing where
## the body is being moved from or to, and there is nothing down here.
func _put_in_the_courtyard(participant: MatchParticipant) -> void:
	participant.body.velocity = Vector3.ZERO
	participant.body.global_position = _centre + Vector3(0.0, DROP_HEIGHT_METRES, 0.0)


## Put every participant in the courtyard at once, spread out.
##
## Spread, because [method _put_in_the_courtyard]'s licence to teleport is that
## the courtyard is empty -- stacking the field in one cubic metre is exactly the
## depenetration trap that licence depends on not happening. Two metres apart is
## clear of the capsules and still deep inside a volume 35 m across.
func _put_the_whole_field_in_the_courtyard() -> void:
	for participant: MatchParticipant in _controller.get_participants():
		participant.body.velocity = Vector3.ZERO
		participant.body.global_position = _centre + Vector3(
			float(participant.index) * 2.0, DROP_HEIGHT_METRES, 0.0
		)


## The first participant in the race who is actually running under its own power.
func _first_bot_racer() -> MatchParticipant:
	for participant: MatchParticipant in _controller.get_live_participants():
		if participant.brain != null:
			return participant
	return null


## The volume's shape node, found by type rather than by name.
func _shape_holder(volume: KillVolume) -> CollisionShape3D:
	for child: Node in volume.get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


## Bearing of [param point] about the ring axis.
func _angle_about(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func _on_runner_ghosted(participant: MatchParticipant) -> void:
	_ghosted.append(participant)
	_ghosted_at.append(participant.body.global_position)


func _on_round_resolved(_outcome: MatchController.Outcome) -> void:
	_resolutions += 1


func _on_race_started() -> void:
	_races_started += 1
