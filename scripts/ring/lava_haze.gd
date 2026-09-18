class_name LavaHaze
extends MeshInstance3D

## Heat shimmer over a lava tile: two crossed vertical quads sharing one
## [ArrayMesh] across every instance in the map.

## Width of each quad, and the span of the X in plan.
const WIDTH_METRES: float = 2.4

## How far the haze rises above the tile it stands on.
const HEIGHT_METRES: float = 2.0

## Built on first need, then handed to every instance.
static var _shared_mesh: ArrayMesh = null


## The crossed-quad mesh, built once. The same object for all instances.
static func shared_mesh() -> ArrayMesh:
	if _shared_mesh == null:
		_shared_mesh = _build_mesh()
	return _shared_mesh


static func _build_mesh() -> ArrayMesh:
	var half: float = WIDTH_METRES * 0.5
	var top: float = HEIGHT_METRES
	# Eight corners, twelve indices: an indexed surface, which is what every
	# counter that reads ARRAY_INDEX (the draw budget test among them) expects.
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(-half, top, 0.0), Vector3(half, top, 0.0),
		Vector3(half, 0.0, 0.0), Vector3(-half, 0.0, 0.0),
		Vector3(0.0, top, -half), Vector3(0.0, top, half),
		Vector3(0.0, 0.0, half), Vector3(0.0, 0.0, -half),
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	])
	var indices: PackedInt32Array = PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		4, 5, 6, 4, 6, 7,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


func _ready() -> void:
	mesh = shared_mesh()
	material_override = preload("res://scenes/ring/lava_haze_material.tres")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_to_group(&"lava_haze")
