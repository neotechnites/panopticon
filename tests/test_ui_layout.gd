extends TestCase

## Every screen survives the pseudo-locale at every shipped window size.
##
## The root window is resized to each resolution, so the project's own
## canvas_items stretch (1600x900, expand) is what lays the screen out. Each
## visible Label/Button must fit its text, every Control must sit inside its
## parent, and no two content controls may overlap.

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(3840, 2160),
]

const PSEUDO_LOCALE: String = "en_XA"
const SCRATCH_CONFIG: String = "user://test_ui_layout.cfg"

## Containers sort on a deferred call; a screen shown this frame reads as a pile.
const SETTLE_FRAMES: int = 4
const TOLERANCE: float = 1.0

## A long participant/player name, as the pseudo-locale would lengthen one.
const LONG_NAME: String = "[Bärthölöméw Plüméstöné ~~~~]"

var _real_locale: String = ""
var _real_settings: GameSettings = GameSettings.new()
var _real_config_path: String = ""
var _real_root_size: Vector2i = Vector2i.ZERO
var _violations: PackedStringArray = PackedStringArray()


func before_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	_real_settings.copy_from(store.settings)
	_real_config_path = store.config_path
	store.config_path = SCRATCH_CONFIG
	_real_locale = TranslationServer.get_locale()
	store.settings.locale = PSEUDO_LOCALE
	TranslationServer.set_locale(PSEUDO_LOCALE)
	_real_root_size = get_tree().root.size


func after_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.erase_file()
	store.config_path = _real_config_path
	store.settings.copy_from(_real_settings)
	TranslationServer.set_locale(_real_locale)
	get_tree().root.size = _real_root_size


# --- Screens ------------------------------------------------------------------

func test_main_menu_and_its_screens() -> void:
	var settings: GameSettings = SettingsStore.instance().settings
	for size: Vector2i in SIZES:
		settings.reset()
		var menu: MainMenu = _instance("res://scenes/ui/main_menu.tscn", size)
		await _settle()
		_audit("main menu", size, menu)

		menu.open_match_setup()
		await _settle()
		_audit("match setup (canon)", size, menu)
		# Every note the screen can raise at once, under custom rules.
		settings.prisoner_count = 1
		settings.ghosts_enabled = true
		settings.prisoner_lives = 3
		settings.skip_opening_race = true
		settings.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
		(menu.get_node("%MatchSetupScreen") as MatchSetupScreen).refresh()
		await _settle()
		_audit("match setup (custom)", size, menu)
		settings.reset()

		menu.open_multiplayer()
		await _audit_multiplayer(menu.get_node("%MultiplayerScreen") as MultiplayerScreen, menu, size)

		menu.open_settings()
		await _audit_settings(menu.get_node("%SettingsScreen") as SettingsScreen, menu, size, "menu settings")
		menu.free()
	_report()


func _audit_multiplayer(screen: MultiplayerScreen, root: Control, size: Vector2i) -> void:
	var status: Label = screen.get_node("%Status")
	status.text = tr("MP_STATUS_JOIN_FAILED").format({"error": "[Cönnéctïön réfüséd bý thé höst ~~~~]"})
	await _settle()
	_audit("multiplayer (connect)", size, root)

	screen.get_node("%ConnectPanels").visible = false
	screen.get_node("%LobbyPanel").visible = true
	(screen.get_node("%LobbyTitle") as Label).text = tr("MP_LOBBY_JOINED").format({"address": "192.168.100.200:27960"})
	var rows: VBoxContainer = screen.get_node("%PlayerList")
	for seat: int in 8:
		var row: Label = Label.new()
		var shown: String = tr("MP_SEAT_NAME_YOU").format({"name": tr("MP_SEAT_NAME_BOT").format({"name": LONG_NAME})})
		row.text = tr("MP_SEAT_ROW").format({
			"number": seat + 1, "name": shown, "role": tr("HUD_ROLE_PRISONER"), "ready": tr("MP_READY_NO"),
		})
		rows.add_child(row)
	(screen.get_node("%RulesSummary") as Label).text = tr("MP_RULES_SUMMARY").format({
		"mode": tr("SETUP_PRESET_CLASSIC"), "prisoners": 8, "ghosts": tr("MP_READY_NO"),
		"opening": tr("SETUP_OPENING_RACE"), "rounds": tr("SETUP_ROUNDS_MANY").format({"count": 3}),
	})
	(screen.get_node("%StartMatch") as Button).visible = true
	await _settle()
	_audit("multiplayer (lobby)", size, root)


