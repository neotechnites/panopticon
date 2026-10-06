extends TestCase

## The debug menu's Bots count is the saved prisoner count, and a match's rules follow it.


func test_bots_write_the_prisoner_count_into_settings_and_rules() -> void:
	var settings: GameSettings = GameSettings.new()
	var rules: MatchRules = MatchRules.new()
	DebugMenu.write_bot_count(settings, 5, rules)
	assert_eq_int(settings.prisoner_count, 5, "the saved count is the bots chosen")
	assert_eq_int(rules.prisoner_count, 5, "the running match's rules follow it")


func test_bots_clamp_and_pull_the_shutout_under_them() -> void:
	var settings: GameSettings = GameSettings.new()
	var rules: MatchRules = MatchRules.new()
	DebugMenu.write_bot_count(settings, 99, rules)
	assert_eq_int(settings.prisoner_count, GameSettings.MAX_PRISONER_COUNT, "too many clamps to the most")
	settings.shutout_count = 4
	rules.shutout_count = 4
	DebugMenu.write_bot_count(settings, 2, rules)
	assert_eq_int(settings.shutout_count, 2, "a shutout above the bots is pulled down")
	assert_eq_int(rules.shutout_count, 2, "and in the match's rules too")
	DebugMenu.write_bot_count(settings, 0, rules)
	assert_eq_int(settings.prisoner_count, GameSettings.MIN_PRISONER_COUNT, "too few clamps to the least")
