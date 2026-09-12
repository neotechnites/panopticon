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

## A frame-rate ceiling the video tab offers. Values line up with
## [member Engine.max_fps], where 0 means unlimited.
enum FpsCap {
	UNLIMITED,
	FPS_60,
	FPS_120,
	FPS_144,
	FPS_240,
}

## [enum FpsCap] -> the [member Engine.max_fps] value it means.
const FPS_CAP_VALUES: Array[int] = [0, 60, 120, 144, 240]

## Number of entries in [enum FpsCap]. Same reasoning as [constant DISPLAY_MODE_COUNT].
const FPS_CAP_COUNT: int = 5

## What [method DisplayServer.get_name] answers when the game is running inside
## the editor's embedded Game panel rather than in a window of its own. See
## [method is_embedded].
const EMBEDDED_DISPLAY: StringName = &"embedded"

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

## Reload seconds for the first [constant RELOAD_BY_TURN_COUNT] times a player
## holds the tower, written into [member MatchRules.reload_seconds_by_turn].
## Matches [member MatchRules.base_reload_seconds] on the shipped rules, for the
## same reason [constant DEFAULT_GHOSTS_ENABLED] matches the ghost rule.
const DEFAULT_RELOAD_BY_TURN: PackedFloat32Array = [2.5, 2.5, 2.5, 2.5, 2.5]

## Fixed grid size the settings screen offers: five turns, no more, no fewer.
const RELOAD_BY_TURN_COUNT: int = 5

const MIN_RELOAD_BY_TURN: float = 0.1
const MAX_RELOAD_BY_TURN: float = 15.0

## Highest seat index this file will believe off disk.
##
## Matches the top of [member MatchRules.opening_seat_index]'s exported range.
## The real ceiling is how many participants a match has, which depends on
## [member MatchRules.prisoner_count] and is therefore not knowable here; the
## match clamps the value against its own roster when it reads it. This clamp
## exists only so a corrupt file cannot put an absurd number into the config.
const MAX_TOWER_SEAT_INDEX: int = 31

## How many prisoners a match started from this menu puts on the ring. Agrees
## with [member MatchRules.prisoner_count] and with the shipped
## [code]resources/rules/default_match_rules.tres[/code], for the same reason
## [constant DEFAULT_GHOSTS_ENABLED] agrees with the ghost rule: a preference
## that disagrees with the rule it overwrites means the first match a player
## starts is played under a rule set nobody chose.
const DEFAULT_PRISONER_COUNT: int = 3
const MIN_PRISONER_COUNT: int = 1

## The largest field the SAVED PREFERENCE may name.
##
## [member MatchRules.prisoner_count] is exported as [code]1..32, or_greater[/code]
## and a sweep may still ask for any of it -- this bound is on the preference, not
## on the rule. Eight is the most the start line has been measured at: the field
## is dealt out sideways across a 25 m deck at
## [member MatchRules.start_line_spacing_metres], and a number large enough to
## run off the end of that line is a spawn bug, not a game mode.
const MAX_PRISONER_COUNT: int = 8

## Hits a prisoner absorbs. Agrees with [member MatchRules.prisoner_lives].
const DEFAULT_PRISONER_LIVES: int = 1
const MIN_PRISONER_LIVES: int = 1

## The most lives the SAVED PREFERENCE may name, against the rule's own
## [code]1..10[/code]. A survived hit has no hit reaction, no stagger and no
## recovery -- see [member MatchRules.prisoner_lives] -- so the screen offers the
## smallest range in which that is still legible rather than the whole rule.
const MAX_PRISONER_LIVES: int = 3

## Prisoners the tower must convert under
## [constant MatchRules.ShooterWinCondition.SHUTOUT_COUNT].
##
## [MatchRules] ships this at 0 = unset and refuses to guess, because a sweep
## that quietly played total conversion under another name would be measuring a
## rule it did not select -- see [member MatchRules.shutout_count]. A PLAYER
## cannot be handed that refusal: they pick the mode off a menu, and a mode that
## does nothing is not a mode. So the preference carries a real number, and 2 of
## the shipped 3 prisoners is the smallest one that is not total conversion in
## disguise. Whether it is the RIGHT number is the open question the rule states,
## and a sweep answers it in [MatchRules], not here.
const DEFAULT_SHUTOUT_COUNT: int = 2
const MIN_SHUTOUT_COUNT: int = 1

