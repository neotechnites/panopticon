class_name RunnerPower
extends Node

## The runner's one-shot power, driven by the body's [MoveIntent] and armed by
## [MatchController] with the match's [MatchRules].

const DECOY_GROUP: StringName = &"hologram_decoys"
const SHIELD_RADIUS: float = 4.0
## A layer inside the rifle's hit mask that no body's collision mask includes,
## so shots stop on the shell and runners walk out of it.
const SHIELD_LAYER: int = 1 << 19
const CAMO_VISIBLE_RANGE: float = 25.0
const CAMO_ALPHA: float = 0.25
## Whole-body camo tint: dark hell red.
const CAMO_COLOR: Color = Color(0.55, 0.11, 0.06, 1.0)

@export var body: PlayerController

var rules: MatchRules = null
var match_controller: MatchController = null

var _active: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE
var _remaining: float = 0.0
var _cooldown: float = 0.0
var _shield: StaticBody3D = null
var _decoy: PlayerController = null
var _shell: MeshInstance3D = null
var _camo_mesh: MeshInstance3D = null
var _camo_saved: Material = null
## What a client is DRAWING, off the snapshot. Never set on the authority, where
## [member _active] is the truth.
var _presented: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE


## A decoy's intent: straight ahead at run speed, nothing else.
class DecoyIntent:
	extends IntentSource

	func poll(_delta: float) -> MoveIntent:
		_intent.clear()
		_intent.move_direction = Vector2(0.0, 1.0)
		return _intent


## The ability node on [param node], or null.
static func of(node: Node) -> RunnerPower:
	if node == null:
		return null
	return node.get_node_or_null(^"Ability") as RunnerPower


## The hologram [param collider] belongs to, or null.
static func decoy_of(collider: Node) -> PlayerController:
	var node: Node = collider
	while node != null:
		if node.is_in_group(DECOY_GROUP):
			return node as PlayerController
		node = node.get_parent()
	return null


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if body == null or not body.is_physics_processing():
		return
	var intent: MoveIntent = body.get_intent()
	if _active != MatchRules.RunnerAbility.NONE:
		_remaining -= delta
		var released: bool = _active == MatchRules.RunnerAbility.ARMOR_LOCK and not intent.ability_held
		if _remaining <= 0.0 or released:
			_end()
		return
	if intent.ability_slot > 0:
		activate(intent.ability_slot as MatchRules.RunnerAbility)
	elif intent.ability_pressed:
		activate()


## Give this node the match's rules and reset it for a fresh placement.
func arm(match_rules: MatchRules, controller: MatchController) -> void:
	cancel()
	rules = match_rules
	match_controller = controller
	_cooldown = 0.0


## Start the selected power. False when none is selected, one is running, or
## the cooldown has not run out.
func activate(which: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE) -> bool:
	if rules == null or body == null or _active != MatchRules.RunnerAbility.NONE or _cooldown > 0.0:
		return false
	if which == MatchRules.RunnerAbility.NONE:
		which = rules.runner_ability
	if which == MatchRules.RunnerAbility.NONE:
		return false
	_active = which
	_remaining = maxf(rules.ability_duration_seconds, 0.0)
	match _active:
		MatchRules.RunnerAbility.BUBBLE_SHIELD:
			_raise_shield()
		MatchRules.RunnerAbility.HOLOGRAM:
			_spawn_decoy()
		MatchRules.RunnerAbility.ARMOR_LOCK:
			_lock()
		MatchRules.RunnerAbility.ACTIVE_CAMO:
			_cloak()
	return true


## Tear the power down without starting a cooldown.
func cancel() -> void:
	_teardown()
	_active = MatchRules.RunnerAbility.NONE
	_presented = MatchRules.RunnerAbility.NONE
	_remaining = 0.0


## Draw [param which] on a mirrored body: the same shield, shell and tint
## [method activate] builds, with none of the effect. The client's whole view of
## somebody else's power, and of its own -- a client simulates neither.
##
## Called every frame from [PlayerNetLink] with the replicated state, so it is a
## no-op unless the power changed.
func present(which: MatchRules.RunnerAbility, remaining: float) -> void:
	_remaining = maxf(remaining, 0.0)
	if which == _presented:
		return
	_teardown()
	_presented = which
	match which:
		MatchRules.RunnerAbility.BUBBLE_SHIELD:
			_raise_shield()
		MatchRules.RunnerAbility.HOLOGRAM:
			_spawn_decoy()
		MatchRules.RunnerAbility.ARMOR_LOCK:
			_raise_shell()
		MatchRules.RunnerAbility.ACTIVE_CAMO:
			_cloak()


func get_ability() -> MatchRules.RunnerAbility:
	return rules.runner_ability if rules != null else MatchRules.RunnerAbility.NONE


func is_active() -> bool:
	return _active != MatchRules.RunnerAbility.NONE or _presented != MatchRules.RunnerAbility.NONE


## The power running now, or NONE. Sampled into the snapshot by [PlayerNetLink].
func get_active() -> MatchRules.RunnerAbility:
	return _active


## What this machine is DRAWING: its own power on the authority, the replicated
## one on a client.
func get_shown() -> MatchRules.RunnerAbility:
	return _active if _active != MatchRules.RunnerAbility.NONE else _presented


func get_remaining() -> float:
	return _remaining if is_active() else 0.0


func get_cooldown_remaining() -> float:
	return _cooldown


