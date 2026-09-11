extends TestCase

## The air control the player picks before a match: from the row on the setup
## screen to the bodies the match actually spawns.
##
## [b]The defect this pins[/b]
##
## Four named air-control presets ship in [code]resources/movement/[/code] and
## they were reachable from exactly one place: the F key in the movement
## playground. They could be measured and not played. The match was hardwired to
## [code]scenes/player/default_movement_profile.tres[/code], so the one question
## the presets exist to answer -- which of these is the game -- could not be
## asked by playing the game.
##
## The chain is the one every other choice on the setup screen travels, plus one
## link no other choice has, and each is asserted below:
##
## [codeblock]
##   the Air Control row   -> GameSettings.air_control_id     (the screen)
##   GameSettings          -> user://settings.cfg             (the round trip)
##   GameSettings          -> MatchRules.air_control_id       (apply_to_match_rules)
##   SettingsBoot          -> the rules the controller runs   (the scene wiring)
##   MatchController       -> EVERY body in the match         (set_profile)
## [/codeblock]
##
## The last link is the one that is peculiar to this setting. A map is installed
## once; an air control has to reach a human body that the scene owns AND three
## bot bodies the controller spawns, or a preset is being felt against opponents
## who move differently, which is not the preset being felt.
##
## [b]Committed is the default and this file is what keeps it that way[/b]
##
## Four places hold an opinion about which preset is the shipped one:
## [constant AirControlCatalog.DEFAULT_ID], [constant
## GameSettings.DEFAULT_AIR_CONTROL_ID], [MatchRules]' own code default, and
## [code]resources/rules/default_match_rules.tres[/code]. They must agree, and
## they must agree on the tuning the game already shipped with -- the choice
## between the four has not been made, and a default that quietly moved would
## make it by accident.
##
## [b]The shared store and the shipped resource, and putting both back[/b]
##
## [method SettingsStore.instance] is process-wide and the shipped rules resource
## is one cached object for the whole process. Every test here redirects the
## store to a scratch file and snapshots both.

const SETUP_SCREEN_PATH: String = "res://scenes/ui/match_setup_screen.tscn"
const MATCH_RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const SHIPPED_PROFILE_PATH: String = "res://scenes/player/default_movement_profile.tres"
const SCRATCH_CONFIG: String = "user://test_air_control_choice.cfg"

## The preset the "a match runs what was chosen" tests select. Deliberately NOT
## the default: a test that chose Committed would pass against a match that
## ignored the choice entirely and ran the shipped profile.
const CHOSEN_ID: StringName = &"kite"

## The four numbers a preset is allowed to move, and the only ones this file
## compares. Everything else being equal is [code]test_air_control_presets.gd[/code]'s.
const AIR_CONTROL_FIELDS: Array[String] = [
	"max_air_speed", "air_acceleration", "air_friction", "auto_bunny_hop",
]

var _real_config_path: String = ""
var _real_settings: GameSettings = GameSettings.new()
var _real_air_control_id: StringName = &""


func before_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	_real_config_path = store.config_path
	_real_settings.copy_from(store.settings)
	store.config_path = SCRATCH_CONFIG

	var shipped: MatchRules = _shipped_rules()
	if shipped != null:
		_real_air_control_id = shipped.air_control_id


func after_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.erase_file()
	store.config_path = _real_config_path
	store.settings.copy_from(_real_settings)

	var shipped: MatchRules = _shipped_rules()
	if shipped != null:
		shipped.air_control_id = _real_air_control_id

	# The match scene's PauseMenu writes the store's look preferences into the
	# SHIPPED movement profile, which is one object for the whole process. The
	# sensitivity test moves them, so they are put back here -- a test that left
	# the shipped profile retuned would hand every later test a different body.
	_real_settings.apply_to_movement_profile(load(SHIPPED_PROFILE_PATH) as MovementProfile)


# --- Committed is the default, everywhere that has an opinion -----------------

