extends "res://tools/capture/stages/stage.gd"

## marble_sections: proof takes of the four marble blockout sections, down a runner's eyes.
## --map=marble --shot=pack_lead --stage=marble_sections --pov=runner --bots=3 --seconds=10 --set=beat=a|b|c|d
## a: a runner shoves Section A's second activator; the runner ahead on its trapdoor drops.
## b: a runner walks Section B; the tower's rifle hits the wall-top activator ahead; he sees the hit, never the tower.
## c, d: a walk through the buttresses (C) and the column forest (D), hopping in D.

## Section A's second trapdoor and its activator (marble_sections_blockout.py).
const A_START: float = 84.375
const A_ACT: float = 82.975
## Section B: the walk, and the second trapdoor's wall-top activator, the one the rifle hits.
const B_FROM: float = 254.0
const B_STOP: float = 268.5
const SPARE_DEG: float = 330.0

var _beat: String = "a"
var _walker: PlayerController = null
var _guard: PlayerController = null
var _fired: bool = false


func bots() -> int:
	return 3


func needs_pov() -> String:
	return "" if String(option("beat", "a")) == "cwide" else "runner"


## cwide: a fixed wide lens over the void onto Section C's flying buttresses.
func lens(_delta: float) -> bool:
	if _beat != "cwide":
		return false
	camera().global_position = LIB.ring_point(float(option("eye_deg", 200.0)), 38.0, 7.0)
	camera().look_at(LIB.ring_point(float(option("look_deg", 222.0)), 55.0, 6.0), Vector3.UP)
	return true


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0


func before_start() -> void:
	_beat = String(option("beat", "a"))
	LIB.disarm_pads(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var one: PlayerController = runners[0].controller
	var two: PlayerController = runners[1].controller
	var park: Array = [{"do": "place", "at": LIB.ring_point(SPARE_DEG, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}]
	drive(runners[2], park, 2, "spare")
	match _beat:
		"a":
			# The shover by the activator, a step behind the wall's lead-in; the victim ahead walks onto the door.
			drive(runners[0], [
				{"do": "place", "deg": A_ACT - 1.6, "r": 51.0}, {"do": "hold", "seconds": 1.0},
				{"do": "run", "to": LIB.ring_point(A_ACT - 0.3, 51.0, 0.1), "speed": 0.25, "within": 0.3},
				{"do": "until", "t": float(option("shove", 3.2))}, {"do": "shove"}, {"do": "hold", "seconds": 60.0},
			], 0, "shover")
			drive(runners[1], [
				{"do": "place", "deg": A_ACT - 0.6, "r": 54.0}, {"do": "until", "t": 1.6},
				{"do": "run", "to": LIB.ring_point(A_START + 10.0, 54.0, 0.1), "speed": float(option("pace", 0.3)), "timeout": 12.0},
				{"do": "hold", "seconds": 60.0},
			], 1, "victim")
			stage_body(one)
			victim_body(two)
		"b":
			drive(runners[0], [
				{"do": "place", "deg": B_FROM, "r": 53.5}, {"do": "hold", "seconds": 1.0},
				{"do": "run", "to": LIB.ring_point(B_STOP, 53.5, 0.1), "speed": float(option("pace", 0.3)), "timeout": 12.0},
				{"do": "hold", "seconds": 60.0},
			], 0, "walker")
			drive(runners[1], [{"do": "place", "at": LIB.ring_point(SPARE_DEG + 4.0, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}], 1, "spare2")
			stage_body(one)
		"c", "cwide":
			drive(runners[0], [
				{"do": "place", "deg": 192.0, "r": 55.3}, {"do": "hold", "seconds": 0.8},
			] + _arc(192.0, 246.0, 53.0, {"speed": float(option("pace", 0.5))}) + [
				{"do": "hold", "seconds": 60.0},
			], 0, "walker")
			drive(runners[1], [{"do": "place", "at": LIB.ring_point(SPARE_DEG + 4.0, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}], 1, "spare2")
			stage_body(one)
		_:
			drive(runners[0], [
				{"do": "place", "deg": 12.0, "r": 52.0}, {"do": "hold", "seconds": 0.8},
			] + _arc(12.0, 52.0, 52.0, {"speed": float(option("pace", 0.45)), "hop": float(option("hop", 1.1))}) + [
				{"do": "hold", "seconds": 60.0},
			], 0, "walker")
			drive(runners[1], [{"do": "place", "at": LIB.ring_point(SPARE_DEG + 4.0, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}], 1, "spare2")
			stage_body(one)
	_walker = one
	say("marble_sections: beat %s" % _beat)
	return true


## Run steps along the ring at [param r] from [param from] to [param to] degrees, a waypoint every 3 deg.
func _arc(from: float, to: float, r: float, extra: Dictionary) -> Array:
	var out: Array = []
	var deg: float = from + 3.0
	while deg <= to + 0.01:
		var step: Dictionary = {"do": "run", "to": LIB.ring_point(deg, r, 0.1), "within": 1.2, "timeout": 6.0}
		step.merge(extra)
		out.append(step)
		deg += 3.0
	return out


func tick(_delta: float) -> void:
	if _walker != null and elapsed() > 0.0 and int(elapsed() * 2.0) != int((elapsed() - _delta) * 2.0):
		say("walker at %.2f deg r %.2f y %.2f" % [LIB.bearing_of(_walker.global_position), LIB.radius_of(_walker.global_position), _walker.global_position.y])
	if _beat != "b" or _fired or elapsed() < float(option("fire", 3.5)):
		return
	if _guard == null:
		var shooter: TowerShooter = LIB.stand_down(seat())
		if shooter == null or shooter.controller == null:
			return
		_guard = shooter.controller
		LIB.guard_to_window(_guard, 271.0)
		return
	var section: Node = LIB.find_node(clip.root, "SectionB")
	var door: TrapDoor = section.get_node_or_null(^"Trapdoor2") as TrapDoor if section != null else null
	var plate: Node3D = door.find_child("PlateHitbox", true, false) as Node3D if door != null else null
	var rifle: Rifle = controller().rifle
	if plate == null or rifle == null or not rifle.can_fire():
		return
	var eye: Node3D = _guard.get_node_or_null(^"Head/Camera") as Node3D
	var d: Vector3 = plate.global_position - eye.global_position
	_guard.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	_guard.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	_guard.set(&"_pitch", _guard.head.rotation.x)
	rifle.rules = null   # a scoped shot: no hip spread, the round goes down the aim line
	_fired = rifle.try_fire()
	say("plate at %s (%.2f deg r %.2f), eye at %s" % [plate.global_position, LIB.bearing_of(plate.global_position), LIB.radius_of(plate.global_position), eye.global_position])
	say("rifle at the wall-top activator: %s" % ("fired" if _fired else "refused"))


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "?"))


func on_out(participant: MatchParticipant) -> void:
	if participant != null and participant.body != null:
		say("out: %s at %.1f deg r %.1f y %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position), participant.body.global_position.y])
