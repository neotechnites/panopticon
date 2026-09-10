extends TestCase

## The map registry: what maps exist, and that the one the game ships is the one
## the game actually plays.
##
## [b]The defect this pins[/b]
##
## The arena was called [code]test_ring.tscn[/code] and was reachable only by
## being hard-coded in four places -- the match scene, the bot harness, the test
## fixtures and [MatchController]'s own header. There was no list of maps, so
## there was nothing for a player to choose from and nothing for a second map to
## be added to. [MapCatalog] is that list, and these tests hold it to three
## promises:
##
## [codeblock]
##   every entry names a scene that exists     (a picker cannot offer a hole)
##   the default is IN the list                (a first run gets a map)
##   what the list names is what is played     (the match scene, the harness)
## [/codeblock]
##
## The third is the one worth the file. A registry that everything reads and
## nothing obeys is a configuration screen for a constant, so the map named in
## [code]resources/maps/map_catalog.tres[/code] is compared against the arena
## [code]scenes/match/match.tscn[/code] actually composes and against the arena
## [BotMatchWorld] would load for a sweep.

const MATCH_RULES_PATH: String = "res://resources/rules/default_match_rules.tres"

## An id no map will ever have, for the fallback tests.
const ABSENT_ID: StringName = &"a_map_that_does_not_exist"


# --- The catalog --------------------------------------------------------------

func test_the_catalog_loads_and_holds_at_least_one_map() -> void:
	var catalog: MapCatalog = MapCatalog.shared()
	assert_not_null(catalog, "%s loads" % MapCatalog.CATALOG_PATH)
	assert_gt(float(MapCatalog.all().size()), 0.0, "and it names at least one map")


## Every entry is a map a picker can offer and a match can load.
func test_every_map_is_named_described_and_loadable() -> void:
	var seen: Array[StringName] = []
	for map: MapDefinition in MapCatalog.all():
		assert_not_null(map, "no empty slot in the catalog")
		if map == null:
			continue
		for problem: String in map.validate():
			assert_true(false, problem)
		assert_true(map.is_playable(), "%s is playable" % map.id)
		assert_false(seen.has(map.id), "%s is the only map with that id" % map.id)
		seen.append(map.id)


## The default has to BE in the list, or a first run has no map at all.
func test_the_default_map_is_in_the_catalog_and_is_offered_first() -> void:
	var map: MapDefinition = MapCatalog.by_id(MapCatalog.DEFAULT_ID)
	assert_not_null(map, "the catalog holds %s" % MapCatalog.DEFAULT_ID)
	assert_same(MapCatalog.default_map(), map, "and it is the default map")
	assert_eq_int(MapCatalog.index_of(MapCatalog.DEFAULT_ID), 0, "and the picker shows it first")


## An id from an older build, a newer build or a hand-edited file still produces
## a scene. The alternative is a match with no arena, which is a black screen.
func test_an_unknown_id_falls_back_to_a_playable_map() -> void:
	assert_null(MapCatalog.by_id(ABSENT_ID), "an unknown id names no map")
	assert_false(MapCatalog.has(ABSENT_ID), "and has() says so")
	var fallback: String = MapCatalog.scene_path_for(ABSENT_ID)
	assert_eq_string(
		fallback, MapCatalog.default_map().scene_path, "but it still resolves to the default map"
	)
	assert_eq_string(
		MapCatalog.scene_path_for(&""), fallback, "and so does naming no map at all"
	)


# --- The map the registry names is the map that is played ---------------------

## The arena the catalog names carries the three markers [MatchController] reads
## its geometry from. A renamed scene that no longer has them would pass every
## other test in this file and fail every match.
func test_the_default_map_carries_the_markers_the_match_reads() -> void:
	var path: String = MapCatalog.default_map().scene_path
	var packed: PackedScene = load(path) as PackedScene
	assert_not_null(packed, "%s loads as a scene" % path)
	if packed == null:
		return
	var arena: Node3D = packed.instantiate() as Node3D
	assert_not_null(arena, "and instances as a Node3D")
	if arena == null:
		return
	assert_not_null(
		arena.get_node_or_null(TestFixtures.START_MARKER_PATH), "it has a prisoner start"
	)
	assert_not_null(arena.get_node_or_null(TestFixtures.END_MARKER_PATH), "it has a prisoner end")
	assert_not_null(arena.get_node_or_null(TestFixtures.TOWER_SPAWN_PATH), "it has a tower spawn")
	arena.free()


