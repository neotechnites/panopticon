extends "res://tools/capture/stages/stage.gd"

## forest_window: the guard at the 32 deg window scopes the open stretch (41-60 deg, probe_ring --los, eye 32:4.4:5.9)
## and drops 3 runners in turn as each crosses it; lanes end at 75 deg, nowhere near the tower. Dials: pace (0.6).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const STARTS: Array = [Vector3(37.0, 51.0, 0.0), Vector3(33.0, 50.0, 1.0), Vector3(29.0, 52.0, 2.2)]

var _bodies: Array[PlayerController] = []
var _hand: Node = null


func bots() -> int:
	return 3


func needs_pov() -> String:
	return "guard"


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0
	rules.guard_projectile_speed = 0.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	var pace: float = float(option("pace", 0.6))
	for index: int in 3:
		if runners[index].controller == null:
			return false
		var at: Vector3 = STARTS[index]
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(at.x, at.y, 0.1), "face": LIB.toward(LIB.ring_point(at.x, at.y), LIB.ring_point(at.x + 4.0, at.y))},
			{"do": "human", "on": true},
			{"do": "hold", "seconds": at.z, "fidget": true},
			{"do": "lane", "to": 75.0, "r": at.y, "speed": pace, "weave": 0.04, "period": 1.3, "timeout": 30.0},
			{"do": "hold", "seconds": 60.0, "fidget": true},
		], index, "ClipWindowRunner%d" % index)
		_bodies.append(runners[index].controller)
	say("forest_window: %s, %s, %s; pace %.2f" % [_bodies[0].name, _bodies[1].name, _bodies[2].name, pace])
	return true


func tick(_delta: float) -> void:
	if _bodies.is_empty() or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	var stand: Vector3 = LIB.ring_point(float(option("guard_deg", 32.0)), float(option("guard_r", 4.4)), 0.0)
	guard.global_position = Vector3(stand.x, guard.global_position.y, stand.z)
	guard.velocity = Vector3.ZERO
	LIB.open_the_scope(guard, 0.74)
	_tighten(guard, float(option("scope_fov", 0.0)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.beats = [
		{"body": _bodies[0], "seconds": 2.4, "fire_at": float(option("fire1", 1.6)), "watch": true, "clear": true},
		{"body": _bodies[1], "seconds": 2.6, "fire_at": float(option("fire2", 1.8)), "watch": true, "clear": true},
		{"body": _bodies[2], "seconds": 4.0, "fire_at": float(option("fire3", 1.8)), "watch": true, "clear": true},
	]
	_hand.park = LIB.ring_point(44.0, 51.0, 1.0)
	_hand.start_at = float(option("hand_start", 1.0))
	say("forest_window: hand on %s at the %.0f deg window, starts %.1f s" % [guard.name, float(option("guard_deg", 32.0)), _hand.start_at])


## scope_fov > 0 narrows the zoomed lens to that many degrees so a runner fills the scope.
func _tighten(guard: PlayerController, fov: float) -> void:
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic
	if fov <= 0.0 or optic == null or optic.profile == null or optic.base_fov <= 0.0:
		return
	optic.profile.zoom_factor = clampf(fov / optic.base_fov, 0.05, 1.0)
	say("forest_window: scope fov %.1f (base %.1f)" % [fov, optic.base_fov])


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s" % (participant.body.name if participant.body else "?"))
