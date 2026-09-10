class_name MapDefinition
extends Resource

## One map, as data: what it is called, what it is, and where its scene lives.
##
## [b]Why a resource and not a constant in a script.[/b] The game has one arena
## today and the vertical slice requires the player to CHOOSE it. A choice of one
## is still a choice, and the thing that makes it one is that the list is data:
## adding the second map must be a [code].tres[/code] file and an entry in
## [code]resources/maps/map_catalog.tres[/code], not an edit to the setup screen,
## to [MatchController] or to the bot harness. Everything that needs to know what
## maps exist -- the match setup screen and [BotMatchWorld] -- reads them through
## [MapCatalog], so there is one list and no second opinion.
##
## [b]What is NOT here.[/b] Arena geometry. [member MatchRules.track_radius],
## [member MatchRules.start_line_spacing_metres] and
## [member MatchRules.lap_arrival_tolerance] are numbers the ring was measured
## for and they still live on [MatchRules], where the harness sweeps them. A map
## that needed different ones would be the moment to move them here; today
## claiming to own them would be a lie in a file.

## Stable identity. Written into [member MatchRules.map_id] and into the player's
## settings file, so it is the one field that may never be renamed casually: a
## saved preference naming a map id that no longer exists falls back to the
## default map, silently, and the player's choice is gone.
@export var id: StringName = &""

## What the map is called, as the map picker shows it.
@export var title: String = ""

## One sentence under the picker: what running this map IS. A description, not a
## warning, exactly as [member MatchPresets.Preset.summary] is.
@export_multiline var summary: String = ""

## The arena scene. Instanced as the [code]Arena[/code] node of a match -- see
## [method MatchController.get_map_scene_path] -- and by [BotMatchWorld] for a
## headless sweep.
@export_file("*.tscn") var scene_path: String = ""


## True when this entry names a map that can actually be loaded.
##
## Checked rather than assumed because the failure it guards is a map that is
## offered in the picker, chosen by the player, and then not there: a typo in
## [member scene_path] would otherwise reach the player as an empty match.
func is_playable() -> bool:
	return not String(id).is_empty() and not scene_path.is_empty() and ResourceLoader.exists(scene_path)


## Everything wrong with this entry, in words, or an empty array. Mirrors
## [method MatchRules.validate]: the harness and the tests ask, nothing asserts.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if String(id).is_empty():
		problems.append("a map has no id; nothing can name it in a settings file or a rules resource.")
	if title.is_empty():
		problems.append("map %s has no title; the picker would show a blank row." % id)
	if summary.is_empty():
		problems.append("map %s does not say what it is." % id)
	if scene_path.is_empty():
		problems.append("map %s names no scene." % id)
	elif not ResourceLoader.exists(scene_path):
		problems.append("map %s names %s, which does not exist." % [id, scene_path])
	return problems
