extends "res://scripts/player/body_layer.gd"

## Feet that plant: a ray under each foot finds the ground, the hips drop to the lower one and each leg is
## re-solved onto its own. Off stops the rays; the legs still take up whatever the other layers do to the hips.

## SAMPLE runs first and remembers where the clip put the legs; SOLVE runs after the other layers.
enum Stage { SAMPLE, SOLVE }

## Metres above the body's origin a ray starts from.
const RAY_TOP: float = 0.6
## A hit this far, metres, from where the foot now is is stale.
const STALE_METRES: float = 0.7
## Ground steeper than this (its normal's y) is a wall, not a footing.
const FOOTING_NORMAL_Y: float = 0.5
## Per second, how fast the legs take up and give back the hold on their footing.
const PIN_RATE: float = 12.0
## The share of full length a leg is straightened to, and the most the hips sink to give a leg reach, metres.
const STRAIGHT: float = 0.995
const SINK_LIMIT: float = 0.3
## A fall faster than this, m/s, with ground this many seconds away, has the legs reach for it.
const BRACE_FALL: float = 2.0
const BRACE_LEAD: float = 0.22
## Metres below the body a ray looks for that ground; seconds the reach takes, and the stand lasts after landing.
const BRACE_REACH: float = 3.0
const BRACE_IN: float = 0.12
const BRACE_OUT: float = 0.3
## Metres the reaching feet are held short of straight.
const BRACE_TUCK: float = 0.08

## Centimetres a foot will go down, and up, off the clip to find ground.
@export_range(0.0, 80.0, 1.0) var reach_down_centimetres: float = 40.0
@export_range(0.0, 80.0, 1.0) var step_up_centimetres: float = 40.0
## Per second, how fast feet and hips follow a change of ground.
@export_range(1.0, 60.0, 1.0) var settle_rate: float = 16.0
## Planting is whole at or below the first speed, m/s, and gone by the second.
@export_range(0.0, 40.0, 0.5) var full_speed: float = 4.5
@export_range(0.0, 40.0, 0.5) var off_speed: float = 8.0
## The share of the ground's slope each sole takes.
@export_range(0.0, 1.0, 0.05) var sole_tilt: float = 0.7
## What counts as ground: the map's layers.
@export_flags_3d_physics var ground_mask: int = 1

var stage: Stage = Stage.SOLVE
## The SOLVE stage, which holds the state both read.
var lead: Node = null

var _hips: int = -1
## Left then right, for every per-leg array below.
var _thighs: PackedInt32Array = PackedInt32Array([-1, -1])
var _shins: PackedInt32Array = PackedInt32Array([-1, -1])
var _feet: PackedInt32Array = PackedInt32Array([-1, -1])
var _thigh_length: float = 0.0
var _shin_length: float = 0.0
var _rays: Array[RayCast3D] = [null, null]
## The clip's own pose, model space, taken by SAMPLE.
var _clip_hips: Transform3D = Transform3D.IDENTITY
var _clip_knee: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _clip_foot: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
## Metres each foot, and the hips, sit off the clip; and each foot's ground normal, model space.
var _offset: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _pelvis: float = 0.0
var _normal: PackedVector3Array = PackedVector3Array([Vector3.UP, Vector3.UP])
var _found: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _footing: PackedByteArray = PackedByteArray([0, 0])
## 0 to 1: how firmly the feet hold their footing against the hips moving.
var _pin: float = 0.0
## 0 to 1: how far the legs have left the clip for a stand, reaching for a landing. Each foot's stand, model space and off the hips.
var _brace: float = 0.0
var _stand_foot: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _hips_to_stand: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _sampled: bool = false


func _bound(skeleton: Skeleton3D) -> void:
	_hips = skeleton.find_bone("Hips")
	for i: int in 2:
		var side: String = "L" if i == 0 else "R"
		_thighs[i] = skeleton.find_bone("Thigh." + side)
		_shins[i] = skeleton.find_bone("Shin." + side)
		_feet[i] = skeleton.find_bone("Foot." + side)
	if _hips < 0 or _thighs[1] < 0 or _shins[1] < 0 or _feet[1] < 0:
		_hips = -1
		return
	_thigh_length = skeleton.get_bone_rest(_shins[0]).origin.length()
	_shin_length = skeleton.get_bone_rest(_feet[0]).origin.length()
	for i: int in 2:
		var ray: RayCast3D = RayCast3D.new()
		ray.name = "Ground%d" % i
		ray.top_level = true
		ray.enabled = false
		ray.collision_mask = ground_mask
		ray.target_position = Vector3(0.0, -(RAY_TOP + BRACE_REACH), 0.0)
		_stand_foot[i] = skeleton.get_bone_global_rest(_feet[i])
		_hips_to_stand[i] = skeleton.get_bone_global_rest(_hips).affine_inverse() * _stand_foot[i]
		add_child(ray)
		ray.add_exception(body)
		_rays[i] = ray
	var sampler: SkeletonModifier3D = (get_script() as GDScript).new()
	sampler.name = "FootSample"
	sampler.stage = Stage.SAMPLE
	sampler.lead = self
	skeleton.add_child(sampler)
	skeleton.move_child(sampler, 0)
	sampler.body = body
	sampler.motion = motion


