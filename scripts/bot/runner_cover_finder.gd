class_name RunnerCoverFinder
extends RefCounted

## Where a prisoner could stand and not be shot, found by asking the world.
##
## [b]Nothing in this file knows anything about the arena.[/b] No cover
## positions, no track radius, no piece count, no scene paths. It probes the map it
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
## 4. [b]Is there floor all the way there?[/b] The same downward ray, repeated
##    every [constant PATH_STEP_METRES] along the straight line the runner would
##    actually walk. See [method path_is_walkable].
## 5. [b]Is it a hazard?[/b] A candidate inside a [TrapVolume] box, or reached by
##    a straight line that crosses one, is rejected. See [method collect_hazards]
##    and [method segment_crosses_hazard]; nothing here names a map's hazards.
##
## [b]The fourth probe is a bug fix, and it is worth saying which one.[/b] For a
## long time this file asked only whether the DESTINATION had a floor, and the
## crossing itself was never checked. That is fine on a solid deck and fatal on
## one with holes in it: a runner would find real cover on the far side of a
## pit, price the crossing on exposure alone, commit, and walk straight into the
## hole -- the observed failure being a cover runner that falls out of the world
## on a map whose cover is perfectly reachable by going round. Three levels and
## twelve pits made that certain rather than likely, so the path is now probed
## as well as the endpoint, and a candidate you cannot walk to in a straight
## line is not a candidate. [RingRunner] applies the same test to its open-ground
## fallback, which this file never sees.
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

## How far BELOW a candidate the floor probe reaches, in metres. Deep enough to
## find the pit and be sure it is a pit.
##
## There is no matching number for how far ABOVE it starts, and that is the
## point: see [method _floor_within_a_step].
const FLOOR_PROBE_METRES: float = 20.0

## How far above a candidate the floor probe STARTS, over and above the step the
## runner is allowed to take. Just enough to be clear of the surface it is
## looking for and nothing like enough to reach a ceiling.
const FLOOR_PROBE_LIFT_METRES: float = 0.25

## How far apart the floor probes along a crossing path stand, in metres.
##
## The narrowest hazard on the shipped arena is a five metre pit, so a metre and
## a half guarantees at least two samples inside any of them. Finer costs
## raycasts on a search that already runs a few dozen; coarser can step over a
## hole.
const PATH_STEP_METRES: float = 1.5

## Margin added to a hazard box for the runner's own capsule, in metres.
const HAZARD_MARGIN_METRES: float = 0.8

## Spacing of hazard samples along a crossing, in metres.
const HAZARD_STEP_METRES: float = 0.5

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

## Resumable search state: the step to probe next and the pose it was started from.
const RESUME_MOVE_METRES: float = 3.0

## Raycasts every runner's cover search may spend per physics frame, shared.
const RAYS_PER_FRAME: int = 80
static var _ray_frame: int = -1
static var _rays_spent: int = 0
var _radius_index: int = 0
var _best: Vector3 = Vector3.ZERO
var _best_deviation: float = INF
var _step: int = 1
var _complete: bool = true
var _key_from: Vector3 = Vector3.ZERO
var _key_eye: Vector3 = Vector3.ZERO


