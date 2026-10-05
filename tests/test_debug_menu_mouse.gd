extends TestCase

## The cursor stays visible while the debug menu is open, whatever play does.


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_menu() -> PauseMenu:
	var menu: PauseMenu = PauseMenu.new()
	add_child(menu)
	menu.call("_open_debug")
	return menu


func test_a_respawned_body_does_not_recapture_under_the_debug_menu() -> void:
	var menu: PauseMenu = _open_menu()
	var fresh: HumanIntentSource = HumanIntentSource.new()
	add_child(fresh)
	assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_VISIBLE, "a new body's ready left the cursor hidden")
	menu.close()
	assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_CAPTURED, "closing did not hand the mouse back")


func test_a_click_under_the_debug_menu_does_not_recapture() -> void:
	var menu: PauseMenu = _open_menu()
	var source: HumanIntentSource = HumanIntentSource.new()
	source.capture_mouse_on_ready = false
	add_child(source)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = true
	source._unhandled_input(click)
	assert_true(MouseFocus.wanted_mode() == Input.MOUSE_MODE_VISIBLE, "a click hid the cursor under the menu")
	menu.close()
