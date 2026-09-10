extends TestCase

## The bindings PANOPTICON ships, and the one rule they have to obey: the host
## OS must not be able to eat them.
##
## [b]The bug this file exists to catch.[/b] Slide shipped on Control, jump on
## Space. On Windows that is the genre-standard pair and it works. On macOS
## Control+Space is a system shortcut -- "Select the previous input source",
## symbolic hotkey 60, enabled by default and functional the moment a second
## input source exists, which a Japanese, Chinese or Korean IME or a second
## keyboard layout all quietly install. The WindowServer claims the chord before
## any application is offered it, so while Control was held the [b]Space[/b]
## press never reached the game at all. Ctrl+Space is the same story under IBus
## and fcitx on Linux.
##
## What made it expensive to find is that neither key looks broken on its own.
## Control alone reaches Godot and opens the slide; Space alone reaches Godot
## and jumps. Only the combination disappears, so the report is "the slide jump
## doesn't work on my Mac" and every instinct points at the movement code --
## which was correct the whole time, and is covered by the slide tests in
## [code]tests/test_movement.gd[/code].
##
## So the invariant asserted here is not about sliding. It is that no shipped
## default binds one of the chord-prefix modifiers, because a binding the
## operating system is entitled to intercept is not a binding.
##
## [b]Read from [ProjectSettings], not from the [InputMap].[/b] The live
## [InputMap] is whatever the last thing to touch it left behind: [SettingsStore]
## applies the player's saved overrides over the top of the shipped set at
## startup, and the settings-screen tests rebind actions inside this same
## process. A test that read the [InputMap] would be asserting on the tester's
## own [code]settings.cfg[/code] -- which is exactly how the original bug
## survived being fixed once already, because the developer's saved override
## kept handing Control back after project.godot no longer did.
## [code]ProjectSettings.get_setting("input/<action>")[/code] is the shipped set
## and nothing else can write to it.

## The modifiers whose chords desktop operating systems reserve for themselves.
##
## Shift is deliberately absent and [b]must[/b] stay absent: it is a shift-level
## modifier rather than a chord prefix, no OS builds Shift+key shortcuts out of
## it by default, and sprint has shipped on it since the beginning. Adding it
## here would fail a binding that has never caused anyone a problem.
const RESERVED_MODIFIERS: Array[Key] = [KEY_CTRL, KEY_META, KEY_ALT]

## What the project must ship for slide, in slot order.
##
## C first, because it is the one a player's hand finds and the one the project
## already carried as an alternate. Z second, so the action keeps the two slots
## [constant KeybindMap.MAX_BINDINGS] gives every other action. Written as
## literal physical keycodes rather than read from [PlayerActions], because
## [PlayerActions] is half of what is under test.
const EXPECTED_SLIDE: Array[Key] = [KEY_C, KEY_Z]

## Jump's shipped binding. Pinned because it is the other half of the chord that
## broke: moving jump onto a reserved modifier would reopen the same hole from
## the opposite side, and nothing else in the suite would notice.
const EXPECTED_JUMP: Array[Key] = [KEY_SPACE]

## Snapshot of the live [InputMap] taken before a test is allowed to disturb it.
var _saved: Dictionary[StringName, Array] = {}


func before_each() -> void:
	KeybindMap.ensure_actions_registered()
	_saved.clear()
	for action: StringName in KeybindMap.ACTIONS:
		if InputMap.has_action(action):
			_saved[action] = InputMap.action_get_events(action).duplicate()


## Put the [InputMap] back however the test left it.
##
## The [InputMap] is engine-global and outlives the case, so a test here that
## erased an action would silently change what every later test in the whole
## suite is running against. Restoring unconditionally, rather than only on the
## paths that mutate, is what makes that impossible to get wrong.
func after_each() -> void:
	for action: StringName in _saved:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, PlayerActions.DEADZONE)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)


## No shipped binding may be a modifier the OS builds its own shortcuts out of.
##
## This is the assertion that would have caught the macOS slide-jump before it
## reached a player. It sweeps every rebindable action rather than just slide,
## because the next person to reach for "an obvious spare key" will reach for
## Control on some other action and meet the same WindowServer.
func test_no_default_binds_an_os_reserved_modifier() -> void:
	for action: StringName in KeybindMap.ACTIONS:
		for key: InputEventKey in _shipped_keys(action):
			for modifier: Key in RESERVED_MODIFIERS:
				assert_false(
					key.physical_keycode == modifier,
					"%s must not default to %s: the OS reserves its chords" % [
						action, OS.get_keycode_string(modifier),
					],
				)


## Slide ships on C and Z, in that order.
func test_slide_defaults_to_c_then_z() -> void:
	assert_eq_string(
		_shipped_codes(&"slide"), _key_names(EXPECTED_SLIDE),
		"slide must ship on C then Z",
	)


## Jump is still Space, so the chord the bug needed cannot reassemble itself.
func test_jump_still_defaults_to_space() -> void:
	assert_eq_string(
		_shipped_codes(&"jump"), _key_names(EXPECTED_JUMP),
		"jump must ship on Space",
	)


