extends SceneTree

## PANOPTICON's test runner.
##
## [codeblock]
## godot --headless --path . --script res://tools/run_tests.gd
## [/codeblock]
##
## Exits 0 when every check passed, 1 when any check failed, and 2 when the
## suite could not be run at all (a test file that will not load, a test that
## hung, or a GDScript runtime error anywhere in the run). [b]The exit code is
## the entire point[/b] -- a runner that prints "FAILED" and exits 0 is a green
## CI badge over a broken game -- so the quit code is set from one place,
## [member _exit_code], and nothing else calls [method SceneTree.quit].
##
## [b]Why this script runs itself twice[/b]
##
## A GDScript runtime error -- a null dereference, a property that no longer
## exists on a class somebody refactored -- does not raise anything a script can
## catch. Godot prints it to stderr, abandons the function it happened in, and
## carries on with the next one. From inside the process the test looks like it
## simply stopped asserting: the assertions it did make are still counted, the
## ones after the error never ran, and the test is reported as a pass. That is
## the exact failure this whole suite exists to prevent, and it cannot be seen
## from in-process because a program cannot read its own stderr.
##
## So the invocation above starts a [b]supervisor[/b]. It re-executes this same
## script in a child Godot with [code]-- --child[/code], captures the child's
## stdout and stderr together, prints them verbatim, and fails the run if the
## child reported an engine error at any point. Nothing is hidden and nothing is
## re-formatted; the only thing the parent adds is the stderr scan. Pass
## [code]-- --in-process[/code] to skip the supervisor when debugging the runner
## itself, accepting that a runtime error will then pass unnoticed.
##
## [b]No addon, on purpose[/b]
##
## This is about two hundred lines with no dependency to pin, no addon to update
## against a Godot release, and nothing between a failing assertion and the
## reason it failed. A third-party framework would buy fixtures and a doubles
## library the project does not need, in exchange for an upgrade obligation on
## every engine bump.
##
## [b]Three headless facts this file is built around[/b]
##
## 1. [method SceneTree.quit] called from [method _initialize] exits before
##    stdout is flushed, so a run can print a full report and CI sees nothing.
##    All work therefore happens from [method _process], which returns [code]true[/code]
##    only on the frame it is genuinely finished.
## 2. Nodes added during [method _initialize] are not in the tree yet, so
##    [member Node3D.global_position] reads back as the origin and every physics
##    fixture silently sits on top of every other one. [method _initialize] here
##    does nothing but configure the clock.
## 3. The main loop is real-time locked: physics ticks execute at
##    [member Engine.physics_ticks_per_second] per [i]wall-clock[/i] second, so a
##    35 second simulated lap costs 35 seconds of CI at the default 60 Hz. Raising
##    the tick rate and [member Engine.time_scale] by the same factor leaves the
##    physics delta at exactly 1/60 s -- the step the shipped game runs at -- while
##    executing those ticks as fast as the machine can. See [constant TIME_COMPRESSION].

## Where tests live, and the filename convention that makes a file a test file.
## Anything under [constant TESTS_ROOT] that does not match is support code and
## is skipped, which is what keeps [code]tests/support/[/code] out of discovery.
const TESTS_ROOT: String = "res://tests"
const FILE_PREFIX: String = "test_"
const FILE_SUFFIX: String = ".gd"

## Methods matching this prefix are tests. One fresh case instance per method.
const METHOD_PREFIX: String = "test_"

## How much faster than real time the simulation runs.
##
## [member Engine.physics_ticks_per_second] is multiplied by this and
## [member Engine.time_scale] is set to it, so the delta handed to every
## [code]_physics_process[/code] stays [code]TIME_COMPRESSION / (60 * TIME_COMPRESSION)[/code]
## = 1/60 s. The simulation is bit-for-bit the 60 Hz one; only the wall clock
## moves. The practical ceiling is how many main-loop iterations the host can do
## per second (around 1200 on a 2024 laptop), so values past that stop helping.
const TIME_COMPRESSION: int = 50

## The project's real physics rate, and the delta every test is written against.
const SIM_HZ: int = 60

