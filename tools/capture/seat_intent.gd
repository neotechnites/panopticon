extends Node

## --seat-intent: the seat body's INPUTS, scripted like a player's hands (run, look:tower:2s,
## shove_when_rival_within:3m, wait:1s), through its BotIntentSource; every other body keeps its brain.

const MAX_YAW_RATE: float = 3.0
const MAX_PITCH_RATE: float = 2.0
const DEFAULT_LOOK_SECONDS: float = 1.0
const DEFAULT_SHOVE_TIMEOUT: float = 10.0
const ALIGNED_RADIANS: float = 0.03

var body: PlayerController = null
var brain: RunnerBrain = null
var controller: MatchController = null
var landmarks: Dictionary = {}
var _steps: Array[Dictionary] = []
var _index: int = 0
var _clock: float = 0.0
var _forward: bool = false
var _done: bool = false
var _reported: Dictionary = {}
var _say: Callable = Callable()


## Parse [param text] and take the body's input over from its brain. [param say] logs a line.
func install(seat_body: PlayerController, seat_brain: RunnerBrain, match_controller: MatchController, marks: Dictionary, text: String, say: Callable) -> bool:
	body = seat_body
	brain = seat_brain
	controller = match_controller
	landmarks = marks
	_say = say
	for raw: String in text.replace(";", ",").split(",", false):
		var step: Dictionary = _parse(raw.strip_edges())
		if step.is_empty():
			printerr("[intent] cannot read step '%s'" % raw)
			return false
		_steps.append(step)
	if brain != null:
		brain.set_physics_process(false)
		brain.input.command.clear()
		brain.input.shove_enabled = false
	_say.call("[intent] %d steps on %s: %s" % [_steps.size(), body.name, text])
	return true


func is_done() -> bool:
	return _done


func _parse(raw: String) -> Dictionary:
	var parts: PackedStringArray = raw.split(":")
	var kind: String = parts[0]
	match kind:
		"run":
			return {"kind": "run", "seconds": _seconds(parts, 1, -1.0)}
		"stop":
			return {"kind": "stop"}
		"wait":
			return {"kind": "wait", "seconds": _seconds(parts, 1, 1.0)}
		"look":
			if parts.size() < 2 or not landmarks.has(parts[1]):
				return {}
			return {"kind": "look", "at": parts[1], "seconds": _seconds(parts, 2, DEFAULT_LOOK_SECONDS)}
		"shove_when_rival_within":
			var metres: float = _seconds(parts, 1, 3.0)
			return {"kind": "shove", "metres": metres, "timeout": _seconds(parts, 2, DEFAULT_SHOVE_TIMEOUT)}
	return {}


static func _seconds(parts: PackedStringArray, at: int, fallback: float) -> float:
	if parts.size() <= at:
		return fallback
	return float(parts[at].trim_suffix("s").trim_suffix("m"))


func _physics_process(delta: float) -> void:
	if _done or body == null or not is_instance_valid(body) or brain == null:
		return
	var participant: MatchParticipant = controller.resolve_participant(body)
	if participant == null or not participant.is_running:
		_release("the seat is out")
		return
	if _index >= _steps.size():
		_release("steps finished")
		return
	var source: BotIntentSource = brain.input
	source.command.move_direction = Vector2(0.0, 1.0) if _forward else Vector2.ZERO
	var step: Dictionary = _steps[_index]
	_clock += delta
	match String(step["kind"]):
		"run":
			_forward = true
			var seconds: float = float(step["seconds"])
			if seconds < 0.0 or _clock >= seconds:
				if seconds >= 0.0:
					_forward = false
				_next()
		"stop":
			_forward = false
			_next()
		"wait":
			if _clock >= float(step["seconds"]):
				_next()
		"look":
			var error: float = _turn_towards(landmarks[step["at"]], delta, float(step["seconds"]))
			if absf(error) < ALIGNED_RADIANS or _clock >= float(step["seconds"]) + 1.0:
				_next()
		"shove":
			var rival: Node3D = _rival_within(float(step["metres"]))
			if rival != null:
				var error: float = _turn_towards(rival.global_position, delta, 0.2)
				if absf(error) < 0.3:
					source.command.shove_pressed = true
					_say.call("[intent] %5.2f shove at %s" % [_clock, rival.name])
					_next()
			elif _clock >= float(step["timeout"]):
				_say.call("[intent] shove_when_rival_within timed out after %.1f s" % _clock)
				_next()


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
	var head_pitch: float = body.head.rotation.x if body.head != null else 0.0
	var pitch_error: float = wanted_pitch - head_pitch
	var share: float = 1.0 / maxf(seconds, 0.1)
	brain.input.aim(
		clampf(yaw_error * share * 2.0, -MAX_YAW_RATE, MAX_YAW_RATE),
		clampf(pitch_error * share * 2.0, -MAX_PITCH_RATE, MAX_PITCH_RATE),
		delta,
	)
	return yaw_error


## The nearest living rival within [param metres], ahead of the body.
func _rival_within(metres: float) -> Node3D:
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
		if forward.length_squared() > 1e-6 and forward.normalized().dot(offset / distance) < 0.0:
			continue
		if best == null or distance < best_distance:
			best = rival
			best_distance = distance
	return best


## Hand the body back to its shipped brain.
func _release(why: String) -> void:
	_done = true
	if brain != null and is_instance_valid(brain):
		brain.input.command.clear()
		brain.input.shove_enabled = true
		brain.set_physics_process(true)
	_say.call("[intent] released: %s" % why)
