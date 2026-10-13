extends "res://tools/capture/stages/stage.gd"

## haters_forest_edge: haters_forest on the clean edge at 341-344.5 deg (probe: no lip or boulder, deck flat
## to r47, sheer past r45). Lane r48.5-52 trunk-free 326-350 bar the portal slab at 345 r50.5-53.3.

const SHOVER_AT := Vector2(326.5, 50.0)
const VICTIM_AT := Vector2(330.0, 49.3)
const LEAD_AT := Vector2(331.5, 51.3)

var _shover: PlayerController = null
var _victim: PlayerController = null
var _lead: PlayerController = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 32.0))
	rules.shove_up_impulse = float(option("up", 7.0))


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

	# Steered from the first step: every turn is eased through the mouse, so the lens never snaps (v6 jumped at each leg).
	var shover_steps: Array = [
		{"do": "place", "at": LIB.ring_point(SHOVER_AT.x, SHOVER_AT.y, 0.1)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 160.0, "gain": 5.0},
	]
	shover_steps.append_array(_legs([[334.0, 50.0], [340.5, 50.0], [342.5, 49.3]], pace, 0.0))
	shover_steps.append_array([
		{"do": "chase", "victim": _victim, "range": 2.6, "timeout": 2.5, "speed": 1.0},
		{"do": "glance", "right": 40.0, "pitch": -22.0, "seconds": 0.6, "smooth": true},    # watch him go over
		{"do": "hold", "seconds": 60.0},
	])
	drive(runners[0], shover_steps, 0, "ClipShoverDriver")

	var victim_steps: Array = [
		{"do": "place", "at": LIB.ring_point(VICTIM_AT.x, VICTIM_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	victim_steps.append_array(_legs([[337.0, 49.2], [341.5, 49.0], [344.5, 47.8], [350.0, 47.6]], pace * 0.9, 0.0))
	victim_steps.append({"do": "hold", "seconds": 60.0})
	drive(runners[1], victim_steps, 1, "ClipVictimDriver")

	var lead_steps: Array = [
		{"do": "place", "at": LIB.ring_point(LEAD_AT.x, LEAD_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	lead_steps.append_array(_legs([[338.0, 51.5], [343.5, 50.2], [346.5, 49.6], [352.0, 50.5]], pace, 0.0))
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
