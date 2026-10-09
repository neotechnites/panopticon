@tool
class_name TrapDoor
extends Node3D

## A hinged trapdoor in the walkway with its lever: a shove beside the lever, or a
## rifle hit on its handle, drops both leaves into the spiked pit under them.
## The whole cycle is a pure function of the seconds since the pull, so the host
## sends one reliable (cycle, seconds) per pull and every peer animates the same.

enum Phase { ARMED, WARN, DROP, OPEN, CLOSE, COOLDOWN }

## Where the lever stands, in this node's frame (+Z is the way the lap runs).
@export var lever_offset: Vector3 = Vector3(-2.18, 0.0, -5.15):
	set(value):
		lever_offset = value
		_place_lever()
## The lever's turn about Y, so it can face the lane where it stands.
@export_range(-180.0, 180.0, 0.01) var lever_yaw_degrees: float = 6.23:
	set(value):
		lever_yaw_degrees = value
		_place_lever()

@export_group("Timing")
## The rattle before the drop: the only warning a runner on it gets.
@export_range(0.0, 2.0, 0.01) var warn_seconds: float = 0.3
## The leaves' swing from flat to hanging.
@export_range(0.05, 2.0, 0.01) var drop_seconds: float = 0.35
## Open time, from the end of the rattle to the start of the close.
@export_range(0.5, 20.0, 0.1) var open_seconds: float = 4.0
@export_range(0.1, 3.0, 0.05) var close_seconds: float = 0.8
## From the pull until it can be pulled again.
@export_range(1.0, 60.0, 0.5) var rearm_seconds: float = 10.0

@export_group("Bots")
## Chance, rolled once per arming, that a bot next to the lever pulls it on a rival.
@export_range(0.0, 1.0, 0.05) var bot_pull_chance: float = 0.5

## The lethal footprint over the hole, in this node's frame: what [RingBake] steers round.
@export var hole_size_metres: Vector3 = Vector3(5.2, 1.4, 2.5)

## The hitbox layer the rifle hits and nothing walks into (inside WeaponProfile.hit_mask).
const SHOT_TARGET_LAYER: int = 1 << 17
const LEAF_DROP_RADIANS: float = PI * 0.5
const LEAF_RATTLE_RADIANS: float = 0.03
const LEAF_RATTLE_HZ: float = 38.0
const HANDLE_REST_RADIANS: float = -0.61
const HANDLE_THROWN_RADIANS: float = 0.61
const HANDLE_THROW_SECONDS: float = 0.12
const HANDLE_RETURN_SECONDS: float = 1.0
## How far before the hole, along the lap, a rival counts as about to cross it.
const BOT_LEAD_METRES: float = 3.0
const SESSION_PATH: NodePath = ^"/root/NetSession"
const RNG_SEED: int = 20261008

## Every live door, for [RingBake] and the bots' lever hook. Never iterated in the editor.
static var live: Array[TrapDoor] = []

var _cycle: int = 0
var _since_pull: float = INF
var _phase: Phase = Phase.ARMED
var _leaves: Array[Node3D] = []
var _leaf_rest: Array[Transform3D] = []
var _leaf_bodies: Array[AnimatableBody3D] = []
var _lever: Node3D = null
var _handle: Node3D = null
var _handle_rest: Transform3D = Transform3D.IDENTITY
var _hitbox: StaticBody3D = null
var _reach: Area3D = null
var _reachers: Array[PlayerController] = []
var _reach_calls: Array[Callable] = []
var _session: NetSession = null
var _hit_since_msec: int = 0
var _bots_may_pull: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_place_lever()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_rng.seed = RNG_SEED + int(absf(global_position.x) * 100.0) + int(absf(global_position.z) * 10.0)
	_session = get_tree().root.get_node_or_null(SESSION_PATH) as NetSession
	_find_parts()
	_roll_bots()
	_hit_since_msec = Time.get_ticks_msec()
	_pose(0.0)


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not live.has(self):
		live.append(self)


func _exit_tree() -> void:
	live.erase(self)


func _physics_process(delta: float) -> void:
	if _since_pull < INF:
		_since_pull += delta
	var phase: Phase = _phase_at(_since_pull)
	if phase != _phase:
		_enter(phase)
	_pose(_since_pull)
	if _phase == Phase.ARMED and _hitbox != null and _decides():
		var slot: int = Rifle.recent_hit_on(_hitbox, _hit_since_msec)
		if slot >= 0:
			pull()


# --- The trigger --------------------------------------------------------------

## Throw the lever. Only the host decides; a mirror waits for [method _net_pulled].
func pull() -> bool:
	if _phase != Phase.ARMED or not _decides():
		return false
	_start_cycle(_cycle + 1, 0.0)
	_broadcast()
	return true


## True from the rattle to the end of the close: the hole is, or is about to be, open.
func is_open() -> bool:
	return _phase != Phase.ARMED and _phase != Phase.COOLDOWN


func is_armed() -> bool:
	return _phase == Phase.ARMED