func _layer(skeleton: Skeleton3D, delta: float) -> void:
	if stage == Stage.SAMPLE:
		lead._sample(skeleton)
	elif _hips >= 0 and _sampled:
		_solve(skeleton, delta)


## Remember the clip's legs before any layer moves the hips, and put each ray over its foot.
func _sample(skeleton: Skeleton3D) -> void:
	if _hips < 0:
		return
	_sampled = true
	_clip_hips = skeleton.get_bone_global_pose(_hips)
	var world: Transform3D = skeleton.global_transform
	for i: int in 2:
		_clip_knee[i] = skeleton.get_bone_global_pose(_shins[i]).origin
		_clip_foot[i] = skeleton.get_bone_global_pose(_feet[i])
		if _brace > 0.0:
			# A body about to land, or just down, stands on its feet whatever the airborne clip is doing.
			_clip_foot[i] = _clip_foot[i].interpolate_with(_stand_foot[i], _brace)
		if _rays[i].enabled:
			var foot: Vector3 = _clip_foot[i].origin
			_rays[i].global_position = world * Vector3(foot.x, RAY_TOP, foot.z)


func _solve(skeleton: Skeleton3D, delta: float) -> void:
	var up: bool = motion.live and not motion.limp and not motion.sliding
	var standing: bool = up and motion.grounded
	var falling: bool = up and not motion.grounded and motion.velocity.y < -BRACE_FALL
	_pin = 0.0 if motion.limp else move_toward(_pin, 1.0 if standing else 0.0, delta * PIN_RATE)
	var seek: float = _gate * (1.0 - smoothstep(full_speed, maxf(off_speed, full_speed + 0.01), motion.speed))
	var looking: bool = (seek > 0.0 and _pin > 0.0) or (falling and _gate > 0.0)
	for i: int in 2:
		if _rays[i].enabled != looking:
			_rays[i].enabled = looking
	var world: Transform3D = skeleton.global_transform
	# Legs reach for ground that is coming, and hold the stand through the landing.
	if falling and _gate > 0.0 and _gap_below(world) < -motion.velocity.y * BRACE_LEAD:
		_brace = move_toward(_brace, 1.0, delta / BRACE_IN)
	else:
		_brace = move_toward(_brace, 0.0, delta / (BRACE_OUT if standing else BRACE_IN))
	if motion.limp:
		_brace = 0.0
	if _pin <= 0.0 and _brace <= 0.0:
		_offset[0] = 0.0
		_offset[1] = 0.0
		_pelvis = 0.0
		return

	var hips: Transform3D = skeleton.get_bone_global_pose(_hips)
	# The feet go round with the hips' turn and hold against everything else the layers did to them.
	var carried: Vector3 = hips.basis * (_clip_hips.basis.inverse() * Vector3.BACK)
	var turn: Basis = Basis(Vector3.UP, atan2(carried.x, carried.z))
	var lowest: float = 0.0
	var any: bool = false
	for i: int in 2:
		var at: Vector3 = _clip_hips.origin + turn * (_clip_foot[i].origin - _clip_hips.origin)
		_footing[i] = 1 if seek > 0.0 and _pin > 0.0 and _find_ground(i, world, at) else 0
		if _footing[i] == 1 and (not any or _found[i] < lowest):
			lowest = _found[i]
			any = true
	var blend: float = 1.0 - exp(-settle_rate * delta)
	_pelvis = lerpf(_pelvis, lowest * seek, blend)
	for i: int in 2:
		var goal: float = _found[i] if _footing[i] == 1 else lowest
		_offset[i] = lerpf(_offset[i], goal * seek, blend)
		if _footing[i] == 0:
			_normal[i] = _normal[i].lerp(Vector3.UP, blend)

	var moved: bool = hips.origin.distance_squared_to(_clip_hips.origin) > 0.00000025 \
		or not hips.basis.is_equal_approx(_clip_hips.basis)
	if not moved and _brace <= 0.0 and absf(_pelvis) < 0.0005 and absf(_offset[0]) < 0.0005 and absf(_offset[1]) < 0.0005:
		return

	hips.origin.y += _pelvis * _pin
	# Hips drop to keep both legs in reach.
	var sink: float = 0.0
	var full: float = (_thigh_length + _shin_length) * STRAIGHT
	for i: int in 2:
		var joint: Vector3 = hips * skeleton.get_bone_pose_position(_thighs[i])
		var ankle: Vector3 = _clip_hips.origin + turn * (_clip_foot[i].origin - _clip_hips.origin)
		ankle.y += _offset[i]
		var flat: float = Vector2(ankle.x - joint.x, ankle.z - joint.z).length_squared()
		if flat < full * full:
			sink = maxf(sink, (joint.y - ankle.y) - sqrt(full * full - flat))
	hips.origin.y -= minf(sink, SINK_LIMIT) * _pin
	skeleton.set_bone_global_pose(_hips, hips)

	var hold: float = maxf(_pin, _brace)
	for i: int in 2:
		var held: Transform3D = Transform3D(turn * _clip_foot[i].basis, _clip_hips.origin + turn * (_clip_foot[i].origin - _clip_hips.origin))
		held.origin.y += _offset[i]
		if sole_tilt > 0.0 and _normal[i].y < 0.9999:
			var sole: Vector3 = Vector3.UP.lerp(_normal[i], sole_tilt * seek).normalized()
			held.basis = Basis(Quaternion(Vector3.UP, sole)) * held.basis
		if _pin < 1.0:
			# Off the ground the stand hangs under the hips, a little tucked, not on the floor.
			var hung: Transform3D = hips * _hips_to_stand[i]
			hung.origin.y += BRACE_TUCK
			held = hung.interpolate_with(held, _pin)
		var loose: Transform3D = skeleton.get_bone_global_pose(_feet[i])
		var clip_joint: Vector3 = _clip_hips * skeleton.get_bone_pose_position(_thighs[i])
		var bend: Vector3 = (turn * (_clip_knee[i] - clip_joint)).lerp(turn * Vector3.BACK * 0.3, _brace)
		_solve_leg(skeleton, i, loose.interpolate_with(held, hold), bend, turn * Vector3.BACK)


