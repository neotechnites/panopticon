extends SceneTree

## Runs session_driver.gd against the SOURCE tree, for the editor-side run an export is compared with:
## godot --headless --path . --script res://tools/export_check/boot_from_source.gd -- <driver args>


func _initialize() -> void:
	var driver: Node = (load("res://tools/export_check/session_driver.gd") as GDScript).new() as Node
	driver.name = "ExportDriver"
	root.add_child.call_deferred(driver)
	change_scene_to_file.call_deferred(String(ProjectSettings.get_setting("application/run/main_scene")))
