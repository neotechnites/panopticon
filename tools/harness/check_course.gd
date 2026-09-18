extends SceneTree

## PANOPTICON's headless course check: is the lap of an arena covered, and can it
## be walked end to end?
##
## [codeblock]
## godot --headless --path . --script res://tools/harness/check_course.gd -- \
##     --scene=res://scenes/ring/forest.tscn --bin=5
## [/codeblock]
##
## Two questions, both asked of the bake rather than of the geometry:
##
## 1. [b]Cover.[/b] Where round the lap did [RingBake] find cover, in bearing
##    bins of [code]--bin[/code] degrees? A bin with no cover in it is a stretch
##    of lap a prisoner crosses with nothing to stand behind, and the longest
##    such run is the number that says whether the map is playable at all.
## 2. [b]Walk.[/b] Does the mesh carry a path from PrisonerStart to PrisonerEnd?
##    Cover means nothing on a lap that is not connected.
##
## [b]Map-agnostic on purpose.[/b] Nothing here names a map, a radius or an
## angle. The scene is named on the command line, and every number the bins are
## judged against is read off the scene's own [RingLevel] -- found by class, not
## by path -- so the same tool checks map 1, map 2 and whatever is authored next.
## A tool that knew one map's radii would quietly pass every other map.
##
## [b]Diagnostics[/b]
##
## Three optional modes, each printing its own prefix and changing nothing about
## the COURSE lines above, because the COURSE lines are what a gate reads and a
## diagnostic that moved them would break every caller that already parses them.
##
## [codeblock]
## --dump-cover                  COVER <bearing> <radius> <y>, one per cover point
## --sight=<bearing>,<radius>    SIGHT ... whether the eye's rays reach a lane point
## --lane-gaps                   GAPS ... bearings with no walkable radial width
## [/codeblock]
##
## [code]--sight[/code] is repeatable, which is why it is read straight off
## [method OS.get_cmdline_user_args] rather than through
## [method BotHarness.parse_arguments]: that returns one value per key, and the
## question being asked here is about several points at once.
##
## [b]Why the work happens in _process[/b]
##
## The same three headless facts [code]tools/harness/run_bot_match.gd[/code] is
## built around. [method SceneTree.quit] from [method _initialize] exits before
## stdout is flushed; nodes added during [method _initialize] are not in the
## tree, so every global_position reads back as the origin; and the bake's region
## is parented with [method Node.add_child.call_deferred], so the navigation map
## does not answer a query until frames have passed. So [method _initialize]
## parses the command line and nothing else.

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1

## Physics ticks the scene is given to build its collision before it is baked.
## The bake parses static colliders; a scene baked on its first frame is baked
## against bodies the physics server has not registered yet.
const SETTLE_TICKS: int = 120
## Ticks the navigation map is given to answer, after the region is parented.
const SYNC_TICKS: int = 120

const DEFAULT_BIN_DEGREES: int = 5
const FULL_CIRCLE_DEGREES: float = 360.0

const DUMP_COVER_FLAG: String = "dump-cover"
const LANE_GAPS_FLAG: String = "lane-gaps"
const SIGHT_FLAG: String = "sight"
const SIGHT_PREFIX: String = "--sight="

## --lane-gaps probes this band, in metres from the axis, at this step. Wider
## than any one deck on purpose: the band is the question ("is there walkable
## width anywhere near the lane"), not the answer.
const GAP_RADIUS_MIN: float = 46.0
const GAP_RADIUS_MAX: float = 58.0
const GAP_RADIUS_STEP: float = 0.25
## A radial run narrower than this is not a lane a body can hold.
const GAP_MIN_RUN_METRES: float = 1.6
const GAP_BEARING_STEP_DEGREES: int = 1

var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_FAILED
var _options: Dictionary = {}


func _initialize() -> void:
	_options = BotHarness.parse_arguments({
		"scene": "",
		"bin": DEFAULT_BIN_DEGREES,
		DUMP_COVER_FLAG: false,
		LANE_GAPS_FLAG: false,
		# Present so a repeated --sight is not an unknown option; the values are
		# gathered by _sight_requests, which keeps all of them.
		SIGHT_FLAG: "",
	})


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		# Deliberately not awaited: _run is a coroutine that parks on physics
		# frames, and this main loop is what delivers them.
		_run()
		return false
	if _finished:
		quit(_exit_code)
		return true
	return false


