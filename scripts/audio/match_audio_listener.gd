class_name MatchAudioListener
extends Node

## Turns what a [Rifle] and a [MatchController] announce into posted audio
## events. [b]Attach it; do not edit them.[/b]
##
## Drop this node into scenes/match/match.tscn next to the [AudioDirector] and
## the whole match is audible. Neither scripts/weapon/rifle.gd nor
## scripts/match/match_controller.gd changes, or ever needs to: they already
## emit every signal worth hearing, and this file is the adapter that turns each
## one into a name from [AudioEvents]. If a fourth system later wants to know
## about a shot, it writes its own listener rather than adding a line to the
## rifle.
##
## [b]What comes from where[/b]
## [codeblock]
##   Rifle.fired            -> weapon.rifle.fired            positional, origin
##   Rifle.target_hit       -> weapon.rifle.hit              positional, impact
##   Rifle.missed           -> weapon.rifle.missed           positional, far end
##   Rifle.reload_started   -> weapon.rifle.reload_started    flat
##   Rifle.reload_finished  -> weapon.rifle.reload_finished   flat
##   MatchController.match_started    -> match.started
##   MatchController.race_started     -> match.race_started
##   MatchController.round_started    -> match.round_started
##   MatchController.seat_changed     -> match.seat_changed
##   MatchController.round_resolved   -> match.round_resolved
##   MatchController.runner_removed   -> match.runner_converted
##   MatchController.match_won        -> match.won
##   FxHitReaction.struck             -> player.hit_taken
##   FxCatchReaction.catch_made       -> player.catch_made
##   FxCatchReaction.catch_taken      -> player.catch_taken
## [/codeblock]
##
## [b]Why the rifle is looked up and not just exported.[/b] The rifle is
## reparented mid-match -- [MatchController] moves it onto whoever holds the
## tower -- so a [NodePath] typed into the scene points at the human's head and
## goes stale the moment the seat changes. Signals do not care about
## reparenting, so this listener resolves the [Rifle] object once and keeps the
## connections; the node can move anywhere in the tree afterwards.
##
## Everything here is defensive to the point of dullness on purpose: an absent
## director, an absent rifle and an absent controller are all silent no-ops, so
## this node can be left in a scene that a headless harness loads without a
## director in it.

## The director to post to. Leave unset to use whichever director is in the
## tree ([method AudioDirector.instance]).
@export var director: AudioDirector = null

## The rifle to listen to. Leave unset and, with [member auto_discover] on, the
## first [Rifle] under [member search_root] is used.
@export var rifle: Rifle = null

## The match to listen to. Leave unset and, with [member auto_discover] on, the
## first [MatchController] under [member search_root] is used.
@export var controller: MatchController = null

## The local player's hit reaction, for [constant AudioEvents.PLAYER_HIT_TAKEN].
## Leave unset and, with [member auto_discover] on, the first [FxHitReaction]
## under [member search_root] is used -- which is the right one, because a scene
## has exactly one of them and it belongs to the body this machine is looking out
## of. Absent, this listener simply never posts that event.
@export var hit_reaction: FxHitReaction = null

## The local player's catch reaction, for [constant AudioEvents.PLAYER_CATCH_MADE]
## and [constant AudioEvents.PLAYER_CATCH_TAKEN]. Found the same way, for the
## same reason, and absent the same way: this listener simply never posts them.
##
## Deliberately NOT wired off [signal MatchController.ghost_caught] directly.
## That signal fires for every catch in the round including the bots' own, and
## the question "was that catch mine, and which side of it was I on" is already
## answered once, by [FxCatchReaction]. Asking it twice is two places to get it
## wrong.
@export var catch_reaction: FxCatchReaction = null

## Where discovery starts. Defaults to the root of the scene this node is in --
## see [method _default_search_root] -- so the listener finds the match whether
## it is a direct child of the match root or nested inside an instanced audio
## scene.
@export var search_root: Node = null

## Search the scene for a rifle and a controller when they were not assigned.
## Turn off to require explicit wiring.
@export var auto_discover: bool = true

var _rifle: Rifle = null
var _controller: MatchController = null
var _hit_reaction: FxHitReaction = null
var _catch_reaction: FxCatchReaction = null


## Subscribes in [method Node._enter_tree], not [method Node._ready], and the
## difference is a bug.
##
## [MatchController.start_match] is called from that controller's own
## [code]_ready[/code], and it emits [signal MatchController.match_started] and
## [signal MatchController.race_started] before it returns. Godot runs every
## [code]_enter_tree[/code] in a subtree before it runs any [code]_ready[/code]
## in it, so subscribing here catches those two; subscribing in [code]_ready[/code]
## catches them only if this node happens to sit before the controller in the
## scene's child order, and deferring the subscription misses them always. The
## whole subtree is already constructed by the time any [code]_enter_tree[/code]
## fires, so discovery has everything to find.
func _enter_tree() -> void:
	_connect_all()


