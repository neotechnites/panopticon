extends "res://tools/capture/stages/stage.gd"

## conga: the edge conga (f09_edge_conga, "legitimately perfect"). Filmed with
## [code]--shot=rim_side --bots=7 --seconds=18[/code], cut from 1.633 s in for
## 15 s so the first shove lands at 7.00 s of the clip, on the word "sabotage".
##
## Ryan: "have a shot of a guy facing the pit, we see him from the side. then,
## slowly, another bot crouches behind him and approaches. then, when i say
## the word sabotage, he shoves him off the edge. then, have bots keep coming
## up from behind, and shoving the bot currently at the edge off".
##
## Timed beats: every shove is on the driver's own clock ("until" steps), so
## the beat is a number in this file, not a thing that happens when a chase
## arrives. The driver clock starts when the stage casts (0.62 s into the
## take); a clip cut IN seconds in sees a beat at (beat + 0.62 - IN).
##
## Dials (--set=): deg (the rim spot, 182), first (driver seconds of the first
## shove, 8.0), every (seconds between shoves, 1.4), impulse (the shove, 3.4).
##
## Why the numbers: the shipped 16 m/s throw crosses a 4.6 m-wide portrait frame
## in a tenth of a second and the fall happens 5 m out of shot; 3.4 m/s with
## the shipped 7 m/s lift goes up ~1.1 m, clears the rim, hits the pit wall at
## r ~46.1 and slides down it in frame. A body thrown 37 deg off the radial
## lands on the lip and lives, so every shover is turned square to the rim
## before it swings. Ghosts are off: the dead come back on the start line at
## three times pace and the first would reach the rim before the last shove.
## The creeper's walk is under the movement profile's friction floor, so it
## gets a private profile ("slowfeet") that lets it creep at 0.6 m/s.

const RIM_R: float = 47.3
const CREEP_FROM_R: float = 51.6
const CREEP_TO_R: float = 48.7
const SHOVE_R: float = 48.6
const WAIT_R: float = 54.0
const RUN_IN_SECONDS: float = 1.5


func bots() -> int:
	return 7


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 3.4))
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	say("%d pads disarmed" % LIB.disarm_pads(clip.root))


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var deg: float = float(option("deg", 182.0))
	var first: float = float(option("first", 8.0))
	var every: float = float(option("every", 1.4))
	var inward: Vector3 = -LIB.radial_at(deg)
	# 0: on the rim, facing the pit, alone.
	drive(runners[0], [
		{"do": "place", "at": LIB.ring_point(deg, RIM_R, 0.1), "face": inward},
		{"do": "hold", "seconds": 60.0},
	], 0)
	stage_body(runners[0].controller)
	victim_body(runners[0].controller)
	# 1: creeps in crouched from outside the lens, rises, and shoves on the word.
	drive(runners[1], [
		{"do": "place", "at": LIB.ring_point(deg, CREEP_FROM_R, 0.1), "face": inward},
		{"do": "slowfeet", "floor": 0.5},
		{"do": "until", "t": 0.9},
		{"do": "run", "to": LIB.ring_point(deg, CREEP_TO_R, 0.0), "within": 0.3, "speed": 0.08, "crouch": true, "timeout": first - 1.6},
		{"do": "until", "t": first - 1.35, "crouch": true},
		{"do": "until", "t": first},
		{"do": "shove", "face": inward},
		{"do": "run", "to": LIB.ring_point(deg, RIM_R, 0.0), "within": 0.25, "speed": 0.4, "timeout": 2.0},
		{"do": "hold", "seconds": 60.0},
	], 1)
	# 2..: wait out of frame along the ring, run in at half speed on their
	# beat, square up to the rim, shove, and take the rim.
	for index: int in range(2, runners.size()):
		var beat: float = first + every * float(index - 1)
		var wait_deg: float = deg + 1.2 * float(index - 1)
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(wait_deg, WAIT_R, 0.1), "face": inward},
			{"do": "until", "t": beat - RUN_IN_SECONDS},
			{"do": "run", "to": LIB.ring_point(deg, SHOVE_R, 0.0), "within": 0.3, "speed": 0.5, "timeout": RUN_IN_SECONDS + 0.5},
			{"do": "until", "t": beat},
			{"do": "shove", "face": inward},
			{"do": "run", "to": LIB.ring_point(deg, RIM_R, 0.0), "within": 0.25, "speed": 0.4, "timeout": 2.0},
			{"do": "hold", "seconds": 60.0},
		], index)
	say("conga at %.1f deg: %d runners, first shove at %.2f s of the take, then every %.1f s" % [deg, runners.size(), first + elapsed(), every])
	return true
