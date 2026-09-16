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


# --- The map the rules name is the map that stands ----------------------------

## A body's eye above its feet, for the sight lines.
const EYE_METRES: float = 1.6
## A standing body's feet are on the deck: the drop from the eye is the eye's height.
const FOOTING_METRES: float = 0.3

## Every map in the catalog, installed by [MatchController] into the shipped
## match scene, stands in the tree in the authored arena's place -- with the
## arena it replaced gone, the human on the lane and the tower in plain sight.
##
## The scene's root refuses add_child/remove_child while it is still entering
## the tree, which is when [method MatchController._ready] used to swap: both
## calls failed, the old arena was freed anyway and the match ran in a void.
func test_every_map_stands_in_the_match_scene_when_the_rules_name_it() -> void:
	for map: MapDefinition in MapCatalog.all():
		var match_root: Node3D = TestFixtures.make_match()
		var controller: MatchController = match_root.get_node(^"MatchController") as MatchController
		var rules: MatchRules = TestFixtures.match_rules()
		rules.map_id = map.id
		controller.rules = rules
		add_child(match_root)

		var arena: Node3D = match_root.get_node_or_null(^"Arena") as Node3D
		assert_not_null(arena, "%s: the match has an Arena" % map.id)
		if arena != null:
			assert_same(controller.arena, arena, "%s: and it is the controller's arena" % map.id)
			assert_eq_string(arena.scene_file_path, map.scene_path, "%s: the arena is the map" % map.id)
		var arenas: int = 0
		for child: Node in match_root.get_children():
			if child is Node3D and not child.scene_file_path.is_empty() and child.scene_file_path.begins_with("res://scenes/ring/"):
				arenas += 1
		assert_eq_int(arenas, 1, "%s: one arena in the scene, the replaced one gone" % map.id)
		assert_true(_surfaces_have_materials(arena, map.id), "%s: every surface has a material" % map.id)

		await step_ticks(3)
		var participants: Array[MatchParticipant] = controller.get_participants()
		assert_gt(float(participants.size()), 0.0, "%s: the match has participants" % map.id)
		if not participants.is_empty() and participants[0].body != null:
			_assert_on_the_lane_facing_the_tower(map.id, controller, participants[0].body)
		match_root.free()


func _assert_on_the_lane_facing_the_tower(
	map_id: StringName, controller: MatchController, body: PlayerController
) -> void:
	var route: RingRoute = controller.get_route()
	assert_not_null(route, "%s: the match has a route" % map_id)
	if route == null:
		return
	var centre: Vector3 = controller.arena.global_position
	var feet: Vector3 = body.global_position
	var radius: float = Vector2(feet.x - centre.x, feet.z - centre.z).length()
	var level: RingLevel = route.level_at(0)
	assert_between(radius, level.inner_radius, level.outer_radius, "%s: the human stands on the lane" % map_id)
	assert_almost_eq(feet.y, level.deck_height, 1.5, "%s: at deck height" % map_id)

	# The field is dealt across the lane, so the other bodies stand in the way.
	var bodies: Array[RID] = []
	for participant: MatchParticipant in controller.get_participants():
		if participant.body != null:
			bodies.append(participant.body.get_rid())
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var eye: Vector3 = feet + Vector3.UP * EYE_METRES
	var down := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.DOWN * (EYE_METRES + FOOTING_METRES))
	down.exclude = bodies
	var footing: Dictionary = space.intersect_ray(down)
	assert_false(footing.is_empty(), "%s: the human's feet are on the deck" % map_id)

	# What the eye sees looking at the tower's foot is the map -- the tower, or
	# the lane's own cover -- and never the void a freed arena leaves.
	var tower: Node3D = (controller.arena.get_node(TestFixtures.TOWER_SPAWN_PATH) as Marker3D).get_parent_node_3d()
	var sight := PhysicsRayQueryParameters3D.create(eye, tower.global_position)
	sight.exclude = bodies
	var seen: Dictionary = space.intersect_ray(sight)
	var seen_node: Node = seen.get("collider", null) as Node
	assert_true(
		seen_node != null and controller.arena.is_ancestor_of(seen_node),
		"%s: the sight line to the tower lands on the map, not on nothing" % map_id
	)


func _surfaces_have_materials(arena: Node, map_id: StringName) -> bool:
	var sound: bool = true
	for node: Node in arena.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			if mesh.get_active_material(surface) == null:
				sound = false
				fail("%s: %s surface %d has no material" % [map_id, mesh.name, surface])
	return sound
