extends "res://tools/capture/stages/lavaparkour.gd"

## parkour_sniped: short 9, ONE take on hell, the guard and one runner, filmed twice off one seed/tape:
## --pov=runner (L2) and --pov=guard --hud=crosshair (L3).
## Ryan: L2 {runner pov, looking over at the tower while hes shooting, then look forward and start doing the lava parkour
## section}; L3 {pov of the sniper sniping at the runner from the previous shot}.
##
## The beat (--bots=3, two parked at 103/106 deg out of frame): the runner stands on the S5 near bank (290.4 deg r 52.6) looking over at the tower window while the hand puts
## rounds by him (misses, miss_by m off), turns forward at look_to and hops the seven platforms as lavaparkour's POV
## (POV_PLAN, his own eyes); the hand rides him hop to hop and drops him on an outer top (drop_at).
## The numbers (probe_ring --los, eye at the 305 deg window 5.6 m out, 5.9 m up): the bank 290.4/292 and the outer tops
## (r 54.8: 298, 309.5, 321, 332.6) open; every inner top (r 50.2) hidden by the S5 rim. From 315 or 325 the tower's own
## wall blocks the lake; 305 is the window.
##
## He aims from the 295 opening's centre, 6.2 m out at the sill (guard_deg, guard_r): the 305 spot put the 315 pier in the scope as it swung.
## Dials (--set=): window (305.0, where the runner looks), look_to (3.4, he turns off the tower), misses ("1.9,3.0": the squeezes that miss), miss_by (1.5),
## hand_at (0.8), zoom_at (1.2), drop_at (0.0 = no drop), hold_to (0.0), hold_out (0.0: s he stands on each outer top, in the openings), scope_zoom (0.0: the optic's zoom factor),
## look_drift (1.4 m: the eyes wander on the window so the look is never a frozen frame; 0 drift froze the take).
## finish (0 = off; v9 L3: deg he runs to off the far bank, short of the portal at 345, then turns to the guard's window and
## waits) with finish_pace (0.6). The lake is seen from every window through the S5 fins (r 48.5, 4.3 m tall at 304.5/316.5/
## 328.5 deg): no scope circle (11.3 deg wide at the shipped zoom) fits a gap, so the clean shot is past the last fin, from
## the 340 window (open 328.5-344.5 at every height; the gate from 345): him landing off the last top and at the finish.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const WATCH_SECONDS: float = 0.5

var _runner: PlayerController = null
var _hand: Node = null
var _guard: PlayerController = null
var _hop_seen: int = -1
var _finish_step: int = -1


## Two more players stand out of both frames up the S1 lane, so his death is not the round's end (a solo kill restarts it).
func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"bentham_ring"
	rules.base_reload_seconds = 1.0
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)


func _window_eye() -> Vector3:
	return LIB.ring_point(float(option("window", 305.0)), 5.6, 5.9)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for index: int in 3:
		if runners[index].controller == null:
			return false
	for index: int in [1, 2]:
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(100.0 + 3.0 * float(index), 49.0, 0.1)},
			{"do": "hold", "seconds": 60.0},
		], index, "ClipParkourParked%d" % index)
		LIB.hide_from_the_rifle(runners[index].controller)
	# He waits on the bank for look_to; lavaparkour's own POV hops after it.
	var lead: Dictionary = {"wait": maxf(float(option("look_to", 3.4)) - 0.6, 0.1)}
	var plan: Array = POV_PLAN.duplicate(true)
	for top: int in [0, 2, 4]:
		plan[top]["hold"] = maxf(float(plan[top].get("hold", 0.0)), float(option("hold_out", 0.0)))
	var steps: Array = steps_for(0, true, 0.0, plan, _pov_meta, lead)
	var finish: float = float(option("finish", 0.0))
	if finish > 0.0:
		# In place of lavaparkour's run to 342 and hold: to the finish, then round onto the window he is shot from.
		steps.resize(steps.size() - 2)
		steps.append({"do": "run", "to": LIB.ring_point(finish, 52.5, 0.0), "within": 0.4, "timeout": 4.0,
			"speed": float(option("finish_pace", 0.6)), "look_down": 4.0})
		steps.append({"do": "hold", "seconds": 30.0, "look_at": LIB.ring_point(float(option("guard_deg", 295.0)), 5.6, 5.9)})
		_finish_step = steps.size() - 1
	_pov_driver = drive(runners[0], steps, 0, "ClipParkourPOV")
	_pov_lands = landings(plan)
	_runner = runners[0].controller
	_line.append(_runner)
	stage_body(_runner)
	say("parkour_sniped: %s on the bank, the window at %.0f deg" % [_runner.name, float(option("window", 305.0))])
	return true


