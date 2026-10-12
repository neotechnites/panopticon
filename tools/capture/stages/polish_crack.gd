extends "res://tools/capture/stages/stage.gd"

## polish_crack: the S4 lava crack at 227 deg from the ground, alone, then
## three prisoners come off the 212 crack, land on it and bounce off to 242.
##
## Ryan: L5 "roughly ground level shot showing the cracks and effects" / L6
## "same shot, but at this point people come and bounce off it".
##
## [code]--shot=s4_edge --stage=polish_crack --bots=3 --look=social --seconds=11.2[/code]
## (cut 1.2 s in, 10 s). The crack sits on a 3 m island in S4's lava (r 53-56,
## 223-228 deg, probe --heights), so nobody can run onto it: the chain is
## 212 -> 227 -> 242 (each pad's 18 m/s 45 deg arc lands on the next, 14.7 m).
## Bodies wait on the clear deck at 204-206 deg (probe --clear: 202-207), run
## onto the 212 crack on their beat and arrive at 227 by air.
##
## Dials (--set=): first (driver seconds the first body leaves for 212, 6.18),
## gap (seconds between bodies, 0.75), jitter (seeded +- seconds, 0.12).

## The crack's own centre, and the two it chains between (bentham_ring.tscn).
const CRACK_212 := Vector3(-44.6061, 23.0, -27.8757)
const CRACK_227 := Vector3(-37.0701, 23.2, -39.8437)
const CRACK_242 := Vector3(-25.1778, 23.4, -47.5481)
## The 212 pad's own arc lands at 220.6 deg in the lava (smoke), so its launch
## is carried on to 227 by a leap of the same shape (vy ~14 vs the pad's 12.4).
const LEAP_SPEED: float = 12.5
## Lens 7 m behind the crack on its launch line, 1 m toward the 212 side, 1.4 m
## over its slab (0.8 m sat under the slab's lip and hid the crack, take 1).
const CAM_FROM_DEG: float = 219.7
const CAM_TO_DEG: float = 220.1
const CAM_R: float = 55.05
const CAM_HEIGHT: float = 1.6
## 4 m past the crack, 1.4 m up: level, so the 3 m haze and the rock at
## 238-242 fill the frame behind it and the crack sits low-middle.
const LOOK_DEG: float = 231.3
const LOOK_R: float = 53.9
const LOOK_HEIGHT: float = 1.4
## Vertical fov: the crack, its haze and ~1 s of the outbound arc in one frame.
const CAM_FOV: float = 55.0
## The take this lens drifts over (a very slow push, 0.4 deg ~ 0.4 m).
const DRIFT_SECONDS: float = 11.2
## Where each body waits, off-frame behind the lens (deg, r).
const WAIT: Array = [[205.2, 52.6], [204.4, 53.4], [205.8, 51.8]]

var _airborne: Dictionary = {}
var _bodies: Array = []


func bots() -> int:
	return 3


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var first: float = float(option("first", 6.18))
	var gap: float = float(option("gap", 0.75))
	var jitter: float = float(option("jitter", 0.12))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(clip._options.get("seed", 0)) * 7919 + 227
	for index: int in range(3):
		var spot: Array = WAIT[index]
		var from: Vector3 = LIB.ring_point(float(spot[0]), float(spot[1]), 0.1)
		var beat: float = first + gap * float(index) + (rng.randf_range(-jitter, jitter) if index > 0 else 0.0)
		drive(runners[index], [
			{"do": "place", "at": from, "face": LIB.toward(from, CRACK_212)},
			{"do": "until", "t": beat},
			{"do": "run", "to": CRACK_212, "within": 0.4, "speed": 1.0, "timeout": 2.5},
			{"do": "wait_launch", "timeout": 1.0},
			{"do": "leap", "to": CRACK_227, "speed": LEAP_SPEED, "lock": 0.9},
			{"do": "land", "look_at": CRACK_242},
			{"do": "hold", "seconds": 30.0},
		], index)
		_bodies.append(runners[index].controller)
		say("body %d leaves for 212 at %.2f s of the driver clock" % [index, beat])
	return true


## Prints each take-off from the 227 crack, the beat the cut is timed on.
func tick(_delta: float) -> void:
	for item: Variant in _bodies:
		if not is_instance_valid(item):
			continue
		var body: PlayerController = item as PlayerController
		var near: bool = Vector2(body.global_position.x - CRACK_227.x, body.global_position.z - CRACK_227.z).length() < 2.2
		var up: bool = not body.is_on_floor() and body.velocity.y > 6.0
		var was: bool = bool(_airborne.get(body, false))
		if near and up and not was:
			say("launch227 %s" % body.name)
		_airborne[body] = near and up


func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var u: float = smoothstep(0.0, 1.0, clampf(elapsed() / DRIFT_SECONDS, 0.0, 1.0))
	camera().global_position = LIB.ring_point(lerpf(CAM_FROM_DEG, CAM_TO_DEG, u), CAM_R, CAM_HEIGHT)
	camera().look_at(LIB.ring_point(LOOK_DEG, LOOK_R, LOOK_HEIGHT), Vector3.UP)
	camera().fov = CAM_FOV
	camera().current = true
	return true
