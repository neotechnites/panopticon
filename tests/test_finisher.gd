extends TestCase

## The finale: through the portal the finisher is in the tower and invincible,
## one shove at three times the force throws the guard out of the open tower,
## every view follows him for the beat, and the next round starts.

## Ticks to let the round the race arms settle before it is measured.
const SETTLE_TICKS: int = 60
const MAPS: Array[String] = [
	"res://maps/bentham_ring/bentham_ring.tscn",
	"res://maps/forest/forest.tscn",
	"res://maps/marble/marble.tscn",
	"res://maps/ice/ice.tscn",
]

var _match: Node3D
var _controller: MatchController
var _rules: MatchRules
var _participants: Array[MatchParticipant] = []

var _resolutions: int = 0
var _last_outcome: int = -1
var _beats: int = 0
var _beat_throw: Vector3 = Vector3.ZERO


func before_each() -> void:
	_match = TestFixtures.make_match()
	_controller = _match.get_node("MatchController") as MatchController
	_rules = TestFixtures.match_rules()
	_rules.finisher_hunts_guard = true
	_controller.rules = _rules
	add_child(_match)
	_controller.round_resolved.connect(_on_round_resolved)
	_controller.kill_beat_started.connect(_on_kill_beat)
	_participants = _controller.get_participants()


## The race won, then one prisoner through the portal. Returns [guard, finisher].
func _to_the_finale() -> Array[MatchParticipant]:
	var guard: MatchParticipant = _participants[0]
	guard.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	var finisher: MatchParticipant = _controller.get_live_participants()[0]
	TestFixtures.pin_the_field(_controller, finisher)
	finisher.tracker.lap_finished.emit(12.0, 96.0)
	finisher.shove_cooldown_remaining = 0.0
	return [guard, finisher]


func test_the_finisher_is_in_the_tower_and_invincible() -> void:
	var pair: Array[MatchParticipant] = await _to_the_finale()
	var guard: MatchParticipant = pair[0]
	var finisher: MatchParticipant = pair[1]
	assert_eq_int(_resolutions, 0, "reaching the end resolves nothing")
	assert_same(_controller.get_seat_participant(), guard, "the guard keeps the tower")
	assert_true(finisher.is_finisher, "the finisher is in the finale")
	assert_false(finisher.body.is_armed, "with no rifle: the finale is a shove")
	var spawn: Marker3D = _controller.arena.get_node(_controller.spawn_marker_path) as Marker3D
	assert_lt(finisher.body.global_position.distance_to(spawn.global_position), 4.0, "put by the guard's spawn")

	for shot: int in 20:
		assert_false(_controller.apply_hit(finisher), "shot %d does nothing to the finisher" % shot)
	assert_true(finisher.is_running, "the guard's rifle cannot take them out")
	assert_true(_controller.handle_fall(finisher), "a fall is ruled on")
	assert_true(finisher.is_running and finisher.is_finisher, "and survived: back in the tower")
	assert_lt(finisher.body.global_position.distance_to(spawn.global_position), 4.0, "standing by the spawn again")
	assert_eq_int(_resolutions, 0, "nothing resolved")


func test_one_finale_shove_throws_the_guard_out_and_the_round_turns_over() -> void:
	var pair: Array[MatchParticipant] = await _to_the_finale()
	var guard: MatchParticipant = pair[0]
	var finisher: MatchParticipant = pair[1]
	var rounds_before: int = _controller.get_round_number()
	var tower: Node = _controller.arena.get_node(_controller.spawn_marker_path).get_parent()
	var walls: Array[Node] = tower.find_children("*", "StaticBody3D", true, false)
	var layers: Array[int] = []
	for wall: Node in walls:
		layers.append((wall as StaticBody3D).collision_layer)
	assert_false(_controller.is_tower_open(), "the tower is closed before the shove")

	assert_same(_controller.apply_shove(finisher), guard, "the finisher's one shove lands on the guard")
	assert_eq_int(guard.health, 0, "and kills him")
	assert_eq_int(_beats, 1, "the throw is announced once")
	var forward: Vector3 = -finisher.body.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var ordinary: Vector3 = forward * _rules.shove_impulse + Vector3.UP * _rules.shove_up_impulse
	assert_vec3_almost_eq(_beat_throw, ordinary * 1.5, 0.01, "thrown at one and a half times an ordinary shove")
	assert_true(_controller.is_tower_open(), "the tower's collision is off on the shove")
	for wall: Node in walls:
		assert_eq_int((wall as StaticBody3D).collision_layer, MatchController.OPEN_TOWER_LAYER, "%s is off" % wall.name)
	assert_true(finisher.body.movement_locked, "the finisher is held; they cannot fall out")
	assert_null(_controller.apply_shove(finisher), "a second shove does nothing")

	await step_seconds(_rules.kill_beat_seconds * 0.5)
	assert_eq_int(_resolutions, 0, "the round waits through the tracking shot")
	assert_eq_int(_controller.get_round_number(), rounds_before, "no new round yet")
	await step_seconds(_rules.kill_beat_seconds * 0.5 + 0.2)

	assert_eq_int(_resolutions, 1, "resolved exactly once")
	assert_eq_int(_last_outcome, int(MatchController.Outcome.LOSS), "lost from the tower")
	assert_eq_int(_controller.get_round_number(), rounds_before + 1, "the next round starts")
	assert_same(_controller.get_seat_participant(), finisher, "the finisher takes the tower")
	assert_false(_controller.is_tower_open(), "the tower is closed again")
	for i: int in walls.size():
		assert_eq_int((walls[i] as StaticBody3D).collision_layer, layers[i], "%s is back as it was" % walls[i].name)


