class_name MatchSetupScreen
extends Control

## The rules of the round, chosen with a mouse, before the match starts.
##
## [b]What this screen is for.[/b] [MatchRules] holds every design parameter of a
## round and a player cannot open a text editor to change one. Almost all of them
## were therefore unreachable: the shipped game let you turn ghosts off and skip
## the opening race, and nothing else. This screen makes the rules that are
## genuinely CHOICES -- how many prisoners, who opens in the tower, what each
## side has to do to win, how long the match is -- reachable from the main menu,
## and leaves the ones that are tuning where they were.
##
## [b]What is deliberately not on it.[/b] The reload clock
## ([member MatchRules.base_reload_seconds] and
## [member MatchRules.reload_reduction_per_turn]) is the match's only terminator,
## and a player who sets the escalation to zero has built a match that need never
## end; the arena numbers ([member MatchRules.track_radius],
## [member MatchRules.start_line_spacing_metres],
## [member MatchRules.lap_arrival_tolerance]) are geometry the map was measured
## for; [member MatchRules.guard_fov_degrees] and
## [member MatchRules.round_time_limit_seconds] are deferred and read by nothing;
## the weapon, ghost, shooter and runner profiles are component tuning by the
## seam [MatchRules] draws in its own header; and
## [member MatchRules.ai_shooter_aim_seed] and
## [member MatchRules.turn_count_resets_on_seat_loss] exist to be swept, not
## played. All of them are still exactly as reachable to the harness as they
## were. Ten controls a player can reason about beat twenty-six they cannot.
##
## [b]Instantiate the scene -- do not construct this class.[/b] The layout lives
## in [code]scenes/ui/match_setup_screen.tscn[/code]; this file binds it and
## drives data into it, the same split [SettingsScreen] uses.
##
## [b]How a choice reaches the match.[/b] There is one path and this screen does
## not add a second:
## [codeblock]
##   a control here  -> SettingsStore.instance().settings   (a preference)
##                   -> user://settings.cfg                 (on Start and Back)
##   GameSettings.apply_to_match_rules(rules)
##                   -> the MatchRules the match runs       (SettingsBoot)
## [/codeblock]
## The last link is the one that silently breaks: [SettingsBoot] in
## [code]scenes/match/match.tscn[/code] points at the SAME
## [code]resources/rules/default_match_rules.tres[/code] instance
## [MatchController] exports -- one cached object per resource path -- so what is
## chosen here is written into the rules the match is actually played under, and
## not into a copy of them. [code]tests/test_match_setup.gd[/code] asserts that
## by identity.

## [b]Air control is not a choice on this screen.[/b] It used to be, when the
## four presets in [code]resources/movement/[/code] were still an open question --
## see [AirControlCatalog] -- but Carve is now the shipped tuning and every body
## in every match runs it, via [member MatchRules.air_control_id]'s own default.
## The other three presets stay on disk, playable back to back in the movement
## playground, and are not offered here.
##
## [b]The map is chosen here too, and it is not a rule of the round.[/b] It is
## the first control on the screen, it is read from [MapCatalog] rather than
## typed into the scene, and it is deliberately NOT part of a preset: choosing
## Riot changes six rules and leaves you standing where you chose to stand. It
## travels the identical path everything else on this screen does, ending on
## [member MatchRules.map_id], which [MatchController] reads to decide what arena
## to instance. There is one map today; a list of one is still a choice, and the
## second map is a [code].tres[/code] in [code]resources/maps/[/code] with no
## edit to this file.


## Emitted when the player presses Start, after the settings file is written. The
## owner changes the scene; this node does not, so it works as a child that is
## toggled and as a scene that is freed.
signal start_requested()

## Emitted when the player backs out, after the settings file is written.
signal closed()

## How the tower is decided, as one control over two rules.
##
## [member MatchRules.open_with_race] and [member MatchRules.opening_seat_index]
## are two fields but one question, and asking it as two controls is how the
## settings screen's Match tab ended up with a seat list that is greyed out most
## of the time. Here it is a single list of the three answers that exist.
enum Opening {
	## Everybody runs the ring and the first to the end takes the tower. Canon,
	## and [member MatchRules.open_with_race] true.
	RACE,
	## Skip the race; the human opens in the tower with the rifle.
	TOWER,
	## Skip the race; a bot opens in the tower and the human opens on the ring.
	RING,
}

## The seat the tower is handed to for [constant Opening.RING].
##
## Seat 0 is the human -- see [method MatchRules.get_participant_name] -- so the
## first bot is 1. Only used when the saved seat is the human's; a player who
## picked a particular bot on the settings screen's Match tab keeps that bot.
const FIRST_BOT_SEAT_INDEX: int = 1

