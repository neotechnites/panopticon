extends "res://scripts/player/body_layer.gd"

## Weight on springs: the body leans into a start, a stop and a turn from the feet up; head, chest and arms
## trail a beat behind and settle; each footfall of the run dips the hips.

## How the lag is shared: spine, then head on top of it; and how far the arms swing the other way.
const TRAIL_SPINE: float = 0.4
const TRAIL_HEAD: float = 0.6
const TRAIL_ARMS: float = 1.5
## The trailing spring against the lean's: it chases the lean slower and looser, so it arrives late and overshoots.
const TRAIL_HERTZ: float = 0.6
const TRAIL_DAMPING: float = 0.7
## The footfall spring against the lean's.
const BOB_HERTZ: float = 2.6
## Radians the chest nods per metre of dip.
const BOB_NOD: float = 1.6
## A foot this far, metres, above its lowest is in the air; and the least seconds between two footfalls of one foot.
const FOOT_LIFT: float = 0.05
const FOOT_GAP: float = 0.12
## The pace below which a body is not running, so nothing lands.
const BOB_PACE: float = 0.2

## Degrees the whole body leans when its speed changes by its whole ground speed in a beat.
@export_range(0.0, 30.0, 0.5) var lean_degrees: float = 14.0
## How much of the lean the head, chest and arms arrive late by, then swing past (0 rides rigid).
@export_range(0.0, 2.0, 0.05) var trail_share: float = 1.0
## Centimetres the hips dip on each footfall at full pace.
@export_range(0.0, 10.0, 0.1) var bounce_centimetres: float = 3.0
## The lean spring: cycles a second, and how soon it settles (1 never overshoots).
@export_range(0.5, 8.0, 0.1) var spring_hertz: float = 2.2
@export_range(0.1, 1.5, 0.05) var damping: float = 0.5

var _hips: int = -1
var _spine: int = -1
var _head: int = -1
var _arms: PackedInt32Array = PackedInt32Array([-1, -1])
var _feet: PackedInt32Array = PackedInt32Array([-1, -1])
## Each spring as (value, velocity): lean and trail per model axis, then the dip in metres.
var _lean_x: Vector2 = Vector2.ZERO
var _lean_z: Vector2 = Vector2.ZERO
var _trail_x: Vector2 = Vector2.ZERO
var _trail_z: Vector2 = Vector2.ZERO
var _bob: Vector2 = Vector2.ZERO
var _foot_height: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _foot_falling: PackedByteArray = PackedByteArray([0, 0])
var _foot_wait: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _foot_floor: float = 0.0


func _bound(skeleton: Skeleton3D) -> void:
	_hips = skeleton.find_bone("Hips")
	_spine = skeleton.find_bone("Spine")
	_head = skeleton.find_bone("Head")
	_arms[0] = skeleton.find_bone("UpperArm.L")
	_arms[1] = skeleton.find_bone("UpperArm.R")
	_feet[0] = skeleton.find_bone("Foot.L")
	_feet[1] = skeleton.find_bone("Foot.R")
	if _feet[0] >= 0:
		_foot_floor = skeleton.get_bone_global_rest(_feet[0]).origin.y


func _layer(skeleton: Skeleton3D, delta: float) -> void:
	if _gate <= 0.0 or _hips < 0:
		_lean_x = Vector2.ZERO
		_lean_z = Vector2.ZERO
		_trail_x = Vector2.ZERO
		_trail_z = Vector2.ZERO
		_bob = Vector2.ZERO
		return
	var push: Vector2 = Vector2.ZERO if motion.sliding else Vector2(motion.surge.x, motion.surge.z).limit_length(1.0)
	var lean: float = deg_to_rad(lean_degrees)
	_lean_x = _spring(_lean_x, push.x * lean, spring_hertz, damping, delta)
	_lean_z = _spring(_lean_z, push.y * lean, spring_hertz, damping, delta)
	_trail_x = _spring(_trail_x, _lean_x.x, spring_hertz * TRAIL_HERTZ, damping * TRAIL_DAMPING, delta)
	_trail_z = _spring(_trail_z, _lean_z.x, spring_hertz * TRAIL_HERTZ, damping * TRAIL_DAMPING, delta)
	_footfalls(skeleton, delta)
	_bob = _spring(_bob, 0.0, spring_hertz * BOB_HERTZ, damping, delta)
	var dip: float = clampf(_bob.x, -0.01 * bounce_centimetres * 2.0, 0.01 * bounce_centimetres) * _gate

	# The lean pivots on the ground between the feet, so the feet stay where the clip put them.
	var tilt: Basis = _tilt(Vector2(_lean_x.x, _lean_z.x) * _gate)
	var hips: Transform3D = skeleton.get_bone_global_pose(_hips)
	hips.basis = tilt * hips.basis
	hips.origin = tilt * hips.origin + Vector3(0.0, dip, 0.0)
	skeleton.set_bone_global_pose(_hips, hips)

	var behind: Vector2 = Vector2(_trail_x.x - _lean_x.x, _trail_z.x - _lean_z.x) * trail_share * _gate
	_turn(skeleton, _spine, _tilt(behind * TRAIL_SPINE + Vector2(0.0, -dip * BOB_NOD)))
	_turn(skeleton, _head, _tilt(behind * TRAIL_HEAD))
	var swing: Basis = _tilt(behind * -TRAIL_ARMS)
	_turn(skeleton, _arms[0], swing)
	_turn(skeleton, _arms[1], swing)


## Kick the dip spring when a foot of the running clip comes down.
func _footfalls(skeleton: Skeleton3D, delta: float) -> void:
	var running: bool = motion.grounded and not motion.sliding and motion.pace > BOB_PACE
	for i: int in 2:
		if _feet[i] < 0:
			continue
		var height: float = skeleton.get_bone_global_pose(_feet[i]).origin.y
		var falling: bool = height < _foot_height[i] - 0.0001
		_foot_wait[i] = maxf(_foot_wait[i] - delta, 0.0)
		if running and _foot_falling[i] == 1 and not falling and height < _foot_floor + FOOT_LIFT and _foot_wait[i] <= 0.0:
			_bob.y -= _kick(0.01 * bounce_centimetres * minf(motion.pace, 1.5), spring_hertz * BOB_HERTZ, damping)
			_foot_wait[i] = FOOT_GAP
		if absf(height - _foot_height[i]) > 0.0001:
			_foot_falling[i] = 1 if falling else 0
		_foot_height[i] = height
