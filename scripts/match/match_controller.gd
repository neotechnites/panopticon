class_name MatchController
extends Node

## The round: three runners, one rifle, one outcome.
##
## Every rule of the round lives here and nowhere else. The rifle reports what
## it struck and stays ignorant of what that means; [RingRunner] reports that it
## finished its lap and stays ignorant of what that costs; the player's body
## knows nothing about any of it. This node is the only place that turns those
## reports into a win or a loss, which is what lets the round rules be changed --
## two hits to remove, a timer, a survivor count -- without touching a single
## file under [code]scripts/player[/code], [code]scripts/weapon[/code] or
## [code]scripts/bot[/code].
##
## [b]The rules, in full[/b]
##
## - A runner hit by the rifle is removed from the round. One hit is terminal;
##   there is no health, so there is no damage number to carry anywhere.
## - All three removed: the player WINS.
## - Any one runner reaches the end: the player LOSES, immediately, even with
##   the other two still alive. The tower has to stop all of them, which is the
##   asymmetry the whole game is built on.
## - The round resolves exactly once. Everything that could resolve it is
##   guarded on [method is_resolved], and resolution freezes the survivors so a
##   loss cannot be followed a second later by a second loss.

## What the round has come to. Exhaustive.
enum Outcome {
	## Live. The only state in which a hit or a finished lap means anything.
	IN_PROGRESS,
	## Every runner was removed by the rifle.
	WIN,
	## At least one runner reached the end.
	LOSS,
}

## Emitted once per round, on the tick it resolves. The hook for anything that
## hangs off the result -- a scoreboard, the next round, a sweep's ledger.
signal round_resolved(outcome: Outcome)

## Emitted when a fresh round is armed, after the runners are placed and the
## rifle is ready. Restart emits it again.
signal round_started()

## Emitted when a runner leaves the round, carrying how many are still running.
signal runner_removed(remaining: int)

## Lane radii for the runners, one per runner, in metres.
##
## These are the three usable channels on a 25 m deck. Cover sits at r=41, 47.5
## and 54 and occupies roughly +/-0.9 m about each; a runner does not path
## around anything, so a radius inside a cover band walks a 0.4 m capsule into a
## box and stands there for the rest of the round. 38.5 / 44.5 / 51.0 are the
## clear channels, and they are 6.5 m apart so the runners never touch.
@export var lane_radii: PackedFloat32Array = PackedFloat32Array([38.5, 44.5, 51.0])

## The arena instance. Its origin is the ring axis and the markers are found
## under it by the three paths below.
@export var arena: Node3D

## The human in the tower. Repositioned to [member spawn_marker_path] on every
## round so a restart is a real restart.
@export var player: PlayerController

## The tower's rifle. The round listens to its [signal Rifle.target_hit] and
## forces it back to READY on restart.
@export var rifle: Rifle

## Where spawned runners are parented. Keeping them under one node means a
## restart is a single sweep and nothing of the previous round survives.
@export var runner_container: Node3D

## The runner to spawn, once per entry in [member lane_radii].
@export var runner_scene: PackedScene

@export var start_marker_path: NodePath = ^"StartEnd/PrisonerStart"
@export var end_marker_path: NodePath = ^"StartEnd/PrisonerEnd"
@export var spawn_marker_path: NodePath = ^"Tower/TowerSpawn"

## Arm the first round from [method Node._ready]. Off for a harness that wants
## to place things itself before the clock starts.
@export var auto_start: bool = true

## Physical key that restarts the round. Read as a physical scancode rather than
## through the input map because the map is [code]project.godot[/code]'s
## business and this scene does not get to add actions to it.
const RESTART_KEY: Key = KEY_R

## Long enough to run any reload out in a single [method Rifle.tick]. Used to
## force the weapon back to READY on restart without reaching into its state
## machine: tick() is the weapon's own public harness seam, and one enormous
## step lands on READY from FIRING or RELOADING alike.
const FORCE_READY_SECONDS: float = 3600.0

