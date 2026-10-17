extends Node

## --intent: one body's INPUTS scripted like a player's hands, through its BotIntentSource; the brain is
## paused meanwhile. Runner: run[:s] stop wait:s look:tower|portal[:s] cover:at:s shove_when_rival_within:m[:s]
## portal[:s] brawl idle[:s]. Guard: miss:N hit scope idle[:s] wait:s. Every unnamed body keeps its shipped brain.

const MAX_YAW_RATE: float = 3.0
const MAX_PITCH_RATE: float = 2.0
const DEFAULT_LOOK_SECONDS: float = 1.0
const DEFAULT_SHOVE_TIMEOUT: float = 10.0
const ALIGNED_RADIANS: float = 0.03
## A scripted miss aims this far beside the target (degrees).
const MISS_DEGREES: float = 4.0
const GUARD_TURN_RATE: float = 2.5
## A scripted hit waits this long for a runner to show, then gives up the step.
const HIT_WAIT_SECONDS: float = 8.0
## shove_when_rival_within ignores the spawn bunch for this long.
const SPAWN_GRACE_SECONDS: float = 2.0

var body: PlayerController = null
var brain: RunnerBrain = null
var shooter: TowerShooter = null
var controller: MatchController = null
var landmarks: Dictionary = {}
var _steps: Array[Dictionary] = []
var _index: int = 0
var _clock: float = 0.0
var _forward: bool = false
var _done: bool = false
var _shots_left: int = 0
var _since_install: float = 0.0
var _sure_profile: WeaponProfile = null
var _path: PackedVector3Array = PackedVector3Array()
var _path_age: float = 10.0
var _shipped_profile: WeaponProfile = null
var _say: Callable = Callable()


## Parse [param text] and take the body's input over from its brain ([param runner_brain] or [param tower_brain]).
func install(seat_body: PlayerController, runner_brain: RunnerBrain, tower_brain: TowerShooter, match_controller: MatchController, marks: Dictionary, text: String, say: Callable) -> bool:
	body = seat_body
	brain = runner_brain
	shooter = tower_brain
	controller = match_controller
	landmarks = marks
	_say = say
	for raw: String in text.split(",", false):
		var step: Dictionary = _parse(raw.strip_edges())
		if step.is_empty():
			printerr("[intent] cannot read step '%s'" % raw)
			return false
		_steps.append(step)
	_pause_brains(true)
	_say.call("[intent] %d steps on %s (%s): %s" % [_steps.size(), body.name, "guard" if shooter != null else "runner", text])
	return true


func is_done() -> bool:
	return _done


func _source() -> BotIntentSource:
	return shooter.input if shooter != null else brain.input


func _pause_brains(paused: bool) -> void:
	if shooter != null and is_instance_valid(shooter):
		shooter.set_physics_process(not paused)
		shooter.input.command.clear()
	elif brain != null and is_instance_valid(brain):
		brain.set_physics_process(not paused)
		brain.input.command.clear()
		brain.input.shove_enabled = not paused


func _parse(raw: String) -> Dictionary:
	var parts: PackedStringArray = raw.split(":")
	match parts[0]:
		"run":
			return {"kind": "run", "seconds": _number(parts, 1, -1.0)}
		"stop":
			return {"kind": "stop"}
		"wait":
			return {"kind": "wait", "seconds": _number(parts, 1, 1.0)}
		"idle":
			return {"kind": "idle", "seconds": _number(parts, 1, -1.0)}
		"look":
			if parts.size() < 2 or not landmarks.has(parts[1]):
				return {}
			return {"kind": "look", "at": parts[1], "seconds": _number(parts, 2, DEFAULT_LOOK_SECONDS)}
		"cover":
			return {"kind": "cover", "seconds": _number(parts, 2 if parts.size() > 2 else 1, 2.0)}
		"portal":
			return {"kind": "portal", "seconds": _number(parts, 1, 30.0)}
		"brawl":
			return {"kind": "brawl"}
		"shove_when_rival_within":
			return {"kind": "shove", "metres": _number(parts, 1, 3.0), "timeout": _number(parts, 2, DEFAULT_SHOVE_TIMEOUT), "cover": false}
		"shove_when_rival_cover":
			return {"kind": "shove", "metres": _number(parts, 1, 3.0), "timeout": _number(parts, 2, DEFAULT_SHOVE_TIMEOUT), "cover": true}
		"miss":
			return {"kind": "miss", "shots": int(_number(parts, 1, 1.0))}
		"hit":
			return {"kind": "hit"}
		"scope":
			return {"kind": "scope"}
	return {}


