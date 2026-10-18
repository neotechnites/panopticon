extends "res://tools/capture/stages/stage.gd"

## hell_explainer: short 10, ONE take on the hell map, the guard and three runners, filmed
## twice off one seed/tape (as haters_hell): --pov=guard --hud=crosshair (L1), --pov=runner (L2+L3).
##
## Ryan, his words: L1 "I'm making a game where one of your friends is a sniper in a tower"
## {pov sniper shooting at runners in hell}. L2 ", and everyone else has to get past him."
## {pov runner in the back watching the shots at them}. L3 "the first one to make it throws him
## out, and now, they're the sniper." {same shot, walk up to a runner stopped at cover, shove
## him, he gets shot and ragdolls, continue the course}
##
## The beat: three run the S1 deck into S2 at r 49.5, bearing rising (the course's way). The
## hand (guard_hand at the window, never a brain) puts a round behind the lead, one behind the
## middle man, then drops the lead in the open past the lip rock. The middle man jogs in and stops
## crouched in the rock's shadow 0.6 s before the shove; the POV (the back man) runs in behind him
## eases in to 1.5 m, eyes down on his back, and shoves him without stopping, with the shipped shove; the hand drops him in the air, before he lands (he
## ragdolls, CATCH_AND_SWAP); the POV runs on up the S2 lane.
##
## The numbers (probe_ring.gd, eye at the 62 deg window, 5.6 m off the axis, 5.9 m over the deck):
## --los: r 48.5-51.0 open 40-62 deg and 71-84 deg (r 51.0 blocked by the S2 cover from 76);
## MapBaseLip066 shadows 63-70 deg at every radius, crouched (0.6) and standing (1.0). --heights:
## the rock stands +3.0 m over r <= 48.0 at 64-68 deg; r 48.5-51.0 is flat deck from 40 to 78.
## S3 (145-200) is walled off from any window below 2.5 m, and the 139 rock's shadow (136-143)
## opens only onto walled S3 going the course's way: this rock is the one a shove from behind
## throws a man out of. The shipped 16 m/s shove carries a man ~5.5 m (6.4 deg at r 49.5): from
## 68.5 he lands near 75, open deck. 11 m/s ground speed x 0.70 pace is ~8.9 deg/s at r 49.5.
##
## Dials (--set=): start ("lead,mid,pov" deg; 34,22,4.8), r (49.5), stop (68.5, the mid man's
## crouch), mid_pace (0.41), pov_pace (0.45, to pov_mid 42.0 at ~7.1 s), pov_run (0.70, from there to
## close 4.0 m behind him), close_pace (0.4, into reach 1.5, look 14 deg down; the shove >= 4.0 s after the lead hit),
## watch (1.1 s the POV stands after the shove), run_to (100.0), window (62.0), hand_at (0.8), zoom_at (1.2), lower ("a,b": the scope
## down from a to b s, the hand tracking unscoped; none), track_to (0: the hand rides the middle man to this clip second
## before the drop), miss_lead (2.0), miss_mid (3.4),
## miss_by (1.4 m), drop_at (5.5, the lead's squeeze), hold_to (9.0, the hand holds on the fallen lead), air_delay (0.05 s after the shove, the
## shoved man's squeeze: the round reaches him in the air),
## impulse / up (0 = the shipped shove). follow (0 off; ragdoll_short L4): the POV runs this many metres behind the
## lead on pov_r at the lead's pace (pace), stops at the drop and watches him ragdoll.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

