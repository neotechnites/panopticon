class_name RunnerPower
extends Node

## The runner's power (DESIGN 9): one [PowerState], stepped by the body's commands where it is decided
## or predicted and taken from the snapshot elsewhere, drawn from that state alone on every machine.

const DECOY_GROUP: StringName = &"hologram_decoys"
const SHIELD_RADIUS: float = 4.0
## How far above a body's origin its shield is centred.
const SHIELD_RISE: float = 0.9
## A layer inside the rifle's hit mask that no body's collision mask includes,
## so shots stop on the shell and runners walk out of it.
const SHIELD_LAYER: int = 1 << 19
## The decoy body: hit by the rifle, ignored by every body mask.
const DECOY_LAYER: int = 1 << 18
const DECOY_LEAD_METRES: float = 2.0
const CAMO_VISIBLE_RANGE: float = 25.0
## The whole body's opacity under active camo; its colours never change.
const CAMO_ALPHA: float = 0.25
## One [PowerDef] per [enum MatchRules.RunnerAbility], in its order: the one source of each power's timing.
const DEFS: Array[PowerDef] = [
	preload("res://match/powers/none.tres"),
	preload("res://match/powers/bubble_shield.tres"),
	preload("res://match/powers/hologram.tres"),
	preload("res://match/powers/armor_lock.tres"),
	preload("res://match/powers/active_camo.tres"),
	preload("res://match/powers/cat_grenade.tres"),
]

## This machine's player's pick: kept across scenes, carried into a session's seat, and the seat's while in one.
static var solo_held: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE
## Seeds the bots' picks; once per run.
static var bot_seed: int = randi()

## Power [param which] stopped: "expired", "released", "unheld" (a starved command let the key go),
## "spent" or "cancelled".
signal ended(which: MatchRules.RunnerAbility, reason: StringName)

@export var body: PlayerController

var rules: MatchRules = null
## The power this body's player holds, one or none: their pick, set by the match on every machine.
var held: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE
var match_controller: MatchController = null
## This machine's truth: simulated where it is decided, predicted by its owner, the record elsewhere.
var state: PowerState = PowerState.new()

## A predicting body's snapshot record at this frame's playout clock: its host entity is drawn from it.
var _entity_record: PowerState = PowerState.new()
var _has_entity_record: bool = false
var _view: PowerState = PowerState.new()
## What the visuals show now; [method sync_visuals] diffs against it.
var _drawn: PowerState = PowerState.new()

## The host's entities.
var _decoy: PlayerController = null
var _cat: CatGrenade = null
## The visuals.
var _shield: StaticBody3D = null
var _bubble: MeshInstance3D = null
## This machine decides the power: its shield's collider follows the state, whatever is drawn.
var _collider_from_state: bool = false
## The host: the whole power drawn from this frame's playout record, as the body is.
var _has_playout_record: bool = false
var _shell: MeshInstance3D = null
var _camo_mesh: MeshInstance3D = null
var _hologram: HologramView = null
var _cat_view: CatView = null


## A decoy's intent: straight ahead at run speed, nothing else. It knows whose power it is.
class DecoyIntent:
	extends IntentSource

	var power: RunnerPower = null

	func poll(_delta: float) -> MoveIntent:
		_intent.clear()
		_intent.move_direction = Vector2(0.0, 1.0)
		return _intent


## The ability node of [param node]'s body, or null.
static func of(node: Node) -> RunnerPower:
	var controller: PlayerController = node as PlayerController
	return controller.power if controller != null else null


## The hologram [param collider] belongs to, or null.
static func decoy_of(collider: Node) -> PlayerController:
	var node: Node = collider
	while node != null:
		if node.is_in_group(DECOY_GROUP):
			return node as PlayerController
		node = node.get_parent()
	return null


## [param which]'s definition.
static func def(which: int) -> PowerDef:
	return DEFS[which]


## How long [param which] runs on its clock, in seconds.
static func duration_of(which: int) -> float:
	return DEFS[which].duration_seconds


## A bot's held power: a pick by [param index] and [member bot_seed], never NONE, so bots differ.
static func bot_pick(index: int) -> MatchRules.RunnerAbility:
	return (1 + posmod(hash([bot_seed, index]), DEFS.size() - 1)) as MatchRules.RunnerAbility


