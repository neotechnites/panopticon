class_name KillVolume
extends Area3D

## The volume under the arena that kills whatever falls into it.
##
## PANOPTICON's middle is a drop, not a shortcut: the deck is an annulus and the
## courtyard floor is twelve metres below it, with the guard's platform standing
## alone in the middle of the hole. Until this node existed that floor CAUGHT
## people -- a prisoner who mistimed a jump and a guard who walked off the edge
## of their own stand both ended up standing at the bottom of the pit for the
## rest of the round, alive, unreachable, and out of the game without being out
## of it. This is the answer: a trigger filling the courtyard from just under the
## deck down past the pit floor, that hands whatever enters it to the match.
##
## [b]It rules on nothing.[/b] It resolves the body to a participant and calls
## [method MatchController.handle_fall], which is the same node and the same
## decision that already turns a rifle hit into a ghost. What a death IS stays
## the match's business, in the one place it has always been: a volume that
## decided for itself would be a second death path, and the two would drift.
##
## [b]It finds the match rather than being pointed at it.[/b]
## [code]scenes/ring/bentham_ring.tscn[/code] is an ARENA. It is composed into
## [code]scenes/match/match.tscn[/code], instanced bare by tests, and loaded by
## headless tooling that has no [MatchController] anywhere in it -- so a
## [NodePath] typed into the arena would be a path into a scene the arena knows
## nothing about, exactly as it is for the audio listener. It climbs to the root
## of the running scene once, on ready, and is a silent no-op when there is no
## match to tell.
##
## [b]It can see a ghost, deliberately.[/b] An [Area3D] detects a body through
## [member CollisionObject3D.collision_layer], and a ghost stands on
## [constant MatchController.GHOST_HAZARD_LAYER] rather than on no layer at all
## -- see that constant for why the rifle still cannot find it there. This
## volume's own [member Area3D.collision_mask], authored in
## [code]scenes/ring/bentham_ring.tscn[/code], is widened to include that bit
## specifically, so a ghost that falls in is reported exactly as a living
## prisoner is. [method MatchController.handle_fall] answers for a ghost by
## putting it back at the start -- a ghost is already dead, so a second death
## cannot be taken off it.

## The match to report falls to. Leave unset and, with [member auto_discover] on,
## the first [MatchController] in the running scene is used.
@export var controller: MatchController = null

## Where discovery starts. Defaults to the root of the scene this node is in, so
## the volume finds the match whether the arena is the scene or is instanced
## inside one.
@export var search_root: Node = null

## Search the scene for a controller when one was not assigned. Turn off to
## require explicit wiring.
@export var auto_discover: bool = true

## Radius of the volume, in metres. Defaults to the courtyard's own: the deck's
## inner edge is at r=35 and there is nothing to fall off anywhere else -- the
## outer wall is eight metres tall and closed.
@export_range(1.0, 200.0, 0.5, "or_greater") var radius_metres: float = 35.0

## How far below the deck the roof of the volume sits, in metres.
##
## This is the number that decides what counts as fallen, and three metres is the
## smallest honest answer: the deck and the guard's platform are both level with
## this node's origin, a jump on the tuned movement profile tops out at 1.11 m,
## and nothing standing on either surface can dip three metres under it. Anybody
## below this line left the walking surface and is on their way to the pit.
@export_range(0.5, 100.0, 0.5, "or_greater") var roof_depth_metres: float = 3.0

## How deep the volume goes below its roof, in metres.
##
## Twenty-four takes it from three metres under the deck to twenty-seven, which
## is well past the courtyard floor at twelve and a half and well short of the
## pen a converted body is parked in at a hundred. It has to comfortably contain
## the pit floor rather than merely touch it: a body lands there and STAYS there,
## so the volume it lands in is the one that has to be holding it.
@export_range(1.0, 400.0, 0.5, "or_greater") var depth_metres: float = 24.0

var _controller: MatchController = null


## Sizes the authored shape, then subscribes.
##
## The node, its place, its child and its collision mask are authored in
## [code]scenes/ring/bentham_ring.tscn[/code], where they can be seen and moved. The
## SIZE is written here from the exports above, so the extent of the volume is a
## named number with a reason attached rather than a figure buried in a shape
## resource -- and so there is exactly one of it.
func _ready() -> void:
	_build_shape()
	_controller = _resolve_controller()
	body_entered.connect(_on_body_entered)


## Write a cylinder over the courtyard into the authored [CollisionShape3D].
##
## A cylinder rather than a box because the courtyard is round, and the corners a
## box would add are under the deck -- where a body can only be if it has already
## fallen through geometry, which is not a case worth catching by accident.
func _build_shape() -> void:
	var holder: CollisionShape3D = _find_shape_holder()
	if holder == null:
		push_warning(
			"KillVolume at %s has no CollisionShape3D child; nothing will fall into it."
			% get_path()
		)
		return
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = radius_metres
	cylinder.height = depth_metres
	holder.shape = cylinder
	# Hung from the roof, so that roof_depth_metres means what it says whatever
	# depth_metres is: the top of the volume is that far below this node, and the
	# node sits at the arena's origin, which is the deck.
	holder.position = Vector3(0.0, -roof_depth_metres - depth_metres * 0.5, 0.0)


func _find_shape_holder() -> CollisionShape3D:
	for child: Node in get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


func _on_body_entered(body: Node3D) -> void:
	if _controller == null:
		# A controller added after this node was ready is found on first use.
		_controller = _resolve_controller()
	if _controller == null:
		return
	var participant: MatchParticipant = _controller.resolve_participant(body)
	if participant == null:
		# Something that is not a player fell in. The arena has no such thing
		# today, and if it ever does, destroying it is not this node's decision.
		return
	_controller.handle_fall(participant, true)


func _resolve_controller() -> MatchController:
	if controller != null:
		return controller
	if not auto_discover:
		return null
	var root: Node = search_root if search_root != null else _default_search_root()
	return _find_controller(root) if root != null else null


## The highest ancestor below the [SceneTree]'s root window -- in practice the
## root of the running scene.
##
## [member Node.owner] would be the obvious choice and is the wrong one: this
## node's owner is the arena scene, and the match is above it. Climbing is
## independent of how the arena was composed.
func _default_search_root() -> Node:
	if not is_inside_tree():
		return get_parent()
	var window: Window = get_tree().root
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != window:
		node = node.get_parent()
	return node


func _find_controller(node: Node) -> MatchController:
	var here: MatchController = node as MatchController
	if here != null:
		return here
	for child: Node in node.get_children():
		var found: MatchController = _find_controller(child)
		if found != null:
			return found
	return null
