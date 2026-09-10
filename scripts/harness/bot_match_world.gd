class_name BotMatchWorld
extends Node3D

## Everything a headless bot match needs, assembled in code: the greybox arena,
## a container for the AI bodies, one rifle, and a [MatchController] wired to
## them.
##
## [b]Why this is not scenes/match/match.tscn[/b]
##
## The shipped match scene contains a HUD, a pause menu and -- decisively -- a
## human body. [MatchController] gives the human the first participant slot, and
## a human body with nobody at the keyboard is a participant who never runs a
## lap and, when the tower reaches them, never fires. One dead seat in a four
## player match makes every measurement taken from it a measurement of a game
## nobody plays. So the harness composes the same parts with no human in them
## and leaves the match scene alone -- which also means this file does not break
## when the match scene is re-authored.
##
## Nothing here reaches inside [MatchController]. It is configured through its
## exports, started through [method MatchController.start_match], and read
## through its accessors and signals.

## Last resort only. The arena a sweep runs is the one
## [member MatchRules.map_id] names, resolved through [MapCatalog], so that a
## sweep and a played match are measuring the same ground; this constant is what
## is left if the catalog itself cannot be read.
const ARENA_SCENE_PATH: String = "res://scenes/ring/bentham_ring.tscn"
const RUNNER_SCENE_PATH: String = "res://scenes/bot/ring_runner.tscn"
const RIFLE_SCENE_PATH: String = "res://scenes/weapon/rifle.tscn"

var _controller: MatchController = null
var _rifle: Rifle = null
var _arena: Node3D = null
var _runners: Node3D = null


## Build the world around [param rules]. Call it after this node is in the tree:
## the arena's markers are read in world space when the match starts.
##
## The rifle's [WeaponProfile] is duplicated and its tracer lifetime zeroed. A
## tracer is a mesh built per shot and seen by nobody in a headless sweep; it is
## the only thing removed, it changes no timing the match reads, and the copy is
## private so the shared .tres is not retuned for whatever runs next in the same
## process.
func build(rules: MatchRules) -> void:
	name = "BotMatchWorld"

	_arena = (load(resolve_arena_path(rules)) as PackedScene).instantiate() as Node3D
	_arena.name = "Arena"
	add_child(_arena)

	_runners = Node3D.new()
	_runners.name = "Runners"
	add_child(_runners)

	_rifle = (load(RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	_rifle.name = "Rifle"
	if _rifle.profile != null:
		var weapon: WeaponProfile = _rifle.profile.duplicate() as WeaponProfile
		weapon.tracer_lifetime = 0.0
		_rifle.profile = weapon
	add_child(_rifle)

	_controller = MatchController.new()
	_controller.name = "MatchController"
	_controller.rules = rules
	_controller.arena = _arena
	_controller.player = null
	_controller.rifle = _rifle
	_controller.runner_container = _runners
	_controller.runner_scene = load(RUNNER_SCENE_PATH) as PackedScene
	# The harness starts the match itself, once the telemetry and the tower
	# brain are listening. Armed from _ready, the opening race would already be
	# running before anything could watch it.
	_controller.auto_start = false
	add_child(_controller)

	silence_local_input(self)


## The arena scene [param rules] names, or [constant ARENA_SCENE_PATH] if the
## catalog cannot answer.
##
## Static so a sweep spec can be checked against the maps that exist before a
## single match is run, and so this file holds no second opinion about which
## arena a rule set means.
static func resolve_arena_path(rules: MatchRules) -> String:
	var id: StringName = rules.map_id if rules != null else &""
	var path: String = MapCatalog.scene_path_for(id)
	return path if not path.is_empty() else ARENA_SCENE_PATH


## The controller running this world. The harness's entire view of the match.
func get_controller() -> MatchController:
	return _controller


## The one rifle in the match, whoever is currently holding it.
func get_rifle() -> Rifle:
	return _rifle


## The node AI bodies are spawned under, so a caller can find them after the
## match has started.
func get_runner_container() -> Node3D:
	return _runners


## Switch off every node in [param root] that reads the local keyboard or mouse.
##
## A headless run has no window to capture a cursor into and no device to poll,
## so none of these do anything -- until the day one of them does, and an
## unattended sweep is the worst place to discover that a bot's trigger was
## being pulled by a stray input event. Called on the world at build time and
## again on each AI body as it spawns.
static func silence_local_input(root: Node) -> void:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)

		var human: HumanIntentSource = node as HumanIntentSource
		if human != null:
			human.capture_mouse_on_ready = false
			human.set_active(false)

		var trigger: WeaponInput = node as WeaponInput
		if trigger != null:
			trigger.capture_mouse_on_ready = false
			trigger.set_active(false)
