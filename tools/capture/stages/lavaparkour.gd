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
## [code]--pov=runner[/code] rides the last body, played as a person (v19, Ryan: "the lava
## parkour scene doesnt relaly look human"): his eyes are his own (stage_driver.eyes), on
## the landing for the first half of a flight and round onto the next platform before he
## is down, one turn a hop on a spring; he never lands on the same spot twice (POV_PLAN),
## so no two run-ups are the same length; a check on one top, a stumble on another.
##
## Geometry from tools/modelling/maps/bentham_ring/map_base_build.py: the lake runs 292.3-338.3
## deg, floor 0.3 m under the deck, seven 2.4 m platforms at deck height from
## 298 deg every 5.7676 deg, alternating r 54.8 / r 50.2 (7.0 m apart). Each
## hop is an exact ballistic leap in the shipped jump's own air time (0.636 s: 7 m/s up, 22 down).
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
## The shipped jump: 2 * jump_velocity / gravity.
const JUMP_SECONDS: float = 0.636
## The POV's landings, platform by platform: metres past the centre along his line and to its right, how far
## out he launches from, a "hold" on the top (seconds) and whether his eyes drop to his feet for it ("dip").
const POV_PLAN: Array = [
	{"along": 0.2, "side": 0.15, "edge": 0.8},
	{"along": 0.4, "side": -0.2, "edge": 0.95, "hold": 0.1},
	{"along": -0.15, "side": 0.25, "edge": 0.7},
	{"along": -0.5, "side": -0.1, "edge": 0.9, "hold": 0.17, "dip": true},
	{"along": 0.3, "side": 0.2, "edge": 0.85},
	{"along": 0.0, "side": -0.25, "edge": 1.0, "hold": 0.08},
	{"along": 0.2, "side": 0.1, "edge": 0.75},
]
## Share of a flight his eyes stay on the landing before they go to the next platform, hop by hop.
const POV_EYES_SHARE: Array = [0.5, 0.42, 0.6, 0.5, 0.66, 0.45, 0.55, 0.5]
## How far toward the platform after it the look at the next one is pulled (a turn short of square).
const POV_EYES_ON: float = 0.22
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
## The POV body's driver, where each of its hops comes down, and what each of its steps is.
var _pov_driver: Node = null
var _pov_lands: Array = []
var _pov_meta: Array = []
var _pov_step: int = -1
var _pov_flight: float = 7.0


## The line is the whole field (--set=line=3 is three prisoners and the guard, nobody else).
func bots() -> int:
	return int(option("line", 4))


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
## [param plan] moves each landing and launch off the centre line; [param meta], when given, is filled
## step for step with {"hop", "phase"} so a stage can tell where in the line of hops the body is.
static func steps_for(index: int, human: bool, stagger: float, plan: Array = [], meta: Array = []) -> Array:
	var hops: Array = stops()
	var lands: Array = landings(plan)
	var start: Vector3 = LIB.ring_point(START_DEGREES - SPACING_DEGREES * float(index), START_R, 0.1)
	var steps: Array = [
		{"do": "place", "at": start, "face": LIB.toward(start, hops[0])},
		{"do": "hold", "seconds": 0.25 + stagger * float(index), "look_down": 6.0},
	]
	if human:
		steps.append({"do": "human", "on": true})
	else:
		steps.append({"do": "steer", "on": true, "rate": 720.0, "gain": 14.0})
	steps.append({"do": "run", "to": hops[0], "within": 0.45, "timeout": 4.0, "look_at": hops[1]})
	while meta.size() < steps.size():
		meta.append({"hop": 0, "phase": "ground"})
	var from: Vector3 = hops[0]
	for hop: int in range(1, hops.size()):
		var target: Vector3 = lands[hop]
		var speed: float = Vector2(target.x - from.x, target.z - from.z).length() / JUMP_SECONDS if not plan.is_empty() else LEAP_SPEED
		steps.append({"do": "leap", "to": target, "speed": speed, "lock": 0.45 if human else 0.9})
		meta.append({"hop": hop, "phase": "air"})
		var land: Dictionary = {"do": "land", "look_at": target + Vector3.UP * 0.2}
		if human:
			land["stick_after"] = 0.42
		steps.append(land)
		meta.append({"hop": hop, "phase": "air"})
		if hop == hops.size() - 1:
			break
		var entry: Dictionary = plan[hop - 1] if hop - 1 < plan.size() else {}
		if float(entry.get("hold", 0.0)) > 0.0:
			steps.append({"do": "hold", "seconds": float(entry["hold"]), "look_down": 30.0})
			meta.append({"hop": hop, "phase": "dip" if bool(entry.get("dip", false)) else "ground"})
		var next: Vector3 = lands[hop + 1]
		from = hops[hop] + LIB.toward(hops[hop], next) * float(entry.get("edge", EDGE))
		steps.append({"do": "run", "to": from, "within": 0.3, "timeout": 2.5, "look_at": next + Vector3.UP * 0.6})
		meta.append({"hop": hop, "phase": "ground"})
	# Off the far bank and on up the lane, short of the portal at 345.
	steps.append({"do": "run", "to": LIB.ring_point(342.0, 52.5, 0.0), "within": 0.5, "timeout": 4.0, "look_down": 4.0})
	steps.append({"do": "hold", "seconds": 8.0, "look_down": 4.0})
	while meta.size() < steps.size():
		meta.append({"hop": hops.size() - 1, "phase": "ground"})
	return steps