func test_the_tracking_shot_holds_the_view_for_the_beat() -> void:
	assert_almost_eq(MatchRules.new().kill_beat_seconds, 2.0, 1e-6, "two seconds by default")
	var view: FinaleView = _match.get_node("FinaleView") as FinaleView
	var pair: Array[MatchParticipant] = await _to_the_finale()
	_controller.apply_shove(pair[1])
	assert_true(view.is_active(), "the tracking shot takes the view")
	assert_true(view.camera.current, "on its own camera")
	var spawn: Node3D = _controller.arena.get_node(_controller.spawn_marker_path) as Node3D
	var off_axis: Vector3 = view.camera.global_position - spawn.global_position
	assert_gt(Vector2(off_axis.x, off_axis.z).length(), 7.0, "cut to a camera outside the tower")
	assert_false(view._in_room(view.camera.global_position), "not inside the tower's room")
	assert_gt(view.get_predicted_arc().size(), 2, "set against the arc he is thrown along")
	await step_seconds(_rules.kill_beat_seconds + 0.2)
	assert_false(view.is_active(), "and gives it back when the next round starts")
	assert_false(view.camera.current, "its camera stood down")


func test_an_ordinary_shove_is_not_scaled() -> void:
	var guard: MatchParticipant = _participants[0]
	guard.tracker.lap_finished.emit(30.0, 240.0)
	await step_ticks(SETTLE_TICKS)
	var runners: Array[MatchParticipant] = _controller.get_live_participants()
	TestFixtures.pin_the_field(_controller, null)
	var shover: MatchParticipant = runners[0]
	var victim: MatchParticipant = runners[1]
	shover.shove_cooldown_remaining = 0.0
	var forward: Vector3 = -shover.body.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	victim.body.global_position = shover.body.global_position + forward * 0.3
	assert_same(_controller.apply_shove(shover), victim, "a prisoner shoves a prisoner")
	assert_vec3_almost_eq(
		victim.body._pending_launch,
		forward * _rules.shove_impulse + Vector3.UP * _rules.shove_up_impulse,
		0.01, "at the ordinary force",
	)
	assert_eq_int(_beats, 0, "no finale")
	assert_false(_controller.is_tower_open(), "and the tower stays shut")


func test_a_bot_finisher_shoves_the_guard_out_by_itself() -> void:
	var pair: Array[MatchParticipant] = await _to_the_finale()
	if not assert_false(pair[1].is_human(), "the finisher is a bot"):
		return
	await step_seconds(_rules.shove_cooldown_seconds + 1.0)
	assert_eq_int(_beats, 1, "the bot closed on the guard and shoved")


func test_every_map_tower_carries_a_collider_to_switch_off() -> void:
	for path: String in MAPS:
		var map: Node = (load(path) as PackedScene).instantiate()
		var spawn: Node = map.get_node_or_null(^"Tower/TowerSpawn")
		if assert_not_null(spawn, "%s has a TowerSpawn" % path):
			var solid: int = 0
			for body: Node in spawn.get_parent().find_children("*", "StaticBody3D", true, false):
				if (body as StaticBody3D).collision_layer != 0:
					solid += 1
			assert_gt(solid, 0, "%s: the tower has collision to open" % path)
		map.free()


func _on_round_resolved(outcome: int) -> void:
	_resolutions += 1
	_last_outcome = outcome


func _on_kill_beat(_guard: MatchParticipant, _seconds: float, throw: Vector3) -> void:
	_beats += 1
	_beat_throw = throw
