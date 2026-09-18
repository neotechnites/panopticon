extends SceneTree

## How much COVER the bot bake found inside one angular section of the ring.
##
## [codeblock]
## godot --headless --path . --script res://tools/modelling/s3_cover_count.gd -- --section=145,200
## godot --headless --path . --script res://tools/modelling/s3_cover_count.gd -- --section=215,270
## [/codeblock]
##
## [code]--section=FROM,TO[/code]  game bearings in degrees, wrapping past 360
## (default [code]145,200[/code], which is S3 The Split; S4 Demon Run is
## [code]215,270[/code]).
##
## A section's geometry is only finished when a bot can HIDE in it, and the bake
## is the only witness to that: [RingBake] samples cover off the walkable mesh
## against the tower's eye, so a section whose rocks and slabs are decorative
## bakes zero cover points however solid it looks in the editor. This counts
## them, reports their radii, bearings and a 5 degree histogram, and exits 1 on
## zero, so "S3 has cover" is a measurement rather than an opinion. Nothing under
## [code]scripts/bot/[/code] is touched; this only reads what the bake exposes.

const RING_SCENE: String = "res://scenes/ring/bentham_ring.tscn"
const PREFIX: String = "S3COVER"
const BUCKET_DEGREES: float = 5.0

## Frames the arena gets to build its collision before the bake parses it.
const SETTLE_FRAMES: int = 30
## Frames the baked region gets to answer map queries after it is parented.
const READY_FRAMES: int = 60

const EXIT_OK: int = 0
const EXIT_FAIL: int = 1
const EXIT_BROKEN: int = 2

var _options: Dictionary = {}
var _frames: int = 0
var _ring: Node = null
var _bake: RingBake = null
var _waited: int = 0


func _initialize() -> void:
	_options = BotHarness.parse_arguments({"section": "145,200"})


func _process(_delta: float) -> bool:
	if bool(_options.get("_error", false)):
		_fail("bad command line")
		quit(EXIT_BROKEN)
		return true
	_frames += 1
	if _frames == 1:
		var packed: PackedScene = load(RING_SCENE) as PackedScene
		if packed == null:
			_fail("could not load %s" % RING_SCENE)
			quit(EXIT_BROKEN)
			return true
		_ring = packed.instantiate()
		root.add_child(_ring)
		return false
	if _frames <= SETTLE_FRAMES:
		return false
	if _bake == null:
		_bake = RingBake.ensure(_ring)
		if _bake == null:
			_fail("the ring has no RingBake")
			quit(EXIT_BROKEN)
			return true
		return false
	if not _bake.is_ready() and _waited < READY_FRAMES:
		_waited += 1
		return false
	quit(_report())
	return true


# --- The report ---------------------------------------------------------------

## Print the four kinds of line and return the exit code.
func _report() -> int:
	var span: Vector2 = _section()
	if is_nan(span.x):
		_fail("bad --section=%s; expected FROM,TO in degrees" % _options.get("section", ""))
		return EXIT_BROKEN

	var total: int = _bake.get_cover_count()
	print("%s total=%d" % [PREFIX, total])

	var width: float = _width(span)
	var bearings: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for index: int in total:
		var point: Vector3 = _bake.cover_point(index)
		var bearing: float = _degrees(point)
		var offset: float = fposmod(bearing - span.x, 360.0)
		if offset > width:
			continue
		bearings.append(bearing)
		radii.append(_radius(point))

	var count: int = bearings.size()
	if count == 0:
		print("%s section=%.1f..%.1f count=0 r=-..- bearings=-..-" % [PREFIX, span.x, span.y])
	else:
		print("%s section=%.1f..%.1f count=%d r=%.2f..%.2f bearings=%.1f..%.1f" % [
			PREFIX, span.x, span.y, count,
			_lowest(radii), _highest(radii), _lowest(bearings), _highest(bearings),
		])

	var edge: float = 0.0
	while edge < width:
		var high: float = minf(edge + BUCKET_DEGREES, width)
		var inside: int = 0
		for index: int in count:
			var offset: float = fposmod(bearings[index] - span.x, 360.0)
			if offset >= edge and (offset < high or is_equal_approx(high, width)):
				inside += 1
		print("%s bucket %.1f..%.1f count=%d" % [
			PREFIX, fposmod(span.x + edge, 360.0), fposmod(span.x + high, 360.0), inside,
		])
		edge = high

	if total == 0:
		_fail("the bake found no cover anywhere on the map")
		return EXIT_FAIL
	if count == 0:
		_fail("no cover between %.1f and %.1f degrees" % [span.x, span.y])
		return EXIT_FAIL
	print("%s OK" % PREFIX)
	return EXIT_OK


func _fail(reason: String) -> void:
	print("%s FAIL %s" % [PREFIX, reason])


# --- The section --------------------------------------------------------------

## [code]--section[/code] as two bearings wrapped into 0..360, or NAN.x when unparsable.
func _section() -> Vector2:
	var parts: PackedStringArray = String(_options.get("section", "")).split(",", false)
	if parts.size() != 2:
		return Vector2(NAN, NAN)
	for part: String in parts:
		if not part.strip_edges().is_valid_float():
			return Vector2(NAN, NAN)
	return Vector2(
		fposmod(float(parts[0].strip_edges()), 360.0),
		fposmod(float(parts[1].strip_edges()), 360.0),
	)


## Degrees walked forward from the section's start to its end; a whole lap when equal.
func _width(span: Vector2) -> float:
	var forward: float = fposmod(span.y - span.x, 360.0)
	return 360.0 if is_zero_approx(forward) else forward


static func _degrees(point: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(point.z, point.x)), 360.0)


static func _radius(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


static func _lowest(values: PackedFloat32Array) -> float:
	var best: float = values[0]
	for value: float in values:
		best = minf(best, value)
	return best


static func _highest(values: PackedFloat32Array) -> float:
	var best: float = values[0]
	for value: float in values:
		best = maxf(best, value)
	return best
