extends "res://tools/capture/stages/stage.gd"

## trailer_marble_far_lever (23alt): Ryan: "make an alternate version of just this clip, where instead of shooting at the runners,
## the sniper shoots one of the levers and drops a runner into a pit?" 23's runner POV as it is (eyes on the window, running, two men
## ahead) on Section B: the round hits a trapdoor's wall-top plate on the beat and the man crossing that door drops into the pit.
## Section B: low walls (3 m) at the lip never hide the window; the POV starts past ArcWall253 (ends 258.5); the victim 15 deg ahead at the drop, big enough to read.
##   --map=marble --shot=pack_lead --stage=trailer_marble_far_lever --bots=3 --pov=runner --rifle=projectile --seed=20261001
## Dials: start (the POV's bearing at the deal, 265), ahead_a/ahead_b (deg ahead of him at the deal: the victim, the far man; 16/31),
## section/door (SectionB/Trapdoor4), window (291: the opening 273.7-293.8 of the colonnade), fire (clip s the round is squeezed, 1.98),
## look (deg right of his run the eyes rest, 47), look_pitch (5), gravity (the round's drop the squeeze holds over, 22).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const HUMAN_RUN := preload("res://tools/capture/stages/human_run.gd")

const POV: int = 0
const VICTIM: int = 1
const FAR: int = 2
const START_R: Array[float] = [55.0, 53.5, 54.0]
const SPEED: Array[float] = [0.70, 0.60, 0.62]
## The two ahead flinch at the shot and glance up at the tower; never behind.
const FLINCH: Array = [
	{"t": 0.0, "right": -8.0, "pitch": 4.0}, {"t": 0.12, "right": 10.0, "pitch": -4.0}, {"t": 0.38, "right": 62.0, "pitch": 9.0},
	{"t": 1.0, "right": 6.0, "pitch": -1.0},
]

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null
var _plate: Node3D = null
var _fired: bool = false
var _dropped: bool = false


func bots() -> int:
	return 3


func needs_pov() -> String:
	return "runner"


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"marble"
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 0.8
	# The shipped rule: a man who drops goes limp where he lands and stays there.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


## Pads off; the pits stay live, the drop is the shot.
func before_start() -> void:
	LIB.disarm_pads(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var start: float = float(option("start", 265.0))
	var starts: Array[float] = [start, start + float(option("ahead_a", 16.0)), start + float(option("ahead_b", 31.0))]
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
	victim_body(_bodies[VICTIM])
	say("trailer_marble_far_lever: POV %s from %.1f deg, %s and %s ahead" % [_bodies[POV].name, start, _bodies[VICTIM].name, _bodies[FAR].name])
	return true


## The POV's eyes rest on the tower window, a mouse's drift on top; the two ahead run their lines.
func _legs(index: int) -> Array:
	if index == POV:
		var look: float = float(option("look", 47.0))
		var up: float = float(option("look_pitch", 5.0))
		return [{"to": 350.0, "r": START_R[POV], "speed": SPEED[POV], "weave": 0.03, "period": 1.4, "glances": [
			{"t": 0.0, "right": look - 6.0, "pitch": up - 1.0}, {"t": 0.9, "right": look + 2.0, "pitch": up},
			{"t": 1.7, "right": look - 2.0, "pitch": up + 0.5}, {"t": 2.6, "right": look + 1.0, "pitch": up - 0.5},
		]}]
	var weave: float = 0.04 if index == VICTIM else 0.05
	return [{"to": 350.0, "r": START_R[index], "speed": SPEED[index], "weave": weave, "period": 1.2 + 0.2 * index,
		"flinch_on": "hit", "flinch_glances": FLINCH,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.8, "right": 6.0 * index, "pitch": -2.0}, {"t": 1.6, "right": -3.0, "pitch": -1.0}]}]


