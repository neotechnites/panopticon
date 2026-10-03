@tool
extends EditorScenePostImport

## Refilters an imported .glb's materials to nearest-with-mipmaps and mips any embedded texture.
## Textures from a home's textures/ PNGs stay linked to that file, so editing the PNG edits the model.

const SharedMaterials := preload("res://tools/import/shared_materials.gd")
## Surfaces whose glTF material is named here get the waving lava shader instead.
const WAVE_MATERIALS := [&"LavaRiver", &"LavaSea", &"LavaCrack"]
const LAVA_WAVE_SHADER := "res://maps/bentham_ring/materials/lava_wave.gdshader"
## Every finish portal's swirl gets the one rippling see-through shader: its glTF alpha is kept, its glow unboosted.
const PORTAL_WAVE_SHADER := "res://maps/bentham_ring/materials/portal_wave.gdshader"
const SEE_THROUGH_WAVE := {&"PortalGlow": PORTAL_WAVE_SHADER, &"ForestPortalSwirl": PORTAL_WAVE_SHADER, &"MarbleGlow": PORTAL_WAVE_SHADER}
## No torches on the ring any more: the lava itself carries that light, boosted here.
const LAVA_EMISSION_BOOST := 1.4
## Marble's stone is fully matte: no sheen, whatever roughness the .glb carries.
const MATTE_PREFIX := "res://maps/marble/"
## Every other surface draws through the PS1 shader (vertex snap, affine UVs) but these, whose
## BaseMaterial3Ds the game recolours at runtime (body tints, the eye's sclera).
const PS1_STANDARD := "res://scripts/fx/ps1_standard.gdshaderinc"
const PS1_KEEP_PREFIXES := ["res://characters/", "res://tower/models/eye.glb"]

const TEXTURE_PROPERTIES := [
	&"albedo_texture",
	&"normal_texture",
	&"emission_texture",
	&"roughness_texture",
]

var _texture_cache: Dictionary = {}
var _seen_materials: Dictionary = {}
var _wave_cache: Dictionary = {}
var _ps1_cache: Dictionary = {}
var _ps1_shaders: Dictionary = {}
var _ps1: bool = false
var _textures_mipped: int = 0
var _materials_refiltered: int = 0
var _matte: bool = false


func _post_import(scene: Node) -> Object:
	_texture_cache.clear()
	_seen_materials.clear()
	_wave_cache.clear()
	_ps1_cache.clear()
	_ps1 = not PS1_KEEP_PREFIXES.any(func(prefix: String) -> bool: return get_source_file().begins_with(prefix))
	_textures_mipped = 0
	_materials_refiltered = 0
	_matte = get_source_file().begins_with(MATTE_PREFIX)

	_walk(scene)
	SharedMaterials.share(scene, get_source_file())

	print("MIPMAP %s: %d textures gained mips, %d materials refiltered to NEAREST_WITH_MIPMAPS_ANISOTROPIC" % [
		get_source_file().get_file(), _textures_mipped, _materials_refiltered,
	])
	return scene


func _walk(node: Node) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null:
		_fix_material(mesh_instance.material_override)
		var surface_count := 0
		if mesh_instance.mesh != null:
			surface_count = mesh_instance.mesh.get_surface_count()
		for i in surface_count:
			_fix_material(mesh_instance.mesh.surface_get_material(i))
			_fix_material(mesh_instance.get_surface_override_material(i))
			var wave := _wave_material(mesh_instance.mesh.surface_get_material(i))
			if wave == null and _ps1:
				wave = _ps1_material(mesh_instance.mesh.surface_get_material(i))
			if wave != null:
				mesh_instance.mesh.surface_set_material(i, wave)
	for child in node.get_children():
		_walk(child)


func _fix_material(material: Material) -> void:
	var base := material as BaseMaterial3D
	if base == null:
		return
	var material_id := base.get_instance_id()
	if _seen_materials.has(material_id):
		return
	_seen_materials[material_id] = true

	for property in TEXTURE_PROPERTIES:
		var texture: Texture2D = base.get(property)
		var replacement := _mipped_texture(texture)
		if replacement != null:
			base.set(property, replacement)

	base.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	if _matte:
		base.roughness = 1.0
		base.metallic = 0.0
		base.metallic_specular = 0.0
	_materials_refiltered += 1


