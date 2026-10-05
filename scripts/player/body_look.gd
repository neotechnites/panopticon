extends "res://scripts/player/body_layer.gd"

## The head finds the look first and the feet follow a beat later: hips trail the yaw, spine, neck and head
## hand it back and share the pitch. Reads the body's own yaw and head pitch, which every machine has.

## How the turn back to the look, and the pitch, are shared up the back: spine, neck, head. Each sums to one.
const TURN_SHARE: Array[float] = [0.3, 0.25, 0.45]
const PITCH_SHARE: Array[float] = [0.2, 0.3, 0.5]
## Model space: a pitch up turns about -X.
const PITCH_AXIS: Vector3 = Vector3(-1.0, 0.0, 0.0)
## Horizontal speed, m/s, at which a body counts as fully on the move.
const MOVING_SPEED: float = 3.0
## How much faster the feet catch the look on the move than standing.
const MOVING_FOLLOW: float = 2.5
## Per second, how fast the drawn pitch follows the head's.
const PITCH_RATE: float = 14.0

## Degrees the head may lead the feet before the feet are dragged round.
@export_range(0.0, 90.0, 1.0) var twist_limit_degrees: float = 55.0
## Degrees a standing body lets the head and chest turn before the feet move at all.
@export_range(0.0, 60.0, 1.0) var stand_free_degrees: float = 22.0
## Per second, how fast the feet catch up with the look.
@export_range(0.5, 30.0, 0.5) var follow_rate: float = 5.0
## The share of the look's pitch the back and head take, and the most they bend, degrees.
@export_range(0.0, 1.0, 0.05) var pitch_share: float = 0.8
@export_range(0.0, 89.0, 1.0) var pitch_limit_degrees: float = 55.0
## The share of the twist a body holding a rifle keeps; its pitch is the hold's.
@export_range(0.0, 1.0, 0.05) var armed_share: float = 0.3

var _hips: int = -1
var _back: PackedInt32Array = PackedInt32Array([-1, -1, -1])
## World yaw the feet are drawn at, and the drawn pitch.
var _feet_yaw: float = 0.0
var _pitch: float = 0.0
var _seeded: bool = false


func _bound(skeleton: Skeleton3D) -> void:
	_hips = skeleton.find_bone("Hips")
	_back[0] = skeleton.find_bone("Spine")
	_back[1] = skeleton.find_bone("Neck")
	_back[2] = skeleton.find_bone("Head")


func _layer(skeleton: Skeleton3D, delta: float) -> void:
	var yaw: float = body.global_rotation.y
	if _gate <= 0.0 or not _seeded or _hips < 0:
		_feet_yaw = yaw
		_pitch = 0.0
		_seeded = true
		return
	var moving: float = clampf(motion.speed / MOVING_SPEED, 0.0, 1.0)
	var lead: float = angle_difference(_feet_yaw, yaw)
	var free: float = deg_to_rad(stand_free_degrees) * (1.0 - moving)
	var owed: float = lead - clampf(lead, -free, free)
	var rate: float = follow_rate * lerpf(1.0, MOVING_FOLLOW, moving)
	lead -= owed * (1.0 - exp(-rate * delta))
	var limit: float = deg_to_rad(twist_limit_degrees) * (armed_share if motion.holding else 1.0)
	lead = clampf(lead, -limit, limit)
	_feet_yaw = wrapf(yaw - lead, -PI, PI)

	var head_pitch: float = body.head.rotation.x if body.head != null and not motion.holding else 0.0
	var bend: float = deg_to_rad(pitch_limit_degrees)
	var want: float = clampf(head_pitch * pitch_share, -bend, bend)
	_pitch = lerpf(_pitch, want, 1.0 - exp(-PITCH_RATE * delta))

	var twist: float = lead * _gate
	_turn(skeleton, _hips, Basis(Vector3.UP, -twist))
	for i: int in 3:
		var turn: Basis = Basis(PITCH_AXIS, _pitch * _gate * PITCH_SHARE[i]) * Basis(Vector3.UP, twist * TURN_SHARE[i])
		_turn(skeleton, _back[i], turn)
