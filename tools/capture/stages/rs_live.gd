extends "res://tools/capture/stages/stage.gd"

## rs_live: a normal match, the shipped bot guard (TowerShooter) shooting at bullet speed; nothing staged.
## No hit marker; see on_shot for the scope's hold.
## Dials: speed (195, rules.guard_projectile_speed), hold (1.6), flight (0.45), follow (5: how fast the scope eases after the body), lift (1, the guard_alone grade), clear (0.74), old (0),
## ride (a runner's name: --pov=runner stays on that body), beat (the finale's kill beat, shipped 2.0),
## ahead and sure (the bot's cover look-ahead and sure-shot confidence; shipped 0.35, 0.9),
## spectate (0; 1 with no --pov: a ground camera beside the runner the guard aims at, kept in clear sight of him, held on the body after a hit),
## spec_fov (38), spec_d (14 m), spec_hold (1.8 s),
## tower_fov (0: off; the ridden runner's lens fov inside the tower until he holds it, so the shove shows the guard whole).

var _guard: PlayerController = null
var _held: float = 0.0
var _held_shooter: TowerShooter = null
var _fallen: PlayerController = null
var _base_fov: float = 0.0
var _runners: Array[PlayerController] = []
var _subject: PlayerController = null
var _candidate: PlayerController = null
var _candidate_for: float = 0.0
var _spot: Vector3 = Vector3.ZERO
var _spot_ok: bool = false
var _blind_for: float = 0.0
var _look: Vector3 = Vector3.ZERO
var _hit_hold: float = 0.0


## --bots sets the ring (shorts cap at 4 players with the guard).
func bots() -> int:
	return 0


## Any eyes: the guard's scope for the kills, a runner's (--pov=runner) for a finale played out.
func needs_pov() -> String:
	return ""


func tune_rules(rules: MatchRules) -> void:
	rules.guard_projectile_speed = float(option("speed", 195.0))
	rules.guard_hit_marker = false
	rules.kill_beat_seconds = float(option("beat", rules.kill_beat_seconds))


## The shipped profile unless ahead/sure are set: the base would stand the tower down.
func tune_shooter(profile: ShooterProfile) -> void:
	profile.cover_lookahead_seconds = float(option("ahead", profile.cover_lookahead_seconds))
	profile.sure_shot_confidence = float(option("sure", profile.sure_shot_confidence))


func before_start() -> void:
	if int(option("lift", 1)) == 1:
		var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


## old=1: every runner's death ragdoll off, so a kill plays the pre-ragdoll "Death" clip.
func cast(runners: Array[RunnerBrain]) -> bool:
	var ride: String = String(option("ride", ""))
	for brain: RunnerBrain in runners:
		if brain.controller != null:
			_runners.append(brain.controller)
	for brain: RunnerBrain in runners:
		if brain.controller != null and brain.controller.name == ride:
			stage_body(brain.controller)
			say("rs_live: riding %s" % ride)
	if int(option("old", 0)) == 1:
		for brain: RunnerBrain in runners:
			for avatar: Node in brain.controller.find_children("*", "PrisonerAvatar", true, false):
				avatar.set(&"_ragdoll", null)
		say("rs_live: ragdoll off, the old death clip")
	return true


## Down the guard's eyes the scope stays where it fired until the round lands (the brain would swing onto
## the next runner mid-flight); a kill holds it `hold` s more so the death plays out in frame.
func on_shot(_confidence: float) -> void:
	var shooter: TowerShooter = seat().get_active_shooter() if seat() != null else null
	if shooter != null and clip._pov == "guard":
		shooter.set_physics_process(false)
		_held_shooter = shooter
		_held = float(option("flight", 0.45))


