extends SceneTree
## Headless proof the title screen frames and watches the tower.
##
## [codeblock]
## godot --headless --path . --script res://tools/check_title_screen.gd
## [/codeblock]
## Instantiates scenes/ui/main_menu.tscn, advances 2 s, then prints the tower's
## unprojected screen position and the eye's gaze dotted with the direction back
## to the camera (1.0 means it is looking straight at it). Exits 1 if either is
## missing or the eye is not looking at the camera.

const SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"
const ADVANCE_SECONDS: float = 2.0

## The project's configured window: project.godot's display/window/size. The
## headless script runner's own root Window is a fixed 64x64 regardless of
## that setting, so the scene is loaded into a SubViewport of this size
## instead -- otherwise the framing check would score the wrong aspect ratio.
const WINDOW_SIZE: Vector2i = Vector2i(1600, 900)


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("check_title_screen: could not load %s" % SCENE_PATH)
		quit(1)
		return

	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW_SIZE
	viewport.own_world_3d = true
	root.add_child(viewport)
	var menu: Control = packed.instantiate() as Control
	viewport.add_child(menu)

	var start_usec: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start_usec) / 1_000_000.0 < ADVANCE_SECONDS:
		await process_frame

	var camera: Camera3D = menu.get_node("World/MenuCamera") as Camera3D
	var tower: Node3D = menu.get_node("World/Tower") as Node3D
	var eye: WatchingEye = menu.get_node("World/Tower/Watcher") as WatchingEye
	if camera == null or tower == null or eye == null:
		push_error("check_title_screen: World/MenuCamera, World/Tower or World/Tower/Watcher missing")
		quit(1)
		return

	var screen: Vector2 = camera.unproject_position(tower.global_position)
	var norm_x: float = screen.x / float(WINDOW_SIZE.x)
	var norm_y: float = screen.y / float(WINDOW_SIZE.y)

	var to_camera: Vector3 = (camera.global_position - eye.global_position).normalized()
	var gaze_dot: float = eye.gaze_direction().dot(to_camera)

	print("tower screen x: %.3f" % norm_x)
	print("tower screen y: %.3f" % norm_y)
	print("eye gaze . to_camera: %.3f" % gaze_dot)

	var ok: bool = norm_x >= 0.70 and norm_x <= 0.86 and gaze_dot >= 0.9
	print("OK" if ok else "FAIL")
	quit(0 if ok else 1)
