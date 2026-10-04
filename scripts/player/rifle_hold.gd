extends SkeletonModifier3D

## One stage of a body holding a rifle. LEAN bends the back to the aim, seats the rifle at the drawn eye
## within both arms' reach and parks the wrists for a TwoBoneIK3D; HANDS lays each palm on its anchor.

enum Stage { LEAN, HANDS }

## Metres from the wrist joint to the middle of the mitten.
const PALM_REACH: float = 0.09
## How the aim pitch is shared down the back: spine, neck, head. Sums to one.
const LEAN_SHARE: Array[float] = [0.45, 0.3, 0.25]
## Skeleton space: the model faces +Z, so a pitch up turns about -X.
const PITCH_AXIS: Vector3 = Vector3(-1.0, 0.0, 0.0)
## The drawn right eye at rest, skeleton space: where a third-person rifle's eye sits.
const EYE_REST: Vector3 = Vector3(-0.045, 1.6, 0.21)
## Where each elbow bends toward, off its palm in skeleton space: the trigger elbow out and down, the support elbow under.
const ELBOW_OFFSETS: Array[Vector3] = [Vector3(-0.3, -0.45, -0.1), Vector3(0.1, -0.5, -0.05)]
## How much of the aim pitch the elbow offsets turn with.
const ELBOW_PITCH_SHARE: float = 0.5
## The share of full arm length a wrist may sit from its shoulder before the rifle is drawn in.
const REACH_SHARE: float = 0.97
## Passes of drawing the rifle in; each one closes what the last left.
const REACH_PASSES: int = 3

var stage: Stage = Stage.LEAN
## The LEAN stage, which holds the state every stage reads.
var lead: Node = null
## Right (grip) then left (fore-end), for every per-arm array below.
var anchors: Array[Node3D] = [null, null]
var targets: Array[Node3D] = [null, null]
var poles: Array[Node3D] = [null, null]
var uppers: PackedInt32Array = PackedInt32Array([-1, -1])
var lowers: PackedInt32Array = PackedInt32Array([-1, -1])
var hands: PackedInt32Array = PackedInt32Array([-1, -1])
var back: PackedInt32Array = PackedInt32Array([-1, -1, -1])
## Whose rotation.x is the aim pitch: the holder's head.
var pitch_source: Node3D = null
## The held rifle, moved to the drawn eye while [member follow_eye] is set.
var rifle: Node3D = null
var follow_eye: bool = false
var _head_forward: Vector3 = Vector3.BACK
var _eye_local: Vector3 = Vector3.ZERO
var _reach: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])


## Resolve the bones once; the LEAN stage also makes the two wrist targets.
func bind(skeleton: Skeleton3D, arm_names: Array[StringName], back_names: Array[StringName]) -> void:
	for i in 2:
		uppers[i] = skeleton.find_bone(String(arm_names[i]))
		lowers[i] = skeleton.find_bone(String(arm_names[i + 2]))
		hands[i] = skeleton.find_bone(String(arm_names[i + 4]))
		if uppers[i] >= 0 and lowers[i] >= 0 and hands[i] >= 0:
			var lower: Vector3 = skeleton.get_bone_global_rest(lowers[i]).origin
			_reach[i] = REACH_SHARE * (skeleton.get_bone_global_rest(uppers[i]).origin.distance_to(lower)
					+ lower.distance_to(skeleton.get_bone_global_rest(hands[i]).origin))
	for i in 3:
		back[i] = skeleton.find_bone(String(back_names[i]))
	if back[2] >= 0:
		var head_rest: Transform3D = skeleton.get_bone_global_rest(back[2])
		_head_forward = head_rest.basis.inverse() * Vector3.BACK
		_eye_local = head_rest.affine_inverse() * EYE_REST
	if stage == Stage.LEAN:
		for i in 2:
			targets[i] = _marker("Wrist%d" % i)
			poles[i] = _marker("Elbow%d" % i)


func _marker(node_name: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = node_name
	marker.top_level = true
	add_child(marker)
	return marker


func _process_modification_with_delta(_delta: float) -> void:
	_modify()


func _process_modification() -> void:
	_modify()


func _modify() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or lead == null or lead.anchors[0] == null:
		return
	match stage:
		Stage.LEAN:
			_lean(skeleton)
		Stage.HANDS:
			_lay_hands(skeleton)


## Bend the back until the head looks down the aim, then put each wrist where its palm lands on the anchor.
func _lean(skeleton: Skeleton3D) -> void:
	if back[2] >= 0 and pitch_source != null:
		var forward: Vector3 = skeleton.get_bone_global_pose(back[2]).basis * _head_forward
		var delta: float = pitch_source.rotation.x - asin(clampf(forward.normalized().y, -1.0, 1.0))
		for i in 3:
			if back[i] < 0:
				continue
			var pose: Transform3D = skeleton.get_bone_global_pose(back[i])
			pose.basis = Basis(PITCH_AXIS, delta * LEAN_SHARE[i]) * pose.basis
			skeleton.set_bone_global_pose(back[i], pose)
	if rifle != null and follow_eye and back[2] >= 0:
		rifle.global_position = skeleton.global_transform * (skeleton.get_bone_global_pose(back[2]) * _eye_local)
		_draw_in(skeleton)
	elif rifle != null:
		rifle.position = Vector3.ZERO
	var pitch: float = pitch_source.rotation.x if pitch_source != null else 0.0
	var elbow_turn: Basis = skeleton.global_transform.basis * Basis(PITCH_AXIS, pitch * ELBOW_PITCH_SHARE)
	for i in 2:
		targets[i].global_position = _wrist(i)
		poles[i].global_position = anchors[i].global_position + elbow_turn * ELBOW_OFFSETS[i]


func _wrist(i: int) -> Vector3:
	var anchor: Transform3D = anchors[i].global_transform
	return anchor.origin - anchor.basis.y.normalized() * PALM_REACH


## Move the rifle toward the shoulders until both wrists are in reach: the rifle comes to the hands.
func _draw_in(skeleton: Skeleton3D) -> void:
	for _pass in REACH_PASSES:
		var shift: Vector3 = Vector3.ZERO
		for i in 2:
			var shoulder: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(uppers[i]).origin
			var span: Vector3 = _wrist(i) - shoulder
			if span.length() > _reach[i]:
				shift -= span.normalized() * (span.length() - _reach[i])
		if shift.is_zero_approx():
			return
		rifle.global_position += shift


## Turn each hand onto its anchor.
func _lay_hands(skeleton: Skeleton3D) -> void:
	var to_skeleton: Basis = skeleton.global_transform.basis.orthonormalized().inverse()
	for i in 2:
		var hand: int = lead.hands[i]
		if hand < 0:
			continue
		var pose: Transform3D = skeleton.get_bone_global_pose(hand)
		pose.basis = (to_skeleton * lead.anchors[i].global_transform.basis).orthonormalized()
		skeleton.set_bone_global_pose(hand, pose)