## [param seconds] as whole commands: a power's clocks count commands, one a host tick.
static func ticks_of(seconds: float) -> int:
	return maxi(roundi(seconds * float(NetCodec.TICK_RATE)), 0)


func _init() -> void:
	# After the replicator has written this frame's records, so a record is drawn the frame it lands.
	process_priority = 10
	# After every body has moved and before the replicator samples them: the entities' poses.
	process_physics_priority = 90


func _ready() -> void:
	# Only while a host entity is out (the engine turns it on at ready for an overridden callback).
	set_physics_process(_decoy != null or _cat != null)


## A body leaving the tree takes its shield, hologram, shell, tint and cat with it.
func _exit_tree() -> void:
	_free_entities()
	state.active = false
	state.out = false
	state.cooking = false
	state.remaining_ticks = 0
	_has_entity_record = false
	_view.clear()
	sync_visuals(_view)


func _process(_delta: float) -> void:
	sync_visuals(_current_view())
	# A record is this frame's: a body that stops being drawn from one draws its own state.
	_has_entity_record = false
	_has_playout_record = false


## The host: follow the entities' poses into the state, once they have moved this tick.
func _physics_process(_delta: float) -> void:
	_follow_entities()


## One command's worth of the power, run by [method PlayerController.run_command]: its clocks,
## and a press, release or cook. [param authority] simulates what only the host may (decoy, cat).
func step(intent: MoveIntent, _delta: float, authority: bool) -> void:
	if state.cooldown_ticks > 0:
		state.cooldown_ticks -= 1
	if body == null or body.held:
		return
	var asked: int = intent.pressed & MoveIntent.POWER
	if not state.active:
		_rule(intent.pressed & MoveIntent.COOK, &"no-cat")
		if intent.ability_pressed:
			_rule(asked, &"ran" if activate(authority) else refusal())
		return
	if authority and not _has_its_entity():
		# The host runs a power only with its entity: a machine that became the host has none.
		_end(&"spent")
	else:
		var fused: bool = DEFS[state.which].clock == PowerDef.Clock.FUSE
		if fused and intent.cook_pressed:
			state.cooking = true
			_rule(MoveIntent.COOK, &"ran")
		elif not fused:
			_rule(intent.pressed & MoveIntent.COOK, &"no-cat")
		if state.is_timed() and state.remaining_ticks > 0:
			state.remaining_ticks -= 1
		# The clock runs out on the host's word; a predicting client waits for it.
		if DEFS[state.which].ends_on_release and not intent.ability_held:
			_end(&"released" if intent.released & MoveIntent.POWER != 0 else &"unheld")
		elif state.is_timed() and state.remaining_ticks <= 0 and authority:
			if fused:
				_blast()
			else:
				_end(&"expired")
	_rule(asked, &"busy")
	if authority:
		# The host's shield collider stands from the tick it is raised, whenever it is drawn.
		_collider_from_state = true
		_sync_shield_body(state)


## Tell the body what this command made of the keys in [param buttons]; nothing when none went down.
func _rule(buttons: int, ruling: StringName) -> void:
	if buttons != 0:
		body.press_ruled.emit(buttons, ruling)


## Give this node the match's rules and reset it for a fresh placement; [member held] is kept.
func arm(match_rules: MatchRules, controller: MatchController) -> void:
	cancel()
	rules = match_rules
	match_controller = controller
	state.cooldown_ticks = 0


## Start the held power, as the deciding machine when [param authority] (it builds the entity);
## false when none is held, one is running, or the cooldown has not run out.
func activate(authority: bool = true) -> bool:
	if not refusal().is_empty():
		return false
	var which: MatchRules.RunnerAbility = held
	var definition: PowerDef = DEFS[which]
	state.which = which
	state.active = true
	state.serial = (state.serial + 1) % PowerState.SERIAL_MODULUS
	state.remaining_ticks = ticks_of(definition.duration_seconds)
	state.cooking = false
	state.out = definition.entity == PowerDef.Entity.DECOY
	state.place_position = Vector3.ZERO
	state.place_yaw = 0.0
	match definition.place:
		PowerDef.Place.ABOVE:
			state.place_position = body.global_position + Vector3.UP * SHIELD_RISE
		PowerDef.Place.AHEAD:
			var ahead: Vector3 = -body.global_transform.basis.z
			ahead.y = 0.0
			state.place_position = body.global_position + ahead.normalized() * DECOY_LEAD_METRES
			state.place_yaw = body.global_rotation.y
	if definition.holds_body:
		body.velocity = Vector3.ZERO
	state.pose_position = state.place_position
	state.pose_yaw = state.place_yaw
	state.pose_velocity = Vector3.ZERO
	if authority:
		_spawn_entity()
		_collider_from_state = true
		_sync_shield_body(state)
	return true


