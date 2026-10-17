extends "res://tools/capture/stages/stage.gd"

## rs_pitshove: trailer_forest_pit on the hell rim. A pack runs the open rim (28-50 deg); the POV closes on
## the man on the inside, turns onto him and shoves him sideways over the rim into the pit, eyes after him, runs on.
# The rim is walled (r 47-47.3, +2.4 m) from 62 round to 210 and 0-12 deg; 14-60 is open, the deck flat to r 46.5.
# Ryan: "on 'shove someone' the POV runner shoves a runner in front of them off into the pit -- exactly like the
# forest shot in trailer v35, but in hell". Probe --floor: rocks at 36 r53, 48 r51.5-52, 52-54 r50.5, 58 r53.
# He is ahead in the narrow portrait frame from the start: 4 m up the lane, 0.7 m inside, run down at pace 0.8.
# Dials: from (31), back (4.6 deg), pace (0.8), turn_gap (1.9 m), flinch_gap (1.6), shove_gap (0.45: beside him, so the throw is across the pit), follow (1.1 s),
# victim_r (48.9), shover_r (49.6), exposure (2.2; 0 keeps the map's), ahead (1: two more runners up the lane), impulse (16) and up (7): the shipped shove,
# pack (4: runners on the ring; 3 keeps a short's 4-player cap with one runner ahead).

const ON_TO: float = 70.0

var _victim: PlayerController = null
var _shover: PlayerController = null
var _drivers_by_body: Dictionary = {}
var _turned_in: bool = false
var _swung: bool = false
var _flinched: bool = false
var _shoved_at: float = -1.0
var _eyes_front: bool = false


func bots() -> int:
	return int(option("pack", 4))


