@tool
class_name HeatShimmer
extends MeshInstance3D
## Hell's heat shimmer over lava: a clip-space quad warping the frame by hot air along each view ray.
## Draws in the editor viewport too; the CanvasLayer HUD and MacLift stay on top, unwarped.

const SHADER: Shader = preload("res://scripts/fx/heat_shimmer.gdshader")
const MASK: Texture2D = preload("res://maps/bentham_ring/materials/heat_mask.png")

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
@export_range(0.0, 2.0, 0.05) var look_down_boost: float = 0.8:
	set(value):
		look_down_boost = value
		_push()
## Faint warm lift multiplied into the frame; keeps blacks black.
@export_range(0.0, 0.3, 0.01) var warm_lift: float = 0.06:
	set(value):
		warm_lift = value
		_push()

var _material: ShaderMaterial = null


func _ready() -> void:
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
	# First in the transparent pass, so later see-through surfaces draw over it unwarped.
	_material.render_priority = Material.RENDER_PRIORITY_MIN
	_material.set_shader_parameter(&"noise_tex", tex)
	_material.set_shader_parameter(&"mask_tex", MASK)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = _material
	mesh = quad
	_push()


# The quad is built here, so the scene never stores it.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _push() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"strength", strength)
	_material.set_shader_parameter(&"speed", speed)
	_material.set_shader_parameter(&"look_down_boost", look_down_boost)
	_material.set_shader_parameter(&"warm_lift", warm_lift)
