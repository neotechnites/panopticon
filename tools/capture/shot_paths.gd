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
		"lake_fall", "scope_hunt", "wall_fall", "s5_survey", "teaser_lap",
		"s2_gap", "s3_open_lane", "pad_flight", "s3_pillar", "s4_edge",
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
		"lake_fall":
			return _shot(shot_name, _lake_fall())
		"scope_hunt":
			return _shot(shot_name, _scope_hunt())
		"wall_fall":
			return _shot(shot_name, _wall_fall())
		"s5_survey":
			return _shot(shot_name, _s5_survey())
		"s2_gap":
			return _shot(shot_name, _s2_gap())
		"s3_open_lane":
			return _shot(shot_name, _s3_open_lane())
		"pad_flight":
			return _shot(shot_name, _pad_flight())
		"s3_pillar":
			return _shot(shot_name, _s3_pillar())
		"s4_edge":
			return _shot(shot_name, _s4_edge())
		"teaser_lap":
			var lap: Dictionary = _shot(shot_name, _teaser_lap())
			# Flown, not aimed: the lens points where the camera is going until
			# it stops, and only the tail has look targets of its own.
			lap["look_ahead"] = 0.14
			lap["look_ahead_until"] = LAP_SECONDS
			return lap
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
		"roll": lerpf(float(a.get("roll", 0.0)), float(b.get("roll", 0.0)), u),
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


## Low tracking shot along the S2 boulder chain over the lava, 76-124 deg.
##
## Flown outside the chain so the landings (r 54.7) sit centred against the cave
## wall and the tower, which is what a portrait frame needs behind a jump.
static func _s2_chain() -> Array:
	var keys: Array = []
	for step: int in 5:
		var angle: float = 76.0 + float(step) * 10.0
		keys.append(_key(float(step) * 3.25, angle, 56.6, 1.2, angle + 8.0, 54.7, 0.3, 58.0))
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


## Walk to the S5 lake lip, then tilt up the lava fall on the outer wall.
##
## The channel runs 292-338 deg with its floor at y 22.7; the fall tops out at
## y 28.8 against the outer wall at r 57.3.
static func _lake_fall() -> Array:
	return [
		_key(0.0, 288.0, 50.0, EYE, 297.0, 54.0, 0.0, 55.0),
		_key(4.0, 293.0, 49.0, EYE, 300.0, 57.0, -0.3, 55.0),
		_key(8.0, 297.0, 48.0, EYE, 301.0, 57.3, -0.3, 55.0),
		_key(12.0, 300.0, 48.0, 1.9, 302.0, 57.3, 4.5, 55.0),
	]


## The tower eye over the S1 spires, zooming from a wide sweep to a scope.
static func _scope_hunt() -> Array:
	return [
		_key(0.0, 8.0, 11.0, 5.0, 15.0, 52.0, 1.0, 42.0),
		_key(3.0, 8.0, 11.0, 5.0, 19.0, 52.0, 1.0, 24.0),
		_key(7.0, 8.0, 11.0, 5.0, 25.0, 52.0, 1.0, 15.0),
		_key(13.0, 8.0, 11.0, 5.0, 33.0, 52.0, 1.0, 13.0),
	]

## Stood on the deck at the S5 channel's near bank, tilting up the lava sheet.
##
## The channel floor is at y 22.7 and the sheet on the outer wall (r 57.3) tops
## out at the slot at y 28.8. Standing at 288 deg keeps solid deck underfoot and
## puts 13 m between the eye and the wall: enough to hold the river, the whole
## drop and the rock over it in one frame.
static func _wall_fall() -> Array:
	return [
		_key(0.0, 288.0, 49.5, EYE, 300.0, 57.3, -0.3, 50.0),
		_key(6.0, 288.5, 49.5, EYE, 300.5, 57.3, 2.4, 50.0),
		_key(12.0, 289.0, 49.5, EYE, 301.0, 57.3, 5.8, 50.0),
	]


