extends "res://tools/capture/stages/stage.gd"

## trailer_beach_portal (v60): the first half of the portal run, on the beach. A runner POV sprints the sand lane into the
## beach portal (300 deg r 68.5) with the marble run's own steps and pace, from the same path length out, so the cut to
## marble mid-run is one run to one portal. --map=beach --shot=portal --pov=runner --bots=3
## Dials: arc (30.45 m: the marble run's distance to its portal at its first stage line), pace (1.0), r (67.4), glance_t (0.0: marble's glance timing).

const PORTAL_DEG: float = 300.0
const PORTAL_R: float = 68.5
## The marble run's lane r and the degrees past the portal it aims (trailer_finish_marble), in metres.
const OVER_METRES: float = 2.72
const STEP_ONE_METRES: float = 1.83
const STEP_TWO_METRES: float = 4.56

var _runner: PlayerController = null
var _arrived: bool = false


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
	var lane_r: float = float(option("r", 67.4))
	var degrees_per_metre: float = rad_to_deg(1.0 / lane_r)
	var from_deg: float = PORTAL_DEG - float(option("arc", 30.45)) * degrees_per_metre
	var pace: float = float(option("pace", 1.0))
	var start: Vector3 = LIB.ring_point(from_deg, lane_r, 0.1)
	_runner = runners[0].controller
	drive(runners[0], [
		{"do": "place", "at": start, "face": LIB.tangent_at(from_deg)},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.2},
		{"do": "lane", "to": from_deg + STEP_ONE_METRES * degrees_per_metre, "r": lane_r, "speed": pace, "timeout": 2.0},
		{"do": "lane", "to": from_deg + STEP_TWO_METRES * degrees_per_metre, "r": lane_r, "speed": pace, "weave": 0.05, "period": 1.2, "timeout": 2.0},
		{"do": "lane", "to": PORTAL_DEG + OVER_METRES * degrees_per_metre, "r": PORTAL_R, "speed": pace, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.45, "right": 18.0, "pitch": 5.0}, {"t": 0.85, "right": 2.0, "pitch": 0.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipBeachPortalDriver")
	# The other two stand far back down the lap, out of the shot and out of the rifle's sight.
	for index: int in [1, 2]:
		var back: float = 140.0 + 10.0 * index
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(back, lane_r, 0.1), "face": LIB.tangent_at(back)},
			{"do": "hold", "seconds": 60.0},
		], index, "ClipParkedDriver%d" % index)
		LIB.hide_from_the_rifle(runners[index].controller)
	stage_body(_runner)
	say("trailer_beach_portal: %s runs the sand from %.1f deg into the portal at %.0f deg" % [_runner.name, from_deg, PORTAL_DEG])
	return true


func tick(_delta: float) -> void:
	if _runner != null and not _arrived and _runner.global_position.distance_to(LIB.ring_point(PORTAL_DEG, PORTAL_R, 0.0)) < 1.5:
		_arrived = true
		say("arrived at %.2f s" % elapsed())
	if _runner != null and Engine.get_physics_frames() % 15 == 0:
		say("at %.2f deg r %.2f; %.2f m from the portal" % [LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position), _runner.global_position.distance_to(LIB.ring_point(PORTAL_DEG, PORTAL_R, 0.0))])


func lens(_delta: float) -> bool:
	return false
