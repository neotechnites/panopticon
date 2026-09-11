extends TestCase

## The match setup screen: from the controls the player clicks to the
## [MatchRules] the match is actually played under.
##
## [b]The defect this pins[/b]
##
## [MatchRules] carries every design parameter of a round and only two of them
## were reachable from a menu. This screen exposes a curated set of the rest, and
## every one of them travels the same four links the ghost toggle already does --
## see [code]tests/test_match_settings.gd[/code], which pins that one end to end:
##
## [codeblock]
##   a control on the screen -> GameSettings                 (the screen)
##   GameSettings            -> user://settings.cfg          (the round trip)
##   GameSettings            -> MatchRules                   (apply_to_match_rules)
##   SettingsBoot            -> the rules the controller runs (the scene wiring)
## [/codeblock]
##
## A test of any one link alone would pass while the screen did nothing, which is
## the failure mode this file exists to catch: a value that saves, reloads,
## displays correctly and reaches nothing. The last link is asserted by IDENTITY
## -- the very object, not an equal one -- because the way this breaks in
## practice is a second copy of the rules resource that everything writes to and
## nothing plays.
##
## [b]Canon has to be the default in every place that has an opinion[/b]
##
## Four files hold a view of what the canon round is: the code defaults in
## [MatchRules], the shipped [code]resources/rules/default_match_rules.tres[/code],
## the preference defaults in [GameSettings], and the canon entry in
## [MatchPresets]. If any two disagree, the first match a player starts is played
## under a rule set nobody chose. Several tests below do nothing but hold those
## four in step.
##
## [b]The shared store and the shipped resource, and putting both back[/b]
##
## [method SettingsStore.instance] is process-wide and the shipped rules resource
## is one cached object for the whole process. Every test here redirects the
## store to a scratch file and snapshots both, and [method after_each] puts them
## back -- a test that left six prisoners in the singleton would hand every later
## test in the same process a different game.

const SETUP_SCREEN_PATH: String = "res://scenes/ui/match_setup_screen.tscn"
const MATCH_RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const SCRATCH_CONFIG: String = "user://test_match_setup.cfg"

var _real_config_path: String = ""
var _real_settings: GameSettings = GameSettings.new()
var _real_rules: MatchRules = MatchRules.new()


func before_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	_real_config_path = store.config_path
	_real_settings.copy_from(store.settings)
	store.config_path = SCRATCH_CONFIG

	# The shipped resource is shared; anything written into it here is written
	# into every later test's game unless it is put back.
	var shipped: MatchRules = _shipped_rules()
	if shipped != null:
		_copy_exposed_rules(shipped, _real_rules)


func after_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.erase_file()
	store.config_path = _real_config_path
	store.settings.copy_from(_real_settings)

	var shipped: MatchRules = _shipped_rules()
	if shipped != null:
		_copy_exposed_rules(_real_rules, shipped)


# --- Canon is the default, everywhere that has an opinion ---------------------

## A player who never opens this screen is already playing canon.
func test_a_fresh_settings_object_is_playing_canon() -> void:
	var settings: GameSettings = GameSettings.new()
	assert_true(MatchPresets.is_canon(settings), "the shipped preference defaults are canon")

	var preset: MatchPresets.Preset = MatchPresets.canon()
	assert_not_null(preset, "there is a preset with the canon id")
	if preset == null:
		return
	assert_eq_int(MatchPresets.all().find(preset), 0, "and it is first in the picker")


## The canon preset and the rules resource the game ships agree, field for field.
##
## This is the one that catches a retune: change a number in
## default_match_rules.tres without changing the preset and the mode named Canon
## stops being the game.
func test_canon_agrees_with_the_shipped_rules() -> void:
	var preset: MatchPresets.Preset = MatchPresets.canon()
	var shipped: MatchRules = _shipped_rules()
	assert_not_null(shipped, "the shipped rules resource loads")
	if preset == null or shipped == null:
		return
	assert_eq_int(preset.prisoner_count, shipped.prisoner_count, "prisoner count")
	assert_eq_int(preset.prisoner_lives, shipped.prisoner_lives, "prisoner lives")
	assert_eq_int(
		int(preset.shooter_win_condition), int(shipped.shooter_win_condition), "shooter win"
	)
	assert_eq_int(
		int(preset.runner_win_condition), int(shipped.runner_win_condition), "runner win"
	)
	assert_eq_int(preset.rounds_to_win_match, shipped.rounds_to_win_match, "rounds to win")
	assert_true(preset.ghosts_enabled == shipped.has_ghosts(), "ghosts")
	assert_true(preset.skip_opening_race != shipped.open_with_race, "the opening race")