func tick(delta: float) -> void:
	super.tick(delta)
	if _runner == null:
		return
	if _pov_driver != null and is_instance_valid(_pov_driver) and elapsed() < float(option("look_to", 3.4)):
		# Over at the tower while it shoots, the eyes never dead still (look_drift m at the window, ~1.5 deg).
		var t: float = elapsed()
		var drift: float = float(option("look_drift", 1.4))
		_pov_driver.eyes(_window_eye() + Vector3(sin(t * 1.7) + 0.5 * sin(t * 3.1), 0.6 * sin(t * 1.1 + 0.7), cos(t * 1.3)) * drift)
	var step: int = int(_pov_driver.get("_index")) if _pov_driver != null and is_instance_valid(_pov_driver) else 0
	var hop: int = int(_pov_meta[mini(step, _pov_meta.size() - 1)]["hop"]) if not _pov_meta.is_empty() else 0
	if hop != _hop_seen:
		_hop_seen = hop
		print("[event] %6.2f  hop%d  %s at %.1f deg r %.2f" % [elapsed(), hop, _runner.name, LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position)])
	if _finish_step >= 0 and step >= _finish_step:
		_finish_step = -1
		print("[event] %6.2f  finish  %s at %.1f deg r %.2f" % [elapsed(), _runner.name, LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position)])
	if _hand == null:
		_raise_the_hand()
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 3 == 0:
		var cam: Camera3D = clip.root.get_viewport().get_camera_3d()
		if cam != null:
			var to: Vector3 = (_runner.global_position + Vector3.UP - cam.global_position).normalized()
			var win: float = rad_to_deg((-cam.global_transform.basis.z).angle_to((_window_eye() - cam.global_position).normalized()))
			say("window off %.1f deg" % win)
			say("aim off %.2f deg fov %.1f in %s h %.2f" % [rad_to_deg((-cam.global_transform.basis.z).angle_to(to)), cam.fov, cam.is_position_in_frustum(_runner.global_position + Vector3.UP), _runner.global_position.y - LIB.DECK_Y])
	_hand.hold_scope = elapsed() >= float(option("zoom_at", 1.2))


func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("guard_deg", 295.0)), float(option("guard_r", 6.2)))
	LIB.open_the_scope(_guard, float(option("clear", 0.74)), float(option("scope_zoom", 0.0)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 0.8))
	var at: float = _hand.start_at
	var miss_by: float = float(option("miss_by", 1.5))
	for raw: String in String(option("misses", "1.9,3.0")).split(",", false):
		var fire: float = float(raw)
		var beat: Dictionary = {"body": _runner, "seconds": fire + WATCH_SECONDS - at, "fire_at": fire - at, "watch": true, "miss_by": miss_by}
		_hand.beats.append(beat)
		at += float(beat["seconds"])
	var drop: float = float(option("drop_at", 0.0))
	if drop > at:
		_hand.beats.append({"body": _runner, "seconds": maxf(float(option("hold_to", 0.0)), drop + 2.0) - at,
			"fire_at": drop - at, "watch": true, "hold": true})
	else:
		_hand.beats.append({"body": _runner, "seconds": 100.0})
	_hand.park = LIB.ring_point(292.0, 52.8, 0.6)
	say("guard at the %.0f window; the hand from %.2f s" % [float(option("guard_deg", 295.0)), _hand.start_at])


func on_hit(collider: Node3D) -> void:
	var lens_cam: Camera3D = clip.root.get_viewport().get_camera_3d()
	if OS.has_environment("STAGE_DEBUG"):
		say("on_hit %s lens %s in %s" % [collider.name, lens_cam.name if lens_cam else "-", lens_cam.is_position_in_frustum(_runner.global_position + Vector3.UP) if lens_cam else false])
	if collider == _runner and lens_cam != null and lens_cam.is_position_in_frustum(_runner.global_position + Vector3.UP):
		print("[event] %6.2f  in_frame  %s" % [elapsed(), _runner.name])


## The POV rides him; a third person lens is not this stage's.
func lens(_delta: float) -> bool:
	return false