static func _number(parts: PackedStringArray, at: int, fallback: float) -> float:
	if parts.size() <= at:
		return fallback
	return float(parts[at].trim_suffix("s").trim_suffix("m"))


func _physics_process(delta: float) -> void:
	if _done or body == null or not is_instance_valid(body):
		return
	var participant: MatchParticipant = controller.resolve_participant(body)
	if participant == null or (not participant.is_running and not participant.is_shooter):
		_release("the body is out")
		return
	if _index >= _steps.size():
		_release("steps finished")
		return
	_since_install += delta
	# The match re-arms brains on every wake (round start, settle); scripted hands stay in charge.
	if shooter != null and shooter.is_physics_processing() or brain != null and shooter == null and brain.is_physics_processing():
		_pause_brains(true)
	if shooter != null:
		_tick_guard(delta)
	else:
		_tick_runner(delta)


func _tick_runner(delta: float) -> void:
	var source: BotIntentSource = brain.input
	source.command.move_direction = Vector2(0.0, 1.0) if _forward else Vector2.ZERO
	var step: Dictionary = _steps[_index]
	_clock += delta
	match String(step["kind"]):
		"run":
			_forward = true
			var seconds: float = float(step["seconds"])
			if seconds < 0.0 or _clock >= seconds:
				_forward = seconds < 0.0
				_next()
		"stop":
			_forward = false
			_next()
		"wait":
			if _clock >= float(step["seconds"]):
				_next()
		"idle":
			_forward = false
			source.command.move_direction = Vector2.ZERO
			if float(step["seconds"]) >= 0.0 and _clock >= float(step["seconds"]):
				_next()
		"cover":
			# Crouched where they stand, as a player ducks behind cover.
			_forward = false
			source.command.move_direction = Vector2.ZERO
			source.hold_slide(true)
			if _clock >= float(step["seconds"]):
				source.hold_slide(false)
				_next()
		"look":
			var error: float = _turn_towards(landmarks[step["at"]], delta, float(step["seconds"]))
			if absf(error) < ALIGNED_RADIANS or _clock >= float(step["seconds"]) + 1.0:
				_next()
		"portal":
			# Face the portal and run at it; the match's own arrival ends it.
			_turn_towards(landmarks["portal"], delta, 0.5)
			source.command.move_direction = Vector2(0.0, 1.0)
			if _clock >= float(step["seconds"]):
				_next()
		"brawl":
			# The match drives brawl bots itself; hand the body back for it.
			_release("brawl: the match's own fight")
		"shove":
			if _clock >= float(step["timeout"]):
				_say.call("[intent] shove step timed out after %.1f s" % _clock)
				_next()
				return
			if not bool(step["cover"]) and _since_install < SPAWN_GRACE_SECONDS:
				return
			if bool(step["cover"]):
				# Walk up to the nearest rival stopped at cover, then shove once within reach.
				var covering: Node3D = _rival_within(1000.0, true)
				if covering == null:
					# Nobody at cover yet: stand, as a player waiting for the moment would.
					source.command.move_direction = Vector2.ZERO
					return
				var gap: float = _flat_distance(covering.global_position)
				if gap > float(step["metres"]) * 0.8:
					_walk_to(covering.global_position, delta)
					if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 60 == 0:
						_say.call("[intent] %5.2f walking to %s, %.1f m, speed %.1f" % [_clock, covering.name, gap, body.get_horizontal_speed()])
					return
				_turn_towards(covering.global_position, delta, 0.3)
			var rival: Node3D = _rival_within(float(step["metres"]), bool(step["cover"]))
			if rival != null:
				var error: float = _turn_towards(rival.global_position, delta, 0.2)
				if absf(error) < 0.3:
					source.command.shove_pressed = true
					_say.call("[intent] %5.2f shove at %s" % [_clock, rival.name])
					_next()


