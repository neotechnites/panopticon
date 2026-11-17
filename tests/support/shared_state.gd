class_name SharedState
extends RefCounted

## Everything one test can leave behind for the next: the shared settings store, the process-wide
## switches, the shared [code].tres[/code] files and the tree. The runner reads it round every test.

## Reported for a watched static the game no longer has, so a rename cannot blind the watch.
const MISSING: String = "<missing>"

## Shared resources a test is handed by path. A test that tunes one must tune a duplicate.
const SHARED_RESOURCES: Array[String] = [
	"res://match/rules/default_match_rules.tres",
	"res://match/rules/default_ghost_profile.tres",
	"res://characters/player/default_movement_profile.tres",
	"res://characters/bots/default_bot_profile.tres",
	"res://weapons/default_weapon_profile.tres",
	"res://maps/marble/marble_match_rules.tres",
	"res://maps/forest/forest_match_rules.tres",
	"res://maps/ice/ice_match_rules.tres",
]

## Process-wide switches, as [global class, static variable, the value a fresh process holds].
const SWITCHES: Array[Array] = [
	[&"HubLobby", &"returns_to_hub", false],
	[&"HubLobby", &"relaunch_on_arrival", false],
	[&"HubLobby", &"relaunch_bot_seats", null],
	[&"MatchSetupScreen", &"show_all_rules_everywhere", false],
]

## Process-wide registries of live nodes, as [global class, static variable]. Each empties with the
## scene that filled it, so a size that grew is a node that outlived its test.
const REGISTRIES: Array[Array] = [
	[&"TrapDoor", &"live"],
	[&"HubCat", &"_all"],
]

## Nodes the game itself keeps under the root for the life of the process, made on first use.
const ROOT_SINGLETONS: Array[StringName] = [CatGrenadeRelay.NODE_NAME]

## The variable the runner's supervisor sets to the user directory it isolated.
const ISOLATED_HOME_VARIABLE: String = "PANOPTICON_TEST_HOME"

static var _scripts: Dictionary[StringName, GDScript] = {}

## The locale the process booted in, kept so a test that leaves another one cannot pass it on.
static var _boot_locale: String = ""


## Put back everything that can be put back: the settings store, bindings, locale, the switches and
## the files in the isolated user://. Called before every test, so none of it can be inherited.
static func restore() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.config_path = SettingsStore.CONFIG_PATH
	store.settings.reset()
	store.keybinds.reset_to_defaults()
	store.keybinds.apply_to_input_map()
	if _boot_locale.is_empty():
		_boot_locale = TranslationServer.get_locale()
	TranslationServer.set_locale(_boot_locale)
	for entry: Array in SWITCHES:
		var script: GDScript = _script_of(entry[0])
		if script != null and entry[1] in script:
			script.set(entry[1], entry[2])
	# Only ever the directory the runner made: with no supervisor user:// is somebody's own.
	var isolated: String = OS.get_environment(ISOLATED_HOME_VARIABLE)
	if not isolated.is_empty() and OS.get_user_data_dir().simplify_path().begins_with(isolated.simplify_path()):
		for file: String in DirAccess.get_files_at("user://"):
			DirAccess.remove_absolute(OS.get_user_data_dir().path_join(file))


## What a test can leave that nothing can put back, as named text values. The runner fails the
## test that changes one: the tree, the clock, live-node registries and the shared resources.
static func fingerprint(tree: SceneTree) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	found["tree paused"] = str(tree.paused)
	found["time scale"] = "%s at %d Hz" % [Engine.time_scale, Engine.physics_ticks_per_second]
	found["nodes under root"] = _root_children(tree)
	for entry: Array in SWITCHES:
		if _static_text(entry[0], entry[1], false) == MISSING:
			found["%s.%s" % [entry[0], entry[1]]] = MISSING
	for entry: Array in REGISTRIES:
		found["%s.%s size" % entry] = _static_text(entry[0], entry[1], true)
	for path: String in SHARED_RESOURCES:
		if ResourceLoader.has_cached(path):
			found[path] = _resource_text(load(path), 0)
	return found


## The names in [param after] whose value is not the one [param before] holds, each with both values.
static func changed(before: Dictionary[String, String], after: Dictionary[String, String]) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for key: String in after:
		# A shared resource first loaded by this test has no earlier value to differ from.
		if not before.has(key) or before[key] == after[key]:
			continue
		lines.append("%s: %s" % [key, _first_difference(before[key], after[key])])
	return lines


static func _root_children(tree: SceneTree) -> String:
	var names: PackedStringArray = PackedStringArray()
	for child: Node in tree.root.get_children():
		if not child.is_queued_for_deletion() and not ROOT_SINGLETONS.has(child.name):
			names.append("%s (%s)" % [child.name, child.get_class()])
	return "\n".join(names)


static func _static_text(owner: StringName, variable: StringName, as_size: bool) -> String:
	var script: GDScript = _script_of(owner)
	if script == null or not (variable in script):
		return MISSING
	var value: Variant = script.get(variable)
	if as_size:
		return str((value as Array).size()) if value is Array else MISSING
	return var_to_str(value)


static func _script_of(owner: StringName) -> GDScript:
	if not _scripts.has(owner):
		for entry: Dictionary in ProjectSettings.get_global_class_list():
			if StringName(entry["class"]) == owner:
				_scripts[owner] = load(String(entry["path"])) as GDScript
	return _scripts.get(owner)


## Every stored property of [param resource], one per line, following resources it owns outright.
static func _resource_text(resource: Resource, depth: int) -> String:
	if resource == null:
		return "null"
	var lines: PackedStringArray = PackedStringArray()
	for property: Dictionary in resource.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var value: Variant = resource.get(StringName(property["name"]))
		var text: String = ""
		if value is Resource:
			var held: Resource = value
			# A resource with a path of its own is shared in its own right; only its identity counts here.
			text = held.resource_path if (not held.resource_path.is_empty() or depth >= 2) \
					else _resource_text(held, depth + 1)
		else:
			text = var_to_str(value)
		lines.append("%s=%s" % [property["name"], text])
	return "\n".join(lines)


## The first line on which two multi-line values disagree, or both whole when they are one line.
static func _first_difference(before: String, after: String) -> String:
	var was: PackedStringArray = before.split("\n")
	var now: PackedStringArray = after.split("\n")
	for index: int in maxi(was.size(), now.size()):
		var old_line: String = was[index] if index < was.size() else "(nothing)"
		var new_line: String = now[index] if index < now.size() else "(nothing)"
		if old_line != new_line:
			return "was '%s', left as '%s'" % [old_line, new_line]
	return "changed"
