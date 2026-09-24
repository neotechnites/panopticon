extends RefCounted

## Map 1's chunk .glbs each import their own copies of the same materials; this
## saves one per glTF name ("HellRock.001" is HellRock) and points every chunk at it.

const CHUNK_PREFIX := "map_base_"
const MATERIAL_DIR := "res://maps/bentham_ring/materials/imported/"


## Swaps each mesh surface's material for the shared saved one; returns how many.
static func share(scene: Node, source_file: String) -> int:
	if not source_file.get_file().begins_with(CHUNK_PREFIX):
		return 0
	DirAccess.make_dir_recursive_absolute(MATERIAL_DIR)
	var shared: Dictionary = {}
	_walk(scene, shared)
	return shared.size()


static func _walk(node: Node, shared: Dictionary) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for i in mesh_instance.mesh.get_surface_count():
			var material := _shared(mesh_instance.mesh.surface_get_material(i), shared)
			if material != null:
				mesh_instance.mesh.surface_set_material(i, material)
	for child in node.get_children():
		_walk(child, shared)


static func _shared(material: Material, shared: Dictionary) -> Material:
	if material == null or material.resource_name.is_empty():
		return null
	var name := RegEx.create_from_string("\\.\\d+$").sub(material.resource_name, "")
	if shared.has(name):
		return shared[name]
	var path := MATERIAL_DIR + name + ".res"
	material.resource_name = name
	if ResourceSaver.save(material, path) != OK:
		push_warning("SHARED MATERIALS: could not save '%s'; chunk keeps its own." % path)
		return null
	material.take_over_path(path)
	shared[name] = material
	return material
