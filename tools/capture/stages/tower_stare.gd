extends "res://tools/capture/stages/stage.gd"

## tower_stare: a runner's eye on the S2 rim, looking across the pit at the tower
## while the eye stares back (social clip hell_s2_tower). Filmed with
## [code]--stage=tower_stare --shot=hell_s2_tower --bots=2 --look=game --seconds=12[/code]
## (cut 2.0 s in, 10 s). Ryan: "standing on the ring side at about the middle of
## hell's S2 section ... looking across at the tower. Mostly still with natural,
## subtle head sway ... The tower eye should be looking back at the camera, using
## the game's own eye tracking ... No other players in frame." Then, on the first
## cut: "you can't see the lava sea" -- the sea fills the lower third, the tower
## crown at ~40% from the top, wall and slits above, a fairly wide lens.
##
## So: the lens stands at the rim edge, 100 deg r 47.0, 4 m over the deck (y 27),
## pitched onto (0, 22.9, 0): the sea (y -11.9) runs from the tower's foot to the
## far shore. Sway is two slow sines per axis (a breath ~0.23 Hz, a drift ~0.07
## Hz), under a degree. The eye's own _process is handed back (run_clip parks it),
## so it tracks the current camera exactly as in a match. The guard is hidden;
## both prisoners stand on the deck behind the lens. S2's traps are off.
##
## Dials (--set=): deg (100), r (47.0), h (4.0), aim_y (22.9), fov (75, vertical),
## yaw (0.6), pitch (0.4), both degrees of sway.

var _guard_hidden: bool = false
var _t: float = 0.0


func bots() -> int:
	return 2


func before_start() -> void:
	var eye: Node3D = clip._eye
	if eye != null:
		eye.process_mode = Node.PROCESS_MODE_INHERIT
		clip._eye = null
	if controller().arena != null:
		LIB.disarm_traps(controller().arena, ^"Sections/S2_LavaShelf")
	say("tower_stare: eye handed back to its own tracking")


func cast(runners: Array[RunnerBrain]) -> bool:
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var deg: float = float(option("deg", 100.0))
	for index: int in runners.size():
		var at: Vector3 = LIB.ring_point(deg - 3.0 + 6.0 * float(index), 55.0, 0.1)
		drive(runners[index], [
			{"do": "place", "at": at, "face": LIB.radial_at(deg)},
			{"do": "hold", "seconds": 600.0},
		], index, "ClipBehind%d" % index)
	say("tower_stare: %d prisoners parked behind the lens" % runners.size())
	return true


func tick(_delta: float) -> void:
	_hide_the_guard()


func lens(delta: float) -> bool:
	var lens_camera: Camera3D = camera()
	if lens_camera == null:
		return false
	_t += delta
	var deg: float = float(option("deg", 100.0))
	var at: Vector3 = LIB.ring_point(deg, float(option("r", 47.0)), float(option("h", 4.0)))
	lens_camera.global_position = at
	lens_camera.look_at(Vector3(0.0, float(option("aim_y", 22.9)), 0.0), Vector3.UP)
	var yaw: float = float(option("yaw", 0.6))
	var pitch: float = float(option("pitch", 0.4))
	var y: float = yaw * (0.55 * sin(TAU * 0.071 * _t + 0.4) + 0.3 * sin(TAU * 0.19 * _t + 1.7) + 0.15 * sin(TAU * 0.43 * _t))
	var p: float = pitch * (0.6 * sin(TAU * 0.23 * _t) + 0.25 * sin(TAU * 0.083 * _t + 2.1) + 0.15 * sin(TAU * 0.51 * _t + 0.9))
	var roll: float = 0.15 * sin(TAU * 0.11 * _t + 0.6)
	lens_camera.rotate_object_local(Vector3.UP, deg_to_rad(y))
	lens_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(p))
	lens_camera.rotate_object_local(Vector3.BACK, deg_to_rad(roll))
	lens_camera.fov = float(option("fov", 75.0))
	if not lens_camera.current:
		lens_camera.current = true
	return true


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