func _audit_settings(screen: SettingsScreen, root: Control, size: Vector2i, tag: String) -> void:
	screen.refresh()
	var tabs: TabContainer = screen.get_node("Frame/Dialog/Padding/Layout/Tabs")
	(screen.get_node("%VideoNote") as Label).text = tr("SETTINGS_VIDEO_NOTE_EMBEDDED")
	var panel: KeybindPanel = screen.get_node("%KeybindPanel")
	(panel.get_node("Layout/Footer/Status") as Label).text = tr("KEYBIND_STATUS_CONFLICT").format({
		"binding": "[Rïght Shïft ~~~~]", "other": "[Prïsönér Pöwér 4 ~~~~]",
	})
	for tab: int in tabs.get_tab_count():
		tabs.current_tab = tab
		await _settle()
		_audit("%s tab %d" % [tag, tab], size, root)
	# The capture overlay covers the Controls tab on purpose; it is its own layout.
	var overlay: Control = panel.get_node("CaptureOverlay")
	(panel.get_node("CaptureOverlay/CaptureLabel") as Label).text = tr("KEYBIND_CAPTURE_PROMPT").format({
		"action": KeybindMap.display_name(&"ability_4"), "slot": 2,
	})
	overlay.visible = true
	await _settle()
	_audit("%s capture" % tag, size, overlay)
	overlay.visible = false


func test_pause_menu() -> void:
	for size: Vector2i in SIZES:
		get_tree().root.size = size
		var menu: PauseMenu = PauseMenu.new()
		add_child(menu)
		menu.open()
		await _settle()
		var root: Control = menu.get_child(0) as Control
		_audit("pause", size, root)
		for child: Node in root.get_children():
			(child as Control).visible = child is SettingsScreen
		await _audit_settings(root.get_node("SettingsScreen") as SettingsScreen, root, size, "pause settings")
		menu.close()
		menu.free()
	_report()


func test_match_overlays() -> void:
	for size: Vector2i in SIZES:
		get_tree().root.size = size
		var match_root: Node3D = TestFixtures.make_match()
		add_child(match_root)
		var controller: MatchController = match_root.get_node("MatchController")
		await _settle()

		var hud: Control = _arm_hud(match_root.get_node("HUD/Root") as MatchHud)
		var death: Control = _arm_death(controller)
		await _settle()
		_audit("hud", size, hud)
		_audit("death screen", size, death)

		var result: MatchResultScreen = match_root.get_node("ResultScreen")
		_fill_result(result)
		await _settle()
		_audit("result", size, result.get_node("%Root") as Control)
		result.get_node("%Root").visible = false
		result.get_node("%Beat").visible = true
		await _settle()
		_audit("result beat", size, result.get_node("%Beat") as Control)

		var card: Control = _arm_round_card(match_root.get_node("RoundTransition"))
		await _settle()
		_audit("round card", size, card)
		match_root.free()
	_report()


func test_hub_hud_and_overlay() -> void:
	for size: Vector2i in SIZES:
		get_tree().root.size = size
		var hub: Node3D = (load("res://scenes/hub/hub.tscn") as PackedScene).instantiate() as Node3D
		TestFixtures.silence_human_input(hub)
		(hub.get_node("HubLobby") as HubLobby).changes_scene = false
		add_child(hub)
		var lines: PackedStringArray = PackedStringArray()
		for seat: int in 8:
			lines.append(tr("HUB_SEAT_ROW").format({
				"number": seat + 1,
				"name": tr("HUB_SEAT_NAME_HOST").format({"name": tr("HUB_SEAT_NAME_YOU").format({"name": LONG_NAME})}),
			}))
		var hud: Control = hub.get_node("HUD/Root")
		(hud.get_node("Players") as Label).text = tr("HUB_PLAYERS_MANY").format({"count": 8})
		var prompt: Label = hud.get_node("Prompt")
		prompt.text = tr("HUB_START_PROMPT").format({"map": tr("HUB_MAP_1"), "key": "[Ïntéräct ~~~~]"})
		prompt.visible = true
		var vote: Label = hud.get_node("Vote")
		var vote_lines: PackedStringArray = PackedStringArray([tr("HUB_VOTE_TIMER").format({"seconds": 30})])
		for i: int in 8:
			vote_lines.append(tr("HUB_VOTE_ROW").format({"map": tr("HUB_MAP_1"), "count": i}))
		vote.text = "\n".join(vote_lines)
		vote.visible = true
		var overlay: Control = hub.get_node("Overlay/Root")
		(overlay.get_node("Row/SeatsMargin/Seats") as Label).text = "\n".join(lines)
		overlay.visible = true
		await _settle()
		_audit("hub hud", size, hud)
		_audit("hub overlay", size, overlay)
		hub.free()
	_report()


# --- Arming the code-built overlays -------------------------------------------

