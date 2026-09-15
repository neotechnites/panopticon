extends "res://tools/capture/stages/stage.gd"

## melee: five runners in a scrap, all shoving each other (f08_melee). Filmed
## with [code]--shot=s3_melee --bots=5 --seconds=8[/code], cut from 1.0 s in
## for 6 s; 22 shoves landed in the take, every bot 4-5.
##
## Ryan: "lets have like 5 bots all shoving eachother"; then "they all shove on
## the same cadence" and "around the demon pad which is messing them up"; then
## "just let them shove more, they're just running at each other and staying
## there".
##
## So: the ground is 195 deg r 52, the longest stretch of the ring with nothing
## that launches a body (probe_ring.gd --clear: flat clear deck r 47.5-56.5
## from 179 to 210; the S3 pad at 177 ends at 179, the S4 pad at 212 starts at
## 211). Every body gets its own driver on the "brawl" step, seeded per index
## (opening hold 0.15-1.0 s, reach 2.0-2.4 m, reaction 0.05-0.3 s, breather
## 0-0.35 s, circling between swings), and a shove is only thrown when the
## victim would land inside the safe zone, so nobody is knocked onto a pad or
## over the rim. The match's shove cooldown is 0.8 s for this stage. The lens
## chases the cluster's centre from 4.8 deg round the ring, in the scrap so the
## figures are large and fill the middle of the tall frame.
##
## Dials (--set=): deg (195), r (52), ring (the starting circle's radius, 1.9),
## cooldown (0.8), seconds (how long they brawl, 12).

const SAFE := {"from": 181.0, "to": 208.5, "r_min": 47.6, "r_max": 56.5}
const LENS_BACK_DEGREES: float = 4.8
const LENS_OUT: float = 0.9
const LENS_UP: float = 1.55
const LENS_FOV: float = 82.0    # 52 deg across the 9:16 frame
const LENS_EASE: float = 0.45

var _bodies: Array = []
var _lens_pos: Vector3 = Vector3.ZERO
var _lens_look: Vector3 = Vector3.ZERO
var _lens_set: bool = false


func bots() -> int:
	return 5


func tune_rules(rules: MatchRules) -> void:
	rules.shove_cooldown_seconds = float(option("cooldown", 0.8))


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var deg: float = float(option("deg", 195.0))
	var r: float = float(option("r", 52.0))
	var ring: float = float(option("ring", 1.9))
	var centre: Vector3 = LIB.ring_point(deg, r, 0.0)
	for brain: RunnerBrain in runners:
		_bodies.append(brain.controller)
	for index: int in runners.size():
		var angle: float = TAU * float(index) / float(runners.size())
		var at: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * ring
		drive(runners[index], [
			{"do": "place", "at": at + Vector3.UP * 0.1, "face": LIB.toward(at, centre)},
			{"do": "brawl", "others": _bodies, "safe": SAFE, "seconds": float(option("seconds", 12.0))},
			{"do": "hold", "seconds": 60.0},
		], index)
	stage_body(runners[0].controller)
	say("melee of %d at %.1f deg r %.1f" % [runners.size(), deg, r])
	return true


## The chase lens: the cluster's centre from a few degrees round the ring, a
## little outboard and up, looking at chest height, eased. Bodies thrown at
## the lens pass through it.
func lens(delta: float) -> bool:
	if _bodies.is_empty() or camera() == null:
		return false
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	for body: PlayerController in _bodies:
		if body == null or not is_instance_valid(body) or not LIB.on_deck(body):
			continue
		centre += body.global_position
		count += 1
	if count == 0:
		return false
	centre /= float(count)
	var deg: float = LIB.bearing_of(centre)
	var want_pos: Vector3 = LIB.ring_point(deg - LENS_BACK_DEGREES, LIB.radius_of(centre) + LENS_OUT, LENS_UP)
	var want_look: Vector3 = centre + Vector3.UP * 1.0
	if not _lens_set:
		_lens_set = true
		_lens_pos = want_pos
		_lens_look = want_look
	var k: float = 1.0 - exp(-delta / LENS_EASE)
	_lens_pos = _lens_pos.lerp(want_pos, k)
	_lens_look = _lens_look.lerp(want_look, k)
	camera().global_position = _lens_pos
	if _lens_pos.distance_squared_to(_lens_look) > 0.0001:
		camera().look_at(_lens_look, Vector3.UP)
	camera().fov = LENS_FOV
	camera().current = true
	return true