## Why [method activate] would not start the held power now, or empty when it would.
func refusal() -> StringName:
	if rules == null or body == null:
		return &"unarmed"
	if state.active:
		return &"busy"
	if state.cooldown_ticks > 0:
		return &"cooldown"
	if held == MatchRules.RunnerAbility.NONE:
		return &"unpicked"
	return &""


## Hold [param which] from now, the old one stopped and nothing cooling: the one way [member held] changes,
## the same on every machine, from the seat's word (or the solo pick off a session).
func apply_held(which: MatchRules.RunnerAbility) -> void:
	if which == held:
		return
	cancel()
	state.cooldown_ticks = 0
	held = which


## Stop the power without starting a cooldown.
func cancel() -> void:
	var was: int = state.running()
	_stop()
	if was != MatchRules.RunnerAbility.NONE:
		ended.emit(was, &"cancelled")


## Take [param record]'s power as this machine's state: a body it draws and does not simulate.
func take_record(record: PlayerState) -> void:
	_has_entity_record = false
	state.take_record(record)


## For a body this machine predicts: [param record] at this frame's playout clock, for its host entity.
func take_entity_record(record: PlayerState) -> void:
	_has_entity_record = true
	_entity_record.take_record(record)


## The host, for a body it draws at its playout: [param record] at that clock, for everything drawn.
func take_playout_record(record: PlayerState) -> void:
	_has_playout_record = true
	_entity_record.take_record(record)


## The readout (DESIGN 9), the same on every screen: the held power, then the run and the wait left, 1 to 0.
func get_held() -> MatchRules.RunnerAbility:
	return held


## The run left of the running power, 1 to 0 (an unlit cat is whole); 0 when none runs.
func get_active_fraction() -> float:
	if not state.active:
		return 0.0
	if not state.is_timed():
		return 1.0
	return clampf(float(state.remaining_ticks) / float(maxi(ticks_of(duration_of(state.which)), 1)), 0.0, 1.0)


## The cooldown left of the last power, 1 to 0; 0 when it is ready.
func get_cooldown_fraction() -> float:
	if state.cooldown_ticks <= 0:
		return 0.0
	return clampf(float(state.cooldown_ticks) / float(maxi(_cooldown_ticks_of(state.which), 1)), 0.0, 1.0)


func is_active() -> bool:
	return state.active


## The power running now, or NONE.
func get_active() -> MatchRules.RunnerAbility:
	return state.running() as MatchRules.RunnerAbility


## The power of the running or the last activation: what a cooldown is cooling.
func get_last() -> MatchRules.RunnerAbility:
	return state.which as MatchRules.RunnerAbility


## The power this machine draws, or NONE.
func get_shown() -> MatchRules.RunnerAbility:
	return _drawn.running() as MatchRules.RunnerAbility


func get_remaining() -> float:
	return state.get_remaining() if state.active else 0.0


func get_cooldown_remaining() -> float:
	return state.get_cooldown()


## True while the running power holds its body still (the armor lock).
func holds_body() -> bool:
	return state.active and DEFS[state.which].holds_body


func is_hit_immune() -> bool:
	return holds_body()


func is_camouflaged() -> bool:
	return state.running() == MatchRules.RunnerAbility.ACTIVE_CAMO


## True while this body carries its own cat, so its swing is the throw.
func holds_cat() -> bool:
	return state.active and DEFS[state.which].entity == PowerDef.Entity.CAT and not state.out


## Shove while carrying the cat: throw it, lit. True when a cat took the shove. Authority only.
func throw_cat() -> bool:
	if not holds_cat() or not is_instance_valid(_cat) or not _cat.throw():
		return false
	state.out = true
	state.cooking = true
	_follow_entities()
	return true


## The shield's collider here (it stops shots), or null.
func get_shield() -> StaticBody3D:
	return _shield


