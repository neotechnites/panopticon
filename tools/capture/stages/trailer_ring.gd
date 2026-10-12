extends "res://tools/capture/stages/stage.gd"

## trailer_ring: a pack running the ring the course way, filmed from the deck's outer edge looking in.
## Any map (--map=); tower dead; --pov=runner rides the rearmost. Dials: count, start, rs (radii), pace, cam_r, cam_h, fov, lag, live (1: brains, not lanes).

const SPREAD: Array[float] = [0.0, -1.6, -2.4, -3.9, -5.2]
const RADII: Array[float] = [50.5, 52.6, 49.4, 51.8, 53.4]
const PACE: Array[float] = [0.74, 0.735, 0.745, 0.74, 0.735]
const WEAVE: Array[float] = [0.05, 0.06, 0.04, 0.05, 0.06]
const PERIOD: Array[float] = [1.15, 1.4, 0.95, 1.3, 1.6]

var _pack: Array[PlayerController] = []
var _focus: Vector3 = Vector3.ZERO
var _focus_set: bool = false


## The pack is the whole field: --set=count=3 is three prisoners and the guard.
func bots() -> int:
	return int(option("count", SPREAD.size()))


func tune_rules(rules: MatchRules) -> void:
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	var count: int = mini(int(option("count", SPREAD.size())), SPREAD.size())
	if runners.size() < count:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var start: float = float(option("start", 80.0))
	var rs: PackedStringArray = String(option("rs", "")).split(",", false)
	var live: bool = int(option("live", 0)) == 1
	var pov: bool = String(option("pov", "")) == "runner"
	var ridden: int = count - 1
	for index: int in count:
		var body: PlayerController = runners[index].controller
		var deg: float = start + SPREAD[index]
		var r: float = float(rs[index]) if index < rs.size() else RADII[index]
		if live:
			body.global_position = LIB.ring_point(deg, r, 0.1)
			body.rotation = Vector3(0.0, atan2(-LIB.tangent_at(deg).x, -LIB.tangent_at(deg).z), 0.0)
			if runners[index].profile != null:
				runners[index].profile.track_radius = r
		else:
			# Every body on its own lane, the course way, its own pace and weave: never two ways.
			var lane: Dictionary = {"do": "lane", "to": start + 70.0, "r": r, "speed": PACE[index] * float(option("pace", 1.0)),
				"weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0}
			if pov and index == ridden:
				# Eyes up the lane and on the two ahead of him; never back over the shoulder.
				lane["glances"] = [
					{"t": 0.0, "right": 0.0, "pitch": -2.0},
					{"t": 0.9, "right": -24.0, "pitch": -3.0},
					{"t": 1.35, "right": 3.0, "pitch": -1.5},
					{"t": 2.1, "right": 14.0, "pitch": 1.0},
					{"t": 2.6, "right": -2.0, "pitch": -1.0},
					{"t": 3.6, "right": -10.0, "pitch": -2.0},
					{"t": 4.2, "right": 2.0, "pitch": -1.0},
				]
				lane["strafes"] = [{"t": 0.5, "strafe": 0.1}, {"t": 1.6, "strafe": -0.08}, {"t": 2.8, "strafe": 0.06}]
				lane["speed"] = float(lane["speed"]) * float(option("ridden_pace", 0.99))
			drive(runners[index], [
				{"do": "place", "at": LIB.ring_point(deg, r, 0.1), "face": LIB.tangent_at(deg)},
				{"do": "human", "on": true},
				lane,
				{"do": "hold", "seconds": 60.0},
			], index)
		_pack.append(body)
	stage_body(_pack[ridden] if pov else _pack[0])
	say("trailer_ring: %d %s from %.0f deg" % [count, "live brains" if live else "driven lanes", start])
	return true


func tick(_delta: float) -> void:
	if not OS.has_environment("STAGE_DEBUG") or int(elapsed() * 60.0) % 30 != 0:
		return
	var where: PackedStringArray = []
	for body: PlayerController in _pack:
		if is_instance_valid(body):
			where.append("%.1f/r%.1f/y%.1f" % [LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y])
	say("pack " + " ".join(where))


func lens(delta: float) -> bool:
	if _pack.is_empty() or camera() == null:
		return false
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	for body: PlayerController in _pack:
		if is_instance_valid(body) and LIB.on_deck(body):
			centre += body.global_position
			count += 1
	if count == 0:
		return false
	centre /= float(count)
	if not _focus_set:
		_focus_set = true
		_focus = centre
	_focus = _focus.lerp(centre, 1.0 - exp(-4.0 * delta))
	var deg: float = LIB.bearing_of(_focus) - float(option("lag", 2.0))
	camera().global_position = LIB.ring_point(deg, float(option("cam_r", 56.3)), float(option("cam_h", 2.4)))
	var look: Vector3 = _focus.lerp(Vector3(0.0, LIB.DECK_Y + 6.0, 0.0), 0.45)
	camera().look_at(look, Vector3.UP)
	camera().fov = float(option("fov", 68.0))
	camera().current = true
	return true