func is_hit_immune() -> bool:
	return _active == MatchRules.RunnerAbility.ARMOR_LOCK


func is_camouflaged() -> bool:
	return _active == MatchRules.RunnerAbility.ACTIVE_CAMO


func get_shield() -> StaticBody3D:
	return _shield


func get_decoy() -> PlayerController:
	return _decoy if is_instance_valid(_decoy) else null


func _end() -> void:
	_teardown()
	_active = MatchRules.RunnerAbility.NONE
	_remaining = 0.0
	_cooldown = maxf(rules.ability_cooldown_seconds, 0.0) if rules != null else 0.0


func _teardown() -> void:
	if _shield != null:
		_shield.queue_free()
		_shield = null
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null
	if _shell != null:
		_shell.queue_free()
		_shell = null
	_presented = MatchRules.RunnerAbility.NONE
	if body != null:
		body.movement_locked = false
	if _camo_mesh != null:
		_camo_mesh.material_override = _camo_saved
		_camo_mesh = null
		_camo_saved = null


# --- Bubble shield ------------------------------------------------------------

func _raise_shield() -> void:
	var shield: StaticBody3D = StaticBody3D.new()
	shield.name = "BubbleShield"
	shield.collision_layer = SHIELD_LAYER
	shield.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = SHIELD_RADIUS
	shape.shape = sphere
	shield.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = SHIELD_RADIUS
	sphere_mesh.height = SHIELD_RADIUS * 2.0
	mesh.mesh = sphere_mesh
	mesh.material_override = _glow_material(Color(0.35, 0.75, 1.0, 0.3), Color(0.2, 0.6, 1.0), 1.5)
	shield.add_child(mesh)
	body.get_parent().add_child(shield)
	shield.global_position = body.global_position + Vector3.UP * 0.9
	_shield = shield


# --- Hologram -----------------------------------------------------------------

func _spawn_decoy() -> void:
	if match_controller == null or match_controller.runner_scene == null:
		return
	var decoy: PlayerController = match_controller.runner_scene.instantiate() as PlayerController
	if decoy == null:
		return
	decoy.name = "Hologram"
	for child: Node in decoy.get_children():
		if child is RingRunner or child is IntentSource:
			decoy.remove_child(child)
			child.free()
	var source: DecoyIntent = DecoyIntent.new()
	source.name = "DecoyInput"
	decoy.add_child(source)
	decoy.intent_source = source
	decoy.add_to_group(DECOY_GROUP)
	var container: Node3D = match_controller.runner_container
	decoy.position = container.to_local(body.global_position)
	decoy.rotation = Vector3(0.0, body.global_rotation.y, 0.0)
	container.add_child(decoy)
	var mine: MeshInstance3D = _avatar_mesh(body)
	var theirs: MeshInstance3D = _avatar_mesh(decoy)
	if mine != null and theirs != null:
		theirs.material_override = mine.material_override
		_copy_surfaces(mine, theirs)
	_decoy = decoy


## A decoy the rifle has hit is gone.
static func shatter(decoy: PlayerController) -> void:
	if decoy != null and not decoy.is_queued_for_deletion():
		decoy.queue_free()


# --- Armor lock ---------------------------------------------------------------

func _lock() -> void:
	body.movement_locked = true
	body.velocity = Vector3.ZERO
	_raise_shell()


## The armor lock's glowing shell, and nothing else: what a client draws.
func _raise_shell() -> void:
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "ArmorShell"
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.55
	capsule.height = 2.1
	shell.mesh = capsule
	shell.material_override = _glow_material(Color(1.0, 0.85, 0.4, 0.6), Color(1.0, 0.7, 0.2), 2.0)
	body.add_child(shell)
	shell.position = Vector3.UP * 0.9
	_shell = shell


# --- Active camo --------------------------------------------------------------

func _cloak() -> void:
	var mesh: MeshInstance3D = _avatar_mesh(body)
	if mesh == null:
		return
	_camo_mesh = mesh
	_camo_saved = mesh.material_override
	var base: Material = mesh.material_override
	if base == null:
		base = mesh.get_active_material(0)
	# A duplicate of whatever the body is wearing, so the model's texture and the
	# team tint on it survive the cloak; a fresh flat material only if it has none.
	var camo: BaseMaterial3D = (
		(base.duplicate() as BaseMaterial3D) if base is BaseMaterial3D else StandardMaterial3D.new()
	)
	# Ryan: not invisible -- hell red, the colour that vanished against the rock.
	camo.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	camo.albedo_color = CAMO_COLOR
	camo.emission_enabled = false
	mesh.material_override = camo


# --- Helpers ------------------------------------------------------------------

## Copy every surface override across, so a decoy wears the team shirt its
## owner does rather than the model's bare grey.
static func _copy_surfaces(from: MeshInstance3D, to: MeshInstance3D) -> void:
	var count: int = mini(
		from.get_surface_override_material_count(), to.get_surface_override_material_count()
	)
	for index: int in count:
		to.set_surface_override_material(index, from.get_surface_override_material(index))


static func _avatar_mesh(of_body: PlayerController) -> MeshInstance3D:
	var avatar: PrisonerAvatar = of_body.get_node_or_null(^"Avatar") as PrisonerAvatar
	if avatar != null and avatar.mesh != null:
		return avatar.mesh
	return of_body.get_node_or_null(^"BodyMesh") as MeshInstance3D


static func _glow_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material
