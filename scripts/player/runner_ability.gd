class_name RunnerPower
extends Node

## The runner's one-shot power, driven by the body's [MoveIntent] and armed by
## [MatchController] with the match's [MatchRules].

const DECOY_GROUP: StringName = &"hologram_decoys"
const SHIELD_RADIUS: float = 4.0
## How far above a body's origin its shield is centred.
const SHIELD_RISE: float = 0.9
## A layer inside the rifle's hit mask that no body's collision mask includes,
## so shots stop on the shell and runners walk out of it.
const SHIELD_LAYER: int = 1 << 19
## The powers whose effect this body draws itself (a hologram and a cat are host entities).
const _DRAWN_POWERS: Array[MatchRules.RunnerAbility] = [
	MatchRules.RunnerAbility.BUBBLE_SHIELD, MatchRules.RunnerAbility.ARMOR_LOCK, MatchRules.RunnerAbility.ACTIVE_CAMO,
]
## The decoy body: hit by the rifle, ignored by every body mask.
const DECOY_LAYER: int = 1 << 18
const DECOY_LEAD_METRES: float = 2.0
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
var _cat: CatGrenade = null
## What a client is DRAWING, off the snapshot. Never set on the authority, where
## [member _active] is the truth.
var _presented: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE
## When a mirrored decoy was last placed, for its drawn velocity; 0 when not moving.
var _decoy_seen_msec: int = 0
const DECOY_STILL_MSEC: int = 300


## A decoy's intent: straight ahead at run speed, nothing else.
class DecoyIntent:
	extends IntentSource

	func poll(_delta: float) -> MoveIntent:
		_intent.clear()
		_intent.move_direction = Vector2(0.0, 1.0)
		return _intent


## The ability node on [param node], or null.
##
## Memoised per body. The tower's target scan, the net link's presentation pass
## and the decoy driver all ask this per body per tick, and each ask was a path
## resolution down the body's children.
static var _by_body: Dictionary[int, RunnerPower] = {}

static func of(node: Node) -> RunnerPower:
	if node == null:
		return null
	var id: int = node.get_instance_id()
	var cached: RunnerPower = _by_body.get(id, null)
	if cached != null and is_instance_valid(cached) and is_instance_valid(node):
		return cached
	var found: RunnerPower = node.get_node_or_null(^"Ability") as RunnerPower
	if found != null:
		if _by_body.size() > 256:
			_by_body.clear()
		_by_body[id] = found
	return found


## The hologram [param collider] belongs to, or null.
static func decoy_of(collider: Node) -> PlayerController:
	var node: Node = collider
	while node != null:
		if node.is_in_group(DECOY_GROUP):
			return node as PlayerController
		node = node.get_parent()
	return null


func _ready() -> void:
	CatGrenadeRelay.ensure(self)


## A body leaving the tree takes its shield, hologram, shell, tint and cat with it.
func _exit_tree() -> void:
	_teardown()
	_active = MatchRules.RunnerAbility.NONE
	_remaining = 0.0


## One command's worth of the power, run by [method PlayerController.run_command]: its clocks,
## and a press, release or cook. [param authority] builds what only the host may (decoy, cat).
func step(intent: MoveIntent, delta: float, authority: bool) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if body == null or body.held:
		return
	if _active == MatchRules.RunnerAbility.CAT_GRENADE:
		# The cat's own fuse is the clock; a predicting client waits on the authority.
		if is_instance_valid(_cat):
			if intent.cook_pressed:
				_cat.cook()
			_remaining = _cat.fuse_left
		elif authority:
			_end()
		return
	if _active != MatchRules.RunnerAbility.NONE:
		_remaining -= delta
		var released: bool = _active == MatchRules.RunnerAbility.ARMOR_LOCK and not intent.ability_held
		# A predicting client's power runs out on the authority's word, not its own clock.
		if (_remaining <= 0.0 and authority) or released:
			_end()
		return
	if intent.ability_slot > 0:
		activate(intent.ability_slot as MatchRules.RunnerAbility, authority)
	elif intent.ability_pressed:
		activate(MatchRules.RunnerAbility.NONE, authority)


## Give this node the match's rules and reset it for a fresh placement.
func arm(match_rules: MatchRules, controller: MatchController) -> void:
	cancel()
	rules = match_rules
	match_controller = controller
	_cooldown = 0.0


