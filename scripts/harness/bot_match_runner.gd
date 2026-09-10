class_name BotMatchRunner
extends Node

## One headless bot-versus-bot match, from an empty tree to a result dictionary.
##
## [codeblock]
## var runner: BotMatchRunner = BotMatchRunner.new()
## runner.configure(rules, "baseline", 0, 20260930, 36000)
## add_child(runner)
## runner.begin()
## var result: Dictionary = await runner.finished
## [/codeblock]
##
## [b]It must not hang, and that is a design constraint rather than a hope[/b]
##
## A sweep runs unattended. A match that never resolves -- because the shooter
## cannot see, because a rule combination has no terminator, because a body fell
## through the deck -- must cost a bounded number of ticks and then be RECORDED
## as unresolved. Discarding it would silently bias every average the sweep
## reports towards the matches that happened to end; blocking on it would eat
## the whole run. So there is a tick ceiling, a match that reaches it is written
## out with [code]status: "UNRESOLVED"[/code] and its reason, and the aggregate
## reports resolved and unresolved counts side by side.
##
## [b]What "deterministic where it can be" means here[/b]
##
## The physics delta is pinned at 1/60 s regardless of time compression, the
## shooter's aim RNG is seeded from the harness seed and the participant index,
## and the optic runs on the physics tick rather than the render tick. Given the
## same seed, the same rules and the same machine, two runs execute the same
## ticks. Across machines, floating-point differences in the physics solver can
## still diverge, which is why a result file records its seed rather than
## claiming reproducibility it cannot enforce.

## Emitted once, on the tick the match stops for any reason. Carries the full
## result dictionary; see tools/harness/RESULT_SCHEMA.md.
signal finished(result: Dictionary)

## The rate the simulation is pinned to, whatever the wall clock is doing.
const SIM_HZ: int = 60

const SHOOTER_PROFILE_PATH: String = "res://scenes/bot/default_shooter_profile.tres"

var _rules: MatchRules = null
var _variant: String = "default"
var _match_index: int = 0
var _seed: int = 0
var _max_ticks: int = SIM_HZ * 600

var _world: BotMatchWorld = null
var _telemetry: BotMatchTelemetry = null
var _seat: BotTowerSeat = null

var _running: bool = false
var _reported: bool = false
var _wall_started_ms: int = 0
var _wall_elapsed_ms: int = 0
var _status: String = "UNRESOLVED"
var _reason: String = "the match never started"


## Set up the match. Call before [method begin], and before this node enters the
## tree if you like -- nothing here touches the scene.
##
## [param rules] is used as given and is not duplicated: a sweep owns its
## variants and duplicating here would hide a caller mutating one between
## matches, which is a bug worth seeing.
func configure(
	rules: MatchRules,
	variant: String,
	match_index: int,
	seed_value: int,
	max_ticks: int,
) -> void:
	_rules = rules
	_variant = variant
	_match_index = match_index
	_seed = seed_value
	_max_ticks = maxi(max_ticks, 1)


## Build the world, arm the watchers, and start the match.
##
## The order is the whole of the correctness here. The telemetry and the tower
## brain are connected BEFORE [method MatchController.start_match], because the
## opening race and the first seat grant are both emitted from inside it and a
## watcher connected afterwards would miss the start of the match it is
## measuring.
func begin() -> void:
	if _running or _reported:
		return

	_world = BotMatchWorld.new()
	add_child(_world)
	_world.build(_rules)

	var controller: MatchController = _world.get_controller()

	_telemetry = BotMatchTelemetry.new()
	_telemetry.name = "Telemetry"
	# Before the match, so the tick a signal fires on is the tick it is counted
	# on rather than the one after.
	_telemetry.process_priority = -100
	add_child(_telemetry)
	_telemetry.install(controller, _world.get_rifle())

	_seat = BotTowerSeat.new()
	_seat.name = "TowerSeat"
	add_child(_seat)
	_seat.install(controller, _shooter_profile(), _seed)

	_status = "UNRESOLVED"
	_reason = "the match did not reach a conclusion"
	_wall_started_ms = Time.get_ticks_msec()
	_running = true

	controller.start_match()
	# The AI bodies exist only once the match has been armed, so this is the
	# first moment their inherited human-input nodes can be switched off.
	BotMatchWorld.silence_local_input(_world.get_runner_container())


