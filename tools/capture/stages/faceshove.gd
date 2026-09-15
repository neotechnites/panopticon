extends "res://tools/capture/stages/stage.gd"

## faceshove: two runners face to face, trading shoves (f05_face_shove and,
## down the first one's eyes, f04_pov_shove).
##
## Ryan: "a shot or two runners facing eachother shoving each other" and "4th
## can be player perspective of doing section 5".
##
## Third person: [code]--shot=s3_face_side --stage=faceshove --bots=2 --seconds=8[/code]
## (or s3_face_over); the lens keeps the shot path's offset from the pair's
## eased midpoint, looks at it, and zooms out as the pair spreads so both
## bodies stay in the tall frame. POV: add [code]--pov=runner[/code]; the first
## body is ridden and walks back in between shoves (Ryan: "every POV needs
## to look like a person playing").
##
## The pair stands 2.4 m apart on the S3 lane at 170.3 deg r 50.5 (POV: r 55,
## clear of the demon pads at 148/163/177 deg r 51, which re-launch a shoved
## body flying over them; the pads are switched off for the clip anyway). Each
## shove is the real MatchController.apply_shove (16 m/s + 7 up, 1.4 s air
## lock): the thrown runner lands, comes straight back and returns it, about
## every 1.15 s.
##
## Dials (--set=): deg (170.3), r (50.5, 55 down the eyes), gap (2.4 m), rounds (6).

const ZOOM_MIN_FOV: float = 62.0
const ZOOM_MAX_FOV: float = 92.0
const ZOOM_SPREAD: float = 9.0     # metres apart at which the lens is widest
const LENS_EASE: float = 0.35

var _first: PlayerController = null
var _second: PlayerController = null
var _offset: Vector3 = Vector3.ZERO
var _mid: Vector3 = Vector3.ZERO
var _lens_set: bool = false


func bots() -> int:
	return 2


func before_start() -> void:
	say("%d pads disarmed" % LIB.disarm_pads(clip.root))


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	var pov: bool = String(option("pov", "")) == "runner"
	var deg: float = float(option("deg", 170.3))
	var r: float = float(option("r", 55.0 if pov else 50.5))
	var gap: float = float(option("gap", 2.4))
	var rounds: int = int(option("rounds", 6))
	var half: float = rad_to_deg(gap * 0.5 / r)
	_first = runners[0].controller
	_second = runners[1].controller
	var a: Vector3 = LIB.ring_point(deg - half, r, 0.1)
	var b: Vector3 = LIB.ring_point(deg + half, r, 0.1)
	var first_steps: Array = [{"do": "place", "at": a, "face": LIB.toward(a, b)}, {"do": "hold", "seconds": 0.5}]
	var second_steps: Array = [{"do": "place", "at": b, "face": LIB.toward(b, a)}, {"do": "hold", "seconds": 0.3}]
	if pov:
		first_steps.append({"do": "human", "on": true})
	# The second takes the first swing; from then on each one lands, comes
	# back, swings, and stands square until the answer throws it.
	second_steps.append({"do": "wait_launch", "timeout": 4.0})
	second_steps.append({"do": "land"})
	for _round: int in rounds:
		first_steps.append({"do": "chase", "victim": _second, "range": 2.6, "timeout": 5.0})
		if pov:
			first_steps.append({"do": "advance", "victim": _second, "speed": 0.3, "sway": 0.35, "until": 4.0, "timeout": 4.0})
			first_steps.append({"do": "wait_launch", "timeout": 3.0})
		else:
			first_steps.append({"do": "face_hold", "victim": _second, "seconds": 4.0})
		first_steps.append({"do": "land"})
		second_steps.append({"do": "chase", "victim": _first, "range": 2.4, "timeout": 5.0})
		second_steps.append({"do": "face_hold", "victim": _first, "seconds": 4.0})
		second_steps.append({"do": "land"})
	first_steps.append({"do": "hold", "seconds": 60.0})
	second_steps.append({"do": "hold", "seconds": 60.0})
	drive(runners[0], first_steps, 0)
	drive(runners[1], second_steps, 1)
	stage_body(_first)
	victim_body(_second)
	say("faceshove: %s and %s %.1f m apart at %.1f deg r %.1f%s" % [_first.name, _second.name, gap, deg, r, ", ridden" if pov else ""])
	return true


## A tracking dolly: the shot path's offset from the pair's midpoint, kept as
## the midpoint moves, looking at it, wider as they spread.
func lens(delta: float) -> bool:
	if _first == null or camera() == null or not is_instance_valid(_first) or not is_instance_valid(_second):
		return false
	var mid: Vector3 = (_first.global_position + _second.global_position) * 0.5 + Vector3.UP * 1.0
	if not _lens_set:
		_lens_set = true
		var pose: Dictionary = clip.SHOTS.sample(clip._keys, clip._key_start)
		_offset = (pose["pos"] as Vector3) - mid
		_mid = mid
	_mid = _mid.lerp(mid, 1.0 - exp(-delta / LENS_EASE))
	var spread: float = _first.global_position.distance_to(_second.global_position)
	camera().global_position = _mid + _offset
	camera().look_at(_mid, Vector3.UP)
	camera().fov = lerpf(ZOOM_MIN_FOV, ZOOM_MAX_FOV, clampf(spread / ZOOM_SPREAD, 0.0, 1.0))
	camera().current = true
	return true
