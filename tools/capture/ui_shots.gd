extends SceneTree
## Screenshots of the menu screens at the window's own size, for eyeballing layout.
##
##   godot --path . --resolution 1920x1080 --script res://tools/capture/ui_shots.gd -- --locale=en_XA --out=DIR
##
## Writes <locale>_main_menu.png, <locale>_settings_<tab>.png and <locale>_result.png.
## Needs a window; headless runs the flow and saves nothing.

const MENU := "res://ui/main_menu.tscn"
const RESULT := "res://ui/match_result_screen.tscn"
const SETTLE_FRAMES := 6
const LONG_NAME := "Bartholomew Plumestone"


func _arg(name: String, fallback: String) -> String:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % name):
			return raw.substr(name.length() + 3)
	return fallback


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var locale: String = _arg("locale", "en")
	var out: String = _arg("out", "user://ui_shots")
	# Read before the store boots: booting applies the saved resolution.
	var window: Vector2i = DisplayServer.window_get_size()
	var store: SettingsStore = SettingsStore.instance()
	store.config_path = "user://ui_shots_scratch.cfg"
	store.settings.locale = locale
	store.settings.display_mode = GameSettings.DisplayMode.WINDOWED
	store.settings.resolution = window
	store.apply_all(true)
	DirAccess.make_dir_recursive_absolute(out)

	var menu: MainMenu = (load(MENU) as PackedScene).instantiate() as MainMenu
	root.add_child(menu)
	await _settle()
	await _shot(out, "%s_main_menu" % locale)

	menu.open_settings()
	var settings: SettingsScreen = menu.get_node("%SettingsScreen") as SettingsScreen
	var tabs: TabContainer = settings.get_node("Frame/Dialog/Padding/Layout/Tabs") as TabContainer
	for tab: int in tabs.get_tab_count():
		tabs.current_tab = tab
		await _settle()
		await _shot(out, "%s_settings_%d" % [locale, tab])
	settings.close()

	var result: MatchResultScreen = (load(RESULT) as PackedScene).instantiate() as MatchResultScreen
	result.controller = MatchController.new()
	root.add_child(result)
	result.set_process(false)
	(result.get_node("%Verdict") as Label).text = tr("RESULT_VICTORY")
	(result.get_node("%Headline") as Label).text = "\n".join([
		tr("RESULT_WINNER_HELD_TOWER").format({"name": LONG_NAME}), tr("RESULT_ROLE_PRISONER_GHOST"),
	])
	(result.get_node("%Detail") as Label).text = "\n".join([
		tr("RESULT_DETAIL_TOWER").format({"name": LONG_NAME, "turn": 3, "rounds": 2}),
		tr("RESULT_DETAIL_ROUNDS").format({"rounds": 4}),
		tr("RESULT_DETAIL_CLEARED").format({"cleared": 3, "total": 3}),
		tr("RESULT_DETAIL_SWAPS").format({"swaps": 5}),
	])
	result.get_node("%Root").set("visible", true)
	await _settle()
	await _shot(out, "%s_result" % locale)
	result.controller.free()
	result.free()
	menu.free()
	quit(0)


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame


func _shot(dir: String, name: String) -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("headless: skipped %s" % name)
		return
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [dir, name]
	var error: Error = image.save_png(path)
	print("%s %s %dx%d" % [error_string(error), path, image.get_width(), image.get_height()])