## Metres from the body's floor down to the nearest ground either ray saw; huge when neither did.
func _gap_below(world: Transform3D) -> float:
	var gap: float = 1000.0
	for i: int in 2:
		var ray: RayCast3D = _rays[i]
		if ray.enabled and ray.is_colliding() and not (ray.get_collider() is CharacterBody3D):
			gap = minf(gap, world.origin.y - ray.get_collision_point().y)
	return gap


## Where the ground is under foot [param i], as metres off the body's own floor; false when there is no footing.
func _find_ground(i: int, world: Transform3D, at: Vector3) -> bool:
	var ray: RayCast3D = _rays[i]
	if not ray.is_colliding():
		return false
	if ray.get_collider() is CharacterBody3D:
		ray.add_exception(ray.get_collider())
		return false
	var normal: Vector3 = ray.get_collision_normal()
	if normal.y < FOOTING_NORMAL_Y:
		return false
	var hit: Vector3 = ray.get_collision_point()
	var foot: Vector3 = world * at
	var away: Vector2 = Vector2(foot.x - hit.x, foot.z - hit.z)
	if away.length() > STALE_METRES:
		return false
	# The ray is a tick old: carry its hit along the ground's own plane to where the foot is now.
	var height: float = hit.y - (normal.x * away.x + normal.z * away.y) / normal.y - world.origin.y
	if height < -0.01 * reach_down_centimetres or height > 0.01 * step_up_centimetres:
		return false
	_found[i] = height
	_normal[i] = _normal[i].lerp(motion.to_model * normal, 0.3).normalized()
	return true


## Two-bone solve of leg [param i] onto [param foot], the knee bending the way the clip's did, else [param forward].
func _solve_leg(skeleton: Skeleton3D, i: int, foot: Transform3D, bend: Vector3, forward: Vector3) -> void:
	var thigh: Transform3D = skeleton.get_bone_global_pose(_thighs[i])
	var span: Vector3 = foot.origin - thigh.origin
	var length: float = span.length()
	if length < 0.001:
		return
	var a: float = _thigh_length
	var b: float = _shin_length
	var along: Vector3 = span / length
	var reach: float = clampf(length, absf(a - b) + 0.01, (a + b) * STRAIGHT)
	bend -= along * along.dot(bend)
	if bend.length_squared() < 0.0004:
		bend = forward - along * along.dot(forward)
	bend = bend.normalized()
	var down: float = (a * a - b * b + reach * reach) / (2.0 * reach)
	var knee: Vector3 = thigh.origin + along * down + bend * sqrt(maxf(a * a - down * down, 0.0))
	var ankle: Vector3 = thigh.origin + along * reach
	thigh.basis = _swing(thigh.basis, knee - thigh.origin)
	skeleton.set_bone_global_pose(_thighs[i], thigh)
	var shin: Transform3D = skeleton.get_bone_global_pose(_shins[i])
	shin.basis = _swing(shin.basis, ankle - knee)
	skeleton.set_bone_global_pose(_shins[i], shin)
	skeleton.set_bone_global_pose(_feet[i], Transform3D(foot.basis, ankle))


## [param basis] swung the short way so its +Y, which runs down these bones, lies along [param along].
func _swing(basis: Basis, along: Vector3) -> Basis:
	return Basis(Quaternion(basis.y.normalized(), along.normalized())) * basis
