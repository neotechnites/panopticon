class_name MatchPresets
extends RefCounted

## The named ways to play, as data.
##
## [b]Why presets and not just fields.[/b] The rules on the match setup screen
## are not independent knobs: "six prisoners" and "every prisoner must reach the
## end" and "ghosts off" are answers that only make sense in groups, and a player
## who wants a different game wants to pick the game, not to reconstruct it a
## field at a time. A preset is that group, named once, in one place. The screen
## still lets every field be overridden afterwards -- override and the preset
## picker simply reads [b]Custom[/b], because it no longer describes what is set.
##
## [b]Why this is a script and not a folder of [MatchRules] resources.[/b] It was
## the first design and it is wrong. A [MatchRules] preset would carry all
## twenty-six fields, including [member MatchRules.track_radius] and the AI
## profiles, so applying one would silently overwrite arena geometry and
## component tuning that no player asked about -- and quietly undo whatever the
## harness had been sweeping. A preset here names ONLY the curated subset the
## screen owns, which is the same subset [method GameSettings.apply_to_match_rules]
## writes, so a preset can never reach further than the screen can.
##
## [b]Canon is first and is the default.[/b] [constant CANON_ID] is the rule set
## the game is designed around and the one the shipped
## [code]resources/rules/default_match_rules.tres[/code] plays; every default in
## [GameSettings] agrees with it, so a player who never opens this screen is
## already playing it.

## One named way to play: a title, a sentence, and the curated rules it sets.
##
## Every field here has a counterpart in [GameSettings] and no field here has a
## counterpart anywhere else. That is the whole invariant -- see the note on
## resources above.
class Preset extends RefCounted:
	## Stable identity, used by tests and never shown to a player.
	var id: StringName = &""

	## What the picker shows.
	var title: String = ""

	## One sentence, shown under the picker. What the mode IS, not a warning.
	var summary: String = ""

	var prisoner_count: int = GameSettings.DEFAULT_PRISONER_COUNT
	var prisoner_lives: int = GameSettings.DEFAULT_PRISONER_LIVES
	var ghosts_enabled: bool = GameSettings.DEFAULT_GHOSTS_ENABLED
	var skip_opening_race: bool = GameSettings.DEFAULT_SKIP_OPENING_RACE
	var tower_seat_index: int = GameSettings.DEFAULT_TOWER_SEAT_INDEX
	var shooter_win_condition: MatchRules.ShooterWinCondition = (
		MatchRules.ShooterWinCondition.TOTAL_CONVERSION
	)
	var runner_win_condition: MatchRules.RunnerWinCondition = (
		MatchRules.RunnerWinCondition.FIRST_ARRIVAL
	)
	var rounds_to_win_match: int = GameSettings.DEFAULT_ROUNDS_TO_WIN_MATCH

	## Write this preset over [param settings].
	##
	## Writes every field it owns, always. A preset that only wrote its
	## non-default fields would leave the previous preset's choices standing
	## underneath it, so picking Riot after Siege would give a third game that
	## nobody named.
	func apply_to(settings: GameSettings) -> void:
		if settings == null:
			return
		settings.prisoner_count = prisoner_count
		settings.prisoner_lives = prisoner_lives
		settings.ghosts_enabled = ghosts_enabled
		settings.skip_opening_race = skip_opening_race
		settings.tower_seat_index = tower_seat_index
		settings.shooter_win_condition = shooter_win_condition
		settings.runner_win_condition = runner_win_condition
		settings.rounds_to_win_match = rounds_to_win_match
		settings.clamp_all()

	## True when [param settings] is currently playing exactly this preset.
	##
	## This is how the picker knows what to show, rather than remembering which
	## button was last pressed: a remembered choice and the values it set can
	## disagree the moment one field is overridden, and the picker would then
	## name a mode the player is not playing.
	##
	## [member tower_seat_index] is compared only when the race is skipped,
	## because it is the seat the tower is HANDED to and nothing hands it while
	## it is being raced for -- a stale seat index under a racing preset is not a
	## different game.
	func describes(settings: GameSettings) -> bool:
		if settings == null:
			return false
		if settings.skip_opening_race != skip_opening_race:
			return false
		if skip_opening_race and settings.tower_seat_index != tower_seat_index:
			return false
		return (
			settings.prisoner_count == prisoner_count
			and settings.prisoner_lives == prisoner_lives
			and settings.ghosts_enabled == ghosts_enabled
			and settings.shooter_win_condition == shooter_win_condition
			and settings.runner_win_condition == runner_win_condition
			and settings.rounds_to_win_match == rounds_to_win_match
		)


