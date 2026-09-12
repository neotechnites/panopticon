class_name SpeedPowerup
extends Area3D

## A race-only pickup: touch it, run at [member speed_multiplier] for
## [member duration_seconds]. Placed at the end of the hard route through a
## section so there is a reason to take it.
##
## Detection matches [TrapVolume]: layer 0, mask bit 0 (a living body) and bit
## 20 ([constant MatchController.GHOST_HAZARD_LAYER]), monitorable off, an
## empty [CollisionShape3D] child sized from [member size_metres] on ready.
##
## It finds the match the way [PhaseGate] does -- duck-typed, no [NodePath] --
## because the arena this scene lives in has no [MatchController] of its own.
## With none found, [member race_only] is not enforced: the same "nothing to
## gate against" default [PhaseGate] uses.

@export var speed_multiplier: float = 3.0
@export var duration_seconds: float = 7.0
@export var race_only: bool = true

## How big the trigger is, in metres, as full extents. Same axes as
## [member TrapVolume.size_metres].
@export var size_metres: Vector3 = Vector3(1.5, 2.0, 1.5)

## The child that hovers, spins and bobs -- the orb model.
@export var orb: Node3D = null

## The controller to gate against. Leave unset and, with [member auto_discover]
## on, the first match in the running scene is used.
@export var controller: Node = null

## Where discovery starts. Defaults to the root of the scene this node is in.
@export var search_root: Node = null

## Search the scene for a controller when one was not assigned.
@export var auto_discover: bool = true

const HOVER_HEIGHT_METRES: float = 1.2
const _SPIN_RADIANS_PER_SECOND: float = 1.2
const _BOB_METRES: float = 0.15
const _BOB_RADIANS_PER_SECOND: float = 1.6

var _controller: Node = null
var _bob_phase: float = 0.0
var _armed: bool = true


func _ready() -> void:
	_build_shape()
	_controller = _resolve_controller()
	if _controller != null:
		_controller.connect(&"race_started", _on_race_started)
		if race_only:
			_controller.connect(&"round_started", _on_round_started)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if orb == null:
		return
	orb.rotate_y(_SPIN_RADIANS_PER_SECOND * delta)
	_bob_phase += _BOB_RADIANS_PER_SECOND * delta
	orb.position.y = HOVER_HEIGHT_METRES + sin(_bob_phase) * _BOB_METRES


# --- Geometry -----------------------------------------------------------------


func _build_shape() -> void:
	var holder: CollisionShape3D = _find_shape_holder()
	if holder == null:
		push_warning("SpeedPowerup at %s has no CollisionShape3D child; it will boost nobody." % get_path())
		return
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size_metres
	holder.shape = box


func _find_shape_holder() -> CollisionShape3D:
	for child: Node in get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


# --- Contact --------------------------------------------------------------


func _on_body_entered(body: Node3D) -> void:
	if not _armed:
		return
	if race_only and _controller != null and int(_controller.call(&"get_phase")) != MatchController.Phase.RACE:
		return
	var player: PlayerController = body as PlayerController
	if player == null:
		return
	player.apply_speed_boost(speed_multiplier, duration_seconds)
	_armed = false
	if orb != null:
		orb.visible = false
	# Deferred: Area3D refuses to change monitoring from inside its own
	# body_entered dispatch.
	set_deferred(&"monitoring", false)


## Re-arm when a new race starts, exactly as [PhaseGate] re-presents its
## content on the same signal.
func _on_race_started() -> void:
	_armed = true
	if orb != null:
		orb.visible = true
	monitoring = true


## Race-only: gone for the rounds.
func _on_round_started() -> void:
	_armed = false
	if orb != null:
		orb.visible = false
	set_deferred(&"monitoring", false)


# --- Finding the match, exactly as scripts/match/phase_gate.gd does -----------


func _resolve_controller() -> Node:
	if controller != null:
		return controller
	if not auto_discover:
		return null
	var root: Node = search_root if search_root != null else _default_search_root()
	return _find_controller(root) if root != null else null


func _default_search_root() -> Node:
	if not is_inside_tree():
		return get_parent()
	var window: Window = get_tree().root
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != window:
		node = node.get_parent()
	return node


func _find_controller(node: Node) -> Node:
	if _looks_like_controller(node):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_controller(child)
		if found != null:
			return found
	return null


func _looks_like_controller(node: Node) -> bool:
	return node != self and node.has_signal(&"race_started") \
		and node.has_signal(&"round_started") and node.has_method(&"get_phase")
