extends "res://tools/capture/stages/stage.gd"

## finale: one runner runs into the portal, arrives in the tower invincible,
## shoves the guard out of the open tower, the view tracks him, next round.
## Filmed with --pov=runner. Dials (--set=): lead (metres short of the portal, 5.0).

var _runner: RunnerBrain = null
var _driver: Node = null
var _arrived: bool = false


func bots() -> int:
	return 2


func needs_pov() -> String:
	return "runner"


func before_start() -> void:
	say("%d pads disarmed, %d traps disarmed" % [LIB.disarm_pads(clip.root), LIB.disarm_traps(clip.root)])
	controller().kill_beat_started.connect(
		func(guard: MatchParticipant, seconds: float, throw: Vector3) -> void:
			say("finale shove: %s thrown at %v for %.1f s, tower open %s" % [guard.body.name, throw, seconds, controller().is_tower_open()])
	)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	if controller().get_phase() != MatchController.Phase.ROUND:
		return false
	_runner = runners[0]
	var portal: Vector3 = (controller().arena.get_node(controller().end_marker_path) as Node3D).global_position
	var deg: float = LIB.bearing_of(portal)
	var r: float = LIB.radius_of(portal)
	var lead: float = float(option("lead", 5.0))
	# Short of the portal on its own lane, running the way the route runs into it.
	var start: Vector3 = LIB.ring_point(deg - RunnerBrain.TRAVEL_SIGN * rad_to_deg(lead / r), r, 0.1)
	_driver = drive(_runner, [
		{"do": "place", "at": start, "face": LIB.toward(start, portal)},
		{"do": "hold", "seconds": 1.0},
		{"do": "run", "to": portal, "within": 1.0, "timeout": 3.0},
		{"do": "release"},
	], 0, "FinaleRunner")
	stage_body(_runner.controller)
	say("finale: %s runs %.1f m into the portal at %.1f deg r %.1f" % [_runner.controller.name, lead, deg, r])
	return true


## The run is the arrival: once the driver lets go, the portal takes the runner.
func tick(_delta: float) -> void:
	if _arrived or _driver == null or not is_instance_valid(_driver) or not _driver.is_done():
		return
	_arrived = true
	var portal: Vector3 = (controller().arena.get_node(controller().end_marker_path) as Node3D).global_position
	var short: float = _runner.controller.global_position.distance_to(portal)
	var who: MatchParticipant = LIB.participant_of(controller(), _runner.controller)
	if who != null and who.tracker != null:
		who.tracker.lap_finished.emit(30.0, 240.0)
		say("finale: %s through the portal from %.1f m" % [_runner.controller.name, short])


func on_shove(shover: MatchParticipant, victim: MatchParticipant) -> void:
	say("shove %s -> %s" % [shover.body.name, victim.body.name])
