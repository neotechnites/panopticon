extends SceneTree

## PANOPTICON's headless bot-match runner.
##
## [codeblock]
## godot --headless --path . --script res://tools/harness/run_bot_match.gd -- \
##     --matches=3 --seed=20260930
## [/codeblock]
##
## Runs N bot-versus-bot matches with no window, no input and no rendering, and
## writes one JSON result per match plus an aggregate. Every option:
##
## [codeblock]
## --matches=N        matches to run                       (default 1)
## --rules=PATH       a MatchRules .tres                   (default the shipped one)
## --variant=NAME     label written into the files         (default "default")
## --seed=N           aim RNG seed; 0 means entropy        (default 20260930)
## --max-seconds=F    simulated seconds before UNRESOLVED  (default 600)
## --compression=N    how much faster than real time       (default 60)
## --out=PATH         directory for the run                (default res://tools/harness/runs)
## [/codeblock]
##
## Exits 0 when every match RESOLVED, 1 when any match hit the tick ceiling, and
## 2 when the run could not be set up at all. [b]The exit code is the point[/b]:
## an unattended sweep whose matches all timed out must not look like a
## successful sweep, and a harness that reports a success it did not observe is
## worse than no harness, because every design decision downstream would rest on
## it.
##
## [b]Why the work happens in _process[/b]
##
## Three headless facts, the same three [code]tools/run_tests.gd[/code] is built
## around. [method SceneTree.quit] from [method _initialize] exits before stdout
## is flushed. Nodes added during [method _initialize] are not in the tree, so
## every global_position reads back as the origin. And the main loop is
## real-time locked, which is what [method BotHarness.apply_time_compression]
## answers. So [method _initialize] configures the clock and nothing else.

const EXIT_OK: int = 0
const EXIT_UNRESOLVED: int = 1
const EXIT_BROKEN: int = 2

var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK
var _options: Dictionary = {}


func _initialize() -> void:
	_options = BotHarness.parse_arguments({
		"matches": 1,
		"rules": BotVariants.DEFAULT_RULES_PATH,
		"variant": "default",
		"seed": BotHarness.DEFAULT_SEED,
		"max-seconds": BotHarness.DEFAULT_MAX_SIM_SECONDS,
		"compression": BotHarness.DEFAULT_COMPRESSION,
		"out": BotHarness.DEFAULT_OUT_DIR,
	})
	BotHarness.apply_time_compression(int(_options.get("compression", BotHarness.DEFAULT_COMPRESSION)))


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
	if bool(_options.get("_error", false)):
		printerr("Bad command line; nothing was run.")
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	var variants: Array[BotVariant] = BotVariants.single(
		String(_options.get("rules", BotVariants.DEFAULT_RULES_PATH)),
		String(_options.get("variant", "default")),
	)
	if variants.is_empty():
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	var report: Dictionary = await HarnessConsole.run_and_report(
		self, variants, _options, "PANOPTICON bot match"
	)
	_exit_code = EXIT_OK if int(report.get("unresolved_total", 1)) == 0 else EXIT_UNRESOLVED
	_finished = true
