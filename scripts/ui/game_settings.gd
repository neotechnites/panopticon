class_name GameSettings
extends RefCounted

## Every non-keybind player preference, as one typed, self-validating object.
##
## This holds values and knows how to push them at the engine; it does not know
## about files. [SettingsStore] owns the disk. That split is what makes the
## store testable: a round-trip test builds one of these, hands it to a
## [ConfigFile], reads it back and compares, with no window and no audio device
## anywhere in the loop.
##
## [b]Corrupt input is the normal case, not the exception.[/b] A config file is
## a text file in a directory the player can open, and a build that crashes on a
## half-written one is a build that bricks itself on a power cut. So every read
## goes through the typed helpers at the bottom of this file: a missing key, a
## key of the wrong type and a key holding a wild number all resolve to the
## default rather than propagating. [method clamp_all] then runs unconditionally,
## so no value that reaches the engine is ever outside its documented range.
##
## Ranges deliberately mirror the [code]@export_range[/code] annotations on
## [MovementProfile], because [method apply_to_movement_profile] writes straight
## into one and a value the editor would refuse must not arrive by another door.

## How the window is presented.
enum DisplayMode {
	## A resizable window at [member resolution].
	WINDOWED,
	## Exclusive fullscreen: the display's mode changes. Lowest latency, slowest
	## alt-tab. This is the one Windows players mean by "fullscreen".
	FULLSCREEN,
	## Borderless windowed fullscreen. Instant alt-tab, one frame of extra
	## latency from the compositor.
	BORDERLESS,
}

## Frame pacing. Values line up with [enum DisplayServer.VSyncMode] but are
## restated so the saved file is not hostage to an engine enum's ordering.
enum VSyncMode {
	## Tear freely. Lowest latency, and the only sane choice for a benchmark.
	DISABLED,
	## Wait for the display.
	ENABLED,
	## Wait when the frame was fast enough, tear rather than halve when it was
	## not.
	ADAPTIVE,
}

## Number of entries in [enum DisplayMode]. Spelled out because the value is
## used to clamp an int read off disk, and that clamp must not silently widen
## if a mode is ever added without the settings screen learning about it.
const DISPLAY_MODE_COUNT: int = 3

## Number of entries in [enum VSyncMode]. Same reasoning.
const VSYNC_MODE_COUNT: int = 3

# --- Bus names ----------------------------------------------------------------
#
# res://default_bus_layout.tres defines all three: Master, with Effects and Music
# routed into it. They are still resolved by name at apply time and skipped when
# absent, so this code is correct against a project that has lost or not yet
# added the layout -- adding or removing a bus is a change to that file and
# nothing else.

const MASTER_BUS: StringName = &"Master"
const EFFECTS_BUS: StringName = &"Effects"
const MUSIC_BUS: StringName = &"Music"

## Below this linear volume a bus is muted outright rather than set to a very
## negative decibel value, which is both cheaper and avoids [code]-inf[/code]
## round-tripping through the config file as a string.
const MUTE_THRESHOLD: float = 0.001

# --- Defaults -----------------------------------------------------------------

## Radians of look rotation per pixel of mouse motion. Matches
## [member MovementProfile.mouse_sensitivity]'s own default, so a player who
## never opens the settings screen gets exactly the tuned value.
const DEFAULT_MOUSE_SENSITIVITY: float = 0.0022
const MIN_MOUSE_SENSITIVITY: float = 0.0001
const MAX_MOUSE_SENSITIVITY: float = 0.02

## Matches the FOV that scenes/player/player.tscn ships its Camera3D at, for
## the same reason [constant DEFAULT_MOUSE_SENSITIVITY] matches the movement
## profile's: a player who never opens the settings screen must get exactly the
## value the scene was tuned at, not a number this file invented.
const DEFAULT_FIELD_OF_VIEW: float = 100.0
const MIN_FIELD_OF_VIEW: float = 60.0
const MAX_FIELD_OF_VIEW: float = 120.0

