extends "res://tools/capture/stages/stage.gd"

## trailer_forest_pit (v5 9a/9b): two run the lane side by side and cut in to the lip; the one inside stops on the
## edge and turns to the man coming up beside him, who shoves him backwards into the pit; a third pulls up behind.
## One take, the shover's eyes (pov=shover) or the faller's (pov=victim): he sees the shover on the lip as he falls.
## Lip trunks r 47.45 at 148.28 and 155.82 (probe: trunk 148-149.2 to r 49.5); the lip 149.6-154.8 is clear, flat to
## r 47, the bank -0.6 at r 46 and near-vertical inside r 45. The KillBox roof is y 0; floor_kill lowers it (shot only).
## Dials: pov (shover|victim), at (152.0 deg, the lip he stops on), floor_kill (1), impulse (8), up (2),
## turn_t (clip s the victim turns to the shover, 2.30), shove_t (clip s, 2.75), down_after (s, 0.8: his look down).

## Run targets: each body carries on ~1 m past where its run lets go, onto 153.4/46.8 and ~153/48.2.
const LIP_R: float = 47.9
const SHOVER_R: float = 49.0

var _victim: PlayerController = null
var _shover: PlayerController = null
var _third: PlayerController = null
var _drivers_by_body: Dictionary = {}
var _looked: bool = false
var _swung: bool = false
var _shoved: bool = false
var _shoved_at: float = 0.0
var _looked_down: bool = false


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 8.0))
	rules.shove_up_impulse = float(option("up", 2.0))
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
	var at: float = float(option("at", 152.0))
	_victim = runners[0].controller
	_shover = runners[1].controller
	_third = runners[2].controller
	# The victim: level with him and a stride inside, down the lane past the trunk, in to the lip, a look down over it.
	_drivers_by_body[_victim] = drive(runners[0], [
		{"do": "place", "deg": at - 9.8, "r": 50.1, "h": 0.1, "face": LIB.tangent_at(at - 9.8)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 300.0, "gain": 9.0},
		{"do": "lane", "to": at - 0.9, "r": 50.1, "speed": 0.86, "weave": 0.04, "period": 1.3, "timeout": 4.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -3.0}, {"t": 0.6, "right": 14.0, "pitch": 4.0}, {"t": 0.95, "right": 3.0, "pitch": -2.0}]},
		{"do": "run", "to": LIB.ring_point(at + 1.0, LIP_R), "within": 0.3, "speed": 0.55, "timeout": 3.0},
		{"do": "hold", "seconds": 0.15},
		{"do": "glance", "right": 8.0, "pitch": -24.0, "seconds": 0.35},
		{"do": "hold", "seconds": 60.0, "fidget": false},
	], 0, "ClipPitVictim")
	# The shover: beside him and outside the whole way, his head turned to keep him in view.
	_drivers_by_body[_shover] = drive(runners[1], [
		{"do": "place", "deg": at - 10.4, "r": 51.3, "h": 0.1, "face": LIB.tangent_at(at - 10.4)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 320.0, "gain": 10.0},
		{"do": "lane", "to": at - 1.4, "r": 51.2, "speed": 0.9, "weave": 0.03, "period": 1.1, "timeout": 5.0,
			"glances": [{"t": 0.0, "right": 34.0, "pitch": -6.0}, {"t": 0.45, "right": 26.0, "pitch": -5.0}, {"t": 0.8, "right": 38.0, "pitch": -7.0}]},
		{"do": "run", "to": LIB.ring_point(at + 0.9, SHOVER_R), "within": 0.3, "speed": 0.55, "timeout": 2.5},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipPitShover")
	# The third: further back on the lane; he pulls up behind the shover as it happens.
	_drivers_by_body[_third] = drive(runners[2], [
		{"do": "place", "deg": at - 13.2, "r": 50.6, "h": 0.1, "face": LIB.tangent_at(at - 13.2)},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.1},
		{"do": "steer", "on": true, "rate": 280.0, "gain": 8.0},
		{"do": "lane", "to": at - 2.4, "r": 50.6, "speed": 0.85, "weave": 0.06, "period": 1.4, "timeout": 5.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.8, "right": -12.0, "pitch": 3.0}, {"t": 1.2, "right": 6.0, "pitch": -1.0}]},
		{"do": "run", "to": LIB.ring_point(at - 1.4, 50.7), "within": 0.4, "speed": 0.45, "timeout": 2.0},
		{"do": "hold", "seconds": 60.0},
	], 2, "ClipPitThird")
	for body: PlayerController in [_shover, _third]:
		LIB.hide_from_the_rifle(body)
	victim_body(_victim)
	stage_body(_victim if String(option("pov", "shover")) == "victim" else _shover)
	say("trailer_forest_pit: %s shoves %s off the lip at %.1f deg; %s behind" % [_shover.name, _victim.name, at, _third.name])
	return true


