extends TestCase

## The runner powers under [member MatchRules.runner_ability], on the shipped
## match scene with an AI in the tower and the human running.

const SETTLE_TICKS: int = 30
const DURATION_SECONDS: float = 2.0
const COOLDOWN_SECONDS: float = 3.0
const RAY_STANDOFF_METRES: float = 6.0
const CHEST_HEIGHT: float = 1.2

var _match: Node3D
var _controller: MatchController
var _rifle: Rifle
var _hud: MatchHud
var _rules: MatchRules
var _human: MatchParticipant
var _body: PlayerController
var _input: BotIntentSource
var _ability: RunnerPower


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_rules.runner_ability = MatchRules.RunnerAbility.NONE
	_rules.ability_duration_seconds = DURATION_SECONDS
	_rules.ability_cooldown_seconds = COOLDOWN_SECONDS
	_controller.rules = _rules
	add_child(_match)

	_rifle = _controller.rifle
	_hud = _match.get_node("HUD/Root") as MatchHud
	var participants: Array[MatchParticipant] = _controller.get_participants()
	_human = participants[0]
	_body = _human.body
	_input = BotIntentSource.new()
	_input.name = "TestInput"
	_body.add_child(_input)
	_body.intent_source = _input
	_ability = RunnerPower.of(_body)

	# An AI takes the tower through the scoring seam; the human runs the round.
	participants[1].tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	assert_true(_human.is_running, "the human runs the round")
	assert_not_null(_ability, "the body carries an ability node")


func test_no_power_by_default() -> void:
	assert_eq_int(int(MatchRules.new().runner_ability), int(MatchRules.RunnerAbility.NONE), "off by default")
	await _press()
	assert_false(_ability.is_active(), "nothing happens with no power selected")
	assert_null(_ability.get_shield(), "no shield")
	assert_null(_ability.get_decoy(), "no decoy")


func test_bubble_shield_stops_the_rifle_ray_then_pops() -> void:
	_rules.runner_ability = MatchRules.RunnerAbility.BUBBLE_SHIELD
	await _press()
	var shield: StaticBody3D = _ability.get_shield()
	assert_true(_ability.is_active(), "the shield is up")
	assert_not_null(shield, "a shield body exists")
	if shield == null:
		return
	await step_ticks(2)
	assert_almost_eq(
		shield.global_position.distance_to(_body.global_position + Vector3.UP * 0.9), 0.0, 0.05,
		"the shield is centred on the body",
	)
	assert_same(_cast_at_body().get("collider", null), shield, "the rifle ray stops on the shield")
	assert_null(_controller.resolve_participant(shield), "the shield is nobody")

	await step_seconds(DURATION_SECONDS + 0.5)
	assert_false(_ability.is_active(), "the shield popped")
	assert_null(_ability.get_shield(), "no shield remains")
	assert_false(is_instance_valid(shield), "the shield body is gone")
	assert_same(_cast_at_body().get("collider", null), _body, "the same ray now reaches the body")


func test_hologram_runs_ahead_and_shatters_without_converting() -> void:
	_rules.runner_ability = MatchRules.RunnerAbility.HOLOGRAM
	var lives: int = _human.lives
	var remaining: int = _controller.get_runners_remaining()
	await _press()
	var decoy: PlayerController = _ability.get_decoy()
	assert_not_null(decoy, "a decoy was spawned")
	if decoy == null:
		return
	assert_true(decoy.is_in_group(MatchController.RUNNER_GROUP), "the decoy is a guard candidate")
	assert_null(_controller.resolve_participant(decoy), "the decoy is no participant")
	assert_null(decoy.get_node_or_null(^"Brain"), "the decoy has no brain")
	var start: Vector3 = decoy.global_position
	await step_ticks(30)
	assert_gt(decoy.global_position.distance_to(start), 1.0, "the decoy runs")

	_rifle.target_hit.emit(decoy, decoy.global_position, Vector3.UP)
	assert_true(decoy.is_queued_for_deletion(), "a hit shatters the decoy")
	assert_true(_human.is_running, "the owner still runs")
	assert_eq_int(_human.lives, lives, "the owner lost no life")
	assert_eq_int(_controller.get_runners_remaining(), remaining, "nobody was converted")
	await step_ticks(2)
	assert_null(_ability.get_decoy(), "the ability forgot the shattered decoy")


