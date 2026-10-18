extends "res://tools/capture/stages/stage.gd"

## forest_race: short 9 line L4, Ryan: "so, i implemented a race, every player does the course with no sniper, and the
## first one to complete it gets to be the sniper. this, was the worst part of my game. it wasnt fun, everyone was the
## same speed, and it took to long" {pov of race in forest}. The game's own opening race (start_race), bot brains run it.
## [code]--stage=forest_race --shot=s3_open_lane --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261017 --frame=810x1440 --seconds=22[/code]
## run_clip opens a round in stage mode; the first tick re-arms the race. Four bodies, all racers, seat none all race.
## The three others run on their own race brains; the ridden racer runs stage_driver lanes along their measured line.
## Mac smoke (seed 20261017): race_start 0.02, lap ~28.6 s (race_won at 28.63 on a 34 s run, past the cut). The ride holds
## 4 deg behind the nearest racer ahead: 3rd at 6-9 s, then last 2-4 m behind two, the leader 10-14 deg up the course.
## Window 1.0-20.5 s: near 0.21 m and cover 0.52 at worst, longest runs 0.08 s / 0.03 s (limit 0.1 s).
## The legs at 92.6 / 98.2 deg sit 0.3-0.6 m outside the brain's line: on it the lens grazed something at 94 deg.
## Dials (--set=): ride (3, roster index of the racer ridden), pace (1.0), gap (4.0, deg kept behind the racer ahead), gain (0.08),
## slow (0.75, the slowest pace factor), aside (0.0, m stepped off a shoulder inside reach), reach (3.0), r_min (50.3),
## r_max (53.0), log_every (1.0).

## Roster index of the racer ridden (Runner_3).
const RIDE: int = 3
## Legs of the bots' line (Runner_3's brain run, every 0.5 s): to deg, r, a jump at deg (0: none).
const LINE: Array = [
	Vector3(9.5, 53.5, 0.0), Vector3(14.2, 53.8, 0.0), Vector3(20.0, 53.2, 0.0), Vector3(26.0, 52.4, 0.0), Vector3(32.2, 51.5, 0.0), Vector3(37.7, 51.8, 0.0),
	Vector3(43.6, 51.9, 0.0), Vector3(49.2, 52.5, 0.0), Vector3(55.5, 51.9, 50.5), Vector3(60.5, 51.9, 0.0), Vector3(66.7, 51.3, 0.0), Vector3(73.0, 50.6, 0.0),
	Vector3(79.6, 50.2, 0.0), Vector3(86.2, 50.6, 0.0), Vector3(92.6, 52.3, 0.0), Vector3(98.2, 52.2, 0.0), Vector3(104.1, 51.4, 0.0), Vector3(110.2, 51.0, 0.0),
	Vector3(116.4, 51.1, 0.0), Vector3(122.3, 51.6, 0.0), Vector3(128.2, 51.6, 0.0), Vector3(134.2, 51.7, 0.0), Vector3(140.0, 51.0, 0.0), Vector3(146.0, 50.5, 0.0),
	Vector3(152.2, 50.7, 0.0), Vector3(158.3, 51.3, 0.0), Vector3(164.0, 52.1, 0.0), Vector3(169.7, 51.3, 0.0), Vector3(175.8, 51.0, 0.0), Vector3(181.9, 51.3, 0.0),
	Vector3(187.7, 51.7, 0.0), Vector3(194.1, 51.3, 0.0), Vector3(200.5, 51.4, 0.0), Vector3(206.7, 51.0, 0.0), Vector3(213.2, 51.0, 0.0), Vector3(219.7, 51.6, 0.0),
	Vector3(225.7, 52.0, 0.0), Vector3(232.0, 51.2, 0.0), Vector3(238.5, 51.2, 0.0), Vector3(244.9, 51.7, 0.0), Vector3(251.1, 52.0, 0.0), Vector3(257.4, 51.8, 0.0),
	Vector3(300.0, 51.6, 0.0), Vector3(355.0, 51.6, 0.0),
]
## Eyes up the course and onto the man ahead; the schedule restarts each leg.
const GLANCES: Array = [{"t": 0.0, "right": 3.0, "pitch": -1.5}, {"t": 1.4, "right": -5.0, "pitch": 0.5},
	{"t": 2.9, "right": 6.0, "pitch": -1.0}, {"t": 4.3, "right": 1.0, "pitch": -2.0}]

var _started: bool = false
var _pov: PlayerController = null
var _next_log: float = 0.0
var _won: bool = false
var _ride: Node = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.open_with_race = true
	rules.open_with_tower_brawl = false
	rules.runner_ability = MatchRules.RunnerAbility.NONE


