extends "res://tools/capture/stages/stage.gd"

## trailer_forest_pit (v4 9a/9b): three run the forest lane; the lead stops at the lip and is shoved into
## the pit by the man behind him, the third pulls up and looks down; one take, the shover's eyes (pov=shover) or the faller's (pov=victim).
## Lip trunks r 47.45 at 148.28 and 155.82 (forest_trees.py LAYOUT): the lip between is clear, the bank
## drops near-vertical inside r 45. The KillBox roof is y 0, above the mist; floor_kill lowers it (shot only).
## Dials: pov (shover|victim), at (151.6 deg, the lip he stops on), floor_kill (1), impulse (11), up (3.5).

const LIP_R: float = 47.85

var _victim: PlayerController = null
var _shover: PlayerController = null
var _third: PlayerController = null
var _drivers_by_body: Dictionary = {}
var _shoved: bool = false


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 11.0))
	rules.shove_up_impulse = float(option("up", 3.5))
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	if int(option("floor_kill", 1)) == 1:
		# The ravine kills at y 0, six metres over the mist; for this shot it kills at the floor (y -11.05).
		var box: Node3D = LIB.find_node(clip.root, "KillBox") as Node3D
		if box != null:
			box.position.y -= 10.9


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var at: float = float(option("at", 151.6))
	_victim = runners[0].controller
	_shover = runners[1].controller
	_third = runners[2].controller
	# The victim: down the lane, then over to the lip, a look out at the tower.
	_drivers_by_body[_victim] = drive(runners[0], [
		{"do": "place", "deg": at - 8.6, "r": 50.6, "h": 0.1, "face": LIB.tangent_at(at - 8.6)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 300.0, "gain": 9.0},
		{"do": "lane", "to": at - 2.6, "r": 50.4, "speed": 0.64, "weave": 0.05, "period": 1.3, "timeout": 4.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -3.0}, {"t": 0.55, "right": 22.0, "pitch": 6.0}, {"t": 0.95, "right": 2.0, "pitch": -2.0}]},
		{"do": "run", "to": LIB.ring_point(at, LIP_R), "within": 0.35, "speed": 0.45, "timeout": 3.0},
		{"do": "hesitate", "seconds": 0.25},
		{"do": "glance", "right": 28.0, "pitch": 14.0, "seconds": 0.45},
		{"do": "hold", "seconds": 60.0, "fidget": true},
	], 0, "ClipPitVictim")
	# The shover: a step behind and outboard, he comes up, eyes on the man at the edge, and shoves.
	_drivers_by_body[_shover] = drive(runners[1], [
		{"do": "place", "deg": at - 11.8, "r": 51.3, "h": 0.1, "face": LIB.tangent_at(at - 11.8)},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.18},
		{"do": "steer", "on": true, "rate": 320.0, "gain": 10.0},
		{"do": "lane", "to": at - 2.2, "r": 51.1, "speed": 0.86, "weave": 0.04, "period": 1.1, "timeout": 5.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.7, "right": -10.0, "pitch": -4.0}, {"t": 1.05, "right": 18.0, "pitch": -6.0}, {"t": 1.4, "right": 9.0, "pitch": -5.0}]},
		{"do": "run", "to": LIB.ring_point(at + 0.6, 49.6), "within": 0.4, "speed": 0.55, "timeout": 2.0},
		{"do": "glance", "right": 62.0, "pitch": -9.0, "seconds": 0.24},
		{"do": "shove", "victim": _victim},
		{"do": "hold", "seconds": 0.22},
		{"do": "glance", "right": -6.0, "pitch": -36.0, "seconds": 0.5},
		{"do": "hold", "seconds": 0.35},
		{"do": "glance", "right": 9.0, "pitch": -6.0, "seconds": 0.45},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipPitShover")
	# The third: behind on the lane; he flinches at the shove, pulls up by the lip and looks down.
	_drivers_by_body[_third] = drive(runners[2], [
		{"do": "place", "deg": at - 14.0, "r": 50.2, "h": 0.1, "face": LIB.tangent_at(at - 14.0)},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.12},
		{"do": "steer", "on": true, "rate": 280.0, "gain": 8.0},
		{"do": "lane", "to": at - 3.2, "r": 50.0, "speed": 0.66, "weave": 0.06, "period": 1.4, "timeout": 5.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.8, "right": -16.0, "pitch": 3.0}, {"t": 1.2, "right": 4.0, "pitch": -1.0}],
			"flinch_on": "shove", "flinch_glances": [{"t": 0.05, "right": 30.0, "pitch": -5.0}, {"t": 0.3, "right": 52.0, "pitch": -14.0}, {"t": 0.95, "right": 24.0, "pitch": -9.0}]},
		{"do": "run", "to": LIB.ring_point(at - 1.7, 48.9), "within": 0.4, "speed": 0.4, "timeout": 2.0},
		{"do": "hesitate", "seconds": 0.2},
		{"do": "glance", "right": 40.0, "pitch": -26.0, "seconds": 0.5},
		{"do": "hold", "seconds": 60.0, "fidget": true},
	], 2, "ClipPitThird")
	for body: PlayerController in [_shover, _third]:
		LIB.hide_from_the_rifle(body)
	victim_body(_victim)
	stage_body(_victim if String(option("pov", "shover")) == "victim" else _shover)
	say("trailer_forest_pit: %s shoves %s off the lip at %.1f deg; %s ahead" % [_shover.name, _victim.name, at, _third.name])
	return true


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and _victim != null and is_instance_valid(_victim) and Engine.get_physics_frames() % 10 == 0:
		var line: String = ""
		for body: PlayerController in [_victim, _shover, _third]:
			line += " %s %.1f/%.2f y%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y]
		say("at" + line)


func on_shove(_from: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	say("shove: %s over the lip at %.1f deg r %.2f" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])
	# The faller: a jerk, then round and up at the lip he left, the men on it; the hand never still.
	_drivers_by_body[_victim].retarget([
		{"do": "steer", "on": false},
		{"do": "glance", "right": 14.0, "pitch": 9.0, "seconds": 0.12},
		{"do": "glance", "right": -150.0, "pitch": 46.0, "seconds": 0.62},
		{"do": "hold", "seconds": 0.3},
		{"do": "glance", "right": 12.0, "pitch": 7.0, "seconds": 0.4},
		{"do": "hold", "seconds": 60.0},
	])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s %s" % [participant.body.name, participant.death_cause])


## No third-person lens: every shot of the trailer is a POV.
func lens(_delta: float) -> bool:
	return false
