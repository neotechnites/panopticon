extends "res://tools/capture/stages/trailer_duel.gd"

## trailer_duel2: the duel behind real cover -- hell's pocket lip wall (rock r 47-48,
## 2.4-3.0 m tall over 66-70 deg, 0.4 m by 71), not S4's lava. Both captures are POV:
## [code]--pov=runner --look=social[/code] (his eyes) and [code]--pov=guard --hud=crosshair[/code]
## (the scope), same seed, same events. The guard stands at the 70 deg window
## (LIB.guard_to_window, r 5.6). probe_ring --eye=70:5.6:5.85: r 51 BLOCKED by
## MapBaseLip066 at 68-70 deg (h 0.7-1.6), open from 70.5 (h 1.6) and 71; r 49 open every
## 3 deg from 72 to 99 (rock; S2's lava is r 50.3+ from ~74 deg). He crouches at 68.8/50.6
## facing the rock, side-steps left (+bearing) past its end with his eyes on the tower,
## steps back as the round cracks the rock, turns to the course and sprints r 49.
## Dials: at, peek_seconds (0.5), back_seconds (1.15), hidden_by (70.0 deg: the squeeze), break_to, window (70).

const AT: String = "68.8,50.6"
const BREAK_TO: String = "100,49.0"
## Step indices of the beats in cast()'s list.
const STEP_BACK: int = 6
const STEP_COVERED: int = 7
const STEP_TURN: int = 8


## Crouched facing the rock, a side-step out and back, then down the course; eyes never behind him.
func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	_spot = LIB.polar(String(option("at", AT)), LIB.ring_point(68.8, 50.6))
	var away: Vector3 = LIB.polar(String(option("break_to", BREAK_TO)), LIB.ring_point(100.0, 49.0))
	var deg: float = LIB.bearing_of(_spot)
	_runner = runners[0].controller
	# Square to the rock, turned a little toward its end: left is +bearing, the course.
	var face: Vector3 = (-LIB.radial_at(deg) * 0.98 + LIB.tangent_at(deg) * 0.2).normalized()
	_driver = drive(runners[0], [
		{"do": "place", "at": _spot + Vector3.UP * 0.1, "face": face},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 240.0, "gain": 10.0},
		{"do": "until", "t": 1.9, "crouch": true, "sway": 4.0, "period": 2.6, "look_down": -16.0},
		{"do": "hold", "seconds": float(option("peek_seconds", 0.5)), "strafe": -0.55, "look_down": -6.0},
		{"do": "hold", "seconds": 0.45, "look_down": -6.0},
		{"do": "hold", "seconds": float(option("back_seconds", 1.15)), "strafe": 0.7, "crouch": true, "look_down": -10.0},
		{"do": "hold", "seconds": 0.9, "crouch": true, "look_down": -12.0},
		{"do": "glance", "right": -78.0, "pitch": 4.0, "seconds": 0.35},
		{"do": "lane", "to": LIB.bearing_of(away), "r": LIB.radius_of(away), "dir": 1, "speed": 1.0, "weave": 0.04, "period": 1.2, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.9, "right": 34.0, "pitch": 6.0}, {"t": 1.3, "right": 3.0, "pitch": -1.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipDuelDriver")
	victim_body(_runner)
	stage_body(_runner)
	say("trailer_duel2: %s crouched at %.1f deg r %.1f behind the lip wall" % [_runner.name, deg, LIB.radius_of(_spot)])
	return true


## Either POV is lit like the scope (trailer_duel's lift): a ridden body carries no fill.
func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	if String(option("pov", "")) == "":
		return
	var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment.duplicate() as Environment
		env.tonemap_exposure = 3.8
		env.ambient_light_energy = 3.6
		world.environment = env


## The squeeze as he steps back behind the rock (it takes the rock), then the hand rides his sprint.
func tick(_delta: float) -> void:
	if _runner == null:
		return
	if _hand == null:
		_raise_the_hand()
		return
	var step: int = int(_driver.get("_index")) if _driver != null else 0
	if not _fired and step >= STEP_BACK and LIB.bearing_of(_runner.global_position) <= float(option("hidden_by", 70.0)):
		_fired = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at + 0.05
		say("he steps back behind the rock: squeeze")
	if _fired and not _broke and step >= STEP_TURN:
		_broke = true
		_hand.beats[0]["watch"] = true
		say("he breaks for it")
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 15 == 0:
		say("runner %.1f deg r %.2f step %d" % [LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position), step])


## trailer_duel's hand, with the guard first walked to the window a player would stand at.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 70.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.beats.append({"body": _runner, "seconds": 100.0, "fire_at": -1.0})
	_hand.park = LIB.ring_point(70.6, 49.0, 1.2)
	_hand.start_at = elapsed() + 0.2
	say("guard at the %.0f deg window %v; the hand holds on the rock's end" % [float(option("window", 70.0)), _guard.global_position])


## No third-person lens: every shot of the trailer is a POV.
func lens(_delta: float) -> bool:
	return false
