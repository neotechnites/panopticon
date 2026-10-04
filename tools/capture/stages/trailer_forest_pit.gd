extends "res://tools/capture/stages/stage.gd"

## trailer_forest_pit (v5 9a/9b): three sprint the lane past the pit; the outside man turns in mid-stride and shoves
## the one beside him sideways over the lip; nobody stops, the two left run on. One take, the shover's eyes or the faller's.
## v19 (Ryan): "they shold be running, and get shoved to the side"; "the other players shouldnt just be looking at
## him fall, they should be running."
## Lip trunks r 47.45 at 148.28 and 155.82 (probe: trunk 148-149.2 to r 49.5); the lip 149.6-154.8 is clear, flat to
## r 47, the bank -0.6 at r 46 and near-vertical inside r 45. The KillBox roof is y 0; floor_kill lowers it (shot only).
## Lane (probe --heights, 0.5 deg x 0.25 m): r 50-51.3 clear 137.5-157 (trunks r <= 49.25 at 140-141.5 and 147.5-149,
## r >= 52.5 at 141.5-143.5 and 149.5-150.5); on past the lip, outside the 163.5-165.5 tree (r 48.5-52.25), inside 170.5-172.5 (r 52.5+).
## Dials: pov (shover|victim), at (147.8 deg, where the swing starts), from (11.0 deg back: the run-up), floor_kill (1),
## impulse (16) and up (7): the shipped shove, turn (64 deg right of the lane: the shove's line), swing (0.15 s from the turn to the shove).

const VICTIM_R: float = 50.0
const SHOVER_R: float = 51.2
const THIRD_R: float = 51.3
## The way on past the lip: out round the 164 tree, back in before the 171 one.
const OUT_FROM: float = 155.5
const OUT_R: float = 53.6
const IN_FROM: float = 166.3
const IN_R: float = 51.4
const ON_TO: float = 200.0

var _victim: PlayerController = null
var _shover: PlayerController = null
var _third: PlayerController = null
var _drivers_by_body: Dictionary = {}
var _swing_at: float = -1.0
var _swung: bool = false
var _shoved: bool = false


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
	var from: float = float(option("at", 147.8)) - float(option("from", 11.0))
	_victim = runners[0].controller
	_shover = runners[1].controller
	_third = runners[2].controller
	# The victim: flat out down the inside of the lane, eyes on the course, a stride ahead of the man outside him.
	_drivers_by_body[_victim] = drive(runners[0], [
		{"do": "place", "deg": from, "r": VICTIM_R, "h": 0.1, "face": LIB.tangent_at(from)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 420.0, "gain": 9.0},
		{"do": "lane", "to": ON_TO, "r": VICTIM_R, "speed": 1.0, "weave": 0.03, "period": 1.3, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -3.0}, {"t": 0.7, "right": -7.0, "pitch": 1.0}, {"t": 1.15, "right": 3.0, "pitch": -3.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipPitVictim")
	# The shover: outside him and a stride behind, checking him across his shoulder as they run.
	_drivers_by_body[_shover] = drive(runners[1], [
		{"do": "place", "deg": from - 1.1, "r": SHOVER_R, "h": 0.1, "face": LIB.tangent_at(from - 1.1)},
		{"do": "human", "on": true},
		{"do": "lane", "to": OUT_FROM, "r": SHOVER_R, "speed": 1.0, "weave": 0.03, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 6.0, "pitch": -3.0}, {"t": 0.35, "right": 22.0, "pitch": -5.0}, {"t": 0.75, "right": 8.0, "pitch": -2.0}]},
		{"do": "lane", "to": IN_FROM, "r": OUT_R, "speed": 1.0, "weave": 0.03, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 3.0, "pitch": -3.0}, {"t": 0.3, "right": -9.0, "pitch": -1.0}, {"t": 0.7, "right": 4.0, "pitch": -2.0}]},
		{"do": "lane", "to": ON_TO, "r": IN_R, "speed": 1.0, "weave": 0.03, "period": 1.1, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 6.0, "pitch": -2.0}, {"t": 0.6, "right": -3.0, "pitch": -1.0}]},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipPitShover")
	# The third: a few strides back down the lane; he runs on past the lip like the shover does.
	_drivers_by_body[_third] = drive(runners[2], [
		{"do": "place", "deg": from - 5.4, "r": THIRD_R, "h": 0.1, "face": LIB.tangent_at(from - 5.4)},
		{"do": "human", "on": true},
		{"do": "lane", "to": OUT_FROM, "r": THIRD_R, "speed": 0.97, "weave": 0.05, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.8, "right": -9.0, "pitch": 2.0}, {"t": 1.2, "right": 5.0, "pitch": -1.0}]},
		{"do": "lane", "to": IN_FROM, "r": OUT_R, "speed": 0.97, "weave": 0.05, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": -6.0, "pitch": -2.0}, {"t": 0.5, "right": 3.0, "pitch": -1.0}]},
		{"do": "lane", "to": ON_TO, "r": IN_R, "speed": 0.97, "weave": 0.05, "period": 1.4, "timeout": 9.0,
			"glances": [{"t": 0.0, "right": 5.0, "pitch": -2.0}, {"t": 0.6, "right": -2.0, "pitch": -1.0}]},
		{"do": "hold", "seconds": 60.0},
	], 2, "ClipPitThird")
	for body: PlayerController in [_shover, _third]:
		LIB.hide_from_the_rifle(body)
	victim_body(_victim)
	stage_body(_victim if String(option("pov", "shover")) == "victim" else _shover)
	say("trailer_forest_pit: %s shoves %s off the lip at a run from %.1f deg; %s behind" % [_shover.name, _victim.name, float(option("at", 147.8)), _third.name])
	return true


