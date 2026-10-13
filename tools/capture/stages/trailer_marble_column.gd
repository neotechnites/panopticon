extends "res://tools/capture/stages/stage.gd"

## trailer_marble_column (10a/10b): two prisoners side by side behind the map's ArcWall188, hidden from the 193.5
## window; one shoves the other along the ring out past its leading end into the open and the guard drops him. Two POVs.
## v37 (Ryan): "the 3 columns for the shove wont work anymore, youll have to use the walls that are now in the map." No spawned
## columns: ArcWall188 (r 47.2, 182.4-193.9 deg, y 23.0-30.6, over the 28.65 eye). probe_ring --map=marble --eye=193.5:5.6:5.65:
## r 48.6 h 0.3/1.0/1.7 BLOCKED to 193.8, open from 193.9; r 48.6-50.5 open 194-200; floor +0.00 r 47.8-55 at 188-208.
## The v11 staging turned -23.25 deg (old edge 217.1 -> 193.85): victim 0.57 deg inside the edge, shover 1 deg behind him.
## v38 (Ryan): "he needs to get shoved further out so that when he gets shot during him running back, his ragdoll doesnt fly behind cover."
## late impulse 16 -> 28: he lands ~206 deg (was 200.6), is hit at 200.6 running back (was 195.0, 1 m off the wall), 6.7 deg clear of the wall's 193.9 end.
## probe_ring --eye=193.5:5.6:5.65: r 48.5 h 0.4/1.0 open from 194.0 on. Smoke fails (expect) if the hit or the rest is inside the cover arc or out of the guard's LoS.
## Dials: victim (193.281,48.55), pov (192.28,48.75), shove (clip s, 2.7), impulse (8.5), up (4.0), lead (0.7: he stops dead on landing), kick (0.3), edge (193.85).
## v8 (Ryan): "he needs to get shot WHILE he's being shoved out": no recovery; the squeeze the first frame he is in the open.
## v27 (Ryan): "the player gets shoved further, the sniper visibly reacts (re-aims), and then hits the shot" (late=1): the shipped
## shove, the scope resting on the wall's far side (rest, deg), he scrambles on (run_after s), the hand comes onto him react s after
## he clears the wall and fires settle s later. And "the runner must NOT look over at the tower" (late=1): the rider's eyes stay low.
## v39 (Ryan): "the sniper pov sucks": late, the scope rides him (beat centre) from the shove to the ragdoll.
## v40 (Ryan): "the sniper doesnt aim". Late dials: rest (deg the scope waits on, 197.0), react (0.2), omega/follow (10, 0.5: he trails
## the throw), hold_over (0.9: onto the held-over mark), settle_omega (25), settle (0.22 s on the mark, then the squeeze), give_up (1.0).
## v41 (Ryan): "we dont even see the fucking shove from the runners pov" and the scope must rest "at the edge of the cover", track, then lead
## him as he runs back. Rest on the wall's end (193.9); expects judge the cuts: m1 (m1_from/m1_to) and m2 (scope_from/scope_to), take s.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const COLUMN_SCENE: String = "res://maps/marble/models/marble_column.glb"
const COLUMN_R: float = 47.5
## The window the guard stands at, by the wall's leading end.
const WINDOW: float = 193.5

