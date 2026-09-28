@tool
extends EditorPlugin
## Puts MacLift over each editor 3D viewport on macOS, so lighting is judged as the game shows it.

var _layers: Array[MacLift] = []


func _enter_tree() -> void:
	if not MacLift.wanted():
		return
	for i in 4:
		var layer: MacLift = MacLift.new()
		EditorInterface.get_editor_viewport_3d(i).add_child(layer)
		_layers.append(layer)


func _exit_tree() -> void:
	for layer: MacLift in _layers:
		if is_instance_valid(layer):
			layer.queue_free()
	_layers.clear()
