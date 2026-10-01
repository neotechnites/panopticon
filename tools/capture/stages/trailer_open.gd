extends "res://tools/capture/stages/stage.gd"

## trailer_open: the cold open, ONE event filmed twice with the same seed. Ryan: "the guard
## stands where a PLAYER stands -- at the tower's edge/window"; "the runner shot must be the
## EXACT SAME scenario as the guard shot -- two POVs of one event"; "when that runner looks up
## at the tower, nothing is in the way". Three prisoners on hell S2's inner lane, all running
## the course (+bearing); the guard at the window on 115 deg zooms, tracks the middle man and
## drops him; the man a step behind him flinches and looks up at the tower.
##   guard:  --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --seed=20261001
##   runner: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --look=social --seed=20261001
## Probe (probe_ring.gd): floor at r 46.5 is the lip, S2's cover wall stands r 50.5-51.5 from
## 90 to 128 deg with the lava past it (TrapVolume boxes r 50.3-57.5), so the lane is r 48.5-49.5
## rock. --eye=115:5.6:5.7: r 48.5 and 49.5 open at every bearing 96-128. --eye=deg:49:1.6 for
## 108-124: the window (115:5.6:5.7) and the drum (115:3:9) both open. Tower room floor +4.05.
## Dials: window (115), start (deg of the victim at the deal, 90), fire_at (3.6), hand_at (1.3),
## zoom_at (1.9), park (deg ahead the scope rests, 10), up_right (86), up_pitch (12).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

## Lead, victim, POV: the POV is a step directly behind the victim on his radius.
const RADII: Array[float] = [48.7, 49.2, 49.2]
const STAGGER: Array[float] = [3.4, 0.0, -2.6]
const PACE: Array[float] = [0.72, 0.70, 0.70]
const WEAVE: Array[float] = [0.05, 0.03, 0.02]
const PERIOD: Array[float] = [1.3, 1.5, 1.7]
const VICTIM: int = 1
const POV: int = 2

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null
var _start: float = 90.0


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"bentham_ring"
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	# A POV carries no fill light: scope_hunt's lift on both, or the scope reads black and the tower is lost.
	if String(option("pov", "")) != "":
		var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < RADII.size():
		return false
	for index: int in RADII.size():
		if runners[index].controller == null:
			return false
	_start = float(option("start", 90.0))
	for index: int in RADII.size():
		var deg: float = _start + STAGGER[index]
		var lane: Dictionary = {
			"do": "lane", "to": 165.0, "r": RADII[index], "speed": PACE[index],
			"weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0,
		}
		if index == POV:
			# Eyes up the lane and on the men ahead; never back. On the hit: a jerk, then up at the tower.
			lane["glances"] = [
				{"t": 0.0, "right": 0.0, "pitch": -2.0},
				{"t": 0.9, "right": -14.0, "pitch": -3.0},
				{"t": 1.35, "right": 4.0, "pitch": -1.5},
				{"t": 2.1, "right": 9.0, "pitch": -2.0},
				{"t": 2.6, "right": 1.0, "pitch": -1.0},
			]
			lane["strafes"] = [{"t": 0.5, "strafe": 0.08}, {"t": 1.6, "strafe": -0.06}, {"t": 2.5, "strafe": 0.04}]
			lane["flinch_on"] = "hit"
			var up_right: float = float(option("up_right", 86.0))
			var up_pitch: float = float(option("up_pitch", 12.0))
			lane["flinch_glances"] = [
				{"t": 0.0, "right": -7.0, "pitch": 5.0},
				{"t": 0.1, "right": 5.0, "pitch": -4.0},
				{"t": 0.32, "right": up_right, "pitch": up_pitch},
				{"t": 1.15, "right": up_right - 6.0, "pitch": up_pitch - 1.5},
				{"t": 1.9, "right": 6.0, "pitch": -1.0},
			]
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(deg, RADII[index], 0.1), "face": LIB.tangent_at(deg)},
			{"do": "human", "on": true},
			lane,
			{"do": "hold", "seconds": 60.0},
		]
		drive(runners[index], steps, index)
		_bodies.append(runners[index].controller)
	victim_body(_bodies[VICTIM])
	stage_body(_bodies[POV])
	say("trailer_open: three on S2's inner lane from %.1f deg; victim %s, POV %s" % [_start, _bodies[VICTIM].name, _bodies[POV].name])
	return true


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and not _bodies.is_empty() and Engine.get_physics_frames() % 15 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _bodies.is_empty():
		return
	if _hand == null:
		_raise_the_hand()
		return
	var zoomed: bool = elapsed() >= float(option("zoom_at", 1.9))
	_hand.hold_scope = zoomed
	if not zoomed:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)


## Stand the tower's brain down, walk the guard to the window and put a hand on the mouse.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 115.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 1.3))
	_hand.beats.append({"body": _bodies[VICTIM], "seconds": 100.0, "fire_at": float(option("fire_at", 3.6)) - _hand.start_at})
	_hand.park = LIB.ring_point(_start + float(option("park", 10.0)), 49.0, 0.6)
	say("guard at the window on %.0f deg; the hand from %.2f s, squeeze at %.2f s" % [float(option("window", 115.0)), _hand.start_at, float(option("fire_at", 3.6))])


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
