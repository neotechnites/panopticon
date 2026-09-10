extends TestCase

## The traps: red blocks that kill on contact, and pits you fall through.
##
## Canon, in the author's words: [i]"for traps, right now just create som
## obsitcles that are red and kill you, and some pits that let oyu fall into the
## kill box. nothing fancy at all just make it a bit more trecherous."[/i]
##
## Three claims are worth a test and the rest is placement judgement.
##
## 1. [b]A trap kills through the door the rifle kills through.[/b] Not "the
##    victim dies" -- that a trap routes into
##    [method MatchController.convert_participant] and therefore becomes a ghost
##    on the start line, counted as a conversion, exactly as a shot prisoner
##    does. A trap that grew a death of its own is what this notices.
## 2. [b]A pit is really a hole, and it really opens onto the kill volume.[/b]
##    A CSG subtraction that failed to cut, or a hole outboard of a volume that
##    only reaches r=35, both look identical from the editor and both leave a
##    prisoner falling forever.
## 3. [b]The racing line is still clear.[/b] The shipped [RingRunner] baseline
##    has no obstacle avoidance at all -- it holds full forward at a point on the
##    [member MatchRules.track_radius] circle four metres ahead. Anything lethal
##    on that circle is a game that cannot be played, so every trap and every pit
##    is asserted to leave the line alone. [code]tests/test_runner.gd[/code] then
##    runs a real bot round the real trapped arena, which is the proof; this is
##    the cheap check that says WHY when that one breaks.

## Ticks to let a freshly armed round settle before it is measured.
const SETTLE_TICKS: int = 60

## Ticks allowed for a volume to notice a body and the match to answer.
const CONTACT_TICKS: int = 12

## Ticks allowed for a body to fall through a pit and be answered for. The deck
## is 1 m thick and the volume's roof hangs 3 m below it, so this is about a
## metre and a half of free fall plus the settle that follows.
const FALL_TICKS: int = 90

## Top of the courtyard floor, in metres, as [code]test_kill_volume.gd[/code]
## reads it: the 1 m PitFloor slab sits at y=-12.5, so a body stands at -12.
const PIT_FLOOR_Y: float = -12.0

## How close two angles about the ring axis must be to count as the same bearing.
const START_ANGLE_TOLERANCE: float = 1e-3

## How much clear deck a hazard must leave on each side of the racing line.
##
## The body is a 0.4 m capsule, so this is five body radii of room either way --
## far more than the baseline's steering error, and the number the placement in
## [code]scenes/ring/bentham_ring.tscn[/code] was chosen against (the tightest
## hazard there leaves 2.25 m). It is deliberately not derived from the cover
## bands: the point of the check is to fail loudly if somebody moves a trap onto
## the line, not to track whatever the cover happens to do.
const TRACK_CLEARANCE_METRES: float = 2.0

## Mask for the floor probes. Everything, so a hole that is a hole under any
## layer scheme still reads as a hole.
const FLOOR_MASK: int = 0xFFFFF

## How far down a floor probe looks. Past the courtyard floor and past the
## bottom of the kill volume, so "nothing hit" means nothing at all.
const PROBE_DEPTH_METRES: float = 40.0

## Ticks a respawn hold is polled for before a test gives up on it. A second
## clear of the shipped three -- see [member GhostProfile.respawn_delay_seconds].
const HOLD_BUDGET_TICKS: int = 240


var _match: Node3D
var _arena: Node3D
var _controller: MatchController
var _rules: MatchRules

var _centre: Vector3 = Vector3.ZERO
var _start_point: Vector3 = Vector3.ZERO

var _ghosted: Array[MatchParticipant] = []
var _ghosted_at: Array[Vector3] = []

## Where each ghost was actually PUT DOWN, and when. Separate from the two above
## because a death and a placement are no longer the same tick: every death is
## held for [member GhostProfile.respawn_delay_seconds] where it happened, and
## only then is the body moved to the start line. Read off
## [signal MatchController.ghost_respawned], which fires on the tick of the
## placement and before the chase brain has carried the body anywhere.
var _respawned: Array[MatchParticipant] = []
var _respawned_at: Array[Vector3] = []


