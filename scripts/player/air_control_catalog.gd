class_name AirControlCatalog
extends Resource

## Every air-control preset the game offers, in one list, read by everything that
## needs to know.
##
## [b]Two things in one file, deliberately.[/b] This script is both the resource
## type of [code]resources/movement/air_control_catalog.tres[/code] -- an ordered
## array of [AirControlPreset] -- and the static accessor everything else uses.
## The same shape as [MapCatalog], and for the same reason: the alternative was a
## second class whose only job was to [method load] the first.
##
## [b]Why the presets needed a catalog at all.[/b] They were authored for the
## movement playground, where the set on offer is typed into
## [code]scenes/dev/movement_playground.tscn[/code] and cycled with a key. That
## is the right shape for a dev scene. A settings file can hold a NAME but not a
## scene's array, so the presets are named -- see [member AirControlPreset.id]
## -- and this is the one list of what exists, independent of any menu.
##
## [b]Who reads it.[/b] There is no picker any more: Carve is [constant
## DEFAULT_ID], and that is the end of the question.
## [codeblock]
##   AirControlCatalog  ->  MatchRules.air_control_id  (what the match runs, at its own default)
##                      ->  MatchController             (what every body runs)
## [/codeblock]
## Note the direction, which is [MapCatalog]'s: nothing here reaches into a
## match. A preset is named, and the thing that needs a [MovementProfile] asks
## this list to build one.
##
## [b]Adding a preset is data[/b] -- a [code].tres[/code] in
## [code]resources/movement/[/code] and an entry in the catalog below, with no
## edit to [MatchController]. The playground's own list is separate and stays
## that way: it is a scene's authored array, and a dev scene is allowed to offer
## a set that is not the shipped one.

## The shipped list. Not a hard-coded preset -- a hard-coded FILE, which is the
## one piece of this that cannot itself be data.
const CATALOG_PATH: String = "res://resources/movement/air_control_catalog.tres"

## The preset every match runs, and the only one a player reaches -- there is no
## picker any more; see [MatchSetupScreen]. Also the fallback for a rules
## resource naming a preset that no longer exists.
##
## Carve. Committed was the tuning the game shipped with, and
## [code]tests/test_air_control_presets.gd[/code] still holds IT identical to
## [code]scenes/player/default_movement_profile.tres[/code] -- that fact is
## about [code]air_control_01_committed.tres[/code], not about this constant,
## and does not move when this does. The other three presets stay on disk and
## in the movement playground, unplayed but not deleted.
const DEFAULT_ID: StringName = &"carve"

## Every preset, in the order the picker shows them.
@export var presets: Array[AirControlPreset] = []

## Loaded once and handed out. The catalog is read every time the picker moves.
static var _shared: AirControlCatalog = null


## Every preset the game offers, in picker order. Never null; empty only if the
## catalog resource is missing, which is a broken install.
static func all() -> Array[AirControlPreset]:
	var catalog: AirControlCatalog = shared()
	if catalog == null:
		return []
	return catalog.presets


## The catalog resource itself, loaded on first use.
static func shared() -> AirControlCatalog:
	if _shared == null:
		_shared = load(CATALOG_PATH) as AirControlCatalog
		if _shared == null:
			push_error(
				"AirControlCatalog cannot load %s; no air control can be chosen." % CATALOG_PATH
			)
	return _shared


## The preset with [param id], or null.
static func by_id(id: StringName) -> AirControlPreset:
	if String(id).is_empty():
		return null
	for preset: AirControlPreset in all():
		if preset != null and preset.id == id:
			return preset
	return null


## The default preset: [constant DEFAULT_ID] if the catalog has it, else the
## first entry, else null. The fallback chain exists so that renaming the default
## out from under this constant degrades to "the player gets air control" rather
## than to "the player gets a body with no profile".
static func default_preset() -> AirControlPreset:
	var preset: AirControlPreset = by_id(DEFAULT_ID)
	if preset != null:
		return preset
	var every: Array[AirControlPreset] = all()
	return every[0] if not every.is_empty() else null


## The position of [param id] in [method all], or -1. The picker fills its items
## with these, exactly as the map picker uses catalog positions.
static func index_of(id: StringName) -> int:
	var every: Array[AirControlPreset] = all()
	for index: int in every.size():
		if every[index] != null and every[index].id == id:
			return index
	return -1


## True when [param id] names a preset that exists. What
## [method GameSettings.clamp_all] asks before it keeps a saved choice.
static func has(id: StringName) -> bool:
	return by_id(id) != null


## What the preset named by [param id] is called on screen, falling back to the
## default preset's name, or [code]""[/code] with no catalog at all.
static func display_name_for(id: StringName) -> String:
	var preset: AirControlPreset = by_id(id)
	if preset == null:
		preset = default_preset()
	return preset.display_name if preset != null else ""


## A fresh [MovementProfile] running the air control [param id] names, falling
## back to the default preset.
##
## [b]This is the one method [MatchController] calls.[/b] It falls back rather
## than failing for [method MapCatalog.scene_path_for]'s reason: the caller is a
## running match, and an unknown id is a stale settings file, not a reason to
## hand the player a body that cannot move.
##
## [b]A fresh profile every call, and that is load-bearing.[/b]
## [method AirControlPreset.build] duplicates
## [code]scenes/player/default_movement_profile.tres[/code], which is the single
## process-wide instance every scene, every bot and every test is holding.
## Handing that object out and then writing air control into it would retune the
## shipped game from a menu. See [method AirControlPreset.build].
static func profile_for(id: StringName) -> MovementProfile:
	var preset: AirControlPreset = by_id(id)
	if preset == null:
		preset = default_preset()
	return preset.build() if preset != null else null


## Everything wrong with the shipped catalog, in words, or an empty array.
## Mirrors [method MatchRules.validate]: the tests ask, nothing asserts.
static func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var every: Array[AirControlPreset] = all()
	if every.is_empty():
		problems.append("the air control catalog is empty; the picker would have nothing in it.")
	var seen: Array[StringName] = []
	for preset: AirControlPreset in every:
		if preset == null:
			problems.append("the air control catalog has a null entry.")
			continue
		problems.append_array(preset.validate())
		if seen.has(preset.id):
			problems.append(
				"air control id %s appears twice; a settings file naming it is ambiguous."
				% preset.id
			)
		seen.append(preset.id)
	if by_id(DEFAULT_ID) == null:
		problems.append(
			"the default air control %s is in no catalog; a first run would fall back."
			% DEFAULT_ID
		)
	return problems


## Drop the cached catalog so the next call re-reads it. For tests; the game
## never calls it.
static func forget() -> void:
	_shared = null
