extends TestCase

## The power panel, bottom-right of a prisoner's HUD, on the shipped match scene: it names the
## power that is running whatever key started it, its time left, and its cooldown.

const SETTLE_TICKS: int = 30
const DURATION_SECONDS: float = 5.0

var _match: Node3D
var _controller: MatchController
var _hud: MatchHud
var _rules: MatchRules
var _human: MatchParticipant
var _body: PlayerController
var _input: BotIntentSource
var _power: RunnerPower


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_rules.runner_ability = MatchRules.RunnerAbility.NONE
	_rules.ability_duration_seconds = DURATION_SECONDS
	_rules.ability_cooldown_seconds = 0.0
	_controller.rules = _rules
	add_child(_match)
	_hud = _match.get_node("HUD/Root") as MatchHud
	var participants: Array[MatchParticipant] = _controller.get_participants()
	_human = _controller.get_human_participant()
	_body = _human.body
	_input = BotIntentSource.new()
	_input.name = "TestInput"
	_body.add_child(_input)
	_body.intent_source = _input
	# The panel is a prisoner's: nothing in these tests may take the viewed body off the ring.
	_input.command.godmode = true
	_power = RunnerPower.of(_body)
	for participant: MatchParticipant in participants:
		var bot: BotIntentSource = participant.body.intent_source as BotIntentSource
		if bot != null:
			bot.shove_enabled = false
	for participant: MatchParticipant in participants:
		if not participant.is_human():
			participant.tracker.lap_finished.emit(30.0, 240.0)
			break
	await step_ticks(SETTLE_TICKS)
	_hud.tick()
	assert_eq_int(int(_hud.get_role()), int(MatchHud.Role.PRISONER), "the viewed player is a prisoner")
	assert_not_null(_power, "the viewed body carries a power node")


func test_a_number_key_power_is_named_with_nothing_picked() -> void:
	_input.command.ability_held = true
	assert_true(_power.activate(MatchRules.RunnerAbility.ARMOR_LOCK), "the armor lock starts")
	await step_ticks(6)
	_hud.tick()
	assert_true(_hud.power_panel.visible, "the power panel is up for a power nobody picked")
	var text: String = _hud.get_context_text()
	assert_true(
		text.contains(_title(MatchRules.RunnerAbility.ARMOR_LOCK)),
		"the panel names the armor lock -- got \"%s\"" % text,
	)
	assert_eq_string(
		text, _active_text(MatchRules.RunnerAbility.ARMOR_LOCK),
		"with the seconds it has left",
	)
	assert_between(_power.get_remaining(), 0.1, DURATION_SECONDS - 0.01, "which are counting down")
	assert_almost_eq(
		_hud.power_fill.anchor_right, _power.get_remaining() / DURATION_SECONDS, 0.001,
		"and the bar is the share of the run left",
	)


func test_the_panel_names_the_running_power_not_the_picked_one() -> void:
	_rules.runner_ability = MatchRules.RunnerAbility.BUBBLE_SHIELD
	_hud.tick()
	assert_eq_string(
		_hud.get_context_text(),
		tr("HUD_ABILITY_READY").format({"title": _title(MatchRules.RunnerAbility.BUBBLE_SHIELD)}),
		"at rest the panel offers the picked power",
	)
	assert_true(_power.activate(MatchRules.RunnerAbility.ACTIVE_CAMO), "camo starts by its own key")
	await step_ticks(6)
	_hud.tick()
	var text: String = _hud.get_context_text()
	assert_eq_string(
		text, _active_text(MatchRules.RunnerAbility.ACTIVE_CAMO), "the panel names camo while camo runs"
	)
	assert_false(
		text.contains(_title(MatchRules.RunnerAbility.BUBBLE_SHIELD)),
		"and not the shield that was picked -- got \"%s\"" % text,
	)