func _run() -> void:
	_exit_code = await _check()
	_finished = true


## The whole check. Returns the exit code; prints the report.
func _check() -> int:
	if bool(_options.get("_error", false)):
		printerr("check_course: bad command line; nothing was checked.")
		return EXIT_FAILED

	var scene_path: String = String(_options.get("scene", ""))
	if scene_path.is_empty():
		printerr("check_course: --scene=res://... is required.")
		return EXIT_FAILED
	var bin_degrees: int = int(_options.get("bin", DEFAULT_BIN_DEGREES))
	if bin_degrees <= 0 or bin_degrees > int(FULL_CIRCLE_DEGREES):
		printerr("check_course: --bin must be between 1 and 360, not %d." % bin_degrees)
		return EXIT_FAILED

	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		printerr("check_course: %s is not a scene." % scene_path)
		return EXIT_FAILED
	var arena: Node3D = packed.instantiate() as Node3D
	if arena == null:
		printerr("check_course: %s does not instance a Node3D." % scene_path)
		return EXIT_FAILED
	root.add_child(arena)
	# In the tree but not yet ticked: global transforms are still the origin, and
	# the colliders the bake reads do not exist until physics has run.
	await _wait_ticks(SETTLE_TICKS)

	var level: RingLevel = _find_level(arena)
	if level == null:
		printerr("check_course: %s authors no RingLevel; there is no lap to check." % scene_path)
		return EXIT_FAILED

	var bake: RingBake = RingBake.ensure(arena)
	if bake == null:
		printerr("check_course: the bake could not be made.")
		return EXIT_FAILED
	# ensure() parents the region deferred, and the navigation map answers a
	# query only once it has iterated.
	var ready: bool = await _wait_for_bake(bake)
	if not ready:
		printerr("check_course: the bake never answered a map query.")
		return EXIT_FAILED

	var centre: Vector3 = arena.global_position
	var bins: PackedInt32Array = _bin_cover(bake, level, centre, bin_degrees)
	print("COURSE cover_points=%d" % bake.get_cover_count())
	for index: int in bins.size():
		print("COURSE bin %d %d" % [index * bin_degrees, bins[index]])

	var covered: int = 0
	for count: int in bins:
		if count > 0:
			covered += 1
	print(
		"COURSE covered_bins=%d/%d longest_covered_run_deg=%.1f longest_open_run_deg=%.1f"
		% [
			covered,
			bins.size(),
			_longest_run(bins, true) * float(bin_degrees),
			_longest_run(bins, false) * float(bin_degrees),
		]
	)

	var code: int = _report_walk(arena, bake)

	# Diagnostics last: the COURSE lines are the contract, and a caller reading
	# them must not have to skip past a dump to find them.
	if bool(_options.get(DUMP_COVER_FLAG, false)):
		_dump_cover(bake, centre)
	var sights: PackedStringArray = _sight_requests()
	if not sights.is_empty():
		_report_sight(arena, bake, level, centre, sights)
	if bool(_options.get(LANE_GAPS_FLAG, false)):
		_report_lane_gaps(bake, level, centre)
	return code


# --- Cover --------------------------------------------------------------------

## One count per bearing bin: baked cover points on [param level]'s annulus whose
## bearing about [param centre] falls in the bin.
##
## Bearing is [code]atan2(z, x)[/code] wrapped into [code][0, 360)[/code], which
## is the same convention [RingRoute] and the map generators author angles in, so
## a bin start printed here is an angle a human can look up on the map.
func _bin_cover(
	bake: RingBake, level: RingLevel, centre: Vector3, bin_degrees: int
) -> PackedInt32Array:
	var bin_count: int = int(ceil(FULL_CIRCLE_DEGREES / float(bin_degrees)))
	var bins: PackedInt32Array = PackedInt32Array()
	bins.resize(bin_count)
	for index: int in bake.get_cover_count():
		var point: Vector3 = bake.cover_point(index)
		var offset: Vector2 = Vector2(point.x - centre.x, point.z - centre.z)
		var radius: float = offset.length()
		if radius < level.inner_radius or radius > level.outer_radius:
			continue
		var bearing: float = fposmod(rad_to_deg(atan2(offset.y, offset.x)), FULL_CIRCLE_DEGREES)
		var bin: int = mini(int(bearing / float(bin_degrees)), bin_count - 1)
		bins[bin] += 1
	return bins