## The guard: aim at the nearest living runner (beside it for a miss, led for a hit) and pull when the rifle is ready.
func _tick_guard(delta: float) -> void:
	var step: Dictionary = _steps[_index]
	_clock += delta
	match String(step["kind"]):
		"wait":
			if _clock >= float(step["seconds"]):
				_next()
		"idle":
			if float(step["seconds"]) >= 0.0 and _clock >= float(step["seconds"]):
				_next()
		"scope":
			if shooter.optic != null:
				shooter.optic.set_zoomed(true)
			_next()
		"miss":
			var target: PlayerController = _nearest_runner()
			if target == null:
				return
			if _shots_left <= 0:
				_shots_left = int(step["shots"])
			var error: Vector2 = _aim_guard(_aim_point(target, true), delta)
			if shooter.optic != null:
				shooter.optic.set_zoomed(true)
			var settled: bool = shooter.optic == null or shooter.optic.is_fully_zoomed()
			if settled and error.length() < deg_to_rad(0.6) and shooter.rifle != null and shooter.rifle.can_fire():
				if shooter.rifle.try_fire():
					_say.call("[intent] %5.2f guard miss at %s" % [_clock, target.name])
					_shots_left -= 1
					if _shots_left <= 0:
						_next()
		"hit":
			_tick_sure_hit()


## A scripted hit: the nearest runner on screen, the aim written straight onto the chest with the round's lead
## and drop, no spread for that one shot. Waits HIT_WAIT_SECONDS for a runner to show.
func _tick_sure_hit() -> void:
	if shooter.optic != null:
		shooter.optic.set_zoomed(true)
	if _clock >= HIT_WAIT_SECONDS:
		_say.call("[intent] hit: no shot in %.0f s; step dropped" % HIT_WAIT_SECONDS)
		_next()
		return
	var target: PlayerController = _visible_runner()
	if target == null:
		return
	var point: Vector3 = _aim_point(target, false)
	_set_aim(point)
	if shooter.optic != null and not shooter.optic.is_fully_zoomed():
		return
	if shooter.rifle == null or not shooter.rifle.can_fire():
		return
	_hold_spread(true)
	var fired: bool = shooter.rifle.try_fire()
	_hold_spread(false)
	if fired:
		_say.call("[intent] %5.2f guard sure shot at %s, %.1f m" % [_clock, target.name, body.global_position.distance_to(target.global_position)])
		_next()


## The rifle's profile with no spread, for one shot; the shipped one comes back after.
func _hold_spread(on: bool) -> void:
	if shooter.rifle == null or shooter.rifle.profile == null:
		return
	if on:
		if shooter.rifle.profile == _sure_profile:
			return
		_shipped_profile = shooter.rifle.profile
		if _sure_profile == null:
			_sure_profile = _shipped_profile.duplicate() as WeaponProfile
			_sure_profile.spread_degrees = 0.0
			_sure_profile.moving_spread_degrees = 0.0
		shooter.rifle.profile = _sure_profile
	elif _shipped_profile != null:
		shooter.rifle.profile = _shipped_profile


## Write the guard's yaw and head pitch so the camera's forward is exactly at [param point].
func _set_aim(point: Vector3) -> void:
	var eye: Node3D = body.get_node_or_null(^"Head/Camera") as Node3D
	var from: Vector3 = eye.global_position if eye != null else body.global_position + Vector3.UP * body.get_eye_height()
	var direction: Vector3 = (point - from).normalized()
	body.rotation.y = atan2(-direction.x, -direction.z)
	if body.head != null:
		body.head.rotation.x = asin(clampf(direction.y, -1.0, 1.0))


