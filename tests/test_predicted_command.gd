extends TestCase

## A client's own command, run as its prediction and as its replay (DESIGN 3.3, C12): the same
## [method PlayerController.run_command] the authority runs, but with no authority it resolves no
## hit, spawns nothing and changes no participant; its trigger moves the gate and draws the shot
## once (DESIGN 7). The replay, under the signal block reconciliation uses, draws nothing again.

const SETTLE_TICKS: int = 60
const REACH_METRES: float = 1.2

var _match: Node3D
var _controller: MatchController
var _resolved: Array[String] = []


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_controller.rules = TestFixtures.match_rules()
	add_child(_match)
	_controller.participant_shoved.connect(func(_a: MatchParticipant, _b: MatchParticipant) -> void: _resolved.append("shove"))
	_controller.rifle.fired.connect(func(_from: Vector3, _to: Vector3) -> void: _resolved.append("shot"))
	_controller.get_participants()[0].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	for participant: MatchParticipant in _controller.get_participants():
		if participant.brain != null:
			participant.brain.set_physics_process(false)
		var input: BotIntentSource = participant.body.intent_source as BotIntentSource
		if input != null:
			input.shove_enabled = false
			input.command.clear()
		participant.body.velocity = Vector3.ZERO
		participant.body.shove_cooldown_remaining = 0.0
	_resolved.clear()


func test_a_predicted_command_changes_no_participant_and_spawns_nothing() -> void:
	var live: Array[MatchParticipant] = _controller.get_live_participants()
	var presser: MatchParticipant = live[0]
	var victim: MatchParticipant = live[1]
	var forward: Vector3 = -presser.body.global_transform.basis.z
	forward.y = 0.0
	victim.body.global_position = presser.body.global_position + forward.normalized() * REACH_METRES
	await step_ticks(2)
	var body: PlayerController = presser.body
	body.set_physics_process(false)
	body.net_predicted = true
	var before: Dictionary = _participants()
	var nodes: int = _match.find_children("*", "", true, false).size()
	var thrown: Vector3 = victim.body.velocity
	var swings: Array[int] = [0]
	body.shoved.connect(func() -> void: swings[0] += 1)

	var command: MoveIntent = MoveIntent.new()
	command.buttons = MoveIntent.SHOVE | MoveIntent.FIRE | MoveIntent.COOK | MoveIntent.POWER
	command.derive_edges(0)
	body.run_command(command, SIM_DELTA)
	assert_eq_int(swings[0], 1, "the presser's own swing is drawn on the press, as the client predicts it")
	assert_almost_eq(
		body.shove_cooldown_remaining, _controller.get_rules().shove_cooldown_seconds, 1e-4,
		"and its cooldown is spent, which the replay must carry forward",
	)
	_assert_nothing_authoritative(before, nodes, victim, thrown, "the predicted command")

	# The replay of the same command, as reconciliation runs it: the gate's state restored first.
	body.shove_cooldown_remaining = 0.0
	body.set_block_signals(true)
	body.simulate_tick(command, SIM_DELTA)
	body.set_block_signals(false)
	assert_eq_int(swings[0], 1, "the replay draws no second swing")
	assert_gt(body.shove_cooldown_remaining, 0.0, "but its gate runs, so the replayed cooldown is the one predicted")
	_assert_nothing_authoritative(before, nodes, victim, thrown, "the replayed command")
	body.net_predicted = false


func test_a_predicted_trigger_pull_draws_its_shot_once_and_resolves_nothing() -> void:
	var guard: MatchParticipant = _controller.get_seat_participant()
	if not assert_not_null(guard, "a guard holds the tower"):
		return
	var rifle: Rifle = _controller.rifle
	var outcomes: Array[String] = []
	rifle.target_hit.connect(func(_c: Node3D, _p: Vector3, _n: Vector3) -> void: outcomes.append("hit"))
	rifle.missed.connect(func(_p: Vector3) -> void: outcomes.append("miss"))
	rifle.projectile_launched.connect(func(_o: Vector3, _d: Vector3, _s: float) -> void: outcomes.append("round"))
	var body: PlayerController = guard.body
	body.set_physics_process(false)
	body.net_predicted = true
	var before: Dictionary = _participants()
	var command: MoveIntent = MoveIntent.new()
	command.buttons = MoveIntent.FIRE
	command.derive_edges(0)
	assert_true(rifle.can_fire(), "the rifle was ready to fire")
	var gate: PackedFloat32Array = PackedFloat32Array()
	gate.resize(Rifle.GATE_STATE_SIZE)
	rifle.capture_gate(gate)
	body.run_command(command, SIM_DELTA)
	assert_eq_int(_resolved.count("shot"), 1, "the presser's own shot is drawn on the press")
	assert_true(rifle.get_state() == Rifle.State.FIRING, "and its gate fires, which the replay must carry forward")
	assert_eq_string(", ".join(outcomes), "", "a predicting machine resolves no hit, miss or round: those are the host's")
	assert_eq_int(rifle.get_projectiles_in_flight(), 0, "nothing is in the air")
	assert_true(_participants() == before, "and no participant changed")
	# The replay of the same command, as reconciliation runs it: the gate's state restored first.
	rifle.restore_gate(gate)
	body.simulate_tick(command, SIM_DELTA)
	assert_eq_int(_resolved.count("shot"), 1, "the replay draws no second shot")
	assert_true(rifle.get_state() == Rifle.State.FIRING, "but its gate runs as predicted")
	body.net_predicted = false


func _assert_nothing_authoritative(
	before: Dictionary, nodes: int, victim: MatchParticipant, thrown: Vector3, what: String
) -> void:
	assert_eq_string(", ".join(_resolved), "", "%s resolved nothing" % what)
	assert_true(_participants() == before, "%s changed no participant" % what)
	assert_eq_int(_match.find_children("*", "", true, false).size(), nodes, "%s spawned nothing" % what)
	assert_vec3_almost_eq(victim.body.velocity, thrown, 1e-4, "%s launched nobody" % what)


## Every participant's plain fields, by index.
func _participants() -> Dictionary:
	var all: Dictionary = {}
	for participant: MatchParticipant in _controller.get_participants():
		var fields: Dictionary = {}
		for property: Dictionary in participant.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
				continue
			var value: Variant = participant.get(property["name"])
			if not (value is Object):
				fields[property["name"]] = value
		all[participant.index] = fields
	return all
