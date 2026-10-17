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
## middle man, then drops the lead in the open past the lip rock. The middle man stops crouched
## in the rock's shadow; the POV (the back man) comes in behind him, slows to a walk, shoves him
## from 1.8 m with the shipped shove; he lands standing in the open and the hand drops him (he
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
## Dials (--set=): start ("lead,mid,pov" deg; 34,30,25), r (49.5), stop (68.5, the mid man's
## crouch), pov_stop (65.0), walk_at (6.0, clip s the POV walks in), walk (0.35), reach (1.8),
## watch (1.1 s the POV stands after the shove), run_to (100.0), window (62.0), hand_at (0.8), zoom_at (1.2), miss_lead (2.0), miss_mid (3.4),
## miss_by (1.4 m), drop_at (5.5, the lead's squeeze), drop_delay (0.3 s after he lands),
## impulse / up (0 = the shipped shove).

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
## Clip seconds the last beat (the shoved man) starts, so its squeeze can be set on his landing.
var _last_beat_at: float = 0.0


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
	var starts: PackedStringArray = String(option("start", "34,30,25")).split(",", false)
	var r: float = float(option("r", 49.5))
	var cast_at: float = elapsed()
	var stop: float = float(option("stop", 68.5))
	var run_to: float = float(option("run_to", 100.0))
	for index: int in 3:
		var deg: float = float(starts[index]) if starts.size() == 3 else [34.0, 30.0, 25.0][index]
		var lane: Dictionary = {
			"do": "lane", "to": run_to, "r": r - (0.7 if index == LEAD else 0.0), "speed": PACE[index],
			"weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0,
		}
		var steps: Array = [
			{"do": "place", "at": LIB.ring_point(deg, r, 0.1), "face": LIB.tangent_at(deg)},
			{"do": "human", "on": true},
			lane,
		]
		if index == MID:
			lane["to"] = stop
			# Crouched in the rock's shadow, peeking up the open lane ahead.
			steps.append({"do": "hold", "seconds": 60.0, "crouch": true, "sway": 10.0, "period": 2.4})
		elif index == POV:
			lane["to"] = float(option("pov_stop", 65.0))
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
			steps.append({"do": "until", "t": float(option("walk_at", 6.0)) - cast_at})
			steps.append({"do": "chase", "victim": runners[MID].controller, "range": float(option("reach", 1.8)),
				"speed": float(option("walk", 0.35)), "timeout": 4.0})
			# Watch him fly and drop, then continue the course.
			steps.append({"do": "hold", "seconds": float(option("watch", 1.1))})
			steps.append({"do": "lane", "to": run_to, "r": r, "speed": 0.72, "weave": 0.03, "period": 1.6, "timeout": 30.0})
		steps.append({"do": "hold", "seconds": 60.0})
		var driver: Node = drive(runners[index], steps, index)
		if index == MID:
			_mid_driver = driver
		_bodies.append(runners[index].controller)
	victim_body(_bodies[MID])
	stage_body(_bodies[POV])
	say("hell_explainer: lead %s, mid %s (stops %.1f), POV %s, r %.1f" % [_bodies[LEAD].name, _bodies[MID].name, stop, _bodies[POV].name, r])
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
	var zoomed: bool = elapsed() >= float(option("zoom_at", 1.2))
	_hand.hold_scope = zoomed
	if not zoomed:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)
	var mid: PlayerController = _bodies[MID]
	# The shoved man is shot standing: the squeeze is set the moment he is back on the deck.
	if _shoved_at >= 0.0 and not _landed and elapsed() > _shoved_at + 0.25 and is_instance_valid(mid) and mid.is_on_floor():
		_landed = true
		var beat: Dictionary = _hand.beats[_hand.beats.size() - 1]
		beat["fire_at"] = elapsed() + float(option("drop_delay", 0.3)) - _last_beat_at
		say("%s landed at %.1f deg r %.2f; squeeze at %.2f s" % [mid.name, LIB.bearing_of(mid.global_position), LIB.radius_of(mid.global_position), elapsed() + float(option("drop_delay", 0.3))])


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
	for row: Array in plan:
		var fire: float = float(row[1])
		var beat: Dictionary = {"body": row[0], "seconds": fire + WATCH_SECONDS - at, "fire_at": fire - at, "watch": true}
		if float(row[2]) > 0.0:
			beat["miss_by"] = float(row[2])
		else:
			beat["clear"] = true
		_hand.beats.append(beat)
		at = fire + WATCH_SECONDS
	_last_beat_at = at
	# lead 0: he has just landed and stands; the slow velocity average still carries his flight.
	_hand.beats.append({"body": _bodies[MID], "seconds": 100.0, "fire_at": 100.0, "watch": true, "lead": 0.0})
	_hand.park = LIB.ring_point(40.0, 49.5, 0.6)
	say("guard at the window on %.0f deg; the hand from %.2f s" % [float(option("window", 62.0)), _hand.start_at])


func on_shove(_shover: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved_at >= 0.0 or _bodies.size() <= MID or victim.body != _bodies[MID]:
		return
	_shoved_at = elapsed()
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
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
