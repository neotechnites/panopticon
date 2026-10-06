class_name CharacterLight
extends RefCounted
## How a map lights the players: its [CharacterFit], worn as one shader on every body surface.
## A scene absent from [constant FITS] keeps the bodies as authored.

## Map scene -> its fit.
const FITS: Dictionary[String, String] = {
	"res://maps/bentham_ring/bentham_ring.tscn": "res://maps/bentham_ring/bentham_ring_character_fit.tres",
	"res://maps/forest/forest.tscn": "res://maps/forest/forest_character_fit.tres",
	"res://maps/forest/forest_green.tscn": "res://maps/forest/forest_green_character_fit.tres",
	"res://maps/marble/marble.tscn": "res://maps/marble/marble_character_fit.tres",
	"res://maps/ice/ice.tscn": "res://maps/ice/ice_character_fit.tres",
}

const SHADER: Shader = preload("res://characters/materials/character_light.gdshader")
const FADE_SHADER: Shader = preload("res://characters/materials/character_light_fade.gdshader")

## The ground dapple shader's values the players share.
const DAPPLE_PARAMS: Array[StringName] = [&"dapple_metres", &"dapple_strength", &"dapple_light", &"fleck_strength", &"fleck_bias", &"sway", &"sway_speed", &"dapple_top", &"dapple_top_fade", &"dapple_mean"]

## Faces turned from a sun still take this much of it.
const SUN_WRAP: float = 0.5
## Where [method apply] keeps the material it dressed, for [method base_of].
const BASE_META: StringName = &"character_light_base"

## The standing map's levers; null on a map that does not light its players.
var fit: CharacterFit = null
## The arena's axis in the ground plane: the light's "toward the tower" points at it.
var axis: Vector2 = Vector2.ZERO
## Scales the wrapped facing term so an upright body facing a sun gets all of it.
var sun_facing_gain: float = 0.0
## Toward the map's first two suns (world), where the dapple is read for the body's own level.
var suns: Array[Vector3] = []
## The strongest sun's luminous energy: a patch is one sun through the leaves, so that sun alone gives the full lift.
var sun_energy: float = 1.0

var _cache: Dictionary[int, ShaderMaterial] = {}


## The lighting [param arena] gives its players: its scene's fit, the sun gain solved from its suns.
static func for_arena(arena: Node) -> CharacterLight:
	var light: CharacterLight = CharacterLight.new()
	if arena == null or not FITS.has(arena.scene_file_path):
		return light
	light.fit = load(FITS[arena.scene_file_path]) as CharacterFit
	var arena_3d: Node3D = arena as Node3D
	if arena_3d != null and arena_3d.is_inside_tree():
		light.axis = Vector2(arena_3d.global_position.x, arena_3d.global_position.z)
	var energy: float = 0.0
	var facing: float = 0.0
	var suns: Array[Vector3] = []
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = node as DirectionalLight3D
		if not sun.visible:
			continue
		var linear: Color = sun.light_color.srgb_to_linear()
		var e: float = sun.light_energy * (0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b)
		var frame: Transform3D = sun.global_transform if sun.is_inside_tree() else sun.transform
		var toward: Vector3 = frame.basis.z.normalized()
		energy = maxf(energy, e)
		suns.append(toward)
		facing = maxf(facing, e * maxf(Vector2(toward.x, toward.z).length(), SUN_WRAP))
	light.suns = suns
	if energy > 0.0:
		light.sun_energy = energy
		# An upright body faces a sun at its elevation, so that facing reaches the full lift.
		light.sun_facing_gain = energy / facing
	return light


## True when this map lights its players at all.
func is_lit() -> bool:
	return fit != null


## The authored or tinted material [param material] was dressed from; [param material] itself when it is one.
static func base_of(material: Material) -> BaseMaterial3D:
	if material is ShaderMaterial and material.has_meta(BASE_META):
		return material.get_meta(BASE_META) as BaseMaterial3D
	return material as BaseMaterial3D


## [param material] lit as the map lights it, or [param material] itself on an unlit map.
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
	lit.set_meta(BASE_META, base)
	# A self-lit (team) surface's painted colour is its glow: that is what reads on it today.
	var painted: Color = base.albedo_color
	var paint: Color = fit.body
	if base.emission_enabled:
		painted = base.emission * base.emission_energy_multiplier
		painted.a = base.albedo_color.a
		paint = Color(fit.shirt, fit.shirt, fit.shirt)
		lit.set_shader_parameter(&"hue_keep", fit.shirt_hue)
	lit.set_shader_parameter(&"paint_level", Vector3(paint.r, paint.g, paint.b))
	lit.set_shader_parameter(&"albedo_color", painted)
	if base.albedo_texture != null:
		lit.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	lit.set_shader_parameter(&"shade_level", Vector3(fit.shade.r, fit.shade.g, fit.shade.b))
	lit.set_shader_parameter(&"light_level", Vector3(fit.light.r, fit.light.g, fit.light.b))
	lit.set_shader_parameter(&"light_from", fit.light_from)
	lit.set_shader_parameter(&"arena_axis", axis)
	lit.set_shader_parameter(&"light_wrap", fit.wrap)
	lit.set_shader_parameter(&"rim_level", fit.rim)
	lit.set_shader_parameter(&"sun_lift", fit.sun if sun_facing_gain > 0.0 else 0.0)
	lit.set_shader_parameter(&"sun_facing_gain", sun_facing_gain)
	lit.set_shader_parameter(&"sun_energy", sun_energy)
	lit.set_shader_parameter(&"sun_wrap", SUN_WRAP)
	_dress_dapple(lit)
	_cache[key] = lit
	return lit


## The ground's leaf dapple on [param lit]: the fit's texture, every other value read off the ground's shader.
func _dress_dapple(lit: ShaderMaterial) -> void:
	if fit.dapple == null:
		return
	lit.set_shader_parameter(&"dapple_on", true)
	lit.set_shader_parameter(&"dapple", fit.dapple)
	lit.set_shader_parameter(&"dapple_shade", fit.dapple_shade)
	if fit.dapple_shader != null:
		for param: StringName in DAPPLE_PARAMS:
			var value: Variant = RenderingServer.shader_get_parameter_default(fit.dapple_shader.get_rid(), param)
			if value != null:
				lit.set_shader_parameter(param, value)
	if not suns.is_empty():
		lit.set_shader_parameter(&"dapple_sun_a", suns[0])
		lit.set_shader_parameter(&"dapple_sun_b", suns[mini(1, suns.size() - 1)])