## Shown in the map picker when [MapCatalog] returns nothing at all -- a broken
## install, not a state the game can be played in. Present so the row reads as a
## failure rather than as an empty control that swallows clicks.
const NO_MAPS_TITLE: String = "No maps found"

## Item id of that entry, and never a valid map index.
const NO_MAPS_ID: int = -1

## Shown in the mode picker when the rules match no named preset.
const CUSTOM_TITLE: String = "Custom"

## Item id of that entry. Negative so it can never collide with a preset index.
const CUSTOM_ID: int = -1

@onready var _map_option: OptionButton = %MapOption
@onready var _map_summary: Label = %MapSummary

@onready var _preset_option: OptionButton = %PresetOption
@onready var _preset_badge: Label = %PresetBadge
@onready var _preset_summary: Label = %PresetSummary

@onready var _prisoner_count_spin: SpinBox = %PrisonerCountSpin
@onready var _prisoners_readout: Label = %PrisonersReadout
@onready var _opening_option: OptionButton = %OpeningOption
@onready var _opening_readout: Label = %OpeningReadout
@onready var _lives_option: OptionButton = %LivesOption
@onready var _ghosts_check: CheckBox = %GhostsCheck
@onready var _shooter_win_option: OptionButton = %ShooterWinOption
@onready var _runner_win_option: OptionButton = %RunnerWinOption
@onready var _ability_option: OptionButton = %AbilityOption
@onready var _rounds_spin: SpinBox = %RoundsSpin
@onready var _rounds_readout: Label = %RoundsReadout
@onready var _note: Label = %Note

@onready var _back_button: Button = %Back
@onready var _restore_button: Button = %RestoreCanon
@onready var _start_button: Button = %Start

var _store: SettingsStore = null

## A throwaway [MatchRules] this screen asks questions of.
##
## It is never played and never saved. It exists so that "is this win condition
## implemented" and "how many participants is that" are answered BY [MatchRules],
## in the one place those answers live, instead of being restated here where they
## could drift out of step with the round that actually runs.
var _probe: MatchRules = MatchRules.new()

## Set while the controls are being written from the store, so the change signals
## they emit do not bounce straight back into it.
var _syncing: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	_configure_ranges()
	_fill_choices()
	_connect_controls()
	refresh()


## Pull every control's value from the store.
func refresh() -> void:
	_syncing = true

	var settings: GameSettings = _store.settings
	_map_option.selected = _index_of(_map_option, MapCatalog.index_of(settings.map_id))
	_prisoner_count_spin.value = float(settings.prisoner_count)
	_opening_option.selected = _index_of(_opening_option, int(_opening_of(settings)))
	_lives_option.selected = _index_of(_lives_option, settings.prisoner_lives)
	_ghosts_check.button_pressed = settings.ghosts_enabled
	_shooter_win_option.selected = _index_of(
		_shooter_win_option, int(settings.shooter_win_condition)
	)
	_runner_win_option.selected = _index_of(
		_runner_win_option, int(settings.runner_win_condition)
	)
	_ability_option.selected = _index_of(_ability_option, int(settings.runner_ability))
	_rounds_spin.value = float(settings.rounds_to_win_match)

	_syncing = false

	_update_derived()


## Write the settings file and ask the owner to start the match.
func start() -> void:
	_store.save_to_disk()
	start_requested.emit()


## Write the settings file and report the screen closed.
func close() -> void:
	_store.save_to_disk()
	closed.emit()


## True when the rules currently chosen are the canon rules. The badge is driven
## off this, and so is the verification harness.
func is_canon() -> bool:
	return MatchPresets.is_canon(_store.settings)


## Put keyboard focus on Start.
##
## The owner calls this when it shows the screen rather than the screen grabbing
## focus in [method Node._ready], because this scene is instanced hidden inside
## the main menu and a hidden control that seizes focus takes it away from the
## menu the player is actually looking at.
func focus_start() -> void:
	if _start_button != null:
		_start_button.grab_focus()


# --- Wiring -------------------------------------------------------------------

## Spin bounds come from [GameSettings], not from the scene, so what the player
## can dial to and what [method GameSettings.clamp_all] enforces on a loaded file
## are the same numbers rather than two copies that can drift.
func _configure_ranges() -> void:
	_prisoner_count_spin.min_value = float(GameSettings.MIN_PRISONER_COUNT)
	_prisoner_count_spin.max_value = float(GameSettings.MAX_PRISONER_COUNT)
	_prisoner_count_spin.step = 1.0

	_rounds_spin.min_value = float(GameSettings.MIN_ROUNDS_TO_WIN_MATCH)
	_rounds_spin.max_value = float(GameSettings.MAX_ROUNDS_TO_WIN_MATCH)
	_rounds_spin.step = 1.0