## The four places that name a default all name Committed.
##
## Ryan has not chosen between the presets. Until he does, the game must play the
## one it already shipped, and it must do so from a fresh install, from a
## settings file that has never heard of the setting, and from the rules resource
## on disk.
func test_committed_is_the_default_everywhere() -> void:
	assert_eq_string(
		String(AirControlCatalog.DEFAULT_ID), "committed", "the catalog's default"
	)
	assert_eq_string(
		String(GameSettings.DEFAULT_AIR_CONTROL_ID),
		String(AirControlCatalog.DEFAULT_ID),
		"the preference default is the catalog's",
	)
	assert_eq_string(
		String(GameSettings.new().air_control_id),
		String(AirControlCatalog.DEFAULT_ID),
		"a fresh preference is playing it",
	)
	assert_eq_string(
		String(MatchRules.new().air_control_id),
		String(AirControlCatalog.DEFAULT_ID),
		"MatchRules' own code default",
	)
	var shipped: MatchRules = _shipped_rules()
	assert_not_null(shipped, "the shipped rules resource loads")
	if shipped != null:
		assert_eq_string(
			String(shipped.air_control_id),
			String(AirControlCatalog.DEFAULT_ID),
			"and the rules the game ships with",
		)


## The default preset IS the tuning the game shipped with, number for number.
##
## The other half of the promise above: naming Committed the default is only
## honest while Committed is still [code]default_movement_profile.tres[/code].
## [code]test_air_control_presets.gd[/code] holds the preset to the profile; this
## holds the DEFAULT to the preset, so retuning the shipped profile and forgetting
## the preset is caught from either end.
func test_the_default_preset_is_the_shipped_tuning() -> void:
	var shipped_profile: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	var built: MovementProfile = AirControlCatalog.profile_for(AirControlCatalog.DEFAULT_ID)
	assert_not_null(built, "the default preset builds a profile")
	if built == null or shipped_profile == null:
		return
	for field: String in AIR_CONTROL_FIELDS:
		check(
			built.get(field) == shipped_profile.get(field),
			"the default preset's %s must be the shipped value -- expected %s, got %s" % [
				field, str(shipped_profile.get(field)), str(built.get(field)),
			],
		)


## The catalog is well formed: named, distinct, playable, and it contains the
## default it promises.
func test_the_catalog_is_usable() -> void:
	var problems: PackedStringArray = AirControlCatalog.validate()
	assert_eq_int(problems.size(), 0, "the shipped catalog has no problems: " + str(problems))
	assert_eq_int(
		AirControlCatalog.all().size(), 4, "the four authored presets are all in the catalog"
	)
	assert_eq_int(
		AirControlCatalog.index_of(AirControlCatalog.DEFAULT_ID),
		0,
		"and the default is first in the picker",
	)


# --- The screen ---------------------------------------------------------------

## The row offers every preset by NAME, and selecting one writes that preset's
## id into the settings.
##
## The name and not the numbers: the presets are chosen between by feel, which is
## why each carries a display name and a sentence at all.
func test_the_picker_offers_every_preset_by_name_and_writes_the_choice() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	var screen: MatchSetupScreen = _open_screen()

	var option: OptionButton = screen.get_node("%AirControlOption") as OptionButton
	var summary: Label = screen.get_node("%AirControlSummary") as Label
	assert_not_null(option, "the screen has an air control picker")
	assert_not_null(summary, "and a line saying what it feels like")
	if option == null or summary == null:
		return

	var presets: Array[AirControlPreset] = AirControlCatalog.all()
	assert_eq_int(option.item_count, presets.size(), "one row per preset in the catalog")
	for index: int in option.item_count:
		assert_false(option.is_item_disabled(index), "every preset offered can be chosen")
		assert_true(
			option.get_item_text(index).begins_with(presets[index].display_name),
			"the row names the preset -- expected %s, got %s" % [
				presets[index].display_name, option.get_item_text(index),
			],
		)
		# The numbers are the playground's business, not a player's.
		assert_false(
			option.get_item_text(index).contains(presets[index].describe_numbers()),
			"the picker shows the name, not the tuning",
		)

	# The default is legible as the default BEFORE it is selected.
	var default_row: int = AirControlCatalog.index_of(AirControlCatalog.DEFAULT_ID)
	assert_true(
		option.get_item_text(default_row).contains(MatchSetupScreen.DEFAULT_SUFFIX.strip_edges()),
		"the shipped preset says so in the list",
	)

	var wanted: int = AirControlCatalog.index_of(CHOSEN_ID)
	assert_gt(float(wanted), -1.0, "%s is in the catalog" % CHOSEN_ID)
	if wanted < 0:
		return
	var row: int = _index_with_id(option, wanted)
	option.select(row)
	option.item_selected.emit(row)

	assert_eq_string(
		String(store.settings.air_control_id), String(CHOSEN_ID), "the picker wrote the choice"
	)
	assert_eq_string(
		summary.text,
		AirControlCatalog.by_id(CHOSEN_ID).feel,
		"and the screen says what it feels like",
	)


