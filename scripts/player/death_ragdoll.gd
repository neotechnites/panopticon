extends Node
## A rifle kill's limp body, and a shoved runner's flop: physical bones on the avatar's own skeleton, built
## at rest once and simulated only while limp. Cosmetic, local; a flop pins pelvis and chest to the capsule.

## Shove along the shot at the struck bone, in newton-seconds.
@export_range(0.0, 200.0, 1.0) var impulse: float = 70.0
## How fast the pelvis drops at the kill, m/s: the legs give out instead of the body tipping like a plank.
@export_range(0.0, 8.0, 0.1) var buckle: float = 2.5
## How much of the run's velocity the body keeps as it goes down (1 = all).
@export var carry_velocity: float = 1.0
## The whole body's mass, in kg, shared across the parts by fixed weights.
@export var body_mass: float = 70.0
## Damping every part carries; higher reads heavier and stops sooner, lower floppier.
@export var linear_damp: float = 0.05
@export var angular_damp: float = 0.6
@export var friction: float = 0.9
## Joint limits, degrees: swing is how far a ball joint leans, twist how far it turns.
@export var neck_swing: float = 35.0
@export var neck_twist: float = 30.0
@export var spine_swing: float = 30.0
@export var spine_twist: float = 20.0
@export var shoulder_swing: float = 80.0
@export var shoulder_twist: float = 40.0
@export var hip_swing: float = 45.0
@export var hip_twist: float = 20.0
@export var elbow_bend: float = 135.0
@export var knee_bend: float = 125.0
## Joint give, 0..1 (Godot physics only; Jolt holds its limits hard).
@export var joint_softness: float = 0.8
@export var joint_bias: float = 0.3
## What the parts land on: the map's layers. The parts are on no layer, so no ray sees them.
@export_flags_3d_physics var collision_mask: int = 1

@export_group("Shove flop")
## Off keeps the small reel BodyContact gives every throw.
@export var flop_enabled: bool = true
## How hard the shove throws the body over: 1 is the shove's own speed, 0 no tumble.
@export_range(0.0, 3.0, 0.05) var flop_throw: float = 1.0
## 0 holds the limbs stiff, 1 lets them hang and flail.
@export_range(0.0, 1.0, 0.05) var flop_limpness: float = 0.85
## Seconds from limp back into the clip once he is down.
@export_range(0.05, 2.0, 0.05) var flop_get_up_seconds: float = 0.45
@export_group("")

## bone, tail bone (or none), extra length past the tail, radius, parent-joint kind, mass weight.
const PARTS: Array = [
	[&"Hips", &"Spine", 0.06, 0.13, &"none", 0.15],
	[&"Spine", &"Neck", 0.04, 0.14, &"spine", 0.30],
	[&"Head", &"", 0.24, 0.11, &"neck", 0.08],
	[&"UpperArm.L", &"LowerArm.L", 0.0, 0.05, &"shoulder", 0.03],
	[&"LowerArm.L", &"Hand.L", 0.09, 0.045, &"elbow", 0.025],
	[&"UpperArm.R", &"LowerArm.R", 0.0, 0.05, &"shoulder", 0.03],
	[&"LowerArm.R", &"Hand.R", 0.09, 0.045, &"elbow", 0.025],
	[&"Thigh.L", &"Shin.L", 0.0, 0.08, &"hip", 0.10],
	[&"Shin.L", &"Foot.L", 0.0, 0.06, &"knee", 0.055],
	[&"Thigh.R", &"Shin.R", 0.0, 0.08, &"hip", 0.10],
	[&"Shin.R", &"Foot.R", 0.0, 0.06, &"knee", 0.055],
]
## Most a flop's limbs start behind the thrown torso, m/s.
const FLOP_MOST_LAG: float = 2.5
## The chest, struck when the hit point is unknown.
const CHEST_PART: int = 1
## A flop's tumble: degrees a second per m/s of throw, the seconds it spins down over, the most it turns.
const TUMBLE_DEG_PER_MPS: float = 10.0
const TUMBLE_SECONDS: float = 0.6
const TUMBLE_MOST_DEG: float = 110.0
## Damping a stiff limb (limpness 0) carries; and how fast a killed flop's blend returns to full.
const STIFF_ANGULAR_DAMP: float = 8.0
const STIFF_LINEAR_DAMP: float = 2.0
const DEATH_BLEND_RATE: float = 8.0
## A capsule that moves further than this in one tick was placed, not thrown: the flop ends.
const PLACED_METRES: float = 4.0

enum Flop { NONE, THROWN, RISING }