## From the S2 bank, held on the second gap of the boulder chain: the shove.
static func _s2_gap() -> Array:
	return [
		_key(0.0, 87.0, 50.6, 2.2, 95.6, 55.0, 0.9, 62.0),
		_key(4.0, 88.5, 50.8, 2.0, 95.6, 55.4, 0.8, 58.0),
		_key(8.0, 90.0, 51.0, 1.9, 95.6, 55.8, 0.8, 56.0),
	]


## Tracking a runner down the open S3 deck from its outer edge, tower behind.
static func _s3_open_lane() -> Array:
	var keys: Array = []
	for step: int in 6:
		var angle: float = 150.0 + float(step) * 9.0
		keys.append(_key(float(step) * 2.5, angle, 58.0, 3.0, angle + 5.0, 50.0, 0.9, 68.0))
	return keys


## Beside the demon pad on the S3 lane at 148 deg, panning with the flight.
static func _pad_flight() -> Array:
	return [
		_key(0.0, 142.0, 47.0, 2.4, 149.0, 51.5, 1.0, 72.0),
		_key(2.5, 144.0, 47.0, 2.6, 155.0, 51.5, 3.0, 72.0),
		_key(5.0, 147.0, 47.0, 2.8, 162.0, 52.0, 1.2, 72.0),
		_key(8.0, 150.0, 47.0, 2.8, 168.0, 52.0, 0.8, 72.0),
	]


## From the S3 deck's outer edge behind the hidden runner, looking down the lane
## the hologram runs, tower to the right.
static func _s3_pillar() -> Array:
	return [
		_key(0.0, 187.0, 56.5, 1.9, 176.0, 52.0, 0.9, 64.0),
		_key(4.0, 186.5, 56.5, 1.8, 170.0, 52.0, 0.9, 60.0),
		_key(8.0, 186.0, 56.5, 1.8, 164.0, 52.0, 0.9, 58.0),
	]


## Low on the S4 lane at 226 deg, looking down at the outer lava strip.
static func _s4_edge() -> Array:
	return [
		_key(0.0, 225.0, 51.0, 1.9, 233.0, 56.0, 0.3, 66.0),
		_key(6.0, 226.5, 51.0, 1.8, 236.0, 57.5, 0.2, 62.0),
	]


## A wide look across the S5 channel, for checking where its lava actually is.
static func _s5_survey() -> Array:
	return [
		_key(0.0, 285.0, 48.0, 6.0, 305.0, 55.0, 2.0, 70.0),
		_key(3.0, 300.0, 47.0, 6.0, 312.0, 57.0, 3.0, 70.0),
		_key(6.0, 315.0, 47.0, 4.0, 322.0, 57.3, 3.0, 70.0),
	]


## One FPV lap of the ring from the start line, then a stop and a turn to the tower.
##
## Radii and heights are picked per section to stay off the geometry -- over the
## S1 spires, low between the S2 river's ridge and the outer wall, inside the S3
## divider, down the S4 lane between its lava strips, over the S5 lake platforms
## -- and the whole route is checked by tools/capture/verify_path.gd.
const LAP_SECONDS: float = 8.0

