class_name CharacterLight
extends RefCounted
## How a map's suns light the players: painted colour x floor in shade, up to x full-sun level in sun.
## A map absent from [constant BY_MAP] keeps the unshaded bodies it always had.

## Map id -> [shade level, full-sun level], as on-screen multiples of the painted colour.
const BY_MAP: Dictionary[StringName, Vector2] = {&"forest": Vector2(0.78, 1.10)}

const SHADER: Shader = preload("res://characters/materials/character_light.gdshader")
const FADE_SHADER: Shader = preload("res://characters/materials/character_light_fade.gdshader")

## Faces turned from a sun still take this much of it.
const WRAP: float = 0.5

## On-screen multiple of the painted colour in shade; 1.0 when the map is not lit.
var floor_level: float = 1.0
## On-screen multiple the suns add on top of the floor at full strength.
var lift: float = 0.0
## Scales the wrapped facing term so an upright body facing a sun gets all of it.
var facing_gain: float = 0.0
## The strongest sun's luminous energy: a patch is one sun through the leaves, so that sun alone gives the full lift.
var sun_energy: float = 1.0

var _cache: Dictionary[int, ShaderMaterial] = {}


## The lighting [param arena] gives its players: its map's levels, the gain solved from its suns.
static func for_arena(arena: Node) -> CharacterLight:
	var light: CharacterLight = CharacterLight.new()
	if arena == null:
		return light
	var levels: Vector2 = Vector2.ONE
	for map: MapDefinition in MapCatalog.all():
		if map.scene_path == arena.scene_file_path and BY_MAP.has(map.id):
			levels = BY_MAP[map.id]
	if levels == Vector2.ONE:
		return light
	var energy: float = 0.0
	var facing: float = 0.0
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = node as DirectionalLight3D
		if not sun.visible:
			continue
		var linear: Color = sun.light_color.srgb_to_linear()
		var e: float = sun.light_energy * (0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b)
		var frame: Transform3D = sun.global_transform if sun.is_inside_tree() else sun.transform
		var toward: Vector3 = frame.basis.z.normalized()
		energy = maxf(energy, e)
		facing = maxf(facing, e * maxf(Vector2(toward.x, toward.z).length(), WRAP))
	if energy <= 0.0:
		return light
	light.floor_level = levels.x
	light.lift = levels.y - levels.x
	light.sun_energy = energy
	# An upright body faces a sun at its elevation, so that facing reaches the full-sun level.
	light.facing_gain = energy / facing
	return light


## True when this map lights its players at all.
func is_lit() -> bool:
	return lift > 0.0


## [param material] lit by the map's suns, or [param material] itself on an unlit map.
func apply(material: Material) -> Material:
	var base: BaseMaterial3D = material as BaseMaterial3D
	if not is_lit() or base == null:
		return material
	var key: int = base.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var lit: ShaderMaterial = ShaderMaterial.new()
	var fading: bool = base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	lit.shader = FADE_SHADER if fading else SHADER
	# A self-lit (team) surface's painted colour is its glow: that is what reads on it today.
	var painted: Color = base.albedo_color
	if base.emission_enabled:
		painted = base.emission * base.emission_energy_multiplier
		painted.a = base.albedo_color.a
	lit.set_shader_parameter(&"albedo_color", painted)
	if base.albedo_texture != null:
		lit.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	lit.set_shader_parameter(&"light_floor", floor_level)
	lit.set_shader_parameter(&"light_lift", lift)
	lit.set_shader_parameter(&"light_facing_gain", facing_gain)
	lit.set_shader_parameter(&"light_sun_energy", sun_energy)
	lit.set_shader_parameter(&"light_wrap", WRAP)
	_cache[key] = lit
	return lit

