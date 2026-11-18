extends TestCase
## The host's live rules in a session are the lobby's, as every client's are: a settings apply on the host
## cannot drift its match away from the rules it published.

var _session: NetSession = null
var _saved: GameSettings = null


func before_each() -> void:
	_saved = SettingsStore.instance().settings
	SettingsStore.instance().settings = GameSettings.new()


func after_each() -> void:
	if _session != null:
		_session.leave()
		_session.get_parent().remove_child(_session)
		_session.free()
		_session = null
	SettingsStore.instance().settings = _saved


func test_a_settings_apply_on_the_host_keeps_the_published_rules() -> void:
	_session = (load(NetFixtures.SESSION_SCENE_PATH) as PackedScene).instantiate() as NetSession
	_session.name = "NetSession"
	_session.settings = NetFixtures.settings()
	_session.flow.follows = false
	get_tree().root.add_child(_session)
	if await NetFixtures.host_and_wait(self, _session) < 0:
		fail("the host could not take a port")
		return
	_session.lobby.open("Host")
	var published: MatchRules = TestFixtures.match_rules()
	published.prisoner_lives = 3
	published.rounds_to_win_match = 4
	_session.lobby.set_rules(published)
	# The host's own saved settings say otherwise.
	var store: SettingsStore = SettingsStore.instance()
	store.settings.prisoner_lives = 1
	store.settings.rounds_to_win_match = 1
	var live: MatchRules = TestFixtures.match_rules()
	var boot: SettingsBoot = SettingsBoot.new()
	boot.match_rules = live
	add_child(boot)
	store.applied.emit()
	assert_eq_int(live.prisoner_lives, 3, "the host's match keeps the lives it published")
	assert_eq_int(live.rounds_to_win_match, 4, "and the rounds")
	boot.queue_free()
