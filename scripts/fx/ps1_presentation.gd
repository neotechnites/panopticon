class_name PS1Presentation
extends CanvasLayer
## The PS1 look, the one place it is tuned: 3D drawn at a few hundred lines and scaled up nearest,
## vertices snapped, UVs affine, colour cut to 5 bits a channel. The Debug menu writes these live.

const QUANTISE: Shader = preload("res://scripts/fx/ps1_quantise.gdshader")
## Line counts the Debug menu offers.
const LINE_CHOICES: PackedInt32Array = [240, 270, 360]

@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply()
## Target 3D lines; the window is divided by the nearest whole number, so every low-res pixel is a whole square.
@export var lines: int = 240:
	set(value):
		lines = maxi(value, 1)
		_apply()
## Low-res pixels per vertex snap step; 0 turns the snap off.
@export_range(0.0, 4.0, 0.25) var snap_strength: float = 1.0:
	set(value):
		snap_strength = maxf(value, 0.0)
		_apply()
@export var affine: bool = true:
	set(value):
		affine = value
		_apply()
## How far UVs lean to affine when on: 1 is the full PS1 warp, lower keeps it subtle.
@export_range(0.0, 1.0, 0.05) var affine_amount: float = 0.35:
	set(value):
		affine_amount = value
		_apply()
@export var dither: bool = true:
	set(value):
		dither = value
		_apply()
## Steps per colour channel: 31 is 15-bit colour.
@export var colour_levels: float = 31.0:
	set(value):
		colour_levels = maxf(value, 1.0)
		_apply()

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _window_size: Vector2i = Vector2i.ZERO
var _scale: float = 1.0
var _restore_scale: float = 1.0
var _owning: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_free()
		return
	layer = -100
	_material = ShaderMaterial.new()
	_material.shader = QUANTISE
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	_apply()


## Follows the window's size, and takes the 3D scale back from anything that set it while on.
func _process(_delta: float) -> void:
	var root: Window = get_tree().root
	if root.size != _window_size or (enabled and not is_equal_approx(root.scaling_3d_scale, _scale)):
		if enabled and not is_equal_approx(root.scaling_3d_scale, _scale):
			_restore_scale = root.scaling_3d_scale
		_apply()


func _apply() -> void:
	if _rect == null or not is_inside_tree():
		return
	var root: Window = get_tree().root
	_window_size = root.size
	_rect.visible = enabled
	if not enabled:
		if _owning:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = _restore_scale
		_owning = false
		RenderingServer.global_shader_parameter_set(&"ps1_snap_grid", Vector2.ZERO)
		RenderingServer.global_shader_parameter_set(&"ps1_affine", 0.0)
		return
	var divisor: int = maxi(1, roundi(float(_window_size.y) / float(lines)))
	var low: Vector2 = Vector2(_window_size) / float(divisor)
	_scale = 1.0 / float(divisor)
	if not _owning:
		_restore_scale = root.scaling_3d_scale
		_owning = true
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
	root.scaling_3d_scale = _scale
	RenderingServer.global_shader_parameter_set(
			&"ps1_snap_grid", low / snap_strength if snap_strength > 0.0 else Vector2.ZERO)
	RenderingServer.global_shader_parameter_set(&"ps1_affine", affine_amount if affine else 0.0)
	_material.set_shader_parameter(&"low_size", low)
	_material.set_shader_parameter(&"levels", colour_levels)
	_material.set_shader_parameter(&"dither", 1.0 if dither else 0.0)