## The canon way to play. The default, the first entry in [method all], and what
## [method GameSettings.reset] already produces on its own.
const CANON_ID: StringName = &"canon"

## Built once and handed out, because [method describes] is called on every one
## of them every time a control moves.
static var _all: Array[Preset] = []


## Every named mode, canon first.
static func all() -> Array[Preset]:
	if _all.is_empty():
		_all = _build()
	return _all


## The canon preset, or null if somebody has renamed [constant CANON_ID] out from
## under it.
static func canon() -> Preset:
	return by_id(CANON_ID)


## The preset with [param id], or null.
static func by_id(id: StringName) -> Preset:
	for preset: Preset in all():
		if preset.id == id:
			return preset
	return null


## The preset [param settings] is currently playing, or null for Custom.
static func describing(settings: GameSettings) -> Preset:
	for preset: Preset in all():
		if preset.describes(settings):
			return preset
	return null


## True when [param settings] is playing canon.
static func is_canon(settings: GameSettings) -> bool:
	var preset: Preset = canon()
	return preset != null and preset.describes(settings)


static func _build() -> Array[Preset]:
	var presets: Array[Preset] = []

	# Canon. Deliberately spelled out rather than left to Preset's own field
	# defaults: this is the rule set the game IS, and it should be readable here
	# without chasing four files. It must equal what GameSettings.reset()
	# produces -- tests/test_match_setup.gd asserts exactly that.
	var canon_preset: Preset = Preset.new()
	canon_preset.id = CANON_ID
	canon_preset.title = "Canon"
	canon_preset.summary = (
		"The game as designed. Three prisoners, one hit each, ghosts on, and an "
		+ "opening race for the tower. One prisoner through the end takes the seat; "
		+ "hold the seat through a round and the match is yours."
	)
	canon_preset.prisoner_count = 3
	canon_preset.prisoner_lives = 1
	canon_preset.ghosts_enabled = true
	canon_preset.skip_opening_race = false
	canon_preset.rounds_to_win_match = 1
	presets.append(canon_preset)

	# The control case every claim about ghosts is measured against, offered to
	# a player as a mode because it is one: a shot prisoner is simply gone.
	var classic: Preset = Preset.new()
	classic.id = &"classic"
	classic.title = "Classic"
	classic.summary = (
		"Canon without ghosts. A shot prisoner is out of the round and the ring "
		+ "empties as the tower works. Fewer bodies, shorter rounds, no second chance."
	)
	classic.prisoner_count = 3
	classic.prisoner_lives = 1
	classic.ghosts_enabled = false
	classic.skip_opening_race = false
	classic.rounds_to_win_match = 1
	presets.append(classic)

	# One runner, no ghosts, and a match long enough that a single lucky lap does
	# not decide it. Ghosts are off because a ghost with nobody to catch is not
	# the mechanic -- it needs a second living prisoner to swap with.
	var duel: Preset = Preset.new()
	duel.id = &"duel"
	duel.title = "Duel"
	duel.summary = (
		"One prisoner, one rifle, no ghosts, and three rounds to take the match. "
		+ "The tower and the ring trade places until somebody holds the seat three times."
	)
	duel.prisoner_count = 1
	duel.prisoner_lives = 1
	duel.ghosts_enabled = false
	duel.skip_opening_race = false
	duel.rounds_to_win_match = 3
	presets.append(duel)

	# The crowded end of the difficulty dial. Six is inside the measured start
	# line; see GameSettings.MAX_PRISONER_COUNT.
	var riot: Preset = Preset.new()
	riot.id = &"riot"
	riot.title = "Riot"
	riot.summary = (
		"Six prisoners against one single-shot rifle, ghosts on. The tower cannot "
		+ "cover the ring; the question is how much of it you can."
	)
	riot.prisoner_count = 6
	riot.prisoner_lives = 1
	riot.ghosts_enabled = true
	riot.skip_opening_race = false
	riot.rounds_to_win_match = 1
	presets.append(riot)

	# The only preset that moves a win condition, which is the point of it: this
	# is the mode that asks a different question of the map.
	var siege: Preset = Preset.new()
	siege.id = &"siege"
	siege.title = "Siege"
	siege.summary = (
		"Four prisoners, and leakage is not enough: EVERY prisoner still in the "
		+ "round has to reach the end. One left on the ring keeps the tower alive."
	)
	siege.prisoner_count = 4
	siege.prisoner_lives = 1
	siege.ghosts_enabled = true
	siege.skip_opening_race = false
	siege.runner_win_condition = MatchRules.RunnerWinCondition.ALL_ARRIVALS
	siege.rounds_to_win_match = 1
	presets.append(siege)

	return presets
