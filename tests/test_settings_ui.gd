extends TestCase

## [SettingsScreen] and [KeybindPanel]: what the Controls tab offers, and where
## it puts it.
##
## The bug this file exists to catch shipped as "the controls setting section is
## all jumbled". It was not one defect but a shape of defect: the keybind rows
## were nine independent [HBoxContainer]s, each reserving the same guessed pixel
## width for its name column, so the table only looked like a table while every
## label happened to fit inside the guess. Any row whose label did not fit slid
## out of step with the other eight. Nothing asserted on the arrangement, so
## nothing noticed.
##
## So these tests read the [b]built scene[/b] rather than the source list: they
## instantiate [code]scenes/ui/settings_screen.tscn[/code], walk the nodes that
## a player would actually be looking at, and assert on their rectangles. A
## regression that put the rows back in [InputMap] order, leaked Godot's own
## [code]ui_*[/code] actions into the list, or let two rows overlap would fail
## here.
##
## [b]Why a [SubViewport].[/b] The headless root window is 64x64, which is too
## small for any layout assertion to mean anything. Each test builds its own
## viewport at a real resolution, so "does this fit" is a question about the
## game's own window sizes rather than about the test harness.

## Resolutions the layout is asserted at. 1280x720 is the smallest
## [constant GameSettings.RESOLUTION_CHOICES] offers, so it is the floor the
## dialog is designed to fit inside; 1920x1080 is what the bug was reported on.
const SMALLEST_SUPPORTED: Vector2i = Vector2i(1280, 720)
const REPORTED_ON: Vector2i = Vector2i(1920, 1080)

## The actions the Controls tab must offer, in the order a player reads them:
## movement together, then the movement modifiers, then the weapon.
##
## Spelled out rather than read from [constant KeybindMap.ACTIONS], because that
## constant is half of what is under test -- a test that took its expectation
## from the same list it is checking would pass no matter what order that list
## drifted into.
const EXPECTED_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"jump",
	&"slide",
	&"ability",
	&"fire",
	&"zoom",
]

## Index of the Controls tab in the authored [TabContainer]. Fourth of five:
## Match, Game, Audio, Video, Controls, in the order they are authored in
## scenes/ui/settings_screen.tscn.
const CONTROLS_TAB: int = 4

## Frames to let a container settle. Godot sorts containers on a deferred call,
## and a tab that has just been revealed has not been laid out yet -- reading
## positions on the same frame returns every row stacked at the tab's origin,
## which is a fact about the engine's scheduling and not about the scene.
const SETTLE_FRAMES: int = 4

var _viewport: SubViewport = null
var _screen: SettingsScreen = null
var _tabs: TabContainer = null
var _panel: KeybindPanel = null


## Where the shared store is pointed while this file runs. A rebind saves to
## disk the instant it is made -- that is deliberate, losing one is maddening --
## so the suite must redirect it rather than write over the real settings of
## whoever is running the tests.
const SCRATCH_CONFIG: String = "user://test_settings_ui.cfg"

var _real_config_path: String = ""


func before_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	_real_config_path = store.config_path
	store.config_path = SCRATCH_CONFIG
	store.keybinds.reset_to_defaults()
	await _open_settings_at(SMALLEST_SUPPORTED)


func after_each() -> void:
	var store: SettingsStore = SettingsStore.instance()
	store.erase_file()
	store.config_path = _real_config_path
	store.keybinds.reset_to_defaults()
	store.keybinds.apply_to_input_map()


# --- What the tab offers ------------------------------------------------------

## Exactly the game's own actions, in the authored order, and nothing else.
##
## The failure this pins is walking the [InputMap] instead of an authored list.
## [InputMap] iteration is unordered and includes Godot's built-in
## [code]ui_accept[/code], [code]ui_left[/code] and the rest, so a list built
## that way shows the player a dozen actions they have never heard of in an
## order nobody chose.
func test_the_controls_tab_offers_exactly_the_games_own_actions() -> void:
	var shown: Array[StringName] = _panel.get_displayed_actions()

	assert_eq_int(
		shown.size(), EXPECTED_ACTIONS.size(),
		"the Controls tab shows one row per game action and no more",
	)

	for i: int in mini(shown.size(), EXPECTED_ACTIONS.size()):
		assert_eq_string(
			String(shown[i]), String(EXPECTED_ACTIONS[i]),
			"row %d is the action the screen was authored to put there" % i,
		)

	for action: StringName in shown:
		assert_false(
			String(action).begins_with("ui_"),
			"'%s' is one of Godot's built-in UI actions and must never be offered for rebinding" % action,
		)


