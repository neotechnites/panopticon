class_name BrightnessPreview
extends Control

## A strip of grey steps, black to white, drawn the way the 3D scene will show
## them at [member brightness]: linear value times exposure, clipped, encoded.

## Linear grey of each step; the dark end is where a dim display loses detail.
const STEPS: PackedFloat32Array = [0.005, 0.01, 0.02, 0.04, 0.08, 0.16, 0.32, 0.64, 1.0]

## The exposure the strip previews. Mirrors [member GameSettings.brightness].
var brightness: float = 1.0:
	set(value):
		brightness = value
		queue_redraw()


func _draw() -> void:
	var step_width: float = size.x / STEPS.size()
	for i: int in STEPS.size():
		var grey: float = clampf(STEPS[i] * brightness, 0.0, 1.0)
		var shown: Color = Color(grey, grey, grey).linear_to_srgb()
		draw_rect(Rect2(i * step_width, 0.0, step_width, size.y), shown)