## Every preset is a named, described, distinct way to play.
func test_every_preset_is_named_and_distinct() -> void:
	var seen_ids: Array[StringName] = []
	for preset: MatchPresets.Preset in MatchPresets.all():
		assert_false(String(preset.id).is_empty(), "a preset has an id")
		assert_false(preset.title.is_empty(), "%s has a title" % preset.id)
		assert_false(preset.summary.is_empty(), "%s says what it is" % preset.id)
		assert_false(seen_ids.has(preset.id), "%s is the only preset with that id" % preset.id)
		seen_ids.append(preset.id)


## Applying a preset makes it the preset that describes the settings.
##
## [method MatchPresets.describing] is what the picker reads, so this is what
## stops two modes being indistinguishable and the picker naming the wrong one.
func test_each_preset_is_the_one_that_describes_its_own_rules() -> void:
	var settings: GameSettings = GameSettings.new()
	for preset: MatchPresets.Preset in MatchPresets.all():
		preset.apply_to(settings)
		assert_same(
			MatchPresets.describing(settings),
			preset,
			"%s describes the settings it just wrote" % preset.id,
		)


## An override makes the picker read Custom rather than keep naming a mode the
## player is no longer playing.
func test_overriding_a_preset_reads_as_custom() -> void:
	var settings: GameSettings = GameSettings.new()
	assert_true(MatchPresets.is_canon(settings), "starts on canon")
	settings.prisoner_count = GameSettings.DEFAULT_PRISONER_COUNT + 1
	assert_null(MatchPresets.describing(settings), "one changed rule and it is no longer a mode")


# --- The preferences themselves -----------------------------------------------

## Every exposed rule survives a save and a load.
func test_the_preferences_round_trip_through_the_config_file() -> void:
	var written: GameSettings = GameSettings.new()
	written.prisoner_count = 5
	written.prisoner_lives = 2
	written.rounds_to_win_match = 3
	written.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	written.ghosts_enabled = false
	written.skip_opening_race = true
	written.tower_seat_index = 2

	var config: ConfigFile = ConfigFile.new()
	written.write_to(config)

	var read_back: GameSettings = GameSettings.new()
	read_back.read_from(config)
	assert_true(read_back.equals(written), "every match preference came back unchanged")


## A settings file that predates this screen loads as canon rather than as junk.
##
## The keys are simply absent, and an absent key is the current value -- which
## [method SettingsStore.load_from_disk] has just reset to the default. No
## migration constant is needed for that, and this test is what says so.
func test_a_settings_file_without_the_new_keys_loads_as_canon() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(GameSettings.SECTION_AUDIO, "master_volume", 0.5)

	var settings: GameSettings = GameSettings.new()
	settings.read_from(config)
	assert_true(MatchPresets.is_canon(settings), "an old file still plays canon")


## A hand-edited file cannot put an unplayable number into the game.
func test_wild_values_are_clamped() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.prisoner_count = 9999
	settings.prisoner_lives = -4
	settings.rounds_to_win_match = 0
	# Through variables rather than as literal casts: an int CONSTANT cast to an
	# enum member that does not exist is itself a warning, and this project treats
	# warnings as errors. The value being wild is the point of the test.
	var wild_high: int = 99
	var wild_low: int = -1
	settings.shooter_win_condition = wild_high as MatchRules.ShooterWinCondition
	settings.runner_win_condition = wild_low as MatchRules.RunnerWinCondition
	settings.clamp_all()

	assert_eq_int(settings.prisoner_count, GameSettings.MAX_PRISONER_COUNT, "prisoner count")
	assert_eq_int(settings.prisoner_lives, GameSettings.MIN_PRISONER_LIVES, "prisoner lives")
	assert_eq_int(
		settings.rounds_to_win_match, GameSettings.MIN_ROUNDS_TO_WIN_MATCH, "rounds to win"
	)
	assert_between(
		float(settings.shooter_win_condition),
		0.0,
		float(MatchRules.ShooterWinCondition.size() - 1),
		"shooter win condition is inside its enum",
	)
	assert_between(
		float(settings.runner_win_condition),
		0.0,
		float(MatchRules.RunnerWinCondition.size() - 1),
		"runner win condition is inside its enum",
	)


