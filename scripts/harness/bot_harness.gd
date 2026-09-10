class_name BotHarness
extends Node

## Drives a set of [BotVariant]s through N matches each and writes the files.
##
## Shared by [code]tools/harness/run_bot_match.gd[/code] and
## [code]tools/harness/run_sweep.gd[/code] -- a single match is a sweep of one
## arm, and giving the two entry points the same engine is what stops them
## drifting into measuring slightly different games.
##
## [b]The clock, and why a sweep is affordable at all[/b]
##
## Godot's main loop is real-time locked: physics ticks execute at
## [member Engine.physics_ticks_per_second] per WALL-CLOCK second, so a 200
## second match costs 200 seconds of anybody's evening at the default 60 Hz, and
## a sweep of two hundred of them is a week. Raising the tick rate and
## [member Engine.time_scale] by the same factor leaves the delta handed to
## every [code]_physics_process[/code] at exactly
## [code]C / (60 * C) = 1/60[/code] s -- bit for bit the step the shipped game
## runs at -- while executing those ticks as fast as the host can. The technique
## is [code]tools/run_tests.gd[/code]'s; this is the same trick pointed at
## matches instead of tests.
##
## The ceiling is how many physics steps the host can actually retire per
## second, so past a point a higher compression simply stops helping and the
## simulation quietly falls behind its own target rate. That costs nothing but
## wall clock -- the delta is unchanged, so the MATCH is unchanged -- and every
## result file records the compression it actually achieved so the number can
## be seen rather than assumed.

## The rate every match is simulated at, whatever the wall clock is doing.
const SIM_HZ: int = 60

## Multiplier applied to both the tick rate and the time scale. Around 120 is
## the useful range on a 2024 laptop; higher values are accepted and simply
## stop paying off.
const DEFAULT_COMPRESSION: int = 120

## Simulated seconds a single match may run before it is written out as
## UNRESOLVED. Ten minutes is roughly sixteen laps of the ring, which is far
## more than any rule set that terminates should need.
const DEFAULT_MAX_SIM_SECONDS: float = 600.0

## The dated milestone this harness exists for, used as the default seed so an
## undecorated run is still reproducible.
const DEFAULT_SEED: int = 20260930

## Stride between the seeds of successive matches within one run.
##
## Without it, N matches of one variant at one seed are N copies of the same
## match: the aim RNG is the only stochastic input the simulation has, so the
## same seed produces the same shots, the same conversions and the same winner
## every time, and a sweep would report a sample of one with a sample size of
## N -- which is the most confident wrong answer this harness could give. The
## stride keeps a whole RUN reproducible while making the matches inside it
## independent draws.
const SEED_STRIDE: int = 7919

const DEFAULT_OUT_DIR: String = "res://tools/harness/runs"

const SWEEP_SCHEMA: String = "panopticon.bot_sweep.v1"

signal progress(line: String)

var _run_id: String = ""
var _out_dir: String = ""


# --- The clock ----------------------------------------------------------------

## Pin the simulation to [constant SIM_HZ] and run it [param compression] times
## faster than the wall clock. Call from [method MainLoop._initialize], before
## anything is in the tree.
static func apply_time_compression(compression: int) -> void:
	var factor: int = maxi(compression, 1)
	Engine.physics_ticks_per_second = SIM_HZ * factor
	Engine.time_scale = float(factor)
	Engine.max_fps = 0
	# Without this the compression above is mostly decorative. Godot retires at
	# most max_physics_steps_per_frame steps per MAIN LOOP ITERATION -- eight by
	# default -- so a headless loop turning over 140 times a second tops out at
	# 1120 ticks a second whatever the tick rate is set to, and asking for 60x
	# delivers 19x. Raising the cap lets one iteration retire a whole batch. It
	# changes no delta and therefore no match; it only stops the loop rate from
	# being the ceiling. Set here rather than in project.godot because the
	# shipped game genuinely wants the small default: there, a frame that runs
	# sixty physics steps to catch up is a spiral of death, and dropping
	# simulated time is the correct response. A sweep has no frames to drop.
	Engine.max_physics_steps_per_frame = maxi(factor, 8)


# --- Command line -------------------------------------------------------------

