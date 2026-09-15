extends "res://tools/capture/stages/stage.gd"

## lavaparkour: a line of runners hopping the seven S5 lake platforms
## (f10_lava_parkour, the hook; f10_lava_parkour_pov down the last one's eyes).
## Ryan: "a shot of some runners doing the section 5 lava jumps. should look
## like a minecraft parkour shot" -- "get it for me as a 3rd person and as a pov".
##
## Third person: [code]--shot=lava_parkour --stage=lavaparkour --bots=4 --seconds=11[/code]
## (cut 0.9 s in, 7 s): the lens rides ~4.3 m behind and 3.3 m over the last
## body in the line, which sits large in the lower middle of the tall frame,
## the others hop away up the frame, lava fills the bottom. POV:
## [code]--pov=runner[/code] rides the last body, the only one played through
## the human layer: the steering is a wrist (300 deg/s), the eyes go up the line
## to the platform after the next for the first 0.3 s of every flight and then
## down onto the landing, a small yaw flick mid-air lines it up, one stumble on
## the fourth landing (a dead stop, the head dipping, then on).
##
## Geometry from tools/modelling/map_base_build.py: the lake runs 292.3-338.3
## deg, floor 0.3 m under the deck, seven 2.4 m platforms at deck height from
## 298 deg every 5.7676 deg, alternating r 54.8 / r 50.2 (7.0 m apart). Each
## hop is an exact ballistic leap at 10.5 m/s, the shipped jump's own arc.
##
## Dials (--set=): line (4, runners in the line), stagger (0.2 s between them).

const LAKE_NEAR_BANK: float = 292.3
const LAKE_FAR_BANK: float = 338.3
const PLAT_B0: float = 298.0
const PLAT_STEP: float = 5.7676
const PLAT_OUT_R: float = 54.8
const PLAT_IN_R: float = 50.2
const PLAT_COUNT: int = 7
const LEAP_SPEED: float = 10.5
## The edge a runner launches from: this far from a platform's centre toward
## the next (the top is 1.2 m to the edge).
const EDGE: float = 0.85
const START_DEGREES: float = 290.4
const START_R: float = 52.6
const SPACING_DEGREES: float = 2.3
## The chase lens.
const FOLLOW_BACK_DEGREES: float = 4.7
const FOLLOW_UP: float = 3.3
const FOLLOW_R: float = 52.5
const FOLLOW_FOV: float = 74.0
const FOLLOW_LOOK_SHARE: float = 0.6   # of the look point, on the nearest body
const FOLLOW_POS_RATE: float = 5.0
const FOLLOW_LOOK_RATE: float = 7.0

var _line: Array = []
var _follow_pos: Vector3 = Vector3.ZERO
var _follow_look: Vector3 = Vector3.ZERO
var _following: bool = false


func bots() -> int:
	return 4


static func platform_centre(index: int) -> Vector3:
	var radius: float = PLAT_OUT_R if index % 2 == 0 else PLAT_IN_R
	return LIB.ring_point(PLAT_B0 + PLAT_STEP * float(index), radius, 0.0)


## The hops, in order: the lip of the near bank, the seven platforms, the far bank.
static func stops() -> Array:
	var out: Array = [LIB.ring_point(LAKE_NEAR_BANK - 0.4, 52.8, 0.0)]
	for index: int in PLAT_COUNT:
		out.append(platform_centre(index))
	out.append(LIB.ring_point(LAKE_FAR_BANK + 1.2, 53.4, 0.0))
	return out