## The preferences are written over the rules in BOTH directions.
##
## A one-way write is the classic settings bug that looks like it works, because
## the first test of it is always "turn it on".
func test_the_preferences_write_the_rules_both_ways() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	var settings: GameSettings = GameSettings.new()

	settings.prisoner_count = 6
	settings.prisoner_lives = 3
	settings.rounds_to_win_match = 4
	settings.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	settings.apply_to_match_rules(rules)
	assert_eq_int(rules.prisoner_count, 6, "six prisoners reached the rules")
	assert_eq_int(rules.prisoner_lives, 3, "three lives reached the rules")
	assert_eq_int(rules.rounds_to_win_match, 4, "four rounds reached the rules")
	assert_eq_int(
		int(rules.runner_win_condition),
		int(MatchRules.RunnerWinCondition.ALL_ARRIVALS),
		"the runner win condition reached the rules",
	)

	settings.reset()
	settings.apply_to_match_rules(rules)
	assert_eq_int(rules.prisoner_count, GameSettings.DEFAULT_PRISONER_COUNT, "and came back")
	assert_eq_int(rules.prisoner_lives, GameSettings.DEFAULT_PRISONER_LIVES, "and came back")
	assert_eq_int(
		rules.rounds_to_win_match, GameSettings.DEFAULT_ROUNDS_TO_WIN_MATCH, "and came back"
	)
	assert_eq_int(
		int(rules.runner_win_condition),
		int(MatchRules.RunnerWinCondition.FIRST_ARRIVAL),
		"and came back",
	)


# --- The screen ---------------------------------------------------------------

## The screen opens showing canon, and says so.
func test_the_screen_opens_on_canon_and_says_so() -> void:
	SettingsStore.instance().settings.reset()
	var screen: MatchSetupScreen = _open_screen()
	assert_true(screen.is_canon(), "a fresh store opens the screen on canon")

	var badge: Label = screen.get_node("%PresetBadge") as Label
	assert_not_null(badge, "the screen has a badge")
	if badge != null:
		assert_eq_string(badge.text, "CANON", "and the badge names it")


## Moving a control moves the store. One assertion per control type on the
## screen -- a spin box, a check box and an option button -- because each reads
## its value back a different way and each has been got wrong before.
func test_the_controls_drive_the_store() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	var screen: MatchSetupScreen = _open_screen()

	var prisoners: SpinBox = screen.get_node("%PrisonerCountSpin") as SpinBox
	var ghosts: CheckBox = screen.get_node("%GhostsCheck") as CheckBox
	var runner_win: OptionButton = screen.get_node("%RunnerWinOption") as OptionButton
	var opening: OptionButton = screen.get_node("%OpeningOption") as OptionButton
	assert_not_null(prisoners, "the screen has a prisoner count")
	assert_not_null(ghosts, "the screen has a ghost toggle")
	assert_not_null(runner_win, "the screen has a runner win condition")
	assert_not_null(opening, "the screen has an opening")
	if prisoners == null or ghosts == null or runner_win == null or opening == null:
		return

	prisoners.value = 5.0
	assert_eq_int(store.settings.prisoner_count, 5, "the spin box wrote the prisoner count")

	ghosts.button_pressed = false
	assert_false(store.settings.ghosts_enabled, "the check box wrote the ghost preference")

	var all_arrivals: int = _index_with_id(
		runner_win, int(MatchRules.RunnerWinCondition.ALL_ARRIVALS)
	)
	runner_win.select(all_arrivals)
	runner_win.item_selected.emit(all_arrivals)
	assert_eq_int(
		int(store.settings.runner_win_condition),
		int(MatchRules.RunnerWinCondition.ALL_ARRIVALS),
		"the option button wrote the runner win condition",
	)

	# One control over two rules: "open on the ring" has to skip the race AND
	# move the tower off the human, or the player is still the guard.
	var on_the_ring: int = _index_with_id(opening, int(MatchSetupScreen.Opening.RING))
	opening.select(on_the_ring)
	opening.item_selected.emit(on_the_ring)
	assert_true(store.settings.skip_opening_race, "opening on the ring skips the race")
	assert_gt(
		float(store.settings.tower_seat_index),
		0.0,
		"and hands the tower to somebody who is not the player",
	)