## Choosing a MODE does not move the player off the air control they chose.
##
## Air control is how the body handles, not a rule of the round -- the same
## argument the map makes. Asserted against the preset's own property list as
## well as by watching the value, because a preset that DID write it might write
## the value that happened to be there.
func test_no_mode_preset_names_an_air_control() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.air_control_id = CHOSEN_ID
	for preset: MatchPresets.Preset in MatchPresets.all():
		assert_false(
			_has_property(preset, "air_control_id"), "%s names no air control" % preset.id
		)
		preset.apply_to(settings)
		assert_eq_string(
			String(settings.air_control_id),
			String(CHOSEN_ID),
			"%s left the air control alone" % preset.id,
		)


# --- The file -----------------------------------------------------------------

## It survives the settings file, and a file that has never heard of it is not a
## failure -- an older build's file leaves the player on the shipped tuning.
func test_the_choice_round_trips_through_the_config_file() -> void:
	var written: GameSettings = GameSettings.new()
	written.air_control_id = CHOSEN_ID
	var config: ConfigFile = ConfigFile.new()
	written.write_to(config)

	var read_back: GameSettings = GameSettings.new()
	read_back.read_from(config)
	assert_eq_string(
		String(read_back.air_control_id), String(CHOSEN_ID), "the choice came back off the file"
	)

	var old_file: ConfigFile = ConfigFile.new()
	var from_old: GameSettings = GameSettings.new()
	from_old.read_from(old_file)
	assert_eq_string(
		String(from_old.air_control_id),
		String(GameSettings.DEFAULT_AIR_CONTROL_ID),
		"a file that has never heard of the setting still plays the shipped tuning",
	)


## An id from another build is put back to the default rather than played.
func test_an_unknown_id_falls_back_to_the_default() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.air_control_id = &"a_preset_only_this_test_names"
	settings.clamp_all()
	assert_eq_string(
		String(settings.air_control_id),
		String(GameSettings.DEFAULT_AIR_CONTROL_ID),
		"clamped to the default",
	)

	# And the match end of the same fallback: the rules are NOT corrected -- that
	# is clamp_all()'s job -- but nothing that reads them is handed a null.
	var rules: MatchRules = MatchRules.new()
	rules.air_control_id = &"a_preset_only_this_test_names"
	assert_gt(
		float(rules.validate().size()), 0.0, "the rules say so out loud"
	)
	var profile: MovementProfile = AirControlCatalog.profile_for(rules.air_control_id)
	assert_not_null(profile, "and a match built on them still gets a profile")


# --- The last links: the rules the match runs, and the bodies that run them ---

## What the screen chose reaches the rules the [MatchController] runs, and it is
## the SAME object -- not an equal one.
##
## The failure this catches is the classic one: a second copy of the rules
## resource that everything writes to and nothing plays, which leaves the picker
## saving, reloading, displaying correctly and doing nothing.
func test_the_choice_reaches_the_rules_the_match_runs() -> void:
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
	assert_same(controller.rules, shipped, "and those are the very resource the picker writes")

	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	store.settings.air_control_id = CHOSEN_ID
	store.settings.apply_to_match_rules(controller.rules)
	assert_eq_string(
		String(shipped.air_control_id),
		String(CHOSEN_ID),
		"the chosen air control landed on the match's rules",
	)

	match_root.free()


