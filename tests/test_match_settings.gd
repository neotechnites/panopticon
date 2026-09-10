extends TestCase

## The ghost toggle: from the checkbox the player clicks to the [MatchRules] the
## match is actually played under.
##
## [b]The defect this pins[/b]
##
## Ghosts live behind [member MatchRules.ghost_behaviour] in
## [code]resources/rules/default_match_rules.tres[/code], and a player cannot
## open a text editor to change a rule file. So it is also a PREFERENCE, written
## OVER the rules on the way into a match, and the two defaults must agree or the
## first frame of the game is played under a rule set nobody chose.
##
## The chain has four links, each of which is asserted below:
##
## [codeblock]
##   Match tab checkbox  -> GameSettings.ghosts_enabled     (the screen)
##   GameSettings        -> user://settings.cfg             (the round trip)
##   GameSettings        -> MatchRules.ghost_behaviour      (apply_to_match_rules)
##   SettingsBoot        -> the rules the controller runs   (the scene wiring)
## [/codeblock]
##
## A test of any one link alone would pass while the toggle did nothing, which is
## the failure mode this whole file exists to catch: the classic settings bug is
## a value that saves, reloads, displays correctly and reaches nothing.
##
## [b]The shared store, and putting it back[/b]
##
## [method SettingsStore.instance] is a process-wide singleton and the settings
## file is the one belonging to whoever is running the suite. Every test here
## redirects it to a scratch file and restores both the file and
## [member GameSettings.ghosts_enabled] afterwards -- a test that left the
## preference flipped in the singleton would hand every later test in the same
## process a different game.

const SETTINGS_SCREEN_PATH: String = "res://scenes/ui/settings_screen.tscn"

## Where the shared store is pointed while this file runs.
const SCRATCH_CONFIG: String = "user://test_match_settings.cfg"

## The seat the race-skip tests hand the tower to. A bot, and not the first
## participant: "give it to myself or a bot" is the requirement.
const SKIP_SEAT_INDEX: int = 2

var _real_config_path: String = ""
var _real_ghosts_enabled: bool = false
var _real_skip_opening_race: bool = false
var _real_tower_seat_index: int = 0


func before_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	_real_config_path = store.config_path
	_real_ghosts_enabled = store.settings.ghosts_enabled
	_real_skip_opening_race = store.settings.skip_opening_race
	_real_tower_seat_index = store.settings.tower_seat_index
	store.config_path = SCRATCH_CONFIG


func after_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.erase_file()
	store.config_path = _real_config_path
	store.settings.ghosts_enabled = _real_ghosts_enabled
	store.settings.skip_opening_race = _real_skip_opening_race
	store.settings.tower_seat_index = _real_tower_seat_index


# --- The preference itself ----------------------------------------------------

## On by default, because the shipped rules are.
##
## The two defaults have to agree or the first frame of the game is played under
## a rule set nobody chose.
func test_ghosts_are_on_by_default_in_both_places() -> void:
	var settings: GameSettings = GameSettings.new()
	assert_true(settings.ghosts_enabled, "a fresh GameSettings has ghosts on")

	var rules: MatchRules = TestFixtures.match_rules()
	assert_eq_int(
		int(rules.ghost_behaviour),
		int(MatchRules.GhostBehaviour.CATCH_AND_SWAP),
		"the shipped rules play the canon mechanic",
	)
	assert_true(rules.has_ghosts(), "and the match agrees they are on")


## The preference writes the rule, in both directions.
##
## Both directions is the point. A one-way write -- "if ghosts_enabled then turn
## them on" -- leaves a match started after the toggle was switched off still
## running the mechanic, because the rules resource is one shared instance for
## the process. That bug survives testing because the first thing anybody tries
## is turning it ON.
func test_the_preference_writes_the_rule_both_ways() -> void:
	var settings: GameSettings = GameSettings.new()
	var rules: MatchRules = TestFixtures.match_rules()

	settings.ghosts_enabled = true
	settings.apply_to_match_rules(rules)
	assert_eq_int(
		int(rules.ghost_behaviour),
		int(MatchRules.GhostBehaviour.CATCH_AND_SWAP),
		"ghosts on selects the canon mechanic",
	)
	assert_true(rules.has_ghosts(), "and the match plays it")

	settings.ghosts_enabled = false
	settings.apply_to_match_rules(rules)
	assert_eq_int(
		int(rules.ghost_behaviour),
		int(MatchRules.GhostBehaviour.NONE),
		"ghosts off puts the rule back",
	)
	assert_false(rules.has_ghosts(), "and the match stops playing it")