func test_the_cooldown_keeps_the_name_of_the_power_that_ran() -> void:
	_rules.ability_cooldown_seconds = 5.0
	# A lock with the key up ends on its next tick: a power that has just ended.
	assert_true(_power.activate(MatchRules.RunnerAbility.ARMOR_LOCK), "the armor lock starts")
	_hud.tick()
	await step_ticks(3)
	assert_false(_power.is_active(), "the lock has ended")
	assert_gt(_power.get_cooldown_remaining(), 4.0, "and its cooldown is running")
	_hud.tick()
	var text: String = _hud.get_context_text()
	assert_true(
		text.contains(_title(MatchRules.RunnerAbility.ARMOR_LOCK)),
		"the cooldown is shown under the armor lock's name -- got \"%s\"" % text,
	)
	assert_eq_string(
		text,
		tr("HUD_ABILITY_COOLDOWN").format({
			"title": _title(MatchRules.RunnerAbility.ARMOR_LOCK),
			"seconds": "%.0f" % _power.get_cooldown_remaining(),
		}),
		"as the seconds until it is ready",
	)
	assert_almost_eq(
		_hud.power_fill.anchor_right, 1.0 - _power.get_cooldown_remaining() / 5.0, 0.001,
		"and the bar is the share of the wait served",
	)


func test_a_cooked_cat_shows_its_fuse_and_fills_by_the_fuse() -> void:
	assert_true(_power.activate(MatchRules.RunnerAbility.CAT_GRENADE), "the cat is in hand")
	_input.command.cook_pressed = true
	await step_ticks(2)
	_input.command.cook_pressed = false
	await step_ticks(30)
	var left: float = _power.get_remaining()
	assert_between(left, 0.5, CatGrenade.FUSE_SECONDS - 0.3, "the fuse is running: %.2f s" % left)
	_hud.tick()
	assert_eq_string(
		_hud.get_context_text(), _active_text(MatchRules.RunnerAbility.CAT_GRENADE),
		"the panel names the cat and the seconds on its fuse",
	)
	assert_almost_eq(
		float(_hud.call(&"_ability_fill")), left / CatGrenade.FUSE_SECONDS, 0.001,
		"the fill is the share of the 2.5 s fuse left, not of the power duration",
	)
	assert_almost_eq(
		_hud.power_fill.anchor_right, left / CatGrenade.FUSE_SECONDS, 0.001,
		"and the bar on screen is drawn to it",
	)
	# Put the cat away unexploded: its blast is the hub file's business.
	_power.cancel()
	await step_ticks(2)


func test_nothing_picked_running_or_cooling_shows_no_panel() -> void:
	assert_false(_power.is_active(), "nothing runs")
	assert_almost_eq(_power.get_cooldown_remaining(), 0.0, 0.001, "nothing cools")
	_hud.tick()
	assert_false(_hud.power_panel.visible, "the power panel is hidden")
	assert_eq_string(_hud.get_context_text(), "", "and reads nothing")


func test_a_presented_power_is_shown_as_a_client_sees_it() -> void:
	# What a snapshot does to a client's body: the power is drawn, never run, on this machine.
	_power.present(MatchRules.RunnerAbility.ACTIVE_CAMO, 3.0, 0.0)
	_hud.tick()
	assert_true(_hud.power_panel.visible, "the panel is up for a power the host says is running")
	assert_eq_string(
		_hud.get_context_text(),
		tr("HUD_ABILITY_ACTIVE").format({
			"title": _title(MatchRules.RunnerAbility.ACTIVE_CAMO), "seconds": "3.0",
		}),
		"it names camo with the 3.0 s the host reported",
	)
	_power.present(MatchRules.RunnerAbility.NONE, 0.0, 4.0)
	_hud.tick()
	assert_eq_string(
		_hud.get_context_text(),
		tr("HUD_ABILITY_COOLDOWN").format({
			"title": _title(MatchRules.RunnerAbility.ACTIVE_CAMO), "seconds": "4",
		}),
		"then camo's cooldown, as the host reported it",
	)
	_power.present(MatchRules.RunnerAbility.NONE, 0.0, 0.0)
	_hud.tick()
	assert_eq_string(_hud.get_context_text(), "", "and nothing once the host says it is ready")


# --- Helpers ------------------------------------------------------------------

func _title(which: MatchRules.RunnerAbility) -> String:
	return MatchRules.runner_ability_title(which).to_upper()


## What the panel reads while [param which] runs, off the power's own clock.
func _active_text(which: MatchRules.RunnerAbility) -> String:
	return tr("HUD_ABILITY_ACTIVE").format({
		"title": _title(which), "seconds": "%.1f" % _power.get_remaining(),
	})