static func _teaser_lap() -> Array:
	# angle, radius, height, roll, and the time it is reached.
	var route: Array = [
		[5, 52.00, 1.65, 2.3, 0.000],
		[8, 52.00, 1.90, 2.6, 0.386],
		[11, 52.00, 1.90, 3.8, 0.717],
		[14, 52.00, 1.90, 5.1, 0.988],
		[17, 53.90, 1.60, 7.0, 1.222],
		[18, 53.20, 2.50, 9.0, 1.298],
		[21, 54.00, 2.20, 10.8, 1.470],
		[23, 53.50, 2.50, 12.4, 1.569],
		[24, 52.50, 2.20, 13.9, 1.631],
		[27, 53.50, 2.20, 13.9, 1.750],
		[28, 54.50, 2.20, 14.2, 1.799],
		[29, 55.00, 2.60, 14.2, 1.837],
		[30, 56.00, 2.60, 14.2, 1.881],
		[31, 57.00, 2.60, 14.2, 1.921],
		[34, 56.70, 2.00, 14.2, 1.999],
		[35, 57.00, 2.60, 14.2, 2.026],
		[38, 56.50, 1.90, 15.0, 2.090],
		[39, 56.50, 2.50, 15.0, 2.111],
		[42, 56.30, 1.90, 15.0, 2.167],
		[45, 56.00, 1.60, 15.0, 2.219],
		[47, 56.50, 1.60, 15.0, 2.256],
		[50, 56.80, 1.90, 15.0, 2.309],
		[53, 56.20, 2.20, 15.0, 2.361],
		[56, 56.80, 1.90, 15.0, 2.414],
		[59, 56.90, 1.90, 15.0, 2.468],
		[60, 55.90, 1.60, 15.0, 2.493],
		[61, 54.50, 1.90, 15.0, 2.512],
		[64, 54.50, 1.90, 15.0, 2.563],
		[67, 54.50, 1.90, 15.0, 2.614],
		[70, 54.50, 1.90, 15.0, 2.665],
		[73, 54.50, 1.90, 15.0, 2.716],
		[76, 54.50, 1.90, 15.0, 2.767],
		[79, 54.50, 1.90, 15.0, 2.819],
		[82, 54.50, 1.90, 15.0, 2.870],
		[85, 54.50, 1.90, 15.0, 2.921],
		[88, 54.50, 1.90, 15.0, 2.972],
		[91, 54.50, 1.90, 15.0, 3.023],
		[94, 54.50, 1.90, 15.0, 3.074],
		[97, 54.50, 1.90, 15.0, 3.125],
		[100, 54.50, 1.90, 15.0, 3.176],
		[103, 54.50, 1.90, 15.0, 3.227],
		[106, 54.50, 1.90, 15.0, 3.278],
		[109, 54.50, 1.90, 15.0, 3.329],
		[112, 54.50, 1.90, 15.0, 3.380],
		[115, 54.50, 1.90, 15.0, 3.431],
		[118, 54.50, 1.90, 15.0, 3.483],
		[121, 53.50, 1.90, 15.0, 3.536],
		[122, 53.00, 1.90, 15.0, 3.555],
		[125, 53.00, 1.90, 15.0, 3.605],
		[128, 53.00, 1.90, 15.0, 3.654],
		[131, 52.00, 1.90, 15.0, 3.707],
		[134, 52.00, 1.90, 15.0, 3.756],
		[137, 52.00, 1.90, 15.0, 3.804],
		[140, 52.00, 1.90, 15.0, 3.853],
		[143, 52.00, 1.90, 15.0, 3.902],
		[144, 51.00, 1.90, 15.0, 3.926],
		[145, 50.00, 1.90, 15.0, 3.950],
		[148, 50.00, 1.90, 15.0, 3.996],
		[151, 50.00, 1.90, 15.0, 4.043],
		[154, 50.00, 1.90, 15.0, 4.090],
		[157, 50.00, 1.90, 15.0, 4.137],
		[160, 50.00, 1.90, 15.0, 4.184],
		[163, 50.00, 1.90, 15.0, 4.231],
		[166, 50.00, 1.90, 15.0, 4.278],
		[169, 50.00, 1.90, 15.0, 4.324],
		[172, 50.00, 1.90, 15.0, 4.371],
		[175, 50.00, 1.90, 15.0, 4.418],
		[178, 50.00, 1.90, 15.0, 4.465],
		[181, 50.00, 1.90, 15.0, 4.512],
		[184, 50.00, 1.90, 15.0, 4.559],
		[187, 50.00, 1.90, 15.0, 4.606],
		[190, 50.00, 1.90, 15.0, 4.652],
		[193, 50.00, 1.90, 15.0, 4.699],
		[196, 50.00, 1.90, 15.0, 4.746],
		[199, 50.00, 1.90, 15.0, 4.793],
		[201, 51.00, 1.90, 15.0, 4.829],
		[202, 52.00, 1.90, 15.0, 4.853],
		[205, 52.00, 1.90, 15.0, 4.902],
		[208, 52.00, 1.90, 15.0, 4.951],
		[211, 52.00, 1.90, 15.0, 5.000],
		[214, 52.00, 1.90, 15.0, 5.048],
		[215, 52.00, 2.20, 15.0, 5.065],
		[216, 52.00, 2.60, 15.0, 5.083],
		[219, 52.00, 2.60, 15.0, 5.132],
		[222, 52.00, 2.60, 15.0, 5.181],
		[225, 52.00, 2.60, 15.0, 5.229],
		[228, 52.00, 2.60, 15.0, 5.278],
		[231, 52.00, 2.60, 15.0, 5.327],
		[234, 52.00, 2.60, 15.0, 5.376],
		[237, 52.00, 2.60, 15.0, 5.424],
		[240, 52.00, 2.60, 15.0, 5.473],
		[243, 52.00, 2.60, 15.0, 5.522],
		[246, 52.00, 2.60, 15.0, 5.570],
		[249, 52.00, 2.60, 15.0, 5.619],
		[252, 52.00, 2.60, 15.0, 5.668],
		[255, 52.00, 2.60, 15.0, 5.717],
		[258, 52.00, 2.60, 15.0, 5.765],
		[261, 52.00, 2.60, 15.0, 5.814],
		[264, 52.00, 2.60, 15.0, 5.863],
		[267, 52.00, 2.60, 15.0, 5.912],
		[270, 52.00, 2.60, 15.0, 5.960],
		[271, 52.00, 2.20, 15.0, 5.978],
		[272, 52.00, 1.90, 15.0, 5.995],
		[275, 52.00, 1.90, 15.0, 6.044],
		[278, 52.00, 1.90, 15.0, 6.093],
		[281, 52.00, 1.90, 15.0, 6.141],
		[284, 52.00, 1.90, 15.0, 6.190],
		[287, 52.00, 1.90, 15.0, 6.239],
		[290, 52.00, 1.90, 15.0, 6.288],
		[293, 52.00, 1.90, 15.0, 6.336],
		[296, 52.00, 1.90, 15.0, 6.385],
		[299, 52.00, 1.90, 14.9, 6.436],
		[302, 52.00, 1.90, 14.6, 6.488],
		[305, 52.00, 1.90, 14.0, 6.543],
		[308, 52.00, 1.90, 13.2, 6.602],
		[311, 52.00, 1.90, 12.2, 6.666],
		[314, 52.00, 1.90, 11.0, 6.737],
		[317, 52.00, 1.90, 9.5, 6.815],
		[320, 52.00, 1.90, 7.9, 6.905],
		[323, 52.00, 1.90, 6.3, 7.010],
		[326, 52.00, 1.90, 4.9, 7.138],
		[329, 52.00, 1.90, 4.1, 7.305],
		[332, 52.00, 1.90, 3.3, 7.546],
		[335, 52.00, 1.65, 2.6, 8.000],
	]
	var keys: Array = []
	for leg: Array in route:
		# The look targets on the lap are never read -- look_ahead replaces them
		# -- but a key carries one, so each points down the ring ahead of itself.
		keys.append(_key(
			leg[4], leg[0], leg[1], leg[2], leg[0] + 12.0, leg[1], leg[2], 78.0, leg[3]
		))
	# The stop: hold what it is looking at, then ease round onto the tower.
	keys.append(_key(LAP_SECONDS + 0.4, 335.0, 52.0, EYE, 347.0, 52.0, 1.4, 78.0))
	keys.append(_key(LAP_SECONDS + 1.3, 335.0, 52.0, EYE, 20.0, 26.0, 2.6, 74.0))
	keys.append(_key(LAP_SECONDS + 2.2, 335.0, 52.0, EYE, 0.0, 0.0, 4.0, 68.0))
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
	roll: float = 0.0,
) -> Dictionary:
	return {
		"t": t,
		"pos": ring_point(angle, radius, height),
		"look": ring_point(look_angle, look_radius, look_height),
		"fov": fov,
		"roll": roll,
	}


## A point [param height] metres above the deck, [param radius] out at
## [param angle_degrees] about the arena axis.
static func ring_point(angle_degrees: float, radius: float, height: float) -> Vector3:
	var angle: float = deg_to_rad(angle_degrees)
	return Vector3(cos(angle) * radius, DECK_Y + height, sin(angle) * radius)


static func _shot(shot_name: String, keys: Array) -> Dictionary:
	return {"name": shot_name, "duration": float(keys[keys.size() - 1]["t"]), "keys": keys}
