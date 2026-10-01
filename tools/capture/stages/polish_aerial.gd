extends "res://tools/capture/stages/stage.gd"

## polish_aerial: shot 3 of the polish short, the L1 opener d. Ryan: "aerial shot of the hell map".
## [code]--map=bentham_ring --shot=pit_orbit --stage=polish_aerial --bots=7 --look=social[/code] (cut 1.2 s in, 4.5 s).

## High in the open shaft over the pit (wall r ~47 above the 31.5 gallery ceiling), clear of everything.
const START_DEG: float = 315.0
## A 40 deg arc: the far gallery slides from the S3 minefield toward the S2 lava river.
const END_DEG: float = 355.0
## Radius drifts in (a slight push) as it descends.
const START_R: float = 37.0
const END_R: float = 33.0
## Metres over the deck: y 58 -> 50, above the tower's crown (35.5) so it sits under the far gallery.
const START_H: float = 35.0
const END_H: float = 27.0
## Aim 12 m past the pit's centre at y 19 (~37 deg down): far gallery on top, tower mid, lava at its foot.
const LOOK_R: float = 12.0
const LOOK_H: float = -4.0
## Vertical fov: ~2..72 deg down spans the shaft wall over the far gallery to the lava at the tower's foot.
const FOV: float = 70.0
## Seconds of clip time the move spans (the take is in 1.2 + cut 4.5 + 1.0 tail).
const MOVE_SECONDS: float = 6.7
## Share of the move that is linear, so the eased ends never read as a still frame.
const LINEAR_SHARE: float = 0.4


func bots() -> int:
	return 7


func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var s: float = clampf(elapsed() / MOVE_SECONDS, 0.0, 1.0)
	var u: float = LINEAR_SHARE * s + (1.0 - LINEAR_SHARE) * smoothstep(0.0, 1.0, s)
	var deg: float = lerpf(START_DEG, END_DEG, u)
	var pos: Vector3 = LIB.ring_point(deg, lerpf(START_R, END_R, u), lerpf(START_H, END_H, u))
	camera().global_position = pos
	camera().look_at(LIB.ring_point(deg + 180.0, LOOK_R, LOOK_H), Vector3.UP)
	camera().fov = FOV
	return true