## The shield as drawn here, or null: on the host a remote one is drawn at its playout.
func get_bubble() -> MeshInstance3D:
	return _bubble


## The armor lock's shell drawn here, or null.
func get_shell() -> MeshInstance3D:
	return _shell


## The hologram drawn here, or null.
func get_hologram() -> HologramView:
	return _hologram


## The cat drawn here, carried or thrown, or null.
func get_cat_view() -> CatView:
	return _cat_view


## The host's decoy body, or null.
func get_decoy() -> PlayerController:
	return _decoy if is_instance_valid(_decoy) and not _decoy.is_queued_for_deletion() else null


## The host's cat body, or null.
func get_cat() -> CatGrenade:
	return _cat if is_instance_valid(_cat) else null


## A decoy the rifle has hit is gone, and its power says so.
static func shatter(decoy: PlayerController) -> void:
	if decoy == null or decoy.is_queued_for_deletion():
		return
	var source: DecoyIntent = decoy.intent_source as DecoyIntent
	if source != null and source.power != null and source.power._decoy == decoy:
		source.power._lose_decoy()
	else:
		decoy.queue_free()


func _end(reason: StringName) -> void:
	var was: int = state.running()
	_stop()
	state.cooldown_ticks = _cooldown_ticks_of(was)
	ended.emit(was, reason)


## [param which]'s cooldown in commands: its own seconds times the rules' live multiplier.
func _cooldown_ticks_of(which: int) -> int:
	var multiplier: float = rules.ability_cooldown_multiplier if rules != null else 1.0
	return ticks_of(DEFS[which].cooldown_seconds * multiplier)


func _stop() -> void:
	_free_entities()
	state.active = false
	state.out = false
	state.cooking = false
	state.remaining_ticks = 0


# --- Host entities ------------------------------------------------------------

func _spawn_entity() -> void:
	match DEFS[state.which].entity:
		PowerDef.Entity.DECOY:
			_spawn_decoy()
		PowerDef.Entity.CAT:
			var cat: CatGrenade = CatGrenade.new()
			cat.carrier = body
			body.get_parent().add_child(cat)
			_cat = cat
	set_physics_process(_decoy != null or _cat != null)


## The host's hologram: a runner body with no brain, no avatar and no power, driven straight ahead.
func _spawn_decoy() -> void:
	if match_controller == null or match_controller.runner_scene == null:
		state.out = false
		return
	var decoy: PlayerController = match_controller.runner_scene.instantiate() as PlayerController
	if decoy == null:
		state.out = false
		return
	decoy.name = "Hologram"
	for child: Node in decoy.get_children():
		if child is RunnerBrain or child is IntentSource or child is PrisonerAvatar or child is RunnerPower \
				or child.name == &"BodyMesh":
			decoy.remove_child(child)
			child.free()
	var source: DecoyIntent = DecoyIntent.new()
	source.name = "DecoyInput"
	source.power = self
	decoy.add_child(source)
	decoy.intent_source = source
	# A hologram is a target and never a runner: nothing that lists runners may list it.
	decoy.remove_from_group(MatchController.RUNNER_GROUP)
	decoy.add_to_group(DECOY_GROUP)
	var container: Node3D = match_controller.runner_container
	decoy.position = container.to_local(state.place_position)
	decoy.rotation = Vector3(0.0, state.place_yaw, 0.0)
	# Shots stop on it (the rifle mask spans every layer); bodies walk through it.
	decoy.collision_layer = DECOY_LAYER
	decoy.collision_mask = 1
	container.add_child(decoy)
	_decoy = decoy


## True unless this power stands on a host entity this machine does not have.
func _has_its_entity() -> bool:
	match DEFS[state.which].entity:
		PowerDef.Entity.CAT:
			return is_instance_valid(_cat)
		PowerDef.Entity.DECOY:
			return not state.out or is_instance_valid(_decoy)
	return true


func _lose_decoy() -> void:
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null
	state.out = false
	set_physics_process(_cat != null)


## The fuse ran out: the push is host physics, the blast a cue to every machine (DESIGN 6).
func _blast() -> void:
	var at: Vector3 = _cat.blast_point() if is_instance_valid(_cat) else body.global_position
	if match_controller != null:
		CatGrenade.push_all(match_controller.get_participants_ref(), at)
	var link: PlayerNetLink = PlayerNetLink.of(body)
	if link != null and link.replicator != null and link.session != null and link.session.is_established():
		link.replicator.send_event(NetEvents.Type.CAT_BLAST, NetCodec.pack_point(0, at))
	CatView.play_blast(body.get_parent(), at)
	_end(&"spent")


