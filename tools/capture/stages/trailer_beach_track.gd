extends "res://tools/capture/stages/stage.gd"

## trailer_beach_track (v36 beach kill): trailer_marble_track on the beach: the guard on the yacht's flybridge, scoped in on
## three runners on the sand (lane r 68.5, waterline 63.5), the hand rides the lead and the round drops him. --map=beach --set=fire=2.6

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const HUMAN_RUN := preload("res://tools/capture/stages/human_run.gd")
## Where the lead starts (the dial "start").
const START: float = 96.0

## v26 (Ryan): "they look to robotic, because there all just following a line, they should look more like players
## runnign around." Per body, ahead to behind: degrees behind start, radius, seconds before he goes, then his own line.
const BEHIND: Array[float] = [0.0, 2.2, 4.6]
const START_R: Array[float] = [67.6, 66.8, 69.0]
const WAIT: Array[float] = [0.05, 0.12, 0.24]
## When the man in front drops (fire mode): a jerk, up and right at the tower, eyes front; the last man a beat later. Never behind.
const FLINCH: Array = [
	{"t": 0.0, "right": -8.0, "pitch": 4.0}, {"t": 0.12, "right": 10.0, "pitch": -4.0}, {"t": 0.38, "right": 68.0, "pitch": 9.0},
	{"t": 1.0, "right": 6.0, "pitch": -1.0},
]
const FLINCH_LATE: Array = [
	{"t": 0.14, "right": 6.0, "pitch": 3.0}, {"t": 0.3, "right": -5.0, "pitch": -3.0}, {"t": 0.62, "right": 52.0, "pitch": 7.0},
	{"t": 1.35, "right": 3.0, "pitch": -1.0},
]
## The lead: quick away with a look up at the tower, cuts in toward the columns, then a steady line (the hand's lead reads it).
const LEAD_LEGS: Array = [
	{"to": 103.0, "r": 67.8, "speed": 0.78, "weave": 0.04, "period": 1.35,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.45, "right": 48.0, "pitch": 8.0}, {"t": 0.9, "right": 3.0, "pitch": -1.5}]},
	{"to": 108.0, "r": 67.0, "speed": 0.74, "weave": 0.0,
		"glances": [{"t": 0.0, "right": 8.0, "pitch": -2.0}, {"t": 0.5, "right": -3.0, "pitch": -1.0}]},
	{"to": 160.0, "r": 67.4, "speed": 0.72, "weave": 0.03, "period": 1.35,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.9, "right": 10.0, "pitch": -2.0}, {"t": 1.5, "right": -2.0, "pitch": -1.0}]},
]
## The man behind: tight along the columns, then out round the lead's heels and up his outside, quicker.
const SECOND_LEGS: Array = [
	{"to": 103.0, "r": 66.8, "speed": 0.76, "weave": 0.03, "period": 1.1,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.7, "right": -12.0, "pitch": -2.0}]},
	{"to": 109.0, "r": 68.0, "speed": 0.82, "weave": 0.0, "flinch_on": "hit", "flinch_glances": FLINCH,
		"glances": [{"t": 0.0, "right": -9.0, "pitch": -2.0}, {"t": 0.5, "right": 14.0, "pitch": 1.0}]},
	{"to": 160.0, "r": 68.2, "speed": 0.78, "weave": 0.05, "period": 1.1, "flinch_on": "hit", "flinch_glances": FLINCH,
		"glances": [{"t": 0.0, "right": 4.0, "pitch": -1.0}, {"t": 0.8, "right": -4.0, "pitch": -1.0}]},
]
## The last: late off the mark on the outside, sprints to catch up, cuts in across behind the second with a look at the tower.
const THIRD_LEGS: Array = [
	{"to": 100.0, "r": 69.2, "speed": 0.84, "weave": 0.06, "period": 1.6,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.6, "right": 7.0, "pitch": -2.0}]},
	{"to": 107.0, "r": 68.4, "speed": 0.80, "weave": 0.0, "flinch_on": "hit", "flinch_glances": FLINCH_LATE,
		"glances": [{"t": 0.0, "right": 9.0, "pitch": -1.0}, {"t": 0.35, "right": 44.0, "pitch": 7.0}, {"t": 0.8, "right": 4.0, "pitch": -1.0}]},
	{"to": 160.0, "r": 68.6, "speed": 0.75, "weave": 0.06, "period": 1.6, "flinch_on": "hit", "flinch_glances": FLINCH_LATE,
		"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.7, "right": -8.0, "pitch": -1.0}, {"t": 1.3, "right": 3.0, "pitch": -1.0}]},
]
## The bodies the hand works: the lead first, then back to the man behind him. A shot (fire) is on the lead (v26, Ryan:
## "where its only the snipers pov, it should be the player in the front").
const FIRST: int = 0
const SECOND: int = 1

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"beach"
	rules.guard_projectile_speed = 0.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE
	if _fires():
		rules.base_reload_seconds = 1.0
		# The shipped rule: a shot man goes limp where he was hit, not parked out of the world.
		rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var start: float = float(option("start", START))
	var legs: Array = [LEAD_LEGS, SECOND_LEGS, THIRD_LEGS]
	for index: int in range(3):
		var deg: float = start - BEHIND[index]
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(deg, START_R[index], 0.1), "face": LIB.tangent_at(deg)},
			{"do": "human", "on": true},
			{"do": "hold", "seconds": WAIT[index]},
		]
		steps.append_array(HUMAN_RUN.steps(legs[index]))
		steps.append({"do": "hold", "seconds": 60.0})
		drive(runners[index], steps, index)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[FIRST])
	if _fires():
		for index: int in range(3):
			if index != FIRST:
				LIB.hide_from_the_rifle(_bodies[index])
		victim_body(_bodies[FIRST])
	say("trailer_beach_track: three from %.1f deg on the sand" % start)
	return true


func tick(_delta: float) -> void:
	if _bodies.is_empty():
		return
	if Engine.get_physics_frames() % 30 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _hand == null:
		_raise_the_hand()
		return
	_hand.hold_scope = elapsed() >= float(option("zoom", 0.8))
	if not _hand.hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)


## The guard at the flybridge rail, a hand on the mouse.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 108.0)), float(option("guard_r", 1.2)))
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = elapsed() + 0.1
	_hand.park = LIB.ring_point(float(option("start", START)), 67.5, 1.0)
	if _fires():
		# One man from the start: the lead is read off a speed the eye has measured the whole way.
		_hand.beats.append({"body": _bodies[FIRST], "seconds": 100.0, "watch": true,
			"fire_at": float(option("fire", -1.0)) - _hand.start_at, "lead": float(option("lead", 1.0))})
	else:
		_hand.beats.append({"body": _bodies[FIRST], "seconds": float(option("swing", 2.4)) - _hand.start_at})
		_hand.beats.append({"body": _bodies[SECOND], "seconds": 100.0})
	if OS.has_environment("STAGE_DEBUG") and controller().rifle != null:
		controller().rifle.target_hit.connect(func(c: Node3D, at: Vector3, _n: Vector3) -> void:
			say("round struck %s at %.1f deg r %.2f y %.2f" % [c.name if c != null else "?", LIB.bearing_of(at), LIB.radius_of(at), at.y]))


func _fires() -> bool:
	return float(option("fire", -1.0)) >= 0.0


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.1f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])


func lens(_delta: float) -> bool:
	return false
