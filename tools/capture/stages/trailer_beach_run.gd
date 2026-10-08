extends "res://tools/capture/stages/stage.gd"

## trailer_beach_run (v36 beach run): h1's POV run on the beach sand (waterline r 63.5, lane 68.5, wall 74.1), the shore on
## the right, a man a stride ahead on the same line and a third wide. --map=beach --shot=pack_lead --bots=3 --pov=runner

const HUMAN_RUN := preload("res://tools/capture/stages/human_run.gd")

## The line: radii by bearing on the sand, gently in toward the water and out again.
const LINE: Array = [
	{"to": 100.0, "r": 67.2},
	{"to": 108.0, "r": 66.6},
	{"to": 116.0, "r": 67.0},
	{"to": 124.0, "r": 66.4},
	{"to": 170.0, "r": 66.8},
]
const POV_EYES: Array = [
	[{"t": 0.0, "right": 2.0, "pitch": -4.0}],
	[{"t": 0.0, "right": 5.0, "pitch": -4.0}, {"t": 0.4, "right": 1.0, "pitch": -3.0}],
	[{"t": 0.0, "right": -2.0, "pitch": -4.0}],
	[{"t": 0.0, "right": 3.0, "pitch": -3.0}],
	[{"t": 0.0, "right": 0.0, "pitch": -3.0}],
]
const WIDE: Array = [{"to": 170.0, "r": 69.4}]
## Start bearings and radii: the POV, the man ahead, the wide man.
const STARTS: Array[float] = [92.0, 94.8, 96.0]
const START_R: Array[float] = [67.2, 67.2, 69.4]

var _bodies: Array[PlayerController] = []


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"beach"
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	var shooter_seat: Node = seat()
	if shooter_seat != null:
		LIB.stand_down(shooter_seat)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	for index: int in 3:
		var legs: Array = []
		var line: Array = WIDE if index == 2 else LINE
		for k: int in line.size():
			var eyes: Array = POV_EYES[mini(k, POV_EYES.size() - 1)] if index == 0 else [{"t": 0.0, "right": 0.0, "pitch": -2.0}]
			legs.append({"to": line[k]["to"], "r": line[k]["r"], "speed": 1.0, "glances": eyes})
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(STARTS[index], START_R[index], 0.1), "face": LIB.tangent_at(STARTS[index])},
			{"do": "human", "on": true},
		]
		steps.append_array(HUMAN_RUN.steps(legs))
		steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[index], steps, index, "ClipSprint%d" % index)
		LIB.hide_from_the_rifle(runners[index].controller)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[0])
	say("trailer_beach_run: %s on the sand behind %s, %s wide" % [_bodies[0].name, _bodies[1].name, _bodies[2].name])
	return true


func tick(_delta: float) -> void:
	if not _bodies.is_empty() and Engine.get_physics_frames() % 30 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)


func lens(_delta: float) -> bool:
	return false
