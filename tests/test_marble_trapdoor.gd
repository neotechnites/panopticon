extends TestCase

## Map 2's lever and trapdoor, driven in the shipped scene: a body on the door
## drops into the pit's lethal volume, a body beside it does not, and a rifle hit
## on the lever's handle throws it.

const SCENE_PATH: String = "res://maps/marble/marble.tscn"
const DOOR_NODE: NodePath = ^"Elements/Trapdoor049"
const PIT_NODE: NodePath = ^"PitTrap"

const BODY_RADIUS: float = 0.4
const BODY_HEIGHT: float = 1.8
const GRAVITY: float = 22.0
const BODY_LAYER: int = 1
const STATIC_COLLIDER_MASK: int = 1
const SETTLE_TICKS: int = 10
## Rattle 0.3 + swing 0.35 + a 1.4 m fall, with room to spare.
const DROP_TICKS: int = 90

## On the closed door: over leaf B, clear of the seam and the frame.
const ON_DOOR_LOCAL: Vector3 = Vector3(0.6, 0.05, 0.6)
## On the deck past the door's leading edge, well outside the hole.
const BESIDE_DOOR_LOCAL: Vector3 = Vector3(0.6, 0.05, 2.8)

## The shooter: this far toward the tower from the handle, and this far up.
const SHOT_BACK_METRES: float = 15.0
const SHOT_UP_METRES: float = 4.0

var _marble: Node3D
var _door: TrapDoor
var _pit: TrapVolume
var _entered: Array[Node3D] = []


func before_each() -> void:
	_entered.clear()
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "the marble scene loads")
	if packed == null:
		return
	_marble = packed.instantiate() as Node3D
	add_child(_marble)
	await step_ticks(1)
	_door = _marble.get_node_or_null(DOOR_NODE) as TrapDoor
	assert_not_null(_door, "the scene ships a trapdoor at %s" % DOOR_NODE)
	if _door == null:
		return
	_pit = _door.get_node_or_null(PIT_NODE) as TrapVolume
	assert_not_null(_pit, "and a lethal volume in its pit")
	if _pit != null:
		_pit.body_entered.connect(_on_pit_entered)


func after_each() -> void:
	if _marble != null and is_instance_valid(_marble):
		remove_child(_marble)
		_marble.free()
	_marble = null
	_door = null
	_pit = null


## A body standing on the closed door falls into the pit's lethal volume when it
## opens; a body on the deck beside it stays standing and untouched.
func test_a_body_on_the_door_falls_to_the_spikes_and_one_beside_it_does_not() -> void:
	if _door == null or _pit == null:
		fail("no trapdoor to drive")
		return
	var on_door: Faller = _make_body(_door.global_transform * ON_DOOR_LOCAL)
	var beside: Faller = _make_body(_door.global_transform * BESIDE_DOOR_LOCAL)
	await step_ticks(SETTLE_TICKS)
	assert_true(on_door.is_on_floor(), "the closed door holds a body up")
	assert_true(beside.is_on_floor(), "the deck beside it does too")
	assert_false(_entered.has(on_door), "nobody on the closed door is touched by the spikes")
	var deck_y: float = _door.global_position.y

	assert_true(_door.is_armed(), "the door starts armed")
	assert_true(_door.pull(), "and the host's pull throws it")
	assert_true(_door.is_open(), "the rattle counts as open")
	await step_ticks(DROP_TICKS)

	assert_true(_entered.has(on_door), "the body on the door reached the pit's lethal volume")
	assert_lt(on_door.global_position.y, deck_y - 0.5, "and is down in the pit")
	assert_false(_entered.has(beside), "the body beside the door was never touched")
	assert_true(beside.is_on_floor(), "and still stands on the deck")
	assert_almost_eq(beside.global_position.y, deck_y, 0.1, "at deck height")
	assert_false(_door.pull(), "a second pull during the cycle does nothing")
	print("      on-door body at y %.2f, beside at y %.2f, deck %.2f" % [
		on_door.global_position.y, beside.global_position.y, deck_y,
	])


## The guard's rifle, fired at the lever's handle, throws it.
func test_the_lever_fires_from_the_guards_shot() -> void:
	if _door == null:
		fail("no trapdoor to shoot at")
		return
	var hitbox: StaticBody3D = _door.find_child("HandleHitbox", true, false) as StaticBody3D
	assert_not_null(hitbox, "the lever carries a handle hitbox")
	if hitbox == null:
		return
	var rifle: Rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(rifle)
	rifle.profile = TestFixtures.weapon_profile()
	# No rules: no hip spread off an unscoped rifle, so the shot is the aim line.
	rifle.rules = null
	add_child(rifle)
	rifle.set_physics_process(false)
	rifle.tracer_parent = _marble
	var target: Vector3 = hitbox.global_position
	var inward: Vector3 = Vector3(-target.x, 0.0, -target.z).normalized()
	var origin: Vector3 = target + inward * SHOT_BACK_METRES + Vector3.UP * SHOT_UP_METRES
	rifle.global_transform = Transform3D(Basis.IDENTITY, origin).looking_at(target, Vector3.UP)
	var struck: Array[Node3D] = []
	rifle.target_hit.connect(func(collider: Node3D, _at: Vector3, _n: Vector3) -> void: struck.append(collider))
	await step_ticks(1)

	assert_true(_door.is_armed(), "the door is armed before the shot")
	assert_true(rifle.try_fire(), "a READY rifle takes the shot")
	assert_eq_int(struck.size(), 1, "the shot struck something")
	if struck.size() == 1:
		assert_true(struck[0] == hitbox, "and it was the lever's handle, not %s" % struck[0].name)
	await step_ticks(2)
	assert_true(_door.is_open(), "the hit threw the lever and the door is going")
	remove_child(rifle)
	rifle.free()


# --- The body -------------------------------------------------------------------

## A capsule under gravity and nothing else.
class Faller extends CharacterBody3D:
	var gravity: float = 0.0

	func _physics_process(delta: float) -> void:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= gravity * delta
		move_and_slide()


func _make_body(at: Vector3) -> Faller:
	var body: Faller = Faller.new()
	body.collision_layer = BODY_LAYER
	body.collision_mask = STATIC_COLLIDER_MASK
	body.gravity = GRAVITY
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	var holder: CollisionShape3D = CollisionShape3D.new()
	holder.shape = capsule
	holder.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	body.add_child(holder)
	_marble.add_child(body)
	body.global_position = at
	return body


func _on_pit_entered(body: Node3D) -> void:
	_entered.append(body)
