@tool
extends EditorScenePostImport

## Refilters an imported .glb's materials to nearest-with-mipmaps and mips any embedded texture.
## Textures from a home's textures/ PNGs stay linked to that file, so editing the PNG edits the model.

const SharedMaterials := preload("res://tools/import/shared_materials.gd")
## Surfaces whose glTF material is named here get the waving lava shader instead.
const WAVE_MATERIALS := [&"LavaRiver", &"LavaSea", &"LavaCrack"]
const LAVA_WAVE_SHADER := "res://maps/bentham_ring/materials/lava_wave.gdshader"

const TEXTURE_PROPERTIES := [
	&"albedo_texture",
	&"normal_texture",
	&"emission_texture",
	&"roughness_texture",
]

var _texture_cache: Dictionary = {}
var _seen_materials: Dictionary = {}
var _wave_cache: Dictionary = {}
var _textures_mipped: int = 0
var _materials_refiltered: int = 0


func _post_import(scene: Node) -> Object:
	_texture_cache.clear()
	_seen_materials.clear()
	_wave_cache.clear()
	_textures_mipped = 0
	_materials_refiltered = 0

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
	if base == null or not WAVE_MATERIALS.has(StringName(base.resource_name)):
		return null
	var material_id := base.get_instance_id()
	if _wave_cache.has(material_id):
		return _wave_cache[material_id]
	var wave := ShaderMaterial.new()
	wave.resource_name = base.resource_name
	wave.shader = load(LAVA_WAVE_SHADER)
	wave.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	wave.set_shader_parameter(&"albedo_color", base.albedo_color)
	wave.set_shader_parameter(&"emission_texture", base.emission_texture)
	wave.set_shader_parameter(&"emission_color", base.emission if base.emission_enabled else Color.BLACK)
	wave.set_shader_parameter(&"emission_energy", base.emission_energy_multiplier)
	wave.set_shader_parameter(&"roughness", base.roughness)
	wave.set_shader_parameter(&"metallic", base.metallic)
	wave.set_shader_parameter(&"uv1_scale", base.uv1_scale)
	wave.set_shader_parameter(&"uv1_offset", base.uv1_offset)
	_wave_cache[material_id] = wave
	return wave