func before_each() -> void:
	_match = TestFixtures.make_match()

	# Handed over before the instance enters the tree, exactly as
	# test_kill_volume.gd does it: MatchController arms the match from _ready and
	# the rule set has to be the one it arms on.
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_controller.rules = _rules

	add_child(_match)

	_controller.runner_ghosted.connect(_on_runner_ghosted)
	_controller.ghost_respawned.connect(_on_ghost_respawned)

	_arena = _match.get_node("Arena") as Node3D
	_centre = _arena.global_position
	_start_point = (_arena.get_node(TestFixtures.START_MARKER_PATH) as Marker3D).global_position

	# The shipped match opens with a race. Hand the tower to the HUMAN through
	# the seam the match scores on, so every test below starts from a round with
	# a known shooter who has nobody at the keyboard -- and therefore a round in
	# which nothing but the trap under test can kill anybody.
	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)


# --- The red blocks -----------------------------------------------------------

## The arena ships traps, they are triggers, and the red you see is the red that
## kills.
##
## The size is asserted against the export rather than against numbers typed
## here, for the same reason [code]test_kill_volume.gd[/code] asserts the kill
## volume's cylinder that way: both children are written from
## [member TrapVolume.size_metres] on ready, so this proves the three agree and
## leaves the tuning free to move.
func test_the_arena_ships_red_traps_that_are_triggers() -> void:
	var traps: Array[TrapVolume] = _traps()
	assert_gt(float(traps.size()), 0.0, "the arena ships traps at all")

	var body_layer: int = _controller.get_participants()[0].home_collision_layer
	for trap: TrapVolume in traps:
		var where: String = String(trap.name)
		assert_true(trap.monitoring, "%s is watching for bodies" % where)
		assert_eq_int(
			trap.collision_layer, 0,
			"%s is on no layer of its own -- nothing else has to know it is there" % where,
		)
		assert_gt(
			float(trap.collision_mask & body_layer), 0.0,
			"%s does watch the layer a player body is on" % where,
		)

		var holder: CollisionShape3D = _shape_holder(trap)
		assert_not_null(holder, "%s has a shape to be" % where)
		if holder == null:
			continue
		var box: BoxShape3D = holder.shape as BoxShape3D
		assert_not_null(box, "%s is sized from its export on ready" % where)
		if box == null:
			continue
		assert_vec3_almost_eq(
			box.size, trap.size_metres, 1e-4,
			"%s detects over exactly the exported extent" % where,
		)

		var block: CSGBox3D = _block_of(trap)
		assert_not_null(block, "%s draws something" % where)
		if block == null:
			continue
		assert_vec3_almost_eq(
			block.size, trap.size_metres, 1e-4,
			"%s draws exactly the volume that kills" % where,
		)
		assert_false(
			block.use_collision,
			"%s is not solid -- it is not cover and it occludes nothing" % where,
		)

	# The round has been running for a second and nobody has walked into one.
	assert_eq_int(_controller.get_ghosts_remaining(), 0, "no trap takes anybody on the line")
	assert_eq_int(
		_controller.get_runners_remaining(), _rules.prisoner_count,
		"and the ring is still full",
	)