func get_phase() -> Phase:
	return _phase


## The lever's world position, for bots and tests.
func get_lever_position() -> Vector3:
	return _lever.global_position if _lever != null else global_position


## True when [param point] stands over the hole (within [param margin]) while it is open.
func is_lethal_at(point: Vector3, margin: float = 0.0) -> bool:
	if not is_open():
		return false
	return covers(point, margin)


## True when [param point] is over the hole's footprint and at or under the deck.
func covers(point: Vector3, margin: float = 0.0) -> bool:
	var local: Vector3 = global_transform.affine_inverse() * point
	var half: Vector3 = hole_size_metres * 0.5
	return (
		absf(local.x) <= half.x + margin and absf(local.z) <= half.z + margin
		and local.y <= 0.05 + margin and local.y >= -hole_size_metres.y - margin
	)


## A bot at [param body] beside an armed lever, with a rival about to cross the hole.
static func bot_wants_pull(body: PlayerController, rivals: Array[Node]) -> bool:
	for door: TrapDoor in live:
		if door._wants_pull(body, rivals):
			return true
	return false


func _wants_pull(body: PlayerController, rivals: Array[Node]) -> bool:
	if not _bots_may_pull or _phase != Phase.ARMED or not _reachers.has(body):
		return false
	var to_local: Transform3D = global_transform.affine_inverse()
	var half: Vector3 = hole_size_metres * 0.5
	for node: Node in rivals:
		var rival: PlayerController = node as PlayerController
		if rival == null or rival == body or not is_instance_valid(rival):
			continue
		var local: Vector3 = to_local * rival.global_position
		if absf(local.x) <= half.x and local.z >= -half.z - BOT_LEAD_METRES and local.z <= 0.0 and absf(local.y) < 1.0:
			return true
	return false


func _on_reach_entered(body: Node3D) -> void:
	var walker: PlayerController = body as PlayerController
	if walker == null or _reachers.has(walker):
		return
	var call: Callable = _on_reacher_shoved.bind(walker)
	_reachers.append(walker)
	_reach_calls.append(call)
	walker.shoved.connect(call)


func _on_reach_exited(body: Node3D) -> void:
	var walker: PlayerController = body as PlayerController
	if walker == null or not _reachers.has(walker):
		return
	var index: int = _reachers.find(walker)
	var call: Callable = _reach_calls[index]
	_reachers.remove_at(index)
	_reach_calls.remove_at(index)
	if walker.shoved.is_connected(call):
		walker.shoved.disconnect(call)


## A shove swung beside the lever throws it; the shove itself is still the match's.
func _on_reacher_shoved(_walker: PlayerController) -> void:
	pull()


# --- The network ---------------------------------------------------------------

## The host decides: no session, an unestablished one, or the authority.
func _decides() -> bool:
	return _session == null or not _session.is_established() or _session.is_authority()


func _broadcast() -> void:
	if _session == null or not _session.is_established() or not _session.is_authority():
		return
	var lobby: NetLobby = _session.lobby
	for peer: int in _session.get_peer_ids():
		if peer == NetTransport.AUTHORITY_PEER_ID:
			continue
		if lobby != null and not lobby.has_launched(peer):
			continue
		rpc_id(peer, &"_net_pulled", _cycle, _since_pull)


@rpc("authority", "reliable", "call_remote", 0)
func _net_pulled(cycle: int, seconds: float) -> void:
	if cycle <= _cycle:
		return
	_start_cycle(cycle, seconds)


# --- The clock -----------------------------------------------------------------

func _start_cycle(cycle: int, seconds: float) -> void:
	_cycle = cycle
	_since_pull = seconds
	_enter(_phase_at(_since_pull))
	_pose(_since_pull)


func _phase_at(seconds: float) -> Phase:
	if seconds >= rearm_seconds:
		return Phase.ARMED
	if seconds < warn_seconds:
		return Phase.WARN
	if seconds < warn_seconds + drop_seconds:
		return Phase.DROP
	if seconds < warn_seconds + open_seconds:
		return Phase.OPEN
	if seconds < warn_seconds + open_seconds + close_seconds:
		return Phase.CLOSE
	return Phase.COOLDOWN


func _enter(phase: Phase) -> void:
	_phase = phase
	match phase:
		Phase.WARN:
			AudioDirector.post_event_at(AudioEvents.HAZARD_LEVER_THROWN, get_lever_position())
			AudioDirector.post_event_at(AudioEvents.HAZARD_TRAPDOOR_RATTLE, global_position)
		Phase.DROP:
			AudioDirector.post_event_at(AudioEvents.HAZARD_TRAPDOOR_DROP, global_position)
		Phase.COOLDOWN:
			AudioDirector.post_event_at(AudioEvents.HAZARD_TRAPDOOR_SHUT, global_position)
		Phase.ARMED:
			_since_pull = INF
			_hit_since_msec = Time.get_ticks_msec()
			_roll_bots()


func _roll_bots() -> void:
	_bots_may_pull = _rng.randf() < bot_pull_chance