## The longest run of bins that are covered ([param want] true) or open (false),
## in bins, wrapping across 0/360.
##
## The wrap is the point: a map whose only gap straddles the start line has one
## gap, not two, and a scan that stopped at index 0 would report half of it.
func _longest_run(bins: PackedInt32Array, want: bool) -> int:
	var total: int = bins.size()
	if total == 0:
		return 0
	var matching: int = 0
	for count: int in bins:
		if (count > 0) == want:
			matching += 1
	if matching == total:
		return total
	if matching == 0:
		return 0
	# Every run is now bounded, so one pass over the array twice round finds the
	# longest of them however it straddles the origin.
	var best: int = 0
	var current: int = 0
	for step: int in total * 2:
		if (bins[step % total] > 0) == want:
			current += 1
			best = maxi(best, current)
		else:
			current = 0
	return mini(best, total)


# --- The walk -----------------------------------------------------------------

## Print the walk line and return the exit code. The path is the bake's own, from
## the snapped PrisonerStart to the snapped PrisonerEnd.
func _report_walk(arena: Node3D, bake: RingBake) -> int:
	var start: Marker3D = arena.find_child("PrisonerStart", true, false) as Marker3D
	var end: Marker3D = arena.find_child("PrisonerEnd", true, false) as Marker3D
	if start == null or end == null:
		print("COURSE walk=fail waypoints=0 path_length_m=0.00")
		printerr("check_course: the scene has no PrisonerStart/PrisonerEnd Marker3D pair.")
		return EXIT_FAILED

	var from: Vector3 = bake.snap(start.global_position)
	var to: Vector3 = bake.snap(end.global_position)
	var path: PackedVector3Array = bake.find_path(from, to)
	# find_path already empties a path that stops short, but the reach is the
	# claim being made here, so it is checked where it is printed.
	var reached: bool = not path.is_empty()
	if reached:
		var last: Vector3 = path[path.size() - 1]
		reached = Vector2(last.x - to.x, last.z - to.z).length() <= RingBake.REACH_TOLERANCE_METRES
	print(
		"COURSE walk=%s waypoints=%d path_length_m=%.2f"
		% [
			"ok" if reached else "fail",
			path.size(),
			RingBake.path_length(path),
		]
	)
	return EXIT_OK if reached else EXIT_FAILED


# --- Diagnostics --------------------------------------------------------------

## Every baked cover point as bearing, radius and height, sorted by bearing.
## Unfiltered by the level's annulus: a cover point off the deck is itself worth
## seeing, and the COURSE bins above already report the filtered view.
func _dump_cover(bake: RingBake, centre: Vector3) -> void:
	var rows: Array[Vector3] = []
	for index: int in bake.get_cover_count():
		var point: Vector3 = bake.cover_point(index)
		var offset: Vector2 = Vector2(point.x - centre.x, point.z - centre.z)
		rows.append(Vector3(
			fposmod(rad_to_deg(atan2(offset.y, offset.x)), FULL_CIRCLE_DEGREES),
			offset.length(),
			point.y,
		))
	rows.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	for row: Vector3 in rows:
		print("COVER %.1f %.2f %.2f" % [row.x, row.y, row.z])


## Every [code]--sight[/code] on the command line, in order, unparsed.
func _sight_requests() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(SIGHT_PREFIX):
			out.append(argument.substr(SIGHT_PREFIX.length()))
	return out


