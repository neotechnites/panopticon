extends "res://tools/capture/stages/stage.gd"

## rs_tower: a runner has got into the tower room (where a finisher arrives, but not one: he can die);
## the guard, scoped out over the ring, turns round and shoots him point-blank. --pov=guard. Dials: wait (1.4), fire_at (1.0).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _body: PlayerController = null
var _hand: Node = null
var _spot: Vector3 = Vector3.ZERO
var _tower: Vector3 = Vector3.ZERO


func bots() -> int:
	return 2


func needs_pov() -> String:
	return "guard"


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	_tower = controller().get("_tower_point")
	var end: Vector3 = controller().get("_end_point")
	var aside: Vector3 = end - _tower
	aside.y = 0.0
	_spot = _tower + aside.normalized() * float(option("offset", 2.5))
	_body = runners[0].controller
	drive(runners[0], [
		{"do": "place", "at": _spot, "face": LIB.toward(_spot, _tower)},
		{"do": "hold", "seconds": float(option("wait", 1.4))},
		{"do": "run", "to": _goal(), "within": float(option("within", 1.8)), "speed": float(option("pace", 0.4)), "timeout": 4.0},
		{"do": "hold", "seconds": 60.0},
	], 0, "TowerRunner")
	drive(runners[1], [
		{"do": "place", "at": LIB.ring_point(58.0, 50.0, 0.1)},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipSpare")
	say("rs_tower: runner at %v, tower %v" % [_spot, _tower])
	return true


func tick(_delta: float) -> void:
	if _hand != null or _body == null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	LIB.open_the_scope(guard, 0.74)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.hold_scope = int(option("scope", 1)) == 1
	# Watching the ring on the far side from him, then round onto him.
	var away: Vector3 = _tower - (_spot - _tower) * 20.0
	away.y = LIB.DECK_Y + 1.0
	var along: Vector3 = away + (_spot - _tower).cross(Vector3.UP).normalized() * 12.0
	_hand.park = away
	_hand.beats.append({"at": along, "seconds": float(option("look", 1.6))})
	_hand.beats.append({"body": _body, "seconds": 4.0, "fire_at": float(option("fire_at", 1.0)), "watch": true})
	_hand.start_at = float(option("start", 1.2))
	say("rs_tower: hand on %s" % guard.name)


## Where he runs: at the guard, or (cross=1) across the room in front of him, so a kill keeps his run.
func _goal() -> Vector3:
	if int(option("cross", 0)) == 0:
		return _tower
	var out: Vector3 = (_spot - _tower).normalized()
	return _tower + out.cross(Vector3.UP).normalized() * 3.5 + out * 0.8