# --- The pose ------------------------------------------------------------------

## Leaves and handle at [param seconds] since the pull.
func _pose(seconds: float) -> void:
	var leaf: float = _leaf_angle(seconds)
	for index: int in _leaves.size():
		var pose: Transform3D = _leaf_rest[index] * Transform3D(Basis(Vector3.RIGHT, leaf), Vector3.ZERO)
		_leaves[index].transform = pose
		if index < _leaf_bodies.size():
			_leaf_bodies[index].transform = pose
	if _handle != null:
		var turn: Transform3D = Transform3D(Basis(Vector3.RIGHT, _handle_angle(seconds)), Vector3.ZERO)
		_handle.transform = _handle_rest * turn


func _leaf_angle(seconds: float) -> float:
	match _phase_at(seconds):
		Phase.WARN:
			return LEAF_RATTLE_RADIANS * (0.5 + 0.5 * sin(seconds * TAU * LEAF_RATTLE_HZ))
		Phase.DROP:
			var t: float = (seconds - warn_seconds) / drop_seconds
			return LEAF_DROP_RADIANS * t * t
		Phase.OPEN:
			return LEAF_DROP_RADIANS
		Phase.CLOSE:
			var t: float = (seconds - warn_seconds - open_seconds) / close_seconds
			return LEAF_DROP_RADIANS * (1.0 - smoothstep(0.0, 1.0, t))
	return 0.0


func _handle_angle(seconds: float) -> float:
	if seconds >= rearm_seconds:
		return HANDLE_REST_RADIANS
	var thrown: float = clampf(seconds / HANDLE_THROW_SECONDS, 0.0, 1.0)
	var back: float = clampf((seconds - (rearm_seconds - HANDLE_RETURN_SECONDS)) / HANDLE_RETURN_SECONDS, 0.0, 1.0)
	return lerpf(HANDLE_REST_RADIANS, HANDLE_THROWN_RADIANS, thrown * (1.0 - smoothstep(0.0, 1.0, back)))


# --- The parts -----------------------------------------------------------------

func _place_lever() -> void:
	var lever: Node3D = get_node_or_null(^"Lever") as Node3D
	if lever == null:
		return
	lever.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(lever_yaw_degrees)), lever_offset)


func _find_parts() -> void:
	var model: Node3D = get_node_or_null(^"Model") as Node3D
	for leaf_name: String in ["TrapdoorLeafA", "TrapdoorLeafB"]:
		var leaf: Node3D = model.find_child(leaf_name, true, false) as Node3D if model != null else null
		if leaf == null:
			push_warning("TrapDoor at %s has no %s; it will not open." % [get_path(), leaf_name])
			continue
		var rest: Transform3D = model.transform * leaf.transform
		# The mesh is re-parented under this node so its pose and its body's share one frame.
		leaf.get_parent().remove_child(leaf)
		add_child(leaf)
		leaf.transform = rest
		_leaves.append(leaf)
		_leaf_rest.append(rest)
		_leaf_bodies.append(_make_leaf_body(leaf, rest))
	_lever = get_node_or_null(^"Lever") as Node3D
	if _lever != null:
		var lever_model: Node3D = _lever.get_node_or_null(^"Model") as Node3D
		_handle = lever_model.find_child("MarbleLeverHandle", true, false) as Node3D if lever_model != null else null
		if _handle != null:
			_handle_rest = _handle.transform
		_hitbox = _lever.get_node_or_null(^"HandleHitbox") as StaticBody3D
		if _hitbox != null and _handle != null:
			# Authored in the handle's own frame; parented to it so it swings with it.
			var authored: Transform3D = _hitbox.transform
			_hitbox.collision_layer = SHOT_TARGET_LAYER
			_hitbox.collision_mask = 0
			_lever.remove_child(_hitbox)
			_handle.add_child(_hitbox)
			_hitbox.transform = authored
		_reach = _lever.get_node_or_null(^"Reach") as Area3D
		if _reach != null:
			_reach.body_entered.connect(_on_reach_entered)
			_reach.body_exited.connect(_on_reach_exited)


func _make_leaf_body(leaf: Node3D, rest: Transform3D) -> AnimatableBody3D:
	var body: AnimatableBody3D = AnimatableBody3D.new()
	body.name = String(leaf.name) + "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	body.sync_to_physics = true
	var bounds: AABB = _mesh_bounds(leaf)
	var holder: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = bounds.size
	holder.shape = box
	holder.position = bounds.get_center()
	body.add_child(holder)
	add_child(body)
	body.transform = rest
	return body


func _mesh_bounds(leaf: Node3D) -> AABB:
	var visual: MeshInstance3D = leaf as MeshInstance3D
	if visual == null:
		visual = leaf.find_child("*", true, false) as MeshInstance3D
	if visual == null or visual.mesh == null:
		return AABB(Vector3(-2.5, -0.15, 0.0), Vector3(5.0, 0.15, 1.2))
	return visual.mesh.get_aabb()