## Every list is filled from the data it selects -- the presets, the enums, the
## clamp bounds -- rather than typed into the scene, where it would fall out of
## step the first time one of them changed.
func _fill_choices() -> void:
	_map_option.clear()
	var maps: Array[MapDefinition] = MapCatalog.all()
	# map_index, not index: the preset loop below already owns that name in this
	# function, which is why every loop here is named after what it counts.
	for map_index: int in maps.size():
		var map: MapDefinition = maps[map_index]
		if map == null:
			continue
		# The catalog position is the item id, exactly as the mode picker uses
		# the preset position: the MEANING of the entry is which map it is, and
		# reading a list position back would break the day one is inserted.
		_map_option.add_item(map.title, map_index)
	if _map_option.item_count == 0:
		_map_option.add_item(NO_MAPS_TITLE, NO_MAPS_ID)
		_map_option.set_item_disabled(0, true)

	_preset_option.clear()
	var presets: Array[MatchPresets.Preset] = MatchPresets.all()
	for index: int in presets.size():
		var preset: MatchPresets.Preset = presets[index]
		var title: String = preset.title
		if preset.id == MatchPresets.CANON_ID:
			# Named in the list itself as well as in the badge. A default that is
			# only obvious once you have selected it is not obvious.
			title = "%s (the default)" % title
		_preset_option.add_item(title, index)
	# Never selectable, only ever displayed: Custom is what the picker says when
	# the rules describe no named mode, and "choosing" it would mean nothing.
	_preset_option.add_item(CUSTOM_TITLE, CUSTOM_ID)
	_preset_option.set_item_disabled(_preset_option.item_count - 1, true)

	_opening_option.clear()
	_opening_option.add_item("Race for the tower", int(Opening.RACE))
	_opening_option.add_item("Open in the tower", int(Opening.TOWER))
	_opening_option.add_item("Open on the ring", int(Opening.RING))

	_lives_option.clear()
	for lives: int in range(GameSettings.MIN_PRISONER_LIVES, GameSettings.MAX_PRISONER_LIVES + 1):
		var label: String = "1 hit" if lives == 1 else ("%d hits" % lives)
		_lives_option.add_item(label, lives)

	_shooter_win_option.clear()
	for value: int in MatchRules.ShooterWinCondition.size():
		_shooter_win_option.add_item(_shooter_win_title(value), value)
		# Asked of MatchRules rather than restated here. A condition the round
		# does not implement produces a round the tower cannot win, so it is
		# shown -- the design space is worth seeing -- and not selectable.
		_probe.shooter_win_condition = value as MatchRules.ShooterWinCondition
		if not _probe.is_shooter_win_condition_implemented():
			_shooter_win_option.set_item_disabled(_shooter_win_option.item_count - 1, true)

	_runner_win_option.clear()
	for runner_value: int in MatchRules.RunnerWinCondition.size():
		_runner_win_option.add_item(_runner_win_title(runner_value), runner_value)

	_ability_option.clear()
	for ability_value: int in MatchRules.RunnerAbility.size():
		_ability_option.add_item(MatchRules.runner_ability_title(ability_value), ability_value)


func _connect_controls() -> void:
	_map_option.item_selected.connect(_on_map_selected)
	_preset_option.item_selected.connect(_on_preset_selected)
	_prisoner_count_spin.value_changed.connect(_on_prisoner_count_changed)
	_opening_option.item_selected.connect(_on_opening_selected)
	_lives_option.item_selected.connect(_on_lives_selected)
	_ghosts_check.toggled.connect(_on_ghosts_toggled)
	_shooter_win_option.item_selected.connect(_on_shooter_win_selected)
	_runner_win_option.item_selected.connect(_on_runner_win_selected)
	_ability_option.item_selected.connect(_on_ability_selected)
	_rounds_spin.value_changed.connect(_on_rounds_changed)

	_back_button.pressed.connect(close)
	_restore_button.pressed.connect(restore_canon)
	_start_button.pressed.connect(start)


# --- Handlers -----------------------------------------------------------------

## Choose the map. Writes an id and not a path: see [member GameSettings.map_id].
func _on_map_selected(index: int) -> void:
	if _syncing:
		return
	var id: int = _map_option.get_item_id(index)
	var maps: Array[MapDefinition] = MapCatalog.all()
	if id < 0 or id >= maps.size() or maps[id] == null:
		return
	_store.settings.map_id = maps[id].id
	# _after_change() redraws the map summary with everything else.
	_after_change()


