extends SceneTree

## Does a camera path fly into anything you can SEE?
##
## [codeblock]
## godot --headless --path . --script res://tools/capture/verify_path.gd -- --shot=teaser_lap
## godot --headless --path . --script res://tools/capture/verify_path.gd -- --scan=1
## [/codeblock]
##
## Checked against the visual mesh, not the collider. Stalactites, the watching
## eye, the torches and a good deal of the cave dressing carry no collision at
## all, so a physics query calls a path clear that the camera plainly flies
## through. Every visible [MeshInstance3D] in the ring is read for its triangles
## instead, and the distance from a path point to the nearest of them is the
## clearance -- which is what [constant WANT_METRES] is measured against.
##
## [b]--scan[/b] answers the other question: not "is this path clear" but "where
## COULD a path go". For every degree of ring it reports the roomiest place to be
## inside the band a drone at head height is allowed, which is what the route in
## [code]shot_paths.gd[/code] was fitted to.

const SHOTS := preload("res://tools/capture/shot_paths.gd")
const RING_SCENE: String = "res://maps/bentham_ring/bentham_ring.tscn"

const STEP_METRES: float = 0.25
const WANT_METRES: float = 1.0
const SEARCH_METRES: float = 4.0
const TIME_STEP: float = 0.002
const SETTLE_FRAMES: int = 2

## Only geometry in the deck's own shell can be flown into; the pit below and the
## rock outside the rim are dropped before the grid is built.
const BAND_R := Vector2(40.0, 62.0)
const BAND_Y := Vector2(18.0, 36.0)
const CELL: float = 2.0

## The band --scan searches: radii across the deck, heights over its floor.
const SCAN_R := Vector2(47.0, 57.0)
const SCAN_R_STEP: float = 0.5
const SCAN_H: Array = [1.6, 1.9, 2.2, 2.6]
const DECK_Y: float = 23.0

var _frames: int = 0
var _options: Dictionary = {}
var _tris: PackedVector3Array = PackedVector3Array()
var _grid: Dictionary = {}


func _initialize() -> void:
	_options = BotHarness.parse_arguments({"shot": "", "scan": 0, "fit": 0, "floor": 0.0, "polish": 0})
	var packed: PackedScene = load(RING_SCENE) as PackedScene
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames <= SETTLE_FRAMES:
		return false
	_gather(root)
	_index()
	print("visual mesh: %d triangles in the deck shell" % (_tris.size() / 3))
	if int(_options.get("polish", 0)) != 0:
		_polish()
	elif int(_options.get("fit", 0)) != 0:
		_fit()
	elif int(_options.get("scan", 0)) != 0:
		_scan()
	else:
		_verify()
	quit(0)
	return true


# --- The two reports ----------------------------------------------------------

func _verify() -> void:
	var shot: Dictionary = SHOTS.get_shot(String(_options.get("shot", "")))
	if shot.is_empty():
		printerr("Unknown --shot=%s." % _options.get("shot", ""))
		quit(2)
		return
	var points: Array[Vector3] = _walk(shot["keys"])
	var worst: float = SEARCH_METRES
	var worst_at: Vector3 = Vector3.ZERO
	var tight: int = 0
	var lowest: float = 1000.0
	var highest: float = -1000.0
	for point: Vector3 in points:
		lowest = minf(lowest, point.y - DECK_Y)
		highest = maxf(highest, point.y - DECK_Y)
		var clearance: float = _clearance(point)
		if clearance < WANT_METRES:
			tight += 1
			if tight <= 20:
				print("  tight %5.1f deg  r %5.2f  h %5.2f  clear %.2f" % [
					_degrees(point), _radius(point), point.y - DECK_Y, clearance
				])
		if clearance < worst:
			worst = clearance
			worst_at = point
	print("path: %d samples every %.2f m, height %.2f to %.2f m over the deck" % [
		points.size(), STEP_METRES, lowest, highest
	])
	print("min visual clearance %.2f m at %5.1f deg r %.2f h %.2f; %d under %.2f" % [
		worst, _degrees(worst_at), _radius(worst_at), worst_at.y - DECK_Y, tight, WANT_METRES
	])
	print("VERDICT %s" % ("clear" if tight == 0 else "CLIPS"))


## The roomiest spot at head height, degree by degree round the ring.
func _scan() -> void:
	print("scan: deg, best r, best h, clearance")
	for step: int in 360:
		var angle: float = float(step)
		var best: float = -1.0
		var best_r: float = 52.0
		var best_h: float = 1.9
		var radius: float = SCAN_R.x
		while radius <= SCAN_R.y:
			for height: float in SCAN_H:
				var clearance: float = _clearance(_ring_point(angle, radius, DECK_Y + height))
				if clearance > best:
					best = clearance
					best_r = radius
					best_h = height
			radius += SCAN_R_STEP
		print("SCAN %3d %5.1f %4.1f %5.2f" % [int(angle), best_r, best_h, best])


