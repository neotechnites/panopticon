extends "res://tools/capture/stages/stage.gd"

## polish_portal: shot 5 of the polish short. Ryan: "slow zoom shot of the portal".
## Filmed with [code]--shot=portal --stage=polish_portal --bots=1 --look=social[/code], take 8.7 s (cut 1.2 s in, 7.5 s).

## The portal's centre: StartEnd/Portal at 345 deg r 52; its model stands y 23.0-27.0.
const PORTAL_DEG: float = 345.0
const PORTAL_R: float = 52.0
## Disc centre over the deck, read off the first take (it sat at 0.5 aimed at 1.53).
const DISC_H: float = 1.6
## Eye height over the deck, a player looking at it.
const EYE_H: float = 1.7
## Metres back down the pass-through axis: 19 frames portal, glow and motes; 8 lets the disc fill most of the width.
const FROM_D: float = 19.0
const TO_D: float = 8.0
## Vertical fov narrows with the dolly for a touch more push.
const FROM_FOV: float = 50.0
const TO_FOV: float = 43.0
## The push runs just past both ends of the cut so no frame of it is still.
const PUSH_FROM: float = 0.9
const PUSH_TO: float = 9.0
## Share of smoothstep in the ease; the rest is linear so the ends never stop dead.
const EASE_SHARE: float = 0.6
## Disc centre at 0.45 of the height: 0.05 above the middle.
const SCREEN_LIFT: float = 0.05
## The one prisoner parked across the ring, far from 345 deg.
const PARK_DEG: float = 165.0
const PARK_R: float = 52.0


func bots() -> int:
	return 1


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	drive(runners[0], [
		{"do": "place", "deg": PARK_DEG, "r": PARK_R, "h": 0.1},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipParkedDriver")
	return true


func lens(_delta: float) -> bool:
	var cam: Camera3D = camera()
	if cam == null:
		return false
	var t: float = clampf((elapsed() - PUSH_FROM) / (PUSH_TO - PUSH_FROM), 0.0, 1.0)
	var eased: float = lerpf(t, smoothstep(0.0, 1.0, t), EASE_SHARE)
	var d: float = lerpf(FROM_D, TO_D, eased)
	var fov: float = lerpf(FROM_FOV, TO_FOV, eased)
	var axis: Vector3 = LIB.tangent_at(PORTAL_DEG)
	var disc: Vector3 = LIB.ring_point(PORTAL_DEG, PORTAL_R, DISC_H)
	var eye: Vector3 = LIB.ring_point(PORTAL_DEG, PORTAL_R, EYE_H) - axis * d
	var look: Vector3 = disc + Vector3.DOWN * (2.0 * SCREEN_LIFT * tan(deg_to_rad(fov) * 0.5) * d)
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	if not cam.current:
		cam.current = true
	return true
