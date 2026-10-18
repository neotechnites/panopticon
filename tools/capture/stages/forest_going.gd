extends "res://tools/capture/stages/stage.gd"

## forest_going: short 11 "how its going", ONE take in the forest, the guard and three runners, filmed twice off one
## seed/tape: --pov=guard --hud=crosshair (the hand at the 32 deg window drops the lead, then the middle man, and keeps
## tracking the back man) and --pov=runner (the back man runs the lane behind them, both drop ahead of him, he runs on).
## [code]--stage=forest_going --shot=s3_open_lane --map=forest --pov=guard|runner --bots=3 --seed=20261017[/code]
## Numbers from forest_window's probe (eye 32:4.4:5.9 sees the open stretch 41-60 at r 50-52); every lane ends at 75.
## Dials (--set=): pace (0.62), scope_fov (24.0), hand_at (0.8), drop_lead (2.3), drop_mid (3.7), track (5.0), reload (1.0),
## pov_start (29.0 deg), pov_r (51.5), pov_pace (pace), miss_pov (0: off; a squeeze at the POV that crosses miss_by m ahead of him), miss_by (1.3).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

const LEAD: int = 0
const MID: int = 1
const POV: int = 2
## deg, r of each runner's start: the back man starts behind the other two.
const STARTS: Array = [Vector2(37.0, 51.6), Vector2(33.5, 51.0), Vector2(29.0, 51.5)]
const WATCH_SECONDS: float = 0.5

var _bodies: Array[PlayerController] = []
var _hand: Node = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = float(option("reload", 1.0))
	rules.guard_projectile_speed = 0.0
	rules.bots_shove_rivals = false
	# A shot man plays his death and lies where he fell.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for index: int in 3:
		if runners[index].controller == null:
			return false
	var pace: float = float(option("pace", 0.62))
	for index: int in 3:
		var at: Vector2 = STARTS[index]
		var speed: float = pace * (1.03 if index == LEAD else 1.0)
		if index == POV:
			at = Vector2(float(option("pov_start", at.x)), float(option("pov_r", at.y)))
			speed = float(option("pov_pace", pace))
		var lane: Dictionary = {"do": "lane", "to": 75.0, "r": at.y, "speed": speed,
			"weave": 0.04, "period": 1.3 + 0.2 * index, "timeout": 30.0}
		if index == POV:
			# Eyes up the lane on the two ahead; on a hit a jerk and back, never a look behind.
			lane["glances"] = [
				{"t": 0.0, "right": 6.0, "pitch": -2.0},
				{"t": 1.2, "right": -4.0, "pitch": 1.0},
				{"t": 2.4, "right": 8.0, "pitch": -1.5},
				{"t": 3.6, "right": 2.0, "pitch": -1.0},
			]
			lane["flinch_on"] = "hit"
			lane["flinch_glances"] = [
				{"t": 0.0, "right": -6.0, "pitch": 4.0},
				{"t": 0.12, "right": 4.0, "pitch": -3.0},
				{"t": 0.4, "right": 2.0, "pitch": -1.5},
			]
			var miss_at: float = float(option("miss_pov", 0.0))
			if miss_at > 0.0:
				# A look right, toward the tower, as the round crosses; eyes front before the man ahead drops.
				var after: float = miss_at - float(option("drop_lead", 2.3))
				lane["flinch_glances"].append({"t": after + 0.08, "right": 18.0, "pitch": 3.0})
				lane["flinch_glances"].append({"t": after + 0.4, "right": 0.0, "pitch": -2.0})
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(at.x, at.y, 0.1), "face": LIB.tangent_at(at.x)},
			{"do": "human", "on": true},
			lane,
			{"do": "hold", "seconds": 60.0, "fidget": true},
		], index, "ClipGoingRunner%d" % index)
		_bodies.append(runners[index].controller)
	victim_body(_bodies[LEAD])
	stage_body(_bodies[POV])
	say("forest_going: lead %s, mid %s, POV %s; pace %.2f" % [_bodies[LEAD].name, _bodies[MID].name, _bodies[POV].name, pace])
	return true


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and not _bodies.is_empty() and Engine.get_physics_frames() % 6 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _bodies.is_empty() or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	var stand: Vector3 = LIB.ring_point(32.0, 4.4, 0.0)
	guard.global_position = Vector3(stand.x, guard.global_position.y, stand.z)
	guard.velocity = Vector3.ZERO
	LIB.open_the_scope(guard, 0.74)
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic
	var fov: float = float(option("scope_fov", 24.0))
	if fov > 0.0 and optic != null and optic.profile != null and optic.base_fov > 0.0:
		optic.profile.zoom_factor = clampf(fov / optic.base_fov, 0.05, 1.0)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 0.8))
	# Each beat starts where the last one's watch ends; the last tracks the back man and never fires.
	var at: float = _hand.start_at
	var plan: Array = [[_bodies[LEAD], float(option("drop_lead", 2.3)), 0.0], [_bodies[MID], float(option("drop_mid", 3.7)), 0.0]]
	if float(option("miss_pov", 0.0)) > 0.0:
		plan.insert(1, [_bodies[POV], float(option("miss_pov", 0.0)), float(option("miss_by", 1.3))])
	for index: int in plan.size():
		var row: Array = plan[index]
		var fire: float = float(row[1])
		var next: float = float(plan[index + 1][1]) if index + 1 < plan.size() else fire + WATCH_SECONDS * 2.5
		var watch: float = minf(WATCH_SECONDS, (next - fire) * 0.4)
		var beat: Dictionary = {"body": row[0], "seconds": fire + watch - at, "fire_at": fire - at, "watch": true, "clear": true}
		if float(row[2]) > 0.0:
			# Negative miss_by: the round goes ahead of him along his run, across his eyes.
			beat["miss_by"] = -float(row[2])
			beat["clear"] = false
		_hand.beats.append(beat)
		at = fire + watch
	_hand.beats.append({"body": _bodies[POV], "seconds": float(option("track", 5.0))})
	_hand.park = LIB.ring_point(44.0, 51.0, 1.0)
	say("forest_going: hand on %s at the 32 deg window from %.2f s" % [guard.name, _hand.start_at])


func on_hit(collider: Node3D) -> void:
	# The smoke's framing check: the shot man's chest inside the lens at the hit.
	var lens: Camera3D = clip.root.get_viewport().get_camera_3d()
	for body: PlayerController in _bodies:
		if body == collider and lens != null and lens.is_position_in_frustum(body.global_position + Vector3.UP):
			print("[event] %6.2f  in_frame  %s" % [elapsed(), body.name])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
