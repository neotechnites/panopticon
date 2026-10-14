class_name CharacterLight
extends RefCounted
## How a map lights the players, OoT style: plain per-pixel materials its own lights and shadows reach, with its fit's ambient and fill.
## A scene absent from [constant FITS] keeps the bodies as authored.

## Map scene -> its fit.
const FITS: Dictionary[String, String] = {
	"res://maps/bentham_ring/bentham_ring.tscn": "res://maps/bentham_ring/bentham_ring_character_fit.tres",
	"res://maps/forest/forest.tscn": "res://maps/forest/forest_character_fit.tres",
	"res://maps/forest/forest_green.tscn": "res://maps/forest/forest_green_character_fit.tres",
	"res://maps/marble/marble.tscn": "res://maps/marble/marble_character_fit.tres",
	"res://maps/ice/ice.tscn": "res://maps/ice/ice_character_fit.tres",
	"res://maps/beach/beach.tscn": "res://maps/beach/beach_character_fit.tres",
	"res://hub/hub.tscn": "res://hub/hub_character_fit.tres",
}

const DAPPLE_SHADER: Shader = preload("res://characters/materials/character_dapple.gdshader")

## The ground dapple shader's values the players share.
const DAPPLE_PARAMS: Array[StringName] = [&"dapple_metres", &"dapple_strength", &"fleck_strength", &"fleck_bias", &"sway", &"sway_speed", &"dapple_top", &"dapple_top_fade", &"dapple_mean"]

## [member PrisonerAvatar.visual_layers]' two values: the owner-hidden layer 2 and the AI's layer 3.
const BODY_LAYERS: int = 2 | 4
## The fit's fill light, hung once in the arena.
const FILL_NAME: StringName = &"CharacterFill"

## Where [method apply] keeps the material it dressed, for [method base_of].
const BASE_META: StringName = &"character_light_base"

## The standing map's levers; null on a map that does not light its players.
var fit: CharacterFit = null
## Toward the map's first two suns (world), where the dapple is read.
var suns: Array[Vector3] = []

var _cache: Dictionary[int, Material] = {}


## The lighting [param arena] gives its players: its scene's fit with its fill hung, and its suns for the dapple.
static func for_arena(arena: Node) -> CharacterLight:
	var light: CharacterLight = CharacterLight.new()
	var scene: String = _scene_of(arena)
	if not FITS.has(scene):
		return light
	light.fit = load(FITS[scene]) as CharacterFit
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = node as DirectionalLight3D
		if sun.visible and sun.name != FILL_NAME:
			light.suns.append((sun.global_transform if sun.is_inside_tree() else sun.transform).basis.z.normalized())
	if light.fit.fill.get_luminance() > 0.0 and arena.get_node_or_null(NodePath(FILL_NAME)) == null:
		arena.add_child.call_deferred(_fill_of(light.fit))
	return light


## [param fit]'s fill: unshadowed, world-fixed, reaching the body layers alone.
static func _fill_of(fit: CharacterFit) -> DirectionalLight3D:
	var lamp: DirectionalLight3D = DirectionalLight3D.new()
	lamp.name = FILL_NAME
	var level: float = maxf(fit.fill.r, maxf(fit.fill.g, fit.fill.b))
	lamp.light_color = Color(fit.fill.r / level, fit.fill.g / level, fit.fill.b / level)
	lamp.light_energy = level
	lamp.light_cull_mask = BODY_LAYERS
	lamp.shadow_enabled = false
	lamp.basis = Basis.looking_at(-fit.fill_from.normalized(), Vector3.UP if absf(fit.fill_from.normalized().y) < 0.99 else Vector3.FORWARD)
	return lamp


## The scene [param arena] was authored in: its own, or its owner's when it is built in place (the hub).
static func _scene_of(arena: Node) -> String:
	var node: Node = arena
	while node != null and node.scene_file_path.is_empty():
		node = node.owner
	return "" if node == null else node.scene_file_path


## True when this map lights its players at all.
func is_lit() -> bool:
	return fit != null


## The authored or tinted material [param material] was dressed from; [param material] itself when it is one.
static func base_of(material: Material) -> BaseMaterial3D:
	if material != null and material.has_meta(BASE_META):
		return material.get_meta(BASE_META) as BaseMaterial3D
	return material as BaseMaterial3D


## [param material] lit as the map lights it, or [param material] itself on an unlit map.
func apply(material: Material) -> Material:
	var base: BaseMaterial3D = material as BaseMaterial3D
	if not is_lit() or base == null:
		return material
	var key: int = base.get_instance_id()
	if not _cache.has(key):
		_cache[key] = _standard(base)
	return _cache[key]


## The colour [param base] shows before light: its paint in the map's tint, a team shirt (self-lit) its team colour.
func _paint_of(base: BaseMaterial3D) -> Color:
	var paint: Color = base.albedo_color * fit.body
	if base.emission_enabled:
		paint = base.emission * fit.shirt
	paint.a = base.albedo_color.a
	return paint


## [param base] as a plain per-pixel Lambert StandardMaterial3D the map's lights reach, its ambient the fit's (the map's is tuned for its own materials).
## Sampled without mipmaps, so small painted detail (the lips) keeps its contrast at range instead of averaging into skin.
func _standard(base: BaseMaterial3D) -> BaseMaterial3D:
	var plain: BaseMaterial3D = base.duplicate() as BaseMaterial3D
	plain.set_meta(BASE_META, base)
	var paint: Color = _paint_of(base)
	plain.albedo_color = paint
	plain.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	plain.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	plain.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	plain.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	plain.vertex_color_use_as_albedo = false
	plain.disable_ambient_light = true
	plain.emission_enabled = true
	plain.emission = Color(paint.r * fit.ambient.r, paint.g * fit.ambient.g, paint.b * fit.ambient.b)
	plain.emission_energy_multiplier = 1.0
	plain.emission_texture = base.albedo_texture
	plain.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	if fit.dapple != null:
		plain.next_pass = _dapple_pass()
	return plain


## The map's leaf dapple as a multiply pass over a lit body, its values read off the ground's shader.
func _dapple_pass() -> ShaderMaterial:
	var leafy: ShaderMaterial = ShaderMaterial.new()
	leafy.shader = DAPPLE_SHADER
	leafy.set_shader_parameter(&"dapple", fit.dapple)
	leafy.set_shader_parameter(&"dapple_shade", fit.dapple_shade)
	if fit.dapple_shader != null:
		for param: StringName in DAPPLE_PARAMS:
			var value: Variant = RenderingServer.shader_get_parameter_default(fit.dapple_shader.get_rid(), param)
			if value != null:
				leafy.set_shader_parameter(param, value)
	if not suns.is_empty():
		leafy.set_shader_parameter(&"dapple_sun_a", suns[0])
		leafy.set_shader_parameter(&"dapple_sun_b", suns[mini(1, suns.size() - 1)])
	return leafy
