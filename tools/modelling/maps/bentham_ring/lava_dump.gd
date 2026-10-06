extends SceneTree

## Writes every LavaSea / LavaRiver / LavaCrack vertex of map_base_s1..s5.glb, in world space, to
## --out=<json>, for lava_light_layout.py.

func _initialize() -> void:
	var out_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var found: Dictionary = {}
	for chunk: String in ["s1", "s2", "s3", "s4", "s5"]:
		var scene: Node = (load("res://maps/bentham_ring/models/map_base_%s.glb" % chunk) as PackedScene).instantiate()
		_walk(scene, Transform3D.IDENTITY, chunk, found)
		scene.free()
	var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(found))
	quit(0)


func _walk(node: Node, parent: Transform3D, chunk: String, found: Dictionary) -> void:
	var xf: Transform3D = parent * (node as Node3D).transform if node is Node3D else parent
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null:
		for s: int in instance.mesh.get_surface_count():
			var material: Material = instance.mesh.surface_get_material(s)
			var name: String = material.resource_name if material != null else ""
			if not name.begins_with("Lava"):
				continue
			var points: Array = []
			for p: Vector3 in instance.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = xf * p
				points.append([snappedf(w.x, 0.01), snappedf(w.y, 0.01), snappedf(w.z, 0.01)])
			found["%s/%s" % [chunk, name]] = points
	for child: Node in node.get_children():
		_walk(child, xf, chunk, found)