func on_hit(collider: Node3D) -> void:
	if collider is PlayerController and int(option("spectate", 0)) == 1:
		var body: PlayerController = collider as PlayerController
		var chest: Vector3 = body.global_position + Vector3.UP * 1.0
		say("spectate hit %s: subject %s, %.1f m, %s" % [body.name, _subject.name if is_instance_valid(_subject) else "-",
				_spot.distance_to(chest), "clear" if _clear(_spot, chest, body) else "blocked"])
		# The lens stays put through the fall: a re-pick at the hit swung it through the trunks.
		if body == _subject:
			_hit_hold = float(option("spec_hold", 1.8))
	if collider is PlayerController and _held_shooter != null:
		_held = float(option("hold", 1.6))
		_fallen = collider as PlayerController


## Through a kill's hold the scope eases after the body (its ragdoll's pelvis), as a player watches it go down.
func _watch_the_fall(delta: float) -> void:
	var avatar: PrisonerAvatar = PrisonerAvatar.of(_fallen)
	var body: PlayerController = _held_shooter.controller
	if avatar == null or body == null or body.head == null:
		return
	var to: Vector3 = avatar.drawn_centre() - body.head.global_position
	var view: Vector2 = body.get_view_angles()
	var want := Vector2(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	var ease: float = 1.0 - exp(-delta * float(option("follow", 5.0)))
	var turn := Vector2(angle_difference(view.x, want.x), want.y - view.y) * ease
	_held_shooter.input.command.look_delta = Vector2(-turn.x, turn.y if body.profile.invert_look_y else -turn.y)


func tick(delta: float) -> void:
	_widen_in_the_tower()
	if _held > 0.0:
		_held -= delta
		if _fallen != null and is_instance_valid(_fallen) and _held_shooter != null:
			_watch_the_fall(delta)
		# The seat reports no shooter while its brain is off, so the held one is kept here.
		if _held <= 0.0 and _held_shooter != null and is_instance_valid(_held_shooter):
			_held_shooter.input.command.look_delta = Vector2.ZERO
			_held_shooter.set_physics_process(true)
			_held_shooter = null
			_fallen = null
	if OS.has_environment("STAGE_DEBUG") and _guard != null and Engine.get_physics_frames() % 6 == 0:
		var av: PrisonerAvatar = PrisonerAvatar.of(_guard)
		if av != null and av._ragdoll != null and av._ragdoll.is_active():
			var c: Vector3 = av.drawn_centre()
			say("thrown at r %.1f y %.1f" % [Vector2(c.x, c.z).length(), c.y])
	if _guard != null or seat() == null:
		return
	var shooter: TowerShooter = seat().get_active_shooter()
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	say("rs_live: bot guard %s, projectile %.0f m/s" % [_guard.name, controller().rules.guard_projectile_speed])


## tower_fov: the ridden runner's eye widens once he is in the tower room (r < 15) and still a prisoner.
func _widen_in_the_tower() -> void:
	var fov: float = float(option("tower_fov", 0.0))
	if fov <= 0.0 or clip._pov != "runner" or not is_instance_valid(clip._pov_body):
		return
	var body: PlayerController = clip._pov_body as PlayerController
	if body == null:
		return
	var eye: Camera3D = clip._eye_of(body)
	var inside: bool = Vector2(body.global_position.x, body.global_position.z).length() < 15.0
	if eye == null:
		return
	if inside and not body.is_in_group(MatchController.GUARD_GROUP):
		if _base_fov <= 0.0:
			_base_fov = eye.fov
		eye.fov = fov
	elif _base_fov > 0.0:
		eye.fov = _base_fov
		_base_fov = -1.0


# --- spectate: a ground camera on the runner the guard is aiming at ---------------------------

func lens(delta: float) -> bool:
	if int(option("spectate", 0)) != 1 or _guard == null or not is_instance_valid(_guard):
		return false
	var cam: Camera3D = camera()
	cam.fov = float(option("spec_fov", 38.0))
	if _hit_hold > 0.0:
		_hit_hold -= delta
		var avatar: PrisonerAvatar = PrisonerAvatar.of(_subject) if is_instance_valid(_subject) else null
		if avatar != null:
			_look = _look.lerp(avatar.drawn_centre(), 1.0 - exp(-delta * 6.0))
		_place(cam)
		return true
	var aimed: PlayerController = _aimed_at()
	if aimed != _candidate:
		_candidate = aimed
		_candidate_for = 0.0
	_candidate_for += delta
	if _candidate != null and _candidate != _subject and (_subject == null or _candidate_for > 0.5):
		_subject = _candidate
		_spot_ok = _pick_spot(_subject)
		_look = _subject.global_position + Vector3.UP * 1.0
	if _subject == null or not is_instance_valid(_subject):
		return _spot_ok
	var chest: Vector3 = _subject.global_position + Vector3.UP * 1.0
	_blind_for = 0.0 if _clear(_spot, chest, _subject) else _blind_for + delta
	if not _spot_ok or _blind_for > 0.3 or _spot.distance_to(chest) > 24.0:
		_spot_ok = _pick_spot(_subject)
		_blind_for = 0.0
		_look = chest
	_look = _look.lerp(chest, 1.0 - exp(-delta * 8.0))
	_place(cam)
	return _spot_ok


func _place(cam: Camera3D) -> void:
	if _spot_ok and _spot.distance_to(_look) > 0.5:
		cam.global_position = _spot
		cam.look_at(_look, Vector3.UP)


## The runner nearest the guard's line of aim.
func _aimed_at() -> PlayerController:
	var eye: Camera3D = _guard.get_node_or_null(^"Head/Camera") as Camera3D
	if eye == null:
		return null
	var fwd: Vector3 = -eye.global_transform.basis.z
	var best: PlayerController = null
	var best_dot: float = 0.97
	for body: PlayerController in _runners:
		if not is_instance_valid(body) or body == _guard or absf(body.global_position.y - 23.0) > 6.0:
			continue
		var d: float = fwd.dot((body.global_position + Vector3.UP - eye.global_position).normalized())
		if d > best_dot:
			best_dot = d
			best = body
	return best


## A standing spot 9-20 m from the body with a clear line to his chest and feet, preferring the
## outside of the ring (the tower behind him) and side-on to his run.
func _pick_spot(body: PlayerController) -> bool:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var p: Vector3 = body.global_position
	var out: Vector3 = Vector3(p.x, 0.0, p.z).normalized()
	var run: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
	run = run.normalized() if run.length() > 0.5 else out.cross(Vector3.UP)
	var want: float = float(option("spec_d", 14.0))
	var best_score: float = -INF
	for a: int in range(0, 360, 15):
		var dir: Vector3 = out.rotated(Vector3.UP, deg_to_rad(float(a)))
		for d: float in [want - 4.0, want, want + 4.0, want + 7.0]:
			var at: Vector3 = p + dir * d
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 6.0, at + Vector3.DOWN * 8.0)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				continue
			var floor_y: float = (hit["position"] as Vector3).y
			if absf(floor_y - p.y) > 2.5:
				continue
			var eye: Vector3 = Vector3(at.x, floor_y + 1.4, at.z)
			if not _roomy(space, eye) or not _clear(eye, p + Vector3.UP * 1.0, body) or not _clear(eye, p + Vector3.UP * 0.25, body):
				continue
			# He must stay in sight along his run for the next 1.6 s: the round's flight and the fall.
			var seen: int = 0
			for t: float in [0.4, 0.8, 1.2, 1.6]:
				var ahead: Vector3 = p + body.velocity * Vector3(t, 0.0, t)
				if _clear(eye, ahead + Vector3.UP * 0.6, body):
					seen += 1
			if seen < 3:
				continue
			var score: float = dir.dot(out) * 1.0 + (1.0 - absf(dir.dot(run))) * 0.8 - absf(d - want) * 0.05 + seen * 0.3
			if score > best_score:
				best_score = score
				_spot = eye
	return best_score > -INF


func _roomy(space: PhysicsDirectSpaceState3D, eye: Vector3) -> bool:
	for v: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + v * 0.8)).is_empty():
			return false
	return true


func _clear(from: Vector3, to: Vector3, body: PlayerController) -> bool:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = space.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == body or (hit["position"] as Vector3).distance_to(to) < 0.4
