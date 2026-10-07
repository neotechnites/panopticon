class_name SniperKnobs
extends RefCounted

## The guard's per-tower-visit knobs: [constant VISITS] rows of [constant COUNT] floats, visit 1 first.
## Reload is not here; it rides [member MatchRules.reload_seconds_by_turn], already per visit.

## Visits with their own set. The fifth and every later visit play set five.
const VISITS: int = 5

enum Knob {
	MISS_PENALTY, SHOT_SPEED, BULLET_DROP, SWAY, SWAY_RATE, SWAY_SETTLE,
	ZOOM, ZOOM_IN, GUARD_SKILL, HIT_MARKER, HIP_SPREAD,
}

const COUNT: int = 11

## Per knob: the [MatchRules] field it stands in for (&"" for a profile knob), label key,
## min, max, step, default, readout unit key ("" a plain number, "toggle" a switch).
const SPECS: Array[Array] = [
	[&"guard_miss_penalty_seconds", "DEBUG_MISS_PENALTY", 0.0, 30.0, 0.1, 0.0, "DEBUG_UNIT_SECONDS"],
	[&"guard_projectile_speed", "DEBUG_SHOT_SPEED", 0.0, 3600.0, 5.0, 0.0, "DEBUG_UNIT_SPEED"],
	[&"", "DEBUG_BULLET_DROP", 0.0, 180.0, 0.5, 22.0, "DEBUG_UNIT_ACCEL"],
	[&"scope_sway_degrees", "DEBUG_SWAY", 0.0, 15.0, 0.05, 0.0, "DEBUG_UNIT_DEGREES"],
	[&"scope_sway_hz", "DEBUG_SWAY_RATE", 0.02, 6.0, 0.01, 0.25, "DEBUG_UNIT_HZ"],
	[&"scope_sway_settle_seconds", "DEBUG_SWAY_SETTLE", 0.0, 90.0, 0.5, 0.0, "DEBUG_UNIT_SECONDS"],
	[&"", "DEBUG_ZOOM", 1.0, 30.0, 0.25, 5.0, "DEBUG_UNIT_TIMES"],
	[&"", "DEBUG_ZOOM_IN", 0.0, 3.0, 0.01, 0.5, "DEBUG_UNIT_SECONDS"],
	[&"guard_skill", "DEBUG_GUARD_SKILL", 0.0, 1.0, 0.05, 0.5, "DEBUG_UNIT_FRACTION"],
	[&"guard_hit_marker", "DEBUG_HIT_MARKER", 0.0, 1.0, 1.0, 1.0, "toggle"],
	[&"guard_hip_spread_degrees", "DEBUG_HIP_SPREAD", 0.0, 30.0, 0.25, 8.0, "DEBUG_UNIT_DEGREES"],
]


## Every visit at the shipped defaults.
static func defaults() -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(VISITS * COUNT)
	for visit: int in VISITS:
		for knob: int in COUNT:
			values[visit * COUNT + knob] = float(SPECS[knob][5])
	return values


## Index of [param knob] in visit [param visit_index] (zero-based; past the last reads the last).
static func index(visit_index: int, knob: int) -> int:
	return clampi(visit_index, 0, VISITS - 1) * COUNT + knob


## [param values] clamped into every knob's range; a wrong size comes back as the defaults.
static func clamped(values: PackedFloat32Array) -> PackedFloat32Array:
	if values.size() != VISITS * COUNT:
		return defaults()
	var out: PackedFloat32Array = values.duplicate()
	for at: int in out.size():
		var spec: Array = SPECS[at % COUNT]
		out[at] = clampf(out[at], float(spec[2]), float(spec[3])) if is_finite(out[at]) else float(spec[5])
	return out


## Write visit [param visit_index]'s profile knobs (drop, zoom, zoom-in) into the live profiles.
static func apply_profiles(values: PackedFloat32Array, visit_index: int, weapon: WeaponProfile,
		zoom: ZoomProfile) -> void:
	if values.size() != VISITS * COUNT:
		return
	if weapon != null:
		weapon.projectile_gravity = values[index(visit_index, Knob.BULLET_DROP)]
	if zoom != null:
		zoom.zoom_factor = 1.0 / maxf(values[index(visit_index, Knob.ZOOM)], 1.0)
		zoom.zoom_in_seconds = values[index(visit_index, Knob.ZOOM_IN)]
