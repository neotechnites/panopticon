class_name RunnerCoverFinder
extends RefCounted

## Where a prisoner could stand and not be shot, found by asking the world.
##
## [b]Nothing in this file knows anything about the arena.[/b] No cover
## positions, no lane radii, no piece count, no scene paths. It probes the map it
## is standing in with real raycasts and reports what it finds, so a second map
## with cover somewhere else needs no second version of this file and no new
## numbers in [RunnerProfile]. That is a hard requirement rather than good taste:
## the arena in the repository is a greybox, more are coming, and a bot that had
## been told where to hide would stop being a measuring instrument the day the
## first real map landed.
##
## [b]The question it asks[/b]
##
## For each candidate standing point, three rays, in the order that fails
## fastest:
##
## 1. [b]Is it hidden?[/b] A ray from the point at chest height to the guard's
##    eye. Blocked means cover. This is the shooter's own line-of-sight test --
##    literally, via [method RunnerPerception.has_clear_line] -- asked in advance
##    about a place the runner is not standing yet, so "I would be safe there"
##    and "I am safe here" can never come to mean two different things.
## 2. [b]Is it still hidden a step further on?[/b] The same ray from a point
##    [member RunnerProfile.cover_depth_metres] further round the ring. The near
##    edge of a shadow is a place you are hidden and one pace from not being;
##    this is what makes the runner stop somewhere it can actually hold.
## 3. [b]Can it be stood on?[/b] A ray straight down. A floor more than
##    [member RunnerProfile.cover_max_step_height] above or below the runner's own
##    feet is not somewhere it can walk to. This is what rejects the TOP of a
##    cover box -- a point that really is hidden from the tower and really is
##    unreachable -- and the pit in the middle of the ring, without either being
##    named.
##
## [b]Nearest, not furthest[/b]
##
## Candidates are swept in order of increasing arc and the FIRST piece of cover
## that advances the lap by at least
## [member RunnerProfile.cover_min_advance_metres] wins. Taking the furthest would
## make every crossing the longest one available, which is the opposite of the
## game: the prisoner's problem is to spend as little time in the open as it can,
## one gap at a time.

## Collision mask for the standability probe. Everything: a candidate is
## reachable or it is not, and that has nothing to do with what a bullet passes
## through.
const FLOOR_MASK: int = 0xFFFFF

## How far above and below a candidate the floor probe reaches, in metres. Deep
## enough to find the pit and be sure it is a pit.
const FLOOR_PROBE_METRES: float = 20.0

## The spot the last search settled on, in world space and at deck height.
var _position: Vector3 = Vector3.ZERO

## Arc from the search origin to [member _position], in radians, always positive
## and always in the direction of travel.
var _arc_gain: float = 0.0

## Whether the last search found anything at all.
var _found: bool = false

## Candidates probed by the last search. Diagnostics for a map that turns out to
## have no cover on it.
var _probes: int = 0


