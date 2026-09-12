extends SkeletonModifier3D

## Collapses one bone to a point after the AnimationPlayer has posed the
## skeleton, so the owner's own eye is not inside their own skull.
##
## A [SkeletonModifier3D] rather than a [code]_process[/code] hook because only a
## modifier is guaranteed to run after the pose is set, whatever order the nodes
## happen to tick in. No [code]class_name[/code]: PrisonerAvatar preloads this by
## path, so a headless run needs no global class cache to have been built first.
## Toggle it with [method set_hidden].

## How small the bone is driven. Not zero -- a zero-determinant basis is a
## degenerate transform the skinning maths has no reason to enjoy -- but small
## enough that a 0.3 m head becomes 0.3 mm at the neck joint.
const COLLAPSED_SCALE: float = 0.001

## Which bone is collapsed, as a [Skeleton3D] index. Below zero does nothing.
var bone: int = -1


## Collapse the bone from now on, or restore it to its rest scale once.
func set_hidden(hidden: bool) -> void:
	active = hidden
	if hidden:
		return
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton != null and bone >= 0:
		skeleton.set_bone_pose_scale(bone, skeleton.get_bone_rest(bone).basis.get_scale())


func _process_modification_with_delta(_delta: float) -> void:
	_collapse()


func _process_modification() -> void:
	_collapse()


func _collapse() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or bone < 0:
		return
	skeleton.set_bone_pose_scale(bone, Vector3.ONE * COLLAPSED_SCALE)
