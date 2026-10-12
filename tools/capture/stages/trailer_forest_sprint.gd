extends "res://tools/capture/stages/stage.gd"

## trailer_forest_sprint (v28 h1): the forest POV run, rebuilt. Ryan on v27: "you did nothing about it" ("slow and unfinished").
## Why the old one read slow: the line ran the open middle of the lane, two to four metres off every trunk, so nothing near the lens
## moved; the men ahead were small and far; it opened and closed on open grass. This one is a line a player picks through the
## trees at full run (11 m/s): a trunk whipping past the left edge as it opens, close past the lane trunks, threading the
## two-metre gap between the 32.9 and 34.5 trunks, a wipe past the 39 trunk to close; a man four metres ahead takes the
## same line first, a third on the outside line. --map=res://maps/forest/forest_green.tscn --shot=pack_lead --bots=3 --pov=runner
## Probe (probe_ring --map=forest --heights 0.5 deg x 0.5 m): trunks 14.5-15.5 r 49.5-50.5, 20-21.5 r 47-50.5, 25.5-27 r 49.5-50.5,
## 32.5-33.5 r 51.5-54.5, 34-35 r 47.5-49, 38.5-40 r 53.5-55, 46.5-48 r 49.5-52, 53.5-54.5 r 53.5-54.5; outer 15-17, 24.5-29 r 56+.

const HUMAN_RUN := preload("res://tools/capture/stages/human_run.gd")

## The thread: radii by bearing, each leg run to its bearing (the lane steers five degrees ahead, so each change is a curve).
const THREAD: Array = [
	{"to": 12.0, "r": 51.4},
	{"to": 17.5, "r": 51.2},   # past the 14.96 trunk, 0.7 m off its edge
	{"to": 23.5, "r": 51.3},   # past the 20.7 trunk
	{"to": 29.0, "r": 51.2},   # past the 26.1 trunk
	{"to": 35.5, "r": 50.25},  # through the gap: 32.9 trunk to the right (r 51.5), 34.5 trunk to the left (r 49.0)
	{"to": 42.0, "r": 52.4},   # out of it and past the 39.2 trunk on the right
	{"to": 50.0, "r": 53.0},   # outside the 47 trunk
	{"to": 80.0, "r": 52.6},
]
## The POV's eyes lead each turn by a few degrees, as a player's do; slightly down, on the line.
const POV_EYES: Array = [
	[{"t": 0.0, "right": 2.0, "pitch": -4.0}],
	[{"t": 0.0, "right": -3.0, "pitch": -4.0}],
	[{"t": 0.0, "right": 2.0, "pitch": -3.0}],
	[{"t": 0.0, "right": -2.0, "pitch": -4.0}, {"t": 0.3, "right": -6.0, "pitch": -4.0}],
	[{"t": 0.0, "right": -3.0, "pitch": -5.0}, {"t": 0.35, "right": 6.0, "pitch": -4.0}],
	[{"t": 0.0, "right": 5.0, "pitch": -3.0}, {"t": 0.4, "right": 1.0, "pitch": -3.0}],
	[{"t": 0.0, "right": -2.0, "pitch": -3.0}],
	[{"t": 0.0, "right": 0.0, "pitch": -3.0}],
]
## The outside man: wide of the outer trunks, a stride ahead of the POV.
const OUTSIDE: Array = [
	{"to": 31.0, "r": 55.2},
	{"to": 36.0, "r": 55.3},
	{"to": 80.0, "r": 55.4},
]
## Start bearings: the POV, the man ahead on his line, the outside man.
const STARTS: Array[float] = [2.5, 5.3, 6.4]
const START_R: Array[float] = [51.4, 51.4, 55.2]
## v34 (Ryan: "a section of the forest with more foliage in frame"), --set=zone=2: the 57-95 stretch, trunks every 6 deg both sides, the
## lip bushes at 64/71/82 and the outer bushes; probe --heights: IN 61-62 r 49-52, 67.5-68.5 r 49.5-50.5, 91.5-93.5 r 47-50.5; OUT 74.5-76
## r 53.5-54.5, 80.5-82 r 53-54.5, 85-86.5 r 53-56.5. The outer verge is trunk-thick, so the third man runs the thread too, a step behind.
const THREAD2: Array = [
	{"to": 60.0, "r": 52.7},
	{"to": 64.0, "r": 52.7},   # 0.7 m off the 61.5 trunk
	{"to": 70.5, "r": 51.3},   # 0.8 m off the 68 trunk
	{"to": 77.0, "r": 52.6},   # 0.9 m inside the 75 trunk
	{"to": 83.0, "r": 52.3},   # past the 81 trunk
	{"to": 88.5, "r": 52.2},   # past the 85.5 trunk
	{"to": 120.0, "r": 51.6},
]
const STARTS2: Array[float] = [54.0, 56.8, 58.4]
const START_R2: Array[float] = [52.6, 52.6, 52.7]

var _bodies: Array[PlayerController] = []


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
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
	var zone2: bool = int(option("zone", 1)) == 2
	var thread: Array = THREAD2 if zone2 else THREAD
	var starts: Array[float] = STARTS2 if zone2 else STARTS
	var start_r: Array[float] = START_R2 if zone2 else START_R
	for index: int in 3:
		var legs: Array = []
		if index == 2 and not zone2:
			for leg: Dictionary in OUTSIDE:
				legs.append({"to": leg["to"], "r": leg["r"], "speed": 1.0, "glances": [{"t": 0.0, "right": -3.0, "pitch": -2.0}]})
		else:
			for k: int in thread.size():
				var leg: Dictionary = thread[k]
				var eyes: Array = POV_EYES[mini(k, POV_EYES.size() - 1)] if index == 0 else [{"t": 0.0, "right": 0.0, "pitch": -2.0}]
				legs.append({"to": leg["to"], "r": leg["r"], "speed": 1.0, "glances": eyes})
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(starts[index], start_r[index], 0.1), "face": LIB.tangent_at(starts[index])},
			{"do": "human", "on": true},
		]
		steps.append_array(HUMAN_RUN.steps(legs))
		steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[index], steps, index, "ClipSprint%d" % index)
		LIB.hide_from_the_rifle(runners[index].controller)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[0])
	say("trailer_forest_sprint: %s threads the trees behind %s, %s outside" % [_bodies[0].name, _bodies[1].name, _bodies[2].name])
	return true


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and not _bodies.is_empty() and Engine.get_physics_frames() % 6 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f v%.1f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), Vector2(body.velocity.x, body.velocity.z).length()]
		say("at" + line)


func lens(_delta: float) -> bool:
	return false
