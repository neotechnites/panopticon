extends "res://tools/capture/stages/stage.gd"

## dash_shove: L7 of portal_spin. pack_sniped's pack on the open S3 lane, down the back-row runner's eyes: the tracer
## drops the man a step ahead-right at fire_at, the flinch, then we run down the lead and shove him (shove_at clip s).
## --map=bentham_ring --shot=pack_lead --stage=dash_shove --pov=runner --bots=5. Dials: as pack_sniped, shove_at (3.6).

const RADII: Array[float] = [54.9, 53.8, 56.0, 54.35, 55.45]
const STAGGER: Array[float] = [0.0, -0.3, -0.2, -1.6, -1.7]
const PACE: Array[float] = [0.70, 0.705, 0.695, 0.70, 0.70]
const WEAVE: Array[float] = [0.06, 0.05, 0.06, 0.04, 0.05]
const PERIOD: Array[float] = [1.1, 1.45, 0.95, 1.3, 1.6]
const WATCH_DEG: float = 160.0
## The lens: ahead of the pack on its lane, knee high, looking back at it; the
## lead closes from CAM_LEAD to CAM_LEAD_END degrees over the closing window so
## the pack ends the shot filling the frame.
const CAM_LEAD: float = 9.0
const CAM_LEAD_END: float = 2.2
const CAM_CLOSE_FROM: float = 1.2
const CAM_CLOSE_TO: float = 5.7
const CAM_R: float = 54.6
const CAM_HEIGHT: float = 1.1
const CAM_FOV: float = 72.0
const CAM_SMOOTH: float = 12.0

var _pack: Array = []
var _hidden: Array = []
var _fire_at: float = 3.0
var _unlocked: bool = false
var _fired: bool = false
var _focus: Vector3 = Vector3.ZERO
var _focus_set: bool = false


func bots() -> int:
	return 5


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 0.9


## The shipped brain, aim glued, trigger locked until the beat.
func tune_shooter(profile: ShooterProfile) -> void:
	profile.aim_error_degrees = 0.05
	profile.lead_error_seconds = 0.0
	profile.tracking_omega = 25.0
	profile.confident_range = 120.0
	profile.reaction_seconds = 0.05
	profile.reaction_floor_seconds = 0.02
	profile.shot_confidence_threshold = 1.0
	profile.sure_shot_confidence = 1.0


func before_start() -> void:
	LIB.watch(clip.root, WATCH_DEG, 54.0)


func cast(runners: Array[RunnerBrain]) -> bool:
	var count: int = mini(runners.size(), RADII.size())
	if count == 0:
		return false
	for index: int in count:
		if runners[index].controller == null:
			return false
	_fire_at = float(option("fire_at", 3.0))
	var start: float = float(option("start", 144.0))
	var end: float = float(option("end", 214.0))
	var pov_index: int = int(option("pov_index", 3))
	var pov: bool = true
	var victim_index: int = int(option("victim_index", 1))
	for index: int in count:
		var body: PlayerController = runners[index].controller
		if index != victim_index:
			LIB.hide_from_the_rifle(body)
			_hidden.append(body)
		else:
			victim_body(body)
		var lane: Dictionary = {
			"do": "lane", "to": end, "r": RADII[index], "speed": PACE[index],
			"weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0,
		}
		var steps: Array = [{"do": "place", "at": LIB.ring_point(start + STAGGER[index], RADII[index], 0.1)}]
		if pov and index == pov_index:
			# A hand on the mouse: glances at the neighbours, the flinch when
			# the one ahead-right drops. The pair ahead is on our right (inner).
			lane["glances"] = [
				{"t": 0.0, "right": 0.0, "pitch": -1.0},
				{"t": 0.7, "right": -52.0, "pitch": -4.0},   # a look left at the one beside us
				{"t": 1.15, "right": -46.0, "pitch": -3.0},
				{"t": 1.35, "right": 3.0, "pitch": -1.0},    # back to the lane
				{"t": 1.85, "right": 17.0, "pitch": -2.0},   # a look right at the pair ahead
				{"t": 2.75, "right": 12.0, "pitch": -1.5},
			]
			lane["strafes"] = [
				{"t": 0.4, "strafe": 0.16}, {"t": 1.3, "strafe": -0.1}, {"t": 2.1, "strafe": 0.07},
				{"t": 3.2, "strafe": 0.1}, {"t": 4.1, "strafe": -0.12}, {"t": 4.9, "strafe": 0.05},
			]
			lane["flinch_on"] = "hit"
			steps.append({"do": "human", "on": true})
			stage_body(body)
		if pov and index == pov_index:
			var first: Dictionary = lane.duplicate()
			first["timeout"] = float(option("shove_at", 3.6)) - 0.6
			steps.append(first)
			steps.append({"do": "chase", "victim": runners[0].controller, "range": 2.4, "timeout": 2.5, "speed": 1.0})
			var rest: Dictionary = lane.duplicate()
			rest.erase("glances")
			steps.append(rest)
		else:
			steps.append(lane)
		steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[index], steps, index)
		_pack.append(body)
	if not pov:
		stage_body(_pack[0])
	say("pack of %d dealt at %.0f deg; trigger unlocks at %.1f s" % [_pack.size(), start, _fire_at])
	return true


func tick(_delta: float) -> void:
	if _pack.is_empty():
		return
	if not _unlocked and elapsed() >= _fire_at and LIB.set_trigger(seat(), 0.72):
		_unlocked = true
		say("trigger unlocked")


func on_shot(_confidence: float) -> void:
	if _fired:
		return
	_fired = true
	LIB.set_trigger(seat(), 1.0)
	for body: PlayerController in _hidden:
		if is_instance_valid(body):
			body.add_to_group(MatchController.RUNNER_GROUP)
	say("one shot; trigger locked")


## Ahead of the pack on its lane, looking back at the smoothed pack centroid,
## letting the pack gain on it.
func lens(delta: float) -> bool:
	if _pack.is_empty() or camera() == null:
		return false
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	for body: PlayerController in _pack:
		if body == null or not is_instance_valid(body) or not LIB.on_deck(body):
			continue
		var participant: MatchParticipant = LIB.participant_of(controller(), body)
		if participant != null and not participant.is_running:
			continue
		centre += body.global_position
		count += 1
	if count == 0:
		return false
	centre /= float(count)
	if not _focus_set:
		_focus_set = true
		_focus = centre
	_focus = _focus.lerp(centre, 1.0 - exp(-CAM_SMOOTH * delta))
	var u: float = clampf((elapsed() - CAM_CLOSE_FROM) / (CAM_CLOSE_TO - CAM_CLOSE_FROM), 0.0, 1.0)
	var lead: float = lerpf(CAM_LEAD, CAM_LEAD_END, smoothstep(0.0, 1.0, u))
	var deg: float = LIB.bearing_of(_focus)
	camera().global_position = LIB.ring_point(deg + lead, CAM_R, CAM_HEIGHT)
	camera().look_at(_focus + Vector3.UP * 0.9, Vector3.UP)
	camera().fov = CAM_FOV
	camera().current = true
	return true