var _victim: PlayerController = null
var _pov: PlayerController = null
var _victim_driver: Node = null
var _hand: Node = null
var _guard: PlayerController = null
var _shoved: bool = false
var _shoved_at: float = 0.0
var _exposed: bool = false
var _exposed_at: float = 0.0
var _squeezed: bool = false
var _held: bool = false
var _hit_at: float = -1.0
var _rest_checked: bool = false
## Wall's leading end (deg) and the clear margin past it (deg) the hit and the rest must keep.
const WALL_END: float = 193.9
const CLEAR_DEG: float = 3.0
## v41: in m2 the shoved man stays inside IN_FRAME of the scope's radius from the shove on; in m1 inside IN_FRAME of the runner's frame.
const IN_FRAME: float = 0.9
## v41: before the shove the scope sits within EDGE_DEG of the wall's end; the squeeze leads his chest by LEAD_MIN m along his run.
const EDGE_DEG: float = 1.0
const LEAD_MIN: float = 0.6
const WALL_R: float = 47.2
## v40 (Ryan): "the sniper doesnt aim ... he just aim bots". A human hand: eye speed under HUMAN_RATE deg/s, an overshoot past
## him of OVERSHOOT_DEG corrected, the eye LAG_S behind his line while tracking, and within SETTLE_DEG of the squeeze's mark for SETTLE_S.
const HUMAN_RATE: float = 60.0
const OVERSHOOT_DEG: float = 0.2
const LAG_S: float = 0.05
const MOVING_RATE: float = 2.0
const SETTLE_DEG: float = 0.35
const SETTLE_S: float = 0.2
var _peak_rate: float = 0.0
var _peak_rate_at: float = -1.0
var _last_eye: Vector3 = Vector3.ZERO
var _last_t: float = -1.0
var _first_sign: float = 0.0
var _overshoot: float = 0.0
var _corrected: float = 0.0
var _moved_at: float = -1.0
var _offsets: Array = []
var _fired_at: float = -1.0
var _led_at: float = -1.0
var _on_mark_at: float = -1.0
var _settle: float = -1.0
var _scope_judged: bool = false
var _rest_off: float = 0.0
var _rest_rate: float = 0.0
var _rest_rows: int = 0
var _view_worst: float = 0.0
var _view_worst_at: float = -1.0
var _m1_worst: float = 0.0
var _m1_worst_at: float = -1.0
var _m1_judged: bool = false
var _run_at: Vector3 = Vector3.ZERO
var _run_velocity: Vector3 = Vector3.ZERO
var _lead: float = -INF
var _lead_speed: float = 0.0
var _lead_deg_rate: float = 0.0


## Marble columns at [param degrees] on the inner edge for one shot only; the map scene is untouched.
static func spawn_columns(map: Node, degrees: Array[float]) -> void:
	var packed: PackedScene = load(COLUMN_SCENE) as PackedScene
	if map == null or packed == null:
		printerr("[stage] no marble map or no column; nothing spawned")
		return
	for deg: float in degrees:
		var column: Node3D = packed.instantiate() as Node3D
		column.name = "ClipColumn%d" % int(deg * 10.0)
		map.add_child(column)
		column.global_position = LIB.ring_point(deg, COLUMN_R, 0.0)
		column.rotation = Vector3(0.0, -deg_to_rad(deg), 0.0)


func bots() -> int:
	return 2


