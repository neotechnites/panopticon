extends SkeletonModifier3D

## The owner's own rifle arms: a copy of the body's skeleton hung on the eye, so they move rigidly with the view model.
## Everything but the arms is folded away behind the eye; each shoulder slides, off screen, until its palm reaches its anchor.

## Metres from the wrist joint to the middle of the mitten, as the third-person hold uses.
const PALM_REACH: float = 0.09
## Eye space (+X right, -Y down, -Z ahead): each shoulder, below the bottom of the frame. Right (grip) then left (fore-end).
const SHOULDERS: Array[Vector3] = [Vector3(0.14, -0.32, 0.08), Vector3(0.02, -0.42, -0.2)]
## Eye space: where each elbow bends toward, out and down.
const ELBOWS: Array[Vector3] = [Vector3(0.6, -0.9, 0.1), Vector3(-0.2, -1.0, -0.3)]
## Eye space: where the rest of the body is folded to, behind and below the eye.
const FOLD_POINT: Vector3 = Vector3(0.0, -0.45, 0.25)
## The share of full reach a palm is held at; past it the shoulder slides in.
const REACH_SHARE: float = 0.92
const FOLDED_SCALE: float = 0.001

## Grip then fore-end, the same two anchors the third-person hold reaches.
var anchors: Array[Node3D] = [null, null]
var _uppers: PackedInt32Array = PackedInt32Array([-1, -1])
var _lowers: PackedInt32Array = PackedInt32Array([-1, -1])
var _hands: PackedInt32Array = PackedInt32Array([-1, -1])
var _upper_length: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _lower_length: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Every bone that is not an arm, parents first.
var _folded: PackedInt32Array = PackedInt32Array()


## Resolve the arm bones by name; every other bone is folded.
func bind(skeleton: Skeleton3D, arm_names: Array[StringName]) -> void:
	var arm: Dictionary = {}
	for i in 2:
		_uppers[i] = skeleton.find_bone(String(arm_names[i]))
		_lowers[i] = skeleton.find_bone(String(arm_names[i + 2]))
		_hands[i] = skeleton.find_bone(String(arm_names[i + 4]))
		for bone: int in [_uppers[i], _lowers[i], _hands[i]]:
			arm[bone] = true
		var upper: Vector3 = skeleton.get_bone_global_rest(_uppers[i]).origin
		var lower: Vector3 = skeleton.get_bone_global_rest(_lowers[i]).origin
		_upper_length[i] = upper.distance_to(lower)
		_lower_length[i] = lower.distance_to(skeleton.get_bone_global_rest(_hands[i]).origin)
	var depth: Array[Vector2i] = []
	for bone in skeleton.get_bone_count():
		if arm.has(bone):
			continue
		var d: int = 0
		var p: int = skeleton.get_bone_parent(bone)
		while p >= 0:
			d += 1
			p = skeleton.get_bone_parent(p)
		depth.append(Vector2i(d, bone))
	depth.sort()
	for entry: Vector2i in depth:
		_folded.append(entry.y)


func _process_modification_with_delta(_delta: float) -> void:
	_pose()


func _process_modification() -> void:
	_pose()


func _pose() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or anchors[0] == null or anchors[1] == null or _uppers[1] < 0:
		return
	var eye: Node3D = skeleton.get_parent() as Node3D
	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse() * eye.global_transform
	var fold: Transform3D = Transform3D(Basis.from_scale(Vector3.ONE * FOLDED_SCALE), to_skeleton * FOLD_POINT)
	for bone: int in _folded:
		skeleton.set_bone_global_pose(bone, fold)
	var world_to_skeleton: Transform3D = skeleton.global_transform.affine_inverse()
	for i in 2:
		var anchor: Transform3D = world_to_skeleton * anchors[i].global_transform
		var hand: Basis = anchor.basis.orthonormalized()
		var wrist: Vector3 = anchor.origin - hand.y * PALM_REACH
		_reach(skeleton, i, to_skeleton * SHOULDERS[i], wrist, to_skeleton * ELBOWS[i], hand)


## Two-bone solve: shoulder slid along the arm to keep the wrist in reach, elbow bent toward the pole.
func _reach(skeleton: Skeleton3D, i: int, shoulder: Vector3, wrist: Vector3, pole: Vector3, hand: Basis) -> void:
	var a: float = _upper_length[i]
	var b: float = _lower_length[i]
	var span: Vector3 = wrist - shoulder
	var reach: float = (a + b) * REACH_SHARE
	if span.length() > reach:
		shoulder = wrist - span.normalized() * reach
		span = wrist - shoulder
	var dist: float = maxf(span.length(), absf(a - b) + 0.01)
	var along: Vector3 = span / dist
	var out: Vector3 = (pole - shoulder) - along * along.dot(pole - shoulder)
	out = out.normalized() if out.length() > 0.0001 else Vector3.DOWN
	var foot: float = (a * a - b * b + dist * dist) / (2.0 * dist)
	var elbow: Vector3 = shoulder + along * foot + out * sqrt(maxf(a * a - foot * foot, 0.0))
	var upper_dir: Vector3 = (elbow - shoulder).normalized()
	var lower_dir: Vector3 = (wrist - elbow).normalized()
	var hinge: Vector3 = upper_dir.cross(lower_dir)
	var upper_rest: Basis = skeleton.get_bone_global_rest(_uppers[i]).basis
	var upper: Basis = _aim(upper_rest, upper_dir, hinge)
	var lower: Basis = _aim(skeleton.get_bone_global_rest(_lowers[i]).basis, lower_dir, hand.x + upper.x)
	skeleton.set_bone_global_pose(_uppers[i], Transform3D(upper, shoulder))
	skeleton.set_bone_global_pose(_lowers[i], Transform3D(lower, elbow))
	skeleton.set_bone_global_pose(_hands[i], Transform3D(hand, wrist))


## [param rest] swung so its +Y runs along [param along], then twisted so its +X leans toward [param side].
func _aim(rest: Basis, along: Vector3, side: Vector3) -> Basis:
	var swung: Basis = Basis(Quaternion(rest.y.normalized(), along)) * rest.orthonormalized()
	var flat: Vector3 = side - along * along.dot(side)
	if flat.length() < 0.0001:
		return swung
	flat = flat.normalized()
	if flat.dot(swung.x) < 0.0:
		flat = -flat
	return Basis(flat, along, flat.cross(along)).orthonormalized()
