extends SceneTree
## Render the main menu's 3D backdrop -- no UI -- as social banner PNGs.
##
## Same scene, lights and camera the player sees behind the menu: every Control
## is hidden, World stays, and MenuCamera's orbit is frozen at t=0.5 s. One
## 3840x2160 master is rendered through a SubViewport (the masters are larger
## than the desktop, and a window cannot be) and every banner is a crop of it,
## so the horizontal framing is always the menu camera's own.
##
## Bands are placed by the eye rather than centred: a centred band of a tall
## shot cuts the eye off, and the eye is the picture.
##
##   --out=DIR   where the PNGs go (default the PC's brand folder)

const SCENE := "res://ui/main_menu.tscn"
const MASTER := Vector2i(3840, 2160)
const FREEZE_SECONDS := 0.5
## YouTube crops every banner to this centred slice on some devices.
const YT_SIZE := Vector2(2560.0, 1440.0)
const YT_SAFE := Vector2(1546.0, 423.0)

var _sub: SubViewport
var _cam: Camera3D


func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % name):
			return raw.substr(name.length() + 3)
	return fallback


func _initialize() -> void:
	var out_dir: String = _arg("out", "C:/Users/ddd/Desktop/panopticon-renders/brand")
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		push_error("menu_banner.gd could not load %s" % SCENE)
		quit(1)
		return
	var menu: Node = packed.instantiate()
	root.add_child(menu)

	_sub = SubViewport.new()
	_sub.size = MASTER
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.world_3d = root.find_world_3d()
	root.add_child(_sub)
	_cam = Camera3D.new()
	_sub.add_child(_cam)

	# Nothing added above is in the tree yet: _ready, and so the menu camera's
	# own placement, happens on the first idle frame.
	await _settle()

	for child in menu.get_children():
		if child is Control:
			(child as Control).hide()

	var menu_cam := menu.get_node("World/MenuCamera") as Camera3D
	menu_cam.set("_angle_degrees", menu_cam.get("degrees_per_second") * FREEZE_SECONDS)
	menu_cam.call("_apply")
	menu_cam.set_process(false)

	_cam.fov = menu_cam.fov
	_cam.near = menu_cam.near
	_cam.far = menu_cam.far
	_cam.global_transform = menu_cam.global_transform
	_cam.current = true

	var master: Image = await _grab()
	var eye := _screen_rect(menu.get_node("World/Tower/Watcher/Gaze/Model"))
	print("EYE %s" % eye)

	var wide: Rect2i = _band(eye, 3.0)
	_save(master.get_region(Rect2i(Vector2i.ZERO, MASTER)), MASTER, out_dir, "master_3840x2160")
	_save(master.get_region(Rect2i(Vector2i.ZERO, MASTER)), Vector2i(960, 540), out_dir, "banner_discord_960x540")
	_save(master.get_region(wide), Vector2i(1500, 500), out_dir, "banner_x_1500x500")
	_save(master.get_region(wide), Vector2i(3000, 1000), out_dir, "banner_bluesky_3000x1000")
	_save(master.get_region(_band(eye, 5.0)), Vector2i(1920, 384), out_dir, "banner_reddit_1920x384")
	_save(_youtube(master, eye), Vector2i(YT_SIZE), out_dir, "banner_youtube_2560x1440")
	quit(0)


func _settle() -> void:
	# Run the scene for FREEZE_SECONDS of wall clock: the eye turns to face the
	# camera at its own rate and the lights need a tick to light.
	var until: int = Time.get_ticks_msec() + int(FREEZE_SECONDS * 1000.0)
	for _i in 8:
		await process_frame
	while Time.get_ticks_msec() < until:
		await process_frame


func _grab() -> Image:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return _sub.get_texture().get_image()


## Screen rect of everything drawn under a node, in master pixels.
func _screen_rect(node: Node3D) -> Rect2:
	var rect := Rect2()
	var first := true
	for visual in _visuals(node):
		var aabb: AABB = visual.global_transform * visual.get_aabb()
		for i in 8:
			var point: Vector2 = _cam.unproject_position(aabb.get_endpoint(i))
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return rect


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D and (node as VisualInstance3D).visible:
		found.append(node as VisualInstance3D)
	for child in node.get_children():
		found.append_array(_visuals(child))
	return found


## A full-width band of the given aspect, with the eye 28% of the way down it.
func _band(eye: Rect2, aspect: float) -> Rect2i:
	var height: int = int(round(MASTER.x / aspect))
	var top: int = clampi(int(round(eye.get_center().y - height * 0.28)), 0, MASTER.y - height)
	return Rect2i(0, top, MASTER.x, height)


## The master scaled and laid on black so the eye and the tower head sit inside
## YouTube's centred safe area -- which is shorter than any crop of a 16:9 master
## can make them. The backdrop is black, so the seams never show.
func _youtube(master: Image, eye: Rect2) -> Image:
	var subject := Rect2(eye.position, eye.size).grow_individual(eye.size.x, eye.size.y * 0.15, eye.size.x, eye.size.y)
	var scale: float = minf(YT_SAFE.x / subject.size.x, YT_SAFE.y / subject.size.y) * 0.92
	var scaled: Image = master.get_region(Rect2i(Vector2i.ZERO, MASTER))
	scaled.resize(int(round(MASTER.x * scale)), int(round(MASTER.y * scale)), Image.INTERPOLATE_LANCZOS)

	var canvas := Image.create_empty(int(YT_SIZE.x), int(YT_SIZE.y), false, master.get_format())
	canvas.fill(Color.BLACK)
	var offset := Vector2i((YT_SIZE * 0.5 - subject.get_center() * scale).round())
	var window := Rect2i(-offset, Vector2i(YT_SIZE))
	var source: Rect2i = window.intersection(Rect2i(Vector2i.ZERO, scaled.get_size()))
	canvas.blit_rect(scaled, source, source.position + offset)
	print("YT scale=%.3f subject=%s offset=%s" % [scale, subject, offset])
	return canvas


func _save(image: Image, size: Vector2i, dir: String, name: String) -> void:
	if image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var path: String = "%s/%s.png" % [dir, name]
	var err: int = image.save_png(path)
	print("BANNER %s %dx%d err=%d" % [path, size.x, size.y, err])