## Every binding is stored by physical position, never by printed letter.
##
## [KeybindMap] documents this as the rule that keeps WASD under the same
## fingers on AZERTY, but nothing asserted it of the [b]shipped[/b] set, and the
## editor writes a plain keycode unless its "physical" toggle is on. A default
## authored through that toggle would move under a French player's hands and
## pass every other test in the suite.
func test_every_default_key_is_bound_by_physical_position() -> void:
	for action: StringName in KeybindMap.ACTIONS:
		for key: InputEventKey in _shipped_keys(action):
			assert_true(
				key.physical_keycode != KEY_NONE,
				"%s has a key binding with no physical keycode" % action,
			)
			assert_eq_int(
				int(key.keycode), int(KEY_NONE),
				"%s must bind by physical position, not by printed letter" % action,
			)


## [method PlayerActions.ensure_registered] must agree with project.godot.
##
## The fallback exists so player.tscn runs in a bare scene, which means it is
## the binding set nobody looks at -- it stayed on Control through the original
## bug and would have quietly handed Control back to any harness. Erasing the
## action is what forces the fallback to actually run; [method after_each] is
## what makes that safe.
func test_the_code_fallback_matches_the_shipped_bindings() -> void:
	InputMap.erase_action(PlayerActions.SLIDE)
	PlayerActions.ensure_registered()
	assert_eq_string(
		_names_of(InputMap.action_get_events(PlayerActions.SLIDE)),
		_shipped_codes(PlayerActions.SLIDE),
		"the PlayerActions fallback must ship the same slide keys as project.godot",
	)


## A player who rebinds slide and then resets gets C back, not Control.
##
## [KeybindMap] snapshots its defaults off the live [InputMap], so a wrong
## shipped binding and a wrong reset are the same defect seen twice. This is the
## path a player actually takes out of a bad binding, so it is worth one test of
## its own.
func test_resetting_slide_restores_the_shipped_key() -> void:
	# Seeded from the shipped set rather than trusted to be there already:
	# capture_defaults() snapshots the live InputMap, and by this point in the
	# suite that map may carry another test's rebind or the tester's own saved
	# override.
	InputMap.action_erase_events(PlayerActions.SLIDE)
	for key: InputEventKey in _shipped_keys(PlayerActions.SLIDE):
		InputMap.action_add_event(PlayerActions.SLIDE, key)

	var map: KeybindMap = KeybindMap.new()
	map.capture_defaults()

	var rebound: InputEventKey = InputEventKey.new()
	rebound.physical_keycode = KEY_CTRL
	map.set_binding(PlayerActions.SLIDE, 0, KeybindMap.event_to_binding(rebound))
	assert_eq_int(
		_code_of(map.get_binding(PlayerActions.SLIDE, 0)), int(KEY_CTRL),
		"the rebind must take, or the reset below proves nothing",
	)

	map.reset_action(PlayerActions.SLIDE)
	assert_eq_int(
		_code_of(map.get_binding(PlayerActions.SLIDE, 0)), int(EXPECTED_SLIDE[0]),
		"resetting slide must restore the shipped key",
	)


# --- Helpers ------------------------------------------------------------------

## The key events project.godot ships for [param action]. Mouse and pad
## bindings are skipped: fire and zoom are shipped on mouse buttons, which no
## operating system reserves and no keycode assertion applies to.
func _shipped_keys(action: StringName) -> Array[InputEventKey]:
	var keys: Array[InputEventKey] = []
	var setting: Variant = ProjectSettings.get_setting("input/" + String(action))
	if typeof(setting) != TYPE_DICTIONARY:
		return keys
	var declared: Dictionary = setting
	for event: Variant in declared.get("events", []):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			keys.append(key)
	return keys


## The shipped physical keycodes for [param action], as one comparable string.
##
## A string rather than an array so a failure prints "Ctrl, C" against "C, Z"
## instead of two keycode lists a reader has to decode by hand.
func _shipped_codes(action: StringName) -> String:
	var names: PackedStringArray = []
	for key: InputEventKey in _shipped_keys(action):
		names.append(OS.get_keycode_string(key.physical_keycode))
	return ", ".join(names)


## The same rendering, for a live list of [InputMap] events.
func _names_of(events: Array[InputEvent]) -> String:
	var names: PackedStringArray = []
	for event: InputEvent in events:
		var key: InputEventKey = event as InputEventKey
		if key != null:
			names.append(OS.get_keycode_string(key.physical_keycode))
	return ", ".join(names)


## The physical keycode inside a serialised [KeybindMap] binding, or 0.
func _code_of(binding: Dictionary) -> int:
	var raw: Variant = binding.get(KeybindMap.KEY_FIELD_CODE, 0)
	return int(raw) if typeof(raw) == TYPE_INT else 0


func _key_names(keys: Array[Key]) -> String:
	var names: PackedStringArray = []
	for key: Key in keys:
		names.append(OS.get_keycode_string(key))
	return ", ".join(names)