## Sweep the ring ahead of [param from_position] for the next piece of cover.
##
## [param centre] is the arena axis at deck height and [param travel_sign] the
## direction of the lap, both as [RingRunner] holds them.
## [param track_radius] is the radius the runner would rather be on, and is used
## ONLY to break ties. The band that is actually probed is centred on where the
## runner is standing NOW, which is not the same thing once it has taken cover
## twice: a prisoner tucked behind a box on the far side of the deck from the
## track would otherwise sweep a band eleven metres away from itself, find
## nothing, and fall back to sprinting down the open track -- which is the exact
## failure this whole file exists to remove, and it cost a measured round of
## debugging to see.
##
## [param limit_arc] caps the sweep at the arc the runner has left to run, so the
## search never proposes cover past the finish line.
##
## [param hazards] is [method collect_hazards]'s output. Empty (the default)
## means no hazard rejection at all, which is right for a map with none.
##
## Returns true when something was found; [method get_position] then holds it.
func search(
	perception: RunnerPerception,
	profile: RunnerProfile,
	space: PhysicsDirectSpaceState3D,
	from_position: Vector3,
	centre: Vector3,
	travel_sign: float,
	track_radius: float,
	limit_arc: float,
	hazards: Array[Dictionary] = [],
	budget: int = 0,
) -> bool:
	if perception == null or profile == null or space == null:
		_complete = true
		return false
	var since: int = Time.get_ticks_usec()
	var eye: Vector3 = perception.get_threat_eye()
	var resume: bool = budget > 0 and not _complete \
		and from_position.distance_to(_key_from) <= RESUME_MOVE_METRES \
		and eye.distance_to(_key_eye) <= 1.0
	if not resume:
		_found = false
		_position = Vector3.ZERO
		_arc_gain = 0.0
		_probes = 0
		_step = 1
		_radius_index = 0
		_complete = false
		_key_from = from_position
		_key_eye = eye
	from_position = _key_from

	var threat_eye: Vector3 = perception.get_threat_eye()
	var from_angle: float = _angle_of(from_position, centre)
	var from_radius: float = Vector2(
		from_position.x - centre.x, from_position.z - centre.z
	).length()
	var arc: float = minf(profile.get_cover_search_arc_radians(), maxf(limit_arc, 0.0))
	if arc <= 0.0:
		_complete = true
		return false

	var steps: int = maxi(profile.cover_search_steps, 1)
	var min_arc: float = profile.cover_min_advance_metres / maxf(track_radius, 0.001)
	var depth_arc: float = profile.cover_depth_metres / maxf(track_radius, 0.001)

	var probed: int = 0
	while _step <= steps:
		var step: int = _step
		_step += 1
		var step_arc: float = arc * float(step) / float(steps)
		if step_arc < min_arc:
			continue
		if budget > 0 and probed >= budget:
			_step = step
			RingNavigation.charge("cover", since)
			return false
		probed += maxi(profile.cover_search_radial_steps, 1)
		var angle: float = from_angle + travel_sign * step_arc
		if _radius_index == 0:
			_best = Vector3.ZERO
			_best_deviation = INF
		var radii: PackedFloat32Array = _radii(profile, from_radius)

		for ri: int in range(_radius_index, radii.size()):
			if not _rays_left():
				# Out of rays this frame; pick up at this candidate next tick.
				_step = step
				_radius_index = ri
				RingNavigation.charge("cover", since)
				return false
			var radius: float = radii[ri]
			var point: Vector3 = _point_at(centre, angle, radius, from_position.y)
			_probes += 1
			# Cheapest rejection first. See probe 5 in the class docs.
			if point_in_hazard(hazards, point):
				continue
			if segment_crosses_hazard(hazards, from_position, point):
				continue
			if not _is_hidden(perception, profile, point, threat_eye):
				continue
			var deeper: Vector3 = _point_at(
				centre, angle + travel_sign * depth_arc, radius, from_position.y
			)
			if not _is_hidden(perception, profile, deeper, threat_eye):
				continue
			if not _is_standable(space, profile, point, from_position.y):
				continue
			# Reachable, not merely standable. See probe 4 in the class docs.
			if not path_is_walkable(space, profile, from_position, point):
				continue
			var deviation: float = absf(radius - track_radius)
			if deviation < _best_deviation:
				_best_deviation = deviation
				_best = point
		_radius_index = 0

		if _best_deviation < INF:
			_position = _best
			_arc_gain = step_arc
			_found = true
			_complete = true
			RingNavigation.charge("cover", since)
			return true
	_complete = true
	RingNavigation.charge("cover", since)
	return false


## False while a budgeted search still has steps to probe.
func is_complete() -> bool:
	return _complete


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


## True when there is floor within one step of [param from]'s height at every
## sample along the straight line from [param from] to [param to].
##
## Static, and it takes no arena and no route, because it is asked by
## [RingRunner] about its own open-ground fallback as well as by
## [method search] about a piece of cover. One test, one answer, one place a
## crossing is ruled reachable.
##
## The endpoints are not sampled: [param from] is where the body is standing, so
## it has a floor by definition, and [param to] has already been probed by
## whoever proposed it.
static func path_is_walkable(
	space: PhysicsDirectSpaceState3D,
	profile: RunnerProfile,
	from: Vector3,
	to: Vector3,
) -> bool:
	if space == null or profile == null:
		return true
	var distance: float = Vector2(to.x - from.x, to.z - from.z).length()
	if distance <= PATH_STEP_METRES:
		return true
	var samples: int = int(ceil(distance / PATH_STEP_METRES))
	for index: int in samples:
		var fraction: float = (float(index) + 0.5) / float(samples)
		if not _floor_within_a_step(space, profile, from.lerp(to, fraction), from.y):
			return false
	return true


## The furthest point along that line the runner can still walk to, pulled back
## one sample from wherever the floor gave out.
##
## What a runner does when the only way forward is over a hole: it stops at the
## edge of it, which is a place to stand and re-plan from, rather than at the
## bottom of it.
static func last_walkable_point(
	space: PhysicsDirectSpaceState3D,
	profile: RunnerProfile,
	from: Vector3,
	to: Vector3,
) -> Vector3:
	if space == null or profile == null:
		return to
	var distance: float = Vector2(to.x - from.x, to.z - from.z).length()
	if distance <= PATH_STEP_METRES:
		return to
	var samples: int = int(ceil(distance / PATH_STEP_METRES))
	var safe: Vector3 = from
	for index: int in samples:
		var fraction: float = (float(index) + 0.5) / float(samples)
		var point: Vector3 = from.lerp(to, fraction)
		if not _floor_within_a_step(space, profile, point, from.y):
			return safe
		safe = point
	return to