func _late() -> bool:
	return int(option("late", 0)) == 1


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"marble"
	rules.shove_impulse = float(option("impulse", 28.0 if _late() else 8.5))
	rules.shove_up_impulse = float(option("up", 7.0 if _late() else 4.0))
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	# The shipped rule: a shot man plays his death and lies where he fell, not parked out of the world.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var v: Vector3 = LIB.polar(String(option("victim", "193.281,48.55")), LIB.ring_point(193.281, 48.55))
	var p: Vector3 = LIB.polar(String(option("pov", "192.28,48.75")), LIB.ring_point(192.28, 48.75))
	var v_deg: float = LIB.bearing_of(v)
	var p_deg: float = LIB.bearing_of(p)
	_victim = runners[0].controller
	_pov = runners[1].controller
	var tower: Vector3 = LIB.ring_point(WINDOW, 5.6, 6.0)
	# The victim: in the wall's shadow, half turned to peek round it at the tower; a slow sway.
	var v_face: Vector3 = (-LIB.radial_at(v_deg) * 0.75 + LIB.tangent_at(v_deg) * 0.45).normalized()
	_victim_driver = drive(runners[0], [
		{"do": "place", "at": v + Vector3.UP * 0.1, "face": v_face},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 200.0, "gain": 8.0},
		{"do": "hold", "seconds": 0.9, "sway": 6.0, "period": 2.9, "look_at": tower},
		{"do": "glance", "right": -24.0, "pitch": -3.0, "seconds": 0.5},
		{"do": "hold", "seconds": 0.5, "look_down": 2.0},
		{"do": "glance", "right": 30.0, "pitch": 4.0, "seconds": 0.45},
		{"do": "hold", "seconds": 60.0, "sway": 4.0, "period": 2.3},
	], 0, "ClipColumnVictim")
	# The rider: tucked in behind him, eyes on the wall and the end of it, a look at him,
	# then square up and shove him along the ring out of its shadow into the gap.
	# Late: turned 60 deg off the wall toward him, so the gap to the tower is never in his eyes.
	var p_face: Vector3 = (LIB.tangent_at(p_deg) * (0.87 if _late() else 0.34) - LIB.radial_at(p_deg) * (0.5 if _late() else 0.94)).normalized()
	var at_him: Vector3 = LIB.toward(p, v)
	var turn: float = _right_of(p_face, at_him)
	LIB.hide_from_the_rifle(_pov)
	# The swing goes along the ring, 5 deg inboard to keep him in the cone; the edge is r 46.7, he lands ~r 48.
	var swing: Vector3 = (LIB.tangent_at(v_deg) * cos(deg_to_rad(5.0)) - LIB.radial_at(v_deg) * sin(deg_to_rad(5.0))).normalized()
	var square: float = _right_of(p_face, swing)
	var late: bool = _late()
	drive(runners[1], [
		{"do": "place", "at": p + Vector3.UP * 0.1, "face": p_face},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.35},
		{"do": "glance", "right": -9.0, "pitch": -4.0 if late else 6.0, "seconds": 0.45},
		{"do": "hold", "seconds": 0.3},
		{"do": "glance", "right": turn * 0.6 + 9.0, "pitch": -7.0, "seconds": 0.4},
		# v26 (Ryan): "a random cut for nor eason before the player gets shoved": the square-up was a 45 deg flick in six
		# frames. His head comes round onto him over half a second, eased, and the shove lands as it arrives.
		{"do": "until", "t": float(option("shove", 2.7)) - float(option("square_lead", 0.85))},
		{"do": "glance", "right": square - turn * 0.6, "pitch": -1.0, "seconds": 0.5, "smooth": true},
		{"do": "shove", "face": swing},
		{"do": "hold", "seconds": 0.25},
		{"do": "glance", "right": 18.0, "pitch": -2.0, "seconds": 0.4},
		{"do": "hold", "seconds": 0.5},
		# Late: his eyes follow the man out along the ring and stay low; never up past the wall at the tower.
		{"do": "glance", "right": 8.0 if late else -40.0, "pitch": -5.0 if late else 7.0, "seconds": 0.5},
		{"do": "hold", "seconds": 60.0, "fidget": true},
	], 1, "ClipColumnShover")
	for index: int in range(2, runners.size()):
		drive(runners[index], [{"do": "place", "at": LIB.ring_point(250.0, 52.0, 0.1)}, {"do": "hold", "seconds": 60.0}], index)
		LIB.hide_from_the_rifle(runners[index].controller)
	victim_body(_victim)
	stage_body(_pov)
	say("trailer_marble_column: %s behind ArcWall188 at %.1f, %s behind him" % [_victim.name, v_deg, _pov.name])
	return true


## Degrees to the body's right that turn [param from] onto [param to] (a positive turn is right).
static func _right_of(from: Vector3, to: Vector3) -> float:
	var yaw_from: float = atan2(-from.x, -from.z)
	var yaw_to: float = atan2(-to.x, -to.z)
	return -rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI))


