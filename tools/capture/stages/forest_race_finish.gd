extends "res://tools/capture/stages/forest_race.gd"

## forest_race_finish: short 9 L4's second shot, the finish of the same race (seed 20261017) off a fixed high lens behind
## the portal; Runner_2 runs in at 28.52 s (race_won), Runner_0 and Runner_1 1.5 and 3 m behind, and the lane empties.
## [code]--stage=forest_race_finish --shot=s3_open_lane --map=forest --bots=3 --shimmer=0 --look=social --seed=20261017[/code]
## Dials (--set=): lens (351.5,52.5,7.5 deg,r,h: probe_ring --los from it sees the lane 312-340 deg; the canopy wall hides
## 296-308, the portal 342), look (328,50.5,1.0), fov (70, vertical), push (0.25 m/s toward the look point on the flat,
## from push_from 23.0 s), fill (0.0, as forest_race_wide: the race POV it cuts against has none).

const LENS_AT: Vector3 = Vector3(351.5, 52.5, 7.5)
const LOOK_AT: Vector3 = Vector3(328.0, 50.5, 1.0)


func lens(_delta: float) -> bool:
	if camera() == null or not _started:
		return false
	var at: Vector3 = LIB.polar(String(option("lens", "")), LIB.ring_point(LENS_AT.x, LENS_AT.y, LENS_AT.z))
	var look: Vector3 = LIB.polar(String(option("look", "")), LIB.ring_point(LOOK_AT.x, LOOK_AT.y, LOOK_AT.z))
	var creep: float = float(option("push", 0.25)) * maxf(elapsed() - float(option("push_from", 23.0)), 0.0)
	camera().global_position = at + LIB.toward(at, look) * creep
	camera().look_at(look, Vector3.UP)
	camera().fov = float(option("fov", 70.0))
	camera().current = true
	var fill: OmniLight3D = camera().get_node_or_null(^"ClipFill") as OmniLight3D
	if fill != null:
		fill.light_energy = float(option("fill", 0.0))
	return true
