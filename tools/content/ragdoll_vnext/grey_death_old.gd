extends SceneTree

## L2 of ragdoll_vnext, run at the pre-ragdoll ref c1068a6b: one runner on plain grey plays the old "Death" clip.
## godot --path <old worktree> --script res://tools/content/ragdoll_vnext/grey_death_old.gd -- (window sizes the frame)

const RUNNER_SCENE := "res://characters/bots/ring_runner.tscn"
const DIE_AT: float = 1.2
const END_AT: float = 6.0
const GREY := Color(0.5, 0.5, 0.52)
const FLOOR := Color(0.36, 0.36, 0.37)

var _clock: float = 0.0
var _body: Node3D = null
var _dead: bool = false


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GREY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400.0, 400.0)
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FLOOR
	mat.roughness = 1.0
	plane.material_override = mat
	floor_body.add_child(plane)
	world.add_child(floor_body)
	_body = (load(RUNNER_SCENE) as PackedScene).instantiate() as Node3D
	world.add_child(_body)
	_body.position = Vector3(0.0, 0.05, 0.0)
	_body.rotation.y = deg_to_rad(150.0)
	var camera := Camera3D.new()
	camera.fov = 40.0
	var look := Vector3(-0.1, 0.7, 0.3)
	var eye := look + Vector3(0.7, 1.9, 4.6)
	world.add_child(camera)
	camera.transform = Transform3D(Basis.looking_at(look - eye), eye)
	camera.current = true


func _process(delta: float) -> bool:
	_clock += delta
	if not _dead and _clock >= DIE_AT and _body != null:
		_dead = true
		_body.emit_signal(&"died")
		print("[rs] %.2f died" % _clock)
	return _clock >= END_AT