## Where each hop comes down: the stop itself, moved by [param plan] along the line in and to its right.
static func landings(plan: Array) -> Array:
	var hops: Array = stops()
	var out: Array = [hops[0]]
	for hop: int in range(1, hops.size()):
		var entry: Dictionary = plan[hop - 1] if hop - 1 < plan.size() else {}
		var line: Vector3 = LIB.toward(hops[hop - 1], hops[hop])
		out.append(hops[hop] + line * float(entry.get("along", 0.0)) + Vector3(-line.z, 0.0, line.x) * float(entry.get("side", 0.0)))
	return out


## A plan for a body that is not the POV: seeded off the take and its place in the line, small, and no two alike.
static func plan_for(take_seed: int, index: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = take_seed * 31 + index
	var out: Array = []
	for hop: int in PLAT_COUNT:
		var entry: Dictionary = {"along": rng.randf_range(-0.3, 0.3), "side": rng.randf_range(-0.25, 0.25), "edge": rng.randf_range(0.7, 0.95)}
		if rng.randf() < 0.2:
			entry["hold"] = rng.randf_range(0.05, 0.1)
		out.append(entry)
	return out


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
		var plan: Array = POV_PLAN if human else plan_for(int(clip._options.get("seed", 0)), index)
		var driver: Node = drive(runners[index], steps_for(index, human, stagger, plan, _pov_meta if human else []), index, "ClipParkourDriver%d" % index)
		_line.append(runners[index].controller)
		if human:
			_pov_driver = driver
			_pov_lands = landings(plan)
			stage_body(runners[index].controller)
	if not pov:
		stage_body(_line[0])
	say("lavaparkour: %d in line, %s leads%s" % [_line.size(), _line[0].name, (", riding " + _line[pov_index].name) if pov else ""])
	return true


## The POV's eyes, every tick: the landing while it is still to be made, then the next platform, never square on it.
func tick(_delta: float) -> void:
	if _pov_driver == null or not is_instance_valid(_pov_driver):
		return
	var body: PlayerController = _pov_driver.body()
	var step: int = int(_pov_driver.get("_index"))
	var index: int = mini(step, _pov_meta.size() - 1)
	var hop: int = int(_pov_meta[index]["hop"])
	var phase: String = String(_pov_meta[index]["phase"])
	var point: Vector3 = _look_at_hop(hop + 1)
	if phase == "air":
		var here: Vector3 = body.global_position
		var left: float = Vector2(_pov_lands[hop].x - here.x, _pov_lands[hop].z - here.z).length()
		if _pov_meta[maxi(mini(_pov_step, _pov_meta.size() - 1), 0)]["phase"] != "air":
			_pov_flight = maxf(left, 0.1)
		if 1.0 - left / _pov_flight < float(POV_EYES_SHARE[(hop - 1) % POV_EYES_SHARE.size()]):
			point = _pov_lands[hop] + Vector3.UP * 0.1
	elif phase == "dip":
		point = body.global_position - body.global_transform.basis.z * 1.4 + Vector3.UP * 0.2
	_pov_step = step
	_pov_driver.eyes(point)
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		say("pov %.1f deg r %.2f h %.2f hop %d %s yaw %.0f pitch %.0f floor %s" % [LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y - LIB.DECK_Y, hop, phase, rad_to_deg(body.rotation.y), rad_to_deg(body.head.rotation.x), body.is_on_floor()])


## Where he looks when hop [param hop] is the next one: its landing, pulled a little toward the one after, and
## off the lake up the lane once the bank is all that is left.
func _look_at_hop(hop: int) -> Vector3:
	var last: int = _pov_lands.size() - 1
	if hop > last:
		return LIB.ring_point(345.0, 52.5, 1.2)
	var after: Vector3 = _pov_lands[hop + 1] if hop < last else LIB.ring_point(345.0, 52.5, 0.0)
	return (_pov_lands[hop] as Vector3).lerp(after, POV_EYES_ON) + Vector3.UP * 0.3


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
