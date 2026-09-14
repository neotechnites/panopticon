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
## 3. [b]The lap can still be run past the hazards.[/b] The lava now sits ON the
##    deck, deliberately: the shelf and the demon run are hazards you go round,
##    and [RingNavigation] bakes the deck with every trap carved out of it so a
##    runner has a route that misses them. What is worth asserting is therefore
##    not "nothing lethal is near the lane" -- something lethal is, by design --
##    but that a navigated path from the start marker to the end marker still
##    exists and does not cross a single trap.

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

## How far inboard of the deck's own inner edge the pit probes are dropped.
## Clear of the edge's own bevel, and nowhere near the tower in the middle.
const VOID_MARGIN_METRES: float = 2.0

## How many bearings round the ring the pit is probed at. Eight is enough to
## catch a deck that grew a floor over one quadrant of the courtyard.
const VOID_BEARINGS: int = 8

## How close a navigated route must finish to the end marker to count as having
## reached it. The marker stands on the deck and not on the navmesh, so the
## route stops on the nearest polygon; a polygon here is metres across.
const PATH_ARRIVAL_METRES: float = 8.0

## Ticks allowed for a body to fall from the deck into the kill volume.
##
## The deck is at y=23 and the volume's roof hangs at y=-8, so this is thirty
## one metres of free fall under a 22 m/s^2 gravity -- about 1.7 seconds, and
## this is two clear of it. [constant FALL_TICKS] is sized for the metre and a
## half a trap drop used to be, and is nowhere near enough for the open pit.
const PIT_FALL_TICKS: int = 210

## Idle frames a feet-only trap is given to notice a body standing in it.
##
## [member TrapVolume.grace_seconds] is spent in [method Node._process], not in
## the physics step, and the runner compresses time by driving physics far
## faster than the main loop -- so a wait counted in physics ticks can contain
## almost no idle frames at all. This one is counted in the frames that carry
## the timer.
const TRAP_GRACE_FRAMES: int = 240

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

		# The lava is DRAWN by the map model now, not by a CSG block this node
		# owns, so there is nothing here to compare the visual against. What is
		# still this node's own is that it is a trigger and not an obstacle:
		# no collision shape of its own beyond the detection box above, and
		# nothing under it a body could stand on or shoot through.
		assert_false(
			trap.monitorable,
			"%s is invisible to other areas -- it is a trigger, not a thing" % where,
		)
		assert_true(
			trap.feet_only,
			"%s catches a body by the feet, so a leap over it is a leap over it" % where,
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
	await _await_trap_catch(victim)

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
	# The rest of the field is scenery here, and it has to stay alive: this test
	# waits out two respawn holds, and a round that resolves inside either of
	# them clears the hold without ever placing the ghost.
	TestFixtures.pin_the_field(_controller, victim)
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
	await _await_trap_catch(victim)
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

## The pit inside the deck is a real hole, and it opens onto the kill volume.
##
## The holes that used to be cut through the deck are gone: the map model ships
## one annulus with an open middle, and THAT is the pit. The claim is the one the
## cut-out pits made and the failure it catches is the same -- a floor where the
## drop should be leaves a racer standing in mid-air over the courtyard, and a
## hole outboard of the volume leaves one falling past the bottom of the world.
## The control probe on the racing line is what stops this passing because the
## raycast itself was wrong.
func test_the_pit_inside_the_deck_opens_onto_the_kill_volume() -> void:
	var volume: KillVolume = _arena.get_node_or_null(^"KillBox") as KillVolume
	if not assert_not_null(volume, "the arena still ships a kill volume"):
		return
	var route: RingRoute = _controller.get_route()
	if not assert_not_null(route, "and a route to read the deck's edge off"):
		return

	var level: RingLevel = route.level_at(0)
	var reach: float = level.inner_radius - VOID_MARGIN_METRES
	var deck: float = _deck_y()
	var roof: float = volume.global_position.y - volume.roof_depth_metres
	assert_gt(reach, 0.0, "the deck really is an annulus with a middle to fall into")
	assert_lt(reach, volume.radius_metres, "and the middle is inside the volume's radius")
	assert_lt(roof, deck, "whose roof hangs below the deck a body steps off")

	for step: int in VOID_BEARINGS:
		var angle: float = TAU * float(step) / float(VOID_BEARINGS)
		assert_lt(
			_floor_y_under(_point_on_track(reach, angle)), roof,
			"the pit is open at %d degrees -- the first floor under it is below the volume's roof"
			% int(round(rad_to_deg(angle))),
		)

	# The probe works. Without this, a raycast that fell through everything would
	# report every square metre of the arena as a pit.
	assert_gt(
		_floor_y_under(_point_on_track(_rules.track_radius, _angle_about(_start_point))),
		deck - 1.0,
		"the racing line is still solid deck under the same probe",
	)


## A racer who drops into the pit is answered for, and is OUT of the race.
##
## The end-to-end version of the test above: a real body, real gravity, the real
## hole, and the real volume underneath. It is run in the RACE rather than in a
## round on purpose -- the race has no shooter at all, so nothing but the drop
## can remove anybody, and the victim is the human's body, which has no brain and
## no hand on the keyboard and therefore falls straight down instead of steering
## out of its own grave.
func test_a_racer_who_drops_into_the_pit_is_out() -> void:
	var route: RingRoute = _controller.get_route()
	if not assert_not_null(route, "the arena should carry a route"):
		return

	# Back to the top of the match: before_each handed the tower over to get a
	# round, and this is the test that wants the race.
	_controller.start_match()
	await step_ticks(SETTLE_TICKS)
	assert_eq_string(_controller.get_phase_name(), "RACE", "the match is racing")

	var victim: MatchParticipant = _controller.get_participants()[0]
	assert_null(victim.brain, "the victim is the inert human body, not a bot")
	var field: int = _controller.get_participants().size()

	var level: RingLevel = route.level_at(0)
	var over: Vector3 = _point_on_track(
		level.inner_radius - VOID_MARGIN_METRES, _angle_about(_start_point)
	)
	victim.body.velocity = Vector3.ZERO
	victim.body.global_position = Vector3(over.x, _deck_y() + 0.5, over.z)
	await step_ticks(PIT_FALL_TICKS)

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

## A lap can still be navigated past every hazard, without touching one.
##
## [b]This is the check that keeps the game playable.[/b] The lava is on the
## deck on purpose and the old "nothing lethal within two metres of the lane"
## rule would now forbid the map Ryan built. What has to hold instead is that
## the navigation the runners steer on still joins the start marker to the end
## marker, and that the route it hands back does not pass through lava -- which
## is exactly what [RingNavigation] carves the traps out of the bake for.
## [code]tests/test_runner.gd[/code] then runs a real bot round the real arena,
## which is the proof; this is the cheap check that says WHY when that one breaks.
func test_a_lap_can_be_navigated_past_every_hazard() -> void:
	var start: Vector3 = _start_point
	var finish: Vector3 = (
		_arena.get_node(TestFixtures.END_MARKER_PATH) as Marker3D
	).global_position

	var map: RID = _arena.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, finish, true)
	if not assert_gt(float(path.size()), 1.0, "the bake joins the start line to the finish"):
		return
	assert_lt(
		_flat_distance(path[path.size() - 1], finish), PATH_ARRIVAL_METRES,
		"and the route actually reaches it rather than stopping at a hazard",
	)

	for trap: TrapVolume in _traps():
		var worst: String = ""
		for point: Vector3 in path:
			if _is_lethal_at(trap, point):
				worst = "%s at %v" % [trap.name, point]
				break
		assert_eq_string(worst, "", "the navigated lap does not cross %s" % trap.name)


