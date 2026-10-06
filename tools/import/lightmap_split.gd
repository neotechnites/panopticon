extends RefCounted

## Hell's chunks for LightmapGI: rock unwrapped to UV2, lava split to a sibling mesh keeping its wave UV2.
## With res://.lightmap_bake present (the bake clone only) the lava is unwrapped too and glows as a lit emitter.

const CHUNK_PREFIX := "res://maps/bentham_ring/models/map_base_"
## Metres per lightmap texel, soft as the lava's glow; keep each chunk's .glb.import lightmap_texel_size equal (it forces the reimport).
const TEXEL := 0.6
const BAKE_FLAG := "res://.lightmap_bake"
## The stand-in's glow against the wave shader's emission_energy: the one knob the bake's brightness turns on.
const BAKE_GLOW := 4.0


## Splits and unwraps every art mesh under [param scene] when it is a hell chunk; returns how many.
static func split(scene: Node, source_file: String, wave_materials: Array) -> int:
	if not source_file.begins_with(CHUNK_PREFIX):
		return 0
	var baking := FileAccess.file_exists(BAKE_FLAG)
	var done := 0
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var rock := ArrayMesh.new()
		var lava := ArrayMesh.new()
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s)
			var is_lava := material != null and wave_materials.has(StringName(material.resource_name))
			var target := lava if is_lava else rock
			target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
			target.surface_set_material(target.get_surface_count() - 1, _stand_in(material) if is_lava and baking else material)
		rock.resource_name = mesh.resource_name
		if rock.get_surface_count() > 0:
			if rock.lightmap_unwrap(mi.transform, TEXEL) != OK:
				push_warning("LIGHTMAP: could not unwrap '%s'; it bakes no light." % mi.name)
			mi.mesh = rock
			mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			done += 1
		if lava.get_surface_count() > 0:
			if baking:
				lava.lightmap_unwrap(mi.transform, TEXEL)
			var sibling := MeshInstance3D.new()
			sibling.name = String(mi.name) + "Lava"
			sibling.mesh = lava
			sibling.transform = mi.transform
			sibling.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			sibling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.get_parent().add_child(sibling)
			sibling.owner = scene
	return done


## A lit StandardMaterial3D glowing as the wave shader does, which the baker reads where it cannot read an unshaded one.
static func _stand_in(material: Material) -> Material:
	var wave := material as ShaderMaterial
	if wave == null:
		return material
	var lit := StandardMaterial3D.new()
	lit.resource_name = material.resource_name
	lit.albedo_color = Color.BLACK
	lit.emission_enabled = true
	lit.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # colour x texture, as the wave shader; ADD lit the rock white
	lit.emission_texture = wave.get_shader_parameter(&"emission_texture")
	lit.emission = wave.get_shader_parameter(&"emission_color")
	lit.emission_energy_multiplier = float(wave.get_shader_parameter(&"emission_energy")) * BAKE_GLOW
	lit.uv1_scale = wave.get_shader_parameter(&"uv1_scale")
	lit.uv1_offset = wave.get_shader_parameter(&"uv1_offset")
	return lit