func tick(delta: float) -> void:
	if _victim == null:
		return
	_measure_run(delta)
	_watch_the_runner()
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 15 == 0 and is_instance_valid(_victim):
		say("victim %.1f deg r %.2f y %.2f; pov %.1f r %.2f" % [LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.y, LIB.bearing_of(_pov.global_position), LIB.radius_of(_pov.global_position)])
	if _hand == null:
		_raise_the_hand()
		return
	_watch_the_scope()
	if _hit_at >= 0.0 and not _rest_checked and elapsed() >= _hit_at + 1.2:
		_rest_checked = true
		_expect_in_the_open("rest")
	_hand.hold_scope = elapsed() >= float(option("zoom", 1.0))
	if not _hand.hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)
	# Exposed: his shoulder clears the wall's edge (edge, deg); the round is already led into the open.
	if _shoved and not _exposed and is_instance_valid(_victim) and LIB.bearing_of(_victim.global_position) >= float(option("edge", 193.85)):
		_exposed = true
		_exposed_at = elapsed()
		if not _late():
			_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at
		say("victim exposed %.2f s after the shove at %.1f deg r %.2f%s" % [elapsed() - _shoved_at, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), "" if _late() else "; squeeze now"])
	# Late: the hand comes onto him react s after he clears the wall; as he breaks back for it the lead goes on, settle s, squeeze.
	if _late() and _exposed and _hand.start_at == INF:
		_hand.start_at = _exposed_at + float(option("react", 0.2))
	# Late: once he is down, the hand comes off his ragdoll onto the mark (his chest, held over for the drop).
	if _late() and _shoved and not _held and elapsed() >= _shoved_at + float(option("hold_over", 0.9)):
		_held = true
		_hand.beats[0]["centre"] = false
	if _late() and _shoved and not _squeezed and elapsed() >= _shoved_at + float(option("run_after", 1.25)) + float(option("back_fire", 0.25)):
		_squeezed = true
		_led_at = elapsed()
		_hand.beats[0]["lead"] = float(option("lead", 1.0))
		_hand.beats[0]["omega"] = float(option("settle_omega", 25.0))
		say("he breaks for the wall; the hand leads him")
	# The squeeze once the eye has sat on its mark for settle s (at most give_up s after the lead goes on).
	if _squeezed and float(_hand.beats[0]["fire_at"]) < 0.0 and not _offsets.is_empty():
		if float(_offsets[-1][3]) > SETTLE_DEG:
			_on_mark_at = -1.0
		elif _on_mark_at < 0.0:
			_on_mark_at = elapsed()
		if (_on_mark_at >= 0.0 and elapsed() - _on_mark_at >= float(option("settle", 0.22))) or elapsed() - _led_at >= float(option("give_up", 1.0)):
			_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at
			say("settled on him; squeeze")


## The guard at the 193.5 window, a hand resting on the wall he hides behind.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", WINDOW)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	if _late():
		# v40 (Ryan): "the sniper doesnt aim ... he just aim bots to a spots and shoot". 5h's hand (omega 6): resting on the
		# wall's end, onto him react s after he clears it, tracked unled; the lead goes on as he breaks, settle s, squeeze.
		_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true, "centre": true, "omega": float(option("omega", 10.0)),
			"follow": float(option("follow", 0.5)), "max_rate": float(option("max_rate", 140.0)), "lead": 0.0, "now": int(option("now", 0)) == 1, "kick": float(option("kick", 0.3))})
		_hand.park = LIB.ring_point(float(option("rest", WALL_END)), 48.6, 1.3)
		_hand.start_at = INF
	else:
		_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true, "lead": float(option("lead", 0.7)), "now": true, "kick": float(option("kick", 0.3))})
		_hand.park = LIB.ring_point(195.35, 48.6, 1.3)
		_hand.start_at = elapsed() + 0.3
	if controller().rifle != null:
		controller().rifle.fired.connect(_on_fired)
	if OS.has_environment("STAGE_DEBUG") and controller().rifle != null:
		controller().rifle.target_hit.connect(func(c: Node3D, at: Vector3, _n: Vector3) -> void:
			say("round struck %s at %.1f deg r %.2f y %.2f" % [c.name if c != null else "?", LIB.bearing_of(at), LIB.radius_of(at), at.y]))
		controller().rifle.projectile_launched.connect(func(o: Vector3, d: Vector3, sp: float) -> void:
			say("launched from r %.2f y %.2f dir %v speed %.0f" % [LIB.radius_of(o), o.y, d, sp]))


