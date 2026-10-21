class_name HubCat
extends RigidBody3D

## A hub cat: shove facing it to pick it up, shove again to huck it. Host-decided;
## clients follow its pose. Hooked from [method MatchController.apply_shove].

enum State { REST, HELD, FLYING }

## Where the cat sits relative to the carrier's head: just under and ahead of the face.
const CARRY_OFFSET: Vector3 = Vector3(0.0, -0.3, -0.55)
const THROW_SPEED: float = 20.0
const THROW_LIFT: float = 4.0
const THROW_SPIN: float = 12.0
## Height off the floor of the cone check: a cat on a ledge above you is out of reach.
const REACH_HEIGHT: float = 2.0
const FACING_DOT: float = 0.5
const FALL_OUT_Y: float = -60.0
const CAT_LAYER: int = 1 << 3

static var _all: Array[HubCat] = []

var _state: State = State.REST
var _carrier: PlayerController = null
var _home: Transform3D = Transform3D.IDENTITY
var _local_held: bool = false
var _prompt_layer: CanvasLayer = null
var _pet_tween: Tween = null


func _ready() -> void:
	_home = global_transform
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)
	_set_local_held(false)


## E while this machine's player carries the cat: a quick squish on the mesh.
func _unhandled_input(event: InputEvent) -> void:
	if not _local_held or not event.is_action_pressed(&"interact"):
		return
	var mesh: Node3D = get_node_or_null("Mesh") as Node3D
	if mesh == null:
		return
	if _pet_tween != null:
		_pet_tween.kill()
	mesh.scale = Vector3.ONE
	_pet_tween = create_tween()
	_pet_tween.tween_property(mesh, "scale", Vector3(1.2, 0.75, 1.2), 0.08)
	_pet_tween.tween_property(mesh, "scale", Vector3(0.92, 1.1, 0.92), 0.1)
	_pet_tween.tween_property(mesh, "scale", Vector3.ONE, 0.1)


## Show or hide the pet prompt on this machine.
func _set_local_held(held: bool) -> void:
	_local_held = held
	if held and _prompt_layer == null:
		_prompt_layer = CanvasLayer.new()
		var label: Label = Label.new()
		label.text = tr("HUB_CAT_PET_PROMPT")
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		label.offset_bottom = -90.0
		_prompt_layer.add_child(label)
		add_child(_prompt_layer)
	elif not held and _prompt_layer != null:
		_prompt_layer.queue_free()
		_prompt_layer = null


func _announce_held(held: bool) -> void:
	var peer: int = 1
	if held and is_instance_valid(_carrier):
		for child: Node in _carrier.get_children():
			if child is PlayerNetLink:
				peer = (child as PlayerNetLink).owner_peer_id
	if _networked():
		rpc(&"_held_by", peer if held else 0)
	_held_by(peer if held else 0)


## Authority to everyone: which peer carries the cat now, 0 for none.
@rpc("authority", "reliable", "call_remote", 1)
func _held_by(peer: int) -> void:
	var mine: int = 1
	if _networked():
		mine = multiplayer.get_unique_id()
	_set_local_held(peer != 0 and peer == mine)


## Spend [param body]'s shove on a cat: throw the one it carries, else lift one in reach.
## True when a cat took the shove. Authority only, like the shove itself.
static func claim_shove(body: PlayerController, forward: Vector3, reach: float) -> bool:
	if body == null:
		return false
	var best: HubCat = null
	var best_distance: float = 0.0
	for cat: HubCat in _all:
		if cat._carrier == body:
			cat._throw()
			return true
	var here: Vector3 = body.global_position
	for cat: HubCat in _all:
		if cat._state == State.HELD:
			continue
		var offset: Vector3 = cat.global_position - here
		if absf(offset.y) > REACH_HEIGHT:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > reach or (distance > 1e-3 and forward.dot(offset / distance) < FACING_DOT):
			continue
		if best == null or distance < best_distance:
			best = cat
			best_distance = distance
	if best == null:
		return false
	best._pick_up(body)
	return true


func _pick_up(body: PlayerController) -> void:
	_carrier = body
	_state = State.HELD
	collision_layer = 0
	collision_mask = 0
	freeze = true
	_announce_held(true)


func _throw() -> void:
	var look: Basis = _carry_basis()
	global_transform = _carry_transform()
	_carrier = null
	_announce_held(false)
	_state = State.FLYING
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = -look.z * THROW_SPEED + Vector3.UP * THROW_LIFT
	angular_velocity = Vector3.UP * THROW_SPIN


func _carry_basis() -> Basis:
	if _carrier.head != null:
		return _carrier.head.global_basis.orthonormalized()
	return _carrier.global_basis.orthonormalized()


func _carry_transform() -> Transform3D:
	var origin: Vector3 = _carrier.global_position + Vector3.UP * 1.5
	if _carrier.head != null:
		origin = _carrier.head.global_position
	var look: Basis = _carry_basis()
	return Transform3D(Basis(Vector3.UP, look.get_euler().y), origin + look * CARRY_OFFSET)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or _state == State.REST:
		return
	if _state == State.HELD:
		if not is_instance_valid(_carrier) or not _carrier.is_inside_tree():
			_drop()
		else:
			global_transform = _carry_transform()
	elif global_position.y < FALL_OUT_Y:
		_settle(_home)
		return
	elif sleeping:
		_settle(Transform3D(Basis(Vector3.UP, rotation.y), global_position))
		return
	if _networked():
		rpc(&"_pose", global_position, rotation.y)


func _drop() -> void:
	_carrier = null
	_announce_held(false)
	_state = State.FLYING
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO


func _settle(where: Transform3D) -> void:
	_state = State.REST
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = where
	if _networked():
		rpc(&"_rest", where.origin, where.basis.get_euler().y)


func _networked() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


## Authority to everyone, every tick the cat is carried or flying.
@rpc("authority", "unreliable_ordered", "call_remote", 3)
func _pose(at: Vector3, yaw: float) -> void:
	if multiplayer.is_server() or not at.is_finite() or not is_finite(yaw):
		return
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)


## Authority to everyone, once, where the cat came to rest.
@rpc("authority", "reliable", "call_remote", 0)
func _rest(at: Vector3, yaw: float) -> void:
	_pose(at, yaw)
