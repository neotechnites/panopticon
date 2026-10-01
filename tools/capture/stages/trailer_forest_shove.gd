extends "res://tools/capture/stages/stage.gd"

## trailer_forest_shove: Ryan, "a prisoner shoves another out of cover into the open,
## who is shot". A prisoner crouches behind the lane trunk at 100.66 deg (tree_b, IN
## r 49.9); a second runs up the lane behind him, shoves him out (+bearing) into the open,
## and the guard in the 90 deg window drops him once he lands. Down the shover's eyes:
## [code]--map=forest --shot=pack_lead --stage=trailer_forest_shove --bots=2 --pov=runner[/code]
## (or --pov=guard --hud=crosshair, the same event through the scope).
## probe_ring --map=forest --eye=90:4.6:5.85 --los at r 51.4: BLOCKED 99.5-101.5 (the lip
## trunk at 99.79 r 47.45 and the lane trunk), open 98-99 and 102-103; a lip boulder at
## 104.63 hides a crouch (h 0.7) at 104-105, a standing chest (h 1.2) stays open.
## Dials: victim (100.8,51.8), shover (95.6,51.8), impulse (8.5), up (4.0), wait (0.9),
## squeeze (0.3), window (90), win_r (4.6).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _victim: PlayerController = null
var _shover: PlayerController = null
var _victim_driver: Node = null
var _hand: Node = null
var _shoved: bool = false
var _shoved_at: float = 0.0
var _landed: bool = false


func bots() -> int:
	return 2


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 8.5))
	rules.shove_up_impulse = float(option("up", 4.0))
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var v: Vector3 = LIB.polar(String(option("victim", "100.8,51.8")), LIB.ring_point(100.8, 51.8))
	var s: Vector3 = LIB.polar(String(option("shover", "95.6,51.8")), LIB.ring_point(95.6, 51.8))
	var v_deg: float = LIB.bearing_of(v)
	_victim = runners[0].controller
	_shover = runners[1].controller
	# Crouched in the trunk's shadow, half turned to peek round it at the tower.
	_victim_driver = drive(runners[0], [
		{"do": "place", "at": v + Vector3.UP * 0.1, "face": (-LIB.radial_at(v_deg) * 0.7 + LIB.tangent_at(v_deg) * 0.5).normalized()},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 60.0, "crouch": true, "sway": 10.0, "period": 2.4},
	], 0, "ClipVictimDriver")
	# The shover: a beat on the lane, then up behind him and the shove; then he
	# drops into the shadow himself and watches. Out of the rifle's group: the open lane.
	LIB.hide_from_the_rifle(_shover)
	drive(runners[1], [
		{"do": "place", "at": s + Vector3.UP * 0.1, "face": LIB.tangent_at(LIB.bearing_of(s))},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": float(option("wait", 0.9))},
		{"do": "chase", "victim": _victim, "range": 1.6, "timeout": 6.0, "speed": float(option("speed", 0.7))},
		{"do": "hold", "seconds": 60.0, "crouch": true},
	], 1, "ClipShoverDriver")
	for index: int in range(2, runners.size()):
		# Anyone past the two is parked well down the lap, out of every frame.
		drive(runners[index], [{"do": "place", "at": LIB.ring_point(250.0, 52.0, 0.1)}, {"do": "hold", "seconds": 60.0}], index)
		LIB.hide_from_the_rifle(runners[index].controller)
	victim_body(_victim)
	stage_body(_shover)
	say("trailer_forest_shove: %s crouched at %.1f deg r %.1f, %s from %.1f" % [_victim.name, v_deg, LIB.radius_of(v), _shover.name, LIB.bearing_of(s)])
	return true


func tick(_delta: float) -> void:
	if _victim == null:
		return
	if OS.has_environment("STAGE_DEBUG") and is_instance_valid(_victim) and Engine.get_physics_frames() % 15 == 0:
		say("victim at %.1f deg r %.1f y %.2f; shover at %.1f deg r %.1f" % [LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.y, LIB.bearing_of(_shover.global_position), LIB.radius_of(_shover.global_position)])
	if _hand == null:
		_raise_the_hand()
		return
	if _shoved and not _landed and elapsed() > _shoved_at + 0.25 and is_instance_valid(_victim) and _victim.is_on_floor():
		_landed = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at + float(option("squeeze", 0.3))
		say("victim landed at %.1f deg r %.1f; the hand squeezes in %.2f s" % [LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), float(option("squeeze", 0.3))])


## Stand the tower brain down, the guard in his window, the hand resting on the trunk.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	LIB.guard_to_window(guard, float(option("window", 90.0)), float(option("win_r", 4.6)))
	LIB.open_the_scope(guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true})
	_hand.park = _victim.global_position + Vector3.UP
	_hand.start_at = elapsed() + 0.2


func on_shove(_shover_p: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	_shoved_at = elapsed()
	# Crouch key up this tick: he flies, lands and stands where he lands.
	if _victim_driver != null:
		_victim_driver.retarget([{"do": "hold", "seconds": 60.0}])
	say("shove landed on %s" % victim.body.name)


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s" % participant.body.name)
