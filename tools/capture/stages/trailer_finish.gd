extends "res://tools/capture/stages/stage.gd"

## trailer_finish: a runner POV takes the last of S5 into the portal (345 deg
## r 52) off the last lake platform, is handed the finisher rifle in the tower room, shoots the guard, and
## after the kill beat holds the tower. Reveal trailer shot 12:
## [code]--shot=portal --stage=trailer_finish --pov=runner --bots=2[/code].
## Arrival is called here (the lap tracker never saw a lap). Dials: from (332.6,54.8), turn_after (0.15 s after he
## arrives the guard starts round), turn_seconds (0.9: he faces the finisher before the trigger is live).
# v26 (Ryan): "int the final scence, the gaurd should turn around fully before getting shot."

const PORTAL_DEG: float = 345.0
const PORTAL_R: float = 52.0
const ARRIVE_METRES: float = 1.4

var _runner: PlayerController = null
var _driver: Node = null
var _armed: bool = false
var _armed_at: float = 0.0
var _hunter: TowerShooter = null
var _unlocked: bool = false
var _guard: PlayerController = null
var _turn_from: Vector2 = Vector2.ZERO


func bots() -> int:
	return 2


func tune_rules(rules: MatchRules) -> void:
	rules.finisher_hunts_guard = true
	rules.guard_health = 1
	rules.kill_beat_seconds = 1.2
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	controller().kill_beat_started.connect(func(_guard: MatchParticipant, _seconds: float, _throw: Vector3 = Vector3.ZERO) -> void: say("kill beat: the guard is down"))


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	var from: Vector3 = LIB.polar(String(option("from", "332.6,54.8")), LIB.ring_point(332.6, 54.8))
	_runner = runners[0].controller
	_driver = drive(runners[0], [
		{"do": "place", "at": from + Vector3.UP * 0.1, "face": LIB.tangent_at(LIB.bearing_of(from))},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.5},
		{"do": "leap", "to": LIB.ring_point(339.6, 52.3, 0.0), "speed": 8.0},
		{"do": "land", "look_at": LIB.ring_point(PORTAL_DEG, PORTAL_R, 1.6)},
		{"do": "lane", "to": PORTAL_DEG + 3.0, "r": PORTAL_R, "speed": 1.0, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}, {"t": 0.5, "right": 24.0, "pitch": 6.0}, {"t": 0.95, "right": 2.0, "pitch": 0.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipFinishDriver")
	# The other prisoner is parked out of the way, back down the lap.
	drive(runners[1], [
		{"do": "place", "at": LIB.ring_point(250.0, 52.0, 0.1), "face": LIB.tangent_at(250.0)},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipParkedDriver")
	LIB.hide_from_the_rifle(runners[1].controller)
	stage_body(_runner)
	say("trailer_finish: %s runs from %.1f deg into the portal" % [_runner.name, LIB.bearing_of(from)])
	return true


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and _runner != null and Engine.get_physics_frames() % 30 == 0:
		say("at %.1f deg r %.1f y %.2f" % [LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position), _runner.global_position.y])
	if _hunter != null and not _unlocked and elapsed() >= _armed_at + float(option("draw", 1.3)):
		_unlocked = true
		_hunter.profile.shot_confidence_threshold = 0.15
		_hunter.profile.sure_shot_confidence = 0.0
		say("finisher trigger unlocked")
	_turn_the_guard()
	if _runner == null or _armed or int(_driver.get("_index")) < 5:
		return
	if _runner.global_position.distance_to(LIB.ring_point(PORTAL_DEG, PORTAL_R, 0.0)) > ARRIVE_METRES:
		return
	_armed = true
	_driver.release()
	var participant: MatchParticipant = LIB.participant_of(controller(), _runner)
	controller().call("_arm_the_finisher", participant)
	_armed_at = elapsed()
	# The rifle is drawn and raised before the trigger is live (draw, 1.3 s).
	_hunter = controller().call("_find_tower_brain", participant) as TowerShooter
	if _hunter != null and _hunter.profile != null:
		LIB.dead_shooter(_hunter.profile)
	var rifle: Rifle = controller().get_finisher_rifle()
	if rifle != null:
		var vignette: ScopeVignette = rifle.get_node_or_null(^"ScopeVignette") as ScopeVignette
		if vignette != null:
			vignette.set_local_holder(true)
	say("arrived; finisher armed: %s" % (controller().get_finisher() != null))


## The guard hears him arrive and comes round to face him: one eased turn, his rifle with it, done before the shot.
func _turn_the_guard() -> void:
	if not _armed or _runner == null:
		return
	var into: float = elapsed() - _armed_at - float(option("turn_after", 0.15))
	if into < 0.0:
		return
	if _guard == null:
		var shooter: TowerShooter = LIB.stand_down(seat())
		if shooter == null or shooter.controller == null or shooter.controller == _runner:
			return
		_guard = shooter.controller
		_turn_from = Vector2(_guard.rotation.y, _guard.head.rotation.x if _guard.head != null else 0.0)
	var to: Vector3 = _runner.global_position - _guard.global_position
	var want := Vector2(atan2(-to.x, -to.z), atan2(to.y, maxf(Vector2(to.x, to.z).length(), 0.1)))
	if into < 0.02:
		say("the guard (%s) turns %.0f deg to face him, %.1f m off" % [_guard.name, rad_to_deg(angle_difference(_turn_from.x, want.x)), to.length()])
	var u: float = clampf(into / maxf(float(option("turn_seconds", 0.9)), 0.05), 0.0, 1.0)
	var share: float = u * u * (3.0 - 2.0 * u)
	var pitch: float = lerpf(_turn_from.y, want.y, share)
	_guard.rotation = Vector3(0.0, lerp_angle(_turn_from.x, want.x, share), 0.0)
	if _guard.head != null:
		_guard.head.rotation.x = pitch
	# The controller keeps its own pitch and would snap the head back on the next look input.
	_guard.set(&"_pitch", pitch)


func on_hit(collider: Node3D) -> void:
	say("hit %s" % (collider.name if collider != null else "nothing"))