## Parse [code]--key=value[/code] user arguments over [param defaults].
##
## Only the keys already present in [param defaults] are accepted, and each
## incoming value is coerced to the type its default has, so a typo is an error
## at the start of a run rather than a silently ignored flag discovered in the
## report of a sweep that has already cost twenty minutes.
static func parse_arguments(defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			push_error("Harness: unexpected argument %s; expected --key=value" % argument)
			out["_error"] = true
			continue
		var body: String = argument.substr(2)
		var split: int = body.find("=")
		var key: String = body if split < 0 else body.substr(0, split)
		var raw: String = "true" if split < 0 else body.substr(split + 1)
		if not defaults.has(key):
			push_error("Harness: unknown option --%s" % key)
			out["_error"] = true
			continue
		out[key] = _coerce_argument(defaults[key], raw)
	return out


static func _coerce_argument(default_value: Variant, raw: String) -> Variant:
	match typeof(default_value):
		TYPE_INT:
			return int(raw)
		TYPE_FLOAT:
			return float(raw)
		TYPE_BOOL:
			return raw == "true" or raw == "1" or raw == "yes"
		_:
			return raw


# --- The run ------------------------------------------------------------------

## Run every arm and write the files. A coroutine: await it.
##
## Returns the aggregate report, which is also written to
## [code]<out_dir>/<run_id>/sweep.json[/code] alongside one file per match.
func run(
	variants: Array[BotVariant],
	matches_per_variant: int,
	seed_value: int,
	max_sim_seconds: float,
	out_dir: String,
	compression: int,
) -> Dictionary:
	_run_id = "%s-%s" % [
		Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", ""),
		"sweep" if variants.size() > 1 else (variants[0].name if not variants.is_empty() else "empty"),
	]
	_out_dir = out_dir.path_join(_run_id)
	_make_directory(_out_dir)

	var max_ticks: int = maxi(int(max_sim_seconds * float(SIM_HZ)), 1)
	var started_ms: int = Time.get_ticks_msec()
	var arms: Array = []

	for variant: BotVariant in variants:
		var results: Array = []
		for index: int in maxi(matches_per_variant, 1):
			var result: Dictionary = await _run_one(
				variant, index, match_seed(seed_value, index), max_ticks
			)
			var file_path: String = _out_dir.path_join(
				"match_%s_%02d.json" % [variant.name, index]
			)
			result["result_path"] = ProjectSettings.globalize_path(file_path)
			_write_json(file_path, result)
			results.append(result)
			progress.emit(_describe(result))
		arms.append(_summarise(variant, results))

	var unresolved_total: int = 0
	var matches_total: int = 0
	for entry: Variant in arms:
		var arm: Dictionary = entry
		unresolved_total += int(arm.get("unresolved", 0))
		matches_total += int(arm.get("matches", 0))

	var report: Dictionary = {
		"schema": SWEEP_SCHEMA,
		"run_id": _run_id,
		"recorded_at": Time.get_datetime_string_from_system(true, true),
		"engine": String(Engine.get_version_info().get("string", "unknown")),
		"seed": seed_value,
		"seed_stride": SEED_STRIDE,
		"matches_per_variant": maxi(matches_per_variant, 1),
		"matches_total": matches_total,
		"unresolved_total": unresolved_total,
		"max_simulated_seconds": max_sim_seconds,
		"time_compression_requested": compression,
		"wall_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"output_directory": ProjectSettings.globalize_path(_out_dir),
		"variants": arms,
	}
	var sweep_path: String = _out_dir.path_join("sweep.json")
	report["sweep_path"] = ProjectSettings.globalize_path(sweep_path)
	_write_json(sweep_path, report)
	return report


## The seed match [param match_index] of a run seeded [param run_seed] plays on.
## A run seed of 0 is passed through untouched: it means "seed from entropy",
## and striding entropy would only make it look reproducible.
static func match_seed(run_seed: int, match_index: int) -> int:
	if run_seed == 0:
		return 0
	return run_seed + match_index * SEED_STRIDE


func _run_one(
	variant: BotVariant, match_index: int, seed_value: int, max_ticks: int
) -> Dictionary:
	var runner: BotMatchRunner = BotMatchRunner.new()
	runner.name = "Match_%s_%d" % [variant.name, match_index]
	runner.configure(variant.rules, variant.name, match_index, seed_value, max_ticks)
	add_child(runner)
	runner.begin()

	var result: Dictionary = await runner.finished

	# The signal is emitted from inside a physics callback, so the tree is
	# mid-tick right now. Leave the tick before dismantling the world that was
	# running in it.
	await get_tree().physics_frame
	runner.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return result


# --- Aggregation --------------------------------------------------------------

## Fold one arm's matches into the numbers a design argument is settled with.
##
## Medians rather than means for the durations, because an UNRESOLVED match sits
## at the tick ceiling by construction and one of them would drag a mean
## anywhere. Both are reported; the median is the one the database row takes.
func _summarise(variant: BotVariant, results: Array) -> Dictionary:
	var resolved_seconds: Array[float] = []
	var resolved_rounds: Array[float] = []
	var resolved_seat_changes: Array[float] = []
	var tower_wins: int = 0
	var runner_wins: int = 0
	var unresolved: int = 0
	var shots_fired: int = 0
	var shots_hit: int = 0
	var winners: Dictionary = {}
	var wall_seconds: float = 0.0
	var simulated_seconds: float = 0.0

	for entry: Variant in results:
		var result: Dictionary = entry
		var duration: Dictionary = result.get("duration", {})
		wall_seconds += float(duration.get("wall_seconds", 0.0))
		simulated_seconds += float(duration.get("simulated_seconds", 0.0))

		var shots: Dictionary = result.get("shots", {})
		shots_fired += int(shots.get("fired", 0))
		shots_hit += int(shots.get("hit_participant", 0))

		if String(result.get("status", "")) != "RESOLVED":
			unresolved += 1
			continue

		resolved_seconds.append(float(duration.get("simulated_seconds", 0.0)))
		var rounds: Dictionary = result.get("rounds", {})
		resolved_rounds.append(float(rounds.get("started", 0)))
		var seat: Dictionary = result.get("seat", {})
		resolved_seat_changes.append(float(seat.get("changes", 0)))

		var outcome: Dictionary = result.get("outcome", {})
		if String(outcome.get("winner_role", "")) == "TOWER":
			tower_wins += 1
		else:
			runner_wins += 1
		var winner_key: String = String(outcome.get("winner_name", "?"))
		winners[winner_key] = int(winners.get(winner_key, 0)) + 1

	return {
		"variant": variant.name,
		"notes": variant.notes,
		"rules": BotMatchRunner.rules_to_dictionary(variant.rules),
		"matches": results.size(),
		"resolved": results.size() - unresolved,
		"unresolved": unresolved,
		"tower_wins": tower_wins,
		"runner_wins": runner_wins,
		"seconds_median": median(resolved_seconds),
		"seconds_mean": mean(resolved_seconds),
		"seconds_min": resolved_seconds.min() if not resolved_seconds.is_empty() else 0.0,
		"seconds_max": resolved_seconds.max() if not resolved_seconds.is_empty() else 0.0,
		"rounds_median": median(resolved_rounds),
		"seat_changes_median": median(resolved_seat_changes),
		"shots_fired": shots_fired,
		"shots_hit": shots_hit,
		"hit_rate": float(shots_hit) / float(shots_fired) if shots_fired > 0 else 0.0,
		"winner_counts": winners,
		"simulated_seconds_total": simulated_seconds,
		"wall_seconds_total": wall_seconds,
	}


## The median of [param values], or 0.0 when there are none. An empty sample has
## no median and returning one would be an invented measurement.
static func median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle: int = int(floor(float(sorted.size()) * 0.5))
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5


static func mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


# --- Output -------------------------------------------------------------------

## One line describing a finished match, for the console.
static func _describe(result: Dictionary) -> String:
	var duration: Dictionary = result.get("duration", {})
	var outcome: Dictionary = result.get("outcome", {})
	var rounds: Dictionary = result.get("rounds", {})
	var shots: Dictionary = result.get("shots", {})
	var seat: Dictionary = result.get("seat", {})
	return "  %-12s #%d  %-10s  %6.1f sim s  %6.2f wall s  %2d rounds  %2d seats  %3d shots  %5.1f%% hit  winner %s" % [
		String(result.get("variant", "?")),
		int(result.get("match_index", 0)),
		String(result.get("status", "?")),
		float(duration.get("simulated_seconds", 0.0)),
		float(duration.get("wall_seconds", 0.0)),
		int(rounds.get("started", 0)),
		int(seat.get("changes", 0)),
		int(shots.get("fired", 0)),
		float(shots.get("hit_rate", 0.0)) * 100.0,
		String(outcome.get("winner_name", "none")),
	]


static func _make_directory(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(path)
	if error != OK:
		push_error("Harness could not create %s (error %d)" % [path, error])


static func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Harness could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "  ", false))
	file.close()