func tick(_delta: float) -> void:
	var match_controller: MatchController = controller()
	if not _started:
		_started = true
		match_controller.race_started.connect(func() -> void: _event("race_start  %d" % match_controller.get_participants().size()))
		match_controller.seat_changed.connect(_on_seat)
		match_controller.participant_converted.connect(func(p: MatchParticipant) -> void: _event("out  %s" % p.body.name))
		match_controller.start_race()
		var racers: Array[MatchParticipant] = match_controller.get_participants()
		_pov = racers[clampi(int(option("ride", RIDE)), 0, racers.size() - 1)].body
		if _pov != null:
			_drive_the_ride(match_controller)
			stage_body(_pov)
		say("forest_race: %d racers, POV %s" % [match_controller.get_participants().size(), _pov.name if _pov != null else "none"])
	if _pov != null:
		_keep_place()
	if elapsed() < _next_log:
		return
	_next_log = elapsed() + float(option("log_every", 1.0))
	var seat_holder: MatchParticipant = match_controller.get_seat_participant()
	var line: String = "phase %s seat %s" % [match_controller.get_phase_name(), seat_holder.body.name if seat_holder != null else "none"]
	for p: MatchParticipant in match_controller.get_participants():
		if p.body == null:
			continue
		var progress: float = p.tracker.get_progress() if p.tracker != null else -1.0
		line += " | %s%s %.1f deg r %.1f y %.1f p %.3f%s" % ["*" if p.body == _pov else "", p.body.name, LIB.bearing_of(p.body.global_position),
			LIB.radius_of(p.body.global_position), p.body.global_position.y, progress, " SHOOTER" if p.is_shooter else ""]
	print("[race] %6.2f  %s" % [elapsed(), line])


## The ridden racer runs the bots' own line (brain smoke, seed 20261017) at full pace, eyes on the course.
func _drive_the_ride(match_controller: MatchController) -> void:
	var brain: RunnerBrain = null
	for p: MatchParticipant in match_controller.get_participants():
		if p.body == _pov:
			brain = p.brain
	if brain == null:
		return
	var steps: Array = [{"do": "human", "on": true}, {"do": "steer", "on": true, "rate": 260.0, "gain": 9.0}]
	for index: int in LINE.size():
		var leg: Vector3 = LINE[index]
		var lane: Dictionary = {"do": "lane", "to": leg.x, "r": leg.y + float(option("wide", 0.0)), "dir": 1, "speed": float(option("pace", 1.0)),
			"weave": 0.03, "period": 1.2 + 0.1 * index, "timeout": 30.0, "carry": index > 0, "glances": GLANCES}
		if leg.z > 0.0:
			lane["jumps"] = [leg.z]
		steps.append(lane)
	steps.append({"do": "hold", "seconds": 60.0, "fidget": true})
	_ride = drive(brain, steps, 0, "ClipRaceRide")


## A player keeping his place: pace eased to hold gap deg behind the racer ahead, a step aside off a shoulder in reach.
func _keep_place() -> void:
	if _ride == null or not is_instance_valid(_ride) or _ride.is_done():
		return
	var mine: float = LIB.bearing_of(_pov.global_position)
	var my_r: float = LIB.radius_of(_pov.global_position)
	var gap: float = 999.0
	var close: float = 999.0
	var side: float = 0.0
	for p: MatchParticipant in controller().get_participants():
		if p.body == null or p.body == _pov or not p.is_running:
			continue
		var ahead: float = fposmod(LIB.bearing_of(p.body.global_position) - mine, 360.0)
		if ahead < 90.0:
			gap = minf(gap, ahead)
		var metres: float = p.body.global_position.distance_to(_pov.global_position)
		if metres < close:
			close = metres
			side = signf(my_r - LIB.radius_of(p.body.global_position))
	var pace: float = float(option("pace", 1.0))
	if gap < 90.0:
		pace *= clampf(1.0 + float(option("gain", 0.08)) * (gap - float(option("gap", 4.0))), float(option("slow", 0.75)), 1.06)
	var steps: Array = _ride.get("_steps")
	var index: int = int(_ride.get("_index"))
	var step: Dictionary = steps[index]
	if String(step.get("do", "")) != "lane":
		return
	step["speed"] = pace
	var line_r: float = LINE[clampi(index - 2, 0, LINE.size() - 1)].y
	var aside: float = float(option("aside", 0.0)) * (side if side != 0.0 else 1.0) if close < float(option("reach", 3.0)) else 0.0
	step["r"] = clampf(line_r + aside, float(option("r_min", 50.3)), float(option("r_max", 53.0)))


## First past the post takes the tower; later seat changes are rounds, not the race.
func _on_seat(p: MatchParticipant, _turns: int) -> void:
	if not _won:
		_won = true
		_event("race_won  %s" % p.body.name)


func _event(message: String) -> void:
	print("[event] %6.2f  %s" % [elapsed(), message])
