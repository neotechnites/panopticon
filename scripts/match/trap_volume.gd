class_name TrapVolume
extends Area3D

## A trap on the deck: something red that kills whatever touches it.
##
## Canon, in the author's words: [i]"for traps, right now just create som
## obsitcles that are red and kill you, and some pits that let oyu fall into the
## kill box. nothing fancy at all just make it a bit more trecherous."[/i] The
## pits needed no script -- they are holes cut in the deck, and the hole does the
## work. This is the other half: the red blocks.
##
## [b]It rules on nothing, and that is the entire design.[/b] It resolves the
## body that touched it to a participant and calls
## [method MatchController.handle_fall] -- the same call
## [code]scripts/match/kill_volume.gd[/code] makes, landing in the same match on
## the same tick, which for a running prisoner in a round means
## [method MatchController.convert_participant] and a ghost on the start line.
## Touching a trap and being shot are therefore the SAME death, arrived at by
## different routes, and there is nothing here that could ever drift from the
## rifle: a trap that decided for itself what a death was would be a third death
## path, and three would drift faster than two.
##
## It is worth being explicit about what that inherits for free, because none of
## it is written here:
##
## - during a ROUND a prisoner who touches one becomes a ghost and is put back on
##   the start line;
## - during the OPENING RACE a racer who touches one is OUT, and the match
##   restarts if that empties the field;
## - the guard, who never leaves the platform, would be put back on the tower.
##
## [b]What you see is what kills you.[/b] The extent is one exported
## [member size_metres] and BOTH children are written from it on ready -- the
## [CollisionShape3D] that detects and the [CSGBox3D] that is drawn -- so the red
## box on screen and the volume that kills cannot disagree. Same reasoning as
## [KillVolume], which sizes its cylinder from three exported metres for exactly
## this reason. Nothing here is built in code: both children are authored in
## [code]scenes/ring/bentham_ring.tscn[/code] and this only sizes them.
##
## [b]It is a trigger and nothing else.[/b] Layer 0, so nothing in the game has
## to know it is there; mask bits 1 and [constant MatchController.GHOST_HAZARD_LAYER],
## because those are the layers a living body
## ([code]scenes/player/player.tscn[/code]'s own) and a ghost's body stand on,
## respectively; [member monitorable] off. The drawn block carries no collision
## either, which is deliberate and not
## laziness: a SOLID red block would be new cover for the prisoners and a new
## occluder for the tower, both of which are tuned geometry nobody asked to
## change, and it would give the shipped runner brain -- which has no obstacle
## avoidance at all -- something to grind against. A block that is lethal on
## contact does not need to be solid; you never get to stand inside it.
##
## [b]It can see a ghost, deliberately.[/b] A ghost stands on
## [constant MatchController.GHOST_HAZARD_LAYER], not on no layer at all -- see
## that constant for why the rifle still cannot find it there -- and this node's
## [member Area3D.collision_mask] is widened in
## [code]scenes/ring/bentham_ring.tscn[/code] to include that bit, exactly as
## [KillVolume]'s is. [method MatchController.handle_fall] puts a ghost that
## touches one back at the start rather than killing it again.
##
## [b]It finds the match rather than being pointed at it[/b], and for the same
## reason [KillVolume] does: [code]scenes/ring/bentham_ring.tscn[/code] is an ARENA,
## composed into [code]scenes/match/match.tscn[/code], instanced bare by tests,
## and loaded by headless tooling with no [MatchController] in it at all. A
## [NodePath] typed into the arena would be a path into a scene the arena knows
## nothing about. It climbs to the root of the running scene once, on ready, and
## is a silent no-op when there is no match to tell.

## The match to report contact to. Leave unset and, with [member auto_discover]
## on, the first [MatchController] in the running scene is used.
@export var controller: MatchController = null

## Where discovery starts. Defaults to the root of the scene this node is in, so
## a trap finds the match whether the arena is the scene or is instanced inside
## one.
@export var search_root: Node = null

## Search the scene for a controller when one was not assigned. Turn off to
## require explicit wiring.
@export var auto_discover: bool = true

## How big the trap is, in metres, as full extents.
##
## Local X runs along the track, local Y is height and local Z is radial -- the
## same axes the cover boxes in the arena are authored on, so a trap and a piece
## of cover are placed by the same arithmetic. Both children are written from
## this on ready.
##
## The shipped default is chest-high rather than knee-high on purpose: at 2.2 m
## it is well over the 1.11 m jump apex of the tuned
## [MovementProfile], so a trap in the way has to be gone AROUND. Something low
## enough to hop would be a timing puzzle, and a timing puzzle is fancy.
@export var size_metres: Vector3 = Vector3(5.0, 2.2, 2.0)

var _controller: MatchController = null


func _ready() -> void:
	_build_shape()
	_size_the_block()
	_controller = _resolve_controller()
	body_entered.connect(_on_body_entered)


# --- Geometry -----------------------------------------------------------------


## Write [member size_metres] over the detection shape.
func _build_shape() -> void:
	var holder: CollisionShape3D = _find_shape_holder()
	if holder == null:
		push_warning(
			"TrapVolume at %s has no CollisionShape3D child; it will kill nobody."
			% get_path()
		)
		return
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size_metres
	holder.shape = box


## Write [member size_metres] over the drawn block, so the red is the trap.
##
## A missing block is not a warning: a trap with no mesh is invisible, which is a
## thing somebody might want on purpose, and it still kills. A shape that does
## not match the mesh is the failure worth shouting about, and sizing both from
## one number is what makes it impossible.
func _size_the_block() -> void:
	var block: CSGBox3D = _find_block()
	if block == null:
		return
	block.size = size_metres


func _find_shape_holder() -> CollisionShape3D:
	for child: Node in get_children():
		var holder: CollisionShape3D = child as CollisionShape3D
		if holder != null:
			return holder
	return null


func _find_block() -> CSGBox3D:
	for child: Node in get_children():
		var block: CSGBox3D = child as CSGBox3D
		if block != null:
			return block
	return null


# --- Contact ------------------------------------------------------------------


func _on_body_entered(body: Node3D) -> void:
	if _controller == null:
		# A controller added after this node was ready is found on first use.
		_controller = _resolve_controller()
	if _controller == null:
		return
	var participant: MatchParticipant = _controller.resolve_participant(body)
	if participant == null:
		# Something that is not a player touched it. The arena has no such thing
		# today, and if it ever does, destroying it is not this node's decision.
		return
	_controller.handle_fall(participant)


# --- Finding the match --------------------------------------------------------


func _resolve_controller() -> MatchController:
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


func _find_controller(node: Node) -> MatchController:
	var here: MatchController = node as MatchController
	if here != null:
		return here
	for child: Node in node.get_children():
		var found: MatchController = _find_controller(child)
		if found != null:
			return found
	return null
