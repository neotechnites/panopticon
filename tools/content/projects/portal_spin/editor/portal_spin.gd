@tool
extends Node

var _t: float = -1.0
var _mats: Array[ShaderMaterial] = []


func _process(delta: float) -> void:
	if _mats.is_empty():
		for n: Node in get_tree().edited_scene_root.find_children("*", "MeshInstance3D", true, false) if Engine.is_editor_hint() and get_tree().edited_scene_root else []:
			var m := n as MeshInstance3D
			if m.mesh == null:
				continue
			for s: int in m.mesh.get_surface_count():
				var mat := m.get_active_material(s) as ShaderMaterial
				if mat != null and mat.shader != null and mat.shader.resource_path.ends_with("portal_wave.gdshader"):
					_mats.append(mat)
	if _t < 0.0 and FileAccess.file_exists("res://spin.on"):
		_t = 0.0
	if _t >= 0.0:
		_t += delta
	for mat: ShaderMaterial in _mats:
		mat.set_shader_parameter(&"wave_spin", 0.8 if _t >= 0.0 else 0.0)
		mat.set_shader_parameter(&"spin_angle", maxf(_t, 0.0) * 0.8)