const LEAD: int = 0
const MID: int = 1
const POV: int = 2
const PACE: Array[float] = [0.72, 0.70, 0.66]
const WEAVE: Array[float] = [0.03, 0.04, 0.03]
const PERIOD: Array[float] = [1.3, 1.5, 1.7]
## Seconds the hand stays on a man after its squeeze before swinging to the next.
const WATCH_SECONDS: float = 0.5

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _guard: PlayerController = null
var _mid_driver: Node = null
var _shoved_at: float = -1.0
var _landed: bool = false
## Clip seconds the last beat (the shoved man) starts, so its squeeze can be set off the shove.
var _last_beat_at: float = 0.0
## Whether the POV's own eye arms are on the shove, for the [pov] arms log.
var _arms_out: bool = false


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"bentham_ring"
	rules.base_reload_seconds = 1.0
	rules.bots_shove_rivals = false
	if float(option("impulse", 0.0)) > 0.0:
		rules.shove_impulse = float(option("impulse", 0.0))
	if float(option("up", 0.0)) > 0.0:
		rules.shove_up_impulse = float(option("up", 0.0))
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
	var starts: PackedStringArray = String(option("start", "34,22,4.8")).split(",", false)
	var r: float = float(option("r", 49.5))
	var stop: float = float(option("stop", 68.5))
	var run_to: float = float(option("run_to", 100.0))
	for index: int in 3:
		var deg: float = float(starts[index]) if starts.size() == 3 else [34.0, 22.0, 4.8][index]
		var follow: float = float(option("follow", 0.0))
		var pace: float = float(option("pace", PACE[LEAD]))
		if index == POV and follow > 0.0:
			_cast_follower(runners, float(starts[LEAD]) if starts.size() == 3 else 34.0, follow, pace, run_to)
			continue
		var lane: Dictionary = {
			"do": "lane", "to": run_to, "r": r - (0.7 if index == LEAD else 0.0), "speed": pace if index == LEAD else PACE[index],
			"weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0,
		}
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(deg, r, 0.1), "face": LIB.tangent_at(deg)},
			{"do": "human", "on": true},
			lane,
		]
		if index == MID:
			lane["to"] = stop
			lane["speed"] = float(option("mid_pace", 0.41))
			# Crouched in the rock's shadow, peeking up the open lane ahead.
			steps.append({"do": "hold", "seconds": 60.0, "crouch": true, "sway": 10.0, "period": 2.4})
		elif index == POV:
			lane["to"] = float(option("pov_mid", 42.0))
			lane["speed"] = float(option("pov_pace", 0.45))
			# Eyes up the lane on the men ahead; on a hit a jerk and back.
			lane["glances"] = [
				{"t": 0.0, "right": 0.0, "pitch": -2.0},
				{"t": 1.1, "right": -8.0, "pitch": 1.0},
				{"t": 1.8, "right": 5.0, "pitch": -1.5},
				{"t": 3.0, "right": -3.0, "pitch": -1.0},
			]
			lane["flinch_on"] = "hit"
			lane["flinch_glances"] = [
				{"t": 0.0, "right": -6.0, "pitch": 4.0},
				{"t": 0.12, "right": 4.0, "pitch": -3.0},
				{"t": 0.4, "right": 0.0, "pitch": -1.5},
			]
			# No wait: up the lane at the pack's pace, eases in behind him, eyes on his back, and shoves.
			var reach: float = float(option("reach", 1.5))
			var run: float = float(option("pov_run", 0.70))
			steps.append({"do": "lane", "to": stop - rad_to_deg(float(option("close", 4.0)) / r), "r": r, "speed": run,
				"weave": 0.03, "period": 1.6, "timeout": 10.0})
			steps.append({"do": "steer", "on": true})
			steps.append({"do": "chase", "victim": runners[MID].controller, "range": reach,
				"speed": float(option("close_pace", 0.4)), "look_down": float(option("look", 14.0)), "timeout": 4.0})
			# Watch him fly and drop, then continue the course.
			steps.append({"do": "watch", "body": runners[MID].controller, "seconds": float(option("watch", 1.1)), "height": 1.0})
			steps.append({"do": "lane", "to": run_to, "r": r, "speed": 0.72, "weave": 0.03, "period": 1.6,
				"look_down": 2.0, "timeout": 30.0})
		steps.append({"do": "hold", "seconds": 60.0})
		var driver: Node = drive(runners[index], steps, index)
		if index == MID:
			_mid_driver = driver
		_bodies.append(runners[index].controller)
	victim_body(_bodies[MID])
	stage_body(_bodies[POV])
	say("hell_explainer: lead %s, mid %s (stops %.1f), POV %s, r %.1f" % [_bodies[LEAD].name, _bodies[MID].name, stop, _bodies[POV].name, r])
	return true


## follow: the POV a step behind the lead, eyes up the lane on him; at the drop he pulls up and watches the body.
func _cast_follower(runners: Array[RunnerBrain], lead_deg: float, follow: float, pace: float, run_to: float) -> void:
	var pov_r: float = float(option("pov_r", float(option("r", 49.5)) - 0.2))
	var deg: float = lead_deg - rad_to_deg(follow / pov_r)
	var hit_at: float = float(option("drop_at", 5.5)) + 0.37
	var lead: PlayerController = runners[LEAD].controller
	var steps: Array = [
		{"do": "place", "at": LIB.ring_point(deg, pov_r, 0.1), "face": LIB.tangent_at(deg)},
		{"do": "human", "on": true},
		{"do": "lane", "to": run_to, "r": pov_r, "speed": pace, "weave": 0.03, "period": 1.7,
			"timeout": hit_at + float(option("pull_up", 0.15)) - elapsed(),
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -4.0}, {"t": 1.6, "right": -3.0, "pitch": -3.0}, {"t": 3.2, "right": 2.0, "pitch": -4.0}],
			"flinch_on": "hit",
			"flinch_glances": [{"t": 0.0, "right": -4.0, "pitch": 3.0}, {"t": 0.12, "right": 2.0, "pitch": -6.0}]},
		{"do": "steer", "on": true},
		{"do": "watch", "body": lead, "seconds": float(option("watch", 1.1)), "height": float(option("watch_h", 0.5))},
		{"do": "hold", "seconds": 60.0},
	]
	drive(runners[POV], steps, POV)
	_bodies.append(runners[POV].controller)


