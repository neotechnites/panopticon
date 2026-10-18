extends "res://tools/capture/stages/stage.gd"

## hell_pullback: short 4 L3. Ryan: "slow zoom out shot of the old hell map" (the hell ring, map 1, a live bot match).
## [code]--stage=hell_pullback --shot=pit_orbit --bots=3 --seed=20261017[/code]; [event] pullback at the start and the end of the move.

# The lens opens low over the S1 deck (deg 20, r 40, 13 m up, the open shaft inside the r ~47 wall) looking down on
# the runners crossing 32 deg r 51, and cranes up and back to polish_aerial's high spot (deg 0, r 34, 40 m up) looking
# 12 m past the pit's centre: the deck, the tower, the pit and the far gallery come into frame as it rises.
# fov 50 -> 70 (vertical). The move is eased at both ends with a linear middle, so it never reads as a still.
# Dials (--set=): from_t (1.0 s, the move starts), move (8.0 s), fov_from (50), fov_to (70).

const START := [20.0, 40.0, 13.0]
const START_LOOK := [32.0, 51.0, 0.5]
const END := [0.0, 34.0, 40.0]
const END_LOOK := [180.0, 12.0, -4.0]
const LINEAR_SHARE: float = 0.5

var _said: Array[bool] = [false, false]


func bots() -> int:
	return 3


func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var from_t: float = float(option("from_t", 1.0))
	var s: float = clampf((elapsed() - from_t) / float(option("move", 8.0)), 0.0, 1.0)
	var u: float = LINEAR_SHARE * s + (1.0 - LINEAR_SHARE) * smoothstep(0.0, 1.0, s)
	var pos: Vector3 = LIB.ring_point(lerpf(START[0], END[0], u), lerpf(START[1], END[1], u), lerpf(START[2], END[2], u))
	var near_look: Vector3 = LIB.ring_point(START_LOOK[0], START_LOOK[1], START_LOOK[2])
	var far_look: Vector3 = LIB.ring_point(END_LOOK[0], END_LOOK[1], END_LOOK[2])
	camera().global_position = pos
	camera().look_at(near_look.lerp(far_look, u), Vector3.UP)
	camera().fov = lerpf(float(option("fov_from", 50.0)), float(option("fov_to", 70.0)), u)
	camera().current = true
	for i: int in 2:
		if not _said[i] and ((i == 0 and s > 0.0) or (i == 1 and s >= 1.0)):
			_said[i] = true
			print("[event] %6.2f  pullback  %s" % [elapsed(), "start" if i == 0 else "end"])
			_report_sight(pos, near_look.lerp(far_look, u))
	return true


## The smoke's sight check: what the ray from the lens to the look point meets first.
func _report_sight(from: Vector3, to: Vector3) -> void:
	var space := camera().get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	say("sight %.1f m to the look point: %s" % [from.distance_to(to), "clear" if hit.is_empty() else "%s at %.1f m" % [hit["collider"].name, from.distance_to(hit["position"])]])