func tick(_delta: float) -> void:
	if _bodies.is_empty():
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		_log_frame()
	if _hand == null:
		_raise_the_hand()
		return
	if not _fired and elapsed() >= float(option("fire", 1.98)):
		_fired = true
		_squeeze()
	var victim: PlayerController = _bodies[VICTIM]
	if not _dropped and is_instance_valid(victim) and victim.global_position.y < LIB.DECK_Y - 0.4:
		_dropped = true
		say("dropped %s at %.1f deg r %.2f y %.2f" % [victim.name, LIB.bearing_of(victim.global_position), LIB.radius_of(victim.global_position), victim.global_position.y])


## Positions, and where the window, the plate and the two ahead sit in the POV's frame (0..1 across and down; "x" behind him).
func _log_frame() -> void:
	var line: String = ""
	for body: PlayerController in _bodies:
		line += " %s %.1f/%.2f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y]
	var eye: Camera3D = _bodies[POV].get_node_or_null(^"Head/Camera") as Camera3D
	if eye != null and eye.is_inside_tree():
		var size: Vector2 = eye.get_viewport().get_visible_rect().size
		var points: Array = [["win", _guard.global_position + Vector3.UP * 1.6 if _guard != null else LIB.ring_point(float(option("window", 291.0)), 5.6, 5.65) + Vector3.UP * 23.0]]
		if _plate != null:
			points.append(["plate", _plate.global_position])
		points.append(["a", _bodies[VICTIM].global_position + Vector3.UP])
		points.append(["b", _bodies[FAR].global_position + Vector3.UP])
		for p: Array in points:
			var at: Vector3 = p[1]
			if eye.is_position_behind(at):
				line += " | %s x" % p[0]
			else:
				var s: Vector2 = eye.unproject_position(at) / size
				line += " | %s %.2f,%.2f %.0fm" % [p[0], s.x, s.y, eye.global_position.distance_to(at)]
	say("at" + line)


## The plate hitbox of a section's door (the rifle's mark).
func _find_plate() -> Node3D:
	var section: Node = LIB.find_node(clip.root, String(option("section", "SectionB")))
	var door: TrapDoor = section.get_node_or_null(NodePath(String(option("door", "Trapdoor4")))) as TrapDoor if section != null else null
	return door.find_child("PlateHitbox", true, false) as Node3D if door != null else null


## The guard at the window, the hand on the mouse, resting on the plate until the squeeze.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_plate = _find_plate()
	if _plate == null:
		say("no plate for %s/%s" % [String(option("section", "SectionB")), String(option("door", "Trapdoor4"))])
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 291.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = elapsed() + 0.1
	_hand.park = _plate.global_position
	_hand.beats.append({"at": _plate.global_position, "seconds": 100.0})
	say("guard at the window on %.1f deg; plate at %.1f deg r %.2f y %.2f; squeezes at %.2f s" % [float(option("window", 291.0)),
		LIB.bearing_of(_plate.global_position), LIB.radius_of(_plate.global_position), _plate.global_position.y, float(option("fire", 1.98))])
	if OS.has_environment("STAGE_DEBUG") and controller().rifle != null:
		controller().rifle.target_hit.connect(func(c: Node3D, at: Vector3, _n: Vector3) -> void:
			say("round struck %s at %.1f deg r %.2f y %.2f" % [c.name if c != null else "?", LIB.bearing_of(at), LIB.radius_of(at), at.y]))


## The hand is on the plate: the last of the error and the round's drop go in the squeeze, the hand's own way.
func _squeeze() -> void:
	var rifle: Rifle = controller().rifle
	if rifle == null or not rifle.can_fire():
		say("rifle not ready for the plate")
		return
	var mark: Vector3 = _plate.global_position
	var speed: float = rifle.get_shot_speed()
	if speed > 0.0:
		var flight: float = mark.distance_to(_hand._eye_position()) / speed
		mark.y += 0.5 * float(option("gravity", 22.0)) * flight * flight
	var exact: Vector2 = _hand._angles_to(mark)
	_hand._yaw = exact.x
	_hand._pitch = exact.y
	_hand._apply_head()
	say("squeeze on the plate: %s" % ("fired" if rifle.try_fire() else "refused"))


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.1f y %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position),
		LIB.radius_of(participant.body.global_position), participant.body.global_position.y])