## Sweep the ring ahead of [param from_position] for the next piece of cover.
##
## [param centre] is the arena axis at deck height and [param travel_sign] the
## direction of the lap, both as [RingRunner] holds them.
## [param lane_radius] is the radius the runner would rather be on, and is used
## ONLY to break ties. The band that is actually probed is centred on where the
## runner is standing NOW, which is not the same thing once it has taken cover
## twice: a prisoner assigned the inner lane and currently tucked behind an outer
## box would otherwise sweep a band of deck eleven metres away from itself, find
## nothing, and fall back to sprinting down the open track -- which is the exact
## failure this whole file exists to remove, and it cost a measured round of
## debugging to see.
##
## [param limit_arc] caps the sweep at the arc the runner has left to run, so the
## search never proposes cover past the finish line.
##
## Returns true when something was found; [method get_position] then holds it.
func search(
	perception: RunnerPerception,
	profile: RunnerProfile,
	space: PhysicsDirectSpaceState3D,
	from_position: Vector3,
	centre: Vector3,
	travel_sign: float,
	lane_radius: float,
	limit_arc: float,
) -> bool:
	_found = false
	_position = Vector3.ZERO
	_arc_gain = 0.0
	_probes = 0
	if perception == null or profile == null or space == null:
		return false

	var threat_eye: Vector3 = perception.get_threat_eye()
	var from_angle: float = _angle_of(from_position, centre)
	var from_radius: float = Vector2(
		from_position.x - centre.x, from_position.z - centre.z
	).length()
	var arc: float = minf(profile.get_cover_search_arc_radians(), maxf(limit_arc, 0.0))
	if arc <= 0.0:
		return false

	var steps: int = maxi(profile.cover_search_steps, 1)
	var min_arc: float = profile.cover_min_advance_metres / maxf(lane_radius, 0.001)
	var depth_arc: float = profile.cover_depth_metres / maxf(lane_radius, 0.001)

	for step: int in range(1, steps + 1):
		var step_arc: float = arc * float(step) / float(steps)
		if step_arc < min_arc:
			continue
		var angle: float = from_angle + travel_sign * step_arc
		var best: Vector3 = Vector3.ZERO
		var best_deviation: float = INF

		for radius: float in _radii(profile, from_radius):
			var point: Vector3 = _point_at(centre, angle, radius, from_position.y)
			_probes += 1
			if not _is_hidden(perception, profile, point, threat_eye):
				continue
			var deeper: Vector3 = _point_at(
				centre, angle + travel_sign * depth_arc, radius, from_position.y
			)
			if not _is_hidden(perception, profile, deeper, threat_eye):
				continue
			if not _is_standable(space, profile, point, from_position.y):
				continue
			var deviation: float = absf(radius - lane_radius)
			if deviation < best_deviation:
				best_deviation = deviation
				best = point

		if best_deviation < INF:
			_position = best
			_arc_gain = step_arc
			_found = true
			return true

	return false


## Where the runner should go, valid only when the last [method search] returned
## true.
func get_position() -> Vector3:
	return _position


## Arc, in radians, from the search origin to that spot.
func get_arc_gain() -> float:
	return _arc_gain


func has_result() -> bool:
	return _found


## How many standing points the last search tested. A map on which this is large
## and [method has_result] is false is a map with no cover on it.
func get_probe_count() -> int:
	return _probes


# --- Probes -------------------------------------------------------------------

## True when a shot from the tower could not reach a body standing at
## [param point].
func _is_hidden(
	perception: RunnerPerception, profile: RunnerProfile, point: Vector3, threat_eye: Vector3
) -> bool:
	var chest: Vector3 = point + Vector3.UP * profile.cover_test_height
	return not perception.has_clear_line(chest, threat_eye)


## True when there is a floor under [param point] within one step of the height
## the runner is standing at now.
func _is_standable(
	space: PhysicsDirectSpaceState3D, profile: RunnerProfile, point: Vector3, feet_y: float
) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * FLOOR_PROBE_METRES,
		point + Vector3.DOWN * FLOOR_PROBE_METRES,
	)
	query.collision_mask = FLOOR_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var floor_point: Vector3 = hit.get("position", Vector3.ZERO)
	return absf(floor_point.y - feet_y) <= profile.cover_max_step_height


## The radii to probe: a band of [member RunnerProfile.cover_search_radial_span]
## centred on where the runner is standing. An odd step count keeps one sample
## exactly on the runner's current radius, which is the cheapest candidate to
## reach and therefore the right one to have in the set.
func _radii(profile: RunnerProfile, centre_radius: float) -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	var count: int = maxi(profile.cover_search_radial_steps, 1)
	if count == 1:
		radii.append(centre_radius)
		return radii
	var span: float = profile.cover_search_radial_span
	for index: int in count:
		var fraction: float = float(index) / float(count - 1)
		radii.append(centre_radius - span * 0.5 + span * fraction)
	return radii


# --- Ring geometry ------------------------------------------------------------

func _angle_of(point: Vector3, centre: Vector3) -> float:
	return atan2(point.z - centre.z, point.x - centre.x)


func _point_at(centre: Vector3, angle: float, radius: float, height: float) -> Vector3:
	return Vector3(
		centre.x + cos(angle) * radius,
		height,
		centre.z + sin(angle) * radius,
	)