func on_shove(_shover: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	_shoved_at = elapsed()
	if _victim_driver != null and _late():
		# v28 (Ryan): "after the shove the runner starts running the ring instead of going back behind cover. He must duck back
		# behind cover." He lies where the throw puts him until he is up (no input on a flopping body), then sprints back for the wall.
		_victim_driver.retarget([
			{"do": "hold", "seconds": float(option("run_after", 1.25))},
			{"do": "lane", "to": float(option("cover", 193.65)), "dir": -1, "r": 48.6, "speed": float(option("back_pace", 1.0)), "timeout": 4.0,
				"glances": [{"t": 0.0, "right": 0.0, "pitch": -3.0}]},
			{"do": "hold", "seconds": 60.0},
		])
	elif _victim_driver != null:
		# Still stumbling from the push when the round arrives: no input, no recovery.
		_victim_driver.retarget([{"do": "hold", "seconds": 60.0}])
	say("shove landed on %s" % victim.body.name)


## Fail the smoke when [param ok] is false; the take plays on so every expect is read.
func _expect(ok: bool, what: String) -> void:
	print("[expect] %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		clip._exit_code = clip.EXIT_BROKEN


## The victim outside the wall's cover arc by [constant CLEAR_DEG] and seen from the guard's eye at the window.
func _expect_in_the_open(label: String) -> void:
	var at: Vector3 = _victim.global_position
	var deg: float = LIB.bearing_of(at)
	_expect(deg >= WALL_END + CLEAR_DEG, "%s at %.1f deg is %.1f deg past the wall's end (need %.1f)" % [label, deg, deg - WALL_END, CLEAR_DEG])
	var query := PhysicsRayQueryParameters3D.create(LIB.ring_point(float(option("window", WINDOW)), 5.6, 5.65), at + Vector3.UP * 0.9)
	query.exclude = [_victim.get_rid(), _guard.get_rid()]
	var blocker: Dictionary = clip.root.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(blocker.is_empty(), "%s in the guard's line of sight%s" % [label, "" if blocker.is_empty() else " (blocked by %s)" % blocker["collider"].name])


## v39 (Ryan): "you see the runner get shoved for one frame, then they go out of frame". Over m2: the rest on the wall's end
## before the shove, then his body (the ragdoll's pelvis once limp) inside the scope; v40 adds the human-hand expects.
func _watch_the_scope() -> void:
	var t: float = elapsed()
	if _scope_judged or t < float(option("scope_from", 2.75)) or _guard == null or not is_instance_valid(_victim):
		return
	if t > float(option("scope_to", 5.33)):
		_scope_judged = true
		_judge_the_hand()
		return
	var eye: Camera3D = _guard.get_node_or_null(^"Head/Camera") as Camera3D
	if eye == null:
		return
	var point: Vector3 = seen_point(_victim)
	var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
	var clear: float = optic.profile.vignette_clear_fraction if optic != null and optic.profile != null else 0.46
	# The screen as the vignette measures it (fov is the vertical one): offset from the centre in half-heights.
	var view: Transform3D = eye.get_camera_transform()
	var look: Vector3 = -view.basis.z
	var line: Vector3 = (point - view.origin).normalized()
	var aim: float = rad_to_deg(look.angle_to(line))
	var frac: float = INF if aim >= 90.0 else tan(deg_to_rad(aim)) / tan(deg_to_rad(eye.fov) * 0.5) / clear
	if _shoved and frac > _view_worst:
		_view_worst = frac
		_view_worst_at = t
	# Before the shove: how far the eye is off the wall's end, and how fast it moves.
	if not _shoved:
		_rest_off = maxf(_rest_off, rad_to_deg(look.angle_to(LIB.ring_point(WALL_END, WALL_R, 1.3) - view.origin)))
		if _last_t >= 0.0 and t > _last_t:
			_rest_rate = maxf(_rest_rate, rad_to_deg(_last_eye.angle_to(look)) / (t - _last_t))
		_rest_rows += 1
	# Yaw of the crosshair off him (deg, + right): the sign the swing comes from, the far side an overshoot.
	var off: float = rad_to_deg(angle_difference(atan2(-line.x, -line.z), atan2(-look.x, -look.z)))
	var dt: float = t - _last_t
	if _last_t >= 0.0 and dt > 0.0:
		var rate: float = rad_to_deg(_last_eye.angle_to(look)) / dt
		if rate > _peak_rate:
			_peak_rate = rate
			_peak_rate_at = t
		if _moved_at < 0.0 and _exposed and rate > MOVING_RATE:
			_moved_at = t
		if _fired_at < 0.0 and _moved_at >= 0.0:
			if _first_sign == 0.0 and absf(off) > OVERSHOOT_DEG:
				_first_sign = signf(off)
			elif _first_sign != 0.0 and -off * _first_sign > _overshoot:
				_overshoot = -off * _first_sign
			elif _overshoot > OVERSHOOT_DEG and -off * _first_sign < _overshoot * 0.5:
				_corrected = _overshoot
	if _fired_at < 0.0:
		# How far the eye is off the point the squeeze will send the round to: the settle is this held small.
		var mark: Vector3 = _hand._mark_for(_hand.beats[0], _victim) if not _hand.beats.is_empty() else point
		_offsets.append([t, atan2(-look.x, -look.z), atan2(-line.x, -line.z), rad_to_deg(look.angle_to(mark - view.origin))])
	if OS.has_environment("STAGE_DEBUG"):
		say("scope %.2f: runner %.0f%% of the radius, %.2f deg off (yaw %+.2f), %.2f off the mark" % [t, frac * 100.0, aim, off, float(_offsets[-1][3]) if not _offsets.is_empty() else -1.0])
	_last_eye = look
	_last_t = t


## The shot: how long before it the eye had been within SETTLE_DEG of the point the round was sent to.
func _on_fired(origin: Vector3, end: Vector3) -> void:
	if _fired_at >= 0.0 or _offsets.is_empty():
		return
	_fired_at = elapsed()
	# The lead: the launch line's nearest pass to his chest, metres ahead of it along his run (flat).
	var line: Vector3 = (end - origin).normalized()
	var chest: Vector3 = _victim.global_position + Vector3.UP * 1.0
	var ahead: Vector3 = origin + line * (chest - origin).dot(line) - chest
	var run := Vector3(_run_velocity.x, 0.0, _run_velocity.z)
	_lead_speed = run.length()
	_lead = Vector3(ahead.x, 0.0, ahead.z).dot(run.normalized()) if _lead_speed > 0.1 else 0.0
	_lead_deg_rate = rad_to_deg(angle_difference(deg_to_rad(LIB.bearing_of(chest - run * 0.1)), deg_to_rad(LIB.bearing_of(chest)))) / 0.1
	say("squeeze: the aim %.2f m ahead of him along his run, %.1f m/s, %.1f deg/s" % [_lead, _lead_speed, _lead_deg_rate])
	if _late():
		# Back onto him to watch it land, at the tracking hand's pace, not the settle's.
		_hand.beats[0]["centre"] = true
		_hand.beats[0]["omega"] = float(option("omega", 10.0))
	_settle = _fired_at - float(_offsets[0][0])
	for i: int in range(_offsets.size() - 1, -1, -1):
		if float(_offsets[i][3]) > SETTLE_DEG:
			_settle = _fired_at - float(_offsets[i][0])
			break


## His velocity off his own steps, averaged over a tenth of a second.
func _measure_run(delta: float) -> void:
	if not is_instance_valid(_victim) or delta <= 0.0:
		return
	var here: Vector3 = _victim.global_position
	if _run_at != Vector3.ZERO:
		_run_velocity = _run_velocity.lerp((here - _run_at) / delta, clampf(delta / 0.1, 0.0, 1.0))
	_run_at = here


## v41 (Ryan): "we dont even see the fucking shove from the runners pov". Over m1, from the shove on, the man he shoves
## stays inside IN_FRAME of the runner's frame and is out past the wall's end by CLEAR_DEG when the cut ends.
func _watch_the_runner() -> void:
	if _m1_judged or not is_instance_valid(_pov) or not is_instance_valid(_victim):
		return
	var t: float = elapsed()
	var to: float = float(option("m1_to", 3.75))
	if t > to:
		_m1_judged = true
		var deg: float = LIB.bearing_of(_victim.global_position)
		_expect(_shoved and _shoved_at >= float(option("m1_from", 1.75)) and to - _shoved_at >= 0.5, "m1: the shove at %.2f, %.2f s before the cut ends (need 0.5)" % [_shoved_at if _shoved else -1.0, to - _shoved_at if _shoved else -1.0])
		_expect(_shoved and _m1_worst <= IN_FRAME, "m1: the shoved man inside %.0f%% of the runner's frame from the shove to the cut's end (worst %.0f%% at %.2f)" % [IN_FRAME * 100.0, _m1_worst * 100.0, _m1_worst_at])
		_expect(deg >= WALL_END + CLEAR_DEG, "m1: at the cut's end he is %.1f deg past the wall's end (need %.1f)" % [deg - WALL_END, CLEAR_DEG])
		return
	if not _shoved:
		return
	var eye: Camera3D = _pov.get_node_or_null(^"Head/Camera") as Camera3D
	if eye == null:
		return
	# Where he sits in the 16:9 frame, as a share of the half-width or half-height, whichever is worse.
	var local: Vector3 = eye.get_camera_transform().affine_inverse() * seen_point(_victim)
	var half: float = tan(deg_to_rad(eye.fov) * 0.5)
	var share: float = INF if local.z >= -0.01 else maxf(absf(local.x / -local.z) / (half * 16.0 / 9.0), absf(local.y / -local.z) / half)
	if share > _m1_worst:
		_m1_worst = share
		_m1_worst_at = t
	if OS.has_environment("STAGE_DEBUG"):
		say("m1 %.2f: he is %.0f%% of the runner's frame out, %.1f deg" % [t, share * 100.0, LIB.bearing_of(_victim.global_position)])


func _judge_the_hand() -> void:
	_expect(_rest_rows > 0 and _rest_off <= EDGE_DEG and _rest_rate < MOVING_RATE, "m2: the scope still on the wall's end from the cut's open to the shove (%d frames, off %.2f deg, need %.1f; peak %.2f deg/s, need under %.0f)" % [_rest_rows, _rest_off, EDGE_DEG, _rest_rate, MOVING_RATE])
	_expect(_view_worst <= IN_FRAME, "m2: the runner inside %.0f%% of the scope radius from the shove to the cut's end (worst %.0f%% at %.2f)" % [IN_FRAME * 100.0, _view_worst * 100.0, _view_worst_at])
	_expect(_fired_at >= 0.0 and _lead >= LEAD_MIN and _lead_deg_rate < 0.0, "m2: at the squeeze (%.2f) the aim leads his chest %.2f m along his run (need %.1f), %.1f m/s, %.1f deg/s toward the wall" % [_fired_at, _lead, LEAD_MIN, _lead_speed, _lead_deg_rate])
	var to: float = float(option("scope_to", 5.33))
	_expect(_hit_at >= 0.0 and to - _hit_at >= 0.3, "m2: the round hits him at %.2f, %.2f s before the cut ends (need 0.3 of the drop in the scope)" % [_hit_at, to - _hit_at])
	_expect(_peak_rate < HUMAN_RATE, "peak eye speed %.1f deg/s at %.2f under a hand's %.0f" % [_peak_rate, _peak_rate_at, HUMAN_RATE])
	_expect(_corrected > OVERSHOOT_DEG, "an overshoot past him corrected (%.2f deg past, need %.2f)" % [_corrected, OVERSHOOT_DEG])
	var lag: float = _lag()
	_expect(lag >= LAG_S, "the eye trails his line while tracking (best fit %.3f s behind, need %.2f)" % [lag, LAG_S])
	_expect(_settle >= SETTLE_S, "crosshair settled %.2f s before the shot at %.2f (need %.2f)" % [_settle, _fired_at, SETTLE_S])
	say("hand: exposed %.2f, first move %.2f (reaction %.2f s), overshoot %.2f deg, peak %.1f deg/s, lag %.3f s, settle %.2f s, fired %.2f" % [
		_exposed_at, _moved_at, _moved_at - _exposed_at, _corrected, _peak_rate, lag, _settle, _fired_at])


## The delay (s) that best lays the eye's yaw over his line's, from the first move to the lead (or the squeeze): zero is an aim bot.
func _lag() -> float:
	var rows: Array = _offsets.filter(func(row: Array) -> bool: return float(row[0]) >= _moved_at and (_led_at < 0.0 or float(row[0]) < _led_at))
	if rows.size() < 30:
		return 0.0
	var best_k: int = 0
	var best: float = INF
	for k: int in range(0, 25):
		var sum: float = 0.0
		for i: int in range(24, rows.size()):
			sum += absf(angle_difference(float(rows[i - k][2]), float(rows[i][1])))
		if sum < best:
			best = sum
			best_k = k
	return float(rows[best_k][0]) - float(rows[0][0])


## Where a man is to the eye: the ragdoll's pelvis once he is limp, else his chest.
static func seen_point(body: PlayerController) -> Vector3:
	var ragdoll: Node = body.get_node_or_null(^"Avatar/Ragdoll")
	if ragdoll != null and (ragdoll.is_active() or ragdoll.is_flopping()):
		return ragdoll.centre()
	return body.global_position + Vector3.UP * 1.0


func on_hit(collider: Node3D) -> void:
	if collider == _victim and _hit_at < 0.0:
		_hit_at = elapsed()
		_expect_in_the_open("hit")
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])


func lens(_delta: float) -> bool:
	return false
