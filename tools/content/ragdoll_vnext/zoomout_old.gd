extends "res://tools/capture/stages/stage.gd"

## L3 of ragdoll_vnext at c1068a6b: the ring's own match playing while the lens cranes up and back off the tower.
## --shot=pit_orbit --stage=zoomout_old --bots=7 --seconds=12. Over the pit (r 34 -> 22) so it never meets rock.

const DEG: float = 95.0


func bots() -> int:
	return 7


func cast(_runners: Array[RunnerBrain]) -> bool:
	return true


func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var span: float = maxf(float(option("span", 11.0)), 1.0)
	var t: float = clampf((elapsed() - float(option("from", 0.8))) / span, 0.0, 1.0)
	var e: float = t * t * (3.0 - 2.0 * t)
	var a: Vector3 = LIB.ring_point(DEG, 34.0, 6.0)
	var b: Vector3 = LIB.ring_point(DEG, 22.0, 62.0)
	camera().global_position = a.lerp(b, e)
	camera().look_at(Vector3(0.0, LIB.DECK_Y + lerpf(9.0, -4.0, e), 0.0), Vector3.UP)
	camera().fov = lerpf(42.0, 78.0, e)
	camera().current = true
	return true