## Wall-clock budget for a single test. A test that overruns it is almost always
## awaiting a signal that will never fire; the suite aborts rather than letting
## CI sit on it until the job times out.
const TEST_TIMEOUT_MS: int = 90000

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_BROKEN: int = 2

## Passed to the child so it knows to run the suite rather than supervise again.
const CHILD_FLAG: String = "--child"

## Skips the supervisor entirely. For debugging the runner, not for CI.
const IN_PROCESS_FLAG: String = "--in-process"

## Substrings that mean the engine reported something the run must not survive.
##
## Godot writes all four to stderr and keeps going, which is precisely why the
## supervisor exists. "ERROR:" also catches [method @GlobalScope.push_error],
## so a production script complaining that it is misconfigured fails the suite
## instead of being scrolled past.
const ERROR_MARKERS: Array[String] = [
	"SCRIPT ERROR",
	"USER SCRIPT ERROR",
	"ERROR:",
	"USER ERROR",
]

## True in the child process, which is the one that actually runs tests.
var _is_child: bool = false

var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK

## Name of the test in flight, for the timeout message.
var _current: String = ""
var _current_started_ms: int = 0

var _tests_run: int = 0
var _tests_passed: int = 0
var _tests_failed: int = 0
var _checks: int = 0


func _initialize() -> void:
	# Clock and mode only. Nothing that prints, nothing that needs the tree: see
	# the class docs for why neither works here.
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	_is_child = user_args.has(CHILD_FLAG) or user_args.has(IN_PROCESS_FLAG)

	Engine.physics_ticks_per_second = SIM_HZ * TIME_COMPRESSION
	Engine.time_scale = float(TIME_COMPRESSION)
	Engine.max_fps = 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_current_started_ms = Time.get_ticks_msec()
		if _is_child:
			# Deliberately not awaited: _run_suite is a coroutine that parks on
			# physics frames, and this main loop is what delivers them.
			_run_suite()
		else:
			_supervise()
		return false

	if _finished:
		quit(_exit_code)
		return true

	if not _is_child:
		# The supervisor has no tests of its own to time out; the child carries
		# the per-test budget and exits on its own.
		return false

	if Time.get_ticks_msec() - _current_started_ms > TEST_TIMEOUT_MS:
		printerr("TIMEOUT after %d ms in %s" % [TEST_TIMEOUT_MS, _current])
		printerr("The suite was aborted; results above are incomplete.")
		quit(EXIT_BROKEN)
		return true

	return false


# --- The supervisor -----------------------------------------------------------

## Run the suite in a child Godot and adopt its verdict, plus stderr.
func _supervise() -> void:
	var arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", get_script().resource_path,
		"--", CHILD_FLAG,
	])

	var captured: Array = []
	# read_stderr, so a runtime error lands in the same stream as the report it
	# belongs next to and the ordering in the log is the ordering it happened in.
	var code: int = OS.execute(OS.get_executable_path(), arguments, captured, true, false)

	var transcript: String = ""
	for chunk: Variant in captured:
		transcript += String(chunk)
	# Verbatim: the child's report is the report, and a supervisor that reprints
	# a summary of it is a second thing that can be wrong.
	print(transcript.strip_edges(false, true))

	if code < 0:
		printerr("Could not launch the test child: %s" % OS.get_executable_path())
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	var offenders: PackedStringArray = _engine_errors(transcript)
	if not offenders.is_empty():
		print("")
		print("%d engine error line(s) during the run -- a GDScript runtime error" % offenders.size())
		print("abandons the function it happened in and lets the suite carry on, so")
		print("these do not show up as failing checks. They fail the run anyway:")
		for line: String in offenders:
			print("    %s" % line)
		_exit_code = EXIT_BROKEN if code == EXIT_OK else code
		_finished = true
		return

	_exit_code = code
	_finished = true


## Lines of [param transcript] that carry an engine error marker.
func _engine_errors(transcript: String) -> PackedStringArray:
	var offenders: PackedStringArray = PackedStringArray()
	for line: String in transcript.split("\n"):
		for marker: String in ERROR_MARKERS:
			if line.contains(marker):
				offenders.append(line.strip_edges())
				break
	return offenders


