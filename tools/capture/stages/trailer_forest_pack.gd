extends "res://tools/capture/stages/stage.gd"

## trailer_forest_pack: the reveal trailer's hook on the forest. Three prisoners run
## the lane together (+bearing) through the trunk slalom; the guard, standing in his
## window, scopes one in a gap between trees and drops him. One deterministic stage,
## two POVs: [code]--pov=runner[/code] (the tail, a step behind and outside the victim)
## and [code]--pov=guard --hud=crosshair[/code], same seed, same events.
## [code]--map=forest --shot=pack_lead --stage=trailer_forest_pack --bots=3[/code]
##
## Geometry (forest_trees.py LAYOUT, probe_ring --map=forest): lane trunks IN (r 49.9)
## at 14.96, 20.73, 26.09 and OUT (r 53.8) at 32.94, 39.2; lip trunks (r 47.3) too. So
## r 51.6-52.4 is a clear corridor the whole stretch. From the window eye (45, 4.6,
## +5.85; floor +4.05, the bark lip +4.60 from r 5.2) --los at r 51.8 h 1: BLOCKED at
## 20, 26 (lane trunks) and 34 (a lip trunk), open at 22-24, 28-32, 36-64. The pack
## crosses those shadows; the hand takes the victim in the 28-32 gap.
## Dials: window (45), win_r (4.6), fire (clip s, 3.55), zoom (clip s, 2.0), lift (0).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

## Start bearing, radius, pace and weave per body: lead, victim, tail.
const STARTS: Array[float] = [9.4, 7.6, 5.2]
const RADII: Array[float] = [52.3, 51.7, 52.0]
const PACE: Array[float] = [0.71, 0.70, 0.705]
const WEAVE: Array[float] = [0.05, 0.04, 0.06]
const PERIOD: Array[float] = [1.2, 1.45, 1.0]
const VICTIM: int = 1
## The ridden body: the tail, 2.4 deg (2.2 m) behind the victim and 0.3 m outside him.
const POV: int = 2

var _pack: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	if int(option("lift", 0)) == 1:
		var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure *= 1.8
			world.environment = env


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < STARTS.size():
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	for index: int in STARTS.size():
		var body: PlayerController = runners[index].controller
		# Eyes up the lane, a glance at the trees either side; never behind.
		var glances: Array = [
			{"t": 0.0, "right": 0.0, "pitch": -1.0},
			{"t": 0.8 + 0.3 * index, "right": -18.0 + 9.0 * index, "pitch": -2.0},
			{"t": 1.5 + 0.2 * index, "right": 4.0, "pitch": -1.0},
			{"t": 2.4 + 0.25 * index, "right": 14.0 - 6.0 * index, "pitch": 2.0},
			{"t": 3.1 + 0.2 * index, "right": -3.0, "pitch": -1.0},
		]
		var lane: Dictionary = {"do": "lane", "to": 80.0, "r": RADII[index], "speed": PACE[index], "weave": WEAVE[index],
			"period": PERIOD[index], "timeout": 30.0, "glances": glances}
		if index == POV:
			# The rider: a look left at the lead, right at the victim ahead; when he drops,
			# a jerk, then up and right at the tower he came from; eyes front. Never behind.
			lane["glances"] = [
				{"t": 0.0, "right": 0.0, "pitch": -2.0},
				{"t": 0.6, "right": -24.0, "pitch": -3.0},
				{"t": 1.05, "right": -6.0, "pitch": -2.0},
				{"t": 1.6, "right": 12.0, "pitch": -3.0},
				{"t": 2.2, "right": 3.0, "pitch": -2.0},
				{"t": 2.65, "right": 9.0, "pitch": -4.0},
			]
			lane["strafes"] = [{"t": 0.5, "strafe": 0.12}, {"t": 1.4, "strafe": -0.08}, {"t": 2.3, "strafe": 0.06}]
			lane["flinch_on"] = "hit"
			lane["flinch_glances"] = [
				{"t": 0.0, "right": 6.0, "pitch": 5.0},
				{"t": 0.12, "right": 14.0, "pitch": -6.0},
				{"t": 0.4, "right": 80.0, "pitch": 10.0},
				{"t": 1.15, "right": 76.0, "pitch": 8.0},
				{"t": 1.5, "right": 4.0, "pitch": -2.0},
				{"t": 2.2, "right": -8.0, "pitch": -2.0},
			]
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(STARTS[index], RADII[index], 0.1), "face": LIB.tangent_at(STARTS[index])},
			{"do": "human", "on": true},
			lane,
			{"do": "hold", "seconds": 60.0},
		], index)
		if index != VICTIM:
			LIB.hide_from_the_rifle(body)
		_pack.append(body)
	victim_body(_pack[VICTIM])
	stage_body(_pack[POV])
	say("trailer_forest_pack: three from %.1f deg, victim %s" % [STARTS[0], _pack[VICTIM].name])
	return true


func tick(_delta: float) -> void:
	if _pack.is_empty():
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 15 == 0:
		var v: Vector3 = _pack[VICTIM].global_position
		say("victim at %.1f deg r %.1f" % [LIB.bearing_of(v), LIB.radius_of(v)])
	if _hand == null:
		_raise_the_hand()
		return
	_hand.hold_scope = elapsed() >= float(option("zoom", 2.0))
	if not _hand.hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)


## Stand the tower brain down, put the guard in his window, a hand on the mouse.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 45.0)), float(option("win_r", 4.6)))
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = elapsed() + 0.6
	_hand.park = LIB.ring_point(30.0, 52.0, 1.0)
	_hand.beats.append({"body": _pack[VICTIM], "seconds": 100.0, "fire_at": float(option("fire", 3.55)) - _hand.start_at, "watch": true})
	say("guard at the %.0f deg window; squeeze at %.2f s" % [float(option("window", 45.0)), float(option("fire", 3.55))])


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
