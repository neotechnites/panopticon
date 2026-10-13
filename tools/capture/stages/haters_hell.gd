extends "res://tools/capture/stages/stage.gd"

## haters_hell: one hell match, 1 guard + 3 runners on S2; the guard drops the man beside the POV,
## the POV looks up at the tower, then shoves the lead into the pit. Dials as trailer_open's plus fire_at.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

## Lead (pit side, just ahead of the POV), victim (well ahead, on the guard's clear line), POV: the tower look stays clear.
const RADII: Array[float] = [47.4, 48.6, 48.2]
const STAGGER: Array[float] = [2.2, 13.8, 0.0]
const PACE: Array[float] = [0.70, 0.71, 0.70]
const WEAVE: Array[float] = [0.02, 0.04, 0.03]
const PERIOD: Array[float] = [1.3, 1.5, 1.7]
const LEAD: int = 0
const VICTIM: int = 1
const POV: int = 2
## The hit lands about this long after the squeeze (hitscan).
const HIT_LAG: float = 0.36

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null
var _start: float = 90.0


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"bentham_ring"
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	# The shipped rule: a shot man plays his death and lies where he fell, not parked out of the world.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < RADII.size():
		return false
	for index: int in RADII.size():
		if runners[index].controller == null:
			return false
	_start = float(option("start", 72.0))
	var hit: float = float(option("fire_at", 4.4)) + HIT_LAG
	var cast_at: float = elapsed()
	for index: int in RADII.size():
		var deg: float = _start + STAGGER[index]
		var lane: Dictionary = {
			"do": "lane", "to": 165.0, "r": RADII[index], "speed": PACE[index],
			"weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0,
		}
		if index == LEAD:
			lane["timeout"] = hit + float(option("lead_stop", 3.4)) - cast_at
		if index == POV:
			# Eyes up the lane and on the men ahead; never back. On the hit: a jerk, then up at the tower.
			lane["glances"] = [
				{"t": 0.0, "right": 0.0, "pitch": -2.0},
				{"t": 0.9, "right": -14.0, "pitch": -3.0},
				{"t": 1.35, "right": 4.0, "pitch": -1.5},
				{"t": 2.1, "right": 9.0, "pitch": -2.0},
				{"t": 2.6, "right": 1.0, "pitch": -1.0},
			]
			lane["strafes"] = [{"t": 0.5, "strafe": 0.08}, {"t": 1.6, "strafe": -0.06}, {"t": 2.5, "strafe": 0.04}]
			lane["flinch_on"] = "hit"
			var up_right: float = float(option("up_right", 86.0))
			var up_pitch: float = float(option("up_pitch", 12.0))
			lane["flinch_glances"] = [
				{"t": 0.0, "right": -7.0, "pitch": 5.0},
				{"t": 0.1, "right": 5.0, "pitch": -4.0},
				{"t": 0.32, "right": up_right, "pitch": up_pitch},
				{"t": 1.9, "right": 16.0, "pitch": -6.0},
			]
			lane["timeout"] = hit + float(option("shove_go", 2.6)) - cast_at
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(deg, RADII[index], 0.1), "face": LIB.tangent_at(deg)},
			{"do": "human", "on": true},
			lane,
			{"do": "hold", "seconds": 60.0, "fidget": true},
		]
		if index == POV:
			steps[3] = {"do": "chase", "victim": runners[LEAD].controller, "range": 2.0, "timeout": 4.0}
			steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[index], steps, index)
		_bodies.append(runners[index].controller)
	victim_body(_bodies[VICTIM])
	stage_body(_bodies[POV])
	say("haters_hell: three on S2's inner lane from %.1f deg; victim %s, POV %s" % [_start, _bodies[VICTIM].name, _bodies[POV].name])
	return true


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and not _bodies.is_empty() and Engine.get_physics_frames() % 15 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _bodies.is_empty():
		return
	if _hand == null:
		_raise_the_hand()
		return
	var zoomed: bool = elapsed() >= float(option("zoom_at", 1.2))
	_hand.hold_scope = zoomed
	if not zoomed:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)


## Stand the tower's brain down, walk the guard to the window and put a hand on the mouse.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 115.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 0.8))
	_hand.beats.append({"body": _bodies[VICTIM], "seconds": 100.0, "fire_at": float(option("fire_at", 4.4)) - _hand.start_at, "watch": true})
	_hand.park = LIB.ring_point(_start + float(option("park", 10.0)), 49.0, 0.6)
	say("guard at the window on %.0f deg; the hand from %.2f s, squeeze at %.2f s" % [float(option("window", 115.0)), _hand.start_at, float(option("fire_at", 4.4))])


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
