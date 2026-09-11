class_name RingRoute
extends Node3D

## The run, as data: which decks a prisoner must lap, in what order, and where
## the ramps between them are.
##
## [b]What progress IS, now that there is more than one deck.[/b]
##
## The arena used to be one circle and progress used to be one number: the arc
## swept about the axis. That measurement was right for exactly as long as an
## angle identified a position. It stopped the moment a second deck existed at
## the same angle five and a half metres up.
##
## What replaces it is [b]one monotonic distance along a three-lap route[/b]:
## the metres banked for every level already finished, plus the arc swept so far
## on the current level taken at that level's own lane radius. It is still an
## arc measurement -- the same accumulator, the same wrap handling, the same
## indifference to the radius a body chooses to run at -- with a level index
## beside it and a conversion to metres so that laps of different sizes can be
## added up. See [method metres_travelled].
##
## The alternatives were considered and are worse. Raw path length rewards a
## prisoner who paces about behind cover over one who runs. A single arc
## accumulated across all three levels cannot tell a runner who has climbed from
## one who has run three laps of the bottom deck. A per-level fraction averaged
## together makes a metre on the short bottom lap worth more than a metre on the
## long top one, which is a scoring rule nobody chose.
##
## [b]A level is banked on two tests, not one.[/b] The arc for the level must be
## swept AND the body must be standing at the height of the level above. Arc
## alone would let a runner who wandered onto the ramp early bank a lap they had
## not run; height alone would let one who walked up the trench from the start
## line bank two. Together they are exactly the rule Ryan asked for: you have to
## complete three 360s to get to the tower.
##
## [b]The levels stack.[/b] Ryan: "the levels should be right on top of one
## another, not like a staircase." Every deck of the shipped arena is the same
## annulus at a different height, which is what makes the map one column of ring
## seen from one point. Nothing in this file cares -- a route is a list of decks
## and the arithmetic is the same whatever radii they hold -- but it is why
## [method validate] checks heights and ramps and says nothing about radii: two
## levels sharing a band is the design, not a fault. Whether the guard can
## actually see under the deck above is a question about the ARENA's geometry and
## the tower's height, and it is answered in the arena scene, where both are
## known.
##
## [b]It never steers and it never scores.[/b] This is a lookup table with the
## arithmetic of the route on it. [MatchLapTracker] scores off it, [RingRunner]
## steers off it, [MatchHUD] reads metres off it, and none of them holds a second
## opinion about where the run goes.

## Direction the lap runs, as a sign on swept angle. It must agree with
## [constant RingRunner.TRAVEL_SIGN]; the two are separate constants rather than
## one because the ring script and the bot script would otherwise have to import
## each other, and [code]tests/test_levels.gd[/code] asserts they match.
const TRAVEL_SIGN: float = 1.0

## The least a level may sit above the one below it, in metres. A jump apex on
## the tuned movement profile is 1.11 m; anything under about twice that is not a
## storey, it is a kerb, and the ramp between them would be a step somebody could
## hop.
const MINIMUM_RISE: float = 2.5

## How far above a deck a body still counts as standing on it, in metres. Wide
## enough to cover a body that is airborne over its own deck or settling onto
## it, and far narrower than the smallest rise between two levels.
const DECK_TOLERANCE: float = 0.6

var _levels: Array[RingLevel] = []
var _scanned: bool = false


func _ready() -> void:
	_scan()


## The levels of this route, lowest first. Empty on a route with no levels
## authored under it, which [method validate] reports and callers treat as a map
## with no route at all.
func get_levels() -> Array[RingLevel]:
	_scan()
	return _levels


func level_count() -> int:
	return get_levels().size()


## The last level: the one whose exit is the finish.
func last_index() -> int:
	return maxi(level_count() - 1, 0)


## Level [param index], clamped into range. Null only on an empty route.
func level_at(index: int) -> RingLevel:
	var levels: Array[RingLevel] = get_levels()
	if levels.is_empty():
		return null
	return levels[clampi(index, 0, levels.size() - 1)]


