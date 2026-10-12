@tool
extends Node

var _t: float = -1.0
var _mats: Array[ShaderMaterial] = []
var _centre: Vector3 = Vector3.ZERO
var _normal: Vector3 = Vector3.FORWARD


func _ready() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_setting("interface/editor/update_continuously", true)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _mats.is_empty():
		var root: Node = get_tree().edited_scene_root
		if root == null:
			return
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh == null:
				continue
			for s: int in m.mesh.get_surface_count():
				var mat := m.get_active_material(s) as ShaderMaterial
				if mat != null and mat.shader != null and mat.shader.resource_path.ends_with("portal_wave.gdshader"):
					_mats.append(mat)
					var local: AABB = m.get_aabb()
					_centre = (m.global_transform * local).get_center()
					var axis: int = 0 if local.size.x <= minf(local.size.y, local.size.z) else (1 if local.size.y <= local.size.z else 2)
					var nrm: Vector3 = m.global_transform.basis[axis]
					_normal = Vector3(nrm.x, 0.0, nrm.z).normalized()
					var bearing: float = atan2(_centre.z, _centre.x)
					if _normal.dot(Vector3(sin(bearing), 0.0, -cos(bearing))) < 0.0:
						_normal = -_normal
	if _mats.is_empty():
		return
	var cam: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if cam != null:
		var side: Vector3 = _normal.cross(Vector3.UP).normalized()
		cam.global_position = _centre + _normal * 8.0 + Vector3.UP * 0.4 + side * 0.6
		cam.look_at(_centre + Vector3.UP * 0.2, Vector3.UP)
	if _t < 0.0 and FileAccess.file_exists("res://spin.on"):
		_t = 0.0
	if _t >= 0.0:
		_t += delta
	for mat: ShaderMaterial in _mats:
		mat.set_shader_parameter(&"wave_spin", 0.8 if _t >= 0.0 else 0.0)
		mat.set_shader_parameter(&"spin_angle", maxf(_t, 0.0) * 0.8)
