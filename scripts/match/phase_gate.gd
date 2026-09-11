class_name PhaseGate
extends Node3D

## Content that exists in only one phase of the match. Race-only geometry sits
## under a "Race only" gate, shooter-round-only geometry under "Rounds only" --
## drag [code]scenes/ring/race_only.tscn[/code] or [code]rounds_only.tscn[/code]
## in and reparent walls, pads, lava or boulders under it.
##
## Gated by REMOVAL, not visibility: a hidden [Area3D] still fires and a hidden
## [StaticBody3D] still collides, but a node taken out of the tree does
## neither, and the navmesh stops seeing it too. Children are kept, not freed,
## and put straight back when the phase returns.
##
## [b]Finds the match by shape, not by name.[/b] Anything in the running scene
## with [signal race_started], [signal round_started] and [method get_phase]
## counts as the controller -- a climb from the scene root, no [NodePath] to
## wire. With none found (the editor, a bare test scene) every child stays
## present and nothing is ever removed.

const RACE_ONLY: int = 0
const ROUNDS_ONLY: int = 1

@export_enum("Race only", "Rounds only") var phase: int = RACE_ONLY

## The controller to gate against. Leave unset and, with [member auto_discover]
## on, the first match in the running scene is used.
@export var controller: Node = null

## Where discovery starts. Defaults to the root of the scene this node is in.
@export var search_root: Node = null

## Search the scene for a controller when one was not assigned.
@export var auto_discover: bool = true

var _controller: Node = null
var _held: Array[Node] = []
var _present: bool = true


func _ready() -> void:
	_controller = _resolve_controller()
	if _controller == null:
		return
	_controller.connect(&"race_started", _on_race_started)
	_controller.connect(&"round_started", _on_round_started)
	_apply(_wants_present(_controller.call(&"get_phase")))


func _on_race_started() -> void:
	_apply(_wants_present(MatchController.Phase.RACE))


func _on_round_started() -> void:
	_apply(_wants_present(MatchController.Phase.ROUND))


## Whether this gate's content belongs in [param current_phase]. IDLE reads as
## the race side and MATCH_OVER as the round side: a match only ever reaches
## either by way of one of the two signals this gate already listens to.
func _wants_present(current_phase: int) -> bool:
	var round_side: bool = current_phase == MatchController.Phase.ROUND \
		or current_phase == MatchController.Phase.MATCH_OVER
	return round_side if phase == ROUNDS_ONLY else not round_side


func _apply(present: bool) -> void:
	if present == _present:
		return
	_present = present
	if present:
		for child: Node in _held:
			add_child(child)
		_held.clear()
	else:
		_held = get_children()
		for child: Node in _held:
			remove_child(child)
	# Deferred so several gates swapping on the same signal all land before the
	# navmesh reads the result -- gate first, bake once, after.
	get_tree().call_group.call_deferred(RingNavigation.GROUP, "phase_geometry_changed")


func _resolve_controller() -> Node:
	if controller != null:
		return controller
	if not auto_discover:
		return null
	var root: Node = search_root if search_root != null else _default_search_root()
	return _find_controller(root) if root != null else null


## The highest ancestor below the [SceneTree]'s root window -- in practice the
## root of the running scene.
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
