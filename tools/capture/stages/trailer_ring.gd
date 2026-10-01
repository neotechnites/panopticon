extends "res://tools/capture/stages/stage.gd"

## trailer_ring: a pack of live brains running the ring, filmed from the deck's
## outer edge looking in, so the pack crosses the foreground under the tower.
## Any map (--map=). Reveal trailer variety cuts 13-15. Tower dead.
## Dials: start (deg, 80), cam_r (56.3), cam_h (2.4), fov (68), lag (deg the lens trails the pack, 2).

const SPREAD: Array[float] = [0.0, -1.6, -2.4, -3.9, -5.2]
const RADII: Array[float] = [50.5, 52.6, 49.4, 51.8, 53.4]

var _pack: Array[PlayerController] = []
var _focus: Vector3 = Vector3.ZERO
var _focus_set: bool = false


func bots() -> int:
	return 5


func tune_rules(rules: MatchRules) -> void:
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < SPREAD.size():
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var start: float = float(option("start", 80.0))
	for index: int in SPREAD.size():
		var body: PlayerController = runners[index].controller
		var deg: float = start + SPREAD[index]
		body.global_position = LIB.ring_point(deg, RADII[index], 0.1)
		body.rotation = Vector3(0.0, atan2(-LIB.tangent_at(deg).x, -LIB.tangent_at(deg).z), 0.0)
		if runners[index].profile != null:
			runners[index].profile.track_radius = RADII[index]
		_pack.append(body)
	stage_body(_pack[0])
	say("trailer_ring: five live brains from %.0f deg" % start)
	return true


func lens(delta: float) -> bool:
	if _pack.is_empty() or camera() == null:
		return false
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	for body: PlayerController in _pack:
		if is_instance_valid(body) and LIB.on_deck(body):
			centre += body.global_position
			count += 1
	if count == 0:
		return false
	centre /= float(count)
	if not _focus_set:
		_focus_set = true
		_focus = centre
	_focus = _focus.lerp(centre, 1.0 - exp(-4.0 * delta))
	var deg: float = LIB.bearing_of(_focus) - float(option("lag", 2.0))
	camera().global_position = LIB.ring_point(deg, float(option("cam_r", 56.3)), float(option("cam_h", 2.4)))
	var look: Vector3 = _focus.lerp(Vector3(0.0, LIB.DECK_Y + 6.0, 0.0), 0.45)
	camera().look_at(look, Vector3.UP)
	camera().fov = float(option("fov", 68.0))
	camera().current = true
	return true