## True when a body standing at [param point] would be converted by [param trap]:
## inside its box, or, for a feet_only one, at or below the surface it kills at.
func _is_lethal_at(trap: TrapVolume, point: Vector3) -> bool:
	var half: Vector3 = trap.size_metres * 0.5
	var local: Vector3 = trap.global_transform.affine_inverse() * point
	if absf(local.x) > half.x or absf(local.z) > half.z:
		return false
	var ceiling: float = TrapVolume._FEET_DEPTH if trap.feet_only else half.y
	return local.y <= ceiling and local.y >= -half.y
# --- Helpers ------------------------------------------------------------------

## Every trap in the arena, found by type rather than by path.
func _traps() -> Array[TrapVolume]:
	var found: Array[TrapVolume] = []
	for node: Node in _walk(_arena):
		var trap: TrapVolume = node as TrapVolume
		if trap != null:
			found.append(trap)
	return found
func _shape_holder(trap: TrapVolume) -> CollisionShape3D:
	for child: Node in trap.get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


## Stand [param participant] in the middle of [param trap], on the deck.
##
## A teleport rather than a walk, for the reason [code]test_kill_volume.gd[/code]
## gives: the volume does not care how the body arrived, and walking one into a
## trap is a lap of simulation to prove something about a trigger. Safe to do by
## hand because a trap carries no collision, so there is nothing here to
## depenetrate out of.
func _put_on_the_trap(participant: MatchParticipant, trap: TrapVolume) -> void:
	# The trap's OWN height, not the first deck's: the lava lies on whichever
	# deck it was placed on, and a trap only catches a body whose feet are at or
	# below its origin (see TrapVolume.feet_only), so a body stood at a height
	# taken from somewhere else is a body it is entitled to ignore.
	participant.body.velocity = Vector3.ZERO
	participant.body.global_position = trap.global_position


## How high the first floor under [param point] is, or -[constant INF] when
## there is nothing within [constant PROBE_DEPTH_METRES].
func _floor_y_under(point: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _arena.get_world_3d().direct_space_state
	if space == null:
		return -INF
	var from: Vector3 = Vector3(point.x, point.y + 0.5, point.z)
	var to: Vector3 = Vector3(point.x, point.y + 0.5 - PROBE_DEPTH_METRES, point.z)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, FLOOR_MASK
	)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.has("position"):
		return -INF
	return (hit.get("position") as Vector3).y


## Wait for a feet-only trap to spend its grace on [param victim], counted in
## the idle frames that grace actually runs in. See [constant TRAP_GRACE_FRAMES].
##
## The respawn hold is what is waited on, because both answers a trap can give
## open with one: a prisoner it converts is held where it died, and a ghost it
## catches is held before it is put back.
func _await_trap_catch(victim: MatchParticipant) -> void:
	var tree: SceneTree = get_tree()
	for _frame: int in TRAP_GRACE_FRAMES:
		if _controller.is_awaiting_respawn(victim):
			return
		await tree.process_frame


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