## Returns a mipmapped stand-in for `texture`, or null when nothing is needed.
## Conversions are cached by source texture instance, so one sheet shared by
## several surfaces is rebuilt once and every surface gets the same texture.
func _mipped_texture(texture: Texture2D) -> Texture2D:
	if texture == null or texture.resource_path.get_extension() == "png":
		return null
	var texture_id := texture.get_instance_id()
	if _texture_cache.has(texture_id):
		return _texture_cache[texture_id]

	var image: Image = texture.get_image()
	if image == null or image.has_mipmaps():
		return null

	image = image.duplicate() as Image
	if image.is_compressed():
		if image.decompress() != OK:
			push_warning("MIPMAP: could not decompress '%s'; left without mips." % texture.resource_name)
			return null
	if image.generate_mipmaps() != OK:
		push_warning("MIPMAP: could not generate mips for '%s'." % texture.resource_name)
		return null

	var mipped := ImageTexture.create_from_image(image)
	mipped.resource_name = texture.resource_name
	_texture_cache[texture_id] = mipped
	_textures_mipped += 1
	return mipped


## The lava wave ShaderMaterial standing in for a WAVE_MATERIALS surface's own
## (its mipped textures and factors carried over), or null for any other.
func _wave_material(material: Material) -> Material:
	var base := material as BaseMaterial3D
	var mat_name := StringName(base.resource_name) if base != null else &""
	if not WAVE_MATERIALS.has(mat_name) and not SEE_THROUGH_WAVE.has(mat_name):
		return null
	var material_id := base.get_instance_id()
	if _wave_cache.has(material_id):
		return _wave_cache[material_id]
	var wave := ShaderMaterial.new()
	wave.resource_name = base.resource_name
	wave.shader = load(SEE_THROUGH_WAVE.get(mat_name, LAVA_WAVE_SHADER))
	wave.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	wave.set_shader_parameter(&"albedo_color", base.albedo_color)
	wave.set_shader_parameter(&"emission_texture", base.emission_texture)
	wave.set_shader_parameter(&"emission_color", base.emission if base.emission_enabled else Color.BLACK)
	wave.set_shader_parameter(&"emission_energy", base.emission_energy_multiplier * (1.0 if SEE_THROUGH_WAVE.has(mat_name) else LAVA_EMISSION_BOOST))
	wave.set_shader_parameter(&"roughness", base.roughness)
	wave.set_shader_parameter(&"metallic", base.metallic)
	wave.set_shader_parameter(&"uv1_scale", base.uv1_scale)
	wave.set_shader_parameter(&"uv1_offset", base.uv1_offset)
	_wave_cache[material_id] = wave
	return wave


## The PS1 ShaderMaterial drawing what `material` drew, or null when it uses a feature the shader lacks.
func _ps1_material(material: Material) -> Material:
	var base := material as BaseMaterial3D
	if base == null or base.normal_enabled or base.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return null
	if not [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA,
			BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS].has(base.transparency):
		return null
	var material_id := base.get_instance_id()
	if _ps1_cache.has(material_id):
		return _ps1_cache[material_id]
	var modes: PackedStringArray = [["cull_back", "cull_front", "cull_disabled"][base.cull_mode]]
	if base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		modes.append("unshaded")
	if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		modes.append("depth_prepass_alpha")
	var see_through := base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	var code := "shader_type spatial;\nrender_mode %s;\n%s#include \"%s\"\n" % [
		", ".join(modes), "#define PS1_ALPHA\n" if see_through else "", PS1_STANDARD]
	if not _ps1_shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		_ps1_shaders[code] = shader
	var ps1 := ShaderMaterial.new()
	ps1.resource_name = base.resource_name
	ps1.shader = _ps1_shaders[code]
	var glow := base.emission_texture if base.emission_enabled else null
	ps1.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	ps1.set_shader_parameter(&"albedo_color", base.albedo_color)
	ps1.set_shader_parameter(&"use_vertex_color", base.vertex_color_use_as_albedo)
	ps1.set_shader_parameter(&"emission_texture", glow)
	ps1.set_shader_parameter(&"emission_color", base.emission if base.emission_enabled else Color.BLACK)
	ps1.set_shader_parameter(&"emission_energy", base.emission_energy_multiplier)
	ps1.set_shader_parameter(&"emission_multiply", glow != null and base.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
	ps1.set_shader_parameter(&"roughness", base.roughness)
	ps1.set_shader_parameter(&"metallic", base.metallic)
	ps1.set_shader_parameter(&"specular", base.metallic_specular)
	ps1.set_shader_parameter(&"uv1_scale", base.uv1_scale)
	ps1.set_shader_parameter(&"uv1_offset", base.uv1_offset)
	ps1.render_priority = base.render_priority
	_ps1_cache[material_id] = ps1
	return ps1
