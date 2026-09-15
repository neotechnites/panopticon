class_name RunnerProfile
extends Resource

## Every tunable of an AI prisoner: what it may perceive, and how it plays.
## A round overrides it through [member MatchRules.ai_runner_profile].

enum Behaviour {
	## Runs the lap and ignores the tower: the control case every claim is measured against.
	BASELINE,
	## Runs the lap and takes cover when the rifle is on it. See [RunnerBrain].
	COVER,
}

@export var behaviour: Behaviour = Behaviour.COVER

@export_group("Perception")
@export_range(20.0, 179.0, 1.0) var view_fov_degrees: float = 100.0
@export_range(0.5, 4.0, 0.01) var view_aspect: float = 1.7778
@export_range(0.1, 1.0, 0.01) var fov_margin: float = 0.9
@export_range(0.0, 3.0, 0.05) var eye_height: float = 1.6
## Height above the feet a shot is judged against; the same point the rifle aims at.
@export_range(0.0, 2.0, 0.05) var cover_test_height: float = 0.9
## Seconds a changed reading of the guard's attention must hold before it is believed.
@export_range(0.0, 3.0, 0.01) var reaction_seconds: float = 0.35
@export_range(1.0, 180.0, 1.0) var attention_cone_degrees: float = 30.0
@export_range(0.0, 90.0, 0.5) var attention_read_error_degrees: float = 14.0
@export_range(0.02, 5.0, 0.01) var attention_resample_seconds: float = 0.4
## Seconds out of sight of the tower before the runner assumes it is watched again.
@export_range(0.0, 20.0, 0.1) var threat_memory_seconds: float = 1.5
## A round landing this close is a round meant for this prisoner.
@export_range(0.0, 30.0, 0.5) var tracer_alarm_metres: float = 6.0
@export var perception_seed: int = 0
@export_range(0.1, 15.0, 0.05) var assumed_reload_seconds: float = 2.5
@export_range(0.0, 1.0, 0.01) var reload_read_accuracy: float = 0.75
@export_range(0.0, 3.0, 0.01) var reload_safety_margin: float = 0.35

@export_group("Play")
## Chance the runner keeps running when it believes it is watched; shot at, it always hides.
@export_range(0.0, 1.0, 0.01) var boldness: float = 0.5
## How far ahead a cover point is worth a detour.
@export_range(1.0, 60.0, 0.5) var cover_reach_metres: float = 12.0
## Seconds behind cover before the runner goes anyway.
@export_range(0.0, 30.0, 0.1) var cover_patience_seconds: float = 3.0
## Seconds behind cover before any reason to leave counts.
@export_range(0.0, 10.0, 0.05) var hold_min_seconds: float = 0.4
## Under 0.5 the runner refuses the hard jumps and walks the long way round.
@export_range(0.0, 1.0, 0.01) var jump_confidence: float = 0.7


func plays_cover() -> bool:
	return behaviour == Behaviour.COVER


## The half-angles of the runner's view, horizontal then vertical, in radians.
func get_view_half_angles() -> Vector2:
	var vertical: float = deg_to_rad(view_fov_degrees) * 0.5
	return Vector2(atan(tan(vertical) * view_aspect), vertical) * fov_margin


func get_attention_cone_radians() -> float:
	return deg_to_rad(attention_cone_degrees)


func get_attention_read_error_radians() -> float:
	return deg_to_rad(attention_read_error_degrees)


## A generator seeded from [param seed_override], else [member perception_seed]; 0 means entropy.
func make_rng(seed_override: int = 0) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var chosen: int = seed_override if seed_override != 0 else perception_seed
	if chosen == 0:
		rng.randomize()
	else:
		rng.seed = chosen
	return rng


## The profile the round's rules name, or [param fallback] when they have no opinion.
static func resolve(rules: MatchRules, fallback: RunnerProfile) -> RunnerProfile:
	if rules == null:
		return fallback
	var exported: RunnerProfile = rules.get("ai_runner_profile") as RunnerProfile
	if exported != null:
		return exported
	if rules.has_meta(&"ai_runner_profile"):
		var from_meta: RunnerProfile = _as_profile(rules.get_meta(&"ai_runner_profile"))
		if from_meta != null:
			return from_meta
	return fallback


## A metadata value read back as a profile: the resource itself, or a path to one.
static func _as_profile(value: Variant) -> RunnerProfile:
	var direct: RunnerProfile = value as RunnerProfile
	if direct != null:
		return direct
	if typeof(value) == TYPE_STRING:
		var loaded: RunnerProfile = load(String(value)) as RunnerProfile
		if loaded == null:
			push_error("MatchRules.ai_runner_profile names %s, which is not a RunnerProfile." % String(value))
		return loaded
	push_error("MatchRules.ai_runner_profile is neither a RunnerProfile nor a path to one.")
	return null
