extends "res://tools/capture/stages/stage.gd"

## trailer_marble_track (5b): the guard at marble's 126 deg window, scoped in, tracks three runners
## past the inner-edge columns (trailer_marble_column's, this shot only); swings from one to the next, no shot.
## probe_ring --map=marble --eye=126:5.6:5.8: r 48.6-52 open 118-140 bar the columns in front.
## Dials: start (106.5), zoom (0.8), swing (clip s the hand leaves the lead, 2.4).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const COLUMNS := preload("res://tools/capture/stages/trailer_marble_column.gd")

## Per body, ahead to behind: bearing offset from start, radius, pace, weave, period.
const OFFSET: Array[float] = [5.6, 2.1, 0.0]
const RADII: Array[float] = [50.9, 49.7, 51.6]
const PACE: Array[float] = [0.69, 0.73, 0.71]
const WEAVE: Array[float] = [0.06, 0.04, 0.08]
const PERIOD: Array[float] = [1.35, 1.1, 1.6]
## The bodies the hand works: the lead first, then back to the man behind him.
const FIRST: int = 0
const SECOND: int = 1

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"marble"
	rules.guard_projectile_speed = 0.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	COLUMNS.spawn_columns(controller().arena if controller().arena != null else clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var start: float = float(option("start", 106.5))
	for index: int in range(3):
		var deg: float = start + OFFSET[index]
		# Eyes up the lane, a look at the columns and up at the tower they are passing; never behind.
		var glances: Array = [
			{"t": 0.0, "right": 0.0, "pitch": -1.0},
			{"t": 0.55 + 0.35 * index, "right": -22.0 + 6.0 * index, "pitch": 6.0 - 2.0 * index},
			{"t": 1.2 + 0.25 * index, "right": 3.0, "pitch": -1.5},
			{"t": 2.0 + 0.3 * index, "right": 11.0 - 7.0 * index, "pitch": -2.0},
			{"t": 2.7 + 0.2 * index, "right": -2.0, "pitch": -1.0},
		]
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(deg, RADII[index], 0.1), "face": LIB.tangent_at(deg)},
			{"do": "human", "on": true},
			{"do": "hold", "seconds": 0.05 + 0.12 * index},
			{"do": "lane", "to": 175.0, "r": RADII[index], "speed": PACE[index], "weave": WEAVE[index],
				"period": PERIOD[index], "timeout": 30.0, "glances": glances},
			{"do": "hold", "seconds": 60.0},
		]
		drive(runners[index], steps, index)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[FIRST])
	say("trailer_marble_track: three from %.1f deg past the columns" % start)
	return true


func tick(_delta: float) -> void:
	if _bodies.is_empty():
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 15 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _hand == null:
		_raise_the_hand()
		return
	_hand.hold_scope = elapsed() >= float(option("zoom", 0.8))
	if not _hand.hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)


## The guard at the window, a hand on the mouse: on the lead, then back to the man behind him.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 126.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = elapsed() + 0.1
	_hand.park = LIB.ring_point(float(option("start", 106.5)) + 6.0, 50.0, 1.0)
	_hand.beats.append({"body": _bodies[FIRST], "seconds": float(option("swing", 2.4)) - _hand.start_at})
	_hand.beats.append({"body": _bodies[SECOND], "seconds": 100.0})


func lens(_delta: float) -> bool:
	return false
