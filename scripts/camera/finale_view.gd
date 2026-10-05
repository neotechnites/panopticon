class_name FinaleView
extends Node3D
## The finale shove's tracking shot: from wherever this machine's view is, its own
## camera swings in behind the guard thrown out of the tower and rides with him until the next round.

## The match to listen to. Without one this node does nothing.
@export var controller: MatchController
## This node's own camera. Never the player's.
@export var camera: Camera3D
## How fast the view swings onto the thrown body: higher is tighter.
@export_range(1.0, 40.0, 0.5) var follow_rate: float = 12.0
## Where the camera rides, metres behind the throw and above the body.
@export_range(0.0, 20.0, 0.1) var chase_back: float = 4.0
@export_range(0.0, 10.0, 0.1) var chase_up: float = 1.4
## Seconds held at the shover's eye to see the shove land, then to swing in behind.
@export_range(0.0, 1.0, 0.01) var hold_seconds: float = 0.12
@export_range(0.01, 1.0, 0.01) var swing_seconds: float = 0.3

var _avatar: PrisonerAvatar = null
var _guard: PlayerController = null
## The camera that was current when the shot began, given the view back after.
var _previous: Camera3D = null
var _remaining: float = 0.0
var _clock: float = 0.0
var _start: Vector3 = Vector3.ZERO
var _away: Vector3 = Vector3.FORWARD


func _ready() -> void:
	set_process(false)
	if controller == null or camera == null:
		return
	camera.current = false
	controller.kill_beat_started.connect(_on_guard_thrown)
	controller.round_started.connect(stand_down)
	controller.match_started.connect(func(_count: int) -> void: stand_down())


## True while the tracking shot holds the view.
func is_active() -> bool:
	return _remaining > 0.0


## The point the shot is following, world space.
func get_focus_point() -> Vector3:
	if _avatar != null and is_instance_valid(_avatar):
		return _avatar.drawn_centre()
	if _guard != null and is_instance_valid(_guard):
		return _guard.global_position + Vector3.UP
	return camera.global_position - camera.global_basis.z


func _on_guard_thrown(guard: MatchParticipant, seconds: float, throw: Vector3) -> void:
	if guard == null or guard.body == null or seconds <= 0.0:
		return
	_guard = guard.body
	_avatar = PrisonerAvatar.of(guard.body)
	_previous = get_viewport().get_camera_3d()
	if _previous != null and _previous != camera:
		camera.global_transform = _previous.global_transform
		camera.fov = _previous.fov
	_start = camera.global_position
	var flat: Vector3 = Vector3(throw.x, 0.0, throw.z)
	_away = flat.normalized() if flat.length_squared() > 1e-6 else -camera.global_basis.z
	_clock = 0.0
	# Ended by the next round; the clock is only a backstop for a lost round start.
	_remaining = seconds + 1.0
	camera.current = true
	set_process(true)


func _process(delta: float) -> void:
	tick(delta)


## Follow the thrown body for one frame. Public so a test may step it.
func tick(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		stand_down()
		return
	_clock += delta
	var focus: Vector3 = get_focus_point()
	var behind: Vector3 = focus - _away * chase_back + Vector3.UP * chase_up
	var swing: float = smoothstep(0.0, 1.0, (_clock - hold_seconds) / swing_seconds)
	camera.global_position = _start.lerp(behind, swing)
	var to_focus: Vector3 = focus - camera.global_position
	if to_focus.length_squared() < 1e-4 or absf(to_focus.normalized().y) > 0.999:
		return
	var aim: Basis = Basis.looking_at(to_focus.normalized(), Vector3.UP)
	var weight: float = 1.0 - exp(-follow_rate * delta)
	camera.global_basis = camera.global_basis.orthonormalized().slerp(aim, weight)


## Give the view back to the camera that had it. Idempotent.
func stand_down() -> void:
	_remaining = 0.0
	set_process(false)
	_avatar = null
	_guard = null
	if camera == null or not camera.current:
		_previous = null
		return
	camera.current = false
	if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
		_previous.current = true
	_previous = null


func _exit_tree() -> void:
	stand_down()