var _skeleton: Skeleton3D = null
var _simulator: PhysicalBoneSimulator3D = null
var _bones: Array[PhysicalBone3D] = []
var _active: bool = false
var _flop: Flop = Flop.NONE
## What the flop is pinned to (the avatar), and the pinned pelvis, chest and the tumble's pivot in its space.
var _anchor: Node3D = null
var _hips_local: Transform3D = Transform3D.IDENTITY
var _chest_local: Transform3D = Transform3D.IDENTITY
var _pivot_local: Vector3 = Vector3.ZERO
## The tumble axis in the anchor's space, the angle turned, radians, and its spin, radians a second.
var _axis_local: Vector3 = Vector3.RIGHT
var _tumble: float = 0.0
var _spin: float = 0.0
var _rise: float = 0.0
var _last_anchor: Vector3 = Vector3.ZERO


func _ready() -> void:
	# After every body has moved this tick, so the pinned torso is where the capsule is now.
	process_physics_priority = 1000
	set_physics_process(false)


## Build the bones on [param skeleton] from its rest pose. Call once, before the
## first animated frame; false when the rig lacks a bone.
func build(skeleton: Skeleton3D) -> bool:
	_skeleton = skeleton
	for part: Array in PARTS:
		if skeleton.find_bone(String(part[0])) < 0:
			push_error("DeathRagdoll: the rig has no bone \"%s\"; a shot body will play its clip." % part[0])
			return false
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "DeathRagdoll"
	_simulator.active = false
	skeleton.add_child(_simulator)
	var total: float = 0.0
	for part: Array in PARTS:
		total += float(part[5])
	for part: Array in PARTS:
		_bones.append(_make_part(part, float(part[5]) / total))
	# Joints are made against the rest pose, so every limit is measured from standing.
	var saved: Array[Transform3D] = []
	for i: int in skeleton.get_bone_count():
		saved.append(skeleton.get_bone_pose(i))
	skeleton.reset_bone_poses()
	for bone: PhysicalBone3D in _bones:
		bone.global_transform = skeleton.global_transform \
			* skeleton.get_bone_global_pose(skeleton.find_bone(bone.bone_name)) * bone.body_offset
	for i: int in _bones.size():
		_set_joint(_bones[i], PARTS[i][4])
	for i: int in skeleton.get_bone_count():
		skeleton.set_bone_pose(i, saved[i])
	return true


func is_active() -> bool:
	return _active


## A shove's flop is limp now or still getting up.
func is_flopping() -> bool:
	return _flop != Flop.NONE


## Thrown and not yet getting up.
func is_thrown() -> bool:
	return _flop == Flop.THROWN


