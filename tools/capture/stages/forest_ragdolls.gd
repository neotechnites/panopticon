extends "res://tools/capture/stages/stage.gd"

## forest_ragdolls: short 4 L5, three forest kills read from the ground; a fixed lens on the lane, each man limp and tumbling toward it.
## [code]--map=forest --shot=s3_open_lane --stage=forest_ragdolls --bots=3 --rifle=projectile --seed=20261017[/code]
## Probe (probe_ring --map=forest): deck flat at 23 on 44-60 deg r 50-54; a trunk at 46-48 deg r 48.5-50.5, a rock at
## 54 deg r 52-53.5; --eye=59.5:51:1.5 and the 32 deg window (32:4.4:5.9) both see 44-52 deg at r 51.2-51.8.
## Dials (--set=): pace (0.45), hits (2.4,4.4,6.4: squeeze seconds, one per man), fire_deg (47.5), lens (59.0,51.0,1.5), look (53.2,52.1,0.4), fov (50).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

## Each man's lane radius, in the order they are dropped; lanes clear of the 48 deg trunk.
const LANES: Array = [51.3, 51.8, 51.5]
## Smoke-measured run, deg/s at pace 1 from 0.7 s; a man starts where he reaches fire_deg at his squeeze.
const DEG_PER_S_AT_PACE: float = 11.5
const MOVE_AT: float = 0.7
const LOOK_HEIGHT: float = 0.9

var _bodies: Array[PlayerController] = []
var _hit_at: Dictionary = {}
var _hand: Node = null
var _checks: Dictionary = {}


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0
	rules.bots_shove_rivals = false
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP
	# The third kill is the last runner: a held round keeps total conversion from resetting the deck under his fall.
	rules.shooter_win_condition = MatchRules.ShooterWinCondition.HOLD_DURATION
	rules.hold_duration_seconds = 600.0


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func _hits() -> PackedFloat64Array:
	var out: PackedFloat64Array = []
	for part: String in String(option("hits", "2.4,4.4,6.4")).split(","):
		out.append(float(part))
	return out


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for index: int in 3:
		if runners[index].controller == null:
			return false
	var pace: float = float(option("pace", 0.45))
	var hits: PackedFloat64Array = _hits()
	for index: int in 3:
		var start: float = float(option("fire_deg", 47.5)) - DEG_PER_S_AT_PACE * pace * (hits[index] - MOVE_AT)
		var at := Vector2(start, float(LANES[index]))
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(at.x, at.y, 0.1), "face": LIB.tangent_at(at.x)},
			{"do": "human", "on": true},
			{"do": "lane", "to": 70.0, "r": at.y, "speed": pace, "weave": 0.04, "period": 1.2 + 0.2 * index, "timeout": 30.0},
			{"do": "hold", "seconds": 60.0, "fidget": true},
		], index, "ClipRagdollRunner%d" % index)
		_bodies.append(runners[index].controller)
	victim_body(_bodies[0])
	say("forest_ragdolls: %s, %s, %s; pace %.2f" % [_bodies[0].name, _bodies[1].name, _bodies[2].name, pace])
	return true


func tick(_delta: float) -> void:
	_log_falls()
	if OS.has_environment("STAGE_DEBUG") and not _bodies.is_empty() and Engine.get_physics_frames() % 15 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _bodies.is_empty() or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	var stand: Vector3 = LIB.ring_point(32.0, 4.4, 0.0)
	guard.global_position = Vector3(stand.x, guard.global_position.y, stand.z)
	guard.velocity = Vector3.ZERO
	LIB.open_the_scope(guard, 0.74)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.start_at = 0.8
	var at: float = _hand.start_at
	var hits: PackedFloat64Array = _hits()
	for index: int in mini(hits.size(), _bodies.size()):
		var fire: float = hits[index]
		var watch: float = 0.4
		_hand.beats.append({"body": _bodies[index], "seconds": fire + watch - at, "fire_at": fire - at, "watch": true, "clear": true})
		at = fire + watch
	_hand.park = LIB.ring_point(44.0, 51.0, 1.0)
	say("forest_ragdolls: hand on %s at the 32 deg window" % guard.name)


func _centre(body: PlayerController) -> Vector3:
	var avatar: PrisonerAvatar = PrisonerAvatar.of(body)
	var ragdoll: Object = avatar.get(&"_ragdoll") if avatar != null else null
	if ragdoll != null and bool(ragdoll.call(&"is_active")):
		return ragdoll.call(&"centre")
	return body.global_position + Vector3.UP * LOOK_HEIGHT


func lens(_delta: float) -> bool:
	if _bodies.is_empty() or camera() == null:
		return false
	# Fixed and framed on the whole kill zone: tracking the pelvis bone dived the lens off the lying body.
	camera().global_position = LIB.polar(String(option("lens", "59.0,51.0,1.5")), LIB.ring_point(59.0, 51.0, 1.5))
	camera().look_at(LIB.polar(String(option("look", "53.2,52.1,0.4")), LIB.ring_point(53.2, 52.1, 0.4)), Vector3.UP)
	camera().fov = float(option("fov", 50.0))
	camera().current = true
	return true


func on_hit(collider: Node3D) -> void:
	for body: PlayerController in _bodies:
		if body == collider and not _hit_at.has(body):
			_hit_at[body] = elapsed()
			_checks[body] = 0
			if camera() != null and camera().is_position_in_frustum(body.global_position + Vector3.UP):
				print("[event] %6.2f  in_frame  %s" % [elapsed(), body.name])


## Smoke numbers: the limp body's centre in the lens, its range and a clear ray, every 0.25 s for 1.5 s after the hit.
func _log_falls() -> void:
	var lens_cam: Camera3D = camera()
	if lens_cam == null:
		return
	for body: PlayerController in _hit_at.keys():
		var since: float = elapsed() - float(_hit_at[body])
		var n: int = int(_checks[body])
		if n > 6 or since < 0.25 * n:
			continue
		_checks[body] = n + 1
		var at: Vector3 = _centre(body)
		var ray := PhysicsRayQueryParameters3D.create(lens_cam.global_position, at, 1)
		var blocked: Dictionary = clip.root.get_world_3d().direct_space_state.intersect_ray(ray)
		say("fall %s +%.2f: %s, %.1f m, %s, %.1f deg r %.2f h %.2f" % [body.name, since,
			"in lens" if lens_cam.is_position_in_frustum(at) else "OUT of lens", lens_cam.global_position.distance_to(at),
			"clear" if blocked.is_empty() else "blocked by %s" % String(blocked.collider.name),
			LIB.bearing_of(at), LIB.radius_of(at), at.y - LIB.DECK_Y])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
