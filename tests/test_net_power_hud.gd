extends TestCase

## The power wheel, bottom-right of a prisoner's HUD, on the shipped match scene: full when the held
## power is ready, draining over its run, filling back over its cooldown, hidden with nothing held.

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
	TestFixtures.set_power_duration(DURATION_SECONDS)
	TestFixtures.set_power_cooldown(0.0)
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


func test_the_wheel_drains_over_the_run() -> void:
	_input.command.ability_held = true
	assert_true(TestFixtures.fire(_power, MatchRules.RunnerAbility.ARMOR_LOCK), "the armor lock starts")
	await step_ticks(6)
	_hud.tick()
	assert_true(_hud.power_wheel.visible, "the wheel is up for the held power")
	assert_between(_power.get_remaining(), 0.1, DURATION_SECONDS - 0.01, "the run is counting down")
	assert_almost_eq(_hud.power_wheel.get_fraction(), _power.get_remaining() / DURATION_SECONDS, 0.001,
			"and the wheel is the share of the run left")
	assert_lt(_hud.power_wheel.get_fraction(), 1.0, "so it has drained from full")


func test_the_wheel_fills_back_over_the_cooldown() -> void:
	TestFixtures.set_power_cooldown(5.0)
	# A lock with the key up ends on its next tick: a power that has just ended.
	assert_true(TestFixtures.fire(_power, MatchRules.RunnerAbility.ARMOR_LOCK), "the armor lock starts")
	await step_ticks(3)
	assert_false(_power.is_active(), "the lock has ended")
	_hud.tick()
	var early: float = _hud.power_wheel.get_fraction()
	assert_almost_eq(early, 1.0 - _power.get_cooldown_remaining() / 5.0, 0.01, "the wheel is the share of the wait served")
	assert_lt(early, 0.1, "nearly empty as the cooldown starts")
	await step_seconds(2.0)
	_hud.tick()
	assert_gt(_hud.power_wheel.get_fraction(), early + 0.3, "and fills as it runs")


func test_a_cooked_cat_drains_the_wheel_by_its_fuse() -> void:
	assert_true(TestFixtures.fire(_power, MatchRules.RunnerAbility.CAT_GRENADE), "the cat is in hand")
	_hud.tick()
	assert_almost_eq(_hud.power_wheel.get_fraction(), 1.0, 0.001, "an unlit cat keeps the wheel whole")
	_input.command.cook_pressed = true
	await step_ticks(2)
	_input.command.cook_pressed = false
	await step_ticks(30)
	var fuse: float = RunnerPower.duration_of(MatchRules.RunnerAbility.CAT_GRENADE)
	_hud.tick()
	assert_almost_eq(_hud.power_wheel.get_fraction(), _power.get_remaining() / fuse, 0.02, "the wheel drains by the fuse")
	# Put the cat away unexploded: its blast is the hub file's business.
	_power.cancel()
	await step_ticks(2)


func test_nothing_held_shows_no_wheel() -> void:
	_hud.tick()
	assert_false(_hud.power_wheel.visible, "the wheel is hidden with nothing held")
	_power.held = MatchRules.RunnerAbility.HOLOGRAM
	_hud.tick()
	assert_true(_hud.power_wheel.visible, "and up once a power is held")
	assert_almost_eq(_hud.power_wheel.get_fraction(), 1.0, 0.001, "full while it is ready")


func test_a_presented_power_is_shown_as_a_client_sees_it() -> void:
	# What a snapshot does to a client's body: the power is drawn, never run, on this machine.
	TestFixtures.set_power_cooldown(8.0)
	_power.held = MatchRules.RunnerAbility.ACTIVE_CAMO
	var run: float = RunnerPower.duration_of(MatchRules.RunnerAbility.ACTIVE_CAMO)
	_present(MatchRules.RunnerAbility.ACTIVE_CAMO, true, run * 0.5, 0.0)
	_hud.tick()
	assert_almost_eq(_hud.power_wheel.get_fraction(), 0.5, 0.02, "half the run the host reported is left")
	var wait: float = RunnerPower.def(MatchRules.RunnerAbility.ACTIVE_CAMO).cooldown_seconds * _rules.ability_cooldown_multiplier
	_present(MatchRules.RunnerAbility.ACTIVE_CAMO, false, 0.0, wait * 0.25)
	_hud.tick()
	assert_almost_eq(_hud.power_wheel.get_fraction(), 0.75, 0.02, "then three quarters of the wait served")
	_present(MatchRules.RunnerAbility.ACTIVE_CAMO, false, 0.0, 0.0)
	_hud.tick()
	assert_almost_eq(_hud.power_wheel.get_fraction(), 1.0, 0.001, "and full once the host says it is ready")


# --- Helpers ------------------------------------------------------------------

## A snapshot's record of [param which] onto the viewed body, as a client takes one.
func _present(which: MatchRules.RunnerAbility, running: bool, remaining: float, cooldown: float) -> void:
	var record: PlayerState = PlayerState.new()
	record.tick = 600
	record.ability = which
	record.power_active = running
	record.ability_end_tick = NetCodec.end_tick(record.tick, remaining)
	record.cooldown_end_tick = NetCodec.end_tick(record.tick, cooldown)
	_power.take_record(record)