## The flyable route that stays closest to the line the shot WANTS.
##
## A maximin fit gives the roomiest corridor, which is the inner lip at ankle
## height for most of a lap: safe and dull. So clearance is a constraint here,
## not the objective -- anything under [constant FLOOR_METRES] is simply not a
## place the drone may be -- and what is minimised is how far the route strays
## from [method _wants], the line each section is supposed to be flown on.
const FLOOR_METRES: float = 1.15
const HEIGHT_COST: float = 2.0
## Paid per step of sideways or vertical movement, so the fit comes out smooth
## enough for a spline through sparse keys to actually follow it.
const TURN_COST: float = 4.5

func _fit() -> void:
	var radii: Array = []
	var radius: float = SCAN_R.x
	while radius <= SCAN_R.y:
		radii.append(radius)
		radius += SCAN_R_STEP
	var heights: Array = [1.6, 1.9, 2.2, 2.6, 3.2, 4.0]
	var first: int = 5
	var last: int = 335
	var huge: float = 1.0e9
	var floor_metres: float = float(_options.get("floor", 0.0))
	if floor_metres <= 0.0:
		floor_metres = FLOOR_METRES

	var best: Array = []
	var came: Array = []
	for angle: int in range(first, last + 1):
		var want: Vector2 = _wants(angle)
		var cap: float = 4.0 if (angle >= 215 and angle <= 270) else 2.6
		var here: Array = []
		var back: Array = []
		for r_index: int in radii.size():
			for h_index: int in heights.size():
				var score: float = huge
				var from: int = -1
				var stray: float = (
					absf(radii[r_index] - want.x) + HEIGHT_COST * absf(heights[h_index] - want.y)
				)
				var blocked: bool = heights[h_index] > cap
				if not blocked:
					blocked = _clearance(
						_ring_point(float(angle), radii[r_index], DECK_Y + heights[h_index])
					) < floor_metres
				if blocked:
					here.append(score)
					back.append(from)
					continue
				if angle == first:
					score = stray
				else:
					for dr: int in [-3, -2, -1, 0, 1, 2, 3]:
						for dh: int in [-1, 0, 1]:
							var pr: int = r_index + dr
							var ph: int = h_index + dh
							if pr < 0 or pr >= radii.size() or ph < 0 or ph >= heights.size():
								continue
							var previous: float = best[best.size() - 1][pr * heights.size() + ph]
							if previous >= huge:
								continue
							var turn: float = TURN_COST * (absf(float(dr)) + absf(float(dh)))
							if previous + stray + turn < score:
								score = previous + stray + turn
								from = pr * heights.size() + ph
				here.append(score)
				back.append(from)
		var reachable: bool = false
		for score: float in here:
			if score < huge:
				reachable = true
				break
		if not reachable:
			print("FIT dead end at %d deg (floor %.2f)" % [angle, floor_metres])
			return
		best.append(here)
		came.append(back)

	var final: Array = best[best.size() - 1]
	var pick: int = -1
	for state: int in final.size():
		if final[state] < huge and (pick < 0 or final[state] < final[pick]):
			pick = state
	if pick < 0:
		print("FIT no route clears %.2f m" % floor_metres)
		return
	print("FIT stray %.1f over %d degrees, floor %.2f m" % [final[pick], last - first, floor_metres])
	var route: Array = []
	var step: int = best.size() - 1
	while step >= 0:
		route.append(pick)
		pick = came[step][pick]
		if pick < 0:
			break
		step -= 1
	route.reverse()
	for index: int in route.size():
		var state: int = route[index]
		print("FIT %3d %5.1f %4.1f" % [
			first + index, radii[state / heights.size()], heights[state % heights.size()]
		])


## Where the shot wants to be at [param angle]: radius, and height over the deck.
##
## The sections, in the language of docs/MAP1_SECTIONS.md: the lane out of the
## start, the S1 columns at head height, the S2 chain, the inside of the S3
## divider, the S4 pad arcs, and the S5 lake platforms weaving in and out.
func _wants(angle: int) -> Vector2:
	if angle < 15:
		return Vector2(52.0, 1.7)
	if angle <= 60:
		return Vector2(52.0, 1.9)
	if angle < 75:
		return Vector2(52.0, 1.9)
	if angle <= 130:
		return Vector2(54.7, 1.9)
	if angle < 145:
		return Vector2(52.0, 1.9)
	if angle <= 200:
		return Vector2(50.0, 1.9)
	if angle < 215:
		return Vector2(52.0, 1.9)
	if angle <= 270:
		# Riding the arcs: low over each demon pad, up between them.
		var pads: Array = [212.0, 227.0, 242.0, 258.0]
		var nearest: float = 99.0
		for pad: float in pads:
			nearest = minf(nearest, absf(float(angle) - pad))
		var lift: float = clampf(nearest / 7.5, 0.0, 1.0)
		return Vector2(52.0, lerpf(1.8, 3.6, lift))
	if angle < 285:
		return Vector2(52.0, 1.9)
	# The lake: seven platforms from 298 deg, 5.77 deg apart, alternating sides.
	var index: int = int(round((float(angle) - 298.0) / 5.7676))
	var platform: float = 54.8 if (index % 2 == 0) else 50.2
	return Vector2(platform, 1.9)