## Runner [param index] of the line: placed on the bank, off after its stagger,
## then edge, leap, land, edge, leap ... to the far bank and on up the lane.
static func steps_for(index: int, human: bool, stagger: float) -> Array:
	var hops: Array = stops()
	var start: Vector3 = LIB.ring_point(START_DEGREES - SPACING_DEGREES * float(index), START_R, 0.1)
	var steps: Array = [
		{"do": "place", "at": start, "face": LIB.toward(start, hops[0])},
		{"do": "hold", "seconds": 0.25 + stagger * float(index), "look_down": 6.0},
	]
	if human:
		steps.append({"do": "steer", "on": true, "rate": 300.0, "gain": 7.0, "pitch_rate": 140.0, "pitch_gain": 6.0})
		steps.append({"do": "human", "on": true})
	else:
		steps.append({"do": "steer", "on": true, "rate": 720.0, "gain": 14.0})
	steps.append({"do": "run", "to": hops[0], "within": 0.45, "timeout": 4.0, "look_at": hops[1]})
	for hop: int in range(1, hops.size()):
		var target: Vector3 = hops[hop]
		steps.append({"do": "leap", "to": target, "speed": LEAP_SPEED, "lock": 0.45 if human else 0.9})
		var land: Dictionary = {"do": "land", "look_at": target + Vector3.UP * 0.2}
		if human:
			land["correct"] = 5.0
			land["stick_after"] = 0.42
			if hop + 1 < hops.size():
				land["look_ahead"] = hops[hop + 1] + Vector3.UP * 0.8
				land["ahead_until"] = 0.3
		steps.append(land)
		if hop == hops.size() - 1:
			break
		if human and hop == 4:
			# The stumble: a dead stop on the landing, the head dipping, then on.
			steps.append({"do": "hold", "seconds": 0.17, "look_down": 30.0})
		var next: Vector3 = hops[hop + 1]
		var edge: Vector3 = target + LIB.toward(target, next) * EDGE
		steps.append({"do": "run", "to": edge, "within": 0.3, "timeout": 2.5, "look_at": next + Vector3.UP * 0.6})
	# Off the far bank and on up the lane, short of the portal at 345.
	steps.append({"do": "run", "to": LIB.ring_point(342.0, 52.5, 0.0), "within": 0.5, "timeout": 4.0, "look_down": 4.0})
	steps.append({"do": "hold", "seconds": 8.0, "look_down": 4.0})
	return steps


func cast(runners: Array[RunnerBrain]) -> bool:
	var count: int = mini(runners.size(), int(option("line", 4)))
	if count == 0:
		return false
	for index: int in count:
		if runners[index].controller == null:
			return false
	var pov: bool = String(option("pov", "")) == "runner"
	var stagger: float = float(option("stagger", 0.2))
	var pov_index: int = count - 1
	for index: int in count:
		var human: bool = pov and index == pov_index
		drive(runners[index], steps_for(index, human, stagger), index, "ClipParkourDriver%d" % index)
		_line.append(runners[index].controller)
		if human:
			stage_body(runners[index].controller)
	if not pov:
		stage_body(_line[0])
	say("lavaparkour: %d in line, %s leads%s" % [_line.size(), _line[0].name, (", riding " + _line[pov_index].name) if pov else ""])
	return true


## The chase lens over the lake: behind and above the last body in the line,
## eased, looking between it and the leader. Bodies that have died drop out.
func lens(delta: float) -> bool:
	if _line.is_empty() or camera() == null:
		return false
	var alive: Array = []
	for body: PlayerController in _line:
		if body == null or not is_instance_valid(body):
			continue
		var participant: MatchParticipant = LIB.participant_of(controller(), body)
		if participant != null and participant.is_running and body.global_position.y > LIB.DECK_Y - 3.0:
			alive.append(body)
	if alive.is_empty():
		return false
	var rear: PlayerController = alive[alive.size() - 1]
	var lead: PlayerController = alive[0]
	var rear_deg: float = LIB.bearing_of(rear.global_position)
	if rear_deg < 270.0 or LIB.bearing_of(lead.global_position) < 270.0:
		return false   # not placed on the bank yet: the shot path's start pose
	var mean_r: float = 0.0
	for body: PlayerController in alive:
		mean_r += LIB.radius_of(body.global_position)
	mean_r /= float(alive.size())
	var want_pos: Vector3 = LIB.ring_point(rear_deg - FOLLOW_BACK_DEGREES, lerpf(FOLLOW_R, mean_r, 0.35), FOLLOW_UP)
	var want_look: Vector3 = (rear.global_position + Vector3.UP * 0.9) * FOLLOW_LOOK_SHARE + (lead.global_position + Vector3.UP * 0.9) * (1.0 - FOLLOW_LOOK_SHARE)
	if not _following:
		_following = true
		_follow_pos = want_pos
		_follow_look = want_look
	_follow_pos = _follow_pos.lerp(want_pos, 1.0 - exp(-FOLLOW_POS_RATE * delta))
	_follow_look = _follow_look.lerp(want_look, 1.0 - exp(-FOLLOW_LOOK_RATE * delta))
	camera().global_position = _follow_pos
	if _follow_pos.distance_squared_to(_follow_look) > 0.0001:
		camera().look_at(_follow_look, Vector3.UP)
	camera().fov = FOLLOW_FOV
	camera().current = true
	return true
