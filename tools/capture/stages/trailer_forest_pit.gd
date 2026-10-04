extends "res://tools/capture/stages/stage.gd"

## trailer_forest_pit (9a/9b): three sprint the lane; the outside man comes up on the inside man's shoulder, turns
## onto him and shoves him sideways through the gap in the lip trees. One take, the shover's eyes or the faller's.
# Ryan v19: "they shold be running, and get shoved to the side"; "the other players shouldnt just be looking at
# him fall, they should be running." v20: "the shove doesnt read right ... tht its two shots of the same event."
# Probe (--heights 0.5 deg x 0.25 m): lane trees 134-135.5 (r 49-50.75) and 135-136 (r 54.25+), so the run-up
# threads r 51-54 there; lip trees 147.5-149.5 and 155-156.5 (to r 49.75), the lip between them flat to r 46.75.
# Dials: pov (shover|victim), from (124.3), back (2.2 deg), pace (0.93), turn_at (144.0), at (148.9),
# follow (0.55 s), flinch (1.6 deg before the shove), on_him (0.3 s), lip (152.2 deg), floor_kill (1), impulse (16) and up (7): the shipped shove.

const VICTIM_R: float = 50.0
const SHOVER_R: float = 51.0
const THIRD_R: float = 51.4
const GATE: float = 136.5
const VICTIM_GATE_R: float = 51.6
const SHOVER_GATE_R: float = 52.5
const THIRD_GATE_R: float = 52.1
# The way on past the lip: out round the 164 tree, back in before the 171 one.
const OUT_FROM: float = 155.5
const OUT_R: float = 53.6
const IN_FROM: float = 166.3
const IN_R: float = 51.4
const ON_TO: float = 200.0

var _victim: PlayerController = null
var _shover: PlayerController = null
var _third: PlayerController = null
var _drivers_by_body: Dictionary = {}
var _turned_in: bool = false
var _swung: bool = false
var _flinched: bool = false
var _shoved_at: float = -1.0
var _eyes_front: bool = false
var _lip: Node3D = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 16.0))
	rules.shove_up_impulse = float(option("up", 7.0))
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	if int(option("floor_kill", 1)) == 1:
		# The ravine kills at y 0, six metres over the mist; for this shot it kills at the floor (y -11.05).
		var box: Node3D = LIB.find_node(clip.root, "KillBox") as Node3D
		if box != null:
			box.position.y -= 10.9


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var from: float = float(option("from", 124.3))
	var back: float = float(option("back", 2.2))
	var pace: float = float(option("pace", 0.93))
	_victim = runners[0].controller
	_shover = runners[1].controller
	_third = runners[2].controller
	# The victim: down the inside of the lane, eyes on the course, a little off the pace.
	_drivers_by_body[_victim] = drive(runners[0], [
		{"do": "place", "deg": from, "r": VICTIM_GATE_R, "h": 0.1, "face": LIB.tangent_at(from)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 420.0, "gain": 9.0},
		{"do": "lane", "to": GATE, "r": VICTIM_GATE_R, "speed": pace, "weave": 0.02, "period": 1.3, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -3.0}]},
		{"do": "lane", "to": ON_TO, "r": VICTIM_R, "speed": pace, "weave": 0.02, "period": 1.3, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 2.0, "pitch": -3.0}, {"t": 0.5, "right": -6.0, "pitch": 1.0}, {"t": 0.95, "right": 3.0, "pitch": -3.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipPitVictim")
	# The shover: outside him and behind, flat out, closing on his shoulder with a check on him as he comes.
	_drivers_by_body[_shover] = drive(runners[1], [
		{"do": "place", "deg": from - back, "r": SHOVER_GATE_R, "h": 0.1, "face": LIB.tangent_at(from - back)},
		{"do": "human", "on": true},
		{"do": "lane", "to": GATE, "r": SHOVER_GATE_R, "speed": 1.0, "weave": 0.02, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 5.0, "pitch": -3.0}, {"t": 0.5, "right": 13.0, "pitch": -4.0}, {"t": 0.9, "right": 3.0, "pitch": -2.0}]},
		{"do": "lane", "to": OUT_FROM, "r": SHOVER_R, "speed": 1.0, "weave": 0.02, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 8.0, "pitch": -4.0}, {"t": 0.25, "right": 19.0, "pitch": -6.0}, {"t": 0.5, "right": 6.0, "pitch": -3.0}]},
		{"do": "lane", "to": IN_FROM, "r": OUT_R, "speed": 1.0, "weave": 0.03, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 3.0, "pitch": -3.0}, {"t": 0.3, "right": -9.0, "pitch": -1.0}, {"t": 0.7, "right": 4.0, "pitch": -2.0}]},
		{"do": "lane", "to": ON_TO, "r": IN_R, "speed": 1.0, "weave": 0.03, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 6.0, "pitch": -2.0}, {"t": 0.6, "right": -3.0, "pitch": -1.0}]},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipPitShover")
	# The third: three metres behind the shover; he runs on past the lip like the shover does.
	var third_from: float = from - back - 3.3
	_drivers_by_body[_third] = drive(runners[2], [
		{"do": "place", "deg": third_from, "r": THIRD_GATE_R, "h": 0.1, "face": LIB.tangent_at(third_from)},
		{"do": "human", "on": true},
		{"do": "lane", "to": GATE, "r": THIRD_GATE_R, "speed": 1.0, "weave": 0.03, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}]},
		{"do": "lane", "to": OUT_FROM, "r": THIRD_R, "speed": 1.0, "weave": 0.04, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.6, "right": -8.0, "pitch": 2.0}, {"t": 1.0, "right": 5.0, "pitch": -1.0}]},
		{"do": "lane", "to": IN_FROM, "r": OUT_R, "speed": 1.0, "weave": 0.05, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": -6.0, "pitch": -2.0}, {"t": 0.5, "right": 3.0, "pitch": -1.0}]},
		{"do": "lane", "to": ON_TO, "r": IN_R, "speed": 1.0, "weave": 0.05, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 5.0, "pitch": -2.0}, {"t": 0.6, "right": -2.0, "pitch": -1.0}]},
		{"do": "hold", "seconds": 60.0},
	], 2, "ClipPitThird")
	for body: PlayerController in [_shover, _third]:
		LIB.hide_from_the_rifle(body)
	# The lip he goes over, between its two trees: where the faller's eyes stay.
	_lip = Node3D.new()
	_lip.name = "ClipPitLip"
	clip.root.add_child(_lip)
	_lip.global_position = LIB.ring_point(float(option("lip", 152.2)), 50.8, 0.0)
	victim_body(_victim)
	stage_body(_victim if String(option("pov", "shover")) == "victim" else _shover)
	say("trailer_forest_pit: %s shoves %s off the lip at a run at %.1f deg; %s behind" % [_shover.name, _victim.name, float(option("at", 148.9)), _third.name])
	return true


