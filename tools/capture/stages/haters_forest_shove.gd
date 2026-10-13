extends "res://tools/capture/stages/stage.gd"

## haters_forest_shove: three runners on the forest lane, the POV shoves the pit-side one over the lip. Built like
## trailer_duel2: probed numbers here, each runner a list of stage_driver steps, every number a dial, POV only, one seed.
## Probe (head, probe_ring --floor/--aabb/--los, forest): lane band r 48.0-51.0 clear of every obstacle 70-94 deg (21 m);
## trees sit outside it both sides. Pit lip r 46-48 clean 74-86 deg bar BushLow_082 (82.1 r 47.5, 2.7 m: 80.8-83.4)
## and BushLow_071 (71.0): shove at 85.0-86.0 or 77-79. Tower eye (0, 28.9, 0) sees r 50 h 1.4 at 80 and 84 deg
## (canopy at 76 and 88). Deck y 23.0; the pit is below y 22.
## Dials: go/go_victim/go_extra (driver seconds the feet start), pov_at, victim_at, extra_at ("deg,r"), lane_mid, lane_r, lane_to,
## victim_to, extra_to, victim_speed, range, watch, impulse, up, tail. Mac smoke (seed 20261012): chase from 80 deg so the
## head turns onto him as it closes (from 86 the shove whiffed); impulse 16 left him on the slope at r 44.8, 24 drops him.

const POV_AT: String = "70.0,49.6"
const VICTIM_AT: String = "71.5,48.3"
const EXTRA_AT: String = "74.0,50.7"
const RIM_Y: float = 22.0

var _pov: PlayerController = null
var _victim: PlayerController = null
var _pov_driver: Node = null
var _victim_driver: Node = null
## The victim's hold step: on the shove his feet leave the lane (a player thrown, not one steering back to it).
const VICTIM_HOLD: int = 5
var _go_at: float = -1.0
var _shove_at: float = -1.0
var _airborne_at: float = -1.0
var _below_at: float = -1.0
var _ended: bool = false
var _last_yaw: float = 0.0
var _max_yaw: float = 0.0


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 24.0))
	rules.shove_up_impulse = float(option("up", rules.shove_up_impulse))


func _at(key: String, fallback: String) -> Vector2:
	var parts: PackedStringArray = String(option(key, fallback)).split(",")
	return Vector2(float(parts[0]), float(parts[1]))


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	_pov = runners[0].controller
	_victim = runners[1].controller
	var pov_at: Vector2 = _at("pov_at", POV_AT)
	var victim_at: Vector2 = _at("victim_at", VICTIM_AT)
	var extra_at: Vector2 = _at("extra_at", EXTRA_AT)

	var pov_steps: Array = [
		{"do": "place", "deg": pov_at.x, "r": pov_at.y, "h": 0.1, "face": LIB.tangent_at(pov_at.x)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 200.0, "gain": 8.0},
		{"do": "until", "t": float(option("go", 0.6))},
		{"do": "lane", "to": float(option("lane_to", 80.0)), "r": float(option("lane_r", pov_at.y)), "dir": 1, "speed": 1.0,
			"weave": 0.03, "period": 1.2, "timeout": 8.0, "carry": true,
			"glances": [{"t": 0.7, "right": -18.0, "pitch": 3.0}, {"t": 1.8, "right": 6.0, "pitch": -1.0}]},
		{"do": "chase", "victim": _victim, "range": float(option("range", 1.2)), "timeout": 2.0, "speed": 1.0},
		{"do": "watch", "body": _victim, "seconds": float(option("watch", 1.0)), "height": 0.8},
		{"do": "hold", "seconds": 0.5},
		{"do": "hold", "seconds": 60.0},
	]
	# lane_mid (a longer run-up): hold pov r to that bearing, then lane in to lane_r (row 68's obstacle sits at r 48.5-50.0).
	if String(option("lane_mid", "")) != "":
		pov_steps.insert(4, {"do": "lane", "to": float(option("lane_mid", 69.0)), "r": pov_at.y, "dir": 1, "speed": 1.0,
			"weave": 0.03, "period": 1.2, "timeout": 8.0, "carry": true, "glances": [{"t": 0.0, "right": 0.0, "pitch": 0.0}]})
	_pov_driver = drive(runners[0], pov_steps, 0, "ClipShoverDriver")

	_victim_driver = drive(runners[1], [
		{"do": "place", "deg": victim_at.x, "r": victim_at.y, "h": 0.1, "face": LIB.tangent_at(victim_at.x)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 200.0, "gain": 8.0},
		{"do": "until", "t": float(option("go_victim", 0.55))},
		{"do": "lane", "to": float(option("victim_to", 92.0)), "r": victim_at.y, "dir": 1,
			"speed": float(option("victim_speed", 0.88)), "weave": 0.03, "period": 1.3, "timeout": 8.0},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipVictimDriver")

	drive(runners[2], [
		{"do": "place", "deg": extra_at.x, "r": extra_at.y, "h": 0.1, "face": LIB.tangent_at(extra_at.x)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 200.0, "gain": 8.0},
		{"do": "until", "t": float(option("go_extra", 0.45))},
		{"do": "lane", "to": float(option("extra_to", 96.0)), "r": extra_at.y, "dir": 1, "speed": 1.0,
			"weave": 0.03, "period": 1.4, "timeout": 8.0},
		{"do": "hold", "seconds": 60.0},
	], 2, "ClipExtraDriver")

	stage_body(_pov)
	victim_body(_victim)
	say("haters_forest_shove: %s shoves %s; %s runs on" % [_pov.name, _victim.name, runners[2].controller.name])
	return true


## Game lighting: nothing on the lights; pads and traps off so only the shove moves anyone.
func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func tick(delta: float) -> void:
	if _pov == null or _ended or not is_instance_valid(_pov) or not is_instance_valid(_victim):
		return
	var yaw: float = rad_to_deg(_pov.rotation.y)
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		say("pov %.1f deg r %.2f  victim %.1f deg r %.2f y %.2f" % [LIB.bearing_of(_pov.global_position), LIB.radius_of(_pov.global_position),
			LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.y])
	if _go_at < 0.0 and _pov_driver != null and int(_pov_driver.get("_index")) >= 4:
		_go_at = elapsed()
		_event("go  %s" % _pov.name)
	elif _go_at >= 0.0 and delta > 0.0:
		_max_yaw = maxf(_max_yaw, absf(wrapf(yaw - _last_yaw, -180.0, 180.0)) / delta)
	_last_yaw = yaw
	if _shove_at < 0.0:
		return
	if _airborne_at < 0.0 and not _victim.is_on_floor():
		_airborne_at = elapsed()
		_event("airborne  %s" % _victim.name)
	if _below_at < 0.0 and _victim.global_position.y < RIM_Y:
		_below_at = elapsed()
		_event("below_rim  %s  at %.1f deg r %.1f" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])
	if _below_at >= 0.0 and elapsed() >= _below_at + float(option("tail", 0.7)):
		_ended = true
		_event("max_yaw  %.0f" % _max_yaw)
		_event("end")
		flag_all("end")


func on_shove(shover: MatchParticipant, victim: MatchParticipant) -> void:
	if _shove_at < 0.0 and shover.body == _pov and victim.body == _victim:
		_shove_at = elapsed()
		if _victim_driver != null and int(_victim_driver.get("_index")) < VICTIM_HOLD:
			_victim_driver.set("_index", VICTIM_HOLD)
			_victim_driver.set("_clock", 0.0)


func lens(_delta: float) -> bool:
	return false


func _event(message: String) -> void:
	print("[event] %6.2f  %s" % [elapsed(), message])
