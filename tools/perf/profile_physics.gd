extends SceneTree

## Per-map physics profiler: what one tick of a full match costs on THIS map.
##
## [codeblock]
## godot --headless --path . --script res://tools/perf/profile_physics.gd -- \
##     --map=forest --warmup=120 --ticks=1080 --seed=20260930
## [/codeblock]
##
## [codeblock]
## --map=ID       a MapCatalog id, or a res:// scene path  (default: the rules' map)
## --warmup=N     ticks run before the counters start      (default 120)
## --ticks=N      the measurement window, in ticks         (default 1080)
## --seed=N       aim RNG seed; 0 means entropy            (default 20260930)
## [/codeblock]
##
## Prints one line and exits:
##
## [codeblock]
## PHYS map=forest seats=8 ticks=1080 avg_ms=1.187 worst_ms=5.41 peak_ms=6.02 \
##      objects_per_tick=0.0019 phys_active=41.0 phys_pairs=96.3 nodes=1204
## [/codeblock]
##
## [b]Why this exists next to tests/test_budgets.gd[/b]
##
## The budgets are a GATE: one map, one shape, pass or fail. This is the same
## instrument pointed at a QUESTION -- "what did the new map do to the tick?" --
## which a gate cannot answer, because a gate that fails tells you a number
## moved and not which map moved it. Everything measured here is measured the
## way [code]tests/test_budgets.gd[/code] measures it, deliberately, so the two
## numbers can be read against each other: the same seven prisoners plus a
## guard, the same rounds and lives raised to 99 so the window is play rather
## than a match ending at the first pad, the same warmup, the same
## second-worst-sample convention for [code]worst_ms[/code]. Only the map moves.
##
## [b]These are not the PC's numbers[/b] -- see [code]docs/PERF_REVIEW.md[/code]
## §2 and [code]tools/perf/profile_match.gd[/code], which is the profiler that
## can see a GPU. What this sees is the simulation: bodies, pairs, nav, and the
## bot AI that walks over whatever geometry the map put in front of it. That is
## exactly the part a map author changes.
##
## [b]Three headless facts this file is built around[/b], the same three
## [code]tools/harness/run_bot_match.gd[/code] is built around: [method
## SceneTree.quit] from [method _initialize] exits before stdout is flushed;
## nodes added during [method _initialize] are not in the tree, so every
## global_position reads back as the origin; and the main loop is real-time
## locked, which [method BotHarness.apply_time_compression] answers. So
## [method _initialize] configures the clock and nothing else, and all the work
## happens in [method _process].

const RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const SHOOTER_PROFILE_PATH: String = "res://scenes/bot/default_shooter_profile.tres"

## Seven, because seven is the full lobby and the only count the physics tick
## has ever failed at. Same constant, same reason, as the budgets file.
const BOTS: int = 7

const EXIT_OK: int = 0
const EXIT_BROKEN: int = 2

## [code]tools/run_tests.gd[/code]'s [code]TIME_COMPRESSION[/code]. Duplicated
## rather than imported because that file is a [SceneTree] main loop and cannot
## be loaded from another one. If it changes there, change it here: the two
## being equal is the only reason avg_ms may be compared with B1.
const RUN_TESTS_COMPRESSION: int = 50

