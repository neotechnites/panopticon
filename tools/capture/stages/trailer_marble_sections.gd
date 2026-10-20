extends "res://tools/capture/stages/stage.gd"

## trailer_marble_sections: the trailer's marble slots (v69) re-staged onto the four sections, same lenses as the shots they
## replace (guard scope with the guard hand, runner POV). --set=beat=bscope|bfar|ashove|ascope; every beat lands on its slot's
## beat time (fire / shove dials), so the edit keeps the old take frames.
## bscope (5hr's slot): the scope eases onto B's wall-top activator and hits it (fire 2.967).
## bfar (23's slot): a runner walking B sees the rifle hit two activators ahead; the floor drops under the two runners there.
## ashove (10ar's slot): the POV runner shoves A's activator; the runner ahead on the trapdoor drops (shove 3.033).
## ascope (10br's slot): the scope tracks a runner out of A's cover into the open gap and hits him (fire 4.983).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const SPARE_DEG: float = 330.0

var _beat: String = ""
var _bodies: Array[PlayerController] = []
var _guard: PlayerController = null
var _hand: Node = null
var _plates: Array[Node3D] = []
## Clip seconds each plate round is squeezed (its flight lands it on the slot's beat).
var _fire_times: Array[float] = []
var _fired: int = 0


func bots() -> int:
	return 3


func needs_pov() -> String:
	var beat: String = String(option("beat", "bscope"))
	return "guard" if beat == "bscope" or beat == "ascope" else "runner"


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"marble"
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 0.8
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	_beat = String(option("beat", "bscope"))
	LIB.disarm_pads(clip.root)


## A trapdoor of a section, by name.
func _door(section: String, door: String) -> TrapDoor:
	var node: Node = LIB.find_node(clip.root, section)
	return node.get_node_or_null(NodePath(door)) as TrapDoor if node != null else null


