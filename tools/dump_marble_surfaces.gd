extends SceneTree
## Dump every drawn surface of a scene headless: node path, its VisualInstance3D layers, and per
## surface the material name, albedo_color and vertex_color_use_as_albedo -- the one measurement
## that finds a surface rendering its tile untinted (Godot 4.7's glTF import drops
## vertex_color_use_as_albedo on a mesh's FIRST surface, so its COLOR_0 tint is lost).
##   godot --headless --path <project> --script res://tools/dump_marble_surfaces.gd -- --scene=res://maps/marble/marble.tscn

func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % name):
			return raw.substr(name.length() + 3)
	return fallback


func _initialize() -> void:
	var scene_path: String = _arg("scene", "res://maps/marble/marble.tscn")
	var packed: PackedScene = load(scene_path) as PackedScene
	var node: Node = packed.instantiate()
	_walk(node, "")
	node.free()
	quit(0)


func _walk(node: Node, path: String) -> void:
	var here: String = path + "/" + node.name
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		print("MESH %s layers=%d visible=%s surfaces=%d" % [here, mi.layers, str(mi.visible), mi.mesh.get_surface_count()])
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var desc: String = "none"
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat as StandardMaterial3D
				desc = "%s albedo=(%.3f,%.3f,%.3f) vcol=%s tex=%s" % [sm.resource_name, sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, str(sm.vertex_color_use_as_albedo), str(sm.albedo_texture != null)]
			elif mat != null:
				desc = "%s (%s)" % [mat.resource_name, mat.get_class()]
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var has_col: bool = arrays[Mesh.ARRAY_COLOR] != null
			print("  surf %d %s color0=%s" % [s, desc, str(has_col)])
	for child: Node in node.get_children():
		_walk(child, here)
