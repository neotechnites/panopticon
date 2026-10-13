extends "res://tools/capture/stages/stage.gd"

## forest_pov_kills: down a runner's eyes on the forest's open stretch (41-60 deg, seen from the 32 deg window), three
## running close ahead and beside are dropped in turn by the guard's hand; the POV is hidden from the rifle. Dials: pace (0.5).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
## Start bearing, radius, then the radius after the 46.5-48 trunk (r 49.5-52): beside-inner, beside-outer, lead, POV.
const STARTS: Array = [Vector3(42.0, 51.4, 52.3), Vector3(43.6, 53.2, 53.1), Vector3(45.6, 52.7, 52.7), Vector3(40.0, 52.6, 52.6)]
const POV: int = 3

var _bodies: Array[PlayerController] = []
var _hand: Node = null


func bots() -> int:
	return 4


func needs_pov() -> String:
	return "runner"


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 0.8
	rules.guard_projectile_speed = 0.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < STARTS.size():
		return false
	var pace: float = float(option("pace", 0.5))
	for index: int in STARTS.size():
		if runners[index].controller == null:
			return false
	for index: int in STARTS.size():
		var at: Vector3 = STARTS[index]
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(at.x, at.y, 0.1), "face": LIB.tangent_at(at.x)},
			{"do": "human", "on": true},
		]
		if index == POV:
			steps.append({"do": "lane", "to": 80.0, "r": at.y, "speed": pace, "weave": 0.03, "period": 1.2, "timeout": 30.0,
				"glances": [{"t": 0.0, "right": 0.0, "pitch": -3.0}, {"t": 1.2, "right": -5.0, "pitch": -3.0},
					{"t": 2.4, "right": 4.0, "pitch": -3.0}, {"t": 3.6, "right": 0.0, "pitch": -3.0}]})
		else:
			steps.append({"do": "lane", "to": 46.0, "r": at.y, "speed": pace, "weave": 0.03, "period": 1.3, "timeout": 30.0})
			steps.append({"do": "lane", "to": 80.0, "r": at.z, "speed": pace, "weave": 0.03, "period": 1.3, "timeout": 30.0})
		steps.append({"do": "hold", "seconds": 60.0, "fidget": true})
		drive(runners[index], steps, index, "ClipPovKills%d" % index)
		_bodies.append(runners[index].controller)
	LIB.hide_from_the_rifle(_bodies[POV])
	stage_body(_bodies[POV])
	victim_body(_bodies[0])
	say("forest_pov_kills: POV %s behind %s, %s, %s; pace %.2f" % [_bodies[POV].name, _bodies[0].name, _bodies[1].name, _bodies[2].name, pace])
	return true


func tick(_delta: float) -> void:
	if _bodies.is_empty() or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	LIB.guard_to_window(guard, float(option("guard_deg", 32.0)), float(option("guard_r", 4.4)))
	LIB.open_the_scope(guard, 0.74)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.beats = [
		{"body": _bodies[0], "seconds": 1.4, "fire_at": float(option("fire1", 0.8)), "watch": true, "clear": true},
		{"body": _bodies[1], "seconds": 1.4, "fire_at": float(option("fire2", 0.8)), "watch": true, "clear": true},
		{"body": _bodies[2], "seconds": 4.0, "fire_at": float(option("fire3", 0.8)), "watch": true, "clear": true},
	]
	_hand.park = LIB.ring_point(44.0, 52.0, 1.0)
	_hand.start_at = elapsed() + float(option("hand_start", 0.6))
	say("forest_pov_kills: hand on %s at the %.0f deg window" % [guard.name, float(option("guard_deg", 32.0))])


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
