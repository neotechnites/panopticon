extends "res://scripts/player/body_layer.gd"

## What happens to a body shows on it: a landing squashes it by how hard it came down, a throw (a shove, a pad)
## reels it along the throw, and a rifle round passing close makes it duck away. Each recovers on a spring.

## Seconds a reel's and a flinch's pull lasts before the spring is left to recover.
const REEL_SECONDS: float = 0.35
const FLINCH_SECONDS: float = 0.25
## The reel and flinch springs against the squash's: quicker in.
const REEL_HERTZ: float = 1.5
const FLINCH_HERTZ: float = 2.6
## A rise this fast, m/s in one sample, with no jump behind it is a throw; so is this much sideways change.
const THROWN_RISE: float = 3.0
const THROWN_JOLT: float = 7.0
## The speed a thrown body must be left with, the throw that reels it fully, and the least a throw reels.
const THROWN_SPEED: float = 5.0
const FULL_THROW: float = 16.0
const LEAST_REEL: float = 0.4
## Seconds after a landing in which a change of speed is the landing's own.
const LANDING_SECONDS: float = 0.15
## Metres from the muzzle inside which the body is the one shooting; and the chest's height.
const SHOOTER_METRES: float = 3.0
const CHEST_HEIGHT: float = 1.1
## Radians the chest folds per metre of squash; metres the hips drop at a full flinch.
const SQUASH_FOLD: float = 1.1
const FLINCH_DROP: float = 0.14
## How the reel is shared: hips into the throw, chest with it, head and arms whipped back; arms thrown wide.
const REEL_HIPS: float = 0.45
const REEL_SPINE: float = 0.35
const REEL_HEAD: float = -0.6
const REEL_ARMS: float = -1.0
const REEL_SPREAD: float = 0.9

## Centimetres the hips drop per m/s of landing speed, and the most they drop.
@export_range(0.0, 5.0, 0.1) var squash_centimetres: float = 1.5
@export_range(0.0, 50.0, 1.0) var squash_limit_centimetres: float = 26.0
## Degrees a full shove reels the body.
@export_range(0.0, 60.0, 1.0) var reel_degrees: float = 30.0
## Degrees the chest and head duck at a round passing dead close, and how close counts, metres.
@export_range(0.0, 45.0, 1.0) var flinch_degrees: float = 28.0
@export_range(0.0, 5.0, 0.1) var near_miss_metres: float = 1.6
## The recovery spring: cycles a second, and how soon it settles (1 never overshoots).
@export_range(0.5, 10.0, 0.1) var spring_hertz: float = 2.6
@export_range(0.1, 1.5, 0.05) var damping: float = 0.55

var _hips: int = -1
var _spine: int = -1
var _head: int = -1
var _arms: PackedInt32Array = PackedInt32Array([-1, -1])
## Each spring as (value, velocity); the squash is kicked, the other two chase a pull that fades.
var _squash: Vector2 = Vector2.ZERO
var _reel_x: Vector2 = Vector2.ZERO
var _reel_z: Vector2 = Vector2.ZERO
var _reel_pull: Vector2 = Vector2.ZERO
var _flinch: Vector2 = Vector2.ZERO
var _flinch_pull: float = 0.0
## Model space, unit: away from the round that passed.
var _flinch_away: Vector2 = Vector2.RIGHT
var _jumped: bool = false
var _landing: float = 0.0
var _seen_shot: int = 0


func _bound(skeleton: Skeleton3D) -> void:
	_hips = skeleton.find_bone("Hips")
	_spine = skeleton.find_bone("Spine")
	_head = skeleton.find_bone("Head")
	_arms[0] = skeleton.find_bone("UpperArm.L")
	_arms[1] = skeleton.find_bone("UpperArm.R")
	_seen_shot = Rifle.shot_serial()
	body.landed.connect(_on_landed)
	body.jumped.connect(_on_jumped)


func _on_landed(impact_speed: float) -> void:
	_jumped = false
	_landing = LANDING_SECONDS
	var drop: float = minf(impact_speed * squash_centimetres, squash_limit_centimetres) * 0.01
	_squash.y += _kick(drop, spring_hertz, damping)


func _on_jumped() -> void:
	_jumped = true


