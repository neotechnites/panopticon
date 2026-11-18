extends TestCase
## Playtest regressions a small monitor finds: the Host/Join screen and its lobby with 2, 3 and 4
## seated, and the networked result buttons, must be on screen and pressable at every window size.

const SIZES: Array[Vector2i] = [
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const SETTLE_FRAMES: int = 4
const TOLERANCE: float = 1.0
const SCRATCH_CONFIG: String = "user://test_regress_ui_layout.cfg"
const LONG_NAME: String = "Bartholomew Plumestone IV"

var _real_root_size: Vector2i = Vector2i.ZERO
var _real_settings: GameSettings = GameSettings.new()
var _real_config_path: String = ""
var _sessions: Array[NetSession] = []


func before_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	_real_settings.copy_from(store.settings)
	_real_config_path = store.config_path
	store.config_path = SCRATCH_CONFIG
	store.settings.reset()
	_real_root_size = get_tree().root.size
	_sessions.clear()


func after_each() -> void:
	for i: int in range(_sessions.size() - 1, -1, -1):
		_sessions[i].leave()
	var store: SettingsStore = SettingsStore.instance()
	store.erase_file()
	store.config_path = _real_config_path
	store.settings.copy_from(_real_settings)
	get_tree().root.size = _real_root_size


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


## Every control under [param root] a player can click or type in, that is drawn.
func _interactive(root: Control) -> Array[Control]:
	var found: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var control: Control = node as Control
		if control != null and not control.visible:
			continue
		if control is BaseButton or control is LineEdit or control is TextEdit or control is SpinBox:
			found.append(control)
			if control is SpinBox:
				continue
		for child: Node in node.get_children():
			stack.append(child)
	return found


## Every interactive control under [param root] lies inside the window and no two cover each other.
func _assert_all_on_screen(root: Control, tag: String) -> void:
	var window: Rect2 = root.get_viewport().get_visible_rect()
	var controls: Array[Control] = _interactive(root)
	assert_gt(float(controls.size()), 0.0, "%s: there is something to press" % tag)
	for control: Control in controls:
		var rect: Rect2 = control.get_global_rect()
		assert_true(rect.has_area(), "%s: %s has a size" % [tag, control.name])
		assert_true(window.grow(TOLERANCE).encloses(rect), "%s: %s at %s is inside the window %s" % [
			tag, control.name, rect, window.size])
	for i: int in controls.size():
		for j: int in range(i + 1, controls.size()):
			var a: Rect2 = controls[i].get_global_rect().grow(-TOLERANCE)
			var b: Rect2 = controls[j].get_global_rect().grow(-TOLERANCE)
			assert_false(a.intersects(b), "%s: %s and %s do not overlap" % [tag, controls[i].name, controls[j].name])


## [param control] is drawn inside the window, takes keyboard focus and (unless told) is enabled.
func _assert_usable(control: Control, tag: String, enabled: bool = true) -> void:
	assert_true(control.is_visible_in_tree(), "%s: %s is drawn" % [tag, control.name])
	var window: Rect2 = control.get_viewport().get_visible_rect()
	assert_true(window.grow(TOLERANCE).encloses(control.get_global_rect()), "%s: %s at %s is inside the window %s" % [
		tag, control.name, control.get_global_rect(), window.size])
	assert_true(control.focus_mode != Control.FOCUS_NONE, "%s: %s takes focus" % [tag, control.name])
	var button: BaseButton = control as BaseButton
	if button != null and enabled:
		assert_false(button.disabled, "%s: %s is enabled" % [tag, control.name])
	var edit: LineEdit = control as LineEdit
	if edit != null and enabled:
		assert_true(edit.editable, "%s: %s can be typed in" % [tag, control.name])
	control.grab_focus()
	assert_same(control.get_viewport().gui_get_focus_owner(), control, "%s: %s holds the focus it was given" % [tag, control.name])


## The main menu with its Host/Join screen open, as the game shows it.
func _open_multiplayer() -> MainMenu:
	var menu: MainMenu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	# Two menus stand side by side in the lobby test; one audio director is the game's rule.
	var audio: Node = menu.get_node_or_null("GameAudio")
	if audio != null and AudioDirector.instance() != null:
		audio.free()
	add_child(menu)
	menu.open_multiplayer()
	return menu


func _screen(menu: MainMenu) -> MultiplayerScreen:
	return menu.get_node("%MultiplayerScreen") as MultiplayerScreen


func _part(menu: MainMenu, unique: String) -> Control:
	return _screen(menu).get_node("%" + unique) as Control


# --- PT1-01: the Host/Join screen ----------------------------------------------

func test_the_join_and_host_controls_fit_and_take_focus_at_every_window_size() -> void:
	for size: Vector2i in SIZES:
		get_tree().root.size = size
		var menu: MainMenu = _open_multiplayer()
		await _settle()
		var tag: String = "connect @%dx%d" % [size.x, size.y]
		assert_same(
			get_viewport().gui_get_focus_owner(), _part(menu, "StartHosting"),
			"%s: the screen opens with the keyboard on Host" % tag
		)
		_assert_all_on_screen(_screen(menu), tag)
		for unique: String in ["NameEdit", "StartHosting", "JoinAddressEdit", "Join", "Back"]:
			_assert_usable(_part(menu, unique), tag)
		for unique: String in ["HostPortSpin", "JoinPortSpin"]:
			var spin: SpinBox = _part(menu, unique) as SpinBox
			_assert_usable(spin.get_line_edit(), "%s %s" % [tag, unique])
		# The error a failed join writes must not push Join off the bottom.
		(_part(menu, "Status") as Label).text = tr("MP_STATUS_JOIN_FAILED").format({"error": "Connection refused by the host"})
		await _settle()
		_assert_all_on_screen(_screen(menu), "%s with an error shown" % tag)
		menu.free()
		await _settle()


## A real session of 2, 3 and 4 people; the host's and a client's lobby panel at every window size.
func test_the_lobby_fits_and_is_pressable_for_host_and_client_with_two_three_and_four() -> void:
	var host_menu: MainMenu = _open_multiplayer()
	var host_screen: MultiplayerScreen = _screen(host_menu)
	var host: NetSession = NetFixtures.make_peer(self, "Host", NetFixtures.settings())
	_sessions.append(host)
	host_screen._bind_session(host)
	var port: int = NetFixtures.reserve_port()
	if not assert_true(port > 0, "a port to host on"):
		return
	host_screen.set_player_name(LONG_NAME)
	host_screen.set_host_port(port)
	(_part(host_menu, "StartHosting") as Button).pressed.emit()
	if not await NetFixtures.poll_until(self, func() -> bool: return host.is_established() and host.lobby.get_local_seat_index() == 0):
		fail("pressing Host did not open a lobby")
		return

	var client_menu: MainMenu = _open_multiplayer()
	var client_screen: MultiplayerScreen = _screen(client_menu)
	var client: NetSession = NetFixtures.make_peer(self, "Client1", NetFixtures.settings())
	_sessions.append(client)
	client_screen._bind_session(client)
	client_screen.set_player_name(LONG_NAME + " II")
	client_screen.set_join_target("127.0.0.1", port)
	(_part(client_menu, "Join") as Button).pressed.emit()
	if not await NetFixtures.poll_until(self, func() -> bool: return client.is_established() and client.lobby.get_local_seat_index() >= 0):
		fail("pressing Join did not seat the client")
		return

	for roster: int in [2, 3, 4]:
		while _sessions.size() < roster:
			var extra: NetSession = NetFixtures.make_peer(self, "Client%d" % _sessions.size(), NetFixtures.settings())
			_sessions.append(extra)
			if extra.join("127.0.0.1", port) != OK:
				fail("client %d could not join" % _sessions.size())
				return
			if not await NetFixtures.poll_until(self, func() -> bool: return extra.is_established() and extra.lobby.get_local_seat_index() >= 0):
				fail("client %d was never seated" % _sessions.size())
				return
		if not await NetFixtures.poll_until(self, func() -> bool:
			return (_part(host_menu, "PlayerList").get_child_count() == roster
				and _part(client_menu, "PlayerList").get_child_count() == roster)):
			fail("the lobby panels never listed %d players (host %d, client %d)" % [
				roster, _part(host_menu, "PlayerList").get_child_count(), _part(client_menu, "PlayerList").get_child_count()])
			return
		for size: Vector2i in SIZES:
			get_tree().root.size = size
			for who: String in ["host", "client"]:
				var menu: MainMenu = host_menu if who == "host" else client_menu
				host_menu.visible = who == "host"
				client_menu.visible = who == "client"
				await _settle()
				var tag: String = "%s lobby of %d @%dx%d" % [who, roster, size.x, size.y]
				assert_true(_part(menu, "LobbyPanel").is_visible_in_tree(), "%s: the lobby panel is up" % tag)
				assert_false(_part(menu, "ConnectPanels").is_visible_in_tree(), "%s: the connect panels are gone" % tag)
				_assert_all_on_screen(_screen(menu), tag)
				var window: Rect2 = get_viewport().get_visible_rect()
				for row: Node in _part(menu, "PlayerList").get_children():
					var label: Label = row as Label
					assert_true(window.grow(TOLERANCE).encloses(label.get_global_rect()), "%s: the row \"%s\" is inside the window" % [tag, label.text])
				_assert_usable(_part(menu, "ReadyToggle"), tag)
				_assert_usable(_part(menu, "Leave"), tag)
				_assert_usable(_part(menu, "Back"), tag)
				var start: Button = _part(menu, "StartMatch") as Button
				if who == "host":
					_assert_usable(start, tag, false)
					_assert_usable(_part(menu, "PresetOption"), tag)
					_assert_usable(_part(menu, "MapOption"), tag)
				else:
					assert_false(start.is_visible_in_tree(), "%s: a client is not offered Start" % tag)
		# Everyone readies: the host's Start must become pressable.
		for index: int in _sessions.size():
			_sessions[index].lobby.set_ready(index, true)
		var ready: bool = await NetFixtures.poll_until(self, func() -> bool:
			return not (_part(host_menu, "StartMatch") as Button).disabled)
		assert_true(ready, "the host's Start is enabled once all %d are ready" % roster)
		for index: int in _sessions.size():
			_sessions[index].lobby.set_ready(index, false)
		await NetFixtures.poll_until(self, func() -> bool: return (_part(host_menu, "StartMatch") as Button).disabled)
	host_menu.free()
	client_menu.free()


# --- PT3-07: the networked result buttons ----------------------------------------

func test_the_rematch_and_hub_buttons_fit_and_take_focus_at_every_window_size() -> void:
	for size: Vector2i in SIZES:
		get_tree().root.size = size
		var match_root: Node3D = TestFixtures.make_match()
		add_child(match_root)
		await _settle()
		var controller: MatchController = match_root.get_node("MatchController")
		var result: MatchResultScreen = match_root.get_node("ResultScreen")
		controller._win_match(controller.get_participants()[0])
		result.show_result()
		# As a networked host sees it: both net buttons and who has asked so far.
		(result.get_node("%NetButtons") as Control).visible = true
		(result.get_node("%HubAllButton") as Control).visible = true
		var votes: Label = result.get_node("%RematchVotes")
		votes.text = tr("RESULT_REMATCH_VOTES").format({"names": ", ".join([LONG_NAME, LONG_NAME, LONG_NAME, LONG_NAME])})
		votes.visible = true
		await _settle()
		var tag: String = "result @%dx%d" % [size.x, size.y]
		var root: Control = result.get_node("%Root")
		_assert_all_on_screen(root, tag)
		assert_true(get_viewport().get_visible_rect().grow(TOLERANCE).encloses(votes.get_global_rect()), "%s: the vote line is inside the window" % tag)
		for unique: String in ["RematchButton", "HubAllButton", "PlayAgainButton", "MainMenuButton"]:
			_assert_usable(result.get_node("%" + unique) as Control, tag)
		match_root.free()
		await _settle()
