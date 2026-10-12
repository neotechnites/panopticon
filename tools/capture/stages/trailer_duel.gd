extends "res://tools/capture/stages/stage.gd"

## trailer_duel: one runner pinned behind CoverS4 (probe: r 52 hidden at
## 211-220 deg, open at 209-210, Lip204 hides 204-208); he peeks out, ducks back, the guard's round hits
## the rock, the bolt cycles, and he breaks for it down the lane. The guard is a
## hand (guard_hand.gd) that holds on the rock, follows the peek, fires on the
## duck, then follows the sprint without firing. Reveal trailer shots 6-8:
## Third person is this file's fixed lens (cam, look, fov); [code]--pov=guard --hud=crosshair[/code] the scope.
## Dials: at (212.6,52), peek (209.6,52), break_to (198,52.6), cam (205.6,55.2,1.3), look (212.2,51.6,0.9), fov (56).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _runner: PlayerController = null
var _driver: Node = null
var _hand: Node = null
var _guard: PlayerController = null
var _fired: bool = false
var _broke: bool = false
var _spot: Vector3 = Vector3.ZERO


func bots() -> int:
	return 1


func tune_rules(rules: MatchRules) -> void:
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.4
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	# A POV carries no fill light: scope_hunt's lift, or the scope reads black.
	if String(option("pov", "")) == "guard":
		var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	_spot = LIB.polar(String(option("at", "212.6,52.0")), LIB.ring_point(212.6, 52.0))
	var peek: Vector3 = LIB.polar(String(option("peek", "209.6,52.0")), LIB.ring_point(209.6, 52.0))
	var away: Vector3 = LIB.polar(String(option("break_to", "198,52.6")), LIB.ring_point(198.0, 52.6))
	var deg: float = LIB.bearing_of(_spot)
	_runner = runners[0].controller
	_driver = drive(runners[0], [
		{"do": "place", "at": _spot + Vector3.UP * 0.1, "face": (-LIB.radial_at(deg) * 0.8 - LIB.tangent_at(deg) * 0.3).normalized()},
		{"do": "human", "on": true},
		{"do": "until", "t": 1.9, "crouch": true, "sway": 10.0, "period": 2.4},
		{"do": "run", "to": peek, "speed": 0.45, "within": 0.4, "timeout": 2.0, "look_at": Vector3(0.0, 30.0, 0.0)},
		{"do": "hold", "seconds": 0.55},
		{"do": "run", "to": _spot, "speed": 0.6, "within": 0.4, "timeout": 2.0},
		{"do": "hold", "seconds": 1.0, "crouch": true},
		{"do": "lane", "to": LIB.bearing_of(away), "r": LIB.radius_of(away), "dir": -1, "speed": 1.0, "weave": 0.05, "period": 1.2, "timeout": 8.0},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipDuelDriver")
	victim_body(_runner)
	stage_body(_runner)
	say("trailer_duel: %s pinned at %.1f deg r %.1f" % [_runner.name, deg, LIB.radius_of(_spot)])
	return true


func tick(_delta: float) -> void:
	if _runner == null:
		return
	if _hand == null:
		_raise_the_hand()
		return
	# Index 6 is the crouch after the duck (place, human, until, run, hold, run, hold).
	var step: int = int(_driver.get("_index")) if _driver != null else 0
	if not _fired and step >= 6:
		_fired = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at + 0.08
		say("he is back behind the rock: squeeze")
	if _fired and not _broke and step >= 7:
		_broke = true
		_hand.beats[0]["watch"] = true
		say("he breaks for it")


func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.beats.append({"body": _runner, "seconds": 100.0, "fire_at": -1.0})
	_hand.park = _spot + Vector3.UP * 1.0
	_hand.start_at = elapsed() + 0.2
	say("tower brain stood down; the hand holds on the rock")


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


## The fixed third-person lens: outside the pocket, low, the cover and the tower beyond him.
func lens(_delta: float) -> bool:
	return fixed_lens(camera(), String(option("cam", "205.6,55.2,1.3")), String(option("look", "212.2,51.6,0.9")), float(option("fov", 56.0)))


static func fixed_lens(cam: Camera3D, at: String, look: String, fov: float) -> bool:
	if cam == null:
		return false
	cam.global_position = LIB.polar(at, LIB.ring_point(205.6, 55.2, 1.3))
	cam.look_at(LIB.polar(look, LIB.ring_point(212.2, 51.6, 0.9)), Vector3.UP)
	cam.fov = fov
	cam.current = true
	return true
