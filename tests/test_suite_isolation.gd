extends TestCase

## The suite runs on its own [code]user://[/code], never the settings of whoever runs it.

func test_user_data_lives_in_the_directory_the_runner_isolated() -> void:
	var isolated: String = OS.get_environment("PANOPTICON_TEST_HOME")
	if isolated.is_empty():
		skip("run with -- --in-process: no supervisor, so nothing isolated user://")
		return
	var user_dir: String = OS.get_user_data_dir().simplify_path()
	assert_true(
		user_dir.begins_with(isolated.simplify_path()),
		"user:// is %s, outside the isolated %s" % [user_dir, isolated],
	)


func test_the_shared_settings_store_started_from_no_file() -> void:
	if OS.get_environment("PANOPTICON_TEST_HOME").is_empty():
		skip("run with -- --in-process: no supervisor, so nothing isolated user://")
		return
	var store: SettingsStore = SettingsStore.instance()
	assert_eq_string(store.config_path, SettingsStore.CONFIG_PATH, "the store reads the shipped path")
	var defaults: GameSettings = GameSettings.new()
	assert_true(store.settings.equals(defaults), "and holds the shipped defaults, not a saved file's")


## Every static the runner watches or resets still exists under that name.
func test_no_watched_static_has_gone_missing() -> void:
	var state: Dictionary[String, String] = SharedState.fingerprint(get_tree())
	for key: String in state:
		assert_false(state[key] == SharedState.MISSING, "%s is watched by SharedState but no longer exists" % key)


## A test that leaves the shared store changed does not hand it on: the runner puts it back.
func test_a_changed_store_is_put_back() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.settings.prisoner_count = GameSettings.MIN_PRISONER_COUNT
	HubLobby.returns_to_hub = true
	SharedState.restore()
	assert_true(store.settings.equals(GameSettings.new()), "the store is back on the shipped defaults")
	assert_false(HubLobby.returns_to_hub, "and so is the hub's switch")


## The runner's watch sees a shared resource retuned in place and a node left under the root.
func test_the_watch_sees_what_cannot_be_put_back() -> void:
	var rules: MatchRules = load(TestFixtures.MATCH_RULES_PATH) as MatchRules
	var before: Dictionary[String, String] = SharedState.fingerprint(get_tree())
	var kept: int = rules.prisoner_count
	rules.prisoner_count = kept + 1
	var stray: Node = Node.new()
	get_tree().root.add_child(stray)
	var seen: PackedStringArray = SharedState.changed(before, SharedState.fingerprint(get_tree()))
	rules.prisoner_count = kept
	get_tree().root.remove_child(stray)
	stray.free()
	assert_eq_int(seen.size(), 2, "both are reported: %s" % "; ".join(seen))
	assert_true(SharedState.changed(before, SharedState.fingerprint(get_tree())).is_empty(), "and neither once undone")
