@tool
extends Node
## One filmed editor take (ragdoll_short M2): the window fills the screen, the docks are scoped, the 3D camera is
## held on the prisoner; the Death clip plays once when res://go.on appears. Autoload of the scrubbed copy only.

const SCOPE := "res://characters/"
const EYE := Vector3(@EYE@)
const AT := Vector3(@AT@)
const FOV := @FOV@
const HOLD_S := 3.0

var _clock: float = 0.0
var _framed_at: float = -1.0
var _sent: bool = false
var _played: bool = false
var _navigated: bool = false
var _crisped: bool = false
var _plain: bool = false


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_clock += delta
	OS.low_processor_usage_mode = false
	_window()
	_docks()
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null or _clock < 2.0:
		return
	if _framed_at < 0.0:
		EditorInterface.set_main_screen_editor("3D")
		_framed_at = _clock
	if _clock - _framed_at > 0.5 and not _plain:
		_plain = _menus()
	var cam: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if cam != null:
		cam.fov = FOV
		cam.global_position = EYE
		cam.look_at(AT, Vector3.UP)
	if not _crisped:
		_crisped = _crisp(root)
	if not _sent and _clock - _framed_at > HOLD_S:
		_sent = true
		_write_ready()
	if not _played and FileAccess.file_exists("res://go.on"):
		_played = true
		var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			ap.play(&"Death")


func _write_ready() -> void:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var c: Control = vp.get_parent() as Control
	var r: Rect2 = c.get_global_rect() if c != null else Rect2()
	var win: Window = get_tree().root
	var f: FileAccess = FileAccess.open("res://ready.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"vx": int(r.position.x) + win.position.x, "vy": int(r.position.y) + win.position.y,
				"vw": int(r.size.x), "vh": int(r.size.y), "win": [win.position.x, win.position.y, win.size.x, win.size.y]}))
		f.close()


func _crisp(root: Node) -> bool:
	# As the v26/v27 void cuts drew him: linear sampling, no mipmaps, every surface of the one mesh.
	var mi: MeshInstance3D = root.find_child("Runner", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return false
	for s: int in mi.mesh.get_surface_count():
		var m: BaseMaterial3D = mi.get_active_material(s) as BaseMaterial3D
		if m == null:
			continue
		var d: BaseMaterial3D = m.duplicate() as BaseMaterial3D
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mi.set_surface_override_material(s, d)
	return true


func _window() -> void:
	var win: Window = get_tree().root
	var size: Vector2i = DisplayServer.screen_get_size(DisplayServer.SCREEN_PRIMARY)
	var pos: Vector2i = DisplayServer.screen_get_position(DisplayServer.SCREEN_PRIMARY)
	if win.borderless and win.size == size and win.position == pos:
		return
	win.mode = Window.MODE_WINDOWED
	win.min_size = Vector2i.ZERO
	win.borderless = true
	win.always_on_top = true
	win.size = size
	win.position = pos
	win.grab_focus()


func _docks() -> void:
	var fs: FileSystemDock = EditorInterface.get_file_system_dock()
	if not _navigated:
		_navigated = true
		fs.navigate_to_path(SCOPE)
	for t: Node in fs.find_children("*", "Tree", true, false):
		var top: TreeItem = (t as Tree).get_root()
		if top != null:
			for it: TreeItem in top.get_children():
				_scope(it)
	_hide_slot(EditorInterface.get_inspector())
	for t: Node in get_tree().root.find_children("*", "EditorToaster", true, false):
		(t as CanvasItem).visible = false


func _scope(it: TreeItem) -> void:
	var m: Variant = it.get_metadata(0)
	var path: String = m if m is String else ""
	var above: bool = path.ends_with("/") and path != SCOPE and SCOPE.begins_with(path)
	var keep: bool = above or (path != "" and path.begins_with(SCOPE))
	if it.visible != keep:
		it.visible = keep
	if (above or path == SCOPE) and it.collapsed:
		it.collapsed = false
	if above:
		for c: TreeItem in it.get_children():
			_scope(c)


func _hide_slot(c: Control) -> void:
	var n: Node = c
	while n != null and not (n is TabContainer):
		n = n.get_parent()
	var slot: Control = (n as Control) if n != null else c
	while slot != null:
		if slot.visible:
			slot.visible = false
		var p: Container = slot.get_parent() as Container
		if p == null:
			return
		for ch: Node in p.get_children():
			if ch is Control and (ch as Control).visible:
				return
		slot = p


func _menus() -> bool:
	# As v14's frame: no grid, no origin lines, no gizmos; nothing selected. The View menus' own toggles.
	EditorInterface.get_selection().clear()
	var hit: bool = false
	for pm: Node in EditorInterface.get_editor_main_screen().find_children("*", "PopupMenu", true, false):
		var p: PopupMenu = pm as PopupMenu
		for i: int in p.item_count:
			if p.get_item_text(i) in ["View Grid", "View Origin", "View Gizmos"]:
				hit = true
				if p.is_item_checked(i):
					p.id_pressed.emit(p.get_item_id(i))
	return hit
