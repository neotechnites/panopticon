@tool
class_name HeatShimmer
extends CanvasLayer
## Hell's level-wide heat shimmer: one full-screen pass warping the 3D frame with rising noise.
## Layer -1 sits under the HUD (1) and MacLift (100), so the crosshair stays sharp.

const SHADER: Shader = preload("res://scripts/fx/heat_shimmer.gdshader")
const LOOK_DOWN: StringName = &"look_down"

## Overall warp; 0 turns the effect off.
@export_range(0.0, 4.0, 0.05) var strength: float = 1.0:
	set(value):
		strength = value
		_push()
## Scroll rate of the rising noise.
@export_range(0.0, 4.0, 0.05) var speed: float = 1.0:
	set(value):
		speed = value
		_push()
## Extra warp when the camera looks straight down (added on top of strength).
@export_range(0.0, 2.0, 0.05) var look_down_boost: float = 0.8
## Faint warm lift multiplied into the frame; keeps blacks black.
@export_range(0.0, 0.3, 0.01) var warm_lift: float = 0.06:
	set(value):
		warm_lift = value
		_push()

var _material: ShaderMaterial = null
var _rect: ColorRect = null


func _ready() -> void:
	layer = -1
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 2
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"noise_tex", tex)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	_push()


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var down: float = 0.0
	if camera != null:
		down = clampf(camera.global_basis.z.y, 0.0, 1.0) * look_down_boost
	_material.set_shader_parameter(LOOK_DOWN, down)


func _push() -> void:
	if _material == null:
		return
	_rect.visible = strength > 0.0
	_material.set_shader_parameter(&"strength", strength)
	_material.set_shader_parameter(&"speed", speed)
	_material.set_shader_parameter(&"warm_lift", warm_lift)