## The result, once [signal finished] has been emitted. Empty before that.
func get_result() -> Dictionary:
	return _build_result() if _reported else {}


func _physics_process(_delta: float) -> void:
	if not _running:
		return

	var controller: MatchController = _world.get_controller()
	if controller.is_match_over():
		_stop("RESOLVED", "")
		return

	if _telemetry.get_ticks() >= _max_ticks:
		_stop("UNRESOLVED", (
			"hit the tick ceiling of %d ticks (%.1f simulated seconds) in phase %s, round %d"
			% [
				_max_ticks,
				float(_max_ticks) / float(SIM_HZ),
				controller.get_phase_name(),
				controller.get_round_number(),
			]
		))


func _stop(status: String, reason: String) -> void:
	if _reported:
		return
	_running = false
	_reported = true
	_status = status
	_reason = reason
	_wall_elapsed_ms = Time.get_ticks_msec() - _wall_started_ms

	# Stop the world before reading it. A body still running while the result is
	# assembled would put a lap in one field and not in the next.
	set_physics_process(false)
	_telemetry.set_physics_process(false)
	_freeze_world()
	_telemetry.finalise()

	finished.emit(_build_result())


## Take every body and both brains out of the physics tick.
##
## The match freezes its participants when it is WON, and correctly does not
## when a round is merely unresolved -- so a match stopped by the tick ceiling
## is still running at the moment the harness stops watching it, and would go on
## running while the next match is being built if it were left alone.
func _freeze_world() -> void:
	var controller: MatchController = _world.get_controller()
	for participant: MatchParticipant in controller.get_participants():
		if participant.body != null:
			participant.body.velocity = Vector3.ZERO
			participant.body.set_physics_process(false)
		if participant.brain != null:
			participant.brain.set_physics_process(false)
	var shooter: TowerShooter = _seat.get_active_shooter()
	if shooter != null:
		shooter.set_physics_process(false)
	_world.get_rifle().set_physics_process(false)


## A private copy of the tuned shooter profile.
##
## Duplicated because [BotTowerSeat] writes a seed into its copy per
## participant, and the .tres is one shared instance for the whole process: a
## sweep that retuned it would hand every later match a shooter that had been
## quietly modified by an earlier one.
func _shooter_profile() -> ShooterProfile:
	var profile: ShooterProfile = load(SHOOTER_PROFILE_PATH) as ShooterProfile
	return profile.duplicate() as ShooterProfile


# --- The result ---------------------------------------------------------------

func _build_result() -> Dictionary:
	var controller: MatchController = _world.get_controller()
	var ticks: int = _telemetry.get_ticks()
	var wall_seconds: float = float(_wall_elapsed_ms) / 1000.0
	var simulated_seconds: float = float(ticks) / float(SIM_HZ)

	var result: Dictionary = {
		"schema": "panopticon.bot_match.v1",
		"variant": _variant,
		"match_index": _match_index,
		"seed": _seed,
		"engine": String(Engine.get_version_info().get("string", "unknown")),
		"recorded_at": Time.get_datetime_string_from_system(true, true),
		"status": _status,
		"unresolved_reason": _reason,
		"rules": rules_to_dictionary(controller.get_rules()),
		"outcome": _outcome_dictionary(controller),
		"duration": {
			"simulated_seconds": simulated_seconds,
			"physics_ticks": ticks,
			"tick_ceiling": _max_ticks,
			"wall_seconds": wall_seconds,
			"compression_achieved": (
				simulated_seconds / wall_seconds if wall_seconds > 0.0 else 0.0
			),
		},
	}
	result.merge(_telemetry.to_dictionary(SIM_HZ))
	return result


