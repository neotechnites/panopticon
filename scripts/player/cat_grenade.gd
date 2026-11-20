class_name CatGrenade
extends RigidBody3D

## The cat power's body on the host (DESIGN 9): carried, then thrown as a rigid body. Physics only: the
## fuse is the power's state and every machine draws the cat with a [CatView]. Its blast hurts nobody.

const FUSE_SECONDS: float = 2.5
const BLAST_RADIUS: float = 7.0
## Launch speed at the centre of the blast; the edge gets BLAST_EDGE of it.
const BLAST_SPEED: float = 22.0
const BLAST_LIFT: float = 9.0
const BLAST_EDGE: float = 0.35
const BLAST_AIR_LOCK_SECONDS: float = 1.2
## Where a body's middle sits above its origin, for the blast's direction.
const BODY_CENTRE: float = 0.9
## Where the blast goes off above the cat.
const BLAST_RISE: float = 0.2

var carrier: PlayerController = null


func _init() -> void:
	name = "CatGrenade"
	mass = 4.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.28, 0.38, 0.5)
	shape.shape = box
	shape.position = Vector3(0.0, 0.19, 0.0)
	add_child(shape)


func _ready() -> void:
	if carrier != null:
		global_transform = CatView.carry_transform(carrier)


## Huck it the way the hub cat is thrown. False if it is not held.
func throw() -> bool:
	if carrier == null:
		return false
	var velocity: Vector3 = CatView.throw_velocity(carrier)
	global_transform = CatView.carry_transform(carrier)
	carrier = null
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = Vector3.UP * CatView.THROW_SPIN
	return true


## Where the blast goes off now.
func blast_point() -> Vector3:
	return global_position + Vector3.UP * BLAST_RISE


func _physics_process(_delta: float) -> void:
	if carrier != null:
		global_transform = CatView.carry_transform(carrier)


## Launch every player of [param participants] in reach of [param at], harder the closer.
static func push_all(participants: Array[MatchParticipant], at: Vector3) -> void:
	for participant: MatchParticipant in participants:
		push(participant, at)


## Launch one player away from [param at], harder the closer it stands. Never damage.
static func push(participant: MatchParticipant, at: Vector3) -> void:
	var target: PlayerController = participant.body
	if target == null or not target.is_inside_tree():
		return
	if not participant.is_running and not participant.is_ghost and not participant.is_shooter:
		return
	var offset: Vector3 = target.global_position + Vector3.UP * BODY_CENTRE - at
	var distance: float = offset.length()
	if distance > BLAST_RADIUS:
		return
	var strength: float = lerpf(BLAST_EDGE, 1.0, 1.0 - distance / BLAST_RADIUS)
	var flat: Vector3 = Vector3(offset.x, 0.0, offset.z)
	var away: Vector3 = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.ZERO
	target.launch((away * BLAST_SPEED + Vector3.UP * BLAST_LIFT) * strength, BLAST_AIR_LOCK_SECONDS * strength)