## The nearest living runner inside the guard's own frustum with a clear line to its chest.
func _visible_runner() -> PlayerController:
	var cam: Camera3D = body.get_node_or_null(^"Head/Camera") as Camera3D
	if cam == null:
		return _nearest_runner()
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	var best: PlayerController = null
	var best_distance: float = 0.0
	for node: Node in get_tree().get_nodes_in_group(MatchController.RUNNER_GROUP):
		var rival: PlayerController = node as PlayerController
		if rival == null or rival == body:
			continue
		var chest: Vector3 = rival.global_position + Vector3.UP * rival.get_eye_height() * 0.75
		if not cam.is_position_in_frustum(chest):
			continue
		var query := PhysicsRayQueryParameters3D.create(cam.global_position, chest, 0xFFFFFFFF, [body.get_rid()])
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or (hit["collider"] as Node) != rival:
			continue
		var distance: float = cam.global_position.distance_to(chest)
		if best == null or distance < best_distance:
			best = rival
			best_distance = distance
	return best


## Where the guard aims: the runner's chest led by the round's flight, or beside it for a miss.
func _aim_point(target: PlayerController, miss: bool) -> Vector3:
	var eye: Vector3 = body.global_position + Vector3.UP * body.get_eye_height()
	var chest: Vector3 = target.global_position + Vector3.UP * target.get_eye_height() * 0.75
	var speed: float = shooter.rifle.get_shot_speed() if shooter.rifle != null else 0.0
	if speed > 0.0:
		var flight: float = eye.distance_to(chest) / speed
		flight = (chest + target.velocity * flight - eye).length() / speed
		chest += target.velocity * flight
		var gravity: float = shooter.rifle.profile.projectile_gravity if shooter.rifle.profile != null else 0.0
		chest.y += 0.5 * gravity * flight * flight
	if miss:
		var aside: Vector3 = (chest - eye).cross(Vector3.UP).normalized()
		chest += aside * tan(deg_to_rad(MISS_DEGREES)) * eye.distance_to(chest)
	return chest


## Turn the guard's head onto [param point]; returns the (yaw, pitch) error in radians.
func _aim_guard(point: Vector3, delta: float) -> Vector2:
	var eye: Vector3 = body.global_position + Vector3.UP * body.get_eye_height()
	var to_target: Vector3 = point - eye
	var forward: Vector3 = -body.global_transform.basis.z
	var yaw_error: float = Vector2(forward.x, forward.z).angle_to(Vector2(to_target.x, to_target.z))
	var flat: float = Vector2(to_target.x, to_target.z).length()
	var wanted_pitch: float = atan2(to_target.y, maxf(flat, 0.01))
	var pitch_error: float = wanted_pitch - (body.head.rotation.x if body.head != null else 0.0)
	shooter.input.aim(
		clampf(yaw_error * 6.0, -GUARD_TURN_RATE, GUARD_TURN_RATE),
		clampf(pitch_error * 6.0, -GUARD_TURN_RATE, GUARD_TURN_RATE),
		delta,
	)
	return Vector2(yaw_error, pitch_error)


func _nearest_runner() -> PlayerController:
	var best: PlayerController = null
	var best_distance: float = 0.0
	for node: Node in get_tree().get_nodes_in_group(MatchController.RUNNER_GROUP):
		var rival: PlayerController = node as PlayerController
		if rival == null or rival == body:
			continue
		var distance: float = rival.global_position.distance_to(body.global_position)
		if best == null or distance < best_distance:
			best = rival
			best_distance = distance
	return best


func _next() -> void:
	_index += 1
	_clock = 0.0


