class_name SceneWarmup
extends SubViewport

## Draws a bound scene's every distinct visual off screen in its world, so GL Compatibility compiles shaders under
## the loading cover. Runtime-built visuals are offered by [code]warmup_samples() -> Array[Node3D][/code].

## The warm-up has drawn its frames.
signal finished()

## Frames drawn before it counts: the first issues the draws, the next ones present them.
const FRAMES: int = 3
## Metres in front of the warm-up camera the samples stand, each scaled to about a metre.
const DEPTH_METRES: float = 3.0

var _samples: Array[Node3D] = []
var _frames_left: int = FRAMES
var _seen: Dictionary[String, bool] = {}


## Sample [param scene] now, as it stands; the drawing starts once this node is in the tree.
func _init(scene: Node) -> void:
	size = Vector2i(64, 64)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	var viewport: Viewport = scene.get_viewport()
	world_3d = viewport.find_world_3d() if viewport != null else null
	_samples = _collect(scene)


func _ready() -> void:
	var camera: Camera3D = Camera3D.new()
	camera.far = DEPTH_METRES * 4.0
	add_child(camera)
	camera.current = true
	var stand: Node3D = Node3D.new()
	stand.position = Vector3(0.0, 0.0, -DEPTH_METRES)
	camera.add_child(stand)
	for sample: Node3D in _samples:
		stand.add_child(sample)
		_fit(sample)
	_samples.clear()


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left > 0:
		return
	set_process(false)
	finished.emit()
	queue_free()


## One sample per distinct drawable under [param root], and every runtime sample its nodes offer.
func _collect(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node.has_method(&"warmup_samples"):
			for offered: Node3D in node.call(&"warmup_samples"):
				if offered is MeshInstance3D and not _first_of(offered as MeshInstance3D):
					offered.free()
				else:
					out.append(offered)
		var sample: Node3D = _sample_of(node)
		if sample != null:
			out.append(sample)
	return out


## A copy of [param node] that draws what it draws, or null for one already sampled or that draws nothing.
func _sample_of(node: Node) -> Node3D:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh == null or not _first_of(mesh_node):
			return null
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = mesh_node.mesh
		copy.material_override = mesh_node.material_override
		copy.material_overlay = mesh_node.material_overlay
		for surface: int in mesh_node.mesh.get_surface_count():
			copy.set_surface_override_material(surface, mesh_node.get_active_material(surface))
		return copy
	if node is GPUParticles3D or node is CPUParticles3D or node is SpriteBase3D or node is Label3D \
			or node is MultiMeshInstance3D:
		var duplicate: Node3D = node.duplicate(0) as Node3D
		for child: Node in duplicate.get_children():
			duplicate.remove_child(child)
			child.free()
		duplicate.visible = true
		# A particle system that is not emitting draws nothing, and compiles nothing.
		if duplicate is GPUParticles3D or duplicate is CPUParticles3D:
			duplicate.set(&"emitting", true)
		return duplicate
	return null


## True the first time a mesh is seen with these materials: one draw compiles them all.
func _first_of(mesh_node: MeshInstance3D) -> bool:
	if mesh_node.mesh == null:
		return true
	var key: String = "m%d|%s|%s" % [
		mesh_node.mesh.get_instance_id(), _id(mesh_node.material_override), _id(mesh_node.material_overlay)]
	for surface: int in mesh_node.mesh.get_surface_count():
		key += "|" + _id(mesh_node.get_active_material(surface))
	if _seen.has(key):
		return false
	_seen[key] = true
	return true


func _id(resource: Resource) -> String:
	return "0" if resource == null else str(resource.get_instance_id())


## Scale [param sample] to about a metre and centre it on the stand, so every one is in view.
func _fit(sample: Node3D) -> void:
	var visual: VisualInstance3D = sample as VisualInstance3D
	if visual == null:
		return
	var box: AABB = visual.get_aabb()
	var longest: float = maxf(box.get_longest_axis_size(), 0.01)
	sample.scale = Vector3.ONE / longest
	sample.position = -box.get_center() / longest