## Seconds the tower must hold out under
## [constant MatchRules.ShooterWinCondition.HOLD_DURATION]. Real for the same
## reason [constant DEFAULT_SHUTOUT_COUNT] is.
##
## A lap of the shipped ring is roughly 35 seconds, so a siege longer than that
## is one the first arrival always beats: 30 is inside a lap on purpose, and is
## the least surprising reading of "shorter than the round it replaces". It is a
## starting point for a sweep and not a design answer.
const DEFAULT_HOLD_DURATION_SECONDS: float = 30.0
const MIN_HOLD_DURATION_SECONDS: float = 5.0

## Ceiling on the saved preference, against the rule's own [code]0..600[/code].
const MAX_HOLD_DURATION_SECONDS: float = 600.0

## Rounds a player must win from the tower to win the match. Agrees with
## [member MatchRules.rounds_to_win_match].
const DEFAULT_ROUNDS_TO_WIN_MATCH: int = 1
const MIN_ROUNDS_TO_WIN_MATCH: int = 1

## Ceiling on the saved preference, against the rule's own [code]1..16[/code].
const MAX_ROUNDS_TO_WIN_MATCH: int = 7

## The map a player who has chosen none plays. Taken from [MapCatalog] rather
## than spelled out here, for the same reason [constant DEFAULT_GHOSTS_ENABLED]
## exists: two files holding their own opinion of the default is how the first
## match a player starts ends up played under something nobody chose.
const DEFAULT_MAP_ID: StringName = MapCatalog.DEFAULT_ID

const DEFAULT_JOIN_ADDRESS: String = "127.0.0.1"
const MIN_NET_PORT: int = 1024
const MAX_NET_PORT: int = 65535
const MAX_PLAYER_NAME_LENGTH: int = 24

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

## 3D render resolution as a fraction of the window. Written into
## [member Viewport.scaling_3d_scale] on the root viewport.
const DEFAULT_RENDER_SCALE: float = 1.0
const MIN_RENDER_SCALE: float = 0.5
const MAX_RENDER_SCALE: float = 1.0

# --- Section and key names ----------------------------------------------------
#
# Named here rather than written inline so the schema is readable in one place
# and a typo cannot silently create a second key that nothing ever reads.

const SECTION_INPUT: String = "input"
const SECTION_AUDIO: String = "audio"
const SECTION_VIDEO: String = "video"
const SECTION_MATCH: String = "match"
const SECTION_NET: String = "net"

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
var sfx_crush: bool = false

var display_mode: DisplayMode = DisplayMode.WINDOWED

## Requested window size. Only meaningful in [constant DisplayMode.WINDOWED];
## kept across a fullscreen session so returning to windowed restores the size.
var resolution: Vector2i = DEFAULT_RESOLUTION

var vsync_mode: VSyncMode = VSyncMode.ENABLED

## Frame-rate ceiling. Written into [member Engine.max_fps].
var fps_cap: FpsCap = FpsCap.UNLIMITED

## Fraction of the window's resolution the 3D scene is rendered at, then
## upscaled. Written into [member Viewport.scaling_3d_scale].
var render_scale: float = DEFAULT_RENDER_SCALE

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

## Reload seconds for the first [constant RELOAD_BY_TURN_COUNT] times a player
## holds the tower. Always exactly [constant RELOAD_BY_TURN_COUNT] entries --
## [method clamp_all] repairs any other size back to [constant DEFAULT_RELOAD_BY_TURN].
var reload_by_turn: PackedFloat32Array = DEFAULT_RELOAD_BY_TURN.duplicate()

