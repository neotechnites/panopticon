extends SceneTree

## Headless sightline audit for [code]scenes/ring/test_ring.tscn[/code].
##
## The arena's two load-bearing claims are geometric, so they are checked with
## real physics raycasts rather than trusted:
##
## 1. No single standing position in the tower room sees the whole ring.
## 2. A runner 1.5 m behind a cover piece, eye at 1.7 m, is hard-occluded from
##    [i]every[/i] standing position in the tower room -- not merely from the
##    middle of it.
##
## Run: [code]godot --headless --path . --script res://scripts/ring/sightline_probe.gd[/code]
## Exits non-zero if either claim fails.

const SCENE_PATH: String = "res://scenes/ring/test_ring.tscn"

const ROOM_FLOOR_Y: float = 15.0
const EYE_Y: float = ROOM_FLOOR_Y + 1.7      ## Tower occupant, standing.
const TARGET_Y: float = 1.7                  ## Runner's eye on the deck.
const ROOM_HALF_IN: float = 10.0
const STATION_STEP: float = 0.5              ## Same 0.5 m grid as the scene.

const R_INNER: float = 35.0
const R_OUTER: float = 60.0
const COVER_DEPTH: float = 1.5
const HIDE_BEHIND: float = 1.5               ## How far behind the back face we claim safety.
const CONTROL_AHEAD: float = 2.0             ## Open ground in front of a piece: must be seen.

## Radii and angular step used to sample the ring for the coverage claim.
var _sample_radii: Array[float] = [37.0, 41.0, 47.5, 54.0, 58.0]
const SAMPLE_STEP_DEG: float = 2.0

## Cover pieces, mirrored from the scene. Kept as plain data so the probe fails
## loudly if a piece is renamed or moved rather than silently testing nothing.
var _cover_angles: Array[float] = [
	42.0, 68.0, 96.0, 124.0, 150.0, 178.0, 204.0, 232.0, 258.0, 284.0, 306.0, 330.0
]
var _cover_radii: Array[float] = [
	47.5, 41.0, 54.0, 47.5, 54.0, 41.0, 47.5, 41.0, 54.0, 47.5, 41.0, 54.0
]

var _frames: int = 0
var _scene: Node3D = null
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("could not load %s" % SCENE_PATH)
		quit(1)
		return
	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	# CSG meshes (and therefore their collision) are built over the first few
	# frames; raycasting before that silently sees an empty world.
	_frames += 1
	if _frames < 10:
		return false
	_run()
	quit(0 if _failures.is_empty() else 1)
	return true


func _space() -> PhysicsDirectSpaceState3D:
	return root.world_3d.direct_space_state