## The map picker offers the maps that exist and writes the choice into the
## store.
##
## One map ships today, so this asserts the SHAPE -- one row per catalog entry,
## selecting a row writes that map's id -- rather than a number. A list of one is
## the correct thing to show and it must not read as broken: the row is enabled,
## it names the map, and the summary beside it says what the map is.
func test_the_map_picker_offers_every_map_and_writes_the_choice() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	var screen: MatchSetupScreen = _open_screen()

	var option: OptionButton = screen.get_node("%MapOption") as OptionButton
	var summary: Label = screen.get_node("%MapSummary") as Label
	assert_not_null(option, "the screen has a map picker")
	assert_not_null(summary, "and a line saying what the map is")
	if option == null or summary == null:
		return

	var maps: Array[MapDefinition] = MapCatalog.all()
	assert_eq_int(option.item_count, maps.size(), "one row per map in the catalog")
	assert_gt(float(option.item_count), 0.0, "and there is at least one")
	if maps.is_empty():
		return

	for index: int in option.item_count:
		assert_false(option.is_item_disabled(index), "every map offered can be chosen")
		assert_eq_string(
			option.get_item_text(index), maps[index].title, "the row names the map"
		)

	# Selecting the last entry -- which is the only entry today -- writes that
	# map's id and nothing else's.
	var last: int = option.item_count - 1
	option.select(last)
	option.item_selected.emit(last)
	assert_eq_string(
		String(store.settings.map_id), String(maps[last].id), "the picker wrote the map"
	)
	assert_eq_string(summary.text, maps[last].summary, "and the screen says what it is")


## Choosing a mode does not move the player off the map they chose. A map is a
## place, not a rule of the round, and no preset names one.
##
## Asserted against the preset's own property list rather than by watching a
## value, because with one map in the catalog a preset that DID write the map
## would write the same map and the watch would pass.
func test_no_preset_names_a_map() -> void:
	var settings: GameSettings = GameSettings.new()
	var chosen: StringName = settings.map_id
	for preset: MatchPresets.Preset in MatchPresets.all():
		assert_false(_has_property(preset, "map_id"), "%s names no map" % preset.id)
		preset.apply_to(settings)
		assert_eq_string(
			String(settings.map_id), String(chosen), "%s left the map alone" % preset.id
		)


## Every tower win condition is shown, and each is selectable exactly when the
## round implements it. All three are implemented today, so all three are live;
## the assertion is written against
## [method MatchRules.is_shooter_win_condition_implemented] rather than against a
## list of names, so the day a fourth is declared it is greyed out without this
## test being touched.
func test_win_conditions_are_selectable_exactly_when_implemented() -> void:
	var screen: MatchSetupScreen = _open_screen()
	var option: OptionButton = screen.get_node("%ShooterWinOption") as OptionButton
	assert_not_null(option, "the screen has a tower win condition")
	if option == null:
		return
	assert_eq_int(
		option.item_count, MatchRules.ShooterWinCondition.size(), "every condition is listed"
	)

	var probe: MatchRules = MatchRules.new()
	for index: int in option.item_count:
		probe.shooter_win_condition = option.get_item_id(index) as MatchRules.ShooterWinCondition
		assert_true(
			option.is_item_disabled(index) != probe.is_shooter_win_condition_implemented(),
			"%s is selectable exactly when it is implemented" % option.get_item_text(index),
		)


## Picking a mode sets every rule the mode names, in one click.
func test_choosing_a_preset_sets_every_rule() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	var screen: MatchSetupScreen = _open_screen()

	var option: OptionButton = screen.get_node("%PresetOption") as OptionButton
	assert_not_null(option, "the screen has a mode picker")
	if option == null:
		return

	var riot: MatchPresets.Preset = MatchPresets.by_id(&"riot")
	assert_not_null(riot, "there is a Riot mode")
	if riot == null:
		return
	var index: int = _index_with_id(option, MatchPresets.all().find(riot))
	option.select(index)
	option.item_selected.emit(index)

	assert_true(riot.describes(store.settings), "one click set the whole mode")
	assert_false(screen.is_canon(), "and the screen no longer claims canon")

	screen.restore_canon()
	assert_true(screen.is_canon(), "Restore Canon puts it back")


# --- The last link: the rules the match actually runs -------------------------