## Every row carries a written-out name, not the raw action string.
func test_every_row_is_labelled_for_a_human() -> void:
	for action: StringName in EXPECTED_ACTIONS:
		var label: String = _panel.get_row_name(action)
		assert_false(label.is_empty(), "'%s' has a name in the table" % action)
		assert_false(
			label.contains("_"),
			"'%s' is labelled '%s', which is the action name rather than a written-out one" % [action, label],
		)


# --- Where it puts it ---------------------------------------------------------

## The nine rows read top to bottom, one per line, in the authored order.
##
## This is the "jumbled" assertion proper: every row strictly below the one
## before it, and no two rows sharing vertical space.
func test_the_rows_are_stacked_in_order_and_never_overlap() -> void:
	var rows: Array[Rect2] = _row_rects()
	if not assert_eq_int(rows.size(), EXPECTED_ACTIONS.size(), "every action has a row on screen"):
		return

	for i: int in range(1, rows.size()):
		var above: Rect2 = rows[i - 1]
		var below: Rect2 = rows[i]
		assert_ge(
			below.position.y, above.position.y + above.size.y,
			"row %d ('%s') starts below row %d ('%s') instead of overlapping it" % [
				i, EXPECTED_ACTIONS[i], i - 1, EXPECTED_ACTIONS[i - 1],
			],
		)


## The four columns line up across all nine rows.
##
## A [GridContainer] shares one set of column widths, so this holds by
## construction; it broke when the rows were separate [HBoxContainer]s that each
## guessed the same width. Asserting the left edges agree is what would catch a
## return to that arrangement.
func test_the_columns_line_up_across_every_row() -> void:
	for column: int in range(4):
		var edges: PackedFloat32Array = _column_left_edges(column)
		if not assert_eq_int(edges.size(), EXPECTED_ACTIONS.size(), "column %d has a cell in every row" % column):
			continue
		for i: int in range(1, edges.size()):
			assert_almost_eq(
				edges[i], edges[0], 0.5,
				"column %d of row %d ('%s') is at x=%.1f but row 0 puts it at x=%.1f" % [
					column, i, EXPECTED_ACTIONS[i], edges[i], edges[0],
				],
			)


## Nothing in the table is drawn outside the panel that is supposed to contain
## it, at either resolution.
##
## The old layout put the keybind rows under a bare [Control], whose minimum
## size is always zero, so the settings panel never knew the table needed room
## and was free to crush it -- which it did, slicing the last row in half under
## the footer.
func test_the_table_stays_inside_its_panel_when_the_window_resizes() -> void:
	for size: Vector2i in [SMALLEST_SUPPORTED, REPORTED_ON, Vector2i(1600, 900)]:
		await _resize(size)
		var bounds: Rect2 = _visible_rect(_panel)
		for i: int in EXPECTED_ACTIONS.size():
			var cell: Control = _cell(EXPECTED_ACTIONS[i], 0)
			var rect: Rect2 = _visible_rect(cell)
			assert_true(
				bounds.grow(1.0).encloses(rect),
				"at %s, row %d ('%s') at %s escapes the keybind panel at %s" % [
					size, i, EXPECTED_ACTIONS[i], rect, bounds,
				],
			)


## The keybind panel reports a real minimum size, so its container can reserve
## room for it.
##
## Zero here is the specific defect that let the table be crushed: a bare
## [Control] never propagates the size of what is anchored inside it.
func test_the_keybind_panel_asks_for_the_room_it_needs() -> void:
	var minimum: Vector2 = _panel.get_combined_minimum_size()
	assert_gt(minimum.x, 0.0, "the keybind panel declares a minimum width")
	assert_gt(minimum.y, 0.0, "the keybind panel declares a minimum height")

	var tab: Control = _tabs.get_tab_control(CONTROLS_TAB)
	assert_ge(
		tab.get_combined_minimum_size().x, minimum.x,
		"the Controls tab reserves at least the width the table needs",
	)


# --- What it persists ---------------------------------------------------------

## A rebind survives a save and a reload.
##
## Runs against a private [SettingsStore] on its own file rather than the shared
## instance, so the suite never touches the player's real
## [code]user://settings.cfg[/code].
func test_a_rebind_round_trips_through_the_settings_file() -> void:
	var path: String = "user://test_settings_ui_round_trip.cfg"

	var written: SettingsStore = SettingsStore.new()
	written.config_path = path
	written.bootstrap()
	written.keybinds.set_binding(&"jump", 0, {
		KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_KEY,
		KeybindMap.KEY_FIELD_CODE: KEY_G,
	})
	written.keybinds.clear_binding(&"slide", 0)
	assert_eq_int(written.save_to_disk(), OK, "the settings file is written")

	var read: SettingsStore = SettingsStore.new()
	read.config_path = path
	read.load_from_disk()

	assert_true(read.loaded_from_disk, "the file that was just written reads back")
	assert_eq_int(
		read.keybinds.get_binding(&"jump", 0).get(KeybindMap.KEY_FIELD_CODE, 0), KEY_G,
		"the rebound key survives the round trip",
	)
	assert_true(
		read.keybinds.get_binding(&"slide", 0).is_empty(),
		"a slot the player cleared on purpose stays cleared rather than reverting to its default",
	)

	read.erase_file()