## A prisoner who touches a trap dies the way the rifle kills: as a ghost, on the
## start line, counted as a conversion.
##
## [b]Every assertion here is an assertion [code]test_ghosts.gd[/code] makes
## about a SHOT prisoner, and that is the entire point of the test.[/b] The trap
## is a second route into the same door, not a second door.
func test_a_prisoner_who_touches_a_trap_becomes_a_ghost() -> void:
	var traps: Array[TrapVolume] = _traps()
	if not assert_gt(float(traps.size()), 0.0, "there is a trap to walk into"):
		return

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	var living_before: int = _controller.get_runners_remaining()
	assert_gt(float(living_before), 1.0, "the round has prisoners in it to lose")

	_put_on_the_trap(victim, traps[0])
	await step_ticks(CONTACT_TICKS)

	assert_true(victim.is_ghost, "a prisoner who touches red is a ghost")
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
	if _ghosted.size() == 1:
		assert_same(_ghosted[0], victim, "for the prisoner who touched it")

	# The placement WAITS. A trap death is held where it happened for
	# [member GhostProfile.respawn_delay_seconds] like every other death, so the
	# body is still standing on the red when the death is announced.
	assert_eq_int(_ghosted_at.size(), 1, "the death was recorded")
	assert_true(
		_controller.is_awaiting_respawn(victim),
		"and the body is held on the trap rather than moved immediately",
	)
	await _await_respawn(victim)

	# Back on the start line, which is where a conversion puts a ghost -- and the
	# proof that the trap went through convert_participant rather than doing
	# something of its own that merely looked like it.
	assert_eq_int(_respawned_at.size(), 1, "the placement was recorded")
	if _respawned_at.size() == 1:
		assert_almost_eq(
			absf(wrapf(_angle_about(_respawned_at[0]) - _angle_about(_start_point), -PI, PI)),
			0.0, START_ANGLE_TOLERANCE,
			"they were put down at the start line's own bearing",
		)
	assert_false(
		victim.body.is_in_group(MatchController.RUNNER_GROUP),
		"and are not a legitimate target",
	)


## A ghost that touches a trap is returned to the start, not lost.
##
## Same ruling as the kill volume's: [i]"yeah, put them back at the start, even
## if they hit the trap"[/i]. Every assertion mirrors
## [code]test_kill_volume.gd[/code]'s
## [code]test_a_ghost_who_falls_in_is_returned_to_the_start[/code] -- the two
## hazards share the one door in [method MatchController.handle_fall], and the
## same [constant MatchController.GHOST_HAZARD_LAYER] is what lets either of
## them see a ghost in the first place.
func test_a_ghost_who_touches_a_trap_is_returned_to_the_start() -> void:
	var traps: Array[TrapVolume] = _traps()
	if not assert_gt(float(traps.size()), 0.0, "there is a trap to walk into"):
		return

	var victim: MatchParticipant = _controller.get_live_participants()[0]
	assert_true(_controller.apply_hit(victim), "a prisoner is shot to make a ghost")
	await _await_respawn(victim)
	await step_ticks(SETTLE_TICKS)
	assert_true(victim.is_ghost, "the victim is a settled ghost")
	assert_eq_int(
		victim.body.collision_layer, MatchController.GHOST_HAZARD_LAYER,
		"and stands on the layer the trap's mask has been widened to watch",
	)
	var ghosts_before: int = _controller.get_ghosts_remaining()
	var ghosted_before: int = _ghosted.size()

	var respawns_before: int = _respawned_at.size()
	_put_on_the_trap(victim, traps[0])

	# A ghost a hazard catches is held exactly as long as a prisoner the rifle
	# kills -- [i]"weather youre alive or already a ghost"[/i] -- so the wait is
	# run out and the position is read off the signal that fires on the tick of
	# the placement itself. Reading the body afterwards would instead read
	# wherever the chase brain had carried it, which is what broke this
	# assertion the first time it was written.
	await step_ticks(CONTACT_TICKS)
	await _await_respawn(victim)
	if not assert_gt(
		float(_respawned_at.size()), float(respawns_before),
		"the trap put the ghost back",
	):
		return
	var returned_at: Vector3 = _respawned_at[_respawned_at.size() - 1]

	# Let the rest of the placement's own settle play out before checking that
	# it woke -- a separate concern from where it was put.
	await step_ticks(CONTACT_TICKS)

	assert_true(victim.is_ghost, "the ghost is still a ghost -- not lost, not un-ghosted")
	assert_false(victim.is_running, "and still not a prisoner")
	assert_eq_int(
		_controller.get_ghosts_remaining(), ghosts_before,
		"the trap neither removed the ghost nor made a second one",
	)
	assert_eq_int(
		_ghosted.size(), ghosted_before,
		"runner_ghosted is not announced again -- this is not a second death",
	)
	assert_eq_int(
		_controller.get_runners_removed(), 1,
		"still exactly the one conversion the rifle made",
	)

	# Back on the start line, exactly where a ghost is always put.
	assert_almost_eq(
		absf(wrapf(_angle_about(returned_at) - _angle_about(_start_point), -PI, PI)),
		0.0, START_ANGLE_TOLERANCE,
		"they were put down at the start line's own bearing",
	)
	assert_true(victim.body.is_physics_processing(), "the ghost's body is being stepped again")