## What the screen chose reaches the rules the [MatchController] runs, and it is
## the SAME object -- not an equal one.
##
## This is the link that cannot be tested by behaviour without starting a match
## and the one most easily broken by a careless edit. Three references have to be
## one object: the resource named by path, the one [SettingsBoot] writes, and the
## one [MatchController] plays. If any of them is a copy, every control on the
## setup screen saves, reloads, displays and does nothing.
func test_the_setup_choice_reaches_the_rules_the_match_runs() -> void:
	var shipped: MatchRules = _shipped_rules()
	assert_not_null(shipped, "the shipped rules resource loads")
	if shipped == null:
		return

	# Instantiated and never added: entering the tree would start a match.
	var match_root: Node3D = TestFixtures.make_match()
	var boot: SettingsBoot = match_root.get_node_or_null(^"SettingsBoot") as SettingsBoot
	var controller: MatchController = (
		match_root.get_node_or_null(^"MatchController") as MatchController
	)
	assert_not_null(boot, "the match scene has a SettingsBoot")
	assert_not_null(controller, "the match scene has a MatchController")
	if boot == null or controller == null:
		match_root.free()
		return

	assert_same(boot.match_rules, controller.rules, "the boot writes the rules the match runs")
	assert_same(
		controller.rules,
		shipped,
		"and those are the very resource the setup screen's preferences are written into",
	)

	# And the write itself, on that object. before_each snapshotted it and
	# after_each puts it back, so this cannot leak into another test.
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	store.settings.prisoner_count = 6
	store.settings.prisoner_lives = 2
	store.settings.rounds_to_win_match = 3
	store.settings.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	store.settings.apply_to_match_rules(controller.rules)

	assert_eq_int(shipped.prisoner_count, 6, "the prisoner count landed on the match's rules")
	assert_eq_int(shipped.prisoner_lives, 2, "the lives landed on the match's rules")
	assert_eq_int(shipped.rounds_to_win_match, 3, "the match length landed on the match's rules")
	assert_eq_int(
		int(shipped.runner_win_condition),
		int(MatchRules.RunnerWinCondition.ALL_ARRIVALS),
		"the runner win condition landed on the match's rules",
	)
	assert_eq_int(
		shipped.get_participant_count(), 7, "and the roster the controller builds grew with it"
	)

	# The map takes the same door. Written verbatim -- an id the catalog does
	# not know is not corrected here, because correcting it is
	# GameSettings.clamp_all()'s job and doing it twice would hide the day this
	# link stopped working.
	store.settings.map_id = &"a_map_only_this_test_names"
	store.settings.apply_to_match_rules(controller.rules)
	assert_eq_string(
		String(shipped.map_id),
		"a_map_only_this_test_names",
		"the chosen map landed on the match's rules",
	)

	match_root.free()


# --- Fixtures -----------------------------------------------------------------

## The authored setup screen, in the tree and ready. Parented to this test, so
## the runner frees it whatever the test does.
func _open_screen() -> MatchSetupScreen:
	var screen: MatchSetupScreen = (
		(load(SETUP_SCREEN_PATH) as PackedScene).instantiate() as MatchSetupScreen
	)
	add_child(screen)
	return screen


static func _shipped_rules() -> MatchRules:
	return load(MATCH_RULES_PATH) as MatchRules


## True when [param object] carries a property called [param property_name].
static func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false


## The entry of [param option] whose item id is [param id], or -1.
static func _index_with_id(option: OptionButton, id: int) -> int:
	for index: int in option.item_count:
		if option.get_item_id(index) == id:
			return index
	return -1


## Copy exactly the fields the setup screen is allowed to write, and no others.
static func _copy_exposed_rules(from: MatchRules, to: MatchRules) -> void:
	to.prisoner_count = from.prisoner_count
	to.prisoner_lives = from.prisoner_lives
	to.shooter_win_condition = from.shooter_win_condition
	to.shutout_count = from.shutout_count
	to.hold_duration_seconds = from.hold_duration_seconds
	to.runner_win_condition = from.runner_win_condition
	to.rounds_to_win_match = from.rounds_to_win_match
	to.ghost_behaviour = from.ghost_behaviour
	to.open_with_race = from.open_with_race
	to.opening_seat_index = from.opening_seat_index
	to.map_id = from.map_id
	to.air_control_id = from.air_control_id
