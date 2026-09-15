extends Node

## B-roll only: the guard's head driven like a hand on a mouse, for a guard POV.
##
## Ryan: "it should look like a normal person aiming" and "the sniper should
## hit some shots". The tower's own brain is stood down the moment it holds
## the rifle; this node then moves the head through a list of beats -- ease
## onto a runner with a slight overshoot, settle, track him for a moment
## (leading him, so the crosshair sits ON him rather than a step behind),
## squeeze at [code]fire_at[/code], take the recoil and let the same spring
## bring the scope back down onto the drop, then ease off to the next beat.
##
## [codeblock]
## var hand: Node = GUARD_HAND.new()
## root.add_child(hand)
## hand.install(guard_body, controller)
## hand.beats = [
##     {"body": runner_a, "seconds": 1.7, "fire_at": 1.25},
##     {"body": runner_b, "seconds": 1.7, "fire_at": 1.25},
##     {"at": Vector3, "seconds": 1.0},               # a look at a point, no shot
## ]
## hand.park = Vector3   # where the scope rests until the first beat
## hand.start_at = 1.8   # clip seconds the hand starts moving (install passes the clip clock)
## [/codeblock]
##
## The hand is a second-order response to the aim error: OMEGA sets how quick,
## ZETA under one gives the overshoot a real hand has, and the rate cap is a
## wrist. The breathing sway dies out before the trigger, the way a hand settles
## before it squeezes. Everything is on the guard body's own camera, so the
## scope, the zoom and the vignette are the game's.

const HAND_OMEGA: float = 6.0
const HAND_ZETA: float = 0.7
const HAND_MAX_RATE: float = deg_to_rad(140.0)
const SETTLE_SECONDS: float = 0.35
const RECOIL_PITCH_RATE: float = deg_to_rad(80.0)
const RECOIL_YAW_RATE: float = deg_to_rad(14.0)
const SWAY_DEGREES: float = 0.25
const SWAY_HZ: float = 0.6
const AIM_HEIGHT: float = 1.0

var beats: Array = []
var park: Vector3 = Vector3.ZERO
var start_at: float = 0.0
var hold_scope: bool = true

var _guard: PlayerController = null
var _controller: MatchController = null
var _elapsed: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _rate: Vector2 = Vector2.ZERO
var _fired: Array = []
var _last_aim: Array = []
var _installed: bool = false


## [param clock] is the clip's elapsed time now, so start_at and the log are in clip seconds.
func install(guard: PlayerController, match_controller: MatchController, clock: float = 0.0) -> void:
	_guard = guard
	_controller = match_controller
	_elapsed = clock
	_yaw = _guard.rotation.y
	_pitch = _guard.head.rotation.x if _guard.head != null else 0.0
	_installed = true


func _physics_process(delta: float) -> void:
	if not _installed or _guard == null or not is_instance_valid(_guard):
		return
	_elapsed += delta
	if hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(true)
	var t: float = _elapsed - start_at
	if beats.is_empty() or t < 0.0:
		if park != Vector3.ZERO:
			var angles: Vector2 = _angles_to(park)
			_yaw = angles.x
			_pitch = angles.y
		_rate = Vector2.ZERO
		_apply_head()
		return
	while _last_aim.size() < beats.size():
		_last_aim.append(Vector3.ZERO)
	# Which beat, and how far into it.
	var k: int = 0
	var into: float = t
	while k < beats.size() - 1 and into >= float(beats[k].get("seconds", 1.7)):
		into -= float(beats[k].get("seconds", 1.7))
		k += 1
	var beat: Dictionary = beats[k]
	var body: PlayerController = beat.get("body") as PlayerController
	var fire_at: float = float(beat.get("fire_at", -1.0))
	var aim: Vector3
	if _fired.has(k) or body == null or not is_instance_valid(body):
		aim = _last_aim[k] if _last_aim[k] != Vector3.ZERO else beat.get("at", park)
	else:
		aim = body.global_position + Vector3.UP * AIM_HEIGHT
		_last_aim[k] = aim
		# Tracking a runner is aiming where he is going: the lead cancels the
		# second-order lag, so once the hand has settled the crosshair sits on him.
		var lag_seconds: float = 2.0 * HAND_ZETA / HAND_OMEGA
		aim += Vector3(body.velocity.x, 0.0, body.velocity.z) * lag_seconds
	var wanted: Vector2 = _angles_to(aim)
	if not _fired.has(k):
		var settling: float = 1.0 if fire_at < 0.0 else clampf((fire_at - into) / SETTLE_SECONDS, 0.0, 1.0)
		var sway: float = deg_to_rad(SWAY_DEGREES) * settling
		wanted += Vector2(sin(t * TAU * SWAY_HZ) * sway, sin(t * TAU * SWAY_HZ * 1.7 + 1.0) * sway * 0.6)
	var error := Vector2(angle_difference(_yaw, wanted.x), wanted.y - _pitch)
	var accel: Vector2 = error * (HAND_OMEGA * HAND_OMEGA) - _rate * (2.0 * HAND_ZETA * HAND_OMEGA)
	_rate += accel * delta
	_rate = _rate.limit_length(HAND_MAX_RATE)
	_yaw = wrapf(_yaw + _rate.x * delta, -PI, PI)
	_pitch += _rate.y * delta
	if body != null and is_instance_valid(body) and fire_at >= 0.0 and not _fired.has(k) and into >= fire_at:
		_fired.append(k)
		# The last of the error goes in the squeeze: the crosshair is on him.
		var exact: Vector2 = _angles_to(body.global_position + Vector3.UP * AIM_HEIGHT)
		_yaw = exact.x
		_pitch = exact.y
		_apply_head()
		_fire(k)
		# The kick lands the frame after the shot line is resolved.
		_rate = Vector2(RECOIL_YAW_RATE * (1.0 if k % 2 == 0 else -1.0), RECOIL_PITCH_RATE)
		return
	_apply_head()


## Pull the trigger with the head already on the runner. Hitscan: the rifle's
## own ray decides, along the eye it is aimed from.
func _fire(k: int) -> void:
	var rifle: Rifle = _controller.rifle
	if rifle == null:
		printerr("[event] %6.2f  no rifle to fire on beat %d" % [_elapsed, k])
		return
	if not rifle.can_fire():
		printerr("[event] %6.2f  rifle not ready (%s) on beat %d" % [_elapsed, rifle.get_state_name(), k])
		return
	var ok: bool = rifle.try_fire()
	print("[event] %6.2f  hand  beat %d %s" % [_elapsed, k, "fired" if ok else "REFUSED"])


func _eye_position() -> Vector3:
	var camera: Node3D = _guard.get_node_or_null(^"Head/Camera") as Node3D
	return camera.global_position if camera != null else _guard.global_position + Vector3.UP * 1.65


## Yaw and pitch that put the head on [param point], in the controller's own convention.
func _angles_to(point: Vector3) -> Vector2:
	var d: Vector3 = point - _eye_position()
	var flat: float = Vector2(d.x, d.z).length()
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, maxf(flat, 0.001)))


func _apply_head() -> void:
	_guard.rotation = Vector3(0.0, _yaw, 0.0)
	if _guard.head != null:
		_guard.head.rotation.x = _pitch
	# The controller keeps its own pitch and would snap the head back to it on
	# the next look input; kept in step so nothing ever arrives to undo this.
	_guard.set(&"_pitch", _pitch)