func _arm_hud(hud: MatchHud) -> Control:
	hud.set_process(false)
	for child: Node in hud.get_children():
		(child as Control).visible = true
	var status: String = "  ·  ".join([
		tr("HUD_ROUND").format({"round": 12}),
		"%s 8/8" % tr("HUD_ROLE_PRISONER"),
		tr("HUD_TOWER_HOLDER").format({"name": LONG_NAME}),
	])
	(hud.get_node("Status/Line") as Label).text = status
	(hud.get_node("Flash") as Label).text = tr("HUD_TOWER_TAKEN_BY").format({"name": LONG_NAME.to_upper()})
	(hud.get_node("Flash") as Label).modulate = Color.WHITE
	(hud.get_node("TowerReload/Rows/Head/Value") as Label).text = tr("HUD_READY")
	(hud.get_node("GuardReload/Value") as Label).text = tr("HUD_READY")
	(hud.get_node("Power/Rows/Name") as Label).text = tr("HUD_ABILITY_COOLDOWN").format({
		"title": MatchRules.runner_ability_title(MatchRules.RunnerAbility.BUBBLE_SHIELD).to_upper(), "seconds": "12",
	})
	(hud.get_node("Boost") as Label).text = tr("HUD_SPEED_BOOST").format({"multiplier": 2, "seconds": "12.0"})
	(hud.get_node("Dev") as Label).text = " · ".join([
		tr("HUD_DEV_INVINCIBLE"), tr("HUD_DEV_TURBO"), tr("HUD_DEV_FREECAM"),
	])
	return hud


func _arm_death(controller: MatchController) -> Control:
	var screen: MatchDeathScreen = MatchDeathScreen.new()
	screen.headless_inert = false
	screen.controller = controller
	add_child(screen)
	screen.set_process(false)
	var root: Control = screen.get_node("Root")
	root.visible = true
	(root.get_node("Band/Column/Title") as Label).text = tr("DEATH_OUT_ROUND").format({"round": 12})
	(root.get_node("Band/Column/Countdown") as Label).text = "10.0"
	(root.get_node("Band/Column/Hint") as Label).text = tr("DEATH_HINT_GHOST")
	return root


func _fill_result(result: MatchResultScreen) -> void:
	result.set_process(false)
	var headline: String = "\n".join([
		tr("RESULT_WINNER_HELD_TOWER").format({"name": LONG_NAME}), tr("RESULT_ROLE_PRISONER_GHOST"),
	])
	var detail: String = "\n".join([
		tr("RESULT_DETAIL_TOWER").format({"name": LONG_NAME, "turn": 12, "rounds": 12}),
		tr("RESULT_DETAIL_ROUNDS").format({"rounds": 12}),
		tr("RESULT_DETAIL_CLEARED").format({"cleared": 8, "total": 8}),
		tr("RESULT_DETAIL_SWAPS").format({"swaps": 12}),
	])
	(result.get_node("%Verdict") as Label).text = tr("RESULT_MATCH_OVER")
	(result.get_node("%Headline") as Label).text = headline
	(result.get_node("%Detail") as Label).text = detail
	(result.get_node("%BeatVerdict") as Label).text = tr("RESULT_MATCH_OVER")
	(result.get_node("%BeatHeadline") as Label).text = headline
	(result.get_node("%BeatHint") as Label).visible = true
	result.get_node("%Beat").visible = false
	result.get_node("%Root").visible = true


func _arm_round_card(card: RoundTransitionScreen) -> Control:
	card.set_process(false)
	var root: Control = card.get_node("%Root")
	root.visible = true
	(card.get_node("%Round") as Label).text = tr("ROUND_TITLE").format({"round": 12})
	(card.get_node("%MapName") as Label).text = tr("HUB_MAP_1")
	(card.get_node("%Tower") as Label).text = tr("ROUND_TOWER").format({"name": LONG_NAME.to_upper(), "turn": 12})
	(card.get_node("%Prisoners") as Label).text = tr("ROUND_PRISONERS").format({"count": 8})
	(card.get_node("%Hint") as Label).visible = true
	return root


# --- The audit ----------------------------------------------------------------

func _instance(path: String, size: Vector2i) -> Control:
	get_tree().root.size = size
	var screen: Control = (load(path) as PackedScene).instantiate() as Control
	add_child(screen)
	screen.visible = true
	return screen


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _report() -> void:
	assert_true(
		_violations.is_empty(),
		"%d layout violation(s):\n    %s" % [_violations.size(), "\n    ".join(_violations)],
	)


## Walk [param root]: text fits, rects nest, content does not overlap.
func _audit(screen: String, size: Vector2i, root: Control) -> void:
	assertions += 1
	if root == null or not root.is_visible_in_tree():
		_violations.append("%s @%dx%d: nothing visible to audit" % [screen, size.x, size.y])
		return
	var tag: String = "%s @%dx%d" % [screen, size.x, size.y]
	var leaves: Array[Control] = []
	var rects: Array[Rect2] = []
	var viewport: Rect2 = root.get_viewport().get_visible_rect()
	_walk(root, viewport, viewport, tag, leaves, rects)
	for i: int in leaves.size():
		var a: Rect2 = rects[i].grow(-TOLERANCE)
		for j: int in range(i + 1, leaves.size()):
			var b: Rect2 = rects[j].grow(-TOLERANCE)
			if a.intersects(b):
				_violations.append("%s: %s overlaps %s (%s vs %s)" % [
					tag, _name(leaves[i], root), _name(leaves[j], root), _fmt(a), _fmt(b),
				])


