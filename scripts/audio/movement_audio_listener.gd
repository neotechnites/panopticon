class_name MovementAudioListener
extends Node

## Turns what every [PlayerController] in the scene is doing into posted audio
## events. [b]Attach it; do not edit them.[/b]
##
## Drop this node into [code]scenes/audio/game_audio.tscn[/code] next to the
## [AudioDirector] and every body in the match becomes audible: footsteps, jump,
## landing and both ends of a slide, for the human, for every bot, and for a
## ghost. [code]scripts/player/player_controller.gd[/code] is not modified for
## any of this except footsteps -- see below -- because jump, landing and the
## slide are already announced on the body's own signals
## ([signal PlayerController.jumped], [signal PlayerController.landed],
## [signal PlayerController.slide_started], [signal PlayerController.slide_ended]);
## this file only has to listen.
##
## [b]Footsteps are the one event with no signal behind them, and deliberately
## stay that way.[/b] Rather than teach the controller a new "footstep" concept,
## this listener paces them itself from the controller's EXISTING public
## surface -- [method PlayerController.get_horizontal_speed],
## [method CharacterBody3D.is_on_floor], [method PlayerController.is_sliding] and
## [member Node3D.global_position] -- accumulating horizontal distance every
## physics tick and posting once [member MovementAudioTuning.footstep_stride_metres]
## is crossed. See [method _pace_footsteps]. The result is the same property the
## rest of this file gets for free: a bot and a human post identically, because
## neither this listener nor the controller can tell which is driving.
##
## [b]Why every body, not one.[/b] [MatchAudioListener] resolves a single rifle
## and a single [MatchController], because there is exactly one of each in a
## match. A body is different -- there can be four -- and other players'
## movement is the whole point: a runner who cannot hear an approaching ghost or
## a slide going past is playing a different, worse game than the one PANOPTICON
## is about. So this file tracks every [PlayerController] it can find, not the
## local player's.
##
## [b]Why it watches [signal SceneTree.node_added] AND sweeps once, exactly like
## [UIAudioListener].[/b] The human's body is authored directly in
## [code]scenes/match/match.tscn[/code] and is already in the tree before this
## node is ready -- the deferred sweep in [method _enter_tree] catches it. Every
## AI body is spawned at runtime into the [code]Runners[/code] container by
## [method MatchController._make_ai_participant], after this node's own
## [code]_ready[/code] -- the live subscription catches those. Between them
## nothing is missed and a body that is freed simply stops firing signals into a
## dictionary that is pruned lazily on the next physics tick.
##
## [b]Ghosts are not special-cased for detection.[/b] The only signal a ghost
## gives off is [member PlayerController.speed_scale] being above 1.0 --
## [MatchController] is "the only thing that writes it, for a ghost" (see that
## field's own docs) -- so that is what [method _is_ghost] reads. See
## [member MovementAudioTuning.ghosts_make_movement_sound] for the audibility
## ruling itself.

## The director to post to. Leave unset to use whichever director is in the
## tree ([method AudioDirector.instance]).
@export var director: AudioDirector = null

## Cadence, thresholds and the ghost-audibility switch. A listener with none
## assigned builds a default-constructed [MovementAudioTuning] on
## [method _enter_tree] rather than refusing to run -- the placeholder numbers on
## that resource are exactly the ones documented there, so an unset export is a
## degraded-but-working state, not a silent one.
@export var tuning: MovementAudioTuning = null

## Where discovery starts. Defaults to the root of the scene this node is in --
## see [method _default_search_root] -- so it finds bodies whether it is a
## direct child of the match root or nested inside an instanced audio scene.
@export var search_root: Node = null

## Search the scene for bodies already present when this node enters the tree.
## Turn off to require every body to arrive after via [signal SceneTree.node_added].
@export var auto_discover: bool = true

var _root: Node = null

## Every body currently tracked, keyed by [method Object.get_instance_id] rather
## than by the body itself -- the same convention
## [code]scripts/match/match_controller.gd[/code]'s
## [code]_participant_by_body_id[/code] and
## [code]scripts/harness/bot_tower_seat.gd[/code]'s [code]_shooters[/code] use for
## the same reason: a dictionary keyed by id survives a stale reference cleanly,
## where a freed [Object] used directly as a key is the thing
## [method is_instance_valid] exists to guard against. The two dictionaries below
## carry the one-tick memory footstep pacing needs, keyed the same way.
var _bodies: Dictionary[int, PlayerController] = {}

## Each tracked body's [member Node3D.global_position] as of last tick, absent
## for a body with no usable last position yet (just discovered, just landed,
## just left the floor or just finished a slide -- see [method _pace_footsteps]).
var _last_position: Dictionary[int, Vector3] = {}

## Metres accumulated toward each tracked body's next footstep.
var _stride_accum: Dictionary[int, float] = {}


## Subscribes and sweeps in [method Node._enter_tree], for the same reason
## [MatchAudioListener] does: the whole subtree that exists at scene-load time
## is already built by the time any [code]_enter_tree[/code] runs, and
## subscribing here rather than in [code]_ready[/code] cannot lose a race against
## sibling ordering.
func _enter_tree() -> void:
	if tuning == null:
		tuning = MovementAudioTuning.new()

	_root = search_root
	if _root == null:
		_root = _default_search_root()

	set_physics_process(true)

	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	if auto_discover and _root != null:
		_wire_subtree.call_deferred(_root)