## Go limp from the pose on screen, pelvis pinned to [param anchor], thrown at [param throw] (world m/s).
func flop(anchor: Node3D, throw: Vector3) -> void:
	if _simulator == null or _active or _flop != Flop.NONE or not flop_enabled:
		return
	_flop = Flop.THROWN
	_anchor = anchor
	_place_simulator_after_layers()
	_simulator.active = true
	_simulator.influence = 1.0
	_go_limp()
	var limp: float = clampf(flop_limpness, 0.0, 1.0)
	for i: int in range(2, _bones.size()):
		_bones[i].angular_damp = lerpf(STIFF_ANGULAR_DAMP, angular_damp, limp)
		_bones[i].linear_damp = lerpf(STIFF_LINEAR_DAMP, linear_damp, limp)
	# Pelvis and chest are driven, never simulated: the drawn torso cannot leave the capsule.
	PhysicsServer3D.body_set_mode(_bones[0].get_rid(), PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_set_mode(_bones[CHEST_PART].get_rid(), PhysicsServer3D.BODY_MODE_KINEMATIC)
	var frame: Transform3D = anchor.global_transform
	var to_anchor: Transform3D = frame.affine_inverse()
	_hips_local = to_anchor * _bones[0].global_transform
	_chest_local = to_anchor * _bones[CHEST_PART].global_transform
	# The tumble turns about the capsule's line at mid-torso, so both stay on it.
	var mid: float = (_bones[0].global_position.y + _bones[CHEST_PART].global_position.y) * 0.5 - frame.origin.y
	_pivot_local = to_anchor * (frame.origin + Vector3.UP * mid)
	_last_anchor = frame.origin
	var flat: Vector3 = Vector3(throw.x, 0.0, throw.z)
	_axis_local = Vector3.RIGHT
	if flat.length() > 0.01:
		_axis_local = (frame.basis.inverse() * Vector3.UP.cross(flat.normalized())).normalized()
	_tumble = 0.0
	_spin = deg_to_rad(TUMBLE_DEG_PER_MPS) * flat.length() * flop_throw
	# The limbs are left behind by the launch, by as much as they are limp.
	# Capped: at a full shove the soft joints let limbs left 7 m/s behind stretch off the torso.
	var behind: Vector3 = (-throw * limp * flop_throw * 0.5).limit_length(FLOP_MOST_LAG)
	for i: int in range(2, _bones.size()):
		_bones[i].linear_velocity = throw + behind
	set_physics_process(true)


## The throw is over and he is down: blend from limp back into the clip.
func get_up() -> void:
	if _flop == Flop.THROWN:
		_flop = Flop.RISING
		_rise = 0.0


## Go limp now, from the pose on screen, moving at [param velocity] and struck at
## [param at] along [param direction] (zero direction: no strike, chest if no point).
func start(velocity: Vector3, at: Vector3, direction: Vector3) -> void:
	if _simulator == null or _active:
		return
	if _flop != Flop.NONE:
		_die_from_flop(velocity, at, direction)
		return
	_active = true
	_skeleton.move_child(_simulator, _skeleton.get_child_count() - 1)
	_simulator.active = true
	_simulator.influence = 1.0
	_go_limp()
	var carried: Vector3 = velocity * carry_velocity
	for bone: PhysicalBone3D in _bones:
		bone.linear_velocity = carried
	_bones[0].linear_velocity = carried + Vector3.DOWN * buckle
	if direction.is_zero_approx():
		return
	var struck: PhysicalBone3D = _nearest_part(at)
	struck.apply_impulse(direction.normalized() * impulse, at - struck.global_position)


## Hand the skeleton back to the animation; the parts stay where they fell, inert.
func stop() -> void:
	if not _active and _flop == Flop.NONE:
		return
	_active = false
	_flop = Flop.NONE
	set_physics_process(false)
	_simulator.physical_bones_stop_simulation()
	_simulator.active = false
	_simulator.influence = 1.0
	for bone: PhysicalBone3D in _bones:
		bone.collision_mask = 0
		bone.angular_damp = angular_damp
		bone.linear_damp = linear_damp


func _physics_process(delta: float) -> void:
	if _active:
		# A kill mid-get-up: the blend returns to the corpse instead of popping to it.
		_simulator.influence = move_toward(_simulator.influence, 1.0, delta * DEATH_BLEND_RATE)
		if _simulator.influence >= 1.0:
			set_physics_process(false)
		return
	if _flop == Flop.NONE or _anchor == null:
		return
	var frame: Transform3D = _anchor.global_transform
	if frame.origin.distance_to(_last_anchor) > PLACED_METRES:
		stop()
		return
	_last_anchor = frame.origin
	var angle: float = _tumble
	if _flop == Flop.THROWN:
		_tumble = minf(_tumble + _spin * delta, deg_to_rad(TUMBLE_MOST_DEG))
		_spin *= exp(-delta / TUMBLE_SECONDS)
		angle = _tumble
	else:
		_rise += delta / maxf(flop_get_up_seconds, 0.01)
		if _rise >= 1.0:
			stop()
			return
		var eased: float = smoothstep(0.0, 1.0, _rise)
		_simulator.influence = 1.0 - eased
		angle = _tumble * (1.0 - eased)
	var pivot: Vector3 = frame * _pivot_local
	var turn: Basis = Basis((frame.basis * _axis_local).normalized(), angle)
	var tumble: Transform3D = Transform3D(turn, pivot - turn * pivot)
	PhysicsServer3D.body_set_state(_bones[0].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, tumble * frame * _hips_local)
	PhysicsServer3D.body_set_state(_bones[CHEST_PART].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, tumble * frame * _chest_local)


## The pelvis, world space.
func centre() -> Vector3:
	return _bones[0].global_position if not _bones.is_empty() else Vector3.ZERO


## Every part's centre, world space; the pelvis first, the chest second.
func part_positions() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for bone: PhysicalBone3D in _bones:
		out.append(bone.global_position)
	return out


## Start the parts simulating against the map, clear of every live body.
func _go_limp() -> void:
	# Live bodies share the map's layer; a pack running over a corpse would bulldoze it.
	var walkers: Array[Node] = get_tree().root.find_children("*", "CharacterBody3D", true, false)
	for bone: PhysicalBone3D in _bones:
		bone.collision_mask = collision_mask
		for walker: Node in walkers:
			bone.add_collision_exception_with(walker)
	_simulator.physical_bones_start_simulation()


## Killed while flopping: the torso is let go and the parts keep the motion they have.
func _die_from_flop(velocity: Vector3, at: Vector3, direction: Vector3) -> void:
	_flop = Flop.NONE
	_active = true
	_skeleton.move_child(_simulator, _skeleton.get_child_count() - 1)
	PhysicsServer3D.body_set_mode(_bones[0].get_rid(), PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_mode(_bones[CHEST_PART].get_rid(), PhysicsServer3D.BODY_MODE_RIGID)
	for bone: PhysicalBone3D in _bones:
		bone.angular_damp = angular_damp
		bone.linear_damp = linear_damp
	_bones[CHEST_PART].linear_velocity = velocity * carry_velocity
	_bones[0].linear_velocity = velocity * carry_velocity + Vector3.DOWN * buckle
	set_physics_process(_simulator.influence < 1.0)
	if direction.is_zero_approx():
		return
	var struck: PhysicalBone3D = _nearest_part(at)
	struck.apply_impulse(direction.normalized() * impulse, at - struck.global_position)


## Right after the last body layer and before the first-person hiders, so a viewed body still hides its head.
func _place_simulator_after_layers() -> void:
	var after: int = -1
	for child: Node in _skeleton.get_children():
		if child != _simulator and child.has_method(&"bind_body"):
			after = child.get_index()
	var at: int = after if _simulator.get_index() < after else after + 1
	_skeleton.move_child(_simulator, clampi(at, 0, _skeleton.get_child_count() - 1))


func _exit_tree() -> void:
	stop()


func _make_part(part: Array, share: float) -> PhysicalBone3D:
	var bone_index: int = _skeleton.find_bone(String(part[0]))
	var head: Transform3D = _skeleton.get_bone_global_rest(bone_index)
	var along: Vector3
	var tail_index: int = -1 if part[1] == &"" else _skeleton.find_bone(String(part[1]))
	if tail_index >= 0:
		along = _skeleton.get_bone_global_rest(tail_index).origin - head.origin
	else:
		along = head.basis.y.normalized() * 0.001
	var length: float = along.length() + float(part[2])
	var dir: Vector3 = along.normalized()
	# Body frame in skeleton space: -Z down the bone, X the body's own sideways.
	var z: Vector3 = -dir
	var x: Vector3 = (Vector3.RIGHT - z * z.dot(Vector3.RIGHT)).normalized()
	var y: Vector3 = z.cross(x)
	var frame: Transform3D = Transform3D(Basis(x, y, z), head.origin + dir * length * 0.5)

	var body: PhysicalBone3D = PhysicalBone3D.new()
	body.name = String(part[0])
	body.bone_name = String(part[0])
	body.body_offset = head.affine_inverse() * frame
	body.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, length * 0.5))
	body.mass = maxf(body_mass * share, 0.1)
	body.friction = friction
	body.bounce = 0.0
	body.linear_damp = linear_damp
	body.angular_damp = angular_damp
	# Off every layer and mask until it falls; see start().
	body.collision_layer = 0
	body.collision_mask = 0
	var radius: float = float(part[3])
	var shape: CollisionShape3D = CollisionShape3D.new()
	if length <= radius * 2.0:
		var ball: SphereShape3D = SphereShape3D.new()
		ball.radius = radius
		shape.shape = ball
	else:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = length
		shape.shape = capsule
		shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	body.add_child(shape)
	_simulator.add_child(body)
	return body