## It survives the file, and a file that has never heard of it is not a failure.
func test_the_preference_round_trips_through_the_config_file() -> void:
	var written: GameSettings = GameSettings.new()
	written.ghosts_enabled = false

	var config: ConfigFile = ConfigFile.new()
	written.write_to(config)

	var read: GameSettings = GameSettings.new()
	read.read_from(config)
	assert_false(read.ghosts_enabled, "ghosts_enabled comes back off disk")
	assert_true(read.equals(written), "and nothing else was lost round-tripping it")

	var older: GameSettings = GameSettings.new()
	older.ghosts_enabled = false
	# A settings file written before this key existed: the value already in hand
	# is the fallback, exactly as every other reader here behaves.
	older.read_from(ConfigFile.new())
	assert_false(older.ghosts_enabled, "a file with no ghosts key changes nothing")

	var reset: GameSettings = GameSettings.new()
	reset.ghosts_enabled = false
	reset.reset()
	assert_true(reset.ghosts_enabled, "reset puts ghosts back on")


## A settings file written before ghosts became the default does not leave a
## returning player with them off.
##
## Version 1 wrote [code]ghosts_enabled=false[/code] into every file it saved,
## because that was the default then and the file records VALUES, not choices.
## Read back literally, it would put the player's preference and the rules
## resource on opposite sides -- which is the one thing this file exists to stop.
## So a version 1 file is taken to have expressed no preference about ghosts, and
## a version 2 file is believed whatever it says.
func test_a_pre_ghost_settings_file_does_not_force_ghosts_off() -> void:
	var store: SettingsStore = SettingsStore.instance()

	var old_file: ConfigFile = ConfigFile.new()
	old_file.set_value(SettingsStore.SECTION_META, "version", 1)
	old_file.set_value(GameSettings.SECTION_MATCH, "ghosts_enabled", false)
	assert_eq_int(int(old_file.save(SCRATCH_CONFIG)), int(OK), "the version 1 file is written")

	assert_true(store.load_from_disk(), "the version 1 file is readable")
	assert_true(store.settings.ghosts_enabled, "its stale ghosts_enabled=false is not obeyed")

	# A file this build wrote is believed, off included.
	store.settings.ghosts_enabled = false
	assert_eq_int(int(store.save_to_disk()), int(OK), "the current file is written")
	assert_true(store.load_from_disk(), "the current file is readable")
	assert_false(store.settings.ghosts_enabled, "a chosen off survives the round trip")


# --- The race skip ------------------------------------------------------------

## The shipped game still opens with a race, and both sides say so.
func test_the_race_skip_is_off_by_default_in_both_places() -> void:
	var settings: GameSettings = GameSettings.new()
	assert_false(settings.skip_opening_race, "a fresh GameSettings runs the race")
	assert_eq_int(settings.tower_seat_index, 0, "and would hand the tower to the player")

	var rules: MatchRules = TestFixtures.match_rules()
	assert_true(rules.open_with_race, "the shipped rules open with a race")
	assert_eq_int(rules.opening_seat_index, 0, "on the same seat")


## The preference writes the rules, in both directions, and the seat survives
## being switched off.
##
## Both directions for the same reason the ghost toggle needs them: the rules
## resource is one shared instance for the process, so a one-way write leaves a
## match started after the skip was cleared still skipping.
func test_the_race_skip_writes_the_rules_both_ways() -> void:
	var settings: GameSettings = GameSettings.new()
	var rules: MatchRules = TestFixtures.match_rules()

	settings.skip_opening_race = true
	settings.tower_seat_index = SKIP_SEAT_INDEX
	settings.apply_to_match_rules(rules)
	assert_false(rules.open_with_race, "the skip turns the race off")
	assert_eq_int(rules.opening_seat_index, SKIP_SEAT_INDEX, "and names who gets the tower")

	settings.skip_opening_race = false
	settings.apply_to_match_rules(rules)
	assert_true(rules.open_with_race, "clearing the skip puts the race back")
	assert_eq_int(
		rules.opening_seat_index, SKIP_SEAT_INDEX,
		"and the seat the player chose is still there for the next time they skip",
	)