func needs_pov() -> String:
	return "runner"


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 16.0))
	rules.shove_up_impulse = float(option("up", 7.0))
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	var exposure: float = float(option("exposure", 2.2))
	var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
	if exposure > 0.0 and world != null and world.environment != null:
		var env: Environment = world.environment.duplicate() as Environment
		env.tonemap_exposure = exposure
		world.environment = env


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var from: float = float(option("from", 31.0))
	var back: float = float(option("back", 4.6))
	var pace: float = float(option("pace", 0.8))
	var victim_r: float = float(option("victim_r", 48.9))
	var shover_r: float = float(option("shover_r", 49.6))
	_victim = runners[0].controller
	_shover = runners[1].controller
	_drivers_by_body[_victim] = drive(runners[0], [
		{"do": "place", "deg": from, "r": victim_r, "h": 0.1, "face": LIB.tangent_at(from)},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 420.0, "gain": 9.0},
		{"do": "lane", "to": ON_TO, "r": victim_r, "speed": pace, "weave": 0.02, "period": 1.3, "timeout": 12.0,
			"glances": [{"t": 0.0, "right": 2.0, "pitch": -3.0}, {"t": 0.6, "right": -6.0, "pitch": 1.0}, {"t": 1.1, "right": 3.0, "pitch": -3.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipPitVictim")
	_drivers_by_body[_shover] = drive(runners[1], [
		{"do": "place", "deg": from - back, "r": shover_r, "h": 0.1, "face": LIB.tangent_at(from - back)},
		{"do": "human", "on": true},
		{"do": "lane", "to": ON_TO, "r": shover_r, "speed": 1.0, "weave": 0.02, "period": 1.1, "timeout": 12.0,
			"glances": [{"t": 0.0, "right": 4.0, "pitch": -3.0}, {"t": 0.5, "right": -5.0, "pitch": -4.0}, {"t": 1.0, "right": 3.0, "pitch": -2.0}]},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipPitShover")
	# Two more up the lane in his eyeline (inside the 48-54 deg rocks), the race he is in: they run on.
	for i: int in range(2, runners.size()):
		var lead: float = from + (6.0 if i == 2 else 10.0)
		var r: float = 49.4 if i == 2 else 48.3
		if int(option("ahead", 1)) == 0:
			lead = 320.0
		_drivers_by_body[runners[i].controller] = drive(runners[i], [
			{"do": "place", "deg": lead, "r": r, "h": 0.1, "face": LIB.tangent_at(lead)},
			{"do": "human", "on": true},
			{"do": "lane", "to": ON_TO + 40.0, "r": r, "speed": 0.97, "weave": 0.04, "period": 1.3 + 0.2 * i, "timeout": 14.0,
				"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}]},
			{"do": "hold", "seconds": 60.0},
		], i, "ClipPitAhead%d" % i)
	victim_body(_victim)
	stage_body(_shover)
	say("rs_pitshove: %s runs %s down and shoves him into the pit" % [_shover.name, _victim.name])
	return true


func tick(_delta: float) -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	var at: float = LIB.bearing_of(_shover.global_position)
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		var ahead: String = ""
		for d: Node in drivers.slice(2):
			var b: PlayerController = d.get(&"_body") as PlayerController
			if b != null:
				ahead += " %s %.1f/%.2f" % [b.name, LIB.bearing_of(b.global_position), LIB.radius_of(b.global_position)]
		say("ahead" + ahead)
		say("at %.1f gap %.2f | victim %.1f/%.2f y%.2f | shover r %.2f" % [at, _ahead_of_shover(), LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.y, LIB.radius_of(_shover.global_position)])
	# Placed at 0.6 s: until they are running, the gap is the spawn's.
	if elapsed() < 1.0:
		return
	var gap: float = _ahead_of_shover()
	if not _turned_in and gap <= float(option("turn_gap", 1.9)):
		_turned_in = true
	if not _turned_in or _eyes_front:
		pass
	elif _shoved_at >= 0.0 and elapsed() >= _shoved_at + float(option("follow", 1.1)):
		_eyes_front = true
		_drivers_by_body[_shover].glance_now([
			{"t": 0.0, "right": 5.0, "pitch": -3.0},
			{"t": 0.7, "right": -4.0, "pitch": -1.0},
		])
	else:
		var aim: Vector2 = _aim_at_victim()
		var pitch: float = -11.0 if _shoved_at < 0.0 else clampf(aim.y - 5.0, -60.0, 6.0)
		_drivers_by_body[_shover].glance_now([{"t": 0.0, "right": clampf(aim.x, -88.0, 88.0), "pitch": pitch}])
	if _turned_in and not _flinched and gap <= float(option("flinch_gap", 1.6)):
		_flinched = true
		var away: Vector3 = _shover.global_position - _victim.global_position
		away.y = 0.0
		_drivers_by_body[_victim].glance_now([{"t": 0.0, "right": _right_of(_lane_of(_victim), away.normalized()), "pitch": -4.0}])
	if _turned_in and not _swung and gap <= float(option("shove_gap", 0.45)):
		_swung = true
		_drivers_by_body[_shover].press_shove()
		say("swing: gap %.2f, %.2f m, facing %.0f deg off the lane, aim %.0f" % [gap, _victim.global_position.distance_to(_shover.global_position), _right_of(_lane_of(_shover), -_shover.global_transform.basis.z), _aim_at_victim().x])


## A body's lane heading, as its lane step steers it (increasing bearing).
static func _lane_of(body: PlayerController) -> Vector3:
	var ahead: Vector3 = LIB.ring_point(LIB.bearing_of(body.global_position) + 5.0, LIB.radius_of(body.global_position), 0.0)
	return Vector3(ahead.x - body.global_position.x, 0.0, ahead.z - body.global_position.z).normalized()


## Degrees right of the shover's lane and degrees up to the victim's chest.
func _aim_at_victim() -> Vector2:
	var to: Vector3 = _victim.global_position + Vector3.UP * 1.1 - (_shover.global_position + Vector3.UP * 1.6)
	var flat: Vector3 = Vector3(to.x, 0.0, to.z)
	return Vector2(_right_of(_lane_of(_shover), flat.normalized()), rad_to_deg(atan2(to.y, maxf(flat.length(), 0.1))))


## Metres the victim is ahead of the shover along the lane.
func _ahead_of_shover() -> float:
	return (_victim.global_position - _shover.global_position).dot(_lane_of(_shover))


## Degrees to the body's right that turn [param from] onto [param to] (a positive turn is right).
static func _right_of(from: Vector3, to: Vector3) -> float:
	var yaw_from: float = atan2(-from.x, -from.z)
	var yaw_to: float = atan2(-to.x, -to.z)
	return -rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI))


func on_shove(_from: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved_at >= 0.0 or victim.body != _victim:
		return
	_shoved_at = elapsed()
	say("shove: %s at %.1f deg r %.2f, %.2f m from %s, facing %.0f deg off the lane" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.distance_to(_shover.global_position), _shover.name, _right_of(_lane_of(_shover), -_shover.global_transform.basis.z)])
	# His feet go inside the 52-54 deg rock (r 50.5) while his eyes stay on the fall.
	_drivers_by_body[_shover].retarget([
		{"do": "lane", "to": ON_TO, "r": float(option("after_r", 48.6)), "speed": 1.0, "weave": 0.02, "period": 1.1, "timeout": 12.0, "carry": true,
			"glances": [{"t": 0.0, "right": 30.0, "pitch": -15.0}]},
		{"do": "hold", "seconds": 60.0},
	])
	# He stops running: his eyes on the man who did it, then on nothing, as he goes.
	_drivers_by_body[_victim].retarget([
		{"do": "watch", "body": _shover, "seconds": 60.0, "height": 1.3},
	])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s %s" % [participant.body.name, participant.death_cause])


func lens(_delta: float) -> bool:
	return false
