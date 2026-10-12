extends "res://tools/capture/stages/stage.gd"

## polish shot 1 (L1 opener a). Ryan: "closeup shot of the prisoner's face from below, kinda a funny shot".
## [code]--stage=polish_face --shot=s1_cave --bots=1 --look=social --seconds=5.2[/code], cut in 1.2 s for 4 s.

# One prisoner on bare S1 deck at 42 deg r 51 (probe --floor: 38-46 deg holds no
# spire; --clear: 0-71 deg no pad or trap), facing a lens 0.7 m out,
# the S1 spires at 48-58 deg behind him. The rig's look pitch never reaches the
# model, so the head acts through a plugin-local modifier on Spine/Neck/Head.
# Dials (--set=): deg (42), r (51), dist (0.7), cam_h (0.35), fov (44), near (0: off).
# Shot 8 is --set=near=0.6: the same line of sight 0.6 m off the face, the lens
# fixed, the head held bowed; only the rig's idle breath (3 deg of spine, 3.2 s) moves.

## Where he stands: bare deck in the S1 pocket, spires behind him.
const BODY_DEG: float = 42.0
const BODY_R: float = 51.0
## Lens 0.7 m in front, 0.35 m over the deck: right under the chin.
const CAM_DIST: float = 0.7
const CAM_H: float = 0.35
## Vertical fov: the face near a quarter of the frame (70 held the whole body, face small).
const CAM_FOV: float = 44.0
## Degrees the view sits under the face, so the face rides the upper-middle.
const FACE_ABOVE_CENTRE: float = 6.0
## A handheld drift in metres, slow enough to read as a person holding it.
const DRIFT: float = 0.025
## Spring for the head: omega (rad/s) and damping ratio under 1 for an overshoot.
const HEAD_OMEGA: float = 13.0
const HEAD_ZETA: float = 0.55

## The acting, seconds after the cast: [t, pitch down, yaw right, roll right] in degrees.
const BEATS: Array = [
	[0.0, 30.0, 0.0, 0.0],      # peering down into the lens
	[0.75, 34.0, 4.0, 6.0],     # a curious tilt
	[1.35, 14.0, 34.0, -3.0],   # a glance aside, off to his right
	[2.0, 33.0, -3.0, 2.0],     # back down at the lens
	[2.7, 40.0, 2.0, -8.0],     # leans in, a squint closer
	[3.35, 16.0, -30.0, 4.0],   # the other side
	[3.95, 31.0, 1.0, 9.0],     # back, head cocked
	[4.6, 36.0, -5.0, -4.0],
]


## Bends Neck, Head and Spine after the AnimationPlayer poses them (plugin-local).
class HeadBend extends SkeletonModifier3D:
	var bones: Array = []      # [bone index, share, last written, its base]
	var bend: Vector3 = Vector3.ZERO   # pitch, yaw, roll in radians
	var head: int = -1
	var head_up: Vector3 = Vector3.UP   # skeleton space, after the bend
	var runs: int = 0

	func _process_modification_with_delta(_delta: float) -> void:
		_apply()

	func _process_modification() -> void:
		_apply()

	func _apply() -> void:
		var skeleton: Skeleton3D = get_skeleton()
		if skeleton == null:
			return
		for entry: Array in bones:
			var bone: int = int(entry[0])
			var now: Quaternion = skeleton.get_bone_pose_rotation(bone)
			# A frame the animation did not re-pose still holds last frame's bend.
			var base: Quaternion = entry[3] if entry[2] != null and now.is_equal_approx(entry[2]) else now
			var q := Quaternion.from_euler(bend * float(entry[1]))
			entry[3] = base
			entry[2] = q * base
			skeleton.set_bone_pose_rotation(bone, entry[2])
		runs += 1
		if head >= 0:
			head_up = skeleton.get_bone_global_pose(head).basis.y.normalized()


var _body: PlayerController = null
var _skeleton: Skeleton3D = null
var _head_bone: int = -1
var _bend: HeadBend = null
var _cast_at: float = 0.0
var _angle: Vector3 = Vector3.ZERO
var _speed: Vector3 = Vector3.ZERO
var _reported: bool = false
## Shot 8: metres from the face along shot 1's sight line; 0 keeps shot 1.
var _near: float = 0.0
var _fixed: Transform3D = Transform3D.IDENTITY
var _fixed_set: bool = false


