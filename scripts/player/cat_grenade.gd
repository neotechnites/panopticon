class_name CatGrenade
extends RigidBody3D

## Power 5's cat: carried, cooked with E, thrown by shove; its blast throws every player in
## reach, guard and hub mannequins too, and hurts nobody. Exists on the authority only; [CatGrenadeRelay] draws it elsewhere.

signal exploded

const MESH: Mesh = preload("res://hub/props/cat/cat_mesh.tres")
const FUSE_SECONDS: float = 2.5
## The hub cat's carry pose and throw (scripts/hub/hub_cat.gd).
const CARRY_OFFSET: Vector3 = Vector3(0.0, -0.3, -0.55)
const THROW_SPEED: float = 10.0
const THROW_LIFT: float = 2.0
const THROW_SPIN: float = 12.0
const BLAST_RADIUS: float = 7.0
## Launch speed at the centre of the blast; the edge gets BLAST_EDGE of it.
const BLAST_SPEED: float = 22.0
const BLAST_LIFT: float = 9.0
const BLAST_EDGE: float = 0.35
const BLAST_AIR_LOCK_SECONDS: float = 1.2
## Where a body's middle sits above its origin, for the blast's direction.
const BODY_CENTRE: float = 0.9

var carrier: PlayerController = null
var match_controller: MatchController = null
var cooking: bool = false
var fuse_left: float = FUSE_SECONDS
var id: int = 0
var _relay: CatGrenadeRelay = null


func _init() -> void:
	name = "CatGrenade"
	mass = 4.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = MESH
	add_child(mesh)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.28, 0.38, 0.5)
	shape.shape = box
	shape.position = Vector3(0.0, 0.19, 0.0)
	add_child(shape)


func _ready() -> void:
	_relay = CatGrenadeRelay.get_relay()
	if _relay != null:
		id = _relay.next_id()
	if is_instance_valid(carrier):
		global_transform = _carry_transform()


## Light the fuse. Idempotent.
func cook() -> void:
	cooking = true


## Huck it the way the hub cat is thrown; an uncooked cat is lit by the throw. False if not held.
func throw() -> bool:
	if not is_instance_valid(carrier):
		return false
	var look: Basis = _carry_basis()
	global_transform = _carry_transform()
	carrier = null
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = -look.z * THROW_SPEED + Vector3.UP * THROW_LIFT
	angular_velocity = Vector3.UP * THROW_SPIN
	cooking = true
	return true


## Remove it without a blast: its power was torn down.
func discard() -> void:
	if _relay != null:
		_relay.gone(id)
	queue_free()


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if carrier != null:
		if not is_instance_valid(carrier) or not carrier.is_inside_tree():
			carrier = null
			collision_mask = 1
			freeze = false
			cooking = true
		else:
			global_transform = _carry_transform()
	if cooking:
		fuse_left = maxf(fuse_left - delta, 0.0)
		if fuse_left <= 0.0:
			_explode()
			return
	if _relay != null:
		_relay.pose(id, global_position, rotation.y)


func _explode() -> void:
	var at: Vector3 = global_position + Vector3.UP * 0.2
	if _relay != null:
		_relay.blast(id, at)
	if match_controller != null:
		for participant: MatchParticipant in match_controller.get_participants_ref():
			_push(participant, at)
	exploded.emit()
	queue_free()


## Launch one player away from [param at], harder the closer it stands. Never damage.
func _push(participant: MatchParticipant, at: Vector3) -> void:
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
	target.launch(
		(away * BLAST_SPEED + Vector3.UP * BLAST_LIFT) * strength, BLAST_AIR_LOCK_SECONDS * strength
	)


func _carry_basis() -> Basis:
	if carrier.head != null:
		return carrier.head.global_basis.orthonormalized()
	return carrier.global_basis.orthonormalized()


func _carry_transform() -> Transform3D:
	var origin: Vector3 = carrier.global_position + Vector3.UP * 1.5
	if carrier.head != null:
		origin = carrier.head.global_position
	var look: Basis = _carry_basis()
	return Transform3D(Basis(Vector3.UP, look.get_euler().y), origin + look * CARRY_OFFSET)
