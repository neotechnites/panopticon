class_name TestCase
extends Node

## Base class for every test in [code]tests/[/code].
##
## A test file [code]extends TestCase[/code] and declares one or more
## [code]test_*()[/code] methods. [code]tools/run_tests.gd[/code] discovers the
## file by name, discovers the methods by prefix, and runs each one on a
## [b]fresh instance[/b] of the case, so no test can inherit state from another.
##
## [b]The instance is a Node in the live scene tree.[/b] The runner adds it under
## the tree root before [method before_each] and frees it after
## [method after_each], so anything a test parents to [code]self[/code] is torn
## down with it. That is the intended way to own fixtures: build them, add them
## as children, and forget about them.
##
## [b]Assertions[/b]
##
## Every helper is deliberately typed rather than taking [Variant]. Typed
## comparisons keep the suite itself free of the unsafe-access warnings the
## project treats as errors, and a typed helper catches a wrong-type comparison
## at parse time instead of quietly passing at runtime. Each helper records a
## check, returns whether it held, and never halts the test -- one test reports
## every failure it finds, not just the first.
##
## [b]Waiting[/b]
##
## Tests may [code]await[/code]. Use [method step_ticks] or
## [method step_seconds] to advance the simulation; both resolve in physics
## frames, which is the only clock [PlayerController] and [Rifle] run on.
##
## [b]Simulated time is not wall-clock time.[/b] The runner raises
## [member Engine.physics_ticks_per_second] and [member Engine.time_scale] by the
## same factor, so the physics delta stays exactly [code]1/60 s[/code] -- the
## step the shipped game runs at -- while ticks execute far faster than real
## time. A test that simulates a 35 second lap therefore costs a couple of
## seconds of CI. Never assert against [method Time.get_ticks_msec]; assert
## against tick counts and against the deltas the nodes themselves accumulate.

## The simulated physics rate, in hertz. Matches the project's
## [code]physics/common/physics_ticks_per_second[/code]; the runner preserves
## this delta no matter how fast it drives the loop.
const SIM_HZ: float = 60.0

## Length of one simulated physics tick, in seconds.
const SIM_DELTA: float = 1.0 / SIM_HZ

## How many checks this test has made. Reported so a test that silently stops
## asserting is visible as a check count that fell.
var assertions: int = 0

## One readable line per failed check.
var failures: PackedStringArray = PackedStringArray()


## Runs before the test method. Build fixtures here; parent them to [code]self[/code].
func before_each() -> void:
	pass


## Runs after the test method, pass or fail. Children of this node are freed by
## the runner regardless, so override this only for things outside the tree
## (a global singleton's state, an [InputMap] action, a changed engine setting).
func after_each() -> void:
	pass


func is_failed() -> bool:
	return not failures.is_empty()


# --- Waiting ------------------------------------------------------------------

## Advance the simulation by [param count] physics ticks.
func step_ticks(count: int) -> void:
	var tree: SceneTree = get_tree()
	for _i: int in count:
		await tree.physics_frame


## Advance the simulation by [param seconds] of simulated time, rounded up to a
## whole tick.
func step_seconds(seconds: float) -> void:
	await step_ticks(int(ceilf(seconds * SIM_HZ)))


# --- Assertions ---------------------------------------------------------------

## Record a check. Every other assertion routes through here.
func check(condition: bool, message: String) -> bool:
	assertions += 1
	if condition:
		return true
	failures.append(message)
	return false


## Record an unconditional failure.
func fail(message: String) -> bool:
	return check(false, message)


func assert_true(value: bool, message: String) -> bool:
	return check(value, "%s -- expected true, got false" % message)


func assert_false(value: bool, message: String) -> bool:
	return check(not value, "%s -- expected false, got true" % message)


func assert_eq_int(actual: int, expected: int, message: String) -> bool:
	return check(actual == expected, "%s -- expected %d, got %d" % [message, expected, actual])


func assert_eq_string(actual: String, expected: String, message: String) -> bool:
	return check(actual == expected, "%s -- expected \"%s\", got \"%s\"" % [message, expected, actual])


## Float equality with an explicit tolerance. There is no zero-tolerance float
## comparison on purpose: a test that demands bit equality of two computed
## floats is a test that will fail on somebody else's CPU.
func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(
		absf(actual - expected) <= tolerance,
		"%s -- expected %.6f +/- %.6f, got %.6f (off by %.6f)" % [
			message, expected, tolerance, actual, actual - expected,
		],
	)


func assert_gt(actual: float, threshold: float, message: String) -> bool:
	return check(actual > threshold, "%s -- expected > %.6f, got %.6f" % [message, threshold, actual])


func assert_ge(actual: float, threshold: float, message: String) -> bool:
	return check(actual >= threshold, "%s -- expected >= %.6f, got %.6f" % [message, threshold, actual])


func assert_lt(actual: float, threshold: float, message: String) -> bool:
	return check(actual < threshold, "%s -- expected < %.6f, got %.6f" % [message, threshold, actual])


func assert_le(actual: float, threshold: float, message: String) -> bool:
	return check(actual <= threshold, "%s -- expected <= %.6f, got %.6f" % [message, threshold, actual])


func assert_between(actual: float, low: float, high: float, message: String) -> bool:
	return check(
		actual >= low and actual <= high,
		"%s -- expected within [%.6f, %.6f], got %.6f" % [message, low, high, actual],
	)


func assert_vec3_almost_eq(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> bool:
	return check(
		actual.distance_to(expected) <= tolerance,
		"%s -- expected %v +/- %.6f, got %v (off by %.6f)" % [
			message, expected, tolerance, actual, actual.distance_to(expected),
		],
	)


func assert_vec2_eq(actual: Vector2, expected: Vector2, message: String) -> bool:
	return check(actual == expected, "%s -- expected %v, got %v" % [message, expected, actual])


func assert_not_null(value: Object, message: String) -> bool:
	return check(value != null, "%s -- expected an object, got null" % message)


func assert_null(value: Object, message: String) -> bool:
	return check(value == null, "%s -- expected null, got %s" % [message, value])


## Identity, not equality: the two references must be the same object.
func assert_same(actual: Object, expected: Object, message: String) -> bool:
	return check(
		actual == expected,
		"%s -- expected %s, got %s" % [message, _describe(expected), _describe(actual)],
	)


func _describe(value: Object) -> String:
	if value == null:
		return "<null>"
	var node: Node = value as Node
	if node != null:
		return "%s(%s)" % [node.get_class(), node.name]
	return str(value)