func bots() -> int:
	return 1


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	var deg: float = float(option("deg", BODY_DEG))
	var r: float = float(option("r", BODY_R))
	var dist: float = float(option("dist", CAM_DIST))
	_body = runners[0].controller
	_near = float(option("near", 0.0))
	var at: Vector3 = LIB.ring_point(deg, r, 0.1)
	var lens_at: Vector3 = LIB.ring_point(deg - rad_to_deg(dist / r), r, 0.1)
	drive(runners[0], [
		{"do": "place", "at": at, "face": LIB.toward(at, lens_at)},
		{"do": "hold", "seconds": 60.0, "sway": 0.0 if _near > 0.0 else 3.5, "period": 3.3},
	], 0)
	stage_body(_body)
	_cast_at = elapsed()
	_skeleton = LIB.find_kind(_body, "Skeleton3D") as Skeleton3D
	if _skeleton != null:
		_head_bone = _skeleton.find_bone("Head")
		_bend = HeadBend.new()
		_bend.name = "ClipHeadBend"
		_bend.head = _head_bone
		for pair: Array in [["Spine", 0.18], ["Neck", 0.37], ["Head", 0.45]]:
			var index: int = _skeleton.find_bone(String(pair[0]))
			if index >= 0:
				_bend.bones.append([index, pair[1], null, Quaternion.IDENTITY])
		_skeleton.add_child(_bend)
	var first: Array = BEATS[0]
	_angle = Vector3(first[1], first[2], first[3])
	say("polish_face: %s at %.1f deg r %.1f, lens %.2f m out; bent bones %d" % [_body.name, deg, r, dist, _bend.bones.size() if _bend != null else -1])
	return true


func tick(delta: float) -> void:
	if _bend == null:
		return
	if _near > 0.0:
		var bow: Array = BEATS[0]
		_bend.bend = Vector3(deg_to_rad(float(bow[1])), 0.0, 0.0)
		return
	var goal: Vector3 = _goal(elapsed() - _cast_at)
	# An underdamped spring: every look overshoots a touch and settles.
	var accel: Vector3 = (goal - _angle) * HEAD_OMEGA * HEAD_OMEGA - _speed * 2.0 * HEAD_ZETA * HEAD_OMEGA
	_speed += accel * delta
	_angle += _speed * delta
	var wobble: float = elapsed() * 1.7
	var pitch: float = _angle.x + sin(wobble * 2.3) * 1.2
	var yaw: float = _angle.y + sin(wobble * 1.3 + 0.7) * 1.5
	_bend.bend = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(_angle.z))
	if not _reported and elapsed() - _cast_at > 1.0 and _head_bone >= 0:
		_reported = true
		var up: Vector3 = (_skeleton.global_transform.basis * _bend.head_up).normalized()
		var facing: Vector3 = -_body.global_transform.basis.z
		var to_lens: Vector3 = LIB.toward(_body.global_position, camera().global_position)
		say("head bend ran %d times; head-up . facing = %.2f; facing . to_lens = %.2f" % [_bend.runs, up.dot(facing), facing.dot(to_lens)])


## The held beat at [param t], stepping (the spring does the easing).
func _goal(t: float) -> Vector3:
	var pick: Array = BEATS[0]
	for beat: Array in BEATS:
		if t >= float(beat[0]):
			pick = beat
	return Vector3(pick[1], pick[2], pick[3])


## The worm's-eye lens: fixed under his chin with a small handheld drift,
## looking up at the head bone, the face above centre.
func lens(_delta: float) -> bool:
	if _body == null or not is_instance_valid(_body) or camera() == null:
		return false
	var deg: float = float(option("deg", BODY_DEG))
	var r: float = float(option("r", BODY_R))
	var dist: float = float(option("dist", CAM_DIST))
	var t: float = elapsed()
	var drift := Vector3(sin(t * 0.9) * DRIFT, sin(t * 1.3 + 1.1) * DRIFT * 0.6, sin(t * 0.7 + 2.0) * DRIFT * 0.5)
	var eye: Vector3 = LIB.ring_point(deg - rad_to_deg(dist / r), r, float(option("cam_h", CAM_H))) + drift
	var face: Vector3 = _body.global_position + Vector3.UP * 1.6
	if _skeleton != null and _head_bone >= 0:
		face = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)).origin + Vector3.UP * 0.08
	if _near > 0.0:
		# Fixed once, before the cut, so the breath moves in the frame.
		if not _fixed_set:
			# The Head bone sits at the neck joint; the face is 0.13 m up the bone.
			var head: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)
			face = head.origin + head.basis.y.normalized() * 0.13
			var from: Vector3 = LIB.ring_point(deg - rad_to_deg(dist / r), r, float(option("cam_h", CAM_H)))
			_fixed = Transform3D(Basis.IDENTITY, face + (from - face).normalized() * _near).looking_at(face, Vector3.UP)
			_fixed_set = elapsed() - _cast_at > 0.3
		camera().global_transform = _fixed
	else:
		camera().global_position = eye
		camera().look_at(face, Vector3.UP)
		camera().rotate_object_local(Vector3.RIGHT, -deg_to_rad(FACE_ABOVE_CENTRE))
	camera().fov = float(option("fov", CAM_FOV))
	camera().current = true
	return true
