extends TestCase

## [HudCrosshair]: the shipped match's crosshair shows where the old dot did -- for a player
## with a readout, scoped or not, centred on the screen -- and nowhere else.

const SETTLE_TICKS: int = 60
const STAGE_LIB: GDScript = preload("res://tools/capture/stages/lib.gd")

var _match: Node3D
var _controller: MatchController
var _hud: MatchHud
var _human: MatchParticipant


func _arm(to_the_human: bool) -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = TestFixtures.match_rules()
	add_child(_match)
	_hud = _match.get_node("HUD/Root") as MatchHud
	_human = _controller.get_human_participant()
	var opener: MatchParticipant = _human
	if not to_the_human:
		for participant: MatchParticipant in _controller.get_participants():
			if not participant.is_human():
				opener = participant
				break
	opener.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	_hud.tick()


func test_the_guard_sees_the_cross_at_the_centre_of_the_screen() -> void:
	await _arm(true)
	var cross: HudCrosshair = _hud.crosshair as HudCrosshair
	assert_not_null(cross, "the HUD's crosshair is the drawn cross, not the old dot")
	assert_true(cross.is_visible_in_tree(), "the guard sees it")
	var screen: Vector2 = _hud.get_viewport().get_visible_rect().size
	assert_vec2_eq(cross.get_screen_centre(), screen * 0.5, "centred where the dot was")


func test_the_scope_draws_no_reticle_and_sits_under_the_cross() -> void:
	await _arm(true)
	var vignette: ScopeVignette = _controller.rifle.get_node(^"ScopeVignette") as ScopeVignette
	assert_eq_int(vignette.get_child_count(), 1, "the scope carries its glass and nothing drawn over it")
	var hud_layer: CanvasLayer = _match.get_node(^"HUD") as CanvasLayer
	assert_gt(hud_layer.layer, vignette.layer, "the cross draws over the scoped view")


func test_a_prisoner_sees_it_and_a_ghost_does_not() -> void:
	await _arm(false)
	assert_true(_hud.crosshair.is_visible_in_tree(), "a running prisoner sees the cross")
	assert_true(_controller.apply_hit(_human), "the rifle converts the human")
	_hud.tick()
	assert_false(_hud.crosshair.is_visible_in_tree(), "a ghost does not")


func test_the_capture_crosshair_option_keeps_only_the_cross() -> void:
	await _arm(true)
	assert_true(STAGE_LIB.show_only_the_crosshair(_match), "the capture HUD option finds the HUD")
	assert_true(_hud.crosshair.is_visible_in_tree(), "the cross is on")
	assert_false(_hud.status_panel.visible, "and the rest of the HUD is off")