func _exit_tree() -> void:
	_disconnect_all()


## Resolve the rifle and the controller and subscribe. Safe to call twice;
## already-connected signals are left alone.
func _connect_all() -> void:
	_resolve()
	if _rifle != null:
		_bind(_rifle.fired, _on_fired)
		_bind(_rifle.target_hit, _on_target_hit)
		_bind(_rifle.missed, _on_missed)
		_bind(_rifle.reload_started, _on_reload_started)
		_bind(_rifle.reload_finished, _on_reload_finished)
	if _hit_reaction != null:
		_bind(_hit_reaction.struck, _on_struck)
	if _catch_reaction != null:
		_bind(_catch_reaction.catch_made, _on_catch_made)
		_bind(_catch_reaction.catch_taken, _on_catch_taken)
	if _controller != null:
		_bind(_controller.finisher_armed, _on_finisher_armed)
		_bind(_controller.match_started, _on_match_started)
		_bind(_controller.race_started, _on_race_started)
		_bind(_controller.round_started, _on_round_started)
		_bind(_controller.seat_changed, _on_seat_changed)
		_bind(_controller.round_resolved, _on_round_resolved)
		_bind(_controller.runner_removed, _on_runner_removed)
		_bind(_controller.match_won, _on_match_won)


func _disconnect_all() -> void:
	if _rifle != null and is_instance_valid(_rifle):
		_unbind(_rifle.fired, _on_fired)
		_unbind(_rifle.target_hit, _on_target_hit)
		_unbind(_rifle.missed, _on_missed)
		_unbind(_rifle.reload_started, _on_reload_started)
		_unbind(_rifle.reload_finished, _on_reload_finished)
	if _hit_reaction != null and is_instance_valid(_hit_reaction):
		_unbind(_hit_reaction.struck, _on_struck)
	if _catch_reaction != null and is_instance_valid(_catch_reaction):
		_unbind(_catch_reaction.catch_made, _on_catch_made)
		_unbind(_catch_reaction.catch_taken, _on_catch_taken)
	if _controller != null and is_instance_valid(_controller):
		_unbind(_controller.match_started, _on_match_started)
		_unbind(_controller.race_started, _on_race_started)
		_unbind(_controller.round_started, _on_round_started)
		_unbind(_controller.seat_changed, _on_seat_changed)
		_unbind(_controller.round_resolved, _on_round_resolved)
		_unbind(_controller.runner_removed, _on_runner_removed)
		_unbind(_controller.match_won, _on_match_won)
	_rifle = null
	_controller = null
	_hit_reaction = null
	_catch_reaction = null


func _bind(source: Signal, handler: Callable) -> void:
	if not source.is_connected(handler):
		source.connect(handler)


func _unbind(source: Signal, handler: Callable) -> void:
	if source.is_connected(handler):
		source.disconnect(handler)


func _resolve() -> void:
	_rifle = rifle
	_controller = controller
	_hit_reaction = hit_reaction
	_catch_reaction = catch_reaction
	if not auto_discover:
		return
	var root: Node = search_root
	if root == null:
		root = _default_search_root()
	if root == null:
		return
	if _rifle == null:
		_rifle = _find_rifle(root)
	if _controller == null:
		_controller = _find_controller(root)
	if _hit_reaction == null:
		_hit_reaction = _find_hit_reaction(root)
	if _catch_reaction == null:
		_catch_reaction = _find_catch_reaction(root)


## The highest ancestor below the [SceneTree]'s root window -- in practice the
## root of the running scene.
##
## [member Node.owner] would be the obvious choice and is the wrong one: when
## this listener ships inside an instanced audio scene, its owner is that audio
## scene's root and the search never sees the match at all. Climbing is
## independent of how the node was composed.
func _default_search_root() -> Node:
	if not is_inside_tree():
		return get_parent()
	var window: Window = get_tree().root
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != window:
		node = node.get_parent()
	return node


func _find_rifle(node: Node) -> Rifle:
	var here: Rifle = node as Rifle
	if here != null:
		return here
	for child: Node in node.get_children():
		var found: Rifle = _find_rifle(child)
		if found != null:
			return found
	return null


func _find_controller(node: Node) -> MatchController:
	var here: MatchController = node as MatchController
	if here != null:
		return here
	for child: Node in node.get_children():
		var found: MatchController = _find_controller(child)
		if found != null:
			return found
	return null


func _find_hit_reaction(node: Node) -> FxHitReaction:
	var here: FxHitReaction = node as FxHitReaction
	if here != null:
		return here
	for child: Node in node.get_children():
		var found: FxHitReaction = _find_hit_reaction(child)
		if found != null:
			return found
	return null