## Yaw (and pitch) towards [param point] over about [param seconds]; returns the yaw error.
func _turn_towards(point: Vector3, delta: float, seconds: float) -> float:
	var to_target: Vector3 = point - body.global_position
	var forward: Vector3 = -body.global_transform.basis.z
	var yaw_error: float = Vector2(forward.x, forward.z).angle_to(Vector2(to_target.x, to_target.z))
	var eye: Vector3 = body.global_position + Vector3.UP * body.get_eye_height()
	var flat: float = Vector2(point.x - eye.x, point.z - eye.z).length()
	var wanted_pitch: float = atan2(point.y - eye.y, maxf(flat, 0.01))
	var pitch_error: float = wanted_pitch - (body.head.rotation.x if body.head != null else 0.0)
	var share: float = 1.0 / maxf(seconds, 0.1)
	brain.input.aim(
		clampf(yaw_error * share * 2.0, -MAX_YAW_RATE, MAX_YAW_RATE),
		clampf(pitch_error * share * 2.0, -MAX_PITCH_RATE, MAX_PITCH_RATE),
		delta,
	)
	return yaw_error


## The nearest living rival within [param metres], ahead of the body.
func _rival_within(metres: float, at_cover: bool = false) -> Node3D:
	var here: Vector3 = body.global_position
	var forward: Vector3 = -body.global_transform.basis.z
	forward.y = 0.0
	var best: Node3D = null
	var best_distance: float = 0.0
	for node: Node in get_tree().get_nodes_in_group(MatchController.RUNNER_GROUP):
		var rival: Node3D = node as Node3D
		if rival == null or rival == body:
			continue
		var offset: Vector3 = rival.global_position - here
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > metres or distance < 1e-3:
			continue
		if not at_cover and forward.length_squared() > 1e-6 and forward.normalized().dot(offset / distance) < 0.0:
			continue
		if at_cover and not _is_at_cover(rival):
			continue
		if best == null or distance < best_distance:
			best = rival
			best_distance = distance
	return best


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - body.global_position.x, point.z - body.global_position.z).length()


## Walk to [param point] along the ring bake's path (the brain's own planner), re-planned twice a second.
func _walk_to(point: Vector3, delta: float) -> void:
	_path_age += delta
	var bake: RingBake = brain.get_navigation() if brain != null else null
	if bake != null and bake.is_ready() and _path_age >= 0.5:
		_path = bake.find_path(body.global_position, point)
		_path_age = 0.0
	# The first waypoint ahead: past 1.2 m from the body and nearer the goal than the body is.
	var next: Vector3 = point
	var left: float = _flat_distance(point)
	for waypoint: Vector3 in _path:
		if _flat_distance(waypoint) > 1.2 and Vector2(point.x - waypoint.x, point.z - waypoint.z).length() < left - 0.5:
			next = waypoint
			break
	_turn_towards(next, delta, 0.3)
	_drive_towards(next)


## Walk at [param point] whatever the body faces; move_direction is body-local.
func _drive_towards(point: Vector3) -> void:
	var flat: Vector2 = Vector2(point.x - body.global_position.x, point.z - body.global_position.z)
	var basis: Basis = body.global_transform.basis
	var right: Vector2 = Vector2(basis.x.x, basis.x.z)
	var forward: Vector2 = Vector2(-basis.z.x, -basis.z.z)
	brain.input.command.move_direction = Vector2(flat.dot(right), flat.dot(forward)).normalized()


## True while [param rival] is stopped at cover: its brain says so, or its hands do (stood still past the spawn).
func _is_at_cover(rival: Node3D) -> bool:
	var participant: MatchParticipant = controller.resolve_participant(rival)
	if participant == null or participant.body == null or not participant.is_running:
		return false
	# Stopped, not still running to its cover point.
	return participant.body.get_horizontal_speed() < 0.3 and is_at_cover(participant, _since_install >= SPAWN_GRACE_SECONDS)


## Cover as the recorder and the searcher read it; [param settled] is false in the spawn bunch.
static func is_at_cover(participant: MatchParticipant, settled: bool) -> bool:
	if participant.brain != null and participant.brain.get_state() == RunnerBrain.State.TAKE_COVER:
		return true
	var body: PlayerController = participant.body
	return settled and body != null and body.is_on_floor() and body.get_horizontal_speed() < 0.3


## Hand the body back to its shipped brain.
func _release(why: String) -> void:
	_done = true
	_pause_brains(false)
	_say.call("[intent] %s released: %s" % [body.name if body != null else "?", why])