## Nudge the path's own keys until the SPLINE is clear, not just the corridor.
##
## A corridor fit is checked degree by degree; what actually gets filmed is a
## Catmull-Rom through sparse keys, which cuts the corners of a weave and can sit
## half a metre inside a route that measured clear. This optimises the thing that
## is measured: each key in turn is offered a few small offsets, and keeps
## whichever leaves the widest tightest point over the spans it touches.
func _polish() -> void:
	var shot: Dictionary = SHOTS.get_shot(String(_options.get("shot", "")))
	if shot.is_empty():
		printerr("Unknown --shot.")
		return
	var keys: Array = shot["keys"]
	var offsets_r: Array = [-0.9, -0.6, -0.3, 0.0, 0.3, 0.6, 0.9]
	var offsets_h: Array = [-0.3, 0.0, 0.3]
	for pass_number: int in 3:
		var sore: Dictionary = _sore_keys(keys)
		if sore.is_empty():
			print("POLISH pass %d: nothing tight left" % (pass_number + 1))
			break
		for index: int in sore:
			var home: Vector3 = keys[index]["pos"]
			var angle: float = _degrees(home)
			var cap: float = 4.0 if (angle >= 215.0 and angle <= 270.0) else 2.6
			var best: float = _span_clearance(keys, index)
			var best_pos: Vector3 = home
			for dr: float in offsets_r:
				for dh: float in offsets_h:
					keys[index]["pos"] = _ring_point(
						angle,
						clampf(_radius(home) + dr, SCAN_R.x, SCAN_R.y),
						DECK_Y + clampf(home.y - DECK_Y + dh, 1.6, cap)
					)
					var score: float = _span_clearance(keys, index)
					if score > best:
						best = score
						best_pos = keys[index]["pos"]
			keys[index]["pos"] = best_pos
		print("POLISH pass %d: moved %d keys, tightest %.2f m" % [
			pass_number + 1, sore.size(), _whole_clearance(keys)
		])
	for index: int in keys.size():
		var point: Vector3 = keys[index]["pos"]
		print("POLISH %5.1f %5.2f %5.2f" % [_degrees(point), _radius(point), point.y - DECK_Y])


## The keys shaping any part of the spline that is still under WANT_METRES.
##
## Only these are worth moving, and there are rarely more than a handful, which
## is what keeps a pass seconds rather than an hour.
func _sore_keys(keys: Array) -> Dictionary:
	var sore: Dictionary = {}
	var last: int = keys.size() - 1
	var previous: Vector3 = SHOTS.sample(keys, float(keys[0]["t"]))["pos"]
	var carried: float = 0.0
	var time: float = float(keys[0]["t"])
	var finish: float = float(keys[last]["t"])
	while time < finish:
		time = minf(time + TIME_STEP, finish)
		var here: Vector3 = SHOTS.sample(keys, time)["pos"]
		carried += previous.distance_to(here)
		if carried >= STEP_METRES:
			carried = 0.0
			if _clearance(here) < WANT_METRES:
				var index: int = 0
				while index < last and float(keys[index + 1]["t"]) < time:
					index += 1
				for near: int in range(maxi(index - 1, 1), mini(index + 3, last)):
					sore[near] = true
		previous = here
	return sore


## The tightest point of the spline over the spans key [param index] shapes.
func _span_clearance(keys: Array, index: int) -> float:
	var first: int = maxi(index - 2, 0)
	var final: int = mini(index + 2, keys.size() - 1)
	return _min_over(keys, float(keys[first]["t"]), float(keys[final]["t"]))


func _whole_clearance(keys: Array) -> float:
	return _min_over(keys, float(keys[0]["t"]), float(keys[keys.size() - 1]["t"]))


func _min_over(keys: Array, from: float, to: float) -> float:
	var worst: float = SEARCH_METRES
	var previous: Vector3 = SHOTS.sample(keys, from)["pos"]
	var carried: float = 0.0
	var time: float = from
	while time < to:
		time = minf(time + TIME_STEP, to)
		var here: Vector3 = SHOTS.sample(keys, time)["pos"]
		carried += previous.distance_to(here)
		if carried >= STEP_METRES:
			worst = minf(worst, _clearance(here))
			carried = 0.0
		previous = here
	return worst


# --- The visual mesh ----------------------------------------------------------

