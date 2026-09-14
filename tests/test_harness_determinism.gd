extends TestCase

## The bot harness replays a seed: the same seed gives the same match, tick for tick.
##
## Every generator is seeded from the match seed, planning is phased by seat,
## trap grace and the navigation sync run on the physics tick, so two runs of
## the same seeds must agree on every number a result file carries except the
## wall clock.

const SEED: int = 20260930
const MATCHES: int = 2
const RUNS: int = 2
## Enough of the opening race for the field to spread, fight the lane and, on
## some seeds, resolve. Kept short so the whole test stays well under 15 s.
const MAX_SIM_SECONDS: float = 25.0
## Keys that carry wall-clock time and may differ between runs.
const WALL_CLOCK_KEYS: Array[String] = ["recorded_at", "wall_seconds", "compression_achieved", "tick_ms"]

var _steps_before: int = 0


func before_each() -> void:
	# The runner's default lets one main-loop iteration retire eight ticks;
	# four short matches want more so the test stays quick. Restored below.
	_steps_before = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 64


func after_each() -> void:
	Engine.max_physics_steps_per_frame = _steps_before


func test_same_seed_replays_the_same_matches() -> void:
	var variants: Array[BotVariant] = BotVariants.single(BotVariants.DEFAULT_RULES_PATH, "determinism")
	if not assert_eq_int(variants.size(), 1, "the shipped rules load"):
		return
	var max_ticks: int = int(MAX_SIM_SECONDS * float(BotHarness.SIM_HZ))
	var runs: Array = []
	for _run: int in RUNS:
		var harness: BotHarness = BotHarness.new()
		add_child(harness)
		var results: Array = []
		for index: int in MATCHES:
			var result: Dictionary = await harness.run_match(
				variants[0], index, BotHarness.match_seed(SEED, index), max_ticks
			)
			results.append(_without_wall_clock(result))
		remove_child(harness)
		harness.free()
		runs.append(results)

	for index: int in MATCHES:
		var first: Dictionary = runs[0][index]
		assert_true(int(first.get("duration", {}).get("physics_ticks", 0)) > 0, "match %d ran" % index)
		for run: int in range(1, RUNS):
			var other: Dictionary = runs[run][index]
			assert_true(
				_same(first, other),
				"match %d differs between run 0 and run %d:\n%s" % [index, run, _first_difference(first, other, "")]
			)


func _without_wall_clock(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in (value as Dictionary):
			if String(key) in WALL_CLOCK_KEYS:
				continue
			out[key] = _without_wall_clock(value[key])
		return out
	if value is Array:
		var items: Array = []
		for item: Variant in (value as Array):
			items.append(_without_wall_clock(item))
		return items
	return value


func _same(a: Variant, b: Variant) -> bool:
	return _first_difference(a, b, "").is_empty()


## The path and values of the first leaf that differs, or "" when none does.
func _first_difference(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, a, b]
	if a is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return "%s: %d keys vs %d keys" % [path, da.size(), db.size()]
		for key: Variant in da:
			if not db.has(key):
				return "%s: key %s missing" % [path, key]
			var found: String = _first_difference(da[key], db[key], "%s/%s" % [path, key])
			if not found.is_empty():
				return found
		return ""
	if a is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s: %d items vs %d items" % [path, aa.size(), ab.size()]
		for index: int in aa.size():
			var found: String = _first_difference(aa[index], ab[index], "%s[%d]" % [path, index])
			if not found.is_empty():
				return found
		return ""
	if a is float:
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s vs %s" % [path, a, b]
	return "" if a == b else "%s: %s vs %s" % [path, a, b]