## The joint to the parent part. Cones twist about the bone; hinges turn about X.
func _set_joint(bone: PhysicalBone3D, kind: StringName) -> void:
	var half: Vector3 = bone.joint_offset.origin
	match kind:
		&"none":
			return
		&"elbow", &"knee":
			# Hinge axis (joint Z) on the body's sideways X.
			bone.joint_offset = Transform3D(Basis(Vector3.BACK, Vector3.DOWN, Vector3.RIGHT), half)
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			var bend: float = elbow_bend if kind == &"elbow" else knee_bend
			bone.set(&"joint_constraints/angular_limit_enabled", true)
			if kind == &"knee":
				bone.set(&"joint_constraints/angular_limit_upper", 2.0)
				bone.set(&"joint_constraints/angular_limit_lower", -bend)
			else:
				bone.set(&"joint_constraints/angular_limit_upper", bend)
				bone.set(&"joint_constraints/angular_limit_lower", -2.0)
			bone.set(&"joint_constraints/angular_limit_softness", joint_softness)
			bone.set(&"joint_constraints/angular_limit_bias", joint_bias)
		_:
			# Twist axis (joint X) down the bone.
			bone.joint_offset = Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT), half)
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			var swing: float = spine_swing
			var twist: float = spine_twist
			match kind:
				&"neck":
					swing = neck_swing
					twist = neck_twist
				&"shoulder":
					swing = shoulder_swing
					twist = shoulder_twist
				&"hip":
					swing = hip_swing
					twist = hip_twist
			bone.set(&"joint_constraints/swing_span", swing)
			bone.set(&"joint_constraints/twist_span", twist)
			bone.set(&"joint_constraints/softness", joint_softness)
			bone.set(&"joint_constraints/bias", joint_bias)


func _nearest_part(at: Vector3) -> PhysicalBone3D:
	if at.is_zero_approx():
		return _bones[CHEST_PART]
	var best: PhysicalBone3D = null
	var best_distance: float = INF
	for bone: PhysicalBone3D in _bones:
		var d: float = bone.global_position.distance_squared_to(at)
		if d < best_distance:
			best_distance = d
			best = bone
	return best