func _exit_tree() -> void:
	if is_inside_tree():
		var tree: SceneTree = get_tree()
		if tree != null and tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
	_bodies.clear()
	_last_position.clear()
	_stride_accum.clear()


func _on_node_added(node: Node) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	if node != _root and not _root.is_ancestor_of(node):
		return
	_wire_node(node)


func _wire_subtree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_wire_node(node)
	for child: Node in node.get_children():
		_wire_subtree(child)


## Start tracking [param node] if it is a body. Idempotent -- a body already in
## [member _bodies] is left alone, which is what lets the deferred sweep and a
## live [signal SceneTree.node_added] both see the same node without double
## connecting it.
func _wire_node(node: Node) -> void:
	var body: PlayerController = node as PlayerController
	if body == null:
		return
	var id: int = body.get_instance_id()
	if _bodies.has(id):
		return
	_bodies[id] = body
	body.jumped.connect(func() -> void: _on_jumped(body))
	body.landed.connect(func(impact_speed: float) -> void: _on_landed(body, impact_speed))
	body.slide_started.connect(func(_entry_speed: float) -> void: _on_slide_started(body))
	body.slide_ended.connect(func() -> void: _on_slide_ended(body))


## The highest ancestor below the [SceneTree]'s root window. See
## [method MatchAudioListener._default_search_root]; identical for the same
## reason.
func _default_search_root() -> Node:
	if not is_inside_tree():
		return get_parent()
	var window: Window = get_tree().root
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != window:
		node = node.get_parent()
	return node


# --- Footsteps, paced by distance ----------------------------------------------

func _physics_process(_delta: float) -> void:
	var stale: Array[int] = []
	for id: int in _bodies:
		var body: PlayerController = _bodies[id]
		if not is_instance_valid(body):
			stale.append(id)
			continue
		_pace_footsteps(body)
	for id: int in stale:
		_bodies.erase(id)
		_last_position.erase(id)
		_stride_accum.erase(id)


## Accumulate horizontal distance for [param body] and post a footstep every
## time it crosses [member MovementAudioTuning.footstep_stride_metres].
##
## Only accumulates on the floor and not sliding -- a slide has its own start
## and end cues and covers ground far faster than a stride length implies, so
## letting it feed this accumulator is exactly the "slide does not machine-gun
## footsteps" failure mode this function exists to avoid. Airborne time and a
## slide both erase [member _last_position]'s entry for the body rather than
## merely pausing accumulation, so the position delta measured on landing or on
## regaining footing after a slide is never the straight-line distance covered
## while off the ground.
func _pace_footsteps(body: PlayerController) -> void:
	var id: int = body.get_instance_id()

	if body.is_sliding() or not body.is_on_floor():
		_last_position.erase(id)
		return

	var position: Vector3 = body.global_position
	if not _last_position.has(id):
		_last_position[id] = position
		return

	var moved: Vector3 = position - _last_position[id]
	moved.y = 0.0
	_last_position[id] = position

	var speed: float = body.get_horizontal_speed()
	if speed < tuning.footstep_min_speed:
		_stride_accum[id] = 0.0
		return

	var accum: float = _stride_accum.get(id, 0.0) + moved.length()
	var stride: float = maxf(tuning.footstep_stride_metres, 0.01)
	if accum < stride:
		_stride_accum[id] = accum
		return
	# Remainder kept, not zeroed, so the phase of the pacing survives a tick
	# whose distance overshot the stride -- and fposmod rather than a subtract
	# loop, so a single huge displacement (a respawn teleport) posts at most one
	# footstep this tick instead of a burst covering the whole gap.
	_stride_accum[id] = fposmod(accum, stride)
	_post_at(body, AudioEvents.MOVEMENT_FOOTSTEP)


# --- Signals ------------------------------------------------------------------

func _on_jumped(body: PlayerController) -> void:
	_post_at(body, AudioEvents.MOVEMENT_JUMP)


func _on_slide_started(body: PlayerController) -> void:
	_post_at(body, AudioEvents.MOVEMENT_SLIDE_START)


func _on_slide_ended(body: PlayerController) -> void:
	_post_at(body, AudioEvents.MOVEMENT_SLIDE_END)


## The one event that scales rather than just posting: see
## [method MovementAudioTuning.landing_gain_db].
func _on_landed(body: PlayerController, impact_speed: float) -> void:
	if not _should_sound(body):
		return
	if impact_speed < tuning.landing_min_impact_speed:
		return
	var gain_db: float = tuning.landing_gain_db(impact_speed)
	var position: Vector3 = body.global_position
	if director != null:
		director.post_at_gain(AudioEvents.MOVEMENT_LAND, position, gain_db)
	else:
		AudioDirector.post_event_at_gain(AudioEvents.MOVEMENT_LAND, position, gain_db)


# --- Posting --------------------------------------------------------------------

func _post_at(body: PlayerController, event: StringName) -> void:
	if not _should_sound(body):
		return
	var position: Vector3 = body.global_position
	if director != null:
		director.post_at(event, position)
	else:
		AudioDirector.post_event_at(event, position)


func _should_sound(body: PlayerController) -> bool:
	if tuning.ghosts_make_movement_sound:
		return true
	return not _is_ghost(body)


## See the class doc's note on ghost detection: [member PlayerController.speed_scale]
## is the only externally visible sign, and it is exactly 1.0 for anything that
## is not sped up by [MatchController._make_ghost].
func _is_ghost(body: PlayerController) -> bool:
	return body.speed_scale > 1.0