func _layer(skeleton: Skeleton3D, delta: float) -> void:
	_watch_for_a_throw(delta)
	_watch_for_a_round()
	if _gate <= 0.0 or _hips < 0:
		_squash = Vector2.ZERO
		_reel_x = Vector2.ZERO
		_reel_z = Vector2.ZERO
		_flinch = Vector2.ZERO
		_reel_pull = Vector2.ZERO
		_flinch_pull = 0.0
		return
	_squash = _spring(_squash, 0.0, spring_hertz, damping, delta)
	_reel_x = _spring(_reel_x, _reel_pull.x, spring_hertz * REEL_HERTZ, damping, delta)
	_reel_z = _spring(_reel_z, _reel_pull.y, spring_hertz * REEL_HERTZ, damping, delta)
	_flinch = _spring(_flinch, _flinch_pull, spring_hertz * FLINCH_HERTZ, damping, delta)
	_reel_pull *= exp(-delta / REEL_SECONDS)
	_flinch_pull *= exp(-delta / FLINCH_SECONDS)

	var squash: float = clampf(_squash.x, -0.03, squash_limit_centimetres * 0.01) * _gate
	var reel: Vector2 = Vector2(_reel_x.x, _reel_z.x) * deg_to_rad(reel_degrees) * _gate
	var flinch: float = _flinch.x * _gate
	if absf(squash) < 0.0005 and reel.length_squared() < 0.000001 and absf(flinch) < 0.001:
		return
	var duck: float = flinch * deg_to_rad(flinch_degrees)

	var hips: Transform3D = skeleton.get_bone_global_pose(_hips)
	hips.basis = _tilt(reel * REEL_HIPS) * hips.basis
	hips.origin.y -= squash + flinch * FLINCH_DROP
	skeleton.set_bone_global_pose(_hips, hips)
	var fold: Vector2 = Vector2(0.0, squash * SQUASH_FOLD + duck * 0.6)
	_turn(skeleton, _spine, _tilt(reel * REEL_SPINE + fold + _flinch_away * duck * 0.6))
	_turn(skeleton, _head, _tilt(reel * REEL_HEAD + Vector2(0.0, duck * 0.4 - squash * SQUASH_FOLD * 0.5)))
	# Arms: whipped back by a throw and thrown wide, flared by a landing, brought up by a flinch.
	var spread: float = reel.length() * REEL_SPREAD + squash * SQUASH_FOLD + duck * 0.6
	var whip: Basis = _tilt(reel * REEL_ARMS + Vector2(0.0, -duck))
	_turn(skeleton, _arms[0], whip * Basis(Vector3.BACK, spread))
	_turn(skeleton, _arms[1], whip * Basis(Vector3.BACK, -spread))


## A body flung upward with no jump behind it, or jolted sideways and left moving, was thrown.
func _watch_for_a_throw(delta: float) -> void:
	_landing = maxf(_landing - delta, 0.0)
	var change: Vector3 = motion.step
	var flat: Vector3 = Vector3(change.x, 0.0, change.z)
	var rose: bool = change.y >= THROWN_RISE and motion.velocity.y > 0.0 and not _jumped
	var jolted: bool = flat.length() >= THROWN_JOLT and _landing <= 0.0
	if not (rose or jolted) or motion.speed < THROWN_SPEED:
		return
	var along: Vector3 = motion.to_model * flat / FULL_THROW
	var pull: Vector2 = Vector2(along.x, along.z).limit_length(1.0)
	if pull.length() < LEAST_REEL:
		pull = pull.normalized() * LEAST_REEL if pull.length() > 0.01 else Vector2(0.0, LEAST_REEL)
	_reel_pull = pull
	# Thrown, not jumped: the next landing is the throw's.
	_jumped = true


## A rifle round whose line passed within reach of the chest, on a body that did not fire it.
func _watch_for_a_round() -> void:
	var serial: int = Rifle.shot_serial()
	if serial == _seen_shot:
		return
	_seen_shot = serial
	if near_miss_metres <= 0.0 or body.is_guard:
		return
	var chest: Vector3 = body.global_position + Vector3(0.0, CHEST_HEIGHT, 0.0)
	var origin: Vector3 = Rifle.shot_origin()
	if origin.distance_to(chest) < SHOOTER_METRES:
		return
	var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(chest, origin, Rifle.shot_end())
	var off: Vector3 = chest - nearest
	var miss: float = off.length()
	if miss > near_miss_metres:
		return
	_flinch_pull = maxf(_flinch_pull, 1.0 - 0.5 * miss / near_miss_metres)
	var away: Vector3 = motion.to_model * off
	if Vector2(away.x, away.z).length() > 0.05:
		_flinch_away = Vector2(away.x, away.z).normalized()
