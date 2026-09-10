extends SceneTree

## PANOPTICON's rule sweep: N matches of each of several [MatchRules] variants,
## aggregated into one file that answers "which of these is better".
##
## [codeblock]
## godot --headless --path . --script res://tools/harness/run_sweep.gd -- \
##     --spec=res://tools/harness/sweeps/reload_floor.json --matches=5
## [/codeblock]
##
## The spec file is documented on [BotVariants]. Every option:
##
## [codeblock]
## --spec=PATH        the sweep spec JSON                  (required)
## --matches=N        matches per variant                  (default 5)
## --seed=N           aim RNG seed; 0 means entropy        (default 20260930)
## --max-seconds=F    simulated seconds before UNRESOLVED  (default 600)
## --compression=N    how much faster than real time       (default 60)
## --out=PATH         directory for the run                (default res://tools/harness/runs)
## [/codeblock]
##
## Exits 0 when every match RESOLVED, 1 when any match hit the tick ceiling, and
## 2 when the sweep could not be set up. A sweep with unresolved matches in it is
## not a failed sweep -- the file is still written and the unresolved count is
## reported next to every average -- but it is not a clean one either, and the
## exit code says so rather than leaving it to be noticed.

const EXIT_OK: int = 0
const EXIT_UNRESOLVED: int = 1
const EXIT_BROKEN: int = 2

var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK
var _options: Dictionary = {}


func _initialize() -> void:
	_options = BotHarness.parse_arguments({
		"spec": "",
		"matches": 5,
		"seed": BotHarness.DEFAULT_SEED,
		"max-seconds": BotHarness.DEFAULT_MAX_SIM_SECONDS,
		"compression": BotHarness.DEFAULT_COMPRESSION,
		"out": BotHarness.DEFAULT_OUT_DIR,
	})
	BotHarness.apply_time_compression(int(_options.get("compression", BotHarness.DEFAULT_COMPRESSION)))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
		return false
	if _finished:
		quit(_exit_code)
		return true
	return false


func _run() -> void:
	if bool(_options.get("_error", false)):
		printerr("Bad command line; nothing was run.")
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	var spec_path: String = String(_options.get("spec", ""))
	if spec_path.is_empty():
		printerr("run_sweep needs --spec=res://path/to/sweep.json")
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	var variants: Array[BotVariant] = BotVariants.from_spec_file(spec_path)
	if variants.is_empty():
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	var report: Dictionary = await HarnessConsole.run_and_report(
		self, variants, _options, "PANOPTICON rule sweep: %s" % spec_path
	)
	_exit_code = EXIT_OK if int(report.get("unresolved_total", 1)) == 0 else EXIT_UNRESOLVED
	_finished = true
