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
## v39 (Ryan): "the sniper pov sucks": late, the scope is centred on him (beat centre) from the raise; rest and react are gone.

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
var _hit_at: float = -1.0
var _rest_checked: bool = false
## Wall's leading end (deg) and the clear margin past it (deg) the hit and the rest must keep.
const WALL_END: float = 193.9
const CLEAR_DEG: float = 3.0
## v39: over the m2 cut (scope_from/scope_to, clip s) the runner stays inside half the scope's radius (7.4 deg) and AIM_DEG of the aim.
const SCOPE_INNER: float = 0.5
const AIM_DEG: float = 3.5
var _worst_frac: float = 0.0
var _worst_aim: float = 0.0
var _worst_at: float = -1.0
var _scope_judged: bool = false


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


func tick(_delta: float) -> void:
	if _victim == null:
		return
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
	# Late: the hand is already on him; the squeeze as he breaks back for the wall (back_fire s after the break), led on his run.
	if _late() and _shoved and not _squeezed and elapsed() >= _shoved_at + float(option("run_after", 1.25)) + float(option("back_fire", 0.25)):
		_squeezed = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at
		say("he breaks for the wall; squeeze at %.2f s" % elapsed())


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
		# v39 (Ryan): "the sniper pov sucks ... the sniper pans over". The scope rides him from before the shove,
		# centred on him (no lead) through the throw, the run back, the hit and the ragdoll; only the squeeze is led.
		_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true, "centre": true, "omega": float(option("omega", 6.0)),
			"lead": float(option("lead", 1.0)), "now": int(option("now", 0)) == 1, "kick": float(option("kick", 0.3))})
		_hand.park = _victim.global_position + Vector3.UP
	else:
		_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true, "lead": float(option("lead", 0.7)), "now": true, "kick": float(option("kick", 0.3))})
		_hand.park = LIB.ring_point(195.35, 48.6, 1.3)
	_hand.start_at = elapsed() + 0.3
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


## Fail the smoke when [param ok] is false.
func _expect(ok: bool, what: String) -> void:
	print("[expect] %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		clip._fail("expect failed: %s" % what)


## The victim outside the wall's cover arc by [constant CLEAR_DEG] and seen from the guard's eye at the window.
func _expect_in_the_open(label: String) -> void:
	var at: Vector3 = _victim.global_position
	var deg: float = LIB.bearing_of(at)
	_expect(deg >= WALL_END + CLEAR_DEG, "%s at %.1f deg is %.1f deg past the wall's end (need %.1f)" % [label, deg, deg - WALL_END, CLEAR_DEG])
	var query := PhysicsRayQueryParameters3D.create(LIB.ring_point(float(option("window", WINDOW)), 5.6, 5.65), at + Vector3.UP * 0.9)
	query.exclude = [_victim.get_rid(), _guard.get_rid()]
	var blocker: Dictionary = clip.root.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(blocker.is_empty(), "%s in the guard's line of sight%s" % [label, "" if blocker.is_empty() else " (blocked by %s)" % blocker["collider"].name])


## v39 (Ryan): "you see the runner get shoved for one frame, then they go out of frame". Over the cut, his body (the
## ragdoll's pelvis once limp) must sit within SCOPE_INNER of the scope's radius and within AIM_DEG of the eye's line.
func _watch_the_scope() -> void:
	var t: float = elapsed()
	if _scope_judged or t < float(option("scope_from", 3.05)) or _guard == null or not is_instance_valid(_victim):
		return
	if t > float(option("scope_to", 5.65)):
		_scope_judged = true
		_expect(_worst_frac <= SCOPE_INNER, "runner within %.0f%% of the scope radius over the cut (worst %.0f%% at %.2f)" % [SCOPE_INNER * 100.0, _worst_frac * 100.0, _worst_at])
		_expect(_worst_aim <= AIM_DEG, "guard's aim within %.1f deg of the runner over the cut (worst %.2f deg)" % [AIM_DEG, _worst_aim])
		return
	var eye: Camera3D = _guard.get_node_or_null(^"Head/Camera") as Camera3D
	if eye == null:
		return
	var point: Vector3 = seen_point(_victim)
	var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
	var clear: float = optic.profile.vignette_clear_fraction if optic != null and optic.profile != null else 0.46
	# The screen as the vignette measures it (fov is the vertical one): offset from the centre in half-heights.
	var view: Transform3D = eye.get_camera_transform()
	var aim: float = rad_to_deg((-view.basis.z).angle_to(point - view.origin))
	var frac: float = INF if aim >= 90.0 else tan(deg_to_rad(aim)) / tan(deg_to_rad(eye.fov) * 0.5) / clear
	if OS.has_environment("STAGE_DEBUG"):
		say("scope %.2f: runner %.0f%% of the radius, %.2f deg off the aim" % [t, frac * 100.0, aim])
	if frac > _worst_frac:
		_worst_frac = frac
		_worst_at = t
	_worst_aim = maxf(_worst_aim, aim)


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