func _clear(from: Vector3, to: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	return _space().intersect_ray(query).is_empty()


## True when a standing 1.7 m eye at [param xz] is in open floor space inside
## the room: the downward probe must land on the room floor rather than pass
## through a solid Core or Fin.
func _is_station(xz: Vector2) -> bool:
	var from: Vector3 = Vector3(xz.x, EYE_Y, xz.y)
	var to: Vector3 = Vector3(xz.x, ROOM_FLOOR_Y - 0.5, xz.y)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = _space().intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	return normal.y > 0.9 and absf(point.y - ROOM_FLOOR_Y) < 0.05


func _stations() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var limit: float = ROOM_HALF_IN - 0.4   # keep a player radius off the walls
	var n: int = int(limit * 2.0 / STATION_STEP)
	for ix: int in range(n + 1):
		for iz: int in range(n + 1):
			var xz: Vector2 = Vector2(-limit + ix * STATION_STEP, -limit + iz * STATION_STEP)
			if _is_station(xz):
				out.append(Vector3(xz.x, EYE_Y, xz.y))
	return out


## A deck sample only counts if a runner could actually stand there: reject
## points inside a cover box or the lap divider.
func _is_open_deck(p: Vector3) -> bool:
	return _clear(Vector3(p.x, 5.0, p.z), Vector3(p.x, TARGET_Y + 0.05, p.z))


func _run() -> void:
	var stations: Array[Vector3] = _stations()
	print("stations sampled inside tower room: %d (0.5 m grid, eye y=%.1f)" % [
		stations.size(), EYE_Y])
	if stations.size() < 200:
		_failures.append("too few valid stations found -- room geometry or CSG collision is wrong")
		return

	_check_deck()
	_check_gallery(stations)
	_check_coverage(stations)
	_check_cover(stations)
	_check_markers(stations)

	print("")
	if _failures.is_empty():
		print("SIGHTLINE PROBE: PASS")
	else:
		print("SIGHTLINE PROBE: FAIL")
		for line: String in _failures:
			print("  - %s" % line)


## The four Fins must narrow the gallery without severing it: the occupant has
## to be able to walk the full loop between all four window stations.
func _check_gallery(stations: Array[Vector3]) -> void:
	var clearance: float = 0.4          # player capsule radius
	var open_set: Dictionary = {}
	for s: Vector3 in stations:
		var free: bool = true
		for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			if not _clear(s, s + d * clearance):
				free = false
				break
		if free:
			open_set[Vector2i(roundi(s.x / STATION_STEP), roundi(s.z / STATION_STEP))] = true
	var keys: Array = open_set.keys()
	if keys.is_empty():
		_failures.append("no walkable cells in the tower room")
		return
	var seen: Dictionary = {}
	var stack: Array[Vector2i] = [keys[0]]
	seen[keys[0]] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if open_set.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	print("tower gallery: %d/%d walkable cells reachable from one another" % [
		seen.size(), open_set.size()])
	for k: Vector2i in open_set.keys():
		if not seen.has(k):
			print("    unreachable cell at (%.1f, %.1f)" % [k.x * STATION_STEP, k.y * STATION_STEP])
	if seen.size() != open_set.size():
		_failures.append("the Fins have severed the gallery -- the occupant cannot reach every window")


## The deck must be continuous solid ground from the kerb to the outer wall --
## a CSG boolean that misfires leaves a hole you would only find by falling in.
func _check_deck() -> void:
	var holes: int = 0
	var probes: int = 0
	var r: float = R_INNER + 1.0
	while r <= R_OUTER - 0.5:
		var deg: float = 0.0
		while deg < 360.0:
			var a: float = deg_to_rad(deg)
			var from: Vector3 = Vector3(cos(a) * r, 10.0, sin(a) * r)
			var to: Vector3 = Vector3(from.x, -2.0, from.z)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
			var hit: Dictionary = _space().intersect_ray(query)
			probes += 1
			var solid: bool = false
			if not hit.is_empty():
				var n: Vector3 = hit.get("normal", Vector3.ZERO)
				var pt: Vector3 = hit.get("position", Vector3.ZERO)
				solid = n.y > 0.9 and pt.y > -0.01 and pt.y < 4.01
			if not solid:
				holes += 1
				if holes < 6:
					print("    deck hole at r=%.1f a=%.0f deg" % [r, deg])
			deg += 5.0
		r += 1.0
	print("deck continuity: %d/%d probes landed on solid ground" % [probes - holes, probes])
	if holes > 0:
		_failures.append("%d deck probes found no ground -- the annulus has holes" % holes)


func _check_coverage(stations: Array[Vector3]) -> void:
	var targets: Array[Vector3] = []
	var steps: int = int(360.0 / SAMPLE_STEP_DEG)
	for r: float in _sample_radii:
		for i: int in range(steps):
			var a: float = deg_to_rad(i * SAMPLE_STEP_DEG)
			var p: Vector3 = Vector3(cos(a) * r, TARGET_Y, sin(a) * r)
			if _is_open_deck(p):
				targets.append(p)
	var best: int = 0
	var best_at: Vector3 = Vector3.ZERO
	var union_seen: PackedByteArray = PackedByteArray()
	union_seen.resize(targets.size())
	for s: Vector3 in stations:
		var seen: int = 0
		for i: int in range(targets.size()):
			if _clear(s, targets[i]):
				seen += 1
				union_seen[i] = 1
		if seen > best:
			best = seen
			best_at = s
	var union_total: int = 0
	var blind: Array[Vector3] = []
	for i: int in range(union_seen.size()):
		union_total += union_seen[i]
		if union_seen[i] == 0:
			blind.append(targets[i])
	var pct: float = 100.0 * float(best) / float(targets.size())
	var upct: float = 100.0 * float(union_total) / float(targets.size())
	print("ring samples (open deck only): %d" % targets.size())
	print("best single standing position: %d/%d = %.1f%% of the ring, at (%.1f, %.1f)" % [
		best, targets.size(), pct, best_at.x, best_at.z])
	print("union over every standing position: %d/%d = %.1f%% (blind spots are walkable-away)" % [
		union_total, targets.size(), upct])
	# Every permanently blind sample should be a cover shadow, not a hole in the
	# tower's design. Report each one against the nearest cover piece so it can
	# be argued with.
	for p: Vector3 in blind:
		var a: float = rad_to_deg(atan2(p.z, p.x))
		if a < 0.0:
			a += 360.0
		var near_deg: float = 999.0
		var near_i: int = -1
		for i: int in range(_cover_angles.size()):
			var d: float = absf(wrapf(a - _cover_angles[i], -180.0, 180.0))
			if d < near_deg:
				near_deg = d
				near_i = i
		print("    blind: r=%.1f a=%5.1f deg -> shadow of Cover%02d (%.1f deg away)" % [
			Vector2(p.x, p.z).length(), a, near_i + 1, near_deg])
	if best >= targets.size():
		_failures.append("a single standing position sees the entire ring")


func _check_cover(stations: Array[Vector3]) -> void:
	var hidden_all: int = 0
	print("")
	print("cover occlusion (hide point %.1f m behind back face, y=%.1f):" % [
		HIDE_BEHIND, TARGET_Y])
	for i: int in range(_cover_angles.size()):
		var a: float = deg_to_rad(_cover_angles[i])
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var r_hide: float = _cover_radii[i] + COVER_DEPTH * 0.5 + HIDE_BEHIND
		var r_ctrl: float = _cover_radii[i] - COVER_DEPTH * 0.5 - CONTROL_AHEAD
		var hide: Vector3 = dir * r_hide + Vector3(0.0, TARGET_Y, 0.0)
		var ctrl: Vector3 = dir * r_ctrl + Vector3(0.0, TARGET_Y, 0.0)
		# Guard against the test fooling itself: if the hide point were inside
		# the cover box (a mis-rotated piece presenting its long face radially)
		# it would read as perfectly hidden while hiding nothing.
		if not _is_open_deck(hide):
			_failures.append("Cover%02d hide point is inside geometry -- the piece is mis-sized or mis-rotated" % (i + 1))
		var exposed: int = 0
		var ctrl_seen: int = 0
		for s: Vector3 in stations:
			if _clear(s, hide):
				exposed += 1
			if _clear(s, ctrl):
				ctrl_seen += 1
		var ok: bool = exposed == 0
		if ok:
			hidden_all += 1
		print("  Cover%02d %3d deg r=%4.1f : hide seen from %d/%d stations %s | control seen from %d" % [
			i + 1, int(_cover_angles[i]), _cover_radii[i], exposed, stations.size(),
			"[HIDDEN]" if ok else "[EXPOSED]", ctrl_seen])
		if ctrl_seen == 0:
			_failures.append("Cover%02d control point in front of the piece is visible from nowhere -- probe is not actually reaching the deck" % (i + 1))
	_check_cover_orientation()
	print("pieces hidden from every station: %d/%d" % [hidden_all, _cover_angles.size()])
	if hidden_all < 3:
		_failures.append("fewer than 3 cover pieces give a hard line-of-sight break")


## Each piece must present its 6 m face tangentially and its 1.5 m depth
## radially. A transposed rotation swaps the two and the occlusion test then
## passes for the wrong reason, so measure the footprint instead of trusting it.
func _check_cover_orientation() -> void:
	for i: int in range(_cover_angles.size()):
		var a: float = deg_to_rad(_cover_angles[i])
		var radial: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var tangent: Vector3 = Vector3(-sin(a), 0.0, cos(a))
		var centre: Vector3 = radial * _cover_radii[i] + Vector3(0.0, 1.7, 0.0)
		var depth: float = _span(centre, radial)
		var width: float = _span(centre, tangent)
		if absf(depth - COVER_DEPTH) > 0.6 or absf(width - 6.0) > 0.6:
			_failures.append("Cover%02d footprint measures %.2f radial x %.2f tangential, expected 1.50 x 6.00 -- piece is rotated wrong" % [
				i + 1, depth, width])


## Total thickness of solid geometry through [param centre] along [param axis],
## measured by shooting inwards from 20 m out on both sides.
func _span(centre: Vector3, axis: Vector3) -> float:
	# Short reach on purpose: 4 m clears the widest half-extent (3 m) but stops
	# well inside the nearest neighbouring geometry, so the measurement is of
	# this box and nothing else.
	var reach: float = 4.0
	var hits: Array[float] = []
	for dir_sign: float in [1.0, -1.0]:
		var from: Vector3 = centre + axis * dir_sign * reach
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, centre)
		var hit: Dictionary = _space().intersect_ray(query)
		if hit.is_empty():
			return -1.0
		var point: Vector3 = hit.get("position", Vector3.ZERO)
		hits.append(centre.distance_to(point))
	return hits[0] + hits[1]


