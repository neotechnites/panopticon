extends TestCase

## [code]scenes/ring/lava_crack.tscn[/code]: a boost pad whose only decoration is
## the refracting [LavaHaze] quad, shared by every crack in a map.

const CRACK_SCENE_PATH: String = "res://scenes/ring/lava_crack.tscn"

const PAD_FOOTPRINT: Vector3 = Vector3(2.5, 1.0, 2.5)
const HAZE_PATH: NodePath = ^"Haze"

## Two crossed quads, two triangles each, no index array.
const HAZE_SURFACES: int = 1
const HAZE_TRIANGLES: int = 4
const HAZE_VERTICES: int = 8


## The crack IS the pad -- same script, same mask, same footprint as
## [code]scenes/ring/demon_pad.tscn[/code]; only the decoration differs.
func test_lava_crack_is_a_boost_pad_with_the_pad_footprint() -> void:
	var crack: Node = _make_crack()
	add_child(crack)

	var pad: BoostPad = crack as BoostPad
	if not assert_not_null(pad, "the crack's root is a BoostPad"):
		return
	assert_vec3_almost_eq(
		pad.footprint_metres, PAD_FOOTPRINT, 1e-6, "with the demon pad's footprint",
	)
	assert_eq_int(pad.collision_layer, 0, "it is detected by nobody")
	assert_eq_int(pad.collision_mask, 1048577, "and watches the living and ghost layers")
	assert_false(pad.monitorable, "nothing queries it back")
	var shape: CollisionShape3D = pad.get_node_or_null(^"Shape") as CollisionShape3D
	if assert_not_null(shape, "and it has the detection shape the script sizes"):
		assert_not_null(shape.shape, "which _build_shape filled in on ready")


## One surface of four triangles, and every crack in a map draws it through the
## same [ShaderMaterial] object rather than a copy each.
func test_lava_crack_haze_is_one_surface_of_four_triangles_sharing_one_material() -> void:
	var first: Node = _make_crack()
	var second: Node = _make_crack()
	add_child(first)
	add_child(second)

	var haze: LavaHaze = first.get_node_or_null(HAZE_PATH) as LavaHaze
	var other: LavaHaze = second.get_node_or_null(HAZE_PATH) as LavaHaze
	if not assert_not_null(haze, "the crack carries a LavaHaze"):
		return
	if not assert_not_null(other, "and a second crack carries one too"):
		return

	var mesh: ArrayMesh = haze.mesh as ArrayMesh
	if not assert_not_null(mesh, "the haze has its ArrayMesh on ready"):
		return
	assert_eq_int(mesh.get_surface_count(), HAZE_SURFACES, "one surface")
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq_int(vertices.size(), HAZE_VERTICES, "two quads' eight corners")
	assert_eq_int(indices.size(), HAZE_TRIANGLES * 3, "four triangles, indexed")
	assert_true(haze.is_in_group(&"lava_haze"), "and it registers itself as haze")

	assert_same(other.mesh, mesh, "both cracks draw the one shared mesh")
	assert_not_null(haze.material_override, "the haze is drawn through a material")
	assert_same(
		other.material_override, haze.material_override,
		"and it is the ONE shared lava_haze_material.tres, not a copy each",
	)


func _make_crack() -> Node:
	return (load(CRACK_SCENE_PATH) as PackedScene).instantiate()