## A pre-migration slide binding does not survive into this build.
##
## Slide's shipped default moved from Control to Shift+Z -- Control+Space is a
## symbolic hotkey macOS reserves for itself, see
## tests/test_keybind_defaults.gd -- and [constant SettingsStore.SLIDE_CHOSEN_FROM_VERSION]
## exists so a file written under the old default hands back the new key rather
## than the stale one. This is the round trip a returning player actually takes:
## boot with an old file on disk and get the new default; rebind after that and
## the rebind sticks.
func test_a_pre_migration_slide_binding_is_replaced_by_the_new_default() -> void:
	var path: String = "user://test_settings_ui_slide_migration.cfg"

	var old_file: ConfigFile = ConfigFile.new()
	old_file.set_value(SettingsStore.SECTION_META, "version", 2)
	old_file.set_value(KeybindMap.SECTION_KEYBINDS, String(PlayerActions.SLIDE), [
		{KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_KEY, KeybindMap.KEY_FIELD_CODE: KEY_CTRL},
		{},
	])
	assert_eq_int(int(old_file.save(path)), int(OK), "the version 2 file is written")

	var store: SettingsStore = SettingsStore.new()
	store.config_path = path
	store.bootstrap()

	assert_eq_int(
		int(store.keybinds.get_binding(PlayerActions.SLIDE, 0).get(KeybindMap.KEY_FIELD_CODE, 0)),
		int(KEY_SHIFT),
		"the stale Control binding is discarded for the shipped Shift key",
	)

	# A file this build writes is believed, Ctrl included: rebinding to it after
	# this version is a choice, not a leftover default.
	store.keybinds.set_binding(PlayerActions.SLIDE, 0, {
		KeybindMap.KEY_FIELD_TYPE: KeybindMap.TYPE_KEY,
		KeybindMap.KEY_FIELD_CODE: KEY_CTRL,
	})
	assert_eq_int(store.save_to_disk(), OK, "the current file is written")
	assert_true(store.load_from_disk(), "the current file is readable")
	assert_eq_int(
		int(store.keybinds.get_binding(PlayerActions.SLIDE, 0).get(KeybindMap.KEY_FIELD_CODE, 0)),
		int(KEY_CTRL),
		"a chosen rebind survives the round trip",
	)

	store.erase_file()


## Clicking a slot and pressing a key rebinds that slot, and only that slot.
##
## Every button in the table is wired by the script to a cell the scene
## authored, so a rename in the scene or a missed connection would leave a row
## that looks right and does nothing. This drives the whole path a player takes:
## press the slot, press a key, read the button's new caption.
##
## The shared [SettingsStore] is pointed at a scratch file for the duration --
## a rebind saves immediately, and a test suite must not write over the settings
## of whoever is running it.
func test_pressing_a_slot_and_then_a_key_rebinds_that_slot() -> void:
	var slot: Button = _cell(&"jump", 2) as Button
	assert_eq_string(slot.text, "Unbound", "jump's second slot starts empty")

	slot.pressed.emit()
	assert_true(_panel.is_capturing(), "pressing a slot arms a capture")

	_press(KEY_G)
	assert_false(_panel.is_capturing(), "the captured key ends the capture")
	assert_eq_string(slot.text, "G", "the slot now shows the key that was pressed")

	assert_eq_string(
		(_cell(&"jump", 0) as Label).text, "Jump",
		"the row it belongs to is untouched",
	)
	assert_eq_string(
		(_cell(&"fire", 2) as Button).text, "Unbound",
		"no other row's slot was written",
	)


## Escape leaves the binding exactly as it was.
func test_escape_abandons_a_rebind() -> void:
	var slot: Button = _cell(&"jump", 1) as Button
	var before: String = slot.text

	slot.pressed.emit()
	_press(KEY_ESCAPE)

	assert_false(_panel.is_capturing(), "Escape ends the capture")
	assert_eq_string(slot.text, before, "the binding is the one it started with")