## Ghosts are on for the matches this player starts, which is what the shipped
## [code]resources/rules/default_match_rules.tres[/code] plays. Named rather than
## written inline because [SettingsStore] needs it too: a settings file written
## before the default flipped has to be told what the new answer is.
const DEFAULT_GHOSTS_ENABLED: bool = true

## The shipped game opens with a race, so the skip is off. Named for the same
## reason [constant DEFAULT_GHOSTS_ENABLED] is: [member MatchRules.open_with_race]
## defaults to true and the two must agree, or the first match a player starts is
## played under a rule nobody chose.
const DEFAULT_SKIP_OPENING_RACE: bool = false

## Seat 0, which is the human whenever a match has one. Agrees with
## [member MatchRules.opening_seat_index] for the same reason as above.
const DEFAULT_TOWER_SEAT_INDEX: int = 0

## Highest seat index this file will believe off disk.
##
## Matches the top of [member MatchRules.opening_seat_index]'s exported range.
## The real ceiling is how many participants a match has, which depends on
## [member MatchRules.prisoner_count] and is therefore not knowable here; the
## match clamps the value against its own roster when it reads it. This clamp
## exists only so a corrupt file cannot put an absurd number into the config.
const MAX_TOWER_SEAT_INDEX: int = 31

## Matches [code]project.godot[/code]'s [code][display]/window/size[/code]
## defaults. They have to agree: [SettingsBoot] bootstraps the store and calls
## [method apply_video] before the player has opened the settings screen even
## once, on the first frame of the main menu, and a mismatch here would have
## that first [method apply_video] shrink the window project.godot just opened
## back down to whatever smaller size this constant named.
const DEFAULT_RESOLUTION: Vector2i = Vector2i(1600, 900)
const MIN_RESOLUTION: Vector2i = Vector2i(640, 360)
const MAX_RESOLUTION: Vector2i = Vector2i(7680, 4320)

## Offered by the video tab. Not a restriction: a resolution loaded from the
## file is honoured whether or not it appears here.
const RESOLUTION_CHOICES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

# --- Section and key names ----------------------------------------------------
#
# Named here rather than written inline so the schema is readable in one place
# and a typo cannot silently create a second key that nothing ever reads.

const SECTION_INPUT: String = "input"
const SECTION_AUDIO: String = "audio"
const SECTION_VIDEO: String = "video"
const SECTION_MATCH: String = "match"

# --- Values -------------------------------------------------------------------

## Radians per pixel. Written into [member MovementProfile.mouse_sensitivity].
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY

## Written into [member MovementProfile.invert_look_y].
var invert_look_y: bool = false

## Linear 0..1, not decibels. Decibels are an output format; storing them would
## make the slider's own maths non-linear and the file unreadable by a human.
var master_volume: float = 1.0
var effects_volume: float = 1.0
var music_volume: float = 1.0

var display_mode: DisplayMode = DisplayMode.WINDOWED

## Requested window size. Only meaningful in [constant DisplayMode.WINDOWED];
## kept across a fullscreen session so returning to windowed restores the size.
var resolution: Vector2i = DEFAULT_RESOLUTION

var vsync_mode: VSyncMode = VSyncMode.ENABLED

## Vertical field of view in degrees, for whichever [Camera3D] the scene decides
## is the player's view. Stored and applied on request via
## [method apply_to_camera]; this object never goes looking for a camera itself.
var field_of_view: float = DEFAULT_FIELD_OF_VIEW

## Turn the ghost mechanic on for the matches this player starts. Default true,
## which is [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP] and what the
## shipped rules resource plays.
##
## [b]Why a preference rather than only a rule file.[/b] Ghosts are a
## [MatchRules] field, and a player cannot open a text editor to turn a mechanic
## off. So the choice is a preference written OVER the rules at match start --
## see [method apply_to_match_rules] -- and the two defaults are kept in step
## deliberately: they must agree, or the first frame of the game is played under
## a rule set nobody chose.
var ghosts_enabled: bool = DEFAULT_GHOSTS_ENABLED