# --- The run ------------------------------------------------------------------

func _run_suite() -> void:
	var started_ms: int = Time.get_ticks_msec()
	print("PANOPTICON test suite")
	print("  engine    %s" % Engine.get_version_info().get("string", "unknown"))
	print("  physics   %d Hz simulated, %dx compressed" % [SIM_HZ, TIME_COMPRESSION])

	var paths: PackedStringArray = _discover(TESTS_ROOT)
	paths.sort()
	if paths.is_empty():
		printerr("No test files found under %s -- expected %s*%s" % [TESTS_ROOT, FILE_PREFIX, FILE_SUFFIX])
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	print("  files     %d" % paths.size())
	print("")

	for path: String in paths:
		await _run_file(path)

	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	print("")
	print("%s  %d tests, %d passed, %d failed, %d checks, %.1f s" % [
		"PASS" if _tests_failed == 0 else "FAIL",
		_tests_run, _tests_passed, _tests_failed, _checks, elapsed_ms / 1000.0,
	])
	if _tests_failed > 0:
		_exit_code = EXIT_FAILED
	_finished = true


func _run_file(path: String) -> void:
	print(path.trim_prefix("res://"))

	var script: GDScript = load(path) as GDScript
	if script == null:
		printerr("  could not load %s as a GDScript" % path)
		_exit_code = EXIT_BROKEN
		return

	var method_names: PackedStringArray = _test_methods(script)
	if method_names.is_empty():
		print("  (no %s methods)" % METHOD_PREFIX)
		return

	for method_name: String in method_names:
		await _run_test(script, path, method_name)


func _run_test(script: GDScript, path: String, method_name: String) -> void:
	_tests_run += 1
	_current = "%s::%s" % [path, method_name]
	_current_started_ms = Time.get_ticks_msec()

	var case: TestCase = script.new() as TestCase
	if case == null:
		printerr("  BROKEN  %s -- %s does not extend TestCase" % [method_name, path])
		_tests_failed += 1
		_exit_code = EXIT_BROKEN
		return

	case.name = "%s_%s" % [path.get_file().get_basename(), method_name]
	root.add_child(case)

	# before_each and after_each may await, and both are called through the same
	# dynamic path as the test itself so a coroutine hook behaves identically to
	# a plain one.
	await case.call("before_each")
	await case.call(method_name)
	await case.call("after_each")

	var elapsed_ms: int = Time.get_ticks_msec() - _current_started_ms
	_checks += case.assertions

	if case.is_failed():
		_tests_failed += 1
		print("  FAIL  %s  (%d checks, %d ms)" % [method_name, case.assertions, elapsed_ms])
		for failure: String in case.failures:
			print("          %s" % failure)
	elif case.assertions == 0:
		# A test that asserts nothing is not a passing test, it is an empty one,
		# and an empty test is the exact shape a deleted assertion leaves behind.
		_tests_failed += 1
		print("  FAIL  %s  (no checks made -- a test that asserts nothing proves nothing)" % method_name)
	else:
		_tests_passed += 1
		print("  pass  %s  (%d checks, %d ms)" % [method_name, case.assertions, elapsed_ms])

	# Free the case and everything a test parented to it, then let the tree
	# actually process the deletions before the next test builds its fixtures.
	root.remove_child(case)
	case.free()
	await physics_frame


# --- Discovery ----------------------------------------------------------------

## Every [code]test_*.gd[/code] under [param dir_path], recursively.
func _discover(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		elif entry.begins_with(FILE_PREFIX) and entry.ends_with(FILE_SUFFIX):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Test method names, in declaration order.
##
## [method Script.get_script_method_list] reports only the methods the script
## itself declares, not its base's, which is why [TestCase]'s own helpers never
## show up here however they are named.
func _test_methods(script: GDScript) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for entry: Dictionary in script.get_script_method_list():
		var method_name: String = String(entry.get("name", ""))
		if method_name.begins_with(METHOD_PREFIX):
			found.append(method_name)
	return found