func tick(_delta: float) -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	var at: float = LIB.bearing_of(_shover.global_position)
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 3 == 0:
		var line: String = " gap %.2f aim %.0f yaw %.0f" % [_ahead_of_shover(), _aim_at_victim().x, _right_of(_lane_of_shover(), -_shover.global_transform.basis.z)]
		for body: PlayerController in [_victim, _shover, _third]:
			line += " %s %.1f/%.2f y%.2f p%.0f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y, rad_to_deg(body.head.rotation.x)]
		say("at" + line)
	if not _turned_in and at >= float(option("turn_at", 144.0)):
		_turned_in = true
	if not _turned_in or _eyes_front:
		pass
	elif _shoved_at >= 0.0 and elapsed() >= _shoved_at + float(option("follow", 0.55)):
		# Eyes front: he never broke stride.
		_eyes_front = true
		_drivers_by_body[_shover].glance_now([
			{"t": 0.0, "right": 5.0, "pitch": -3.0},
			{"t": 0.7, "right": -6.0, "pitch": -1.0},
		])
	else:
		# His head is on the man beside him from the turn until he has gone over, his feet still on the lane.
		var aim: Vector2 = _aim_at_victim()
		var pitch: float = -11.0 if _shoved_at < 0.0 else clampf(aim.y - 5.0, -24.0, 6.0)
		_drivers_by_body[_shover].glance_now([{"t": 0.0, "right": minf(aim.x, 88.0), "pitch": pitch}])
	# The man beside him sees it coming a stride too late: his head snaps round onto the shover, his feet still running.
	if _turned_in and not _flinched and at >= float(option("at", 148.9)) - float(option("flinch", 1.6)):
		_flinched = true
		var back: Vector3 = _shover.global_position - _victim.global_position
		back.y = 0.0
		_drivers_by_body[_victim].glance_now([{"t": 0.0, "right": _right_of(_lane_of(_victim, VICTIM_R), back.normalized()), "pitch": -4.0}])
	# The swing lands as they clear the lip tree, his eyes already on him.
	if _turned_in and not _swung and at >= float(option("at", 148.9)):
		_swung = true
		_drivers_by_body[_shover].press_shove()


## A body's lane heading at radius [param r], as its lane step steers it.
static func _lane_of(body: PlayerController, r: float) -> Vector3:
	var ahead: Vector3 = LIB.ring_point(LIB.bearing_of(body.global_position) + 5.0, r, 0.0)
	return Vector3(ahead.x - body.global_position.x, 0.0, ahead.z - body.global_position.z).normalized()


func _lane_of_shover() -> Vector3:
	return _lane_of(_shover, SHOVER_R)


## Degrees right of the shover's lane and degrees up to the victim's chest.
func _aim_at_victim() -> Vector2:
	var to: Vector3 = _victim.global_position + Vector3.UP * 1.1 - (_shover.global_position + Vector3.UP * 1.6)
	var flat: Vector3 = Vector3(to.x, 0.0, to.z)
	return Vector2(_right_of(_lane_of_shover(), flat.normalized()), rad_to_deg(atan2(to.y, maxf(flat.length(), 0.1))))


## Metres the victim is ahead of the shover along the lane.
func _ahead_of_shover() -> float:
	return (_victim.global_position - _shover.global_position).dot(_lane_of_shover())


## Degrees to the body's right that turn [param from] onto [param to] (a positive turn is right).
static func _right_of(from: Vector3, to: Vector3) -> float:
	var yaw_from: float = atan2(-from.x, -from.z)
	var yaw_to: float = atan2(-to.x, -to.z)
	return -rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI))


func on_shove(_from: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved_at >= 0.0 or victim.body != _victim:
		return
	_shoved_at = elapsed()
	say("shove: %s off the lane at %.1f deg r %.2f, %.2f m from %s" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.distance_to(_shover.global_position), _shover.name])
	# The faller: his eyes are on the man who did it, arms still out; then they stay on the lip he left, and the
	# two left run through them and on.
	_drivers_by_body[_victim].retarget([
		{"do": "watch", "body": _shover, "seconds": float(option("on_him", 0.3)), "height": 1.3},
		{"do": "watch", "body": _lip, "seconds": 60.0, "height": 1.2},
	])
	# The third never breaks stride: a look across at the pit and on.
	_drivers_by_body[_third].glance_now([
		{"t": 0.25, "right": 14.0, "pitch": -4.0},
		{"t": 0.7, "right": 3.0, "pitch": -2.0},
	])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s %s" % [participant.body.name, participant.death_cause])


## No third-person lens: every shot of the trailer is a POV.
func lens(_delta: float) -> bool:
	return false