## Skip the opening race and hand the tower straight to [member tower_seat_index].
## Default false, which is the race the shipped game opens with.
##
## [b]Why a player-facing setting for this.[/b] Every match opens with a lap of
## the ring that decides who shoots first, and somebody testing a change to
## anything else has to run that lap before they can try it. This turns the race
## off, and it lives beside the ghost toggle for the same reason that one does:
## it is a rule of the match, it is written over [MatchRules] on the way in, and
## a player cannot open a text editor to change a rule file.
var skip_opening_race: bool = DEFAULT_SKIP_OPENING_RACE

## Which seat gets the tower when the race is skipped. 0 is the player; every
## higher index is a bot, numbered the way [method MatchRules.get_participant_name]
## numbers it and the way the HUD reports it.
##
## Read only when [member skip_opening_race] is on, and clamped against the
## match's actual roster by [MatchController] -- see
## [member MatchRules.opening_seat_index].
var tower_seat_index: int = DEFAULT_TOWER_SEAT_INDEX


## Return every value to its shipped default.
func reset() -> void:
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	invert_look_y = false
	master_volume = 1.0
	effects_volume = 1.0
	music_volume = 1.0
	display_mode = DisplayMode.WINDOWED
	resolution = DEFAULT_RESOLUTION
	vsync_mode = VSyncMode.ENABLED
	field_of_view = DEFAULT_FIELD_OF_VIEW
	ghosts_enabled = DEFAULT_GHOSTS_ENABLED
	skip_opening_race = DEFAULT_SKIP_OPENING_RACE
	tower_seat_index = DEFAULT_TOWER_SEAT_INDEX