# --- The pits -----------------------------------------------------------------

## Every pit is a real hole with nothing under it, and every hole is inside the
## kill volume's extent.
##
## Both halves are needed and each is worthless alone. A CSG subtraction that
## silently failed to cut leaves solid deck that looks like a pit in the editor;
## a hole outboard of a volume that only reaches the courtyard leaves a prisoner
## falling past the bottom of the world forever. The control probe on the racing
## line is what stops this passing because the raycast itself was wrong.
func test_every_pit_is_a_hole_that_opens_onto_the_kill_volume() -> void:
	var volume: KillVolume = _arena.get_node_or_null(^"KillBox") as KillVolume
	if not assert_not_null(volume, "the arena still ships a kill volume"):
		return

	var pits: Array[Node3D] = _pits()
	assert_gt(float(pits.size()), 0.0, "the deck has pits cut in it")

	for pit: Node3D in pits:
		var where: String = String(pit.name)
		var centre: Vector3 = pit.global_position

		assert_null(
			_probe_floor_under(centre),
			"%s is a real hole -- nothing at all is under it" % where,
		)

		# The whole hole, not just its middle, has to be over the volume.
		var hole: CSGCylinder3D = pit as CSGCylinder3D
		var reach: float = _flat_distance(centre, _centre)
		if hole != null:
			reach += hole.radius
		assert_lt(
			reach, volume.radius_metres,
			"%s falls entirely inside the volume's radius" % where,
		)
		assert_lt(
			-volume.roof_depth_metres, 0.0,
			"%s drops onto a roof that is below the deck" % where,
		)

	# The probe works. Without this, a raycast that hit nothing anywhere would
	# report every square metre of the arena as a pit.
	assert_not_null(
		_probe_floor_under(_point_on_track(_rules.track_radius, _angle_about(_start_point))),
		"the racing line is still solid deck under the same probe",
	)


## A racer who drops through a pit is answered for, and is OUT of the race.
##
## The end-to-end version of the test above: a real body, real gravity, the real
## hole, and the real volume underneath. It is run in the RACE rather than in a
## round on purpose -- the race has no shooter at all, so nothing but the pit can
## remove anybody, and the victim is the human's body, which has no brain and no
## hand on the keyboard and therefore falls straight down instead of steering out
## of its own grave.
func test_a_racer_who_drops_through_a_pit_is_out() -> void:
	var pits: Array[Node3D] = _pits()
	if not assert_gt(float(pits.size()), 0.0, "there is a pit to fall into"):
		return

	# Back to the top of the match: before_each handed the tower over to get a
	# round, and this is the test that wants the race.
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)
	assert_eq_string(_controller.get_phase_name(), "RACE", "the match is racing")

	var victim: MatchParticipant = _controller.get_participants()[0]
	assert_null(victim.brain, "the victim is the inert human body, not a bot")
	var field: int = _controller.get_participants().size()

	var over: Vector3 = pits[0].global_position
	victim.body.velocity = Vector3.ZERO
	victim.body.global_position = Vector3(over.x, _deck_y() + 0.5, over.z)
	await step_ticks(FALL_TICKS)

	assert_false(victim.is_running, "the racer is out")
	assert_lt(
		victim.body.global_position.y, PIT_FLOOR_Y,
		"they are parked in the pen, not standing on a deck that never opened",
	)
	assert_eq_int(
		_controller.get_runners_remaining(), field - 1,
		"and it cost exactly the one racer",
	)


