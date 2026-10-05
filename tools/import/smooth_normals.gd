extends RefCounted

## Characters shade smooth: every vertex takes the angle-weighted mean of the face normals meeting at its position.
## Done at import, so the .glb and its .blend stay as authored.

const HOME := "res://characters/"
const SNAP := 10000.0


## Smooths every mesh under [param scene] when it comes from the characters' home; returns how many.
static func smooth(scene: Node, source_file: String) -> int:
	if not source_file.begins_with(HOME):
		return 0
	var done := 0
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		if mesh != null and mesh.get_blend_shape_count() == 0 and _smooth_mesh(mesh):
			done += 1
	return done


static func _smooth_mesh(mesh: ArrayMesh) -> bool:
	var sums: Dictionary = {}
	var surfaces: Array = []
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if normals.size() != verts.size() or index.is_empty():
			return false
		for t in range(0, index.size(), 3):
			for corner in 3:
				var at := index[t + corner]
				var a := verts[index[t + (corner + 1) % 3]] - verts[at]
				var b := verts[index[t + (corner + 2) % 3]] - verts[at]
				if a.is_zero_approx() or b.is_zero_approx():
					continue
				var key := Vector3i((verts[at] * SNAP).round())
				sums[key] = sums.get(key, Vector3.ZERO) + normals[at] * a.angle_to(b)
		surfaces.append([arrays, mesh.surface_get_material(s), mesh.surface_get_name(s), mesh.surface_get_format(s)])
	for surface: Array in surfaces:
		var verts: PackedVector3Array = surface[0][Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = surface[0][Mesh.ARRAY_NORMAL]
		for i in verts.size():
			var mean: Vector3 = sums.get(Vector3i((verts[i] * SNAP).round()), Vector3.ZERO)
			if not mean.is_zero_approx():
				normals[i] = mean.normalized()
		surface[0][Mesh.ARRAY_NORMAL] = normals
	mesh.clear_surfaces()
	for s in surfaces.size():
		var flags: int = surfaces[s][3] & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s][0], [], {}, flags)
		mesh.surface_set_material(s, surfaces[s][1])
		mesh.surface_set_name(s, surfaces[s][2])
	return true
