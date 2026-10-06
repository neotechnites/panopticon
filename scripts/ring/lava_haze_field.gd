@tool
class_name LavaHazeField
extends MeshInstance3D

## The crack's heat haze over a whole lava body: one mesh of [LavaHaze] panels at [member panels],
## scaled by [member panel_scale], drawn with the crack's material (its rise height scaled to match).

## One panel per entry: x, y, z of its foot on the lava, w its yaw in radians.
@export var panels: PackedVector4Array = PackedVector4Array()
## Size against the crack's 2.4 x 3 m panel.
@export_range(0.25, 4.0, 0.05) var panel_scale: float = 1.0
## Two crossed quads (a crack's X) per panel, or one, facing along its yaw (a falls face).
@export var crossed: bool = true

const CRACK_MATERIAL: ShaderMaterial = preload("res://maps/bentham_ring/materials/lava_haze_material.tres")

## One material per scale, shared by every field at that scale.
static var _materials: Dictionary = {}


func _ready() -> void:
	_dress()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_to_group(&"lava_haze")


## Built in the editor too, so the shimmer shows there; stripped for a save so the scene never stores it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		mesh = null
		material_override = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_dress()


func _dress() -> void:
	mesh = _build_mesh()
	material_override = material_for(panel_scale)


## The crack's material, its rise height scaled so a bigger panel rises at the same speed in metres.
static func material_for(scale_by: float) -> ShaderMaterial:
	if is_equal_approx(scale_by, 1.0):
		return CRACK_MATERIAL
	var key: int = roundi(scale_by * 100.0)
	if not _materials.has(key):
		var made: ShaderMaterial = CRACK_MATERIAL.duplicate() as ShaderMaterial
		made.set_shader_parameter(&"haze_height_metres", LavaHaze.HEIGHT_METRES * scale_by)
		_materials[key] = made
	return _materials[key]


func _build_mesh() -> ArrayMesh:
	var half: float = LavaHaze.WIDTH_METRES * 0.5 * panel_scale
	var top: float = LavaHaze.HEIGHT_METRES * panel_scale
	var quads: int = 2 if crossed else 1
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for panel: Vector4 in panels:
		var foot: Vector3 = Vector3(panel.x, panel.y, panel.z)
		for q: int in quads:
			var along: Vector3 = Vector3(cos(panel.w), 0.0, -sin(panel.w)).rotated(Vector3.UP, q * PI * 0.5) * half
			var base: int = vertices.size()
			vertices.append_array([foot - along + Vector3.UP * top, foot + along + Vector3.UP * top, foot + along, foot - along])
			uvs.append_array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var built: ArrayMesh = ArrayMesh.new()
	if indices.is_empty():
		return built
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built
