class_name MapCatalog
extends Resource

## Every map the game has, in one list, read by everything that needs to know.
##
## [b]Two things in one file, deliberately.[/b] This script is both the resource
## type of [code]resources/maps/map_catalog.tres[/code] -- an ordered array of
## [MapDefinition] -- and the static accessor everything else uses. The
## alternative was a second class whose only job was to [method load] the first,
## and one more indirection to explain.
##
## [b]Adding a map is data.[/b]
## [codeblock]
##   1. author scenes/<something>/<map>.tscn
##   2. add resources/maps/<map>.tres, a MapDefinition naming it
##   3. append that .tres to maps[] in resources/maps/map_catalog.tres
## [/codeblock]
## No script changes. The match setup screen's picker, [MatchController]'s
## arena, and the headless [BotMatchWorld] all read this list, so the new map is
## selectable, playable and sweepable the moment step 3 is saved.
##
## [b]Who reads it.[/b]
## [codeblock]
##   MapCatalog  ->  the picker on the match setup screen  (what exists)
##               ->  GameSettings.map_id                   (what was chosen)
##               ->  MatchRules.map_id                     (what the match runs)
##               ->  MatchController                       (what is instanced)
##               ->  BotMatchWorld                         (what a sweep runs)
## [/codeblock]
## Note the direction: nothing here reaches into a match. A map is named, and the
## thing that needs the scene asks this list for a path.

## The shipped list. Not a hard-coded map -- a hard-coded FILE, which is the one
## piece of this that cannot itself be data.
const CATALOG_PATH: String = "res://resources/maps/map_catalog.tres"

## The map a player who has chosen nothing plays, and the fallback for a
## settings file or a rules resource naming a map that no longer exists.
##
## It must be the id of an entry in the catalog; [code]tests/test_maps.gd[/code]
## asserts that, because a default that names nothing would leave a first run
## with no map at all.
const DEFAULT_ID: StringName = &"bentham_ring"

## Every map, in the order the picker shows them.
@export var maps: Array[MapDefinition] = []

## Loaded once and handed out. The catalog is read every time a control on the
## setup screen moves.
static var _shared: MapCatalog = null


## Every map the game has, in picker order. Never null; empty only if the
## catalog resource is missing, which is a broken install.
static func all() -> Array[MapDefinition]:
	var catalog: MapCatalog = shared()
	if catalog == null:
		return []
	return catalog.maps


## The catalog resource itself, loaded on first use.
static func shared() -> MapCatalog:
	if _shared == null:
		_shared = load(CATALOG_PATH) as MapCatalog
		if _shared == null:
			push_error("MapCatalog cannot load %s; no map can be chosen." % CATALOG_PATH)
	return _shared


## The map with [param id], or null.
static func by_id(id: StringName) -> MapDefinition:
	if String(id).is_empty():
		return null
	for map: MapDefinition in all():
		if map != null and map.id == id:
			return map
	return null


## The default map: [constant DEFAULT_ID] if the catalog has it, else the first
## entry, else null. The fallback chain exists so that renaming the default out
## from under this constant degrades to "the player gets a map" rather than to
## "the player gets a black screen".
static func default_map() -> MapDefinition:
	var map: MapDefinition = by_id(DEFAULT_ID)
	if map != null:
		return map
	var every: Array[MapDefinition] = all()
	return every[0] if not every.is_empty() else null


## The position of [param id] in [method all], or -1. The picker fills its items
## with these, exactly as the mode picker uses preset indices.
static func index_of(id: StringName) -> int:
	var every: Array[MapDefinition] = all()
	for index: int in every.size():
		if every[index] != null and every[index].id == id:
			return index
	return -1


## The scene path of the map named by [param id], falling back to the default
## map, or [code]""[/code] if there is no catalog at all.
##
## This is the one method [MatchController] and [BotMatchWorld] call. It falls
## back rather than failing because the callers are a running match and an
## unattended sweep: an unknown id is a stale settings file or a hand-edited
## rules resource, and neither is a reason to hand the player an empty world.
static func scene_path_for(id: StringName) -> String:
	var map: MapDefinition = by_id(id)
	if map == null:
		map = default_map()
	return map.scene_path if map != null else ""


## True when [param id] names a map that exists. What
## [method GameSettings.clamp_all] asks before it keeps a saved choice.
static func has(id: StringName) -> bool:
	return by_id(id) != null


## Drop the cached catalog so the next call re-reads it. For tests; the game
## never calls it.
static func forget() -> void:
	_shared = null