## The match scene composes the map the catalog names -- by scene path, not by
## resemblance. This is what stops the registry from being a list nobody obeys.
func test_the_match_scene_ships_the_map_the_catalog_names() -> void:
	var match_root: Node3D = TestFixtures.make_match()
	var arena: Node3D = match_root.get_node_or_null(^"Arena") as Node3D
	assert_not_null(arena, "the match scene has an Arena")
	if arena != null:
		assert_eq_string(
			arena.scene_file_path,
			MapCatalog.default_map().scene_path,
			"and it is the default map, not some other arena",
		)
	match_root.free()


## The tests load the same arena the catalog does. [TestFixtures] holds its own
## path so a test can build an arena without a catalog; the two must not drift.
func test_the_test_fixtures_load_the_map_the_catalog_names() -> void:
	assert_eq_string(
		TestFixtures.ARENA_SCENE_PATH,
		MapCatalog.default_map().scene_path,
		"the fixtures and the catalog name one arena",
	)


## A headless sweep runs the map its rules name, so a measurement is always
## attributable to a place.
func test_the_harness_loads_the_map_the_rules_name() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	assert_eq_string(
		BotMatchWorld.resolve_arena_path(rules),
		MapCatalog.scene_path_for(rules.map_id),
		"the harness resolves the arena through the catalog",
	)
	rules.map_id = ABSENT_ID
	assert_eq_string(
		BotMatchWorld.resolve_arena_path(rules),
		MapCatalog.default_map().scene_path,
		"and an unknown map still gives it something to run",
	)


# --- The map as a rule --------------------------------------------------------

## The shipped rules, the code default and the catalog default all name the same
## map. Any two of them disagreeing means the first match a player starts is
## played somewhere nobody chose -- the same argument the canon rules make in
## [code]tests/test_match_setup.gd[/code].
func test_the_shipped_defaults_all_name_the_default_map() -> void:
	var shipped: MatchRules = load(MATCH_RULES_PATH) as MatchRules
	assert_not_null(shipped, "the shipped rules resource loads")
	if shipped != null:
		assert_eq_string(
			String(shipped.map_id), String(MapCatalog.DEFAULT_ID), "the shipped rules"
		)
	assert_eq_string(
		String(MatchRules.new().map_id), String(MapCatalog.DEFAULT_ID), "MatchRules' own default"
	)
	assert_eq_string(
		String(GameSettings.DEFAULT_MAP_ID), String(MapCatalog.DEFAULT_ID), "the preference default"
	)
	assert_eq_string(
		String(GameSettings.new().map_id), String(MapCatalog.DEFAULT_ID), "a fresh preference"
	)


## Rules naming a map that is not in the catalog say so rather than failing.
func test_rules_naming_an_absent_map_are_reported_by_validate() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	assert_false(_mentions_map(rules.validate()), "the shipped map draws no complaint")
	rules.map_id = ABSENT_ID
	assert_true(_mentions_map(rules.validate()), "an absent map does")


## A settings file naming a map that no longer exists loses the choice, not the
## match.
func test_an_unknown_saved_map_is_clamped_to_the_default() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.map_id = ABSENT_ID
	settings.clamp_all()
	assert_eq_string(
		String(settings.map_id), String(GameSettings.DEFAULT_MAP_ID), "clamped to the default"
	)


## The chosen map survives a save and a load.
func test_the_map_choice_round_trips_through_the_config_file() -> void:
	var written: GameSettings = GameSettings.new()
	written.map_id = MapCatalog.default_map().id

	var config: ConfigFile = ConfigFile.new()
	written.write_to(config)

	var read_back: GameSettings = GameSettings.new()
	read_back.map_id = ABSENT_ID
	read_back.read_from(config)
	assert_eq_string(
		String(read_back.map_id), String(written.map_id), "the map came back off the file"
	)
	assert_true(read_back.equals(written), "and nothing else moved")


## A file that predates the map picker plays the default map rather than junk.
func test_a_settings_file_without_a_map_key_plays_the_default() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(GameSettings.SECTION_MATCH, "prisoner_count", 4)

	var settings: GameSettings = GameSettings.new()
	settings.read_from(config)
	assert_eq_string(
		String(settings.map_id), String(GameSettings.DEFAULT_MAP_ID), "an old file still has a map"
	)


## A junk value in the file is not believed.
func test_a_junk_map_key_is_rejected() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(GameSettings.SECTION_MATCH, "map_id", 17)

	var settings: GameSettings = GameSettings.new()
	settings.read_from(config)
	settings.clamp_all()
	assert_eq_string(
		String(settings.map_id), String(GameSettings.DEFAULT_MAP_ID), "a number is not a map id"
	)


# --- Helpers ------------------------------------------------------------------

static func _mentions_map(problems: PackedStringArray) -> bool:
	for problem: String in problems:
		if problem.begins_with("map_id"):
			return true
	return false
