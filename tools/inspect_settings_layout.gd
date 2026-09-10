extends SceneTree

## Prints where the settings screen actually puts things, and complains when
## that is somewhere wrong.
##
## [codeblock]
## godot --headless --path . --script res://tools/inspect_settings_layout.gd
## godot --headless --path . --script res://tools/inspect_settings_layout.gd -- --size 1920x1080
## godot --headless --path . --script res://tools/inspect_settings_layout.gd -- --quiet
## [/codeblock]
##
## Exits 0 when every check held and 1 when any did not, so it can be run in
## anger as well as read.
##
## [b]Why this exists.[/b] The settings screen shipped with its Controls tab
## "all jumbled" and there was no way to look at it: headless cannot render a
## UI, and a screenshot on the one machine that showed the fault is a picture,
## not a measurement. This walks the built scene and turns the arrangement into
## numbers -- which row is where, which column edge is where, what escapes its
## container -- so a layout complaint can be reproduced, argued about and fixed
## from a terminal.
##
## [code]tests/test_settings_ui.gd[/code] asserts on the same properties and is
## what guards them in CI. This tool is the one you reach for when a test has
## failed and you want to see the whole table rather than the first assertion
## that tripped, or when you are changing the layout and want to know what it
## did. Keep the two in step.
##
## [b]It measures a [SubViewport], not the real window.[/b] The headless root is
## 64x64, at which nothing about a layout is meaningful. Every resolution below
## is a viewport built for the purpose, which also means one run can compare
## several without restarting the engine.

## Resolutions checked when [code]--size[/code] is not given. The first is the
## smallest [constant GameSettings.RESOLUTION_CHOICES] offers, and so the floor
## the dialog is designed to fit inside; the last is a common desktop.
const DEFAULT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

## Index of the Controls tab in the authored [TabContainer]. Fourth of five:
## Match, Game, Audio, Video, Controls, in the order they are authored in
## scenes/ui/settings_screen.tscn.
const CONTROLS_TAB: int = 4

## Cells per keybind row: name, slot 1, slot 2, reset.
const COLUMNS: int = 4

## Frames allowed for containers to sort. Godot lays containers out on a
## deferred call, so a tab that was revealed this frame has not been positioned
## yet and every row still reads as sitting at the tab's origin. Measuring then
## reports a pile of overlaps that exist only in the scheduler.
const SETTLE_FRAMES: int = 6

## How far two edges may differ and still count as aligned. Container maths is
## done in floats; half a pixel is rounding, anything more is a real step.
const ALIGN_TOLERANCE: float = 0.5

const EXIT_OK: int = 0
const EXIT_PROBLEMS: int = 1

var _sizes: Array[Vector2i] = []
var _quiet: bool = false

var _frames: int = 0
var _index: int = -1
var _settle: int = 0
var _problems: int = 0

var _viewport: SubViewport = null
var _screen: Control = null
var _panel: Node = null
var _table: GridContainer = null


func _initialize() -> void:
	# Argument parsing only. Nodes added here are not in the tree yet, so
	# nothing that needs a layout can happen before the first _process.
	_parse_arguments()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_next_size()
		return false

	_settle += 1
	if _settle < SETTLE_FRAMES:
		return false

	_report()
	_tear_down()
	if _index + 1 >= _sizes.size():
		_summarise()
		return true
	_next_size()
	return false


# --- Arguments ----------------------------------------------------------------

func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--quiet":
				_quiet = true
			"--size":
				i += 1
				if i < args.size():
					var parsed: Vector2i = _parse_size(args[i])
					if parsed != Vector2i.ZERO:
						_sizes.append(parsed)
					else:
						push_warning("ignoring unreadable --size '%s'" % args[i])
		i += 1
	if _sizes.is_empty():
		_sizes.assign(DEFAULT_SIZES)


## Reads [code]1920x1080[/code], or [constant Vector2i.ZERO] if it will not.
static func _parse_size(text: String) -> Vector2i:
	var parts: PackedStringArray = text.to_lower().split("x", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


# --- Fixture ------------------------------------------------------------------

func _next_size() -> void:
	_index += 1
	_settle = 0

	_viewport = SubViewport.new()
	_viewport.size = _sizes[_index]
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_viewport)

	_screen = (load("res://scenes/ui/settings_screen.tscn") as PackedScene).instantiate()
	_viewport.add_child(_screen)

	var tabs: TabContainer = _find_tab_container(_screen)
	if tabs != null:
		tabs.current_tab = CONTROLS_TAB
	_panel = _screen.find_child("KeybindPanel", true, false)
	_table = _screen.find_child("Table", true, false) as GridContainer