func lane_radius(index: int) -> float:
	var level: RingLevel = level_at(index)
	return 1.0 if level == null else maxf(level.lane_radius, 0.001)


func deck_height(index: int) -> float:
	var level: RingLevel = level_at(index)
	return 0.0 if level == null else level.deck_height


func entry_angle(index: int) -> float:
	var level: RingLevel = level_at(index)
	return 0.0 if level == null else deg_to_rad(level.entry_angle_degrees)


func exit_angle(index: int) -> float:
	var level: RingLevel = level_at(index)
	return 0.0 if level == null else deg_to_rad(level.exit_angle_degrees)


## Arc a prisoner owes on level [param index], in radians, always positive and
## always in the direction of travel.
##
## Wrapped into [code][0, TAU)[/code] exactly as [MatchLapTracker] and
## [RingRunner] used to do it against the two markers: the long way round
## whenever the short way is behind us, which for an entry and an exit a few
## degrees apart is the lap.
func lap_arc(index: int) -> float:
	var level: RingLevel = level_at(index)
	if level == null:
		return 0.0
	var swept: float = deg_to_rad(level.exit_angle_degrees - level.entry_angle_degrees)
	return wrapf(swept * TRAVEL_SIGN, 0.0, TAU)


## That lap in metres, at the level's own lane radius.
func lap_metres(index: int) -> float:
	return lap_arc(index) * lane_radius(index)


## The whole route, in metres. What a prisoner has to cover to take the tower.
func total_metres() -> float:
	var total: float = 0.0
	for index: int in level_count():
		total += lap_metres(index)
	return total


## Metres banked by having FINISHED every level below [param level]. The floor
## a runner on that level is measured up from.
func metres_banked(level: int) -> float:
	var total: float = 0.0
	for index: int in clampi(level, 0, level_count()):
		total += lap_metres(index)
	return total


## Metres of the route covered by a runner [param travelled_arc] radians into
## level [param level].
##
## The arc is clamped to the level's own lap before it is counted, so the
## overshoot a runner accumulates while climbing a ramp -- which sweeps forward
## past the exit -- is not banked twice when the level ticks over.
func metres_travelled(level: int, travelled_arc: float) -> float:
	var index: int = clampi(level, 0, last_index())
	var on_this_level: float = clampf(travelled_arc, 0.0, lap_arc(index))
	return metres_banked(index) + on_this_level * lane_radius(index)


## Metres of the route still to run. What the HUD counts down.
func metres_remaining(level: int, travelled_arc: float) -> float:
	return maxf(total_metres() - metres_travelled(level, travelled_arc), 0.0)


## Fraction of the whole route covered, 0.0 on the start line and 1.0 at the
## finish.
func progress(level: int, travelled_arc: float) -> float:
	var total: float = total_metres()
	if total <= 0.0:
		return 0.0
	return clampf(metres_travelled(level, travelled_arc) / total, 0.0, 1.0)


## True when there is a level above [param index] to climb to.
func has_level_above(index: int) -> bool:
	return index < last_index()


## Foot of the ramp off level [param index], in world space: the level's exit
## angle at its ramp radius, on its own deck.
func ramp_foot(centre: Vector3, index: int) -> Vector3:
	var level: RingLevel = level_at(index)
	if level == null:
		return centre
	var radius: float = level.ramp_foot_radius
	if radius <= 0.0:
		radius = level.lane_radius
	return _point(centre, exit_angle(index), radius, level.deck_height)


## Top of that ramp: the NEXT level's entry angle at the landing radius, on the
## next level's deck.
func ramp_top(centre: Vector3, index: int) -> Vector3:
	var level: RingLevel = level_at(index)
	if level == null or not has_level_above(index):
		return ramp_foot(centre, index)
	var above: RingLevel = level_at(index + 1)
	var radius: float = level.ramp_landing_radius
	if radius <= 0.0:
		radius = above.lane_radius
	return _point(centre, entry_angle(index + 1), radius, above.deck_height)