func _follow_entities() -> void:
	if is_instance_valid(_decoy) and state.out:
		state.pose_position = _decoy.global_position
		state.pose_yaw = _decoy.rotation.y
		state.pose_velocity = _decoy.velocity
	if is_instance_valid(_cat) and state.out:
		state.pose_position = _cat.global_position
		state.pose_yaw = _cat.rotation.y
		state.pose_velocity = _cat.linear_velocity


func _free_entities() -> void:
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null
	if is_instance_valid(_cat):
		_cat.queue_free()
	_cat = null
	set_physics_process(false)


# --- Drawing ------------------------------------------------------------------

## What this machine draws: its state, with the host entity a predicting body sees from the record.
func _current_view() -> PowerState:
	if _has_playout_record:
		return _entity_record
	if not _has_entity_record:
		return state
	var record: PowerState = _entity_record
	if not record.active or DEFS[record.which].entity == PowerDef.Entity.NONE:
		return state
	if not state.active:
		# Over here and not yet at the playout clock: the host's entity is drawn until it is.
		return record
	_view.copy_from(state)
	if record.serial != state.serial or record.which != state.which:
		# The host's entity is drawn once a record has it (DESIGN 7); the rest is as predicted.
		_view.out = false
		return _view
	_view.out = record.out
	_view.pose_position = record.pose_position
	_view.pose_yaw = record.pose_yaw
	_view.pose_velocity = record.pose_velocity
	return _view


## Build, move and tear down the visuals so they show [param view]: the only place they are made.
func sync_visuals(view: PowerState) -> void:
	if body == null:
		return
	_sync_effect(view)
	_sync_shield_body(state if _collider_from_state else view)
	_draw_hologram(view)
	_draw_cat(view)


## The shield's collider, standing while [param source] has the shield up.
func _sync_shield_body(source: PowerState) -> void:
	if _shield != null and not is_instance_valid(_shield):
		_shield = null
	var up: bool = source.running() == MatchRules.RunnerAbility.BUBBLE_SHIELD
	if up and _shield == null and body != null and body.get_parent() != null:
		_raise_shield()
	elif not up and _shield != null:
		# Out of every ray this tick, not only once the frame ends.
		_shield.collision_layer = 0
		_shield.queue_free()
		_shield = null
	if _shield != null and _shield.global_position != source.place_position:
		_shield.global_position = source.place_position


## The bubble, shell or tint [param view] shows; the host entities' views are drawn per frame only.
func _sync_effect(view: PowerState) -> void:
	_forget_freed_visuals()
	var effect: int = view.running() if DEFS[view.which].entity == PowerDef.Entity.NONE else 0
	var drawn_effect: int = _drawn.running() if DEFS[_drawn.which].entity == PowerDef.Entity.NONE else 0
	if effect != drawn_effect:
		_tear_down_effect()
		match effect:
			MatchRules.RunnerAbility.BUBBLE_SHIELD:
				_bubble = _build_shield_mesh()
				_stage().add_child(_bubble)
			MatchRules.RunnerAbility.ARMOR_LOCK:
				_raise_shell()
	if effect == MatchRules.RunnerAbility.ACTIVE_CAMO:
		_cloak()
	if _bubble != null and _bubble.global_position != view.place_position:
		_bubble.global_position = view.place_position
	_drawn.copy_from(view)


## A visual freed with the container it stands in (a rebuilt roster) is drawn again from state.
func _forget_freed_visuals() -> void:
	if (_bubble != null and not is_instance_valid(_bubble)) or (_shell != null and not is_instance_valid(_shell)):
		_bubble = null
		_shell = null
		_drawn.clear()
	if _hologram != null and not is_instance_valid(_hologram):
		_hologram = null
	if _cat_view != null and not is_instance_valid(_cat_view):
		_cat_view = null


func _tear_down_effect() -> void:
	if _bubble != null:
		_bubble.queue_free()
		_bubble = null
	if _shell != null:
		_shell.queue_free()
		_shell = null
	_uncloak()