func _check_markers(stations: Array[Vector3]) -> void:
	var s_marker: Marker3D = _scene.get_node("StartEnd/PrisonerStart") as Marker3D
	var e_marker: Marker3D = _scene.get_node("StartEnd/PrisonerEnd") as Marker3D
	var t_marker: Marker3D = _scene.get_node("Tower/TowerSpawn") as Marker3D
	if s_marker == null or e_marker == null or t_marker == null:
		_failures.append("a required Marker3D is missing")
		return
	var sp: Vector3 = s_marker.global_position
	var ep: Vector3 = e_marker.global_position
	print("")
	print("PrisonerStart %s  PrisonerEnd %s  separation %.2f m" % [
		str(sp), str(ep), sp.distance_to(ep)])
	print("TowerSpawn %s (room floor y=%.1f)" % [str(t_marker.global_position), ROOM_FLOOR_Y])
	if not is_equal_approx(snappedf(t_marker.global_position.y, 0.01), ROOM_FLOOR_Y):
		_failures.append("TowerSpawn is not on the room floor")
	# Start and end must be on opposite sides of the lap divider and close.
	if sp.distance_to(ep) > 12.0:
		_failures.append("start and end are not adjacent")
	if _clear(sp + Vector3(0.0, TARGET_Y, 0.0), ep + Vector3(0.0, TARGET_Y, 0.0)):
		_failures.append("LapDivider does not separate start from end")
	else:
		print("LapDivider blocks start<->end at eye height: OK")
	# -Z of each marker must point counter-clockwise: that is the run heading.
	for pair: Array in [[s_marker, sp], [e_marker, ep]]:
		var m: Marker3D = pair[0]
		var pos: Vector3 = pair[1]
		var want: Vector3 = Vector3(-pos.z, 0.0, pos.x).normalized()
		var got: Vector3 = -m.global_transform.basis.z
		if got.dot(want) < 0.99:
			_failures.append("%s faces %s, expected the counter-clockwise tangent %s" % [
				m.name, str(got), str(want)])
		else:
			print("%s faces the counter-clockwise tangent: OK" % m.name)
	var s_seen: int = 0
	var e_seen: int = 0
	for s: Vector3 in stations:
		if _clear(s, sp + Vector3(0.0, TARGET_Y, 0.0)):
			s_seen += 1
		if _clear(s, ep + Vector3(0.0, TARGET_Y, 0.0)):
			e_seen += 1
	print("start pad visible from %d stations, end pad from %d (both must be > 0)" % [
		s_seen, e_seen])
	if s_seen == 0 or e_seen == 0:
		_failures.append("a marker pad is unobservable from the tower")