## Every triangle of every visible mesh that stands in the deck's shell.
func _gather(node: Node) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.is_visible_in_tree() and mesh_node.mesh != null:
		var faces: PackedVector3Array = mesh_node.mesh.get_faces()
		var basis: Transform3D = mesh_node.global_transform
		var index: int = 0
		while index + 2 < faces.size():
			var a: Vector3 = basis * faces[index]
			var b: Vector3 = basis * faces[index + 1]
			var c: Vector3 = basis * faces[index + 2]
			if _in_band(a) or _in_band(b) or _in_band(c):
				_tris.append(a)
				_tris.append(b)
				_tris.append(c)
			index += 3
	for child: Node in node.get_children():
		_gather(child)


func _in_band(point: Vector3) -> bool:
	if point.y < BAND_Y.x or point.y > BAND_Y.y:
		return false
	var radius: float = _radius(point)
	return radius >= BAND_R.x and radius <= BAND_R.y


## Bucket every triangle into the cells its bounds touch, so a query reads few.
func _index() -> void:
	var triangle: int = 0
	while triangle * 3 + 2 < _tris.size():
		var a: Vector3 = _tris[triangle * 3]
		var b: Vector3 = _tris[triangle * 3 + 1]
		var c: Vector3 = _tris[triangle * 3 + 2]
		var low: Vector3i = _cell(Vector3(minf(minf(a.x, b.x), c.x), minf(minf(a.y, b.y), c.y), minf(minf(a.z, b.z), c.z)))
		var high: Vector3i = _cell(Vector3(maxf(maxf(a.x, b.x), c.x), maxf(maxf(a.y, b.y), c.y), maxf(maxf(a.z, b.z), c.z)))
		for x: int in range(low.x, high.x + 1):
			for y: int in range(low.y, high.y + 1):
				for z: int in range(low.z, high.z + 1):
					var key: Vector3i = Vector3i(x, y, z)
					if not _grid.has(key):
						_grid[key] = PackedInt32Array()
					var bucket: PackedInt32Array = _grid[key]
					bucket.append(triangle)
					_grid[key] = bucket
		triangle += 1


func _cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / CELL), floori(point.y / CELL), floori(point.z / CELL))


## Distance from [param point] to the nearest visible triangle, capped.
func _clearance(point: Vector3) -> float:
	var reach: int = ceili(SEARCH_METRES / CELL)
	var home: Vector3i = _cell(point)
	var best: float = SEARCH_METRES
	var seen: Dictionary = {}
	for x: int in range(home.x - reach, home.x + reach + 1):
		for y: int in range(home.y - reach, home.y + reach + 1):
			for z: int in range(home.z - reach, home.z + reach + 1):
				var bucket: PackedInt32Array = _grid.get(Vector3i(x, y, z), PackedInt32Array())
				for triangle: int in bucket:
					if seen.has(triangle):
						continue
					seen[triangle] = true
					var distance: float = _to_triangle(
						point,
						_tris[triangle * 3],
						_tris[triangle * 3 + 1],
						_tris[triangle * 3 + 2]
					)
					if distance < best:
						best = distance
	return best


## Distance from [param p] to the closest point of triangle abc.
func _to_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ap: Vector3 = p - a
	var d1: float = ab.dot(ap)
	var d2: float = ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return ap.length()
	var bp: Vector3 = p - b
	var d3: float = ab.dot(bp)
	var d4: float = ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return bp.length()
	var vc: float = d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return (p - (a + ab * (d1 / (d1 - d3)))).length()
	var cp: Vector3 = p - c
	var d5: float = ab.dot(cp)
	var d6: float = ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return cp.length()
	var vb: float = d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return (p - (a + ac * (d2 / (d2 - d6)))).length()
	var va: float = d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return (p - (b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))).length()
	var denom: float = 1.0 / (va + vb + vc)
	return (p - (a + ab * (vb * denom) + ac * (vc * denom))).length()


# --- Reading a path -----------------------------------------------------------

func _walk(keys: Array) -> Array[Vector3]:
	var first: float = float(keys[0]["t"])
	var last: float = float(keys[keys.size() - 1]["t"])
	var points: Array[Vector3] = []
	var previous: Vector3 = SHOTS.sample(keys, first)["pos"]
	points.append(previous)
	var carried: float = 0.0
	var time: float = first
	while time < last:
		time = minf(time + TIME_STEP, last)
		var here: Vector3 = SHOTS.sample(keys, time)["pos"]
		carried += previous.distance_to(here)
		if carried >= STEP_METRES:
			points.append(here)
			carried = 0.0
		previous = here
	return points


static func _radius(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


static func _degrees(point: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(point.z, point.x)), 360.0)


static func _ring_point(degrees: float, radius: float, height: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(cos(angle) * radius, height, sin(angle) * radius)