## A match started on the choice runs it -- on every body it spawns.
##
## This is the link no other setting on the screen has. The human's body belongs
## to the scene and the bots' bodies are instanced by [MatchController]; both
## have to end up on the same profile, or the preset is being judged against
## opponents who move differently.
##
## Asserted by IDENTITY, and on the [IntentSource] as well as on the body. The
## floor angle, the snap length and the intent source's own copy are read once at
## ready: an assignment to [member PlayerController.profile] would pass a value
## comparison and leave every body half-configured.
func test_a_started_match_runs_the_chosen_preset_on_every_body() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	store.settings.air_control_id = CHOSEN_ID

	var match_root: Node3D = TestFixtures.make_match()
	# Chosen BEFORE the tree, because SettingsBoot writes the rules from
	# _enter_tree and MatchController arms the match from _ready.
	add_child(match_root)
	var controller: MatchController = match_root.get_node("MatchController") as MatchController

	var chosen: AirControlPreset = AirControlCatalog.by_id(CHOSEN_ID)
	var live: MovementProfile = controller.get_air_control_profile()
	assert_not_null(live, "the match built a profile for the chosen preset")
	if live == null or chosen == null:
		match_root.queue_free()
		return

	for field: String in AIR_CONTROL_FIELDS:
		check(
			live.get(field) == chosen.get(field),
			"the live profile's %s must be %s's -- expected %s, got %s" % [
				field, chosen.display_name, str(chosen.get(field)), str(live.get(field)),
			],
		)
	var shipped_profile: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	assert_false(
		live == shipped_profile,
		"and it is a private profile, not the shipped resource a menu must never retune",
	)

	var participants: Array[MatchParticipant] = controller.get_participants()
	assert_gt(float(participants.size()), 1.0, "the match has a human and at least one bot")

	var humans: int = 0
	var bots: int = 0
	for participant: MatchParticipant in participants:
		assert_not_null(participant.body, "%s has a body" % participant.display_name)
		if participant.body == null:
			continue
		assert_same(
			participant.body.profile,
			live,
			"%s runs the chosen profile" % participant.display_name,
		)
		assert_same(
			participant.body.intent_source.profile,
			live,
			"%s was reconfigured, not merely assigned" % participant.display_name,
		)
		if participant.is_human():
			humans += 1
		else:
			bots += 1
	assert_eq_int(humans, 1, "the human got it")
	assert_gt(float(bots), 0.0, "and so did the bots")

	match_root.queue_free()
	await step_ticks(1)


## A player who has chosen nothing plays Committed, all the way to the bodies.
func test_a_match_nobody_has_configured_runs_committed() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()

	var match_root: Node3D = TestFixtures.make_match()
	add_child(match_root)
	var controller: MatchController = match_root.get_node("MatchController") as MatchController

	var live: MovementProfile = controller.get_air_control_profile()
	var shipped_profile: MovementProfile = load(SHIPPED_PROFILE_PATH) as MovementProfile
	assert_not_null(live, "the match built a profile")
	if live == null or shipped_profile == null:
		match_root.queue_free()
		return
	for field: String in AIR_CONTROL_FIELDS:
		check(
			live.get(field) == shipped_profile.get(field),
			"an unconfigured match runs the shipped %s -- expected %s, got %s" % [
				field, str(shipped_profile.get(field)), str(live.get(field)),
			],
		)

	match_root.queue_free()
	await step_ticks(1)


## The look preferences survive the swap.
##
## The profile the bodies run is a private duplicate of the shipped one, and
## mouse sensitivity lives on it. [PauseMenu] writes the sensitivity into the
## SHIPPED instance, which the bodies are no longer holding, so the controller
## follows [signal SettingsStore.applied] and writes it into the one they are.
## Without that, choosing an air control would silently reset the player's
## sensitivity to whatever the resource on disk says and freeze it there.
func test_the_chosen_profile_still_follows_the_sensitivity_slider() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.reset()
	store.settings.air_control_id = CHOSEN_ID
	store.settings.mouse_sensitivity = GameSettings.MIN_MOUSE_SENSITIVITY

	var match_root: Node3D = TestFixtures.make_match()
	add_child(match_root)
	var controller: MatchController = match_root.get_node("MatchController") as MatchController
	var live: MovementProfile = controller.get_air_control_profile()
	assert_not_null(live, "the match built a profile")
	if live == null:
		match_root.queue_free()
		return

	assert_almost_eq(
		live.mouse_sensitivity,
		GameSettings.MIN_MOUSE_SENSITIVITY,
		1e-9,
		"the saved sensitivity reached the profile the bodies run",
	)

	store.settings.mouse_sensitivity = GameSettings.MAX_MOUSE_SENSITIVITY
	store.apply_all()
	assert_almost_eq(
		live.mouse_sensitivity,
		GameSettings.MAX_MOUSE_SENSITIVITY,
		1e-9,
		"and a change made mid-match reaches it too",
	)

	match_root.queue_free()
	await step_ticks(1)


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
