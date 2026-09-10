class_name TestFixtures
extends RefCounted

## Builders shared by more than one test file.
##
## Two rules govern what belongs here.
##
## 1. [b]Prefer the shipped scene to a hand-built stand-in.[/b] A test that
##    assembles its own player out of loose nodes is testing a body no one plays;
##    if [code]scenes/player/player.tscn[/code] loses its collision shape the test
##    still passes. So the fixtures below instance the real scenes and the real
##    default profiles wherever the test does not need to vary them.
## 2. [b]Never mutate a shared resource.[/b] The default [code].tres[/code] files
##    are one instance shared by every scene that references them, and a test that
##    writes a field into one retunes every later test in the same process --
##    including tests in other files, because the runner is a single Godot
##    process. Every accessor here hands back a [method Resource.duplicate].

const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
const RUNNER_SCENE_PATH: String = "res://scenes/bot/ring_runner.tscn"
const RIFLE_SCENE_PATH: String = "res://scenes/weapon/rifle.tscn"
const ARENA_SCENE_PATH: String = "res://scenes/ring/bentham_ring.tscn"
const MATCH_SCENE_PATH: String = "res://scenes/match/match.tscn"

const MATCH_RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const GHOST_PROFILE_PATH: String = "res://resources/rules/default_ghost_profile.tres"

const MOVEMENT_PROFILE_PATH: String = "res://scenes/player/default_movement_profile.tres"
const WEAPON_PROFILE_PATH: String = "res://scenes/weapon/default_weapon_profile.tres"
const BOT_PROFILE_PATH: String = "res://scenes/bot/default_bot_profile.tres"

## Node paths into [code]scenes/ring/bentham_ring.tscn[/code]. The same defaults
## [MatchController] exports, restated here so a test can find the markers
## without owning a [MatchController].
const START_MARKER_PATH: NodePath = ^"StartEnd/PrisonerStart"
const END_MARKER_PATH: NodePath = ^"StartEnd/PrisonerEnd"
const TOWER_SPAWN_PATH: NodePath = ^"Tower/TowerSpawn"


# --- Profiles -----------------------------------------------------------------

## A private copy of the tuned movement profile.
static func movement_profile() -> MovementProfile:
	var profile: MovementProfile = load(MOVEMENT_PROFILE_PATH) as MovementProfile
	return profile.duplicate() as MovementProfile


## A private copy of the tuned weapon profile.
static func weapon_profile() -> WeaponProfile:
	var profile: WeaponProfile = load(WEAPON_PROFILE_PATH) as WeaponProfile
	return profile.duplicate() as WeaponProfile


## A private copy of the tuned bot profile.
static func bot_profile() -> BotProfile:
	var profile: BotProfile = load(BOT_PROFILE_PATH) as BotProfile
	return profile.duplicate() as BotProfile


## A private copy of the shipped match rules, with a private copy of the shipped
## ghost profile hung off it.
##
## Both copies matter. The [code].tres[/code] files are one instance each for the
## whole process, and the ghost tests turn ghosts ON -- writing that into the
## shared rules would hand every later test in the same process a game with
## ghosts in it, including the tests in other files that assert a shot prisoner
## is parked.
static func match_rules() -> MatchRules:
	var rules: MatchRules = (load(MATCH_RULES_PATH) as MatchRules).duplicate() as MatchRules
	rules.ghost_profile = ghost_profile()
	return rules


## A private copy of the shipped ghost profile.
static func ghost_profile() -> GhostProfile:
	return (load(GHOST_PROFILE_PATH) as GhostProfile).duplicate() as GhostProfile


# --- Bodies -------------------------------------------------------------------

## The real player scene, rewired to be driven by a [BotIntentSource].
##
## Built from [code]scenes/player/player.tscn[/code] rather than from loose
## nodes so the capsule, the head height and the collision layers under test are
## the ones the game ships. The human input node is disabled, not deleted: its
## presence is part of the scene, and deleting it would test a scene that does
## not exist.
##
## [param profile] is assigned before the instance enters the tree, because
## [method PlayerController._ready] reads it and refuses to move without one.
static func make_bot_player(profile: MovementProfile) -> PlayerController:
	var body: PlayerController = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	silence_human_input(body)
	body.profile = profile

	var input: BotIntentSource = BotIntentSource.new()
	input.name = "BotInput"
	body.add_child(input)
	body.intent_source = input
	return body


## The [BotIntentSource] driving a body built by [method make_bot_player].
static func bot_input_of(body: PlayerController) -> BotIntentSource:
	return body.intent_source as BotIntentSource


## Stop a player instance from grabbing the mouse or reading the keyboard.
##
## Headless runs have no mouse to capture and no window to capture it into, and
## a test that leaves [member Input.mouse_mode] captured leaks that state into
## every test that follows it in the same process.
static func silence_human_input(root: Node) -> void:
	for node: Node in _walk(root):
		var human: HumanIntentSource = node as HumanIntentSource
		if human != null:
			human.capture_mouse_on_ready = false
			human.set_active(false)
		var trigger: WeaponInput = node as WeaponInput
		if trigger != null:
			trigger.capture_mouse_on_ready = false
			trigger.set_active(false)


# --- World --------------------------------------------------------------------

## A large static box whose top surface sits at [param top_y].
##
## Deliberately enormous in plan: several movement tests slide a body a long way
## while they measure it, and a body that walks off the edge of its own test
## floor produces a failure that looks like a movement bug.
static func make_floor(top_y: float, extent: float = 400.0) -> StaticBody3D:
	return make_box_body(Vector3(extent, 2.0, extent), Vector3(0.0, top_y - 1.0, 0.0), "Floor")


## An axis-aligned static box, centred on [param centre].
static func make_box_body(size: Vector3, centre: Vector3, node_name: String) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	return body


## The greybox arena, exactly as the match scene composes it.
static func make_arena() -> Node3D:
	return (load(ARENA_SCENE_PATH) as PackedScene).instantiate() as Node3D


## The playable round: arena, tower player, rifle, [MatchController] and HUD.
##
## Human input is silenced before the instance is handed back, but the caller
## must do that work [b]before[/b] adding it to the tree -- [MatchController]
## arms the first round from [method Node._ready], which is the very behaviour
## the spawn-displacement regression test exists to watch.
static func make_match() -> Node3D:
	var match_root: Node3D = (load(MATCH_SCENE_PATH) as PackedScene).instantiate() as Node3D
	silence_human_input(match_root)
	return match_root


## Depth-first walk of a subtree, including [param root] itself.
static func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	for child: Node in root.get_children():
		found.append_array(_walk(child))
	return found
