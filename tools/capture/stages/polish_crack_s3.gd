extends "res://tools/capture/stages/stage.gd"

## polish_crack_s3: the S3 crack grid from 2.8 m, an eased pan across it on L5, then on L6
## three prisoners run up the grid's clear lane one by one onto the 160 crack and are launched.
## Ryan: "instead of the shot of the crack being at S4, let's try it at S3, with the shot a
## little higher so you can see the cracks better, and have it pan."
##
## Capture: [code]--shot=s4_edge --stage=polish_crack_s3 --bots=3 --look=social --seconds=11.2[/code]
## (cut in 1.2 s, 10 s). Probe (--pads, --heights): S3 is flat deck r 47-57; cracks in columns
## r 49.1 / 52.4 / 55.6 every ~3.2 deg from 146.6; row 150 is full, the r 52.4 lane is clear
## 152.5-157.4, LavaCrack_r04_c1_160deg (159.5, r 52.4) throws ~9 m up the ring onto clear deck.
##
## Dials (--set=): wait (driver seconds the first body holds, 7.39), gap (0.75), jitter (0.12),
## pov (the body --pov=runner rides, 0).

## The crack the runners hit, and a point up the lane they push at in the air and stop on.
const CRACK := Vector3(-49.0508, 23.0, 18.2906)
const CRACK_DEG: float = 159.5
const LANE_R: float = 52.4
const LAND_DEG: float = 171.0
## Where each body waits: just past the full row at 150, behind the lens and out of frame.
const WAIT: Array = [[152.85, 52.4], [152.75, 53.0], [152.8, 51.85]]
## Lens 2.8 m up at the outer side of the lane, 5 deg short of the crack, looking up the grid.
const CAM_FROM_DEG: float = 154.3
const CAM_TO_DEG: float = 154.7
const CAM_R: float = 54.6
const CAM_HEIGHT: float = 2.8
## The pan: from the outer column's cracks at 166 deg to the 160 crack low-middle, eased over
## PAN_SECONDS of the take (cut 0-7 s); the lens position keeps creeping so it is never still.
const LOOK_FROM := [166.0, 57.5, -0.5]
const LOOK_TO := [163.0, 52.3, 0.4]
const PAN_FROM: float = 1.2
const PAN_SECONDS: float = 7.0
const DRIFT_SECONDS: float = 11.2
## Vertical fov: the crack, the lane in and ~1 s of the flight up the ring in one frame.
const CAM_FOV: float = 62.0

var _bodies: Array = []
var _launched: Dictionary = {}


func bots() -> int:
	return 3


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(clip._options.get("seed", 0)) * 31 + 10)
	var wait: float = float(option("wait", 7.39))
	var gap: float = float(option("gap", 0.75))
	var jitter: float = float(option("jitter", 0.12))
	var crack: Vector3 = LIB.ring_point(CRACK_DEG, LANE_R, 0.0)
	for index: int in range(3):
		var spot: Array = WAIT[index]
		var from: Vector3 = LIB.ring_point(float(spot[0]), float(spot[1]), 0.1)
		var beat: float = wait + gap * float(index) + (rng.randf_range(-jitter, jitter) if index > 0 else 0.0)
		drive(runners[index], [
			{"do": "place", "at": from, "face": LIB.tangent_at(float(spot[0]))},
			{"do": "until", "t": beat},
			{"do": "run", "to": crack, "within": 0.4, "timeout": 3.0},
			{"do": "wait_launch", "timeout": 1.0},
			# In the air the stick pushes up the lane, as a player would.
			{"do": "run", "to": LIB.ring_point(LAND_DEG, LANE_R, 0.0), "within": 0.6, "timeout": 2.5},
			{"do": "hold", "seconds": 30.0},
		], index, "ClipCrackS3Driver%d" % index)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[clampi(int(option("pov", 0)), 0, 2)])
	say("polish_crack_s3: %d prisoners up the S3 lane" % _bodies.size())
	return true


## Prints each launch off the 160 crack, the beat the cut is timed on.
func tick(_delta: float) -> void:
	for item: Variant in _bodies:
		if not is_instance_valid(item):
			continue
		var body: PlayerController = item as PlayerController
		var flat: Vector2 = Vector2(body.global_position.x - CRACK.x, body.global_position.z - CRACK.z)
		if body.velocity.y > 6.0 and not _launched.has(body.name) and flat.length() < 2.5:
			_launched[body.name] = elapsed()
			say("launch 160 %s" % body.name)


func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var drift: float = smoothstep(0.0, 1.0, clampf(elapsed() / DRIFT_SECONDS, 0.0, 1.0))
	var pan: float = smoothstep(0.0, 1.0, clampf((elapsed() - PAN_FROM) / PAN_SECONDS, 0.0, 1.0))
	var look_from: Vector3 = LIB.ring_point(LOOK_FROM[0], LOOK_FROM[1], LOOK_FROM[2])
	var look_to: Vector3 = LIB.ring_point(LOOK_TO[0], LOOK_TO[1], LOOK_TO[2])
	camera().global_position = LIB.ring_point(lerpf(CAM_FROM_DEG, CAM_TO_DEG, drift), CAM_R, CAM_HEIGHT)
	camera().look_at(look_from.lerp(look_to, pan), Vector3.UP)
	camera().fov = CAM_FOV
	camera().current = true
	return true