func _draw_hologram(view: PowerState) -> void:
	if not view.active or DEFS[view.which].entity != PowerDef.Entity.DECOY or not view.out or not is_inside_tree():
		if _hologram != null:
			_hologram.queue_free()
			_hologram = null
		return
	if _hologram == null:
		_hologram = HologramView.build(body)
		_stage().add_child(_hologram)
	_hologram.pose(view.pose_position, view.pose_yaw, view.pose_velocity)


func _draw_cat(view: PowerState) -> void:
	if not view.active or DEFS[view.which].entity != PowerDef.Entity.CAT or not is_inside_tree():
		if _cat_view != null:
			_cat_view.queue_free()
			_cat_view = null
		return
	if _cat_view == null:
		_cat_view = CatView.new()
		_stage().add_child(_cat_view)
	if view.out:
		_cat_view.global_transform = Transform3D(Basis(Vector3.UP, view.pose_yaw), view.pose_position)
	else:
		# In the hands this machine draws: on the host a remote carrier's are its playout behind.
		var link: PlayerNetLink = PlayerNetLink.of(body)
		_cat_view.global_transform = CatView.carry_transform(body)
		if link != null:
			_cat_view.global_position += link.drawn_offset()
	_cat_view.set_petting(not view.out and _carried_here())


## True when the body is this machine's own player: its link's owner (none once the session is
## gone), or with no session the human's.
func _carried_here() -> bool:
	var link: PlayerNetLink = PlayerNetLink.of(body)
	if link != null:
		return link.is_owned_here()
	return body.intent_source is HumanIntentSource


## Where a hologram or a cat is drawn: beside the body.
func _stage() -> Node:
	return body.get_parent()


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
	_stage().add_child(shield)
	_shield = shield


static func _build_shield_mesh() -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = SHIELD_RADIUS
	sphere_mesh.height = SHIELD_RADIUS * 2.0
	mesh.mesh = sphere_mesh
	mesh.material_override = _glow_material(Color(0.35, 0.75, 1.0, 0.3), Color(0.2, 0.6, 1.0), 1.5)
	return mesh


## The armor lock's glowing shell. The hold is the power's state, read by [method PlayerController._move].
func _raise_shell() -> void:
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


## Fade the body's mesh, or the one it has now; a mesh not built yet is faded the frame it appears.
func _cloak() -> void:
	var mesh: MeshInstance3D = _avatar_mesh(body)
	if mesh == _camo_mesh:
		return
	_uncloak()
	if mesh != null:
		_camo_mesh = mesh
		BodyMaterial.of(mesh).set_fade(CAMO_ALPHA)


func _uncloak() -> void:
	if _camo_mesh != null and is_instance_valid(_camo_mesh):
		BodyMaterial.of(_camo_mesh).set_fade(1.0)
	_camo_mesh = null


## [param which]'s own visual standing alone (a hub stand's), built by the code that draws it; null for NONE.
static func build_display(which: int) -> Node3D:
	match which:
		MatchRules.RunnerAbility.BUBBLE_SHIELD:
			return _build_shield_mesh()
		MatchRules.RunnerAbility.ARMOR_LOCK:
			return _build_shell()
		MatchRules.RunnerAbility.CAT_GRENADE:
			return CatView.new()
		MatchRules.RunnerAbility.HOLOGRAM, MatchRules.RunnerAbility.ACTIVE_CAMO:
			var figure: HologramView = HologramView.build(null)
			if which == MatchRules.RunnerAbility.ACTIVE_CAMO and figure.mesh != null:
				BodyMaterial.of(figure.mesh).set_fade(CAMO_ALPHA)
			return figure
	return null


## What this body's powers draw when they run, for [SceneWarmup]; built by the code that draws them.
func warmup_samples() -> Array[Node3D]:
	var samples: Array[Node3D] = [_build_shell(), _build_shield_mesh(), CatView.build_blast_sprite(), CatView.new()]
	if body != null:
		samples.append(HologramView.build(body))
	var avatar: MeshInstance3D = _avatar_mesh(body) if body != null else null
	if avatar != null and avatar.mesh != null:
		var cloaked: MeshInstance3D = MeshInstance3D.new()
		cloaked.mesh = avatar.mesh
		BodyMaterial.of(avatar).dress(cloaked, CAMO_ALPHA)
		samples.append(cloaked)
	return samples


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
