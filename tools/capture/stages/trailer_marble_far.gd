extends "res://tools/capture/stages/stage.gd"

## trailer_marble_far (23, the no-beach cut): Ryan: "from a runners pov, watching the sniper tower, snipe at two runners,
## much further ahead them themselves". Marble, the clear stretch between ArcWall126 (120.2-131.6) and ArcWall188 (182.5-194):
## the POV runs with his eyes on the tower window; two men 30-40 deg ahead are shot one after the other and lie where they fall.
## probe_ring --map=marble --eye=165:5.6:5.65: r 50 open 155-180, blocked 185 (ArcWall188). A POV inside a wall's bearings
## loses the window (the wall is 7.6 m, the window 5.65), so every body stays in 132-182 while it is on screen.
##   --map=marble --shot=pack_lead --stage=trailer_marble_far --bots=3 --pov=runner --rifle=projectile --seed=20261001
## Dials: start (the POV's bearing at the deal, 126.5), window (176), ahead_a/ahead_b (deg ahead of the POV: the first shot, the second; 40/33),
## fire_a (clip s, 1.95), fire_b (clip s, 2.985: hits 2.32 and 3.37, 63 frames apart), look (deg right of his run the eyes rest, 52), look_pitch (5).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const HUMAN_RUN := preload("res://tools/capture/stages/human_run.gd")

const POV: int = 0
const FIRST: int = 1
const SECOND: int = 2
const START_R: Array[float] = [55.0, 48.8, 49.8]
const SPEED: Array[float] = [0.70, 0.60, 0.62]
## The two ahead flinch at a shot and glance up at the tower; never behind.
const FLINCH: Array = [
	{"t": 0.0, "right": -8.0, "pitch": 4.0}, {"t": 0.12, "right": 10.0, "pitch": -4.0}, {"t": 0.38, "right": 62.0, "pitch": 9.0},
	{"t": 1.0, "right": 6.0, "pitch": -1.0},
]

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null


func bots() -> int:
	return 3


func needs_pov() -> String:
	return "runner"


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"marble"
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 0.8
	# The shipped rule: a shot man goes limp where he was hit and stays there.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var start: float = float(option("start", 126.5))
	var starts: Array[float] = [start, start + float(option("ahead_a", 40.0)), start + float(option("ahead_b", 33.0))]
	for index: int in range(3):
		var legs: Array = _legs(index)
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(starts[index], START_R[index], 0.1), "face": LIB.tangent_at(starts[index])},
			{"do": "human", "on": true},
			{"do": "hold", "seconds": 0.05 + 0.07 * index},
		]
		steps.append_array(HUMAN_RUN.steps(legs))
		steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[index], steps, index)
		_bodies.append(runners[index].controller)
	LIB.hide_from_the_rifle(_bodies[POV])
	stage_body(_bodies[POV])
	victim_body(_bodies[FIRST])
	say("trailer_marble_far: POV %s from %.1f deg, %s and %s ahead" % [_bodies[POV].name, start, _bodies[FIRST].name, _bodies[SECOND].name])
	return true


## The POV's eyes rest on the tower window, a mouse's drift on top; the two ahead run their lines.
func _legs(index: int) -> Array:
	if index == POV:
		var look: float = float(option("look", 52.0))
		var up: float = float(option("look_pitch", 5.0))
		return [{"to": 240.0, "r": START_R[POV], "speed": SPEED[POV], "weave": 0.03, "period": 1.4, "glances": [
			{"t": 0.0, "right": look - 6.0, "pitch": up - 1.0}, {"t": 0.9, "right": look + 2.0, "pitch": up},
			{"t": 1.7, "right": look - 2.0, "pitch": up + 0.5}, {"t": 2.6, "right": look + 1.0, "pitch": up - 0.5},
		]}]
	var weave: float = 0.04 if index == FIRST else 0.05
	return [{"to": 240.0, "r": START_R[index], "speed": SPEED[index], "weave": weave, "period": 1.2 + 0.2 * index,
		"flinch_on": "hit", "flinch_glances": FLINCH,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.8, "right": 6.0 * index, "pitch": -2.0}, {"t": 1.6, "right": -3.0, "pitch": -1.0}]}]


func tick(_delta: float) -> void:
	if _bodies.is_empty():
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		_log_frame()
	if _hand == null:
		_raise_the_hand()


## Positions, and where the window and the two ahead sit in the POV's frame (0..1 across and down; "x" behind him).
func _log_frame() -> void:
	var line: String = ""
	for body: PlayerController in _bodies:
		line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
	var eye: Camera3D = _bodies[POV].get_node_or_null(^"Head/Camera") as Camera3D
	if eye != null and eye.is_inside_tree():
		var size: Vector2 = eye.get_viewport().get_visible_rect().size
		var points: Array = [["win", _guard.global_position + Vector3.UP * 1.6 if _guard != null else LIB.ring_point(176.0, 5.6, 5.65) + Vector3.UP * 23.0]]
		points.append(["a", _bodies[FIRST].global_position + Vector3.UP])
		points.append(["b", _bodies[SECOND].global_position + Vector3.UP])
		for p: Array in points:
			var at: Vector3 = p[1]
			if eye.is_position_behind(at):
				line += " | %s x" % p[0]
			else:
				var s: Vector2 = eye.unproject_position(at) / size
				line += " | %s %.2f,%.2f %.0fm" % [p[0], s.x, s.y, eye.global_position.distance_to(at)]
	say("at" + line)


## The guard at the window, a hand on the mouse: the first man, then the second.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 176.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = elapsed() + 0.1
	_hand.park = _bodies[SECOND].global_position + Vector3.UP
	var fire_a: float = float(option("fire_a", 1.95))
	var swing: float = fire_a - _hand.start_at + 0.45
	_hand.beats.append({"body": _bodies[FIRST], "seconds": swing, "fire_at": fire_a - _hand.start_at, "watch": true})
	_hand.beats.append({"body": _bodies[SECOND], "seconds": 100.0, "fire_at": float(option("fire_b", 2.985)) - _hand.start_at - swing, "watch": true})
	say("guard at the window on %.0f deg; squeezes at %.2f and %.2f s" % [float(option("window", 176.0)), fire_a, float(option("fire_b", 2.985))])
	if OS.has_environment("STAGE_DEBUG") and controller().rifle != null:
		controller().rifle.target_hit.connect(func(c: Node3D, at: Vector3, _n: Vector3) -> void:
			say("round struck %s at %.1f deg r %.2f y %.2f" % [c.name if c != null else "?", LIB.bearing_of(at), LIB.radius_of(at), at.y]))


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
