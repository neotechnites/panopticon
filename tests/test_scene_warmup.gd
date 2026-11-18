extends TestCase
## The warm-up draws, in front of its own camera, one copy of every distinct visual of a bound scene and
## every sample its nodes offer, then finishes and frees them.


## A node that builds a visual at runtime offers it, as a power's shell or a blast does.
class Offerer extends Node3D:
	var offered: MeshInstance3D = null

	func warmup_samples() -> Array[Node3D]:
		offered = MeshInstance3D.new()
		offered.mesh = SphereMesh.new()
		return [offered]


var _scene: Node3D = null


func before_each() -> void:
	_scene = Node3D.new()
	add_child(_scene)


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.free()


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	_scene.add_child(node)
	return node


## In the warm-up's tree, visible, on a layer its camera draws and inside its view.
func _drawn(warmup: SceneWarmup, sample: VisualInstance3D) -> bool:
	if sample == null or not is_instance_valid(sample) or not warmup.is_ancestor_of(sample):
		return false
	var camera: Camera3D = warmup.get_camera_3d()
	return (sample.is_visible_in_tree() and camera != null and (camera.cull_mask & sample.layers) != 0
		and camera.is_position_in_frustum(sample.global_position))


func _meshes_under(warmup: SceneWarmup) -> int:
	var count: int = 0
	var stack: Array[Node] = [warmup]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			count += 1
	return count


func test_an_offered_sample_is_drawn_and_the_warm_up_finishes_and_frees_it() -> void:
	var offerer: Offerer = Offerer.new()
	_scene.add_child(offerer)
	var warmup: SceneWarmup = SceneWarmup.new(_scene)
	var finished: Array[bool] = [false]
	warmup.finished.connect(func() -> void: finished[0] = true)
	add_child(warmup)
	assert_true(_drawn(warmup, offerer.offered), "the offered sample is drawn by the warm-up's camera")
	for _frame: int in SceneWarmup.FRAMES + 1:
		await get_tree().process_frame
	assert_true(finished[0], "the warm-up finishes after its frames")
	await get_tree().process_frame
	assert_false(is_instance_valid(offerer.offered), "and frees what it drew")


func test_a_mesh_drawn_with_the_same_materials_is_sampled_once() -> void:
	var box: BoxMesh = BoxMesh.new()
	var red: StandardMaterial3D = StandardMaterial3D.new()
	var blue: StandardMaterial3D = StandardMaterial3D.new()
	_mesh(box, red)
	_mesh(box, red)
	_mesh(box, blue)
	var warmup: SceneWarmup = SceneWarmup.new(_scene)
	add_child(warmup)
	assert_eq_int(_meshes_under(warmup), 2, "one sample per distinct mesh and material, every one drawn")
	warmup.free()


func test_a_particle_copy_emits_so_its_shaders_compile() -> void:
	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.emitting = false
	_scene.add_child(sparks)
	var warmup: SceneWarmup = SceneWarmup.new(_scene)
	add_child(warmup)
	var copies: Array[Node] = warmup.find_children("*", "CPUParticles3D", true, false)
	assert_eq_int(copies.size(), 1, "the particles are sampled")
	if copies.size() == 1:
		assert_true((copies[0] as CPUParticles3D).emitting, "and the copy emits")
	warmup.free()