## Start the selected power, as the deciding machine when [param authority] (it spawns the cat);
## false when none is selected, one is running, or the cooldown has not run out.
func activate(which: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE, authority: bool = true) -> bool:
	if rules == null or body == null or is_active() or _cooldown > 0.0:
		return false
	if which == MatchRules.RunnerAbility.NONE:
		which = rules.runner_ability
	if which == MatchRules.RunnerAbility.NONE:
		return false
	_active = which
	_remaining = maxf(rules.ability_duration_seconds, 0.0)
	if _active == MatchRules.RunnerAbility.ARMOR_LOCK:
		body.movement_locked = true
		body.velocity = Vector3.ZERO
	elif _active == MatchRules.RunnerAbility.CAT_GRENADE:
		_remaining = CatGrenade.FUSE_SECONDS
	if body.replaying:
		# A replayed command changes the state; what is drawn of it was drawn the first time.
		return true
	match _active:
		MatchRules.RunnerAbility.BUBBLE_SHIELD:
			_raise_shield()
		MatchRules.RunnerAbility.HOLOGRAM:
			# A predicting client draws its decoy where the authority's will walk; the snapshot moves it.
			_spawn_decoy(not authority)
		MatchRules.RunnerAbility.ARMOR_LOCK:
			_raise_shell()
		MatchRules.RunnerAbility.ACTIVE_CAMO:
			_cloak()
		MatchRules.RunnerAbility.CAT_GRENADE:
			if authority:
				_spawn_cat()
	return true


## Tear the power down without starting a cooldown.
func cancel() -> void:
	_teardown()
	_active = MatchRules.RunnerAbility.NONE
	_presented = MatchRules.RunnerAbility.NONE
	_remaining = 0.0


## Draw [param which] on a mirrored body from its record: the shield, shell or tint [method activate]
## builds, with none of the effect, the shield at [param anchor] and the hologram at its pose while
## [param decoy_alive]. Called every drawn frame; a no-op unless something changed.
func present(
	which: MatchRules.RunnerAbility, remaining: float, cooldown: float, anchor: Vector3 = Vector3.INF,
	decoy_alive: bool = false, decoy_yaw: float = 0.0,
) -> void:
	_remaining = maxf(remaining, 0.0)
	_cooldown = maxf(cooldown, 0.0)
	if _active != MatchRules.RunnerAbility.NONE:
		# A power this machine predicted is the record's to describe now: what it drew is kept when
		# they agree and dropped when they do not.
		if _active == which:
			_presented = which
		else:
			_teardown()
		_active = MatchRules.RunnerAbility.NONE
	if which != _presented:
		_teardown(true)
		_presented = which
		match which:
			MatchRules.RunnerAbility.BUBBLE_SHIELD:
				_raise_shield()
			MatchRules.RunnerAbility.ARMOR_LOCK:
				_raise_shell()
			MatchRules.RunnerAbility.ACTIVE_CAMO:
				_cloak()
	present_anchor(which, anchor, decoy_alive, decoy_yaw)


## The host's word on where this body's power stands: its shield's centre, and its hologram's pose
## while one is out. For a predicting body too, whose own guess at both is drawn until this lands.
func present_anchor(which: MatchRules.RunnerAbility, anchor: Vector3, decoy_alive: bool, decoy_yaw: float) -> void:
	if _shield != null and which == MatchRules.RunnerAbility.BUBBLE_SHIELD and anchor.is_finite():
		_shield.global_position = anchor
	if decoy_alive and anchor.is_finite():
		present_decoy(anchor, decoy_yaw)
	elif which == MatchRules.RunnerAbility.HOLOGRAM or _active != MatchRules.RunnerAbility.HOLOGRAM:
		# Out on the host and gone there (shot), or a mirror's power that has none: no hologram.
		clear_decoy()


## Take the host's exact predicted state of this power (DESIGN 7): its data only, as a replay starts.
func restore_predicted(which: int, remaining: float, cooldown: float) -> void:
	_active = which as MatchRules.RunnerAbility
	_remaining = remaining
	_cooldown = cooldown


## After a replay: what this power draws follows the state it was left in.
func settle_visuals() -> void:
	if _active != MatchRules.RunnerAbility.HOLOGRAM:
		clear_decoy()
	var drawn: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE
	if _shield != null:
		drawn = MatchRules.RunnerAbility.BUBBLE_SHIELD
	elif _shell != null:
		drawn = MatchRules.RunnerAbility.ARMOR_LOCK
	elif _camo_mesh != null:
		drawn = MatchRules.RunnerAbility.ACTIVE_CAMO
	var wanted: MatchRules.RunnerAbility = _active if _active in _DRAWN_POWERS else MatchRules.RunnerAbility.NONE
	if drawn != wanted:
		_teardown(true)
		match wanted:
			MatchRules.RunnerAbility.BUBBLE_SHIELD:
				_raise_shield()
			MatchRules.RunnerAbility.ARMOR_LOCK:
				_raise_shell()
			MatchRules.RunnerAbility.ACTIVE_CAMO:
				_cloak()
	body.movement_locked = _active == MatchRules.RunnerAbility.ARMOR_LOCK


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


