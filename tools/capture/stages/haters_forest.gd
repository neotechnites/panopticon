extends "res://tools/capture/stages/stage.gd"

## haters_forest: ONE camera, the shover's eyes. Ryan: "a shot of runners in a forest and a
## shove off the edge". Three runners on the forest lane (guard: four players); the POV
## shoves the runner beside him into the ravine at ~4.5 s and watches him fall. Nobody is
## shot (the tower watches, never fires), so the ridden body never changes.
##
## [code]--stage=haters_forest --shot=s3_open_lane --map=forest --pov=runner --bots=3 --seconds=7 --seed=20261012[/code]
##
## Ground from haters.gd's probe (forest_green, deck r 45.5-56): the victim runs r 49.25
## from 321.5, the shover r 51.5 from 320; the shove lands at ~335 deg between the lip
## boulders at 330.3-333.4 and 338.3-341.3. Dials (--set=): pace (1.0), impulse (18), up (6).

const SHOVER_AT := Vector2(281.0, 51.0)
const VICTIM_AT := Vector2(284.0, 48.75)
const LEAD_AT := Vector2(278.0, 52.5)

var _shover: PlayerController = null
var _victim: PlayerController = null
var _lead: PlayerController = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 18.0))
	rules.shove_up_impulse = float(option("up", 6.0))


func tune_shooter(profile: ShooterProfile) -> void:
	LIB.dead_shooter(profile)


func _legs(legs: Array, pace: float, weave: float) -> Array:
	var out: Array = []
	for leg: Array in legs:
		out.append({"do": "lane", "to": float(leg[0]), "r": float(leg[1]), "speed": pace,
			"weave": weave, "period": 1.3, "timeout": 30.0})
	return out


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var pace: float = float(option("pace", 1.0))
	_shover = runners[0].controller
	_victim = runners[1].controller
	_lead = runners[2].controller

	var shover_steps: Array = [
		{"do": "place", "at": LIB.ring_point(SHOVER_AT.x, SHOVER_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	var glances: Array = [
		{"t": 0.0, "right": 0.0, "pitch": -1.0},
		{"t": 0.9, "right": 12.0, "pitch": -2.0},
		{"t": 1.6, "right": -6.0, "pitch": -1.0},
		{"t": 2.4, "right": 18.0, "pitch": 1.0},
		{"t": 3.0, "right": 4.0, "pitch": -1.0},
	]
	var legs: Array = _legs([[287.0, 53.0], [295.0, 51.5], [301.0, 51.5], [306.0, 53.0], [316.0, 52.0],
		[322.0, 50.8], [334.0, 50.8]], pace, 0.04)
	for leg: Dictionary in legs:
		leg["glances"] = glances
	shover_steps.append_array(legs)
	shover_steps.append_array([
		# Eased onto him through the mouse: an unsteered chase snaps the view round (reads as a cut).
		{"do": "steer", "on": true, "rate": 220.0, "gain": 7.0},
		{"do": "chase", "victim": _victim, "range": 2.6, "timeout": 2.5, "speed": 1.0},
		{"do": "glance", "right": 15.0, "pitch": 26.0, "seconds": 0.3},    # watch him go over
		{"do": "hold", "seconds": 60.0},
	])
	drive(runners[0], shover_steps, 0, "ClipShoverDriver")

	var victim_steps: Array = [
		{"do": "place", "at": LIB.ring_point(VICTIM_AT.x, VICTIM_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	victim_steps.append_array(_legs([[290.0, 48.75], [300.0, 51.5], [306.0, 52.75], [316.0, 51.5],
		[322.0, 50.5], [345.0, 48.75]], pace, 0.04))
	victim_steps.append({"do": "hold", "seconds": 60.0})
	drive(runners[1], victim_steps, 1, "ClipVictimDriver")

	var lead_steps: Array = [
		{"do": "place", "at": LIB.ring_point(LEAD_AT.x, LEAD_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	lead_steps.append_array(_legs([[345.0, LEAD_AT.y]], pace, 0.06))
	lead_steps.append({"do": "hold", "seconds": 60.0})
	drive(runners[2], lead_steps, 2, "ClipLeadDriver")

	stage_body(_shover)
	victim_body(_victim)
	say("haters_forest: %s shoves, %s is the victim, %s leads" % [_shover.name, _victim.name, _lead.name])
	return true


func on_shove(shover: MatchParticipant, victim: MatchParticipant) -> void:
	if victim.body == null:
		return
	say("shove: %s -> %s at %.1f deg r %.1f" % [shover.body.name if shover.body else "?", victim.body.name,
		LIB.bearing_of(victim.body.global_position), LIB.radius_of(victim.body.global_position)])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s" % (participant.body.name if participant.body else "?"))