## Force every value inside its documented range. Called after every read, so
## nothing out of range can reach the engine no matter what the file said.
func clamp_all() -> void:
	mouse_sensitivity = clampf(mouse_sensitivity, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	master_volume = clampf(master_volume, 0.0, 1.0)
	effects_volume = clampf(effects_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	field_of_view = clampf(field_of_view, MIN_FIELD_OF_VIEW, MAX_FIELD_OF_VIEW)
	resolution = resolution.clamp(MIN_RESOLUTION, MAX_RESOLUTION)
	display_mode = clampi(int(display_mode), 0, DISPLAY_MODE_COUNT - 1) as DisplayMode
	vsync_mode = clampi(int(vsync_mode), 0, VSYNC_MODE_COUNT - 1) as VSyncMode
	tower_seat_index = clampi(tower_seat_index, 0, MAX_TOWER_SEAT_INDEX)


## Copy every value out of [param other].
func copy_from(other: GameSettings) -> void:
	mouse_sensitivity = other.mouse_sensitivity
	invert_look_y = other.invert_look_y
	master_volume = other.master_volume
	effects_volume = other.effects_volume
	music_volume = other.music_volume
	display_mode = other.display_mode
	resolution = other.resolution
	vsync_mode = other.vsync_mode
	field_of_view = other.field_of_view
	ghosts_enabled = other.ghosts_enabled
	skip_opening_race = other.skip_opening_race
	tower_seat_index = other.tower_seat_index


## True when every value matches [param other]. Used by the verification harness
## to assert a save/load round trip lost nothing.
func equals(other: GameSettings) -> bool:
	return (
		is_equal_approx(mouse_sensitivity, other.mouse_sensitivity)
		and invert_look_y == other.invert_look_y
		and is_equal_approx(master_volume, other.master_volume)
		and is_equal_approx(effects_volume, other.effects_volume)
		and is_equal_approx(music_volume, other.music_volume)
		and display_mode == other.display_mode
		and resolution == other.resolution
		and vsync_mode == other.vsync_mode
		and is_equal_approx(field_of_view, other.field_of_view)
		and ghosts_enabled == other.ghosts_enabled
		and skip_opening_race == other.skip_opening_race
		and tower_seat_index == other.tower_seat_index
	)


# --- Serialisation ------------------------------------------------------------

## Write every value into [param config]. Does not save the file.
func write_to(config: ConfigFile) -> void:
	config.set_value(SECTION_INPUT, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION_INPUT, "invert_look_y", invert_look_y)

	config.set_value(SECTION_AUDIO, "master_volume", master_volume)
	config.set_value(SECTION_AUDIO, "effects_volume", effects_volume)
	config.set_value(SECTION_AUDIO, "music_volume", music_volume)

	config.set_value(SECTION_VIDEO, "display_mode", int(display_mode))
	config.set_value(SECTION_VIDEO, "resolution_width", resolution.x)
	config.set_value(SECTION_VIDEO, "resolution_height", resolution.y)
	config.set_value(SECTION_VIDEO, "vsync_mode", int(vsync_mode))
	config.set_value(SECTION_VIDEO, "field_of_view", field_of_view)

	config.set_value(SECTION_MATCH, "ghosts_enabled", ghosts_enabled)
	config.set_value(SECTION_MATCH, "skip_opening_race", skip_opening_race)
	config.set_value(SECTION_MATCH, "tower_seat_index", tower_seat_index)


## Read every value out of [param config], substituting the current value --
## which the caller has normally just reset to the default -- for anything
## missing, mistyped or out of range. Never fails.
func read_from(config: ConfigFile) -> void:
	mouse_sensitivity = read_float(config, SECTION_INPUT, "mouse_sensitivity", mouse_sensitivity)
	invert_look_y = read_bool(config, SECTION_INPUT, "invert_look_y", invert_look_y)

	master_volume = read_float(config, SECTION_AUDIO, "master_volume", master_volume)
	effects_volume = read_float(config, SECTION_AUDIO, "effects_volume", effects_volume)
	music_volume = read_float(config, SECTION_AUDIO, "music_volume", music_volume)

	display_mode = read_int(config, SECTION_VIDEO, "display_mode", int(display_mode)) as DisplayMode
	resolution = Vector2i(
		read_int(config, SECTION_VIDEO, "resolution_width", resolution.x),
		read_int(config, SECTION_VIDEO, "resolution_height", resolution.y),
	)
	vsync_mode = read_int(config, SECTION_VIDEO, "vsync_mode", int(vsync_mode)) as VSyncMode
	field_of_view = read_float(config, SECTION_VIDEO, "field_of_view", field_of_view)

	ghosts_enabled = read_bool(config, SECTION_MATCH, "ghosts_enabled", ghosts_enabled)
	skip_opening_race = read_bool(
		config, SECTION_MATCH, "skip_opening_race", skip_opening_race
	)
	tower_seat_index = read_int(config, SECTION_MATCH, "tower_seat_index", tower_seat_index)

	clamp_all()


# --- Application --------------------------------------------------------------

## Push the audio values at [AudioServer].
##
## Buses are resolved by name and skipped when the project does not define them,
## so this is correct today -- when only Master exists -- and correct the moment
## a bus layout adds Effects and Music, with no edit here.
func apply_audio() -> void:
	_apply_bus(MASTER_BUS, master_volume)
	_apply_bus(EFFECTS_BUS, effects_volume)
	_apply_bus(MUSIC_BUS, music_volume)


## Push window mode, size and vsync at [DisplayServer].
##
## A no-op under the headless display driver, which has no window to set and
## whose stubs would otherwise fill test output with noise.
func apply_video() -> void:
	if is_headless():
		return

	var window_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED
	match display_mode:
		DisplayMode.FULLSCREEN:
			window_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayMode.BORDERLESS:
			window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		_:
			window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(window_mode)

	# Size is only meaningful windowed; setting it against a fullscreen window
	# is what produces the classic "fullscreen at the wrong resolution" bug.
	if display_mode == DisplayMode.WINDOWED:
		DisplayServer.window_set_size(resolution)

	var vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
	match vsync_mode:
		VSyncMode.DISABLED:
			vsync = DisplayServer.VSYNC_DISABLED
		VSyncMode.ADAPTIVE:
			vsync = DisplayServer.VSYNC_ADAPTIVE
		_:
			vsync = DisplayServer.VSYNC_ENABLED
	DisplayServer.window_set_vsync_mode(vsync)


## Write look preferences into a live [MovementProfile].
##
## The profile is the single source of truth for how the body moves and is not
## edited by this system at rest; it is written at runtime, idempotently, so
## calling this again after every settings change is correct and cheap.
func apply_to_movement_profile(profile: MovementProfile) -> void:
	if profile == null:
		return
	profile.mouse_sensitivity = mouse_sensitivity
	profile.invert_look_y = invert_look_y


## Write the match preferences into a live [MatchRules].
##
## Every one of them is written UNCONDITIONALLY in both directions -- ghosts on
## as [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP] and off as
## [constant MatchRules.GhostBehaviour.NONE], the race skipped as
## [member MatchRules.open_with_race] false and not skipped as true -- rather
## than only when the player has the thing switched on, because the rules
## resource is one shared instance for the whole process: a one-way write would
## leave a match started after a toggle was turned off still playing it, which is
## the classic settings bug that looks like it works because the first test of it
## is always "turn it on".
##
## Idempotent, so calling it again on every [signal SettingsStore.applied] is
## correct and cheap -- exactly as [method apply_to_movement_profile] is.
##
## It writes [member MatchRules.ghost_behaviour] and nothing else. Ghost TUNING
## -- pace, catch radius, grace -- is [GhostProfile] and is not a player
## preference; a player who wants to retune the mechanic is sweeping it, not
## playing it.
func apply_to_match_rules(rules: MatchRules) -> void:
	if rules == null:
		return
	rules.ghost_behaviour = (
		MatchRules.GhostBehaviour.CATCH_AND_SWAP
		if ghosts_enabled
		else MatchRules.GhostBehaviour.NONE
	)
	rules.open_with_race = not skip_opening_race
	# Written whether or not the race is skipped, so that turning the skip back on
	# uses the seat the player last chose rather than whatever the resource was
	# left holding.
	rules.opening_seat_index = tower_seat_index


## Write [member field_of_view] into a camera. The scene decides which camera;
## this object never searches for one.
func apply_to_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.fov = field_of_view


## True when running under the dummy display driver.
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _apply_bus(bus_name: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var muted: bool = linear <= MUTE_THRESHOLD
	AudioServer.set_bus_mute(index, muted)
	if not muted:
		AudioServer.set_bus_volume_db(index, linear_to_db(linear))


# --- Typed config readers -----------------------------------------------------
#
# ConfigFile hands back a Variant. Every one of these checks the type before
# converting, so a key holding a string, a dictionary or nothing at all yields
# the fallback instead of a runtime error. Shared with KeybindMap.

## Read a float, tolerating an int and rejecting anything else.
static func read_float(config: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(raw)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return fallback
	var value: float = float(raw)
	if not is_finite(value):
		return fallback
	return value


## Read an int, tolerating a whole-valued float and rejecting anything else.
static func read_int(config: ConfigFile, section: String, key: String, fallback: int) -> int:
	var raw: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(raw)
	if kind == TYPE_INT:
		return int(raw)
	if kind == TYPE_FLOAT:
		var value: float = float(raw)
		if not is_finite(value):
			return fallback
		return int(value)
	return fallback


## Read a bool, tolerating an int and rejecting anything else.
static func read_bool(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var raw: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(raw)
	if kind == TYPE_BOOL:
		return bool(raw)
	if kind == TYPE_INT:
		return int(raw) != 0
	return fallback


## Read an untyped array, rejecting anything else. An absent section or key is
## an empty array, checked for rather than defaulted: ConfigFile treats a null
## default as "no default" and logs an error, which would fill the output of an
## ordinary first run with alarming noise.
static func read_array(config: ConfigFile, section: String, key: String) -> Array:
	if not config.has_section(section):
		return []
	if not config.has_section_key(section, key):
		return []
	var raw: Variant = config.get_value(section, key, [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	var value: Array = raw
	return value