var _outcome: Outcome = Outcome.IN_PROGRESS

## Runners still in the round. The size of this is the score.
var _live: Array[RingRunner] = []

## Body instance id -> the brain driving it.
##
## The rifle hands back a [CollisionObject3D], because that is what a raycast
## hits; the round thinks in [RingRunner]s. This is the bridge, and it is built
## from [member RingRunner.controller] at spawn rather than from node paths, so
## it keeps working if the runner scene is ever restructured.
var _brain_by_body: Dictionary[int, RingRunner] = {}

## How many times this controller has resolved a round. A regression in the
## once-only guard shows up here as a number greater than the rounds played.
var _resolve_count: int = 0


func _ready() -> void:
	if arena == null or rifle == null or runner_scene == null or runner_container == null:
		push_error("MatchController is missing an arena, a rifle, a runner scene or a container; no round will run.")
		return
	rifle.target_hit.connect(_on_target_hit)
	if auto_start:
		start_round()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == RESTART_KEY:
		start_round()
		get_viewport().set_input_as_handled()


## Tear down whatever round is running and arm a fresh one.
##
## A full reset, on purpose: runners are destroyed and respawned rather than
## repositioned, because a runner carries elapsed time, arc travelled and a
## half-integrated path length, and reviving one is three chances to leave a
## stale field behind. The rifle is forced ready, the reload is restored to the
## profile's base so progression cannot leak across rounds, and the player goes
## back to the tower spawn.
func start_round() -> void:
	_clear_runners()
	_outcome = Outcome.IN_PROGRESS

	if rifle != null:
		rifle.reset_reload_to_base()
		rifle.tick(FORCE_READY_SECONDS)

	if player != null:
		var spawn: Marker3D = arena.get_node_or_null(spawn_marker_path) as Marker3D
		if spawn != null:
			player.global_position = spawn.global_position
		player.velocity = Vector3.ZERO

	_spawn_runners()
	round_started.emit()


## Alias for [method start_round], for callers that read better this way.
func restart() -> void:
	start_round()


func get_outcome() -> Outcome:
	return _outcome


## Human-readable outcome, for the HUD and for logs.
func get_outcome_name() -> String:
	return String(Outcome.keys()[_outcome])


func is_resolved() -> bool:
	return _outcome != Outcome.IN_PROGRESS


func get_runners_remaining() -> int:
	return _live.size()


func get_runners_total() -> int:
	return lane_radii.size()


## How many rounds this controller has ever resolved. One per round played, and
## the assertion a harness makes against the once-only guard.
func get_resolve_count() -> int:
	return _resolve_count


## The live runners, as a copy. Callers may iterate it while removing.
func get_live_runners() -> Array[RingRunner]:
	return _live.duplicate()


## Which runner, if any, a physics collider belongs to.
##
## The rifle reports the [CollisionObject3D] its ray struck. For a runner that
## is the [PlayerController] at the root of the runner scene -- but nothing here
## assumes that. It walks up from the collider through its ancestors and asks
## the spawn-time map at each step, so a future runner with its hitbox on a
## child node, or reparented under a squad node, resolves without a change here.
## Returns null for the deck, the cover, the tower or anything else in the world.
func resolve_runner(collider: Node3D) -> RingRunner:
	var node: Node = collider
	while node != null:
		var id: int = node.get_instance_id()
		if _brain_by_body.has(id):
			return _brain_by_body[id]
		node = node.get_parent()
	return null


