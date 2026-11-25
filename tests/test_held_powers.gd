extends TestCase

## Each power owns its run and its cooldown ([PowerDef]); a player holds one or none, picked at a hub
## stand, and keeps it into the next match. Offline, on the shipped scenes.

const NONE: int = MatchRules.RunnerAbility.NONE
const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD
const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
const ARMOR: int = MatchRules.RunnerAbility.ARMOR_LOCK
const CAMO: int = MatchRules.RunnerAbility.ACTIVE_CAMO
const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE
const HUB_SCENE_PATH: String = "res://hub/hub.tscn"


## The shipped match scene, without its music: a player still streaming at exit is a leaked resource.
func _match_scene() -> Node3D:
	var scene: Node3D = TestFixtures.make_match()
	scene.get_node("Music").free()
	return scene


## The shipped match with the player running a round and an idle AI in the tower; the player's body.
func _running_body(rules: MatchRules) -> PlayerController:
	var scene: Node3D = _match_scene()
	var controller: MatchController = scene.get_node("MatchController") as MatchController
	controller.rules = rules
	add_child(scene)
	var participants: Array[MatchParticipant] = controller.get_participants()
	for participant: MatchParticipant in participants:
		var bot: BotIntentSource = participant.body.intent_source as BotIntentSource
		if bot != null:
			bot.shove_enabled = false
	participants[1].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(30)
	if participants[1].tower_brain != null:
		participants[1].tower_brain.set_physics_process(false)
	var body: PlayerController = participants[0].body
	var keys: BotIntentSource = BotIntentSource.new()
	keys.name = "TestInput"
	keys.shove_enabled = false
	body.add_child(keys)
	body.intent_source = keys
	return body


func test_each_power_ships_its_own_run_and_cooldown() -> void:
	var want: Dictionary = {SHIELD: [8.0, 20.0], HOLOGRAM: [6.0, 10.0], ARMOR: [3.0, 12.0], CAMO: [6.0, 15.0], CAT: [2.5, 15.0]}
	for which: int in want:
		assert_almost_eq(RunnerPower.def(which).duration_seconds, want[which][0], 1e-4, "power %d runs its own time" % which)
		assert_almost_eq(RunnerPower.def(which).cooldown_seconds, want[which][1], 1e-4, "power %d cools its own time" % which)
	assert_true(RunnerPower.def(ARMOR).ends_on_release, "letting go ends the armor lock early")


func test_a_power_runs_its_own_time_then_cools_its_own_time_scaled_by_the_lever() -> void:
	var rules: MatchRules = TestFixtures.match_rules()
	rules.ability_cooldown_multiplier = 0.5
	var power: RunnerPower = RunnerPower.of(await _running_body(rules))
	for which: int in [SHIELD, HOLOGRAM, CAMO]:
		power.cancel()
		power.state.cooldown_ticks = 0
		assert_true(TestFixtures.fire(power, which), "power %d starts" % which)
		assert_eq_int(power.state.remaining_ticks, RunnerPower.ticks_of(RunnerPower.duration_of(which)), "power %d runs its own length" % which)
		assert_almost_eq(power.get_active_fraction(), 1.0, 1e-4, "the readout starts whole")
		assert_eq_int(power.state.cooldown_ticks, 0, "no cooldown while it runs")
		power.state.remaining_ticks = 1
		await step_ticks(3)
		assert_false(power.is_active(), "power %d ran out" % which)
		var cooling: int = RunnerPower.ticks_of(RunnerPower.def(which).cooldown_seconds * 0.5)
		assert_between(float(power.state.cooldown_ticks), float(cooling - 3), float(cooling), "power %d cools its own time, halved" % which)
		assert_between(power.get_cooldown_fraction(), 0.9, 1.0, "the readout's wait starts whole")
		assert_eq_string(String(power.refusal()), "cooldown", "and refuses a press until it has cooled")


func test_the_armor_lock_lets_go_by_itself_at_its_most() -> void:
	var body: PlayerController = await _running_body(TestFixtures.match_rules())
	var keys: BotIntentSource = body.intent_source as BotIntentSource
	RunnerPower.of(body).held = ARMOR
	keys.command.ability_held = true
	await step_ticks(2)
	assert_true(RunnerPower.of(body).is_active(), "the lock is on while the key is down")
	await step_seconds(RunnerPower.duration_of(ARMOR) + 0.3)
	assert_false(RunnerPower.of(body).is_active(), "and over at its most, the key still down")


func test_bots_in_a_match_hold_a_power_and_the_player_holds_their_pick() -> void:
	RunnerPower.solo_held = HOLOGRAM
	var scene: Node3D = _match_scene()
	var controller: MatchController = scene.get_node("MatchController") as MatchController
	controller.rules = TestFixtures.match_rules()
	add_child(scene)
	await step_ticks(5)
	for participant: MatchParticipant in controller.get_participants():
		var held: int = int(RunnerPower.of(participant.body).get_held())
		if participant.is_human():
			assert_eq_int(held, HOLOGRAM, "the player holds the power picked in the hub")
		else:
			assert_true(held != NONE, "bot %d holds a power" % participant.index)


func test_a_hub_stand_gives_its_power_and_the_next_match_keeps_it() -> void:
	var hub: Node3D = (load(HUB_SCENE_PATH) as PackedScene).instantiate() as Node3D
	TestFixtures.silence_human_input(hub)
	(hub.get_node("HubLobby") as HubLobby).changes_scene = false
	add_child(hub)
	var controller: MatchController = hub.get_node("MatchController") as MatchController
	if not assert_true(await NetFixtures.poll_until(self, func() -> bool:
			return controller.get_human_participant() != null and not controller.get_human_participant().body.held), "the hub stands its player"):
		return
	var me: MatchParticipant = controller.get_human_participant()
	var stands: Array[Node] = hub.get_node("HubWorld/PowerStands").get_children()
	assert_eq_int(stands.size(), MatchRules.RunnerAbility.size(), "a stand per power and one for none")
	var keys: BotIntentSource = BotIntentSource.new()
	keys.shove_enabled = false
	me.body.add_child(keys)
	me.body.intent_source = keys
	for which: int in [CAMO, NONE, CAT]:
		var stand: PowerStand = null
		for node: Node in stands:
			if int((node as PowerStand).power) == which:
				stand = node as PowerStand
		var out: Vector3 = Vector3(stand.global_position.x, 0.0, stand.global_position.z).normalized()
		me.body.global_position = stand.global_position + out
		me.body.velocity = Vector3.ZERO
		await step_ticks(2)
		keys.command.cook_pressed = true
		await step_ticks(1)
		keys.command.cook_pressed = false
		await step_ticks(1)
		assert_eq_int(int(RunnerPower.of(me.body).get_held()), which, "the stand for %d gives it" % which)
		assert_eq_int(int(RunnerPower.solo_held), which, "and the player keeps it past this scene")
	hub.queue_free()
	await step_ticks(2)
	var scene: Node3D = _match_scene()
	add_child(scene)
	await step_ticks(5)
	var next: MatchController = scene.get_node("MatchController") as MatchController
	assert_eq_int(int(RunnerPower.of(next.get_human_participant().body).get_held()), CAT, "the next match's player holds the cat")