## The power's own clock, as prediction restores it.
func get_predicted_remaining() -> float:
	return _remaining


func get_cooldown_remaining() -> float:
	return _cooldown


func is_hit_immune() -> bool:
	return _active == MatchRules.RunnerAbility.ARMOR_LOCK


func is_camouflaged() -> bool:
	return _active == MatchRules.RunnerAbility.ACTIVE_CAMO


func get_shield() -> StaticBody3D:
	return _shield


## The armor lock's shell this body is drawing, or null.
func get_shell() -> MeshInstance3D:
	return _shell


func get_decoy() -> PlayerController:
	return _decoy if is_instance_valid(_decoy) else null


func _end() -> void:
	_teardown()
	_active = MatchRules.RunnerAbility.NONE
	_remaining = 0.0
	# MatchRules.ability_cooldown_multiplier is the lever; the seconds are the
	# design value it scales.
	_cooldown = (
		maxf(rules.ability_cooldown_seconds * rules.ability_cooldown_multiplier, 0.0)
		if rules != null
		else 0.0
	)


func _teardown(keep_decoy: bool = false) -> void:
	if body != null and body.replaying:
		body.movement_locked = false
		return
	if _shield != null:
		_shield.queue_free()
		_shield = null
	if not keep_decoy:
		if is_instance_valid(_decoy):
			_decoy.queue_free()
		_decoy = null
	if _shell != null:
		_shell.queue_free()
		_shell = null
	_presented = MatchRules.RunnerAbility.NONE
	if body != null:
		body.movement_locked = false
	if is_instance_valid(_cat):
		_cat.exploded.disconnect(_on_cat_exploded)
		_cat.discard()
	_cat = null
	if _camo_mesh != null:
		_camo_mesh.material_override = _camo_saved
		_camo_mesh = null
		_camo_saved = null


static func _build_shield_mesh() -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = SHIELD_RADIUS
	sphere_mesh.height = SHIELD_RADIUS * 2.0
	mesh.mesh = sphere_mesh
	mesh.material_override = _glow_material(Color(0.35, 0.75, 1.0, 0.3), Color(0.2, 0.6, 1.0), 1.5)
	return mesh


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
	shield.add_child(_build_shield_mesh())
	body.get_parent().add_child(shield)
	shield.global_position = body.global_position + Vector3.UP * SHIELD_RISE
	_shield = shield


# --- Hologram -----------------------------------------------------------------

## Place the hologram. [param mirrored] builds the client's copy: the same body
## on the same layer, with no intent and no physics, moved only by the
## authority's transforms.
func _spawn_decoy(mirrored: bool = false) -> void:
	if match_controller == null or match_controller.runner_scene == null:
		return
	var decoy: PlayerController = match_controller.runner_scene.instantiate() as PlayerController
	if decoy == null:
		return
	decoy.name = "Hologram"
	for child: Node in decoy.get_children():
		if child is RunnerBrain or child is IntentSource:
			decoy.remove_child(child)
			child.free()
	if not mirrored:
		var source: DecoyIntent = DecoyIntent.new()
		source.name = "DecoyInput"
		decoy.add_child(source)
		decoy.intent_source = source
	# A hologram is a target and never a runner: nothing that lists runners may list it.
	decoy.remove_from_group(MatchController.RUNNER_GROUP)
	decoy.add_to_group(DECOY_GROUP)
	var container: Node3D = match_controller.runner_container
	var ahead: Vector3 = -body.global_transform.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() * DECOY_LEAD_METRES
	decoy.position = container.to_local(body.global_position + ahead)
	decoy.rotation = Vector3(0.0, body.global_rotation.y, 0.0)
	# Shots stop on it (the rifle mask spans every layer); bodies walk through it.
	decoy.collision_layer = DECOY_LAYER
	decoy.collision_mask = 1
	container.add_child(decoy)
	if mirrored:
		decoy.set_physics_process(false)
	var mine: MeshInstance3D = _avatar_mesh(body)
	var theirs: MeshInstance3D = _avatar_mesh(decoy)
	if mine != null and theirs != null:
		theirs.material_override = mine.material_override
		_copy_surfaces(mine, theirs)
	_decoy = decoy