## Feed a key press at the panel the way the viewport would.
func _press(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	_panel._input(event)


# --- The video tab ------------------------------------------------------------
#
# These exist because of a bug report that read "changing the resolution did not
# change the size of the screen". The control was wired correctly and the choice
# was saved correctly; the game was running inside the editor's embedded Game
# window, where DisplayServer.window_set_size does nothing at all and prints one
# line into a log the player never reads. Nothing on the screen said so, so a
# working control was indistinguishable from a broken one.

## Picking a size writes it into the store and it survives a restart.
##
## The restart is a second [SettingsStore] reading the same file, which is
## exactly what the next launch does -- see [method SettingsStore.load_from_disk].
func test_a_chosen_resolution_survives_a_restart() -> void:
	var chosen: Vector2i = GameSettings.RESOLUTION_CHOICES[2]
	var option: OptionButton = _screen.get_node("%ResolutionOption") as OptionButton

	option.selected = 2
	option.item_selected.emit(2)

	assert_true(
		_screen._store.settings.resolution == chosen,
		"picking '%s' put %s in the store, not %s" % [
			option.get_item_text(2), chosen, _screen._store.settings.resolution,
		],
	)

	_screen.close()

	var restarted: SettingsStore = SettingsStore.new()
	restarted.config_path = SCRATCH_CONFIG
	assert_true(restarted.load_from_disk(), "the settings file the screen wrote is readable")
	assert_true(
		restarted.settings.resolution == chosen,
		"a restart reads back %s, not %s" % [chosen, restarted.settings.resolution],
	)


## The note under the resolution control says the window refused, when it did.
##
## [member GameSettings.window_resize_refused] is set by measuring -- the size
## before the call and after it, against the size asked for -- so this test sets
## the measured outcome directly rather than trying to summon a display server
## that refuses, which no headless suite can do.
func test_the_video_note_says_so_when_the_window_refuses_to_resize() -> void:
	var note: Label = _screen.get_node("%VideoNote") as Label

	_screen._store.settings.window_resize_refused = false
	_screen.refresh()
	assert_eq_string(
		note.text, SettingsScreen.RESOLUTION_NOTE,
		"with the window obeying, the note is the ordinary explanation",
	)

	_screen._store.settings.window_resize_refused = true
	_screen.refresh()
	assert_true(
		note.text.contains("did not resize"),
		"with the window refusing, the note says so; it says '%s'" % note.text,
	)
	assert_true(
		note.text.contains("saved"),
		"and it says the choice was kept, because it was; it says '%s'" % note.text,
	)


# The other half of the same bug -- apply_video() dragging a maximised window
# back to the stored resolution every time an unrelated setting moved -- is not
# asserted here. It cannot be: apply_video() is a no-op with no display server,
# so a headless test of it would pass whatever the code did. It was measured
# instead, against a real window on real hardware; see the probe results in the
# session that made this change.


# --- Fixtures -----------------------------------------------------------------

## Instantiate the shipped scene, show the Controls tab, and let it settle.
func _open_settings_at(size: Vector2i) -> void:
	_viewport = SubViewport.new()
	_viewport.size = size
	# Nothing is drawn; only the layout is under test, and rendering a viewport
	# the assertions never read is wasted work in every test in this file.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_screen = (load("res://scenes/ui/settings_screen.tscn") as PackedScene).instantiate()
	_viewport.add_child(_screen)
	await step_ticks(1)

	_tabs = _find_tab_container(_screen)
	_tabs.current_tab = CONTROLS_TAB
	_panel = _screen.find_child("KeybindPanel", true, false) as KeybindPanel
	await step_ticks(SETTLE_FRAMES)


func _resize(size: Vector2i) -> void:
	_viewport.size = size
	await step_ticks(SETTLE_FRAMES)


func _find_tab_container(node: Node) -> TabContainer:
	for child: Node in node.get_children():
		var tabs: TabContainer = child as TabContainer
		if tabs != null:
			return tabs
		var found: TabContainer = _find_tab_container(child)
		if found != null:
			return found
	return null


## The grid cell in [param column] of [param action]'s row: 0 is the name, 1 and
## 2 the two binding slots, 3 the per-action reset.
func _cell(action: StringName, column: int) -> Control:
	var table: GridContainer = _panel.find_child("Table", true, false) as GridContainer
	var index: int = EXPECTED_ACTIONS.find(action) * table.columns + column
	return table.get_child(index) as Control


## One rectangle per row, spanning that row's four cells.
func _row_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for action: StringName in EXPECTED_ACTIONS:
		var row: Rect2 = _visible_rect(_cell(action, 0))
		for column: int in range(1, 4):
			row = row.merge(_visible_rect(_cell(action, column)))
		rects.append(row)
	return rects


func _column_left_edges(column: int) -> PackedFloat32Array:
	var edges: PackedFloat32Array = PackedFloat32Array()
	for action: StringName in EXPECTED_ACTIONS:
		edges.append(_visible_rect(_cell(action, column)).position.x)
	return edges


func _visible_rect(control: Control) -> Rect2:
	return Rect2(control.global_position, control.size)
