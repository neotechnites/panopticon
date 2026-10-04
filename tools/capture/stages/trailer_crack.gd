extends "res://tools/capture/stages/stage.gd"

## trailer_crack (v4 13/14): hell S3, one take, two POVs. A runner behind the lip rock at 139
## breaks across the open gap, the guard fires and misses, a crack throws him up out of cover.
## Probe (--eye=150:5.6:5.85 --los, h 1.2): hidden 140-142.5 r 48.6-49.5 (MapBaseLip139), open
## 143-144.5 r 49.5-51.5, the S3 wall (+2.5 m at r 47-47.5) hides the lane from 145. Cracks are
## BoostPads (pads stay live): r00_c0 146.6 r 49.2 (143.9-149.3, r 46.8-51.5), r01_c1 149.8 r 52.4.
## Dials: hide (141.2,49.3), go (t of the break, driver s, 1.45), to (153,52.3), mate (145.3,52.4),
## window (150), lead (1.0), squeeze (0.0 s after he clears the rock).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _runner: PlayerController = null
var _mate: PlayerController = null
var _hand: Node = null
var _guard: PlayerController = null
var _fired: bool = false
var _launched: Dictionary = {}


func bots() -> int:
	return 2


func needs_pov() -> String:
	return ""


func tune_rules(rules: MatchRules) -> void:
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


## Traps only: the cracks are pads and they are the beat.
func before_start() -> void:
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	var hide: Vector3 = LIB.polar(String(option("hide", "141.2,49.3")), LIB.ring_point(141.2, 49.3))
	var to: Vector3 = LIB.polar(String(option("to", "153,52.3")), LIB.ring_point(153.0, 52.3))
	var mate: Vector3 = LIB.polar(String(option("mate", "146.0,52.4")), LIB.ring_point(146.0, 52.4))
	var go: float = float(option("go", 1.45))
	_runner = runners[0].controller
	_mate = runners[1].controller
	var deg: float = LIB.bearing_of(hide)
	# Behind the rock, standing: a shuffle, a look up over it at the tower (right), then the break.
	drive(runners[0], [
		{"do": "place", "at": hide + Vector3.UP * 0.1, "face": (LIB.tangent_at(deg) * 0.9 - LIB.radial_at(deg) * 0.3).normalized()},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 260.0, "gain": 11.0},
		{"do": "hold", "seconds": 0.35, "fidget": true, "look_down": 2.0},
		{"do": "glance", "right": 38.0, "pitch": 9.0, "seconds": 0.38},
		{"do": "hold", "seconds": 0.28, "fidget": true},
		{"do": "glance", "right": -44.0, "pitch": -7.0, "seconds": 0.32},
		{"do": "until", "t": go, "fidget": true},
		{"do": "run", "to": to, "within": 0.8, "timeout": 3.0, "speed": 1.0, "weave": 0.05, "period": 1.3,
			"glances": [
				{"t": 0.0, "right": -6.0, "pitch": -4.0},
				{"t": 0.22, "right": 30.0, "pitch": 7.0},
				{"t": 0.5, "right": 4.0, "pitch": -2.0},
			],
			"strafes": [{"t": 0.1, "strafe": 0.06}, {"t": 0.6, "strafe": -0.05}],
			"flinch_on": "miss", "flinch_side": 1.0,
			"flinch_glances": [
				{"t": 0.0, "right": 14.0, "pitch": 6.0},
				{"t": 0.14, "right": 58.0, "pitch": 16.0},
				{"t": 0.75, "right": 46.0, "pitch": 9.0},
				{"t": 1.1, "right": 3.0, "pitch": -3.0},
			]},
		{"do": "lane", "to": 178.0, "r": 52.4, "speed": 0.95, "weave": 0.04, "period": 1.1, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": 2.0, "pitch": -3.0}, {"t": 0.9, "right": 22.0, "pitch": 4.0}, {"t": 1.3, "right": -3.0, "pitch": -2.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipCrackRunner")
	# A second man already behind the wall, off a beat ahead of him: up the lane onto the 150 crack.
	drive(runners[1], [
		{"do": "place", "at": mate + Vector3.UP * 0.1, "face": LIB.tangent_at(LIB.bearing_of(mate))},
		{"do": "human", "on": true},
		{"do": "glance", "right": 26.0, "pitch": 6.0, "seconds": 0.4},
		{"do": "until", "t": go - 0.4},
		{"do": "glance", "right": -24.0, "pitch": -5.0, "seconds": 0.3},
		{"do": "lane", "to": 176.0, "r": 52.5, "speed": 0.88, "weave": 0.06, "period": 1.4, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": -4.0, "pitch": -3.0}, {"t": 0.7, "right": 12.0, "pitch": 3.0}, {"t": 1.2, "right": 1.0, "pitch": -2.0}]},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipCrackMate")
	LIB.hide_from_the_rifle(_mate)
	victim_body(_runner)
	stage_body(_runner)
	say("trailer_crack: %s behind the lip rock at %.1f deg r %.1f, breaks at driver %.2f s" % [_runner.name, deg, LIB.radius_of(hide), go])
	return true


func tick(_delta: float) -> void:
	if _runner == null:
		return
	if _hand == null:
		_raise_the_hand()
		return
	if not _fired and LIB.bearing_of(_runner.global_position) >= float(option("open_from", 143.3)):
		_fired = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at + float(option("squeeze", 0.0))
		say("he clears the rock: squeeze")
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		say("runner %.1f deg r %.2f h %.2f; mate %.1f r %.2f h %.2f" % [LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position), _runner.global_position.y - LIB.DECK_Y, LIB.bearing_of(_mate.global_position), LIB.radius_of(_mate.global_position), _mate.global_position.y - LIB.DECK_Y])
	for body: PlayerController in [_runner, _mate]:
		if is_instance_valid(body) and body.velocity.y > 6.0 and not _launched.has(body.name):
			_launched[body.name] = elapsed()
			say("launch %s at %.1f deg r %.1f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)])


## The guard at the 150 window, the scope resting on the rock's end; the hand rides him after the shot.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 150.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.beats.append({"body": _runner, "seconds": 100.0, "fire_at": -1.0, "watch": true, "lead": float(option("lead", 1.0)), "behind": float(option("behind", 0.0))})
	_hand.park = LIB.ring_point(143.4, 50.0, 1.2)
	_hand.start_at = elapsed() + 0.2
	say("guard at the %.0f deg window; the hand on the rock's end" % float(option("window", 150.0)))


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s" % participant.body.name)


func lens(_delta: float) -> bool:
	return false
