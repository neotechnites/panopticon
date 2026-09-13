extends RefCounted

## The named cinematic camera paths [code]tools/capture/run_clip.gd[/code] flies.
##
## A key is [code]{"t": seconds, "pos": Vector3, "look": Vector3, "fov": deg}[/code]
## and a shot is a list of them, Catmull-Rom interpolated. Angles are the ring's
## own -- [code]x = cos(deg) * r, z = sin(deg) * r[/code], the convention
## [method RingRoute._point] uses -- so a section in docs/MAP1_SECTIONS.md can be
## framed by quoting its degrees. Deck surface y = 23, lane r = 52, guard eye
## y = 27.

## Deck surface of the Bentham Ring, the datum every height here is measured off.
const DECK_Y: float = 23.0

## Standing eye height above the deck, so a dolly reads as a body's view.
const EYE: float = 1.65


## Every shot name, in the order they are listed below.
static func names() -> PackedStringArray:
	return PackedStringArray([
		"pit_orbit", "s1_cave", "s2_chain", "s4_run", "s5_fall", "guard_scope",
	])


## The shot called [param shot_name], or an empty dictionary if there is none.
## Carries [code]name[/code], [code]duration[/code] seconds and [code]keys[/code].
static func get_shot(shot_name: String) -> Dictionary:
	match shot_name:
		"pit_orbit":
			return _shot(shot_name, _pit_orbit())
		"s1_cave":
			return _shot(shot_name, _s1_cave())
		"s2_chain":
			return _shot(shot_name, _s2_chain())
		"s4_run":
			return _shot(shot_name, _s4_run())
		"s5_fall":
			return _shot(shot_name, _s5_fall())
		"guard_scope":
			return _shot(shot_name, _guard_scope())
	return {}


## The pose at path time [param t] seconds: [code]pos[/code], [code]look[/code]
## and [code]fov[/code], Catmull-Rom between the two keys it falls between.
static func sample(keys: Array, t: float) -> Dictionary:
	var last: int = keys.size() - 1
	if last < 1:
		return keys[0] if last == 0 else {}
	var time: float = clampf(t, float(keys[0]["t"]), float(keys[last]["t"]))
	var index: int = 0
	while index < last - 1 and float(keys[index + 1]["t"]) < time:
		index += 1

	var a: Dictionary = keys[index]
	var b: Dictionary = keys[index + 1]
	var span: float = float(b["t"]) - float(a["t"])
	var u: float = 0.0 if span <= 0.0 else (time - float(a["t"])) / span
	var before: Dictionary = keys[maxi(index - 1, 0)]
	var after: Dictionary = keys[mini(index + 2, last)]
	return {
		"pos": (a["pos"] as Vector3).cubic_interpolate(b["pos"], before["pos"], after["pos"], u),
		"look": (a["look"] as Vector3).cubic_interpolate(b["look"], before["look"], after["look"], u),
		"fov": lerpf(float(a["fov"]), float(b["fov"]), u),
	}


# --- The paths ----------------------------------------------------------------

## One slow lap of the whole ring, high in the corridor.
##
## Flown inside the deck rather than above it. The ring is a roofed corridor --
## ceiling y = 31.5, closed rock outside it -- so a camera over the pit sees only
## the inner slot and one out beyond the rim films the outside of the shell. Six
## metres up clears every spire, slab and wall on the ground.
static func _pit_orbit() -> Array:
	var keys: Array = []
	for step: int in 9:
		var angle: float = float(step) * 45.0
		keys.append(_key(float(step) * 5.0, angle, 50.0, 5.0, angle + 25.0, 52.0, 0.5, 70.0))
	return keys


## Eye-level dolly through the S1 spire forest, 15-60 deg.
static func _s1_cave() -> Array:
	var keys: Array = []
	for step: int in 5:
		var angle: float = 12.0 + float(step) * 12.0
		keys.append(_key(float(step) * 4.5, angle, 52.0, EYE, angle + 10.0, 51.0, 1.2, 70.0))
	return keys


## Low tracking shot along the S2 boulder chain over the lava, 75-130 deg.
static func _s2_chain() -> Array:
	var keys: Array = []
	for step: int in 5:
		var angle: float = 74.0 + float(step) * 14.0
		keys.append(_key(float(step) * 4.0, angle, 55.2, 1.6, angle + 12.0, 57.0, 0.8, 60.0))
	return keys


## Following the S4 demon-pad flights down the lane, 215-270 deg.
static func _s4_run() -> Array:
	var keys: Array = []
	for step: int in 5:
		var angle: float = 214.0 + float(step) * 14.0
		keys.append(_key(float(step) * 4.0, angle, 54.5, 3.0, angle + 8.0, 52.0, 1.3, 75.0))
	return keys


## Held on the deck at 290 deg, tilting slowly up the outer wall.
static func _s5_fall() -> Array:
	var keys: Array = []
	var heights: PackedFloat32Array = PackedFloat32Array([-2.0, 2.0, 6.0, 10.0])
	for step: int in heights.size():
		keys.append(_key(
			float(step) * 4.6667, 290.0, 44.5, EYE, 292.0, 60.0, heights[step], 65.0
		))
	return keys


## The tower eye, panning slowly across the lava shelf and the split.
static func _guard_scope() -> Array:
	var keys: Array = []
	for step: int in 4:
		keys.append(_key(
			float(step) * 6.6667, 110.0, 9.0, 5.0, 70.0 + float(step) * 26.6667, 55.0, 0.8, 40.0
		))
	return keys


# --- Building keys ------------------------------------------------------------

## One key from ring coordinates: heights are metres above [constant DECK_Y].
static func _key(
	t: float,
	angle: float,
	radius: float,
	height: float,
	look_angle: float,
	look_radius: float,
	look_height: float,
	fov: float,
) -> Dictionary:
	return {
		"t": t,
		"pos": ring_point(angle, radius, height),
		"look": ring_point(look_angle, look_radius, look_height),
		"fov": fov,
	}


## A point [param height] metres above the deck, [param radius] out at
## [param angle_degrees] about the arena axis.
static func ring_point(angle_degrees: float, radius: float, height: float) -> Vector3:
	var angle: float = deg_to_rad(angle_degrees)
	return Vector3(cos(angle) * radius, DECK_Y + height, sin(angle) * radius)


static func _shot(shot_name: String, keys: Array) -> Dictionary:
	return {"name": shot_name, "duration": float(keys[keys.size() - 1]["t"]), "keys": keys}