func _find_catch_reaction(node: Node) -> FxCatchReaction:
	var here: FxCatchReaction = node as FxCatchReaction
	if here != null:
		return here
	for child: Node in node.get_children():
		var found: FxCatchReaction = _find_catch_reaction(child)
		if found != null:
			return found
	return null


## Post through the assigned director, or through whichever one is in the tree.
func _post(event: StringName) -> void:
	if director != null:
		director.post(event)
		return
	AudioDirector.post_event(event)


func _post_at(event: StringName, world_position: Vector3) -> void:
	if director != null:
		director.post_at(event, world_position)
		return
	AudioDirector.post_event_at(event, world_position)


# --- Rifle --------------------------------------------------------------------
#
# The parameter names below are the rifle's, not this file's: they are what the
# signals in scripts/weapon/rifle.gd declare, and keeping them identical is what
# makes it obvious at a glance that nothing has been reinterpreted on the way
# through.

## The shot leaves from the shooter's eye, and that is the position the report
## must come from: the whole point of a shot in PANOPTICON is that it tells
## everyone on the ring roughly where the tower is looking from.
## The finisher's rifle posts the same cues as the tower's.
func _on_finisher_armed(weapon: Rifle) -> void:
	if weapon == null:
		return
	_bind(weapon.fired, _on_fired)
	_bind(weapon.target_hit, _on_target_hit)
	_bind(weapon.missed, _on_missed)
	_bind(weapon.reload_started, _on_reload_started)
	_bind(weapon.reload_finished, _on_reload_finished)


func _on_fired(origin: Vector3, _end_point: Vector3) -> void:
	_post_at(AudioEvents.RIFLE_FIRED, origin)


func _on_target_hit(_collider: Node3D, hit_position: Vector3, _hit_normal: Vector3) -> void:
	_post_at(AudioEvents.RIFLE_HIT, hit_position)


func _on_missed(end_point: Vector3) -> void:
	_post_at(AudioEvents.RIFLE_MISSED, end_point)


## Flat, not positional: this is the tower player's own weapon in their own
## hands, and the duration is deliberately ignored here. A cue that wants to
## span the whole reload is a stream of that length, not a parameter -- the
## reload is a fixed length within a turn and [signal Rifle.reload_started]
## carries it for anything that must scale.
func _on_reload_started(_duration: float) -> void:
	_post(AudioEvents.RIFLE_RELOAD_STARTED)


func _on_reload_finished() -> void:
	_post(AudioEvents.RIFLE_RELOAD_FINISHED)


# --- Match --------------------------------------------------------------------

func _on_match_started(_participant_count: int) -> void:
	_post(AudioEvents.MATCH_STARTED)


func _on_race_started() -> void:
	_post(AudioEvents.RACE_STARTED)


func _on_round_started() -> void:
	_post(AudioEvents.ROUND_STARTED)


func _on_seat_changed(_participant: MatchParticipant, _turns_in_tower: int) -> void:
	_post(AudioEvents.SEAT_CHANGED)


func _on_round_resolved(_outcome: MatchController.Outcome) -> void:
	_post(AudioEvents.ROUND_RESOLVED)


func _on_runner_removed(_remaining: int) -> void:
	_post(AudioEvents.RUNNER_CONVERTED)


func _on_match_won(_participant: MatchParticipant) -> void:
	_post(AudioEvents.MATCH_WON)


# --- The victim ---------------------------------------------------------------

## Flat, not positional. See [constant AudioEvents.PLAYER_HIT_TAKEN]: the
## listener is inside the head that was hit, so there is no distance to
## attenuate and no direction to pan. The direction the shot was travelling is
## carried by the camera whip, and is deliberately dropped here.
func _on_struck(_world_direction: Vector3) -> void:
	_post(AudioEvents.PLAYER_HIT_TAKEN)


# --- The catch ----------------------------------------------------------------

## Flat, not positional, and the colour is deliberately dropped. See
## [constant AudioEvents.PLAYER_CATCH_MADE]: a catch happens at arm's length, so
## the listener is standing inside the sound. WHO it was is carried by the frame
## FxCatchReaction draws in that player's own palette colour, which is the
## channel that can actually express it.
func _on_catch_made(_caught_color: Color) -> void:
	_post(AudioEvents.PLAYER_CATCH_MADE)


## The other half, and the one that has to be unmistakable against
## [constant AudioEvents.PLAYER_HIT_TAKEN]: both are this player dying, and only
## the sound and the colour say which death it was.
func _on_catch_taken(_ghost_color: Color) -> void:
	_post(AudioEvents.PLAYER_CATCH_TAKEN)