# --- Hazards --------------------------------------------------------------

## Every [TrapVolume] under [param root], as an inverse transform and
## inflated half-extents in its own local space. [KillVolume] and anything
## else is ignored, and nothing here is told where a hazard is in advance.
static func collect_hazards(root: Node) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	_collect_hazards(root, hazards)
	return hazards


static func _collect_hazards(node: Node, hazards: Array[Dictionary]) -> void:
	if node == null:
		return
	var trap: TrapVolume = node as TrapVolume
	if trap != null:
		var half: Vector3 = trap.size_metres * 0.5 + Vector3.ONE * HAZARD_MARGIN_METRES
		hazards.append({
			"inverse": trap.global_transform.affine_inverse(),
			"half": half,
			"centre": trap.global_position,
			"reach_squared": half.length_squared(),
		})
	for child: Node in node.get_children():
		_collect_hazards(child, hazards)


## True when [param point] lies inside any box in [param hazards].
static func point_in_hazard(hazards: Array[Dictionary], point: Vector3) -> bool:
	for hazard: Dictionary in hazards:
		if point.distance_squared_to(hazard["centre"]) > float(hazard["reach_squared"]):
			continue
		var local: Vector3 = (hazard["inverse"] as Transform3D) * point
		var half: Vector3 = hazard["half"]
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false


## True when the straight line from [param from] to [param to], sampled every
## [constant HAZARD_STEP_METRES], passes through any box in [param hazards].
static func segment_crosses_hazard(
	hazards: Array[Dictionary], from: Vector3, to: Vector3
) -> bool:
	if hazards.is_empty():
		return false
	var distance: float = from.distance_to(to)
	var samples: int = maxi(int(ceil(distance / HAZARD_STEP_METRES)), 1)
	for index: int in range(samples + 1):
		var fraction: float = float(index) / float(samples)
		if point_in_hazard(hazards, from.lerp(to, fraction)):
			return true
	return false


# --- Probes -------------------------------------------------------------------

static func _spend_ray() -> void:
	var frame: int = Engine.get_physics_frames()
	if frame != _ray_frame:
		_ray_frame = frame
		_rays_spent = 0
	_rays_spent += 1


static func _rays_left() -> bool:
	return Engine.get_physics_frames() != _ray_frame or _rays_spent < RAYS_PER_FRAME


## True when a downward ray at [param point] finds a floor within
## [member RunnerProfile.cover_max_step_height] of [param feet_y].
## [b]It starts JUST above the step, not twenty metres up, and that is the whole
## of it.[/b] The arena has three decks stacked directly over one another, so
## every square metre of the bottom two galleries has a ceiling eight and a half
## metres overhead. A probe dropped from twenty metres up hits that ceiling
## first, reads back a "floor" eight metres above the runner's feet, and rejects
## it -- which rejected every candidate and every crossing on the lower two
## levels, froze the whole cover game on the spot, and looked exactly like a bot
## that had decided to stand still. The ray now starts one step above the point
## it is asking about, so there is nothing overhead for it to find.
static func _floor_within_a_step(
	space: PhysicsDirectSpaceState3D, profile: RunnerProfile, point: Vector3, feet_y: float
) -> bool:
	var lift: float = maxf(profile.cover_max_step_height, 0.0) + FLOOR_PROBE_LIFT_METRES
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(point.x, feet_y + lift, point.z),
		Vector3(point.x, feet_y - FLOOR_PROBE_METRES, point.z),
	)
	query.collision_mask = FLOOR_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true

	_spend_ray()
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var floor_point: Vector3 = hit.get("position", Vector3.ZERO)
	return absf(floor_point.y - feet_y) <= profile.cover_max_step_height

## True when a shot from the tower could not reach a body standing at
## [param point].
func _is_hidden(
	perception: RunnerPerception, profile: RunnerProfile, point: Vector3, threat_eye: Vector3
) -> bool:
	var chest: Vector3 = point + Vector3.UP * profile.cover_test_height
	_spend_ray()
	return not perception.has_clear_line(chest, threat_eye)


## True when there is a floor under [param point] within one step of the height
## the runner is standing at now.
func _is_standable(
	space: PhysicsDirectSpaceState3D, profile: RunnerProfile, point: Vector3, feet_y: float
) -> bool:
	return _floor_within_a_step(space, profile, point, feet_y)


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