func test_armor_lock_freezes_the_body_and_ignores_hits_until_released() -> void:
	_rules.runner_ability = MatchRules.RunnerAbility.ARMOR_LOCK
	_input.command.move_direction = Vector2(0.0, 1.0)
	await step_ticks(10)
	assert_gt(_body.velocity.length(), 0.5, "the body runs before the lock")

	await _press()
	assert_true(_ability.is_active(), "the lock is on")
	assert_true(_body.movement_locked, "the body is locked")
	var held: Vector3 = _body.global_position
	await step_ticks(10)
	assert_almost_eq(_body.velocity.length(), 0.0, 1e-6, "no velocity under lock")
	assert_almost_eq(_body.global_position.distance_to(held), 0.0, 1e-3, "no movement under lock")
	assert_false(_controller.apply_hit(_human), "a hit is ignored")
	assert_true(_human.is_running, "the owner still runs")
	assert_true(_ability.is_hit_immune(), "the lock reports immunity")
	assert_not_null(_body.get_node_or_null(^"ArmorShell"), "the shell shows")
	_hud.tick()
	assert_true(_hud.get_context_text().begins_with("ARMOR LOCK"), "the HUD names the power")

	_input.command.ability_held = false
	await step_ticks(2)
	assert_false(_ability.is_active(), "release ends the lock early")
	assert_false(_body.movement_locked, "the body is free")
	assert_gt(_ability.get_cooldown_remaining(), 0.0, "the cooldown started")
	await step_ticks(10)
	assert_gt(_body.velocity.length(), 0.5, "the body runs again")


func test_active_camo_thins_the_body_then_restores_it_and_cools_down() -> void:
	_rules.runner_ability = MatchRules.RunnerAbility.ACTIVE_CAMO
	var mesh: MeshInstance3D = (_body.get_node(^"Avatar") as PrisonerAvatar).mesh
	var saved: Material = mesh.material_override
	await _press()
	assert_true(_ability.is_camouflaged(), "camo is on")
	var camo: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	assert_not_null(camo, "the body wears a camo material")
	if camo != null:
		assert_almost_eq(camo.albedo_color.a, RunnerPower.CAMO_ALPHA, 1e-6, "at 25% opacity")
		assert_eq_int(int(camo.transparency), int(BaseMaterial3D.TRANSPARENCY_ALPHA), "with alpha on")
		assert_true(camo.emission_enabled, "and a faint glow")

	await step_seconds(DURATION_SECONDS + 0.5)
	assert_false(_ability.is_active(), "camo expired")
	assert_true(mesh.material_override == saved, "the body's material came back")

	await _press()
	assert_false(_ability.is_active(), "a second use waits for the cooldown")
	await step_seconds(COOLDOWN_SECONDS)
	await _press()
	assert_true(_ability.is_active(), "and works once it has run out")


func test_the_codec_carries_the_ability_bits() -> void:
	var intent: MoveIntent = MoveIntent.new()
	intent.ability_pressed = true
	intent.ability_held = true
	var out: MoveIntent = MoveIntent.new()
	assert_eq_int(NetCodec.unpack_intent(NetCodec.pack_intent(7, intent), out), 7, "the intent unpacks")
	assert_true(out.ability_pressed and out.ability_held, "both bits survive the wire")
	out.clear()
	assert_false(out.ability_pressed or out.ability_held, "clear zeroes them")


## Press the ability key for one tick and hold it.
func _press() -> void:
	_input.command.ability_pressed = true
	_input.command.ability_held = true
	await step_ticks(2)
	_input.command.ability_pressed = false


## The rifle's own ray, from 6 m ahead of the body to its chest.
func _cast_at_body() -> Dictionary:
	var forward: Vector3 = -_body.global_transform.basis.z
	var from: Vector3 = _body.global_position + forward * RAY_STANDOFF_METRES + Vector3.UP * CHEST_HEIGHT
	var to: Vector3 = _body.global_position + Vector3.UP * CHEST_HEIGHT
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _rifle.profile.hit_mask
	query.collide_with_bodies = true
	return _body.get_world_3d().direct_space_state.intersect_ray(query)
