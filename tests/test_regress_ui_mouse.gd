extends TestCase
## The cursor under the debug menu (playtest 2026-10-04): nothing a match or a hub does while the
## menu is open may hide it, and closing the menu hands the mouse back only when no other menu is up.

const SCRIPT_ROOTS: PackedStringArray = ["res://scripts", "res://hub", "res://match", "res://ui", "res://weapons", "res://tower", "res://maps"]
const OWNER_PATH: String = "res://scripts/ui/mouse_focus.gd"

var _settings: GameSettings = null


func before_each() -> void:
	_settings = SettingsStore.instance().settings
	SettingsStore.instance().settings = GameSettings.new()


func after_each() -> void:
	get_tree().paused = false
	MouseFocus.set_play_wants(false)
	SettingsStore.instance().settings = _settings


func _shown(what: String) -> void:
	assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_VISIBLE, "the cursor is still shown after %s" % what)


func _captured(what: String) -> void:
	assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_CAPTURED, "play has the mouse %s" % what)


## The debug menu up over [param scene], as a networked host has it: the world keeps running.
func _open_debug(scene: Node) -> PauseMenu:
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	menu.call("_open_debug")
	get_tree().paused = false
	return menu


func test_nothing_a_match_does_hides_the_cursor_under_the_debug_menu() -> void:
	var match_root: Node3D = TestFixtures.make_match()
	add_child(match_root)
	var controller: MatchController = match_root.get_node("MatchController")
	var result: MatchResultScreen = match_root.get_node("ResultScreen")
	result.headless_inert = false
	await step_ticks(10)
	var human: MatchParticipant = controller.get_human_participant()
	if not assert_not_null(human, "the match has a local player"):
		return
	MouseFocus.set_play_wants(true)
	_captured("before any menu opens")

	var menu: PauseMenu = _open_debug(match_root)
	_shown("the debug menu opened")

	# The round starts with the player on the ring, then the player is shot and comes back.
	controller.debug_skip_phase(GameSettings.DEBUG_TOWER_BOT)
	await step_ticks(10)
	_shown("a round started")
	if not assert_true(human.is_running, "the player is a runner in the round"):
		return
	TestFixtures.pin_the_field(controller, human)
	assert_true(controller.convert_participant(human), "the player was shot")
	assert_true(controller.is_awaiting_respawn(human), "and is held for the respawn")
	_shown("the player was shot")
	for _tick: int in 600:
		if not controller.is_awaiting_respawn(human):
			break
		await step_ticks(1)
	assert_false(controller.is_awaiting_respawn(human), "the player respawned")
	await step_ticks(10)
	_shown("the player respawned")

	# A body's input waking, as a respawn or a new scene does, and a click falling through.
	var fresh: HumanIntentSource = HumanIntentSource.new()
	add_child(fresh)
	_shown("a new body's input came up")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	fresh._unhandled_input(click)
	_shown("a click reached the body's input")
	var trigger: WeaponInput = WeaponInput.new()
	trigger.weapon = controller.rifle
	add_child(trigger)
	_shown("a rifle's trigger came up")

	# The seat changes hands: to the player, to a bot, and on through three round turnovers.
	controller.debug_skip_phase(GameSettings.DEBUG_TOWER_ME)
	await step_ticks(10)
	assert_true(controller.get_seat_participant() == human, "the player took the tower")
	_shown("the player took the tower")
	for turnover: int in 3:
		controller.debug_skip_phase(GameSettings.DEBUG_TOWER_BOT)
		await step_ticks(10)
		_shown("round turnover %d" % turnover)
	controller.debug_restart_round()
	await step_ticks(10)
	_shown("the round restarted")

	# The match ends under the menu, and a rematch starts under it.
	controller._win_match(controller.get_participants()[0])
	await step_ticks(5)
	assert_true(result.is_showing(), "the result came up under the menu")
	_shown("the result screen came up")
	result.play_again()
	await step_ticks(10)
	assert_false(result.is_showing(), "Play Again took the result down")
	_shown("Play Again restarted the match")
	controller.restart()
	await step_ticks(10)
	_shown("the match restarted")

	# Closing over a result leaves the cursor for the result; only then does play get the mouse.
	controller._win_match(controller.get_participants()[0])
	await step_ticks(5)
	menu.call("_close_debug")
	assert_false(menu.is_open(), "the menu closed")
	_shown("the debug menu closed over a result screen")
	result.play_again()
	await step_ticks(5)
	_captured("once the result is gone too")

	# And the plain case: open, close, back to play.
	menu = _open_debug(match_root)
	_shown("the debug menu opened again")
	menu.call("_close_debug")
	_captured("after the debug menu closes with nothing else up")
	fresh.free()
	trigger.free()


func test_the_hub_panel_and_the_debug_menu_do_not_take_the_cursor_from_each_other() -> void:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	TestFixtures.silence_human_input(hub)
	var lobby: HubLobby = hub.get_node("HubLobby") as HubLobby
	lobby.changes_scene = false
	add_child(hub)
	await step_ticks(5)
	MouseFocus.set_play_wants(true)
	var menu: PauseMenu = _open_debug(hub)
	_shown("the debug menu opened in the hub")
	lobby.set_overlay_open(true)
	_shown("the hub panel opened under it")
	lobby.set_overlay_open(false)
	_shown("the hub panel closed under it")
	lobby.set_overlay_open(true)
	menu.call("_close_debug")
	_shown("the debug menu closed over the open hub panel")
	lobby.set_overlay_open(false)
	_captured("once the hub panel closes too")
	get_tree().paused = false


## One owner: no game script but MouseFocus may capture or hide the mouse.
func test_only_the_mouse_owner_captures_or_hides_the_mouse() -> void:
	var offenders: PackedStringArray = PackedStringArray()
	var scanned: int = 0
	var stack: Array[String] = []
	for root: String in SCRIPT_ROOTS:
		stack.append(root)
	while not stack.is_empty():
		var folder: String = stack.pop_back()
		for sub: String in DirAccess.get_directories_at(folder):
			stack.append(folder.path_join(sub))
		for file: String in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			var path: String = folder.path_join(file)
			scanned += 1
			if path == OWNER_PATH:
				continue
			var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
			for number: int in lines.size():
				var line: String = lines[number].strip_edges()
				if line.begins_with("#"):
					continue
				var writes: bool = line.contains("set_mouse_mode(") or (
					line.contains("mouse_mode =") and not line.contains("mouse_mode ==")
				)
				# Showing the cursor outright is harmless; anything else must go through the owner.
				if writes and not line.ends_with("= Input.MOUSE_MODE_VISIBLE"):
					offenders.append("%s:%d  %s" % [path, number + 1, line])
	assert_gt(float(scanned), 50.0, "the scan read the game's scripts")
	assert_true(offenders.is_empty(), "only MouseFocus may take the cursor away:\n    %s" % "\n    ".join(offenders))