## Put the mirrored hologram where the host's record has it, building it the first time.
func present_decoy(position: Vector3, yaw: float) -> void:
	if get_decoy() == null:
		_decoy = null
		_spawn_decoy(true)
		_decoy_seen_msec = 0
	if _decoy == null:
		return
	if _decoy.global_position.is_equal_approx(position) and is_equal_approx(_decoy.rotation.y, yaw):
		return
	# Its avatar animates off velocity and floor, which a mirrored decoy never simulates.
	var now: int = Time.get_ticks_msec()
	if _decoy_seen_msec > 0 and now > _decoy_seen_msec:
		var moved: Vector3 = position - _decoy.global_position
		_decoy.velocity = moved / (float(now - _decoy_seen_msec) / 1000.0)
	_decoy_seen_msec = now
	_decoy.net_floor = 1
	_decoy.global_position = position
	_decoy.rotation.y = yaw


func _process(_delta: float) -> void:
	# A mirrored decoy that stopped being moved has stopped.
	if _decoy_seen_msec > 0 and Time.get_ticks_msec() - _decoy_seen_msec > DECOY_STILL_MSEC:
		_decoy_seen_msec = 0
		if is_instance_valid(_decoy):
			_decoy.velocity = Vector3.ZERO


## Drop the mirrored hologram: the authority's expiry, or a shot that shattered
## it, replayed here.
func clear_decoy() -> void:
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null


## A decoy the rifle has hit is gone.
static func shatter(decoy: PlayerController) -> void:
	if decoy != null and not decoy.is_queued_for_deletion():
		decoy.queue_free()


# --- Armor lock ---------------------------------------------------------------

## The armor lock's glowing shell, and the hold that goes with it. A client
## predicting its own body has to be held too, or it walks away from a lock the
## authority has it standing still in.
func _raise_shell() -> void:
	if body != null:
		body.movement_locked = true
	var shell: MeshInstance3D = _build_shell()
	shell.add_to_group(PlayerNetLink.DRAWN_WITH_BODY)
	body.add_child(shell)
	shell.position = Vector3.UP * 0.9
	_shell = shell


static func _build_shell() -> MeshInstance3D:
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "ArmorShell"
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.55
	capsule.height = 2.1
	shell.mesh = capsule
	shell.material_override = _glow_material(Color(1.0, 0.85, 0.4, 0.6), Color(1.0, 0.7, 0.2), 2.0)
	return shell


# --- Cat grenade --------------------------------------------------------------

func _spawn_cat() -> void:
	var cat: CatGrenade = CatGrenade.new()
	cat.carrier = body
	cat.match_controller = match_controller
	cat.exploded.connect(_on_cat_exploded)
	body.get_parent().add_child(cat)
	_cat = cat


func _on_cat_exploded() -> void:
	_cat = null
	if _active == MatchRules.RunnerAbility.CAT_GRENADE:
		_end()


## True while this body carries its own cat, so its swing is the throw.
func holds_cat() -> bool:
	return is_instance_valid(_cat) and is_instance_valid(_cat.carrier)


## Shove while carrying the cat: throw it. True when a cat took the shove. Authority only.
func throw_cat() -> bool:
	return is_instance_valid(_cat) and _cat.throw()


# --- Active camo --------------------------------------------------------------

func _cloak() -> void:
	var mesh: MeshInstance3D = _avatar_mesh(body)
	if mesh == null:
		return
	_camo_mesh = mesh
	_camo_saved = mesh.material_override
	mesh.material_override = _camo_for(mesh)


## A duplicate of whatever [param mesh] wears, so the model's texture and the team tint on it survive
## the cloak; a fresh flat material only if it has none.
static func _camo_for(mesh: MeshInstance3D) -> BaseMaterial3D:
	var base: Material = mesh.material_override
	if base == null:
		base = mesh.get_active_material(0)
	var camo: BaseMaterial3D = (
		(base.duplicate() as BaseMaterial3D) if base is BaseMaterial3D else StandardMaterial3D.new()
	)
	# Ryan: not invisible -- hell red, the colour that vanished against the rock.
	camo.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	camo.albedo_color = CAMO_COLOR
	camo.emission_enabled = false
	return camo


## What this body's powers draw when they run, for [SceneWarmup]; built by the code that draws them.
func warmup_samples() -> Array[Node3D]:
	var samples: Array[Node3D] = [_build_shell(), _build_shield_mesh(), CatGrenadeRelay.build_blast_sprite()]
	var cat: MeshInstance3D = MeshInstance3D.new()
	cat.mesh = CatGrenade.MESH
	samples.append(cat)
	var avatar: MeshInstance3D = _avatar_mesh(body) if body != null else null
	if avatar != null and avatar.mesh != null:
		var cloaked: MeshInstance3D = MeshInstance3D.new()
		cloaked.mesh = avatar.mesh
		cloaked.material_override = _camo_for(avatar)
		samples.append(cloaked)
	return samples


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