# --- The racing line ----------------------------------------------------------

## Nothing lethal stands on the line the shipped runner brain holds.
##
## [b]This is the check that keeps the game playable.[/b] [RingRunner]'s baseline
## faces a point on its level's lane circle and holds full forward with no
## avoidance of any kind, for the whole lap, and the opening race is nothing but
## that baseline four times over. A trap or a pit on a lane is a race that can
## never be finished.
##
## [b]It asks the ROUTE which lanes exist rather than being told.[/b] There are
## three of them now, at three radii, and a hazard is only allowed to be clear of
## the one lane it happens to share a deck with -- an inner trap on level three
## is at r=77.5, which would read as "clear" against level one's r=44.5 while
## sitting on top of level three's runners. So every hazard is matched to the
## level whose deck it stands on, by height, and judged against that level's
## lane. A fourth level added to the map is covered by this test without a line
## being changed here.
func test_every_trap_and_pit_leaves_the_racing_line_clear() -> void:
	var route: RingRoute = _controller.get_route()
	if not assert_not_null(route, "the arena should carry a route to check the lanes of"):
		return

	for trap: TrapVolume in _traps():
		var level: RingLevel = _level_under(route, trap.global_position.y)
		var inner: float = level.lane_radius - TRACK_CLEARANCE_METRES
		var outer: float = level.lane_radius + TRACK_CLEARANCE_METRES
		var band: Vector2 = _radial_band_of_box(trap.global_transform, trap.size_metres)
		assert_true(
			band.y <= inner or band.x >= outer,
			"%s (r%.2f-r%.2f) is clear of %s's racing line r%.2f-r%.2f"
			% [trap.name, band.x, band.y, level.name, inner, outer],
		)

	for pit: Node3D in _pits():
		var hole: CSGCylinder3D = pit as CSGCylinder3D
		if hole == null:
			continue
		# A pit is a subtraction, so its own Y is the middle of the drum it is
		# cut through rather than the deck it opens in. The deck is the one whose
		# radial band it falls inside.
		var reach: float = _flat_distance(pit.global_position, _centre)
		var level: RingLevel = _level_around(route, reach)
		var inner: float = level.lane_radius - TRACK_CLEARANCE_METRES
		var outer: float = level.lane_radius + TRACK_CLEARANCE_METRES
		var low: float = reach - hole.radius
		var high: float = reach + hole.radius
		assert_true(
			high <= inner or low >= outer,
			"%s (r%.2f-r%.2f) is clear of %s's racing line r%.2f-r%.2f"
			% [pit.name, low, high, level.name, inner, outer],
		)


## The level whose deck a thing standing at [param height] is on.
func _level_under(route: RingRoute, height: float) -> RingLevel:
	return route.level_at(route.level_for_height(height))


## The level whose radial band [param radius] falls in.
func _level_around(route: RingRoute, radius: float) -> RingLevel:
	var found: RingLevel = route.level_at(0)
	for index: int in route.level_count():
		var level: RingLevel = route.level_at(index)
		if radius >= level.inner_radius - 0.001 and radius <= level.outer_radius + 0.001:
			found = level
	return found


# --- Helpers ------------------------------------------------------------------

## Every trap in the arena, found by type rather than by path.
func _traps() -> Array[TrapVolume]:
	var found: Array[TrapVolume] = []
	for node: Node in _walk(_arena):
		var trap: TrapVolume = node as TrapVolume
		if trap != null:
			found.append(trap)
	return found


## Every pit in the arena. Found by group, because a pit is a CSG subtraction
## with no script on it and nothing else to recognise it by.
func _pits() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in _walk(_arena):
		var pit: Node3D = node as Node3D
		if pit != null and pit.is_in_group(&"deck_pits"):
			found.append(pit)
	return found


func _shape_holder(trap: TrapVolume) -> CollisionShape3D:
	for child: Node in trap.get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


func _block_of(trap: TrapVolume) -> CSGBox3D:
	for child: Node in trap.get_children():
		var block: CSGBox3D = child as CSGBox3D
		if block != null:
			return block
	return null