## Take a runner out of the round. Returns true if it was in it.
##
## Refuses once the round is resolved, which is half of the once-only guarantee:
## a shot fired in the same frame as the loss cannot turn it into a win.
func remove_runner(runner: RingRunner) -> bool:
	if runner == null or is_resolved():
		return false
	var index: int = _live.find(runner)
	if index < 0:
		return false

	_live.remove_at(index)
	var body: PlayerController = runner.controller
	if body != null:
		_brain_by_body.erase(body.get_instance_id())
	if runner.reached_end.is_connected(_on_runner_reached_end):
		runner.reached_end.disconnect(_on_runner_reached_end)
	runner.set_physics_process(false)
	# The brain is a child of the body, so freeing the body takes both, and it
	# takes the collider with them -- a removed runner cannot be shot again.
	if body != null:
		body.queue_free()

	runner_removed.emit(_live.size())
	if _live.is_empty():
		_resolve(Outcome.WIN)
	return true


# --- Round wiring -------------------------------------------------------------

func _spawn_runners() -> void:
	var start_marker: Marker3D = arena.get_node_or_null(start_marker_path) as Marker3D
	var end_marker: Marker3D = arena.get_node_or_null(end_marker_path) as Marker3D
	if start_marker == null or end_marker == null:
		push_error("MatchController cannot find the PrisonerStart/PrisonerEnd markers; no runners spawned.")
		return

	var centre: Vector3 = arena.global_position
	var start_point: Vector3 = start_marker.global_position
	var end_point: Vector3 = end_marker.global_position

	for index: int in lane_radii.size():
		var radius: float = lane_radii[index]
		var body: PlayerController = runner_scene.instantiate() as PlayerController
		if body == null:
			push_error("MatchController's runner scene does not have a PlayerController at its root.")
			return
		body.name = "Runner_r%.1f" % radius
		runner_container.add_child(body)

		var brain: RingRunner = _find_brain(body)
		if brain == null:
			push_error("MatchController's runner scene has no RingRunner brain; the runner will not run.")
			body.queue_free()
			continue

		# Duplicate the profile: the scene's is a shared resource, and writing a
		# lane radius into it would retune every runner ever spawned from it,
		# including the ones already running.
		var profile: BotProfile = brain.profile.duplicate() as BotProfile
		profile.lane_radius = radius
		brain.profile = profile

		brain.reached_end.connect(_on_runner_reached_end.bind(brain))
		_brain_by_body[body.get_instance_id()] = brain
		_live.append(brain)
		brain.configure(centre, start_point, end_point)


## The brain, found by type rather than by path.
func _find_brain(body: Node) -> RingRunner:
	for child: Node in body.get_children():
		var brain: RingRunner = child as RingRunner
		if brain != null:
			return brain
	return null


func _clear_runners() -> void:
	for brain: RingRunner in _live:
		if brain.reached_end.is_connected(_on_runner_reached_end):
			brain.reached_end.disconnect(_on_runner_reached_end)
		var body: PlayerController = brain.controller
		if body != null:
			body.queue_free()
	_live.clear()
	_brain_by_body.clear()


func _on_target_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if is_resolved():
		return
	var runner: RingRunner = resolve_runner(collider)
	if runner == null:
		# The shot hit the world. A miss costs the same reload either way, which
		# is the rifle's business and not this node's.
		return
	remove_runner(runner)


func _on_runner_reached_end(_elapsed_seconds: float, _path_length: float, _runner: RingRunner) -> void:
	if is_resolved():
		return
	_resolve(Outcome.LOSS)


func _resolve(outcome: Outcome) -> void:
	if is_resolved():
		return
	_outcome = outcome
	_resolve_count += 1
	_freeze_runners()
	round_resolved.emit(_outcome)


## Stop the survivors dead the moment the round is decided.
##
## Not cosmetic: without it, the two runners still on the ring after a loss go
## on to finish their own laps a few seconds later and emit their own
## [signal RingRunner.reached_end]. The guard in [method _resolve] would swallow
## those, but a frozen ring is the honest picture of a round that is over.
func _freeze_runners() -> void:
	for brain: RingRunner in _live:
		brain.set_physics_process(false)
		if brain.input != null:
			brain.input.command.clear()
		var body: PlayerController = brain.controller
		if body != null:
			body.velocity = Vector3.ZERO
