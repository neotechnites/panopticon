extends "res://tools/capture/stages/stage.gd"

## forest_run: L7 of portal_spin, down a runner's eyes on the forest's clear corridor (r 51.6-52.4, bearing 5-60:
## trailer_forest_pack's probe; lane trunks at r 49.9 and r 53.8). Three run it, the POV last. --map=forest --pov=runner.

const STARTS: Array[float] = [12.0, 9.0, 5.5]
const RADII: Array[float] = [52.2, 51.8, 52.0]
const PACE: Array[float] = [0.72, 0.70, 0.705]
const PERIOD: Array[float] = [1.2, 1.45, 1.0]


func bots() -> int:
	return 3


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for i: int in 3:
		if runners[i].controller == null:
			return false
	for i: int in 3:
		var lane: Dictionary = {"do": "lane", "to": 62.0, "r": RADII[i], "speed": PACE[i], "weave": 0.03,
			"period": PERIOD[i], "timeout": 30.0}
		var steps: Array = [{"do": "place", "at": LIB.ring_point(STARTS[i], RADII[i], 0.1)}]
		if i == 2:
			lane["weave"] = 0.0
			lane["glances"] = [
				{"t": 0.0, "right": 0.0, "pitch": -1.0},
				{"t": 0.9, "right": -18.0, "pitch": 4.0},
				{"t": 1.5, "right": 2.0, "pitch": -1.0},
				{"t": 2.6, "right": 14.0, "pitch": -2.0},
				{"t": 3.3, "right": 0.0, "pitch": -1.0},
			]
			steps.append({"do": "human", "on": true})
			stage_body(runners[i].controller)
		steps.append(lane)
		steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[i], steps, i)
	say("three on the corridor")
	return true
