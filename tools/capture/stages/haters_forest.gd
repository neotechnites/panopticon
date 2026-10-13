extends "res://tools/capture/stages/stage.gd"

## haters_forest: haters_hell's guard scope kill ported to the forest: 3 runners on haters.gd's cleared lanes, the hand drops
## each in turn (watch, clear); every lane stops short of the portal (345 deg), so no runner takes the tower. Dials: pace (0.7).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const SHOVER_AT := Vector2(281.0, 51.0)
const VICTIM_AT := Vector2(284.0, 48.75)
const LEAD_AT := Vector2(278.0, 52.5)

var _bodies: Array[PlayerController] = []
var _hand: Node = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0
	rules.guard_projectile_speed = 0.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func _run(at: Vector2, legs: Array, pace: float) -> Array:
	var steps: Array = [{"do": "place", "at": LIB.ring_point(at.x, at.y, 0.1)}, {"do": "human", "on": true}]
	for leg: Array in legs:
		steps.append({"do": "lane", "to": float(leg[0]), "r": float(leg[1]), "speed": pace,
			"weave": 0.04, "period": 1.3, "timeout": 30.0})
	steps.append({"do": "hold", "seconds": 60.0, "fidget": true})
	return steps


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for index: int in 3:
		if runners[index].controller == null:
			return false
	var pace: float = float(option("pace", 0.7))
	drive(runners[0], _run(LEAD_AT, [[324.0, LEAD_AT.y]], pace), 0, "ClipLeadDriver")
	drive(runners[1], _run(VICTIM_AT, [[290.0, 48.75], [300.0, 51.5], [306.0, 52.75], [316.0, 51.5],
		[322.0, 50.5], [332.0, 49.5]], pace * 0.9), 1, "ClipVictimDriver")
	drive(runners[2], _run(SHOVER_AT, [[287.0, 53.0], [295.0, 51.5], [301.0, 51.5], [306.0, 53.0], [316.0, 52.0],
		[322.0, 50.8], [337.0, 50.8]], pace), 2, "ClipShoverDriver")
	for index: int in 3:
		_bodies.append(runners[index].controller)
	victim_body(_bodies[1])
	say("haters_forest: %s, %s, %s on the forest lane; pace %.2f" % [_bodies[0].name, _bodies[1].name, _bodies[2].name, pace])
	return true


func tick(_delta: float) -> void:
	if _bodies.is_empty() or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	var stand: Vector3 = LIB.ring_point(float(option("guard_deg", 315.0)), float(option("guard_r", 4.4)), 0.0)
	guard.global_position = Vector3(stand.x, guard.global_position.y, stand.z)
	guard.velocity = Vector3.ZERO
	LIB.open_the_scope(guard, 0.74)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.beats = [
		{"body": _bodies[0], "seconds": 2.6, "fire_at": 2.2, "watch": true, "clear": true},
		{"body": _bodies[1], "seconds": 2.4, "fire_at": 1.8, "watch": true, "clear": true},
		{"body": _bodies[2], "seconds": 4.0, "fire_at": 1.4, "watch": true, "clear": true},
	]
	_hand.park = LIB.ring_point(LEAD_AT.x + 10.0, LEAD_AT.y, 1.0)
	_hand.start_at = float(option("hand_start", 0.8))
	say("tower brain stood down; the hand starts at %.1f s" % _hand.start_at)


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s" % (participant.body.name if participant.body else "?"))
