class_name PS1Presentation
extends CanvasLayer
## The PS1 look, tuned here alone: the live camera's 3D drawn into a few-hundred-line SubViewport, shown
## nearest under the UI and cut to 5 bits a channel; vertices snapped, UVs affine. The Debug menu writes these live.

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
## How sharp textures stay: 1 picks mips as the window's resolution would, 0 as the low-res buffer would (blurrier).
@export_range(0.0, 1.0, 0.05) var texture_sharpness: float = 1.0:
	set(value):
		texture_sharpness = value
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

var _rect: TextureRect = null
var _material: ShaderMaterial = null
var _view: SubViewport = null
var _eye: Camera3D = null
var _window_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_free()
		return
	layer = -100
	process_priority = 1000
	var root: Window = get_tree().root
	_view = SubViewport.new()
	_view.world_3d = root.find_world_3d()
	_view.positional_shadow_atlas_size = root.positional_shadow_atlas_size
	_view.positional_shadow_atlas_16_bits = root.positional_shadow_atlas_16_bits
	_view.msaa_3d = root.msaa_3d
	_view.use_debanding = root.use_debanding
	_eye = Camera3D.new()
	_view.add_child(_eye)
	add_child(_view)
	_material = ShaderMaterial.new()
	_material.shader = QUANTISE
	_rect = TextureRect.new()
	_rect.texture = _view.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	_apply()


## Last in the frame: the low-res eye takes the live camera's pose and lens, so it never lags a frame.
func _process(_delta: float) -> void:
	var root: Window = get_tree().root
	if root.size != _window_size:
		_apply()
	if not enabled:
		return
	var camera: Camera3D = root.get_camera_3d()
	_rect.visible = camera != null
	if camera == null:
		return
	_eye.global_transform = camera.global_transform
	_eye.projection = camera.projection
	_eye.fov = camera.fov
	_eye.size = camera.size
	_eye.near = camera.near
	_eye.far = camera.far
	_eye.keep_aspect = camera.keep_aspect
	_eye.h_offset = camera.h_offset
	_eye.v_offset = camera.v_offset
	_eye.frustum_offset = camera.frustum_offset
	_eye.cull_mask = camera.cull_mask
	_eye.environment = camera.environment
	_eye.attributes = camera.attributes


func _apply() -> void:
	if _rect == null or not is_inside_tree():
		return
	var root: Window = get_tree().root
	_window_size = root.size
	root.disable_3d = enabled
	_rect.visible = enabled
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	if not enabled:
		RenderingServer.global_shader_parameter_set(&"ps1_snap_grid", Vector2.ZERO)
		RenderingServer.global_shader_parameter_set(&"ps1_affine", 0.0)
		RenderingServer.global_shader_parameter_set(&"ps1_mip_bias", 0.0)
		return
	var divisor: int = maxi(1, roundi(float(_window_size.y) / float(lines)))
	_view.size = Vector2i(maxi(1, roundi(float(_window_size.x) / float(divisor))), maxi(1, roundi(float(_window_size.y) / float(divisor))))
	var low: Vector2 = Vector2(_view.size)
	RenderingServer.global_shader_parameter_set(
			&"ps1_snap_grid", low / snap_strength if snap_strength > 0.0 else Vector2.ZERO)
	RenderingServer.global_shader_parameter_set(&"ps1_affine", affine_amount if affine else 0.0)
	RenderingServer.global_shader_parameter_set(&"ps1_mip_bias", -log(float(divisor)) / log(2.0) * texture_sharpness)
	_material.set_shader_parameter(&"low_size", low)
	_material.set_shader_parameter(&"levels", colour_levels)
	_material.set_shader_parameter(&"dither", 1.0 if dither else 0.0)