func tick(_delta: float) -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		var line: String = ""
		for body: PlayerController in [_victim, _shover, _third]:
			line += " %s %.1f/%.2f y%.2f p%.0f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y, rad_to_deg(body.head.rotation.x)]
		say("at" + line)
	# Past the lip trunk: the shover's head whips in on the man beside him, his feet still on the lane.
	if _swing_at < 0.0 and LIB.bearing_of(_shover.global_position) >= float(option("at", 147.8)):
		_swing_at = elapsed()
		var turn: float = float(option("turn", 64.0))
		_drivers_by_body[_shover].glance_now([
			{"t": 0.0, "right": turn, "pitch": -6.0},
			{"t": 0.42, "right": turn * 0.55, "pitch": -15.0},   # a beat on him going over
			{"t": 0.72, "right": 4.0, "pitch": -3.0},            # eyes front, still running
			{"t": 1.5, "right": -6.0, "pitch": -1.0},
		])
	# The swing lands as the turn does.
	if _swing_at >= 0.0 and not _swung and elapsed() >= _swing_at + float(option("swing", 0.15)):
		_swung = true
		_drivers_by_body[_shover].press_shove()


## A glance that turns [param body]'s eyes onto [param point] over [param seconds].
func _glance_onto(body: PlayerController, point: Vector3, seconds: float) -> Dictionary:
	var facing: Vector3 = -body.global_transform.basis.z
	var flat: Vector3 = Vector3(point.x - body.global_position.x, 0.0, point.z - body.global_position.z)
	var eye: Vector3 = body.global_position + Vector3.UP * 1.6
	var up: float = rad_to_deg(atan2(point.y - eye.y, maxf(flat.length(), 0.1)))
	var now: float = rad_to_deg(body.head.rotation.x) if body.head != null else 0.0
	return {"do": "glance", "right": _right_of(facing, flat.normalized()), "pitch": up - now, "seconds": seconds}


static func _head_of(body: PlayerController) -> Vector3:
	return body.global_position + Vector3.UP * 1.55


## Degrees to the body's right that turn [param from] onto [param to] (a positive turn is right).
static func _right_of(from: Vector3, to: Vector3) -> float:
	var yaw_from: float = atan2(-from.x, -from.z)
	var yaw_to: float = atan2(-to.x, -to.z)
	return -rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI))


func on_shove(_from: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	say("shove: %s off the lane at %.1f deg r %.2f" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])
	# The faller: his head comes round to the lip he left and stays on the man who did it, running on along it.
	_drivers_by_body[_victim].retarget([
		{"do": "hold", "seconds": 0.1},
		_glance_onto(_victim, _head_of(_shover) + LIB.tangent_at(LIB.bearing_of(_shover.global_position)) * 2.5, 0.34),
		{"do": "watch", "body": _shover, "seconds": 60.0, "height": 1.3},
	])
	# The third never breaks stride: a look across at the pit and on.
	_drivers_by_body[_third].glance_now([
		{"t": 0.25, "right": 26.0, "pitch": -6.0},
		{"t": 0.7, "right": 3.0, "pitch": -2.0},
	])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s %s" % [participant.body.name, participant.death_cause])


## No third-person lens: every shot of the trailer is a POV.
func lens(_delta: float) -> bool:
	return false
