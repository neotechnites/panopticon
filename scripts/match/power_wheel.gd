class_name PowerWheel
extends Control

## Stand-in until the diegetic readout: one ring, full when the held power is ready, draining over
## its run and filling back over its cooldown. Drawn from [RunnerPower]'s readout alone; delete with it.

const RING_WIDTH: float = 5.0
const SEGMENTS: int = 64
const BACKING: Color = Color(0.0, 0.0, 0.0, 0.55)
const TRACK: Color = Color(1.0, 1.0, 1.0, 0.18)
const FILL: Color = Color(1.0, 1.0, 1.0, 0.92)

## The viewed body's power, set by the HUD each tick; null shows nothing.
var power: RunnerPower = null


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## How full the ring is: the run left while active, else the share of the cooldown done.
func get_fraction() -> float:
	if power == null:
		return 0.0
	if power.is_active():
		return power.get_active_fraction()
	return 1.0 - power.get_cooldown_fraction()


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - RING_WIDTH
	draw_arc(centre, radius, 0.0, TAU, SEGMENTS, BACKING, RING_WIDTH + 3.0, true)
	draw_arc(centre, radius, 0.0, TAU, SEGMENTS, TRACK, RING_WIDTH, true)
	var fraction: float = get_fraction()
	if fraction > 0.0:
		draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, SEGMENTS, FILL, RING_WIDTH, true)
