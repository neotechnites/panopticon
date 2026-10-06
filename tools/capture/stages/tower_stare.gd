extends "res://tools/capture/stages/stage.gd"

## tower_stare: a runner stood on the S2 rim walk, still, looking across the pit
## at the tower while the eye stares back (social clip hell_s2_tower). Filmed with
## [code]--pov=runner --stage=tower_stare --shot=hell_s2_tower --bots=2 --look=game --audio=near --seconds=12[/code]
## (cut 2.0 s in, 10 s). Ryan: "standing on the ring side at about the middle of
## hell's S2 section ... looking across at the tower. Mostly still with natural,
## subtle head sway ... The tower eye should be looking back at the camera, using
## the game's own eye tracking ... No other players in frame."
##
## So: the runner stands at 100 deg r 48.4 (deck y 23 from 47 to 50 here; lava
## past r 52), squared to the arena's axis, the pitch steered onto the eye. The
## sway is the camera's own local rotation: two slow sines per axis (a breath at
## ~0.23 Hz, a drift at ~0.07 Hz), +/- under a degree, so the tower never leaves
## frame. The eye's own _process is handed back (run_clip parks it), so it tracks
## the current camera exactly as in a match. The guard body is hidden; the spare
## prisoner stands 3 m behind the lens. S2's traps are off.
##
## Dials (--set=): deg (100), r (48.4), yaw (0.6), pitch (0.4), both degrees of sway.

const SPARE_BEHIND: float = 3.0

var _body: PlayerController = null
var _eye_point: Vector3 = Vector3(0.0, 30.0, 0.0)
var _guard_hidden: bool = false
var _t: float = 0.0


func bots() -> int:
	return 2


func needs_pov() -> String:
	return "runner"


func before_start() -> void:
	var eye: Node3D = clip._eye
	if eye != null:
		eye.process_mode = Node.PROCESS_MODE_INHERIT
		_eye_point = eye.global_position
		clip._eye = null
	if controller().arena != null:
		LIB.disarm_traps(controller().arena, ^"Sections/S2_LavaShelf")
	say("tower_stare: eye handed back to its own tracking at %v" % _eye_point)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var deg: float = float(option("deg", 100.0))
	var r: float = float(option("r", 48.4))
	var at: Vector3 = LIB.ring_point(deg, r, 0.1)
	var facing: Vector3 = LIB.toward(at, Vector3(0.0, at.y, 0.0))
	drive(runners[0], [
		{"do": "place", "at": at, "face": facing},
		{"do": "steer", "on": true, "pitch_gain": 6.0},
		{"do": "hold", "seconds": 600.0, "look_at": _eye_point},
	], 0)
	drive(runners[1], [
		{"do": "place", "at": LIB.ring_point(deg, r + SPARE_BEHIND, 0.1), "face": facing},
		{"do": "hold", "seconds": 600.0},
	], 1, "ClipSpare")
	_body = runners[0].controller
	stage_body(_body)
	say("tower_stare: %s at %.1f deg r %.1f, looking at the eye" % [_body.name, deg, r])
	return true


func tick(delta: float) -> void:
	_hide_the_guard()
	if _body == null or not is_instance_valid(_body):
		return
	var lens: Camera3D = _body.get_node_or_null(^"Head/Camera") as Camera3D
	if lens == null:
		return
	_t += delta
	var yaw: float = float(option("yaw", 0.6))
	var pitch: float = float(option("pitch", 0.4))
	var y: float = yaw * (0.55 * sin(TAU * 0.071 * _t + 0.4) + 0.3 * sin(TAU * 0.19 * _t + 1.7) + 0.15 * sin(TAU * 0.43 * _t))
	var p: float = pitch * (0.6 * sin(TAU * 0.23 * _t) + 0.25 * sin(TAU * 0.083 * _t + 2.1) + 0.15 * sin(TAU * 0.51 * _t + 0.9))
	var roll: float = 0.15 * sin(TAU * 0.11 * _t + 0.6)
	lens.rotation = Vector3(deg_to_rad(p), deg_to_rad(y), deg_to_rad(roll))


## Whoever holds the tower is hidden: no other player in frame.
func _hide_the_guard() -> void:
	if _guard_hidden or seat() == null:
		return
	var shooter: TowerShooter = seat().get_active_shooter()
	if shooter == null or shooter.controller == null:
		return
	shooter.controller.visible = false
	_guard_hidden = true
	say("tower_stare: guard hidden")
