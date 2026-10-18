extends "res://tools/capture/stages/stage.gd"

## shove_flop: one runner runs another down on the open S3-S4 deck and shoves him forward up the lane; he goes
## limp in the air and tumbles (the shipped flop), lands, gets up and runs on. Third person: a side dolly on the
## deck, outboard, that rides the pair, then the thrown man. --pov=runner: down the shover's eyes, on the man.
# Ground: probe_ring --clear, flat clear deck r 47.6-56.5 from 181 to 210 deg (melee.gd); pads and traps off.
# Dials: from (183), back (3.2 deg behind), victim_r (52), shover_r (52.4), pace (0.8), shove_gap (1.3 m),
# follow (1.6 s eyes on him), on_to (230), lens_in (-3.5: on the deck 3.5 m outboard, the pit and tower behind), lens_up (1.5), lens_fov (62), lens_lead (0.18 s: the ease).

var _victim: PlayerController = null
var _shover: PlayerController = null
var _drv: Dictionary = {}
var _pov: bool = false
var _swung: bool = false
var _shoved_at: float = -1.0
var _eyes_front: bool = false
var _focus: Vector3 = Vector3.ZERO
var _lens_set: bool = false
var _framed_next: float = 0.0
var _framed_all: bool = true


func bots() -> int:
	return int(option("pack", 2))


