class_name PowerStand
extends Node3D

## A hub stand: interact beside it and you hold its power (none, for the empty one). The pick is the
## host's ruling on your command and lives in your seat ([member LobbySeat.power]), so a stand has no state.

const REACH: float = 1.6
const REACH_HEIGHT: float = 2.0
## Where the power's visual stands: on the plinth.
const SHOW_HEIGHT: float = 0.4

## Every stand in the process; each answers only bodies of its own scene.
static var _all: Array[PowerStand] = []

@export var power: MatchRules.RunnerAbility = MatchRules.RunnerAbility.NONE

var _scene: Node = null


func _enter_tree() -> void:
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


func _ready() -> void:
	_scene = owner if owner != null else get_parent()
	var show: Node3D = RunnerPower.build_display(power)
	if show == null:
		return
	show.name = "Show"
	add_child(show)
	match power:
		MatchRules.RunnerAbility.BUBBLE_SHIELD:
			show.scale = Vector3.ONE * 0.3
			show.position = Vector3.UP * (SHOW_HEIGHT + RunnerPower.SHIELD_RADIUS * 0.3)
		MatchRules.RunnerAbility.ARMOR_LOCK:
			show.position = Vector3.UP * (SHOW_HEIGHT + 1.05)
		MatchRules.RunnerAbility.CAT_GRENADE:
			show.scale = Vector3.ONE * 1.5
			show.position = Vector3.UP * SHOW_HEIGHT
		_:
			(show as HologramView).pose(to_global(Vector3.UP * SHOW_HEIGHT), global_rotation.y, Vector3.ZERO)


## The stand [param body] is beside in its own scene, the nearest, or null.
static func in_reach(body: PlayerController) -> PowerStand:
	var best: PowerStand = null
	var best_distance: float = REACH
	for stand: PowerStand in _all:
		if stand._scene != null and not stand._scene.is_ancestor_of(body):
			continue
		var offset: Vector3 = stand.global_position - body.global_position
		if absf(offset.y) > REACH_HEIGHT:
			continue
		offset.y = 0.0
		if offset.length() <= best_distance:
			best = stand
			best_distance = offset.length()
	return best