func tick(_delta: float) -> void:
	if OS.has_environment("STAGE_DEBUG") and not _bodies.is_empty() and Engine.get_physics_frames() % 15 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)]
		say("at" + line)
	if _bodies.is_empty():
		return
	var avatar: PrisonerAvatar = PrisonerAvatar.of(_bodies[POV])
	if avatar != null and bool(avatar.get("_fp_shoving")) != _arms_out:
		_arms_out = not _arms_out
		print("[pov] %5.2f arms %s" % [elapsed(), "shove" if _arms_out else "down"])
	if _hand == null:
		_raise_the_hand()
		return
	var zoomed: bool = elapsed() >= float(option("zoom_at", 1.2))
	var lower: PackedStringArray = String(option("lower", "")).split(",", false)
	if lower.size() == 2 and elapsed() >= float(lower[0]) and elapsed() < float(lower[1]):
		zoomed = false
	_hand.hold_scope = zoomed
	if not zoomed:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)
	var mid: PlayerController = _bodies[MID]
	if _shoved_at >= 0.0 and not _landed and elapsed() > _shoved_at + 0.25 and is_instance_valid(mid) and mid.is_on_floor():
		_landed = true
		say("%s landed at %.2f s, %.1f deg r %.2f" % [mid.name, elapsed(), LIB.bearing_of(mid.global_position), LIB.radius_of(mid.global_position)])


## Stand the tower's brain down, walk the guard to the window, a hand on the mouse.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 62.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 0.8))
	var miss_by: float = float(option("miss_by", 1.4))
	# Each beat starts where the last one's watch ends; its squeeze is a clip time.
	var plan: Array = [
		[_bodies[LEAD], float(option("miss_lead", 2.0)), miss_by],
		[_bodies[MID], float(option("miss_mid", 3.4)), miss_by],
		[_bodies[LEAD], float(option("drop_at", 5.5)), 0.0],
	]
	var at: float = _hand.start_at
	var track_to: float = float(option("track_to", 0.0))
	for row: Array in plan:
		var fire: float = float(row[1])
		if float(row[2]) <= 0.0 and track_to > at:
			# The hand rides the middle man, no shot, before swinging onto the lead.
			_hand.beats.append({"body": _bodies[MID], "seconds": track_to - at})
			at = track_to
		var beat: Dictionary = {"body": row[0], "seconds": fire + WATCH_SECONDS - at, "fire_at": fire - at, "watch": true}
		if float(row[2]) > 0.0:
			beat["miss_by"] = float(row[2])
		else:
			# The drop: the hand stays on him where he falls, never back on the pack.
			beat["clear"] = true
			beat["hold"] = true
			beat["seconds"] = maxf(float(option("hold_to", 9.0)), fire + WATCH_SECONDS) - at
		_hand.beats.append(beat)
		at += float(beat["seconds"])
	_last_beat_at = at
	# fly: he is led along his arc, flung the instant before the squeeze.
	_hand.beats.append({"body": _bodies[MID], "seconds": 100.0, "fire_at": 100.0, "watch": true, "fly": true})
	_hand.park = LIB.ring_point(40.0, 49.5, 0.6)
	say("guard at the window on %.0f deg; the hand from %.2f s" % [float(option("window", 62.0)), _hand.start_at])


func on_shove(_shover: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved_at >= 0.0 or _bodies.size() <= MID or victim.body != _bodies[MID]:
		return
	_shoved_at = elapsed()
	# The squeeze off the shove: the round reaches him in the air, before he lands.
	if _hand != null and not _hand.beats.is_empty():
		var beat: Dictionary = _hand.beats[_hand.beats.size() - 1]
		beat["fire_at"] = _shoved_at + float(option("air_delay", 0.05)) - _last_beat_at
		say("%s shoved at %.2f s; squeeze at %.2f s" % [victim.body.name, _shoved_at, _shoved_at + float(option("air_delay", 0.05))])
	# Crouch key up this tick: he flies, lands and stands where he lands.
	if _mid_driver != null:
		_mid_driver.retarget([{"do": "hold", "seconds": 60.0}])


func on_hit(collider: Node3D) -> void:
	# The smoke's framing check: the shot man's chest inside the lens at the hit.
	var lens: Camera3D = clip.root.get_viewport().get_camera_3d()
	for body: PlayerController in _bodies:
		if body == collider and lens != null and lens.is_position_in_frustum(body.global_position + Vector3.UP):
			print("[event] %6.2f  in_frame  %s" % [elapsed(), body.name])


func on_out(participant: MatchParticipant) -> void:
	if _bodies.size() > MID and participant.body == _bodies[MID]:
		_landed = true
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