## The plate hitbox of a door (the rifle's mark).
func _plate(door: TrapDoor) -> Node3D:
	return door.find_child("PlateHitbox", true, false) as Node3D


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
		_bodies.append(brain.controller)
	var park: Array = [{"do": "place", "at": LIB.ring_point(SPARE_DEG, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}]
	match _beat:
		"bscope":
			drive(runners[0], [{"do": "place", "deg": 273.0, "r": 54.0}, {"do": "human", "on": true},
				{"do": "run", "to": LIB.ring_point(279.0, 54.0, 0.1), "speed": 0.2, "timeout": 12.0}, {"do": "hold", "seconds": 60.0}], 0)
			drive(runners[1], park, 1)
			drive(runners[2], [{"do": "place", "at": LIB.ring_point(SPARE_DEG + 4.0, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}], 2)
			stage_body(_bodies[0])
		"bfar":
			drive(runners[0], [{"do": "place", "deg": 262.0, "r": 53.0}, {"do": "human", "on": true}, {"do": "hold", "seconds": 0.2},
				{"do": "run", "to": LIB.ring_point(279.5, 53.0, 0.1), "speed": float(option("pace", 0.3)), "timeout": 12.0},
				{"do": "hold", "seconds": 60.0}], 0)
			drive(runners[1], [{"do": "place", "deg": 285.0, "r": 54.0}, {"do": "human", "on": true},
				{"do": "run", "to": LIB.ring_point(292.0, 54.0, 0.1), "speed": 0.15, "timeout": 12.0}, {"do": "hold", "seconds": 60.0}], 1)
			drive(runners[2], [{"do": "place", "deg": 295.0, "r": 55.0}, {"do": "human", "on": true},
				{"do": "run", "to": LIB.ring_point(303.0, 55.0, 0.1), "speed": 0.15, "timeout": 12.0}, {"do": "hold", "seconds": 60.0}], 2)
			stage_body(_bodies[0])
		"ashove":
			drive(runners[0], [{"do": "place", "deg": 81.4, "r": 51.0}, {"do": "human", "on": true}, {"do": "hold", "seconds": 1.0},
				{"do": "run", "to": LIB.ring_point(82.7, 51.0, 0.1), "speed": 0.25, "within": 0.3},
				{"do": "until", "t": float(option("shove", 3.033))}, {"do": "shove"}, {"do": "hold", "seconds": 60.0}], 0)
			drive(runners[1], [{"do": "place", "deg": 82.4, "r": 54.0}, {"do": "human", "on": true}, {"do": "until", "t": 1.5},
				{"do": "run", "to": LIB.ring_point(95.0, 54.0, 0.1), "speed": float(option("pace", 0.3)), "timeout": 12.0},
				{"do": "hold", "seconds": 60.0}], 1)
			drive(runners[2], park, 2)
			stage_body(_bodies[0])
			victim_body(_bodies[1])
		"ascope":
			drive(runners[0], [{"do": "place", "deg": float(option("from", 69.5)), "r": 53.0}, {"do": "human", "on": true},
				{"do": "until", "t": float(option("go", 3.3))},
				{"do": "run", "to": LIB.ring_point(84.0, 53.0, 0.1), "speed": float(option("pace", 0.45)), "timeout": 12.0},
				{"do": "hold", "seconds": 60.0}], 0)
			drive(runners[1], park, 1)
			drive(runners[2], [{"do": "place", "at": LIB.ring_point(SPARE_DEG + 4.0, 52.0, 0.1)}, {"do": "hold", "seconds": 90.0}], 2)
			stage_body(_bodies[0])
			victim_body(_bodies[0])
	say("trailer_marble_sections: beat %s" % _beat)
	return true


func tick(_delta: float) -> void:
	if _bodies.is_empty() or _beat == "ashove":
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 12 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y]
		say("at" + line)
	if _hand == null:
		_raise_the_hand()
		return
	_hand.hold_scope = _beat == "bfar" or elapsed() >= float(option("zoom", 0.8))
	if _fired < _fire_times.size() and elapsed() >= _fire_times[_fired]:
		_squeeze(_plates[_fired])
		_fired += 1


## The hand is on the plate: the last of the error and the round's drop go in the squeeze, the hand's own way.
func _squeeze(plate: Node3D) -> void:
	var rifle: Rifle = controller().rifle
	if rifle == null or not rifle.can_fire():
		say("rifle not ready for %s" % plate.get_parent().get_parent().name)
		return
	var mark: Vector3 = plate.global_position
	var speed: float = rifle.get_shot_speed()
	if speed > 0.0:
		var flight: float = mark.distance_to(_hand._eye_position()) / speed
		mark.y += 0.5 * float(option("gravity", 22.0)) * flight * flight
	var exact: Vector2 = _hand._angles_to(mark)
	_hand._yaw = exact.x
	_hand._pitch = exact.y
	_hand._apply_head()
	say("squeeze on the plate: %s" % ("fired" if rifle.try_fire() else "refused"))


## The guard at the window, the hand on the mouse: the same rig as trailer_marble_track.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	var window: float = {"bscope": 271.0, "bfar": 288.0, "ascope": 78.0}.get(_beat, 0.0)
	LIB.guard_to_window(_guard, float(option("window", window)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = elapsed() + 0.1
	match _beat:
		"bscope":
			_plates = [_plate(_door("SectionB", "Trapdoor2"))]
			_fire_times = [float(option("fire", 2.6))]
			_hand.park = LIB.ring_point(float(option("park", 264.0)), 52.0, 1.0)
			_hand.beats.append({"at": _plates[0].global_position, "seconds": 100.0})
		"bfar":
			_plates = [_plate(_door("SectionB", "Trapdoor3")), _plate(_door("SectionB", "Trapdoor4"))]
			_fire_times = [float(option("fire", 1.95)), float(option("fire2", 3.0))]
			_hand.park = _plates[0].global_position
			_hand.beats.append({"at": _plates[0].global_position, "seconds": _fire_times[0] + 0.2 - _hand.start_at})
			_hand.beats.append({"at": _plates[1].global_position, "seconds": 100.0})
		"ascope":
			_hand.park = LIB.ring_point(float(option("park", 72.0)), 52.0, 1.0)
			_hand.beats.append({"body": _bodies[0], "seconds": 100.0, "watch": true,
				"fire_at": float(option("fire", 4.59)) - _hand.start_at, "lead": float(option("lead", 1.0))})
	if OS.has_environment("STAGE_DEBUG") and controller().rifle != null:
		controller().rifle.target_hit.connect(func(c: Node3D, at: Vector3, _n: Vector3) -> void:
			say("round struck %s at %.1f deg r %.2f y %.2f" % [c.name if c != null else "?", LIB.bearing_of(at), LIB.radius_of(at), at.y]))


func on_out(participant: MatchParticipant) -> void:
	if participant != null and participant.body != null:
		say("out: %s at %.1f deg r %.1f y %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position),
			LIB.radius_of(participant.body.global_position), participant.body.global_position.y])