## Set every curated rule at once from a named mode, then redraw. The player can
## still override any of them afterwards, at which point the picker reads Custom.
func _on_preset_selected(index: int) -> void:
	if _syncing:
		return
	var id: int = _preset_option.get_item_id(index)
	if id == CUSTOM_ID:
		return
	var presets: Array[MatchPresets.Preset] = MatchPresets.all()
	if id < 0 or id >= presets.size():
		return
	presets[id].apply_to(_store.settings)
	_after_change()
	refresh()


## Put the canon rules back. Only these rules -- not the volume, not the
## bindings -- which is why this is not [method SettingsStore.reset_all].
func restore_canon() -> void:
	var preset: MatchPresets.Preset = MatchPresets.canon()
	if preset == null:
		return
	preset.apply_to(_store.settings)
	_after_change()
	refresh()


func _on_prisoner_count_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.prisoner_count = int(roundf(value))
	_after_change()


func _on_opening_selected(index: int) -> void:
	if _syncing:
		return
	var settings: GameSettings = _store.settings
	match _opening_option.get_item_id(index) as Opening:
		Opening.RACE:
			settings.skip_opening_race = false
		Opening.TOWER:
			settings.skip_opening_race = true
			settings.tower_seat_index = 0
		Opening.RING:
			settings.skip_opening_race = true
			# Only moved off the human. A player who picked a particular bot on
			# the settings screen's Match tab keeps that bot.
			if settings.tower_seat_index <= 0:
				settings.tower_seat_index = FIRST_BOT_SEAT_INDEX
	_after_change()


func _on_lives_selected(index: int) -> void:
	if _syncing:
		return
	_store.settings.prisoner_lives = _lives_option.get_item_id(index)
	_after_change()


func _on_ghosts_toggled(pressed: bool) -> void:
	if _syncing:
		return
	_store.settings.ghosts_enabled = pressed
	_after_change()


func _on_shooter_win_selected(index: int) -> void:
	if _syncing:
		return
	_store.settings.shooter_win_condition = (
		_shooter_win_option.get_item_id(index) as MatchRules.ShooterWinCondition
	)
	_after_change()


func _on_runner_win_selected(index: int) -> void:
	if _syncing:
		return
	_store.settings.runner_win_condition = (
		_runner_win_option.get_item_id(index) as MatchRules.RunnerWinCondition
	)
	_after_change()


func _on_ability_selected(index: int) -> void:
	if _syncing:
		return
	_store.settings.runner_ability = (
		_ability_option.get_item_id(index) as MatchRules.RunnerAbility
	)
	_after_change()


func _on_rounds_changed(value: float) -> void:
	if _syncing:
		return
	_store.settings.rounds_to_win_match = int(roundf(value))
	_after_change()


## Clamp, apply and redraw the readouts. Not saved -- [method start] and
## [method close] do that, exactly as [SettingsScreen] saves on close.
##
## [method SettingsStore.apply_all] is called for the same reason the settings
## screen calls it on every change: it is what makes anything listening to
## [signal SettingsStore.applied] -- a [SettingsBoot] holding live rules -- follow
## the store instead of sampling it once.
func _after_change() -> void:
	_store.settings.clamp_all()
	_store.apply_all()
	_update_derived()


# --- Readouts -----------------------------------------------------------------

func _update_derived() -> void:
	_update_map_display()
	_update_preset_display()
	_update_readouts()
	_update_note()


## Say what the chosen map is. With one map this line is the whole reason the
## row does not read as a dead control.
func _update_map_display() -> void:
	var map: MapDefinition = MapCatalog.by_id(_store.settings.map_id)
	if map == null:
		# clamp_all() puts an unknown id back to the default, so this is only
		# reachable with no catalog at all.
		_map_summary.text = (
			"No map could be loaded. The game cannot start a match until "
			+ "%s names one." % MapCatalog.CATALOG_PATH
		)
		return
	_map_summary.text = map.summary


## Show which named mode the current rules are, or Custom.
func _update_preset_display() -> void:
	var settings: GameSettings = _store.settings
	var presets: Array[MatchPresets.Preset] = MatchPresets.all()
	var found: MatchPresets.Preset = MatchPresets.describing(settings)

	_syncing = true
	if found == null:
		_preset_option.selected = _index_of(_preset_option, CUSTOM_ID)
	else:
		_preset_option.selected = _index_of(_preset_option, presets.find(found))
	_syncing = false

	if found == null:
		_preset_badge.text = "custom rules"
		_preset_summary.text = (
			"These rules are not one of the named modes. Pick a mode above to set "
			+ "a whole coherent set at once, or press Restore Canon."
		)
		return
	_preset_badge.text = "CANON" if found.id == MatchPresets.CANON_ID else ""
	_preset_summary.text = found.summary


