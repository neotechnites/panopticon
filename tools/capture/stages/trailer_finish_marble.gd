extends "res://tools/capture/stages/trailer_finish.gd"

## trailer_finish on --map=marble: a runner POV sprints the corridor (+bearing) from 320 deg into
## the portal at 345, is armed in the tower and shoots the guard. Dials: from (320,52.4), pace (1.0).


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	var from: Vector3 = LIB.polar(String(option("from", "320,52.4")), LIB.ring_point(320.0, 52.4))
	var pace: float = float(option("pace", 1.0))
	_runner = runners[0].controller
	# Six steps so the lane into the portal is index 5, the step trailer_finish's tick arms on.
	_driver = drive(runners[0], [
		{"do": "place", "at": from + Vector3.UP * 0.1, "face": LIB.tangent_at(LIB.bearing_of(from))},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.2},
		{"do": "lane", "to": LIB.bearing_of(from) + 2.0, "r": 52.3, "speed": pace, "timeout": 2.0},
		{"do": "lane", "to": LIB.bearing_of(from) + 5.0, "r": 52.1, "speed": pace, "weave": 0.05, "period": 1.2, "timeout": 2.0},
		{"do": "lane", "to": PORTAL_DEG + 3.0, "r": PORTAL_R, "speed": pace, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.45, "right": 18.0, "pitch": 5.0}, {"t": 0.85, "right": 2.0, "pitch": 0.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipFinishDriver")
	drive(runners[1], [
		{"do": "place", "at": LIB.ring_point(250.0, 52.0, 0.1), "face": LIB.tangent_at(250.0)},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipParkedDriver")
	LIB.hide_from_the_rifle(runners[1].controller)
	stage_body(_runner)
	say("trailer_finish_marble: %s runs from %.1f deg into the portal" % [_runner.name, LIB.bearing_of(from)])
	return true