func _tear_down() -> void:
	_viewport.queue_free()
	_viewport = null
	_screen = null
	_panel = null
	_table = null


# --- Reporting ----------------------------------------------------------------

func _report() -> void:
	var size: Vector2i = _sizes[_index]
	print("\n=== settings screen at %dx%d ===" % [size.x, size.y])

	if _table == null:
		_fail("the Controls tab has no keybind Table -- the scene is not what this tool expects")
		return

	var actions: Array = _panel.call("get_displayed_actions")
	print("  %d keybind rows, in the order the scene lays them out:" % actions.size())

	var rows: Array[Rect2] = []
	for i: int in actions.size():
		var action: StringName = actions[i]
		var row: Rect2 = _cell_rect(i, 0)
		var cells: PackedStringArray = PackedStringArray()
		for column: int in range(COLUMNS):
			row = row.merge(_cell_rect(i, column))
			cells.append(_cell_text(i, column))
		rows.append(row)
		if not _quiet:
			print("    %d  %-14s %-28s y=%7.1f h=%5.1f  x=%7.1f w=%6.1f" % [
				i, action, " | ".join(cells), row.position.y, row.size.y, row.position.x, row.size.x,
			])
		if String(action).begins_with("ui_"):
			_fail("row %d is Godot's built-in action '%s', which must never be offered for rebinding" % [i, action])

	_check_stacking(actions, rows)
	_check_columns(actions)
	_check_containment(actions)


## Every row strictly below the one before it. This is "jumbled" in its most
## literal form: rows sharing vertical space are rows drawn on top of each other.
func _check_stacking(actions: Array, rows: Array[Rect2]) -> void:
	for i: int in range(1, rows.size()):
		var above: Rect2 = rows[i - 1]
		var below: Rect2 = rows[i]
		if below.position.y < above.position.y + above.size.y - ALIGN_TOLERANCE:
			_fail("row %d ('%s') at y=%.1f overlaps row %d ('%s') which ends at y=%.1f" % [
				i, actions[i], below.position.y,
				i - 1, actions[i - 1], above.position.y + above.size.y,
			])


## Every column at the same left edge in every row.
##
## This is the property that a [GridContainer] gives for free and that nine
## independent [HBoxContainer]s cannot: one shared set of column widths. When it
## breaks, the table stops reading as a table.
func _check_columns(actions: Array) -> void:
	for column: int in range(COLUMNS):
		var reference: float = _cell_rect(0, column).position.x
		for i: int in range(1, actions.size()):
			var edge: float = _cell_rect(i, column).position.x
			if absf(edge - reference) > ALIGN_TOLERANCE:
				_fail("column %d of row %d ('%s') starts at x=%.1f but row 0 starts it at x=%.1f" % [
					column, i, actions[i], edge, reference,
				])


## Nothing drawn outside the panel meant to contain it.
##
## Catches the crushed-panel failure: when the table's container does not
## reserve room for it, rows are sliced by whatever is drawn next.
func _check_containment(actions: Array) -> void:
	var bounds: Rect2 = _control_rect(_panel as Control).grow(1.0)
	for i: int in actions.size():
		for column: int in range(COLUMNS):
			var rect: Rect2 = _cell_rect(i, column)
			if not bounds.encloses(rect):
				_fail("row %d ('%s') column %d at %s escapes the keybind panel at %s" % [
					i, actions[i], column, rect, bounds,
				])


func _summarise() -> void:
	print("")
	if _problems == 0:
		print("OK  settings layout clean at %d resolution(s)" % _sizes.size())
		quit(EXIT_OK)
		return
	print("PROBLEMS  %d layout fault(s) across %d resolution(s)" % [_problems, _sizes.size()])
	quit(EXIT_PROBLEMS)


func _fail(message: String) -> void:
	_problems += 1
	print("    PROBLEM: %s" % message)


# --- Node access --------------------------------------------------------------

func _cell(row: int, column: int) -> Control:
	var index: int = row * _table.columns + column
	if index < 0 or index >= _table.get_child_count():
		return null
	return _table.get_child(index) as Control


func _cell_rect(row: int, column: int) -> Rect2:
	return _control_rect(_cell(row, column))


func _cell_text(row: int, column: int) -> String:
	var control: Control = _cell(row, column)
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	return ""


static func _control_rect(control: Control) -> Rect2:
	if control == null:
		return Rect2()
	return Rect2(control.global_position, control.size)


func _find_tab_container(node: Node) -> TabContainer:
	for child: Node in node.get_children():
		var tabs: TabContainer = child as TabContainer
		if tabs != null:
			return tabs
		var found: TabContainer = _find_tab_container(child)
		if found != null:
			return found
	return null