## A point on level [param index]'s lane at [param angle], at deck height.
func point_on_lane(centre: Vector3, index: int, angle: float) -> Vector3:
	return _point(centre, angle, lane_radius(index), deck_height(index))


## A point on level [param index] at an arbitrary radius, at deck height. What a
## runner's ramp approach interpolates along.
func point_on_level(centre: Vector3, index: int, angle: float, radius: float) -> Vector3:
	return _point(centre, angle, radius, deck_height(index))


## The level a body at world height [param y] is standing on: the highest one
## whose deck is at or below it, within [constant DECK_TOLERANCE].
##
## Height rather than radius, deliberately. The bands are disjoint so radius
## would also answer, but a body on a ramp is between two bands and over the one
## it came from; height keeps it on the level it has actually left, which is the
## level it is still being scored against until it arrives.
func level_for_height(y: float) -> int:
	var found: int = 0
	for index: int in level_count():
		if y + DECK_TOLERANCE >= deck_height(index):
			found = index
	return found


## True when a body at [param y] has arrived on level [param index]'s deck.
func is_standing_on(index: int, y: float) -> bool:
	return y + DECK_TOLERANCE >= deck_height(index)


## Everything wrong with this route, in words, or an empty array.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var levels: Array[RingLevel] = get_levels()
	if levels.is_empty():
		problems.append("%s has no levels under it; there is no route." % name)
		return problems
	for index: int in levels.size():
		problems.append_array(levels[index].validate())
		if lap_arc(index) <= 0.0:
			problems.append("%s has no lap to run." % levels[index].name)
	for index: int in range(1, levels.size()):
		var below: RingLevel = levels[index - 1]
		var level: RingLevel = levels[index]
		if level.deck_height <= below.deck_height:
			problems.append(
				"%s is at y=%.1f, not above %s at y=%.1f."
				% [level.name, level.deck_height, below.name, below.deck_height]
			)
		if level.deck_height - below.deck_height < MINIMUM_RISE:
			problems.append(
				(
					"%s is only %.1f m above %s. A level has to clear the one below it by"
					+ " more than a body can jump, or the ramp between them is a step."
				) % [level.name, level.deck_height - below.deck_height, below.name]
			)
		if not below.has_ramp():
			problems.append("%s has no ramp up off it; %s is unreachable." % [below.name, level.name])
	return problems


## Build a one-level route from a track radius and the arena's own markers, for
## a map that authors no [RingRoute] of its own.
##
## [b]The fallback is the whole reason a second map does not need a second code
## path.[/b] Everything downstream -- the tracker, the runner brain, the HUD --
## reads a route and only a route; a flat arena is a route with one level on it,
## scored by exactly the arithmetic the ring used before any of this existed.
##
## The returned node is not in the tree. The caller owns it and must parent or
## free it.
static func flat(
	track_radius: float, centre: Vector3, start_point: Vector3, end_point: Vector3
) -> RingRoute:
	var route: RingRoute = RingRoute.new()
	route.name = "FlatRoute"
	var level: RingLevel = RingLevel.new()
	level.name = "Level1"
	level.deck_height = start_point.y
	level.lane_radius = maxf(track_radius, 0.001)
	level.inner_radius = 0.0
	level.outer_radius = maxf(track_radius, 0.001) * 4.0
	level.entry_angle_degrees = rad_to_deg(_angle_about(centre, start_point))
	level.exit_angle_degrees = rad_to_deg(_angle_about(centre, end_point))
	level.ramp_foot_radius = 0.0
	level.ramp_landing_radius = 0.0
	route.add_child(level)
	route._levels = [level]
	route._scanned = true
	return route


func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_levels = []
	for child: Node in get_children():
		var level: RingLevel = child as RingLevel
		if level != null:
			_levels.append(level)


func _point(centre: Vector3, angle: float, radius: float, height: float) -> Vector3:
	return Vector3(centre.x + cos(angle) * radius, height, centre.z + sin(angle) * radius)


static func _angle_about(centre: Vector3, point: Vector3) -> float:
	return atan2(point.z - centre.z, point.x - centre.x)
