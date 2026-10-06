@tool
extends EditorPlugin
## Unattended LightmapGI bake: `-- --lmbake=res://scene.tscn` opens it, presses Bake Lightmaps, writes lmbake.done, quits.
## Godot exposes no bake call to scripts, so it drives the editor's own button and file dialog.

var _scene := ""
var _step := 0
var _wait := 0.0


func _enter_tree() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--lmbake="):
			_scene = raw.trim_prefix("--lmbake=")
	set_process(not _scene.is_empty())


func _process(delta: float) -> void:
	_wait += delta
	if _wait < 2.0 or EditorInterface.get_resource_filesystem().is_scanning():
		return
	_wait = 0.0
	_advance()


## One step of the bake, once the editor has stopped scanning.
func _advance() -> void:
	match _step:
		0:
			EditorInterface.open_scene_from_path(_scene)
		1:
			var root := EditorInterface.get_edited_scene_root()
			var found: Array[Node] = []
			if root != null:
				found = root.find_children("*", "LightmapGI", false, true)
			if found.is_empty():
				_finish("no LightmapGI in %s" % _scene)
				return
			EditorInterface.edit_node(found[0])
		2:
			_bake()
	_step += 1


func _bake() -> void:
	var button := _bake_button(EditorInterface.get_base_control())
	if button == null:
		_finish("no Bake Lightmaps button")
		return
	var dialogs := button.find_children("*", "EditorFileDialog", true, false)
	if dialogs.is_empty():
		_finish("no bake file dialog")
		return
	var out := _scene.get_basename() + ".lmbake"
	print("LMBAKE start %s -> %s (button disabled: %s)" % [_scene, out, button.disabled])
	dialogs[0].file_selected.emit(out)
	_finish("ok" if FileAccess.file_exists(out) else "no %s written" % out)


func _bake_button(node: Node) -> Button:
	var button := node as Button
	if button != null and button.text == "Bake Lightmaps":
		return button
	for child: Node in node.get_children(true):
		var hit := _bake_button(child)
		if hit != null:
			return hit
	return null


func _finish(result: String) -> void:
	print("LMBAKE " + result)
	set_process(false)
	var f := FileAccess.open("res://lmbake.result", FileAccess.WRITE)
	if f != null:
		f.store_line(result)
		f.close()
	get_tree().quit()