## Counts what one physics tick costs, from inside the tick loop.
##
## Lifted from [code]tests/test_budgets.gd[/code]'s TickSampler and extended
## with the two physics monitors, so a map that costs more is attributable:
## avg_ms says it got slower, phys_active and phys_pairs say whether that is
## more bodies awake or more broadphase work. Wall clock between consecutive
## callbacks is the only honest instrument here -- the run compresses simulated
## time, so a tick's DELTA is pinned at 1/60 s however long the machine took
## over it. Priority is raised so this samples last in the tick.
class TickSampler extends Node:
	var ticks: int = 0
	var worst_usec: int = 0
	## Second-highest sample. One tick in ~1080 can be stolen by the OS
	## scheduler regardless of game code, so the single worst is reported as
	## peak_ms and worst_ms carries this one -- the same forgiven outlier B2
	## gates on, so the two numbers mean the same thing.
	var second_worst_usec: int = 0
	var total_usec: int = 0
	var objects_gained: int = 0
	var active_total: float = 0.0
	var pairs_total: float = 0.0
	var _last_usec: int = -1
	var _last_objects: int = -1
	var _armed: bool = false

	func _init() -> void:
		process_priority = 100

	## Start counting. Called after the warmup, so setup is not in the window.
	func arm() -> void:
		_armed = true
		_last_usec = -1
		_last_objects = -1

	func _physics_process(_delta: float) -> void:
		var now: int = Time.get_ticks_usec()
		var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if _armed and _last_usec >= 0:
			var spent: int = now - _last_usec
			if spent > worst_usec:
				second_worst_usec = worst_usec
				worst_usec = spent
			elif spent > second_worst_usec:
				second_worst_usec = spent
			total_usec += spent
			objects_gained += maxi(objects - _last_objects, 0)
			active_total += Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
			pairs_total += Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
			ticks += 1
		_last_usec = now
		_last_objects = objects


var _options: Dictionary = {}
var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK


func _initialize() -> void:
	_options = BotHarness.parse_arguments({
		"map": "",
		"warmup": 120,
		"ticks": 1080,
		"seed": BotHarness.DEFAULT_SEED,
	})
	# The TEST RUNNER's clock, not the harness's. The delta every
	# _physics_process sees is exactly 1/60 s either way, so the simulation is
	# the shipped one whichever is used -- but the compression sets how many
	# ticks are retired per main-loop iteration, and that decides how the idle
	# cost between batches lands on a sample. tools/run_tests.gd runs at 50 and
	# tests/test_budgets.gd's numbers are B1 and B2. Matching it is what lets
	# this tool's avg_ms and worst_ms be read against those two gates rather
	# than only against each other.
	BotHarness.apply_time_compression(RUN_TESTS_COMPRESSION)
	# ...with one thing put back. apply_time_compression also lifts the cap on
	# steps per main-loop iteration, which is right for a sweep -- it is what
	# stops the loop rate being the ceiling -- and wrong for THIS instrument.
	# The sampler measures wall clock between consecutive physics callbacks, so
	# with a 120 step batch the whole idle frame between batches lands on one
	# tick: measured here, that single sample went from 9 ms to 42 ms while the
	# game did not change. Capped at the project default the batches are small,
	# the idle cost is spread, and avg_ms/worst_ms mean what the same numbers
	# mean in tests/test_budgets.gd, which is the entire point of matching that
	# file. It costs wall clock and no fidelity: the delta is untouched.
	Engine.max_physics_steps_per_frame = ProjectSettings.get_setting(
		"physics/common/max_physics_steps_per_frame", 8
	)


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
		_break("Bad command line; nothing was measured.")
		return

	var rules: MatchRules = _rules()
	if rules == null:
		return

	var holder: Node = Node.new()
	holder.name = "PhysProfile"
	root.add_child(holder)

	var world: BotMatchWorld = _build_match(holder, rules)
	if world == null:
		return

	var sampler: TickSampler = TickSampler.new()
	sampler.name = "TickSampler"
	holder.add_child(sampler)

	await _step_ticks(maxi(int(_options.get("warmup", 120)), 0))
	sampler.arm()
	await _step_ticks(maxi(int(_options.get("ticks", 1080)), 1))

	if sampler.ticks <= 0:
		_break("The measurement window ran no ticks; nothing was measured.")
		return

	# Seven prisoners plus whoever holds the tower seat: the guard is a
	# participant too, and a match that lost one would measure a quieter game.
	# Read after the window, as the budgets read it, because the roster is the
	# controller's to fill and not this file's to predict.
	var seats: int = world.get_controller().get_participants().size()
	if seats <= 0:
		_break("The match stood up with no participants; nothing was measured.")
		return

	var window: float = float(sampler.ticks)
	print("PHYS map=%s seats=%d ticks=%d avg_ms=%.3f worst_ms=%.3f peak_ms=%.3f objects_per_tick=%.4f phys_active=%.1f phys_pairs=%.1f nodes=%d" % [
		String(rules.map_id),
		seats,
		sampler.ticks,
		float(sampler.total_usec) / window / 1000.0,
		float(sampler.second_worst_usec) / 1000.0,
		float(sampler.worst_usec) / 1000.0,
		float(sampler.objects_gained) / window,
		sampler.active_total / window,
		sampler.pairs_total / window,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	])
	_finished = true


