class_name StillShot
extends SceneTree
## Render ONE frame of a scene from a given camera pose and write it to a PNG.
##
## Why this exists: a subagent asked to change lighting, a material, a view model
## or a layout cannot see what it made. Left blind it iterates on arithmetic and
## waits for a human to say "still black" -- which cost roughly 300k tokens and
## three rounds on a single light. This gives that loop an eye.
##
## It must run on a machine with a real GPU and a desktop session; over SSH there
## is no OpenGL context and the engine dies. On Ryan's PC it is launched into the
## active console session by tools/shot.ps1.
##
## Pose comes from the command line, after a bare `--`, so no caller has to edit
## this file. Environment variables were tried first and do NOT survive into a
## Windows scheduled task, which is how this gets a GPU:
##   --scene=res://...   scene to load
##   --pos=x,y,z         camera position
##   --look=x,y,z        point to aim at
##   --out=C:/path.png   where to write

func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % name):
			return raw.substr(name.length() + 3)
	return fallback


func _parse(raw: String, fallback: Vector3) -> Vector3:
	var parts: PackedStringArray = raw.split(",")
	if parts.size() != 3:
		return fallback
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


var _scene_path: String = ""
var _out_path: String = ""
var _started: bool = false


## Parse only. Nothing added to the tree here has a global transform yet, so
## the scene and the camera wait for the first frame.
func _initialize() -> void:
	_scene_path = _arg("scene", "")
	_out_path = _arg("out", "")
	if _scene_path.is_empty() or _out_path.is_empty():
		push_error("shot.gd needs --scene= and --out=")
		quit(1)


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var packed: PackedScene = load(_scene_path) as PackedScene
	if packed == null:
		push_error("shot.gd could not load %s" % _scene_path)
		quit(1)
		return true
	root.add_child(packed.instantiate())
	var camera: Camera3D = build_camera(
		root, _parse(_arg("pos", ""), Vector3(0, 1.9, 44)), _parse(_arg("look", ""), Vector3.ZERO)
	)
	camera.current = true
	_capture(_out_path)
	return false


## A 100-degree camera under [param parent], standing at [param pos] and aimed
## at [param look]. Posed after add_child: a node outside the tree has no
## global transform to write and look_at refuses to run.
static func build_camera(parent: Node, pos: Vector3, look: Vector3) -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.fov = 100.0
	parent.add_child(camera)
	camera.global_position = pos
	if not look.is_equal_approx(pos):
		camera.look_at(look, Vector3.UP)
	return camera


func _capture(out_path: String) -> void:
	# Several frames, not one: lights, shadow maps and any _ready() wiring need a
	# tick or two to settle, and a single frame reliably captures the moment
	# before they do.
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png(out_path)
	print("SHOT %s %dx%d" % [out_path, image.get_width(), image.get_height()])
	quit(0)