## [param allowed] is where the control may lie; [param clip] is what a
## ScrollContainer above it lets the player see.
func _walk(
	control: Control, allowed: Rect2, clip: Rect2, tag: String,
	leaves: Array[Control], rects: Array[Rect2],
) -> void:
	var rect: Rect2 = control.get_global_rect()
	if not allowed.grow(TOLERANCE).encloses(rect):
		_violations.append("%s: %s at %s escapes its parent %s" % [
			tag, _name(control, null), _fmt(rect), _fmt(allowed),
		])
	_check_text(control, tag)
	if control is TabContainer:
		_check_tabs(control as TabContainer, tag)
	if _is_content(control):
		var seen: Rect2 = rect.intersection(clip)
		if seen.has_area():
			leaves.append(control)
			rects.append(seen)
	var inner: Rect2 = rect
	var inner_clip: Rect2 = clip
	if control is ScrollContainer:
		var scroll: ScrollContainer = control as ScrollContainer
		inner_clip = clip.intersection(rect)
		if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			inner = Rect2(inner.position.x - 1e6, inner.position.y, 2e6, inner.size.y)
		if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			inner = Rect2(inner.position.x, inner.position.y - 1e6, inner.size.x, 2e6)
	elif control.clip_contents:
		inner_clip = clip.intersection(rect)
	for child: Node in control.get_children():
		var sub: Control = child as Control
		if sub != null and sub.visible:
			_walk(sub, inner, inner_clip, tag, leaves, rects)


func _check_text(control: Control, tag: String) -> void:
	if control is SpinBox:
		_check_line_edit((control as SpinBox).get_line_edit(), control, tag)
		return
	if control is LineEdit:
		_check_line_edit(control as LineEdit, control, tag)
		return
	if not (control is Label or control is Button):
		return
	var text: String = str(control.get("text"))
	if text.is_empty():
		return
	if control is Label:
		var label: Label = control as Label
		label.clip_text = false
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else:
		var button: Button = control as Button
		button.clip_text = false
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var need: Vector2 = control.get_minimum_size()
	var have: Vector2 = control.size
	if need.x > have.x + TOLERANCE or need.y > have.y + TOLERANCE:
		_violations.append("%s: %s text \"%s\" needs %s, has %s" % [
			tag, _name(control, null), control.atr(text).left(40), _fmt_v(need), _fmt_v(have),
		])


## A LineEdit scrolls rather than grows, so its text is measured by hand.
func _check_line_edit(edit: LineEdit, owner: Control, tag: String) -> void:
	var text: String = edit.text if not edit.text.is_empty() else edit.placeholder_text
	if text.is_empty():
		return
	var font: Font = edit.get_theme_font(&"font")
	var need: float = (
		font.get_string_size(edit.atr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, edit.get_theme_font_size(&"font_size")).x
		+ edit.get_theme_stylebox(&"normal").get_minimum_size().x
	)
	if need > edit.size.x + TOLERANCE:
		_violations.append("%s: %s text \"%s\" needs %.0f px, has %.0f" % [
			tag, _name(owner, null), text.left(40), need, edit.size.x,
		])


func _check_tabs(tabs: TabContainer, tag: String) -> void:
	var bar: TabBar = tabs.get_tab_bar()
	if bar == null or bar.tab_count == 0:
		return
	var last: Rect2 = bar.get_tab_rect(bar.tab_count - 1)
	if last.end.x > bar.size.x + TOLERANCE or bar.get_tab_rect(0).position.x < -TOLERANCE:
		_violations.append("%s: tab bar of %s does not fit its %d tabs in %.0f px" % [
			tag, _name(tabs, null), bar.tab_count, bar.size.x,
		])


static func _is_content(control: Control) -> bool:
	return (
		control is Label or control is RichTextLabel or control is BaseButton
		or control is LineEdit or control is TextEdit or control is Range
		or control is Separator or control is SubViewportContainer
	)


static func _name(control: Control, root: Control) -> String:
	if root != null:
		return String(root.get_path_to(control))
	return String(control.get_path()).trim_prefix("/root/")


static func _fmt(rect: Rect2) -> String:
	return "[%.0f,%.0f %.0fx%.0f]" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _fmt_v(v: Vector2) -> String:
	return "%.0fx%.0f" % [v.x, v.y]
