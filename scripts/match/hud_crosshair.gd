class_name HudCrosshair
extends Control

## The crosshair: four short arms round an open centre, a dark line with a thin light edge so it
## reads on every map. Drawn in whole pixels, no anti-aliasing, at the centre of this Control.

## Sizes are in pixels of a 1080-line screen and scale with the window.
const REFERENCE_HEIGHT: float = 1080.0

## Length of each arm, from the end of the gap outward.
@export_range(1.0, 40.0, 1.0) var arm_length: float = 7.0
## Open space between the aim point and the inner end of each arm.
@export_range(0.0, 20.0, 1.0) var gap: float = 4.0
## Width of each arm.
@export_range(1.0, 8.0, 1.0) var thickness: float = 2.0
## Light border round every arm, on each side.
@export_range(0.0, 4.0, 1.0) var edge_thickness: float = 1.0
## Arm colour: dark, so it reads on marble, ice and forest.
@export var line_color: Color = Color(0.04, 0.04, 0.05, 1.0)
## Edge colour: light, so it reads on hell.
@export var edge_color: Color = Color(0.93, 0.9, 0.78, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Pixels per reference pixel at the current window height.
func get_scale_unit() -> float:
	var viewport: Viewport = get_viewport()
	var height: float = viewport.get_visible_rect().size.y if viewport != null else REFERENCE_HEIGHT
	return height / REFERENCE_HEIGHT


## The aim point, in the viewport's canvas coordinates.
func get_screen_centre() -> Vector2:
	return get_global_transform_with_canvas() * (size * 0.5)


func _px(value: float, unit: float) -> int:
	return maxi(roundi(value * unit), 1) if value > 0.0 else 0


func _draw() -> void:
	var unit: float = get_scale_unit()
	var arm: int = _px(arm_length, unit)
	var hole: int = _px(gap, unit)
	var width: int = _px(thickness, unit)
	var edge: int = _px(edge_thickness, unit)
	# Snapped so an even width straddles the centre pixel line and an odd one covers it.
	var centre: Vector2i = Vector2i(floori(size.x * 0.5), floori(size.y * 0.5))
	var low: int = -(width / 2)
	var rects: Array[Rect2] = [
		Rect2(centre.x + low, centre.y - hole - arm, width, arm),
		Rect2(centre.x + low, centre.y + hole + (width % 2), width, arm),
		Rect2(centre.x - hole - arm, centre.y + low, arm, width),
		Rect2(centre.x + hole + (width % 2), centre.y + low, arm, width),
	]
	if edge > 0:
		for rect: Rect2 in rects:
			draw_rect(rect.grow(edge), edge_color, true, -1.0, false)
	for rect: Rect2 in rects:
		draw_rect(rect, line_color, true, -1.0, false)
