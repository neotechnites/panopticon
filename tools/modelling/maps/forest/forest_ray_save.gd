extends SceneTree
## Saves forest_ray_build.py's unit shaft (a JSON file, first user arg) as an ArrayMesh .tres.

func _initialize() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	for v: Array in d["verts"]:
		verts.append(Vector3(v[0], v[1], v[2]))
		normals.append(Vector3(0.0, 0.0, 1.0))
	for c: Array in d["cols"]:
		cols.append(Color(c[0], c[1], c[2], c[3]))
	var idx := PackedInt32Array()
	for i: float in d["idx"]:
		idx.append(int(i))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var err: int = ResourceSaver.save(mesh, d["out"])
	quit(err)
