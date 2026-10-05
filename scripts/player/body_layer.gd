extends SkeletonModifier3D

## One procedural layer over the clip. Cosmetic and local: it poses the drawn skeleton and nothing else,
## runs before the rifle hold so the hands stay on the rifle, and fades out while the body is dead.

const BodyMotion: GDScript = preload("res://scripts/player/body_motion.gd")
## Per second, how fast a layer fades in and out.
const FADE_RATE: float = 8.0
## The longest step a spring is integrated over, seconds.
const MAX_STEP: float = 1.0 / 30.0
const SPRING_STEP: float = 1.0 / 120.0

## Off leaves the clip exactly as animated.
@export var enabled: bool = true

var body: PlayerController = null
var motion: BodyMotion = null
## 0 to 1: how much of this layer is drawn right now.
var _gate: float = 0.0


## Called once by the avatar. Override [method _bound] to resolve bones.
func bind_body(owner_body: PlayerController, shared: BodyMotion) -> void:
	body = owner_body
	motion = shared
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton != null:
		_bound(skeleton)


func _bound(_skeleton: Skeleton3D) -> void:
	pass


func _layer(_skeleton: Skeleton3D, _delta: float) -> void:
	pass


func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or motion == null or body == null:
		return
	var want: float = 1.0 if enabled and motion.live else 0.0
	_gate = 0.0 if motion.limp else move_toward(_gate, want, delta * FADE_RATE)
	_layer(skeleton, minf(delta, MAX_STEP))


## Turn [param bone] by [param turn], a model-space rotation, about its own joint.
func _turn(skeleton: Skeleton3D, bone: int, turn: Basis) -> void:
	if bone < 0:
		return
	var pose: Transform3D = skeleton.get_bone_global_pose(bone)
	pose.basis = turn * pose.basis
	skeleton.set_bone_global_pose(bone, pose)


## The rotation that tips up toward [param lean] (model x, z) by its length in radians.
func _tilt(lean: Vector2) -> Basis:
	var angle: float = lean.length()
	if angle < 0.0001:
		return Basis.IDENTITY
	return Basis(Vector3(lean.y, 0.0, -lean.x) / angle, angle)


## A damped spring pulling [param state] (value, velocity) to [param goal] over [param delta]; returns the new pair.
func _spring(state: Vector2, goal: float, hertz: float, damping: float, delta: float) -> Vector2:
	var omega: float = TAU * hertz
	var steps: int = maxi(ceili(delta / SPRING_STEP), 1)
	var dt: float = delta / float(steps)
	for _i: int in steps:
		state.y += ((goal - state.x) * omega * omega - state.y * 2.0 * damping * omega) * dt
		state.x += state.y * dt
	return state


## The velocity that carries a spring at rest out to a first peak of [param reach].
func _kick(reach: float, hertz: float, damping: float) -> float:
	var zeta: float = clampf(damping, 0.05, 0.95)
	var root: float = sqrt(1.0 - zeta * zeta)
	return reach * TAU * hertz * exp(zeta * atan2(root, zeta) / root)