## Stand [param participant] in the middle of [param trap], on the deck.
##
## A teleport rather than a walk, for the reason [code]test_kill_volume.gd[/code]
## gives: the volume does not care how the body arrived, and walking one into a
## trap is a lap of simulation to prove something about a trigger. Safe to do by
## hand because a trap carries no collision, so there is nothing here to
## depenetrate out of.
func _put_on_the_trap(participant: MatchParticipant, trap: TrapVolume) -> void:
	var where: Vector3 = trap.global_position
	participant.body.velocity = Vector3.ZERO
	participant.body.global_position = Vector3(where.x, _deck_y() + 0.05, where.z)


## What a body standing at [param point] would land on, or null for nothing at
## all within [constant PROBE_DEPTH_METRES].
func _probe_floor_under(point: Vector3) -> Object:
	var space: PhysicsDirectSpaceState3D = _arena.get_world_3d().direct_space_state
	if space == null:
		return null
	# From just above the point ITSELF, not from y=0.5: the galleries are stacked,
	# so a probe dropped from a fixed height finds the ceiling of the deck it was
	# asking about, or nothing at all.
	var from: Vector3 = Vector3(point.x, point.y + 0.5, point.z)
	var to: Vector3 = Vector3(point.x, point.y + 0.5 - PROBE_DEPTH_METRES, point.z)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, FLOOR_MASK
	)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.has("collider"):
		return null
	return hit.get("collider") as Object


## The walking surface of the first gallery, which is where every body this file
## drops onto the deck belongs. Zero on a map with no route.
func _deck_y() -> float:
	var route: RingRoute = _controller.get_route()
	return _centre.y if route == null else route.deck_height(0)


## The band of radii about the ring axis a horizontal box occupies.
##
## Sampled over the box's footprint rather than taken from its corners: the point
## of an inner face is nearer the axis than either of its corners is, so a corner
## test would report a hazard as further off the line than it really is, which is
## the one direction this must never be wrong in.
func _radial_band_of_box(where: Transform3D, size: Vector3) -> Vector2:
	const STEPS: int = 8
	var low: float = INF
	var high: float = 0.0
	for ix: int in range(STEPS + 1):
		for iz: int in range(STEPS + 1):
			var local: Vector3 = Vector3(
				(float(ix) / float(STEPS) - 0.5) * size.x,
				0.0,
				(float(iz) / float(STEPS) - 0.5) * size.z,
			)
			var radius: float = _flat_distance(where * local, _centre)
			low = minf(low, radius)
			high = maxf(high, radius)
	return Vector2(low, high)


func _point_on_track(radius: float, angle: float) -> Vector3:
	# On the FIRST level's deck. The arena is three galleries stacked at one
	# radius now, so a point on the racing line is not a point until it says
	# which deck it is on.
	var route: RingRoute = _controller.get_route()
	var height: float = _centre.y if route == null else route.deck_height(0)
	return Vector3(
		_centre.x + cos(angle) * radius, height, _centre.z + sin(angle) * radius
	)


func _angle_about(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	for child: Node in root.get_children():
		found.append_array(_walk(child))
	return found


func _on_runner_ghosted(participant: MatchParticipant) -> void:
	_ghosted.append(participant)
	_ghosted_at.append(participant.body.global_position)


func _on_ghost_respawned(participant: MatchParticipant) -> void:
	_respawned.append(participant)
	_respawned_at.append(participant.body.global_position)

## Wait out [param participant]'s respawn hold, returning on the tick it expires.
##
## Every death in a match is held before the body is moved, so a test that
## asserts about the PLACEMENT has to get the hold out of the way first. Polled
## rather than slept for a flat duration, so retuning the delay needs no edit
## here.
func _await_respawn(participant: MatchParticipant) -> void:
	for _tick: int in HOLD_BUDGET_TICKS:
		if not _controller.is_awaiting_respawn(participant):
			return
		await step_ticks(1)