## For each requested lane point: can the eye see a chest and a head standing
## there, and if not, what stopped the ray?
##
## The rays are cast here rather than asked of the bake because the bake only
## ever answers yes or no ([code]_sight_clear[/code]); the collider that stopped
## the ray is the whole question when props have just been placed. Same eye, same
## mask, same "areas do not block" rule, so a disagreement with the bake would be
## a real disagreement and not a difference of query.
func _report_sight(
	arena: Node3D, bake: RingBake, level: RingLevel, centre: Vector3, requests: PackedStringArray
) -> void:
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var eye: Vector3 = bake.get_eye()
	for request: String in requests:
		var parts: PackedStringArray = request.split(",")
		if parts.size() != 2:
			printerr("check_course: --sight wants <bearing_deg>,<radius_m>, not %s" % request)
			continue
		var bearing: float = float(parts[0])
		var radius: float = float(parts[1])
		var angle: float = deg_to_rad(bearing)
		var probe: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		probe.y = level.deck_height
		var mesh_y: float = bake.height_at(probe)
		# Off the mesh the ray is still worth casting -- a prop that blocks the
		# eye there is why the point may be off the mesh -- so the deck stands in
		# for the height while navmesh_y still reports nan.
		var base_y: float = level.deck_height if is_nan(mesh_y) else mesh_y
		var chest: Dictionary = _cast(space, eye, Vector3(
			probe.x, base_y + RingBake.COVER_CHEST_METRES, probe.z
		))
		var head: Dictionary = _cast(space, eye, Vector3(
			probe.x, base_y + RingBake.COVER_HEAD_METRES, probe.z
		))
		print(
			"SIGHT %.1f %.2f navmesh_y=%s chest_clear=%s head_clear=%s chest_hit=%s head_hit=%s"
			% [
				bearing,
				radius,
				"nan" if is_nan(mesh_y) else "%.2f" % mesh_y,
				chest.is_empty(),
				head.is_empty(),
				_hit_text(chest),
				_hit_text(head),
			]
		)


## One ray, eye to target, static colliders only, areas ignored.
func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, RingBake.STATIC_COLLIDER_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)


## What a ray hit, as node path and position, or "none".
func _hit_text(hit: Dictionary) -> String:
	if hit.is_empty():
		return "none"
	var collider: Node = hit.get("collider", null) as Node
	var where: Vector3 = hit.get("position", Vector3.ZERO)
	var path: String = String(collider.get_path()) if collider != null else "?"
	return "%s@(%.2f,%.2f,%.2f)" % [path, where.x, where.y, where.z]


## Bearings where the deck has no radial run wide enough to walk, and how many.
##
## Walkability is [method RingBake.height_at], which is the bake's own index of
## the mesh it built, so a gap printed here is a gap the bots' pathfinder has.
func _report_lane_gaps(bake: RingBake, level: RingLevel, centre: Vector3) -> void:
	var blocked: int = 0
	var bearing: int = 0
	while bearing < int(FULL_CIRCLE_DEGREES):
		var angle: float = deg_to_rad(float(bearing))
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var intervals: PackedStringArray = PackedStringArray()
		var widest: float = 0.0
		var run_start: float = NAN
		var previous: float = NAN
		var radius: float = GAP_RADIUS_MIN
		while radius <= GAP_RADIUS_MAX + 0.001:
			var probe: Vector3 = centre + direction * radius
			probe.y = level.deck_height
			var walkable: bool = not is_nan(bake.height_at(probe))
			if walkable:
				if is_nan(run_start):
					run_start = radius
				previous = radius
			elif not is_nan(run_start):
				widest = maxf(widest, previous - run_start)
				intervals.append("%.2f-%.2f" % [run_start, previous])
				run_start = NAN
			radius += GAP_RADIUS_STEP
		if not is_nan(run_start):
			widest = maxf(widest, previous - run_start)
			intervals.append("%.2f-%.2f" % [run_start, previous])
		if widest < GAP_MIN_RUN_METRES:
			blocked += 1
			print("GAPS %d %.2f %s" % [
				bearing, widest, "none" if intervals.is_empty() else ",".join(intervals)
			])
		bearing += GAP_BEARING_STEP_DEGREES
	print("GAPS blocked_bearings=%d" % blocked)


# --- Waiting ------------------------------------------------------------------

## The scene's own lap geometry. Found by class so no path into a map is baked in
## here; the first level is the one whose annulus the bins are judged against.
func _find_level(arena: Node3D) -> RingLevel:
	for node: Node in arena.find_children("*", "RingLevel", true, false):
		var level: RingLevel = node as RingLevel
		if level != null:
			return level
	return null


func _wait_ticks(ticks: int) -> void:
	for _tick: int in ticks:
		await physics_frame


## Tick until the bake answers map queries. True when it does.
func _wait_for_bake(bake: RingBake) -> bool:
	for _tick: int in SYNC_TICKS:
		await physics_frame
		if bake.is_ready():
			return true
	return false
