class_name MannequinIntent
extends BotIntentSource

## A debug body's scripted routine, written into the same struct a bot writes. Nothing here draws:
## what the body shows is the real controller and avatar answering this intent.

enum Routine { STAND, LOOK, WALK, SPRINT, JUMP, LEDGE, SLOPE, GUARD, FOLLOW, SHOVE, NUDGE }

## Stick lengths: a walk, a careful walk over uneven ground, a hop's carry.
const WALK: float = 0.25
const STROLL: float = 0.2
const HOP: float = 0.4
## Radians a second: a walking turn, a sharp turn at a sprint, a snap round at a hard stop, a glance.
const TURN_RATE: float = 3.0
const SHARP_RATE: float = 9.0
const SNAP_RATE: float = 16.0
const LOOK_RATE: float = 2.5
## Metres from a waypoint that count as there; seconds a sprint stands at a hard stop.
const ARRIVED: float = 0.6
const STOP_SECONDS: float = 0.8
## Seconds per glance, and the glances (yaw right, pitch up, degrees) from the facing it started at.
const GLANCE_SECONDS: float = 1.4
const GLANCES: Array[Vector2] = [
	Vector2(-70.0, 0.0), Vector2(70.0, 0.0), Vector2(0.0, 35.0),
	Vector2(0.0, -35.0), Vector2(-110.0, 15.0), Vector2(110.0, -15.0), Vector2(0.0, 0.0),
]
## Metres a follower keeps from who it follows.
const FOLLOW_GAP: float = 2.5

var routine: Routine = Routine.STAND
## Waypoints for the routine, in world space.
var route: PackedVector3Array = PackedVector3Array()
## Who FOLLOW follows.
var follow: Node3D = null

var _yaw: float = 0.0
var _leg: int = 0
var _clock: float = 0.0
var _beat: int = 0


func _init() -> void:
	shove_enabled = false


## Start [param next] now, from the facing the body has.
func run(next: Routine, points: PackedVector3Array = PackedVector3Array()) -> void:
	routine = next
	route = points
	_leg = 0
	_clock = 0.0
	_beat = 0
	command.clear()
	var body: PlayerController = get_parent() as PlayerController
	_yaw = body.rotation.y if body != null else 0.0


func poll(delta: float) -> MoveIntent:
	var body: PlayerController = get_parent() as PlayerController
	if body != null:
		command.move_direction = Vector2.ZERO
		command.look_delta = Vector2.ZERO
		_clock += delta
		_step(body, delta)
	return super.poll(delta)


func _step(body: PlayerController, delta: float) -> void:
	match routine:
		Routine.LOOK:
			var glance: Vector2 = GLANCES[int(_clock / GLANCE_SECONDS) % GLANCES.size()]
			_aim(body, _yaw - deg_to_rad(glance.x), deg_to_rad(glance.y), LOOK_RATE, delta)
		Routine.WALK, Routine.SLOPE:
			if _go(body, WALK if routine == Routine.WALK else STROLL, TURN_RATE, delta):
				_leg = (_leg + 1) % maxi(route.size(), 1)
		Routine.LEDGE:
			if _leg < route.size() and _go(body, STROLL, TURN_RATE, delta):
				_leg += 1
		Routine.SPRINT:
			_sprint(body, delta)
		Routine.JUMP:
			_hop(body, delta)
		Routine.GUARD:
			_aim(body, _yaw + sin(_clock * 0.6) * 0.6, sin(_clock * 1.1) * 0.6, LOOK_RATE, delta)
		Routine.FOLLOW:
			_follow(body, delta)
		Routine.SHOVE:
			if not route.is_empty():
				_aim(body, _yaw_to(body.global_position, route[0]), 0.0, SNAP_RATE, delta)
			if _beat == 0 and _clock >= 0.25:
				_beat = 1
				command.shove_pressed = true
		Routine.NUDGE:
			command.move_direction = Vector2(0.0, 0.15)
			if _clock >= 0.3:
				run(Routine.STAND)


## Corners at a flat-out sprint: even corners a hard stop and a snap round, odd ones a sharp turn on the run.
func _sprint(body: PlayerController, delta: float) -> void:
	if route.is_empty():
		return
	if _beat == 1:
		_aim(body, _yaw_to(body.global_position, route[_leg]), 0.0, SNAP_RATE, delta)
		if _clock >= STOP_SECONDS:
			_beat = 0
		return
	if _go(body, 1.0, SHARP_RATE, delta, false):
		if _leg % 2 == 0:
			_beat = 1
			_clock = 0.0
		_leg = (_leg + 1) % route.size()


## Hop between the waypoints: stand, jump toward the next, land, stand.
func _hop(body: PlayerController, delta: float) -> void:
	if route.is_empty():
		return
	var target: Vector3 = route[_leg]
	if _beat == 0:
		_aim(body, _yaw_to(body.global_position, target), 0.0, SNAP_RATE, delta)
		if _clock >= 0.9 and body.is_on_floor():
			command.jump_pressed = true
			command.jump_held = true
			_beat = 1
			_clock = 0.0
		return
	command.jump_held = false
	_go(body, HOP, TURN_RATE, delta)
	if _clock >= 0.25 and body.is_on_floor():
		_beat = 0
		_clock = 0.0
		_leg = (_leg + 1) % route.size()


func _follow(body: PlayerController, delta: float) -> void:
	if not is_instance_valid(follow):
		return
	var to: Vector3 = follow.global_position - body.global_position
	var gap: float = Vector2(to.x, to.z).length()
	var yaw: float = _yaw_to(body.global_position, follow.global_position)
	_aim(body, yaw, 0.0, SHARP_RATE, delta)
	if gap > FOLLOW_GAP:
		var turn: float = absf(angle_difference(body.rotation.y, yaw))
		command.move_direction = Vector2(0.0, clampf((gap - FOLLOW_GAP) / 6.0, 0.15, 1.0) * clampf(cos(turn), 0.0, 1.0))


## Steer for the current waypoint at [param speed]; true once there. [param easing] slows for a wide turn.
func _go(body: PlayerController, speed: float, rate: float, delta: float, easing: bool = true) -> bool:
	if _leg >= route.size():
		return false
	var target: Vector3 = route[_leg]
	var to: Vector3 = target - body.global_position
	if Vector2(to.x, to.z).length() < ARRIVED:
		return true
	var yaw: float = _yaw_to(body.global_position, target)
	_aim(body, yaw, 0.0, rate, delta)
	var turn: float = absf(angle_difference(body.rotation.y, yaw))
	command.move_direction = Vector2(0.0, speed * (clampf(cos(turn), 0.0, 1.0) if easing else 1.0))
	return false


## Turn the view toward [param yaw] and [param pitch], radians, at most [param rate] a second.
func _aim(body: PlayerController, yaw: float, pitch: float, rate: float, delta: float) -> void:
	var view: Vector2 = body.get_view_angles()
	var turn: float = clampf(angle_difference(view.x, yaw), -rate * delta, rate * delta)
	var tilt: float = clampf(pitch - view.y, -rate * delta, rate * delta)
	var inverted: bool = body.profile != null and body.profile.invert_look_y
	command.look_delta = Vector2(-turn, tilt if inverted else -tilt)


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	return atan2(-d.x, -d.z)