func _outcome_dictionary(controller: MatchController) -> Dictionary:
	var winner: MatchParticipant = controller.get_match_winner()
	return {
		"winner_index": winner.index if winner != null else -1,
		"winner_name": winner.display_name if winner != null else "",
		"winner_kind": ("HUMAN" if winner.is_human() else "AI") if winner != null else "",
		# Under the shipped rules only a shooter can win a match, so this is
		# TOWER on every resolved match today. It is recorded from the match's
		# own answer rather than assumed, so the day a runner win condition
		# lands the sweep files start saying RUNNER without a change here.
		"winner_role": (
			("TOWER" if _telemetry.winner_held_the_tower() else "RUNNER")
			if winner != null
			else "NONE"
		),
		"final_phase": controller.get_phase_name(),
		"final_round_outcome": controller.get_outcome_name(),
	}


## Every design parameter of [param rules], by reflection.
##
## Reflected rather than listed so that a rule added to [MatchRules] tomorrow
## appears in tomorrow's result files without an edit here -- which matters,
## because a swept parameter missing from the file it is swept into is a result
## nobody can interpret. Enum-valued fields carry a [code]_name[/code] companion
## so the file is readable without the source.
static func rules_to_dictionary(rules: MatchRules) -> Dictionary:
	var out: Dictionary = {}
	if rules == null:
		return out

	for entry: Dictionary in rules.get_property_list():
		var usage: int = int(entry.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var key: String = String(entry.get("name", ""))
		if key.is_empty() or key.begins_with("_"):
			continue

		var value: Variant = rules.get(key)
		# typeof first: `as Resource` on an int or a bool is an invalid cast and
		# raises, rather than yielding null the way it does for a mismatched
		# object -- and a rules table is mostly numbers.
		var nested: Resource = value as Resource if typeof(value) == TYPE_OBJECT else null
		if nested != null:
			# A rule that IS a resource -- the ghost tuning, the weapon, the
			# runner difficulty -- carries its numbers one level down, and a
			# result file that recorded only "an object was set here" would be a
			# swept parameter nobody could read back. One level, not a walk: a
			# resource that pointed at itself would otherwise write until the
			# disk filled.
			out[key] = _resource_to_dictionary(nested)
			continue
		if typeof(value) == TYPE_PACKED_FLOAT32_ARRAY:
			# JSON has one number type and no packed arrays. Widening here keeps
			# the file readable by anything that reads JSON, which is the point
			# of writing one.
			var packed: PackedFloat32Array = value
			var floats: Array = []
			for number: float in packed:
				floats.append(number)
			out[key] = floats
		else:
			out[key] = value

		var hint: String = String(entry.get("hint_string", ""))
		if int(entry.get("hint", 0)) == PROPERTY_HINT_ENUM:
			out["%s_name" % key] = _enum_name(hint, int(value))

	return out


## One resource's own exported values, flat, for a result file. Objects nested
## inside it are written as their resource path, which is enough to find them and
## short enough to read.
static func _resource_to_dictionary(resource: Resource) -> Dictionary:
	var out: Dictionary = {"resource_path": resource.resource_path}
	for entry: Dictionary in resource.get_property_list():
		var usage: int = int(entry.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var key: String = String(entry.get("name", ""))
		if key.is_empty() or key.begins_with("_"):
			continue
		var value: Variant = resource.get(key)
		var deeper: Resource = value as Resource if typeof(value) == TYPE_OBJECT else null
		out[key] = deeper.resource_path if deeper != null else value
		if int(entry.get("hint", 0)) == PROPERTY_HINT_ENUM:
			out["%s_name" % key] = _enum_name(String(entry.get("hint_string", "")), int(value))
	return out


## The label [param index] carries inside an exported enum's hint string, which
## Godot writes as [code]NAME:0,OTHER:1[/code].
static func _enum_name(hint_string: String, index: int) -> String:
	for pair: String in hint_string.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() == 2 and int(parts[1]) == index:
			return parts[0]
	return str(index)
