extends "res://tools/capture/stages/stage.gd"

## polish_lava: the S5 lake from its near bank, lens at ground height, the swells rolling along it.
## Ryan: "shot of the lava from about ground height so it's very clear it's waving".
##
## [code]--shot=lava_parkour --stage=polish_lava --bots=1 --look=social --seconds=11.2[/code]
## (cut 1.2 s in, 9 s). The lens drifts along the 291.3 deg bank (outer to inner), 0.6 m over it.
##
## Probed (probe_ring --heights): deck +0.00 at 291-292 deg for r 50-57, the lake from 292.5
## (drawn 0.3 m under the deck); the S4|S5 lip wall stands at r 48 up to 290.5.

## The bank: deck at 291.0-292.0 deg, the lake's end at 292.3.
const BANK_DEG: float = 291.3
const CAM_R_FROM: float = 55.6   # the outer end, 1.7 m off the outer wall foot (57.3)
const CAM_R_TO: float = 51.2     # the inner end, clear of the lip wall (r 48)
const CAM_H: float = 0.6         # over the probed deck: ground height
## Along the lake: 309 deg is 16 m out, past the second and third platforms.
const LOOK_DEG: float = 309.0
const LOOK_R_FROM: float = 53.6
const LOOK_R_TO: float = 51.8
const LOOK_H: float = -1.7       # ~8 deg down: lava fills about two thirds of the frame
const FOV: float = 58.0          # vertical; the portrait frame's width is ~35 deg
## The one prisoner the match needs, parked on clear S1 deck, far out of view.
const PARK_DEG: float = 30.0
const PARK_R: float = 52.0


func bots() -> int:
	return 1


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty():
		return false
	for index: int in runners.size():
		if runners[index].controller == null:
			return false
	for index: int in runners.size():
		var at: Vector3 = LIB.ring_point(PARK_DEG + 3.0 * float(index), PARK_R, 0.1)
		drive(runners[index], [
			{"do": "place", "at": at, "face": LIB.tangent_at(PARK_DEG)},
			{"do": "hold", "seconds": 60.0},
		], index, "ClipLavaPark%d" % index)
	say("polish_lava: %d parked at %.0f deg" % [runners.size(), PARK_DEG])
	return true


## A slow eased truck along the bank, the look easing with it; never still.
func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var total: float = maxf(float(option("seconds", 11.2)), 0.1)
	var p: float = smoothstep(0.0, 1.0, clampf(elapsed() / total, 0.0, 1.0))
	camera().global_position = LIB.ring_point(BANK_DEG, lerpf(CAM_R_FROM, CAM_R_TO, p), CAM_H)
	camera().look_at(LIB.ring_point(LOOK_DEG, lerpf(LOOK_R_FROM, LOOK_R_TO, p), LOOK_H), Vector3.UP)
	camera().fov = FOV
	camera().current = true
	return true