func _update_readouts() -> void:
	var settings: GameSettings = _store.settings

	# Asked of MatchRules so that "how many are in this match" is the same
	# arithmetic the controller builds its roster with.
	_probe.prisoner_count = settings.prisoner_count
	_prisoners_readout.text = "%d in the match" % _probe.get_participant_count()

	match _opening_of(settings):
		Opening.RACE:
			_opening_readout.text = "first to the end takes it"
		Opening.TOWER:
			_opening_readout.text = "you start with the rifle"
		Opening.RING:
			_opening_readout.text = (
				"%s starts with the rifle"
				% MatchRules.get_participant_name(settings.tower_seat_index, true)
			)

	var rounds: int = settings.rounds_to_win_match
	_rounds_readout.text = "one round" if rounds == 1 else ("%d rounds" % rounds)


## Compose the note out of things that are TRUE of the chosen rules and would
## otherwise surprise the player. Hidden when there is nothing to say; never an
## opinion about whether a rule is a good idea.
func _update_note() -> void:
	var settings: GameSettings = _store.settings
	var lines: PackedStringArray = PackedStringArray()

	if settings.prisoner_lives > 1:
		lines.append(
			"A prisoner who survives a hit gets no hit reaction and no recovery: "
			+ "the extra hits are real, the feedback for them is not designed yet."
		)
	if settings.prisoner_count <= 1 and settings.ghosts_enabled:
		lines.append(
			"With one prisoner a ghost has nobody to catch, so the mechanic never "
			+ "comes up."
		)
	if settings.skip_opening_race:
		var holder: String = MatchRules.get_participant_name(settings.tower_seat_index, true)
		lines.append(
			(
				"Skipping the race hands the tower straight to %s on turn one, with "
				+ "everybody else already running. It is the round the race would have started."
			) % holder
		)
	_probe.shooter_win_condition = settings.shooter_win_condition
	if not _probe.is_shooter_win_condition_implemented():
		lines.append(
			"This tower win condition is declared but not implemented; the tower "
			+ "cannot win the round under it."
		)
	# The two conditions that are a NUMBER as well as a rule. The screen has no
	# control for either number yet, so the note is where the player finds out
	# what they just chose -- a mode whose terms are invisible is half a mode.
	elif settings.shooter_win_condition == MatchRules.ShooterWinCondition.SHUTOUT_COUNT:
		lines.append(
			(
				"The tower wins by converting %d of the %d prisoners; the rest may "
				+ "reach the end and it still counts."
			) % [settings.shutout_count, settings.prisoner_count]
		)
	elif settings.shooter_win_condition == MatchRules.ShooterWinCondition.HOLD_DURATION:
		lines.append(
			(
				"The tower wins by holding out for %d seconds. Converting the whole "
				+ "ring is not a win under this rule; surviving the clock is."
			) % int(roundf(settings.hold_duration_seconds))
		)

	_note.text = "\n".join(lines)
	_note.visible = not lines.is_empty()


# --- Helpers ------------------------------------------------------------------

## Which of the three openings [param settings] describes.
static func _opening_of(settings: GameSettings) -> Opening:
	if not settings.skip_opening_race:
		return Opening.RACE
	return Opening.TOWER if settings.tower_seat_index <= 0 else Opening.RING


## The entry of [param option] whose item id is [param id], or 0.
##
## Item ids rather than positions everywhere on this screen: a list filled from
## an enum, from a preset array or from a clamp range has entries whose MEANING
## is the id, and reading the position back would break the day one is inserted.
static func _index_of(option: OptionButton, id: int) -> int:
	for index: int in option.item_count:
		if option.get_item_id(index) == id:
			return index
	return 0


static func _shooter_win_title(value: int) -> String:
	match value:
		MatchRules.ShooterWinCondition.TOTAL_CONVERSION:
			return "Converting every prisoner"
		MatchRules.ShooterWinCondition.SHUTOUT_COUNT:
			return "Converting a set number"
		MatchRules.ShooterWinCondition.HOLD_DURATION:
			return "Holding out for a time"
	return String(MatchRules.ShooterWinCondition.keys()[value])


static func _runner_win_title(value: int) -> String:
	match value:
		MatchRules.RunnerWinCondition.FIRST_ARRIVAL:
			return "One reaching the end"
		MatchRules.RunnerWinCondition.ALL_ARRIVALS:
			return "All of them reaching the end"
	return String(MatchRules.RunnerWinCondition.keys()[value])