## Both values survive the file, and a file that has never heard of them is not a
## failure.
func test_the_race_skip_round_trips_through_the_config_file() -> void:
	var written: GameSettings = GameSettings.new()
	written.skip_opening_race = true
	written.tower_seat_index = SKIP_SEAT_INDEX

	var config: ConfigFile = ConfigFile.new()
	written.write_to(config)

	var read: GameSettings = GameSettings.new()
	read.read_from(config)
	assert_true(read.skip_opening_race, "the skip comes back off disk")
	assert_eq_int(read.tower_seat_index, SKIP_SEAT_INDEX, "and so does the seat")
	assert_true(read.equals(written), "and nothing else was lost round-tripping it")

	# A settings file written before these keys existed: the value already in
	# hand is the fallback, exactly as every other reader here behaves.
	var older: GameSettings = GameSettings.new()
	older.skip_opening_race = true
	older.tower_seat_index = SKIP_SEAT_INDEX
	older.read_from(ConfigFile.new())
	assert_true(older.skip_opening_race, "a file with no skip key changes nothing")
	assert_eq_int(older.tower_seat_index, SKIP_SEAT_INDEX, "and none of the seat")

	# A file holding nonsense does not reach the match holding nonsense.
	var wild: GameSettings = GameSettings.new()
	wild.tower_seat_index = -5
	wild.clamp_all()
	assert_eq_int(wild.tower_seat_index, 0, "a corrupt seat index clamps to the player")

	var reset: GameSettings = GameSettings.new()
	reset.skip_opening_race = true
	reset.tower_seat_index = SKIP_SEAT_INDEX
	reset.reset()
	assert_false(reset.skip_opening_race, "reset puts the race back")
	assert_eq_int(reset.tower_seat_index, 0, "and the tower back to the player")


# --- The screen ---------------------------------------------------------------

## The checkbox exists, shows the stored value, and writes it back.
##
## Asserted against the authored scene rather than a control built here: the
## screen's structure lives in [code].tscn[/code] on purpose, and a test that
## made its own CheckBox would pass while the tab was empty.
func test_the_match_tab_toggle_drives_the_store() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.ghosts_enabled = false

	var screen: SettingsScreen = _open_screen()
	var check: CheckBox = screen.get_node(^"%GhostsCheck") as CheckBox
	assert_not_null(check, "the Match tab has a ghosts checkbox")
	assert_false(check.button_pressed, "it opens showing ghosts off")

	# button_pressed = true does not emit toggled; the player's click does.
	check.button_pressed = true
	check.toggled.emit(true)
	assert_true(store.settings.ghosts_enabled, "ticking it turns ghosts on in the store")

	check.button_pressed = false
	check.toggled.emit(false)
	assert_false(store.settings.ghosts_enabled, "clearing it turns them off again")

	# And it mirrors a value it did not set itself.
	store.settings.ghosts_enabled = true
	screen.refresh()
	assert_true(check.button_pressed, "reopening the screen shows ghosts on")