## How many prisoners run the round, written over
## [member MatchRules.prisoner_count] at match start.
##
## [b]Why this is a preference at all.[/b] Same argument as the ghost toggle
## above: it is a rule of the round, it is the crudest difficulty dial the game
## has, and a player cannot open a text editor to change a rule file. Everything
## from here down to [member rounds_to_win_match] is on the match setup screen
## for that reason and reaches the match by exactly the same door --
## [method apply_to_match_rules], called by the [SettingsBoot] node in
## [code]scenes/match/match.tscn[/code], on the one cached [MatchRules] the
## [MatchController] in that scene runs.
var prisoner_count: int = DEFAULT_PRISONER_COUNT

## Hits a prisoner absorbs before leaving the round. Written over
## [member MatchRules.prisoner_lives].
var prisoner_lives: int = DEFAULT_PRISONER_LIVES

## What the shooter must do to win. Written over
## [member MatchRules.shooter_win_condition].
##
## All three members are implemented, so all three are a real choice and the
## setup screen offers all three live. The clamp in [method clamp_all] is against
## a hand-edited file naming a member this build does not have, not against the
## screen.
var shooter_win_condition: MatchRules.ShooterWinCondition = (
	MatchRules.ShooterWinCondition.TOTAL_CONVERSION
)

## Prisoners the tower must convert under
## [constant MatchRules.ShooterWinCondition.SHUTOUT_COUNT]. Written over
## [member MatchRules.shutout_count].
##
## Written whether or not that condition is the one chosen, exactly as every
## other rule here is: the rules resource is one shared instance for the whole
## process, so a number only written when its mode is selected leaves a match
## started after a change back playing the last one. Clamped never to exceed
## [member prisoner_count] -- a shutout of more prisoners than the round has is a
## round that cannot be won, and the player who lowered the prisoner count did
## not ask for that.
var shutout_count: int = DEFAULT_SHUTOUT_COUNT

## Seconds the tower must hold out under
## [constant MatchRules.ShooterWinCondition.HOLD_DURATION]. Written over
## [member MatchRules.hold_duration_seconds], unconditionally, for the reason
## above.
var hold_duration_seconds: float = DEFAULT_HOLD_DURATION_SECONDS

## What the prisoners must do to win. Written over
## [member MatchRules.runner_win_condition]. Both members are implemented, so
## this one is a real choice.
var runner_win_condition: MatchRules.RunnerWinCondition = (
	MatchRules.RunnerWinCondition.FIRST_ARRIVAL
)

## Rounds a player must win from the tower to win the match. Written over
## [member MatchRules.rounds_to_win_match].
var rounds_to_win_match: int = DEFAULT_ROUNDS_TO_WIN_MATCH

## The power every prisoner carries. Written over [member MatchRules.runner_ability].
var runner_ability: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE

## The map the match is played in, by [member MapDefinition.id]. Written over
## [member MatchRules.map_id].
##
## Held as an id and not a path so that a settings file survives a scene being
## moved, and so that a file naming a map that no longer exists resolves to the
## default in [method clamp_all] rather than starting a match with no arena.
var map_id: StringName = DEFAULT_MAP_ID

## Name shown to other players. Defaults to the OS username.
var player_name: String = default_player_name()

var join_address: String = DEFAULT_JOIN_ADDRESS

var join_port: int = 27960

## True when the last window resize [method apply_video] asked for was ignored
## outright -- the size before the call and the size after it are the same, and
## neither is the size asked for.
##
## [b]Why this is measured rather than assumed.[/b] "Set the size and trust it"
## is how the resolution list came to look broken: run from the editor's embedded
## Game panel, [method DisplayServer.window_set_size] returns without doing
## anything and prints one line into the log, so the choice was received, applied
## and saved and the window never moved. A display server is allowed to refuse --
## embedded, a tiling window manager, a size larger than the screen -- and the
## only honest way to know is to read the size back. A CLAMPED resize does not
## count: the window moved, just not as far as asked, and telling the player it
## failed would be a lie.
##
## Not saved to disk. It is a fact about the process that is running, not a
## preference, and it is recomputed on every [method apply_video].
var window_resize_refused: bool = false

