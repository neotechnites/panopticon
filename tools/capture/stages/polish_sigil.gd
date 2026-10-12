extends "res://tools/capture/stages/stage.gd"

## polish_sigil: the old demon sigil at S4 227 deg, prisoners bouncing off it (polish shot 6, L4).
## Ryan: "shot of people bouncing off the demon pads". Filmed at d15d6eb (the sigils) + this stage.
##
## Capture: [code]--shot=s4_edge --stage=polish_sigil --bots=3 --look=social --seconds=7.5[/code]
## (cut in 1.4 s, 5.5 s: the first 227 bounce ~1.0 s in). Shot 7's lens, so L4/L5 read as before/after.
##
## Geometry (probe_ring --pads --heights at d15d6eb): the S4 deck ends at ~212 deg, lava (-0.3 m)
## from 213 to 270; the only way onto the 227 sigil is DemonPad_212deg, which throws a body 14.1 m
## onto it; 227 throws on to 242, 242 to 258. So each prisoner runs up the lane at r 52.6 over the
## 212 pad and bounces off 227 on the way through.
##
## Dials (--set=): line (3 prisoners), gap (1.15 s between them), jitter (0.2 s, seeded).

const PAD_212_DEGREES: float = 212.0
const PAD_212_R: float = 52.6
## The sigil this shot is about (DemonPad_227deg at -37.07, 23.2, -39.84).
const PAD_227: Vector3 = Vector3(-37.07, 23.2, -39.84)
const PAD_242: Vector3 = Vector3(-25.18, 23.4, -47.55)
const PAD_258: Vector3 = Vector3(-11.64, 23.1, -53.13)
## The first body starts ~6 m short of the 212 pad, behind the lens; its 227 bounce is at ~2.4 s.
const START_DEGREES: float = 205.6
const START_R: float = 52.6
## Each later body starts this much further back down the lane, out of shot.
const SPACING_DEGREES: float = 1.6

## Shot 7's lens (polish_crack.gd, /tmp/polish_s4_lens.txt), copied exactly: 1.6 m over the lava,
## 7 m behind the 227 pad on its launch line, looking up the ring at it; a 0.4 deg drift.
const CAM_FROM_DEG: float = 219.7
const CAM_TO_DEG: float = 220.1
const CAM_R: float = 55.05
const CAM_HEIGHT: float = 1.6
const LOOK_DEG: float = 231.3
const LOOK_R: float = 53.9
const LOOK_HEIGHT: float = 1.4
const CAM_FOV: float = 55.0
const DRIFT_SECONDS: float = 11.2

var _bodies: Array = []
var _launched: Dictionary = {}
var _left_212: Dictionary = {}


func bots() -> int:
	return 3


static func steps_for(index: int, hold: float) -> Array:
	var start: Vector3 = LIB.ring_point(START_DEGREES - SPACING_DEGREES * float(index), START_R, 0.1)
	var pad: Vector3 = LIB.ring_point(PAD_212_DEGREES, PAD_212_R, 0.0)
	return [
		{"do": "place", "at": start, "face": LIB.tangent_at(START_DEGREES)},
		{"do": "hold", "seconds": hold},
		{"do": "run", "to": pad + LIB.tangent_at(PAD_212_DEGREES) * 1.0, "within": 0.4, "timeout": 5.0},
		{"do": "wait_launch", "timeout": 2.0},
		# In the air the stick pushes at the next pad, as a player would (air friction eats a hands-off arc).
		{"do": "run", "to": PAD_227, "within": 1.3, "timeout": 2.0},
		{"do": "run", "to": PAD_242, "within": 1.3, "timeout": 2.0},
		{"do": "run", "to": PAD_258, "within": 1.3, "timeout": 2.0},
		{"do": "run", "to": LIB.ring_point(280.0, 53.0), "within": 0.5, "timeout": 3.0},
		{"do": "hold", "seconds": 8.0},
	]


func cast(runners: Array[RunnerBrain]) -> bool:
	var count: int = mini(runners.size(), int(option("line", 3)))
	if count == 0:
		return false
	for index: int in count:
		if runners[index].controller == null:
			return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(clip._options.get("seed", 0)) * 31 + 6)
	var gap: float = float(option("gap", 1.15))
	var jitter: float = float(option("jitter", 0.2))
	for index: int in count:
		var hold: float = 0.05 + gap * float(index) + (rng.randf_range(-jitter, jitter) if index > 0 else 0.0)
		drive(runners[index], steps_for(index, maxf(hold, 0.0)), index, "ClipSigilDriver%d" % index)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[0])
	say("polish_sigil: %d prisoners up the S4 lane" % _bodies.size())
	return true


## Prints the moment each body leaves the 212 pad and bounces off the 227 sigil.
func tick(_delta: float) -> void:
	for body: PlayerController in _bodies:
		if body == null or not is_instance_valid(body):
			continue
		var flat: Vector2 = Vector2(body.global_position.x, body.global_position.z)
		if body.velocity.y > 6.0 and not _left_212.has(body.name) and flat.distance_to(Vector2(-44.61, -27.88)) < 2.5:
			_left_212[body.name] = elapsed()
			say("launch 212 %s" % body.name)
		if body.velocity.y > 6.0 and not _launched.has(body.name) and flat.distance_to(Vector2(PAD_227.x, PAD_227.z)) < 2.5:
			_launched[body.name] = elapsed()
			say("launch 227 %s" % body.name)


func lens(_delta: float) -> bool:
	if camera() == null:
		return false
	var u: float = smoothstep(0.0, 1.0, clampf(elapsed() / DRIFT_SECONDS, 0.0, 1.0))
	camera().global_position = LIB.ring_point(lerpf(CAM_FROM_DEG, CAM_TO_DEG, u), CAM_R, CAM_HEIGHT)
	camera().look_at(LIB.ring_point(LOOK_DEG, LOOK_R, LOOK_HEIGHT), Vector3.UP)
	camera().fov = CAM_FOV
	camera().current = true
	return true
