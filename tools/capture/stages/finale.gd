extends "res://tools/capture/stages/stage.gd"

## finale: one runner runs into the portal and arrives in the tower, where the
## guard is scoped out of the far window tracking a second runner on the ring,
## his back to the room. Ryan: "the pov of a runner shoving the guard is just
## straight up not gameplay". So the runner walks the few metres up behind him
## (steered, not snapped) and shoves on the normal input once in reach; the
## game's own kill-beat throw and cinematic follow. Filmed with --pov=runner.
## Dials (--set=): lead (metres short of the portal, 5.0), stand (guard's metres
## out from the tower axis toward his window, 3.0), pace (the walk up, 0.6).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const WINDOW_PHASE: float = 25.0
const WINDOW_STEP: float = 45.0

var _runner: RunnerBrain = null
var _mark: RunnerBrain = null
var _driver: Node = null
var _arrived: bool = false
var _hand: Node = null
var _window_deg: float = 0.0


func bots() -> int:
	return 2


func needs_pov() -> String:
	return "runner"


func before_start() -> void:
	say("%d pads disarmed, %d traps disarmed" % [LIB.disarm_pads(clip.root), LIB.disarm_traps(clip.root)])
	controller().kill_beat_started.connect(
		func(guard: MatchParticipant, seconds: float, throw: Vector3) -> void:
			# The hand lets go of the head: the throw is the game's.
			if _hand != null and is_instance_valid(_hand):
				_hand.queue_free()
			_hand = null
			say("finale shove: %s thrown at %v for %.1f s, tower open %s" % [guard.body.name, throw, seconds, controller().is_tower_open()])
	)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	if controller().get_phase() != MatchController.Phase.ROUND:
		return false
	var held: MatchParticipant = controller().get_seat_participant()
	var guard: PlayerController = held.body if held != null else null
	if guard == null:
		return false
	_runner = runners[0]
	_mark = runners[1]
	var portal: Vector3 = _portal()
	var deg: float = LIB.bearing_of(portal)
	var r: float = LIB.radius_of(portal)
	var lead: float = float(option("lead", 5.0))
	# The opening across the room from the portal's arrival side.
	_window_deg = WINDOW_PHASE + WINDOW_STEP * roundf((deg + 180.0 - WINDOW_PHASE) / WINDOW_STEP)
	# Short of the portal on its own lane, running the way the route runs into it.
	var start: Vector3 = LIB.ring_point(deg - RunnerBrain.TRAVEL_SIGN * rad_to_deg(lead / r), r, 0.1)
	_driver = drive(_runner, [
		{"do": "place", "at": start, "face": LIB.toward(start, portal)},
		{"do": "hold", "seconds": 1.0},
		{"do": "run", "to": portal, "within": 1.0, "timeout": 3.0},
		{"do": "wait_flag", "flag": "arrived", "timeout": 2.0},
		# Through: a beat to take in the room, then up behind him on the mouse.
		{"do": "hold", "seconds": 0.45},
		{"do": "steer", "on": true, "rate": 240.0, "gain": 6.0},
		{"do": "human", "on": true},
		{"do": "chase", "victim": guard, "range": 2.3, "speed": float(option("pace", 0.6)), "timeout": 6.0},
		{"do": "chase", "victim": guard, "range": 2.0, "speed": 0.4, "timeout": 4.0},
		{"do": "hold", "seconds": 30.0},
	], 0, "FinaleRunner")
	# The man in the scope: a lane on the deck outside the guard's window.
	drive(_mark, [
		{"do": "place", "at": LIB.ring_point(_window_deg - 18.0, 52.0, 0.1)},
		{"do": "lane", "to": _window_deg + 30.0, "r": 52.0, "speed": 0.5, "weave": 0.2, "period": 1.2, "timeout": 30.0},
		{"do": "hold", "seconds": 60.0},
	], 1, "FinaleMark")
	stage_body(_runner.controller)
	say("finale: %s runs %.1f m into the portal at %.1f deg r %.1f; guard at window %.0f deg" % [_runner.controller.name, lead, deg, r, _window_deg])
	return true


func tick(_delta: float) -> void:
	if _runner == null:
		return
	if _hand == null and not _arrived:
		_post_the_guard()
	# The run is the arrival: once it reaches the portal, the portal takes the runner.
	if _arrived or _driver == null or not is_instance_valid(_driver) or _driver.clock() < 1.0:
		return
	var offset: Vector3 = _runner.controller.global_position - _portal()
	var short: float = Vector2(offset.x, offset.z).length()
	if short > 1.05 and _driver.clock() < 4.0:
		return
	_arrived = true
	var who: MatchParticipant = LIB.participant_of(controller(), _runner.controller)
	if who != null and who.tracker != null:
		who.tracker.lap_finished.emit(30.0, 240.0)
		say("finale: %s through the portal from %.1f m" % [_runner.controller.name, short])
	_driver.flag("arrived")


## The guard stood at the window across the room from the portal, scoped onto the ring.
func _post_the_guard() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	var axis: Vector3 = (controller().arena.get_node(controller().spawn_marker_path) as Node3D).global_position
	var spot: Vector3 = axis + LIB.radial_at(_window_deg) * float(option("stand", 3.0))
	guard.global_position = spot
	guard.velocity = Vector3.ZERO
	var out: Vector3 = LIB.ring_point(_window_deg, 52.0, 1.0) - spot
	guard.rotation = Vector3(0.0, atan2(-out.x, -out.z), 0.0)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.park = LIB.ring_point(_window_deg, 52.0, 1.0)
	_hand.start_at = elapsed()
	# Tracking, never firing: busy at the window when the runner comes in.
	_hand.beats.append({"body": _mark.controller, "seconds": 120.0})
	say("guard posted %.1f m out at the %.0f deg window, scoped on %s" % [float(option("stand", 3.0)), _window_deg, _mark.controller.name])


func _portal() -> Vector3:
	return (controller().arena.get_node(controller().end_marker_path) as Node3D).global_position


func on_shove(shover: MatchParticipant, victim: MatchParticipant) -> void:
	say("shove %s -> %s" % [shover.body.name, victim.body.name])