## The rules the window is measured under, or null when the map cannot be run.
##
## [member MatchRules.map_id] is set here and nowhere else, which is the whole
## point of the tool. An id the catalog does not have is refused rather than
## resolved: [method MapCatalog.scene_path_for] falls back to the default map,
## which is correct for a player with a stale settings file and wrong for a
## profiler, because it would answer a question about [code]forest[/code] with a
## measurement of [code]bentham_ring[/code] and say nothing about the swap.
func _rules() -> MatchRules:
	var loaded: MatchRules = load(RULES_PATH) as MatchRules
	if loaded == null:
		_break("Could not load %s; nothing was measured." % RULES_PATH)
		return null

	var rules: MatchRules = loaded.duplicate() as MatchRules
	rules.prisoner_count = BOTS
	# Raised so the window measures play rather than a match that ended at the
	# first pad. The budgets file raises them for the same reason.
	rules.rounds_to_win_match = 99
	rules.prisoner_lives = 99

	var wanted: String = String(_options.get("map", "")).strip_edges()
	if not wanted.is_empty():
		rules.map_id = StringName(wanted)
	if wanted.begins_with("res://"):
		if not ResourceLoader.exists(wanted):
			_break("No scene at %s; nothing was measured." % wanted)
			return null
	elif not MapCatalog.has(rules.map_id):
		_break("No map %s in %s; nothing was measured." % [rules.map_id, MapCatalog.CATALOG_PATH])
		return null

	var arena_path: String = BotMatchWorld.resolve_arena_path(rules)
	if arena_path.is_empty() or not ResourceLoader.exists(arena_path):
		_break("Map %s resolves to no loadable scene; nothing was measured." % rules.map_id)
		return null
	return rules


## Exactly the world [code]tests/test_budgets.gd::_build_match[/code] builds:
## seven prisoners, one bot in the tower seat, the match started by hand and the
## local input silenced. Parented to [param holder] rather than to the tree root
## so the whole thing is one subtree.
func _build_match(holder: Node, rules: MatchRules) -> BotMatchWorld:
	var shooter: ShooterProfile = load(SHOOTER_PROFILE_PATH) as ShooterProfile
	if shooter == null:
		_break("Could not load %s; nothing was measured." % SHOOTER_PROFILE_PATH)
		return null

	var world: BotMatchWorld = BotMatchWorld.new()
	holder.add_child(world)
	world.build(rules)

	var controller: MatchController = world.get_controller()
	if controller == null:
		_break("The world built no MatchController; nothing was measured.")
		return null

	var seat: BotTowerSeat = BotTowerSeat.new()
	seat.name = "TowerSeat"
	holder.add_child(seat)
	seat.install(controller, shooter.duplicate() as ShooterProfile, int(_options.get("seed", BotHarness.DEFAULT_SEED)))

	controller.start_match()
	BotMatchWorld.silence_local_input(world.get_runner_container())
	return world


## Advance the simulation by [param count] physics ticks.
func _step_ticks(count: int) -> void:
	for _i: int in count:
		await physics_frame


## Report why nothing could be measured and end the run with [constant EXIT_BROKEN].
func _break(reason: String) -> void:
	printerr("profile_physics: %s" % reason)
	_exit_code = EXIT_BROKEN
	_finished = true