func tune_rules(rules: MatchRules) -> void:
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
	_pov = String(option("pov", "")) == "runner"
	var from: float = float(option("from", 183.0))
	var back: float = float(option("back", 3.2))
	var on_to: float = float(option("on_to", 230.0))
	var victim_r: float = float(option("victim_r", 52.0))
	var shover_r: float = float(option("shover_r", 52.4))
	_victim = runners[0].controller
	_shover = runners[1].controller
	_drv[_victim] = drive(runners[0], [
		{"do": "place", "deg": from, "r": victim_r, "h": 0.1, "face": LIB.tangent_at(from)},
		{"do": "human", "on": true},
		{"do": "lane", "to": on_to, "r": victim_r, "speed": float(option("pace", 0.8)), "weave": 0.03, "period": 1.3, "timeout": 12.0,
			"glances": [{"t": 0.0, "right": 2.0, "pitch": -3.0}, {"t": 0.7, "right": -5.0, "pitch": 1.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipFlopVictim")
	_drv[_shover] = drive(runners[1], [
		{"do": "place", "deg": from - back, "r": shover_r, "h": 0.1, "face": LIB.tangent_at(from - back)},
		{"do": "human", "on": true},
		{"do": "lane", "to": on_to, "r": shover_r, "speed": 1.0, "weave": 0.02, "period": 1.1, "timeout": 12.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -6.0}]},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipFlopShover")
	for i: int in range(2, runners.size()):
		var lead: float = from + 9.0 + 4.0 * float(i - 2)
		_drv[runners[i].controller] = drive(runners[i], [
			{"do": "place", "deg": lead, "r": 50.4, "h": 0.1, "face": LIB.tangent_at(lead)},
			{"do": "human", "on": true},
			{"do": "lane", "to": on_to + 30.0, "r": 50.4, "speed": 0.97, "weave": 0.04, "period": 1.5, "timeout": 14.0},
			{"do": "hold", "seconds": 60.0},
		], i, "ClipFlopAhead%d" % i)
	victim_body(_victim)
	stage_body(_shover)
	say("shove_flop: %s runs %s down at %.1f deg%s" % [_shover.name, _victim.name, from, ", ridden" if _pov else ""])
	return true


func tick(_delta: float) -> void:
	if _victim == null or not is_instance_valid(_victim) or elapsed() < 1.0:
		return
	var gap: float = _victim.global_position.distance_to(_shover.global_position)
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		say("gap %.2f | victim %.1f/%.2f y%.2f | shover %.1f/%.2f" % [gap, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.y, LIB.bearing_of(_shover.global_position), LIB.radius_of(_shover.global_position)])
	if _pov and not _eyes_front:
		if _shoved_at >= 0.0 and elapsed() >= _shoved_at + float(option("follow", 1.6)):
			_eyes_front = true
			_drv[_shover].glance_now([{"t": 0.0, "right": 0.0, "pitch": -4.0}])
		else:
			var aim: Vector2 = _aim_at_victim()
			_drv[_shover].glance_now([{"t": 0.0, "right": clampf(aim.x, -60.0, 60.0), "pitch": clampf(aim.y - 4.0, -40.0, 6.0)}])
	if _shoved_at >= 0.0 and elapsed() >= _framed_next and elapsed() <= _shoved_at + 2.05:
		_framed_next = elapsed() + 0.25
		var seen: bool = _in_portrait(_victim)
		_framed_all = _framed_all and seen
		print("[event] %6.2f  %s  %s" % [elapsed(), "in_frame" if seen else "off_frame", _victim.name])
		if _framed_all and elapsed() >= _shoved_at + 1.8:
			print("[event] %6.2f  held_in_frame  %s" % [elapsed(), _victim.name])
		if OS.has_environment("STAGE_DEBUG"):
			var cam: Camera3D = clip.root.get_viewport().get_camera_3d()
			for up: float in [0.1, 1.0, 1.7]:
				var q: Vector3 = cam.global_transform.affine_inverse() * (_victim.global_position + Vector3.UP * up)
				say("frame %.1f: x %.2f y %.2f (limit %.2f / %.2f)" % [up, q.x / -q.z, q.y / -q.z, tan(deg_to_rad(cam.fov) * 0.5) * 9.0 / 16.0, tan(deg_to_rad(cam.fov) * 0.5)])
	if not _swung and gap <= float(option("shove_gap", 1.3)):
		_swung = true
		_drv[_shover].press_shove()


func on_shove(_from: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved_at >= 0.0 or victim.body != _victim:
		return
	_shoved_at = elapsed()
	say("shove: %s at %.1f deg r %.2f" % [_victim.name, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])
	var on_to: float = float(option("on_to", 230.0))
	_drv[_victim].retarget([
		{"do": "land"},
		{"do": "lane", "to": on_to, "r": float(option("victim_r", 52.0)), "speed": 1.0, "weave": 0.03, "period": 1.3, "timeout": 12.0},
		{"do": "hold", "seconds": 60.0},
	])
	_drv[_shover].retarget([
		{"do": "lane", "to": on_to, "r": float(option("shover_r", 52.4)), "speed": 0.75, "weave": 0.02, "period": 1.1, "timeout": 12.0, "carry": true,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -6.0}]},
		{"do": "hold", "seconds": 60.0},
	])


## The smoke's framing check: his feet, chest and head inside the 9:16 frame (the headless viewport is square).
func _in_portrait(body: PlayerController) -> bool:
	var cam: Camera3D = clip.root.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var v: float = tan(deg_to_rad(cam.fov) * 0.5)
	for up: float in [0.1, 1.0, 1.7]:
		var p: Vector3 = cam.global_transform.affine_inverse() * (body.global_position + Vector3.UP * up)
		if p.z >= -0.1 or absf(p.y / -p.z) > v or absf(p.x / -p.z) > v * 9.0 / 16.0:
			return false
	return true


func on_out(participant: MatchParticipant) -> void:
	say("out: %s %s" % [participant.body.name, participant.death_cause])


## Degrees right of the shover's facing and degrees up to the victim's chest.
func _aim_at_victim() -> Vector2:
	var to: Vector3 = _victim.global_position + Vector3.UP * 1.0 - (_shover.global_position + Vector3.UP * 1.6)
	var lane: Vector3 = LIB.tangent_at(LIB.bearing_of(_shover.global_position))
	var flat: Vector3 = Vector3(to.x, 0.0, to.z)
	var yaw_from: float = atan2(-lane.x, -lane.z)
	var yaw_to: float = atan2(-flat.x, -flat.z)
	return Vector2(-rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI)), rad_to_deg(atan2(to.y, maxf(flat.length(), 0.1))))


## The side dolly: inboard of the focus (the pair, then the thrown man, led by his velocity), up, looking at it.
func lens(delta: float) -> bool:
	if _pov or _victim == null or camera() == null or not is_instance_valid(_victim) or elapsed() < 0.65:
		return false
	var want: Vector3 = _victim.global_position.lerp(_shover.global_position, 0.35) + _victim.velocity * float(option("lens_lead", 0.18))
	if _shoved_at >= 0.0:
		want = _victim.global_position + _victim.velocity * float(option("lens_lead", 0.18))
		want.y = lerpf(want.y, _victim.global_position.y, 0.5)
	if not _lens_set:
		_lens_set = true
		_focus = want
	_focus = _focus.lerp(want, 1.0 - exp(-delta / 0.18))
	var look: Vector3 = _focus + Vector3.UP * 0.9
	var deg: float = LIB.bearing_of(_focus)
	var pos: Vector3 = LIB.ring_point(deg, LIB.radius_of(_focus) - float(option("lens_in", -3.5)), float(option("lens_up", 1.5)))
	pos.y = maxf(pos.y, _focus.y + float(option("lens_up", 1.5)))
	camera().global_position = pos
	if OS.has_environment("LENS_DEBUG"):
		say("lens %.1f/%.2f y%.2f | victim %.1f/%.2f v%.1f | shover %.1f/%.2f" % [LIB.bearing_of(pos), LIB.radius_of(pos), pos.y, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.velocity.length(), LIB.bearing_of(_shover.global_position), LIB.radius_of(_shover.global_position)])
	camera().look_at(look, Vector3.UP)
	camera().fov = float(option("lens_fov", 62.0))
	camera().current = true
	return true