# What was last actually pushed at the DisplayServer, so an apply that changes
# nothing about the window does not touch the window. See [method apply_video].
# The sentinels are deliberately impossible values, so the first apply pushes
# everything.
var _pushed_display_mode: int = -1
var _pushed_vsync_mode: int = -1
var _pushed_resolution: Vector2i = Vector2i.ZERO
var _pushed_fps_cap: int = -1
var _pushed_render_scale: float = -1.0


## Return every value to its shipped default.
func reset() -> void:
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	invert_look_y = false
	master_volume = 1.0
	effects_volume = 1.0
	music_volume = 1.0
	sfx_crush = false
	display_mode = DisplayMode.WINDOWED
	resolution = DEFAULT_RESOLUTION
	vsync_mode = VSyncMode.ENABLED
	fps_cap = FpsCap.UNLIMITED
	render_scale = DEFAULT_RENDER_SCALE
	field_of_view = DEFAULT_FIELD_OF_VIEW
	ghosts_enabled = DEFAULT_GHOSTS_ENABLED
	skip_opening_race = DEFAULT_SKIP_OPENING_RACE
	tower_seat_index = DEFAULT_TOWER_SEAT_INDEX
	reload_by_turn = DEFAULT_RELOAD_BY_TURN.duplicate()
	prisoner_count = DEFAULT_PRISONER_COUNT
	prisoner_lives = DEFAULT_PRISONER_LIVES
	shooter_win_condition = MatchRules.ShooterWinCondition.TOTAL_CONVERSION
	shutout_count = DEFAULT_SHUTOUT_COUNT
	hold_duration_seconds = DEFAULT_HOLD_DURATION_SECONDS
	runner_win_condition = MatchRules.RunnerWinCondition.FIRST_ARRIVAL
	rounds_to_win_match = DEFAULT_ROUNDS_TO_WIN_MATCH
	runner_ability = MatchRules.RunnerAbility.NONE
	map_id = DEFAULT_MAP_ID
	player_name = default_player_name()
	join_address = DEFAULT_JOIN_ADDRESS
	join_port = 27960


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
	fps_cap = clampi(int(fps_cap), 0, FPS_CAP_COUNT - 1) as FpsCap
	render_scale = clampf(render_scale, MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	tower_seat_index = clampi(tower_seat_index, 0, MAX_TOWER_SEAT_INDEX)
	# A file holding the wrong number of entries is a build mismatch or a hand
	# edit, not a partial preference worth salvaging.
	if reload_by_turn.size() != RELOAD_BY_TURN_COUNT:
		reload_by_turn = DEFAULT_RELOAD_BY_TURN.duplicate()
	else:
		for i: int in RELOAD_BY_TURN_COUNT:
			reload_by_turn[i] = clampf(reload_by_turn[i], MIN_RELOAD_BY_TURN, MAX_RELOAD_BY_TURN)
	prisoner_count = clampi(prisoner_count, MIN_PRISONER_COUNT, MAX_PRISONER_COUNT)
	prisoner_lives = clampi(prisoner_lives, MIN_PRISONER_LIVES, MAX_PRISONER_LIVES)
	rounds_to_win_match = clampi(
		rounds_to_win_match, MIN_ROUNDS_TO_WIN_MATCH, MAX_ROUNDS_TO_WIN_MATCH
	)
	# Sized off the enums themselves rather than off a count restated here: these
	# live in another file, and a member added there without this one noticing
	# must widen the clamp, not be silently rejected.
	shooter_win_condition = clampi(
		int(shooter_win_condition), 0, MatchRules.ShooterWinCondition.size() - 1
	) as MatchRules.ShooterWinCondition
	runner_win_condition = clampi(
		int(runner_win_condition), 0, MatchRules.RunnerWinCondition.size() - 1
	) as MatchRules.RunnerWinCondition
	runner_ability = clampi(
		int(runner_ability), 0, MatchRules.RunnerAbility.size() - 1
	) as MatchRules.RunnerAbility
	# Bounded by the field it is counted against, so lowering the prisoner count
	# can never leave a shutout nobody can reach. Same bargain as every clamp
	# here: the player loses a choice, not the match.
	shutout_count = clampi(shutout_count, MIN_SHUTOUT_COUNT, prisoner_count)
	hold_duration_seconds = clampf(
		hold_duration_seconds, MIN_HOLD_DURATION_SECONDS, MAX_HOLD_DURATION_SECONDS
	)
	# A map that is not in the catalog is a file written by an older or newer
	# build, or hand-edited. Falling back to the default is the same bargain
	# every clamp above makes: the player loses a choice, not the match.
	if not MapCatalog.has(map_id):
		map_id = DEFAULT_MAP_ID
	player_name = player_name.strip_edges().left(MAX_PLAYER_NAME_LENGTH)
	if player_name.is_empty():
		player_name = default_player_name()
	join_address = join_address.strip_edges()
	if join_address.is_empty():
		join_address = DEFAULT_JOIN_ADDRESS
	join_port = clampi(join_port, MIN_NET_PORT, MAX_NET_PORT)


## Copy every value out of [param other].
func copy_from(other: GameSettings) -> void:
	mouse_sensitivity = other.mouse_sensitivity
	invert_look_y = other.invert_look_y
	master_volume = other.master_volume
	effects_volume = other.effects_volume
	music_volume = other.music_volume
	sfx_crush = other.sfx_crush
	display_mode = other.display_mode
	resolution = other.resolution
	vsync_mode = other.vsync_mode
	fps_cap = other.fps_cap
	render_scale = other.render_scale
	field_of_view = other.field_of_view
	ghosts_enabled = other.ghosts_enabled
	skip_opening_race = other.skip_opening_race
	tower_seat_index = other.tower_seat_index
	reload_by_turn = other.reload_by_turn.duplicate()
	prisoner_count = other.prisoner_count
	prisoner_lives = other.prisoner_lives
	shooter_win_condition = other.shooter_win_condition
	shutout_count = other.shutout_count
	hold_duration_seconds = other.hold_duration_seconds
	runner_win_condition = other.runner_win_condition
	rounds_to_win_match = other.rounds_to_win_match
	runner_ability = other.runner_ability
	map_id = other.map_id
	player_name = other.player_name
	join_address = other.join_address
	join_port = other.join_port


## True when every value matches [param other]. Used by the verification harness
## to assert a save/load round trip lost nothing.
func equals(other: GameSettings) -> bool:
	return (
		is_equal_approx(mouse_sensitivity, other.mouse_sensitivity)
		and invert_look_y == other.invert_look_y
		and is_equal_approx(master_volume, other.master_volume)
		and is_equal_approx(effects_volume, other.effects_volume)
		and is_equal_approx(music_volume, other.music_volume)
		and sfx_crush == other.sfx_crush
		and display_mode == other.display_mode
		and resolution == other.resolution
		and vsync_mode == other.vsync_mode
		and fps_cap == other.fps_cap
		and is_equal_approx(render_scale, other.render_scale)
		and is_equal_approx(field_of_view, other.field_of_view)
		and ghosts_enabled == other.ghosts_enabled
		and skip_opening_race == other.skip_opening_race
		and tower_seat_index == other.tower_seat_index
		and _reload_by_turn_almost_equal(other.reload_by_turn)
		and prisoner_count == other.prisoner_count
		and prisoner_lives == other.prisoner_lives
		and shooter_win_condition == other.shooter_win_condition
		and shutout_count == other.shutout_count
		and is_equal_approx(hold_duration_seconds, other.hold_duration_seconds)
		and runner_win_condition == other.runner_win_condition
		and rounds_to_win_match == other.rounds_to_win_match
		and runner_ability == other.runner_ability
		and map_id == other.map_id
		and player_name == other.player_name
		and join_address == other.join_address
		and join_port == other.join_port
	)


## Element-wise [method is_equal_approx] for [member reload_by_turn], since
## [PackedFloat32Array] has no built-in tolerance comparison.
func _reload_by_turn_almost_equal(other: PackedFloat32Array) -> bool:
	if reload_by_turn.size() != other.size():
		return false
	for i: int in reload_by_turn.size():
		if not is_equal_approx(reload_by_turn[i], other[i]):
			return false
	return true


# --- Serialisation ------------------------------------------------------------

## Write every value into [param config]. Does not save the file.
func write_to(config: ConfigFile) -> void:
	config.set_value(SECTION_INPUT, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION_INPUT, "invert_look_y", invert_look_y)

	config.set_value(SECTION_AUDIO, "master_volume", master_volume)
	config.set_value(SECTION_AUDIO, "effects_volume", effects_volume)
	config.set_value(SECTION_AUDIO, "music_volume", music_volume)
	config.set_value(SECTION_AUDIO, "sfx_crush", sfx_crush)

	config.set_value(SECTION_VIDEO, "display_mode", int(display_mode))
	config.set_value(SECTION_VIDEO, "resolution_width", resolution.x)
	config.set_value(SECTION_VIDEO, "resolution_height", resolution.y)
	config.set_value(SECTION_VIDEO, "vsync_mode", int(vsync_mode))
	config.set_value(SECTION_VIDEO, "fps_cap", int(fps_cap))
	config.set_value(SECTION_VIDEO, "render_scale", render_scale)
	config.set_value(SECTION_VIDEO, "field_of_view", field_of_view)

	config.set_value(SECTION_MATCH, "ghosts_enabled", ghosts_enabled)
	config.set_value(SECTION_MATCH, "skip_opening_race", skip_opening_race)
	config.set_value(SECTION_MATCH, "tower_seat_index", tower_seat_index)
	config.set_value(SECTION_MATCH, "reload_by_turn", reload_by_turn)
	config.set_value(SECTION_MATCH, "prisoner_count", prisoner_count)
	config.set_value(SECTION_MATCH, "prisoner_lives", prisoner_lives)
	config.set_value(SECTION_MATCH, "shooter_win_condition", int(shooter_win_condition))
	config.set_value(SECTION_MATCH, "shutout_count", shutout_count)
	config.set_value(SECTION_MATCH, "hold_duration_seconds", hold_duration_seconds)
	config.set_value(SECTION_MATCH, "runner_win_condition", int(runner_win_condition))
	config.set_value(SECTION_MATCH, "rounds_to_win_match", rounds_to_win_match)
	config.set_value(SECTION_MATCH, "runner_ability", int(runner_ability))
	# As a String, not a StringName: ConfigFile writes a StringName as &"x",
	# which is legible but is not what a hand-edited file will contain.
	config.set_value(SECTION_MATCH, "map_id", String(map_id))

	config.set_value(SECTION_NET, "player_name", player_name)
	config.set_value(SECTION_NET, "join_address", join_address)
	config.set_value(SECTION_NET, "join_port", join_port)


## Read every value out of [param config], substituting the current value --
## which the caller has normally just reset to the default -- for anything
## missing, mistyped or out of range. Never fails.
func read_from(config: ConfigFile) -> void:
	mouse_sensitivity = read_float(config, SECTION_INPUT, "mouse_sensitivity", mouse_sensitivity)
	invert_look_y = read_bool(config, SECTION_INPUT, "invert_look_y", invert_look_y)

	master_volume = read_float(config, SECTION_AUDIO, "master_volume", master_volume)
	effects_volume = read_float(config, SECTION_AUDIO, "effects_volume", effects_volume)
	music_volume = read_float(config, SECTION_AUDIO, "music_volume", music_volume)
	sfx_crush = read_bool(config, SECTION_AUDIO, "sfx_crush", sfx_crush)

	display_mode = read_int(config, SECTION_VIDEO, "display_mode", int(display_mode)) as DisplayMode
	resolution = Vector2i(
		read_int(config, SECTION_VIDEO, "resolution_width", resolution.x),
		read_int(config, SECTION_VIDEO, "resolution_height", resolution.y),
	)
	vsync_mode = read_int(config, SECTION_VIDEO, "vsync_mode", int(vsync_mode)) as VSyncMode
	fps_cap = read_int(config, SECTION_VIDEO, "fps_cap", int(fps_cap)) as FpsCap
	render_scale = read_float(config, SECTION_VIDEO, "render_scale", render_scale)
	field_of_view = read_float(config, SECTION_VIDEO, "field_of_view", field_of_view)

	ghosts_enabled = read_bool(config, SECTION_MATCH, "ghosts_enabled", ghosts_enabled)
	skip_opening_race = read_bool(
		config, SECTION_MATCH, "skip_opening_race", skip_opening_race
	)
	tower_seat_index = read_int(config, SECTION_MATCH, "tower_seat_index", tower_seat_index)
	reload_by_turn = read_packed_float32_array(
		config, SECTION_MATCH, "reload_by_turn", reload_by_turn
	)
	prisoner_count = read_int(config, SECTION_MATCH, "prisoner_count", prisoner_count)
	prisoner_lives = read_int(config, SECTION_MATCH, "prisoner_lives", prisoner_lives)
	shooter_win_condition = read_int(
		config, SECTION_MATCH, "shooter_win_condition", int(shooter_win_condition)
	) as MatchRules.ShooterWinCondition
	shutout_count = read_int(config, SECTION_MATCH, "shutout_count", shutout_count)
	hold_duration_seconds = read_float(
		config, SECTION_MATCH, "hold_duration_seconds", hold_duration_seconds
	)
	runner_win_condition = read_int(
		config, SECTION_MATCH, "runner_win_condition", int(runner_win_condition)
	) as MatchRules.RunnerWinCondition
	rounds_to_win_match = read_int(
		config, SECTION_MATCH, "rounds_to_win_match", rounds_to_win_match
	)
	runner_ability = read_int(
		config, SECTION_MATCH, "runner_ability", int(runner_ability)
	) as MatchRules.RunnerAbility
	map_id = read_string_name(config, SECTION_MATCH, "map_id", map_id)

	player_name = String(read_string_name(config, SECTION_NET, "player_name", player_name))
	join_address = String(read_string_name(config, SECTION_NET, "join_address", join_address))
	join_port = read_int(config, SECTION_NET, "join_port", join_port)

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
	AudioDirector.set_crush(sfx_crush)


## Push window mode, size, vsync, the FPS cap and the render scale.
##
## A no-op under the headless display driver, which has no window to set and
## whose stubs would otherwise fill test output with noise.
##
## [b]It only touches the window when the player changed the window.[/b]
## [method SettingsStore.apply_all] runs this on EVERY settings change -- a
## volume slider drag included -- and the version of it that pushed mode and size
## unconditionally dragged a maximised or hand-resized window back to
## [member resolution] every time anything at all moved. So the last values
## actually pushed are remembered and the calls are skipped when nothing here has
## changed since. [param force] pushes anyway, which is what the video controls
## do: a player who picks a size off the list means it even if the number is the
## one already stored.
func apply_video(force: bool = false) -> void:
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

	var mode_is_stale: bool = force or int(display_mode) != _pushed_display_mode
	if mode_is_stale:
		DisplayServer.window_set_mode(window_mode)
		_pushed_display_mode = int(display_mode)

	# Size is only meaningful windowed; setting it against a fullscreen window
	# is what produces the classic "fullscreen at the wrong resolution" bug.
	# Pushed after the mode for the same reason: leaving either fullscreen mode
	# restores whatever size the window had before it, so the size has to be set
	# on the far side of that.
	if display_mode == DisplayMode.WINDOWED and (mode_is_stale or resolution != _pushed_resolution):
		var before: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_size(resolution)
		var after: Vector2i = DisplayServer.window_get_size()
		_pushed_resolution = resolution
		# Refused outright, as opposed to honoured or clamped. See
		# [member window_resize_refused].
		window_resize_refused = after == before and after != resolution

	if force or int(vsync_mode) != _pushed_vsync_mode:
		var vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
		match vsync_mode:
			VSyncMode.DISABLED:
				vsync = DisplayServer.VSYNC_DISABLED
			VSyncMode.ADAPTIVE:
				vsync = DisplayServer.VSYNC_ADAPTIVE
			_:
				vsync = DisplayServer.VSYNC_ENABLED
		DisplayServer.window_set_vsync_mode(vsync)
		_pushed_vsync_mode = int(vsync_mode)

	if force or int(fps_cap) != _pushed_fps_cap:
		var index: int = clampi(int(fps_cap), 0, FPS_CAP_VALUES.size() - 1)
		Engine.max_fps = FPS_CAP_VALUES[index]
		_pushed_fps_cap = int(fps_cap)

	if force or not is_equal_approx(render_scale, _pushed_render_scale):
		var main_loop: SceneTree = Engine.get_main_loop() as SceneTree
		if main_loop != null and main_loop.root != null:
			main_loop.root.scaling_3d_scale = render_scale
		_pushed_render_scale = render_scale


## True when the game is running inside the editor's embedded Game panel.
##
## Godot 4.4 added that panel and it is on by default. The game it runs is a real
## process with a real renderer, but its window is a child of the editor's
## layout: [method DisplayServer.window_set_size] is a hard no-op there that logs
## [code]Embedded window can't be resized.[/code] and returns. That is not a
## degraded case worth working around -- there is no window to resize -- it is a
## case worth SAYING, which is what [member window_resize_refused] and the note
## on the video tab are for.
static func is_embedded() -> bool:
	return DisplayServer.get_name() == EMBEDDED_DISPLAY


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
## It writes the RULES a player chose and nothing else. The line between the two
## is the same one [MatchRules] draws in its own header: what the round IS is a
## rule and can be chosen; what a component is made of is tuning and cannot.
## Ghost TUNING -- pace, catch radius, grace -- is [GhostProfile]; the rifle's
## reload curve, the track radius, the arrival tolerance and the AI profiles are
## the same kind of number. A player who wants to retune those is sweeping the
## game, not playing it, and none of them are on the setup screen.
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
	rules.reload_seconds_by_turn = reload_by_turn.duplicate()
	# Every one of these is written unconditionally too, and for the reason given
	# above: the rules resource is one shared instance for the whole process, so
	# a value only written when it is non-default leaves a match started after a
	# change back still playing the old one.
	rules.prisoner_count = prisoner_count
	rules.prisoner_lives = prisoner_lives
	rules.shooter_win_condition = shooter_win_condition
	# Both numbers are written whatever condition is chosen, so that switching to
	# SHUTOUT_COUNT or HOLD_DURATION never lands on the 0 = unset the rules
	# resource ships with -- which is a round the tower cannot win.
	rules.shutout_count = shutout_count
	rules.hold_duration_seconds = hold_duration_seconds
	rules.runner_win_condition = runner_win_condition
	rules.rounds_to_win_match = rounds_to_win_match
	rules.runner_ability = runner_ability
	rules.map_id = map_id
	# Air control is not written here. It is no longer a player preference --
	# see [AirControlCatalog] -- so [member MatchRules.air_control_id] is left at
	# its own default and every match runs it.


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


## Read a [StringName], tolerating a [String] and rejecting anything else. An
## empty value is rejected too: the caller's fallback is a real id and an empty
## one would name no map.
## The OS username, or "Player" when the environment does not say.
static func default_player_name() -> String:
	for key: String in ["USER", "USERNAME", "LOGNAME"]:
		var found: String = OS.get_environment(key).strip_edges()
		if not found.is_empty():
			return found.left(MAX_PLAYER_NAME_LENGTH)
	return "Player"


static func read_string_name(
	config: ConfigFile, section: String, key: String, fallback: StringName
) -> StringName:
	var raw: Variant = config.get_value(section, key, fallback)
	var kind: int = typeof(raw)
	if kind != TYPE_STRING and kind != TYPE_STRING_NAME:
		return fallback
	var value: String = String(raw)
	return StringName(value) if not value.is_empty() else fallback


## Read a [PackedFloat32Array], rejecting anything else. [method clamp_all]
## repairs a wrong size or an out-of-range value; this only guards the type.
static func read_packed_float32_array(
	config: ConfigFile, section: String, key: String, fallback: PackedFloat32Array
) -> PackedFloat32Array:
	if not config.has_section_key(section, key):
		return fallback
	var raw: Variant = config.get_value(section, key, fallback)
	if typeof(raw) != TYPE_PACKED_FLOAT32_ARRAY:
		return fallback
	return raw


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