## The race-skip controls exist, show the stored values, and write them back.
##
## Asserted against the authored scene rather than controls built here: the
## screen's structure lives in [code].tscn[/code] on purpose, and a test that
## made its own CheckBox would pass while the tab was empty.
func test_the_match_tab_race_skip_drives_the_store() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.skip_opening_race = false
	store.settings.tower_seat_index = 0

	var screen: SettingsScreen = _open_screen()
	var check: CheckBox = screen.get_node_or_null(^"%SkipRaceCheck") as CheckBox
	var seats: OptionButton = screen.get_node_or_null(^"%TowerSeatOption") as OptionButton
	assert_not_null(check, "the Match tab has a race-skip checkbox")
	assert_not_null(seats, "and a list of seats to hand the tower to")
	if check == null or seats == null:
		return

	assert_false(check.button_pressed, "it opens showing the race being run")
	assert_true(seats.disabled, "and the seat list dead, because there is nothing to hand")

	# One entry per seat the match will actually have, named the way the HUD
	# names it.
	var rules: MatchRules = TestFixtures.match_rules()
	assert_eq_int(
		seats.item_count, rules.get_participant_count(),
		"the list offers exactly the seats a match has",
	)
	assert_eq_string(
		seats.get_item_text(0), MatchRules.get_participant_name(0, true),
		"the player is the first seat",
	)
	assert_eq_string(
		seats.get_item_text(SKIP_SEAT_INDEX),
		MatchRules.get_participant_name(SKIP_SEAT_INDEX, true),
		"and the bots are named as the match names them",
	)

	# button_pressed = true does not emit toggled; the player's click does.
	check.button_pressed = true
	check.toggled.emit(true)
	assert_true(store.settings.skip_opening_race, "ticking it turns the skip on in the store")
	assert_false(seats.disabled, "and wakes the seat list up")

	seats.selected = SKIP_SEAT_INDEX
	seats.item_selected.emit(SKIP_SEAT_INDEX)
	assert_eq_int(
		store.settings.tower_seat_index, SKIP_SEAT_INDEX,
		"choosing a bot writes that seat into the store",
	)

	check.button_pressed = false
	check.toggled.emit(false)
	assert_false(store.settings.skip_opening_race, "clearing it runs the race again")
	assert_true(seats.disabled, "and the seat list goes dead with it")

	# And they mirror values they did not set themselves.
	store.settings.skip_opening_race = true
	store.settings.tower_seat_index = 1
	screen.refresh()
	assert_true(check.button_pressed, "reopening the screen shows the stored skip")
	assert_eq_int(seats.get_selected_id(), 1, "and the stored seat")


## The toggle is captioned, so a player meeting the mechanic knows what it is.
func test_the_ghost_toggle_says_what_the_mechanic_is() -> void:
	var screen: SettingsScreen = _open_screen()
	var note: Label = screen.get_node_or_null(
		^"Frame/Dialog/Padding/Layout/Tabs/Match/GhostsNote"
	) as Label
	assert_not_null(note, "the Match tab has a note beside the toggle")
	if note == null:
		return
	assert_true(note.visible, "the note is shown, not hidden behind something")
	assert_true(
		note.text.to_lower().contains("ghost"),
		"the note describes the mechanic -- got \"%s\"" % note.text,
	)
	assert_true(
		note.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"the note wraps rather than running off the dialog",
	)


# --- The wiring ---------------------------------------------------------------

## [SettingsBoot] writes the store's preference into the rules it is pointed at,
## on entering the tree -- which is before any [MatchController] in the same
## scene is ready.
##
## The rules here are a private copy on purpose: this asserts the mechanism, not
## the scene, and retuning the shipped [code].tres[/code] would hand every later
## test in the process a game with ghosts in it.
func test_settings_boot_writes_the_preference_into_the_rules() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.ghosts_enabled = false

	var rules: MatchRules = TestFixtures.match_rules()
	assert_true(rules.has_ghosts(), "the shipped rules start with ghosts on")

	var boot: SettingsBoot = SettingsBoot.new()
	boot.name = "SettingsBoot"
	boot.match_rules = rules
	add_child(boot)
	assert_false(rules.has_ghosts(), "entering the tree turned ghosts off")

	# And it keeps tracking: the store applies, the rules follow.
	store.settings.ghosts_enabled = true
	store.apply_all()
	assert_true(rules.has_ghosts(), "applying the store turned them on again")


## The match scene points that node at the SAME rules object the controller runs.
##
## This is the link that cannot be tested by behaviour without starting a match,
## and it is the one most easily broken by a careless edit: pointing
## [member SettingsBoot.match_rules] at a second copy of the resource leaves a
## toggle that saves, reloads, displays and does nothing. Identity, not equality
## -- Godot hands back one cached object per resource path, and this asserts that
## both exports resolved to it.
func test_the_match_scene_wires_the_boot_to_the_rules_it_plays() -> void:
	# Instantiated and never added: entering the tree would start a match, and
	# nothing here needs one.
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

	assert_not_null(controller.rules, "the controller names its rules")
	assert_same(
		boot.match_rules,
		controller.rules,
		"the settings boot writes the very rules the controller runs",
	)
	match_root.free()


# --- Fixture ------------------------------------------------------------------

## The authored settings screen, in the tree and ready.
##
## Parented to this test, so the runner frees it whatever the test does.
func _open_screen() -> SettingsScreen:
	var screen: SettingsScreen = (
		(load(SETTINGS_SCREEN_PATH) as PackedScene).instantiate() as SettingsScreen
	)
	add_child(screen)
	return screen
