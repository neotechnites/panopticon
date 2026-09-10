class_name SettingsStore
extends RefCounted

## The player's settings, on disk and in force. One instance, reachable from
## anywhere via [method instance].
##
## [b]Why this is not an autoload.[/b] It does not need to be. It owns no node,
## runs no frame and listens to no signal; it is a value object plus file I/O.
## Making it a [RefCounted] with a static accessor means a scene that wants
## settings gets them by asking, a headless test gets a private instance by
## constructing one, and the project settings file needs no entry at all --
## which matters here, because several agents are editing this repo at once and
## an autoload is a merge conflict waiting to happen. Drop [SettingsBoot] into a
## scene (or register it as an autoload later) if you want the settings applied
## before any menu is opened.
##
## [b]Startup order is load-bearing.[/b] [method bootstrap] does four things and
## the order of the first two is not negotiable:
## [codeblock]
##   1. register the actions      -- so there is something to snapshot
##   2. snapshot InputMap         -- this is "default", and it is only true
##                                   before any override has been applied
##   3. read user://settings.cfg  -- defaults survive if it is missing or junk
##   4. apply everything          -- audio, video, InputMap
## [/codeblock]
## Snapshot after applying overrides and "reset to default" restores the
## player's last override, which is a bug that survives testing because it looks
## right until the second run.
##
## [b]A missing or corrupt file is a normal outcome.[/b] Not an error path, not
## an assert: [method load_from_disk] resets to defaults [i]first[/i] and then
## overlays whatever the file legibly contained, so a truncated write, a
## hand-edit gone wrong or a first run all land the player in the same known
## good state.

## Emitted after [method apply_all]. UI that mirrors a setting redraws on this
## rather than polling.
signal applied()

## Where the settings live. Under [code]user://[/code], which is per-user and
## writable in an exported build -- [code]res://[/code] is read-only once
## packed, and a settings file written next to the executable is the classic way
## to make a game fail on a machine where the player is not an administrator.
const CONFIG_PATH: String = "user://settings.cfg"

## Schema version, written to [code][meta]/version[/code]. A file whose version
## is newer than this was written by a newer build and is not read: a downgrade
## silently reinterpreting fields it does not understand is worse than a reset.
const CONFIG_VERSION: int = 2

## The first version whose [code]ghosts_enabled[/code] key means what the player
## chose. See [method load_from_disk].
const GHOSTS_CHOSEN_FROM_VERSION: int = 2

const SECTION_META: String = "meta"

static var _instance: SettingsStore = null

## Non-keybind preferences.
var settings: GameSettings = GameSettings.new()

## Keyboard, mouse and gamepad bindings.
var keybinds: KeybindMap = KeybindMap.new()

## File this instance reads and writes. Overridable so a test can work in its
## own file instead of trampling the player's.
var config_path: String = CONFIG_PATH

## True when the last [method load_from_disk] found a readable file. False after
## a first run or a rejected file -- the settings screen has no reason to care,
## but the verification harness asserts on it.
var loaded_from_disk: bool = false

## Why the last load fell back to defaults, or empty if it did not.
var last_load_error: String = ""

var _bootstrapped: bool = false


## The shared store, bootstrapped on first use.
static func instance() -> SettingsStore:
	if _instance == null:
		_instance = SettingsStore.new()
		_instance.bootstrap()
	return _instance


## Snapshot the defaults, load the file and apply the result. Safe to call more
## than once; only the first call does anything.
func bootstrap() -> void:
	if _bootstrapped:
		return
	_bootstrapped = true
	KeybindMap.ensure_actions_registered()
	keybinds.capture_defaults()
	load_from_disk()
	apply_all()


## Reset to defaults, then overlay whatever the file legibly contains.
##
## Returns true only if a file was read. False is not a failure to report to the
## player: it is a first run, and the defaults now in [member settings] are the
## correct answer.
func load_from_disk() -> bool:
	settings.reset()
	keybinds.reset_to_defaults()
	loaded_from_disk = false
	last_load_error = ""

	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(config_path)
	if error != OK:
		# Covers both "not there yet" and "there but unparseable". Neither is
		# worth a dialog; both mean defaults.
		last_load_error = "no readable settings file (%s)" % error_string(error)
		return false

	var version: int = GameSettings.read_int(config, SECTION_META, "version", 0)
	if version <= 0 or version > CONFIG_VERSION:
		last_load_error = "unsupported settings version %d" % version
		return false

	settings.read_from(config)
	if version < GHOSTS_CHOSEN_FROM_VERSION:
		# Version 1 wrote ghosts_enabled=false into every file it saved, because
		# off was the default then and this file records values rather than
		# choices. Reading it back now would leave a returning player with ghosts
		# off while the rules resource they play has them on -- the two defaults
		# disagreeing is exactly the bug the toggle exists to prevent. So a
		# version 1 file is taken to have expressed no preference about ghosts.
		settings.ghosts_enabled = GameSettings.DEFAULT_GHOSTS_ENABLED
	keybinds.read_from(config)
	loaded_from_disk = true
	return true


## Write the current settings and bindings out.
func save_to_disk() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION_META, "version", CONFIG_VERSION)
	settings.write_to(config)
	keybinds.write_to(config)
	var error: Error = config.save(config_path)
	if error != OK:
		push_warning("SettingsStore could not write %s: %s" % [config_path, error_string(error)])
	return error


## Push everything at the engine: audio buses, window, [InputMap].
func apply_all() -> void:
	settings.apply_audio()
	settings.apply_video()
	keybinds.apply_to_input_map()
	applied.emit()


## Return every setting and every binding to its shipped default, apply and
## save.
func reset_all() -> void:
	settings.reset()
	keybinds.reset_to_defaults()
	apply_all()
	save_to_disk()


## Delete the settings file. Used by the verification harness to reproduce a
## first run; the store itself never calls it.
func erase_file() -> void:
	if FileAccess.file_exists(config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