func tick(_delta: float) -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		var line: String = ""
		for body: PlayerController in [_victim, _shover, _third]:
			line += " %s %.1f/%.2f y%.2f p%.0f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y, rad_to_deg(body.head.rotation.x)]
		if _shoved:
			var ray := PhysicsRayQueryParameters3D.create(_victim.global_position + Vector3.UP * 1.6, _head_of(_shover), 1)
			var hit: Dictionary = _victim.get_world_3d().direct_space_state.intersect_ray(ray)
			line += " sees %s" % ("shover" if hit.is_empty() else str(hit.get("collider")))
		say("at" + line)
	# The victim hears him and turns round on the edge to face him: his back to the drop.
	if not _looked and elapsed() >= float(option("turn_t", 2.30)):
		_looked = true
		_drivers_by_body[_victim].retarget([
			_glance_onto(_victim, _head_of(_shover), 0.42),
			{"do": "hold", "seconds": 60.0, "look_at": _head_of(_shover)},
		])
	# The shover squares to him and shoves.
	if not _swung and elapsed() >= float(option("shove_t", 2.75)) - 0.24:
		_swung = true
		_drivers_by_body[_shover].retarget([
			_glance_onto(_shover, _chest_of(_victim), 0.2),
			{"do": "shove", "victim": _victim},
			{"do": "hold", "seconds": 0.12},
		])
	# The lip is gone behind the bank (~0.75 s down): the faller snaps his eyes down at the mist coming up.
	if _shoved and not _looked_down and elapsed() >= _shoved_at + float(option("down_after", 0.8)):
		_looked_down = true
		_drivers_by_body[_victim].retarget([
			{"do": "steer", "on": true, "rate": 300.0, "gain": 9.0, "pitch_rate": 420.0, "pitch_gain": 11.0},
			{"do": "hold", "seconds": 60.0, "look_down": 38.0},
		])
	# After the swing his eyes follow the man going over, down to where a player looks.
	if _shoved and Engine.get_physics_frames() % 3 == 0 and _drivers_by_body[_shover].is_done():
		_drivers_by_body[_shover].retarget([{"do": "hold", "seconds": 0.05, "look_at": _chest_of(_victim)}])


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


static func _chest_of(body: PlayerController) -> Vector3:
	return body.global_position + Vector3.UP * 1.1


## Degrees to the body's right that turn [param from] onto [param to] (a positive turn is right).
static func _right_of(from: Vector3, to: Vector3) -> float:
	var yaw_from: float = atan2(-from.x, -from.z)
	var yaw_to: float = atan2(-to.x, -to.z)
	return -rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI))


func on_shove(_from: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	_shoved_at = elapsed()
	say("shove: %s over the lip at %.1f deg r %.2f" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])
	# The faller: eyes on the man who did it, up at the lip as it pulls away.
	_drivers_by_body[_victim].retarget([
		{"do": "hold", "seconds": 60.0, "look_at": _head_of(_shover)},
	])
	# The third pulls up, eyes on him going over.
	_drivers_by_body[_third].retarget([
		{"do": "hold", "seconds": 0.08},
		_glance_onto(_third, LIB.ring_point(float(option("at", 152.0)), 44.0, -2.0), 0.4),
		{"do": "hold", "seconds": 60.0},
	])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s %s" % [participant.body.name, participant.death_cause])


## No third-person lens: every shot of the trailer is a POV.
func lens(_delta: float) -> bool:
	return false
