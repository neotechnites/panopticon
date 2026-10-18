extends "res://tools/capture/stages/stage.gd"

## pill_twin: the pill_era take (c4943a47 run_clip) shot for shot on the current map: three abreast on three lanes, the
## outer man held 1.0 s; the hand parks 4 deg left of the pack, beats from 0.9 (drop mid 2.05), 2.6 (drop inner 4.45), 4.9.
## [code]--stage=pill_twin --shot=s3_open_lane --map=forest|bentham_ring --pov=guard|runner --bots=3 --set=window=32[/code]
## Dials: window (32), eye_r (4.4), start (35.5 deg at 0.6 s), lanes (48.5,51.5,54.5), pace (0.73: 8 m/s, the pill walk),
## scope_fov (28), pov_fov (70), look (pov glance right, deg; 12), drop_mid (2.05), drop_in (4.45), hold (1.0), inner_ahead (0 m), veer.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

const INNER: int = 0
const MID: int = 1
const SPARE: int = 2
## Pill: a walk of 8 m/s for 0.6 s (12 m/s2 from rest) puts the two leaders 2.2 m up the lane at the cast.
const LEAD_METRES: float = 2.2
const PILL_WALK: float = 8.0

var _bodies: Array[PlayerController] = []
var _hand: Node = null
var _kick: int = 0
var _start: float = 35.5
var _radii: PackedFloat64Array = PackedFloat64Array()
var _vignette: Node = null


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.guard_projectile_speed = 0.0
	rules.bots_shove_rivals = false
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
	_layout()
	var pace: float = float(option("pace", 0.73))
	for index: int in 3:
		var r: float = _radii[index]
		var deg: float = _start if index == SPARE else _start + rad_to_deg(LEAD_METRES / r)
		if index == INNER:
			# inner_ahead (m): the pill's inner lane gains 2.2 m on the mid by the drop; tighter lanes start him that far up.
			deg += rad_to_deg(float(option("inner_ahead", 0.0)) / r)
		var lane: Dictionary = {"do": "lane", "to": _start + 120.0, "r": r, "speed": pace, "weave": 0.06, "period": 1.4, "timeout": 30.0}
		var steps: Array = [{"do": "place", "at": LIB.ring_point(deg, r, 0.1), "face": LIB.tangent_at(deg)}]
		if index == SPARE:
			steps.append({"do": "human", "on": true})
			# The pill's spare: held 1.0 s of take time, then his lane, his head eased onto the nearest mate.
			steps.append({"do": "until", "t": float(option("hold", 1.0)) - 0.6})
			lane["glances"] = [{"t": 0.0, "right": float(option("look", 12.0)), "pitch": -1.0}]
		var veer: PackedStringArray = String(option("veer", "")).split(",")
		if index == INNER and veer.size() == 2:
			# veer ("deg,r"): the inner man steps out to r at deg, round a rock on his lane (hell's 066 lip).
			var out: Dictionary = lane.duplicate()
			lane["to"] = float(veer[0])
			out["r"] = float(veer[1])
			steps.append(lane)
			lane = out
		steps.append(lane)
		steps.append({"do": "hold", "seconds": 60.0, "fidget": true})
		drive(runners[index], steps, index, "ClipPillTwin%d" % index)
		_bodies.append(runners[index].controller)
	victim_body(_bodies[MID])
	stage_body(_bodies[SPARE])
	say("pill_twin: inner %s, mid %s, spare %s; start %.1f deg, lanes %s, pace %.2f" % [_bodies[INNER].name, _bodies[MID].name, _bodies[SPARE].name, _start, str(_radii), pace])
	return true


func _layout() -> void:
	_start = float(option("start", 35.5))
	_radii = PackedFloat64Array()
	for part: String in String(option("lanes", "48.5,51.5,54.5")).split(","):
		_radii.append(float(part))


func tick(_delta: float) -> void:
	# The scope is up and parked before the first frame the cut plays (0.6), as the pill's tower player is.
	if _hand == null:
		_raise_the_hand()
	elif _vignette == null:
		_vignette = LIB.find_kind(clip.root, "ScopeVignette")
	if _vignette != null:
		# The vignette re-reads the opened profile every frame (as forest_rush), or it keeps the shipped small disc.
		_vignette.set(&"_applied", -1.0)
	var guard: PlayerController = _hand.get(&"_guard") if _hand != null else null
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic if guard != null else null
	if optic != null and not optic.is_fully_zoomed():
		# The pill's lens is at fov 28 from the first frame: no zoom-in on screen (hell's 0.6 s transition ran into the cut).
		optic.set_zoomed(true)
		optic.tick(1.0)
	if _bodies.is_empty():
		return
	if _hand != null and _hand.beats.is_empty():
		_plan_beats()
	if _kick < 4:
		# The pill's leaders are already walking at the cast: their first frames carry the walk, not a standing start.
		_kick += 1
		for index: int in [INNER, MID]:
			var body: PlayerController = _bodies[index]
			var deg: float = LIB.bearing_of(body.global_position)
			body.velocity = LIB.tangent_at(deg) * PILL_WALK
	var eye: Camera3D = _bodies[SPARE].get_node_or_null(^"Head/Camera") as Camera3D
	if eye != null:
		eye.fov = float(option("pov_fov", 70.0))
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		var line: String = ""
		for body: PlayerController in _bodies:
			line += " %s %.1f/%.2f v%.1f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), Vector2(body.velocity.x, body.velocity.z).length()]
		say("at" + line)
	if OS.has_environment("PILL_PROBE") and Engine.get_physics_frames() % 6 == 0 and eye != null:
		_probe_view(eye)


func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	LIB.guard_to_window(guard, float(option("window", 32.0)), float(option("eye_r", 4.4)))
	LIB.open_the_scope(guard, 0.74)
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic
	var fov: float = float(option("scope_fov", 28.0))
	if optic != null and optic.profile != null and optic.base_fov > 0.0:
		optic.profile.zoom_factor = clampf(fov / optic.base_fov, 0.05, 1.0)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.start_at = 0.9
	_layout()
	# Parked like the pill hand: the pack's middle, 4 deg left and 1.5 deg low.
	var eye: Vector3 = guard.global_position + Vector3.UP * 1.6
	var pack: Vector3 = LIB.ring_point(_start + 1.5, _radii[MID], 1.05)
	var at: Vector3 = eye + (pack - eye).rotated(Vector3.UP, deg_to_rad(4.0))
	at.y -= tan(deg_to_rad(1.5)) * Vector2(at.x - eye.x, at.z - eye.z).length()
	_hand.park = at
	say("pill_twin: hand on %s at the %.0f deg window from 0.90 s" % [guard.name, float(option("window", 32.0))])


func _plan_beats() -> void:
	var drop_mid: float = float(option("drop_mid", 2.05))
	var drop_in: float = float(option("drop_in", 4.45))
	# The pill's beats: on the mid man from 0.9, held on him to 2.6; the inner man to 4.9; then the spare, never fired on.
	_hand.beats.append({"body": _bodies[MID], "seconds": 2.6 - 0.9, "fire_at": drop_mid - 0.9, "watch": true})
	_hand.beats.append({"body": _bodies[INNER], "seconds": 4.9 - 2.6, "fire_at": drop_in - 2.6, "watch": true})
	_hand.beats.append({"body": _bodies[SPARE], "seconds": 100.0})


func on_hit(collider: Node3D) -> void:
	var lens: Camera3D = clip.root.get_viewport().get_camera_3d()
	for body: PlayerController in _bodies:
		if body != collider or lens == null:
			continue
		var to: Vector3 = (body.global_position + Vector3.UP) - lens.global_position
		var fwd: Vector3 = -lens.global_transform.basis.z
		say("%s from the view: %.1f m, %.1f deg right, at %.1f deg r %.2f" % [body.name, to.length(),
			rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))), LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position)])
		if lens.is_position_in_frustum(body.global_position + Vector3.UP):
			print("[event] %6.2f  in_frame  %s" % [elapsed(), body.name])


## PILL_PROBE=1: the POV's 9:16 frame as a 9x16 ray grid: the share blocked by a wall/trunk within 8 m, and the mid man seen or not.
func _probe_view(eye: Camera3D) -> void:
	var space: PhysicsDirectSpaceState3D = eye.get_world_3d().direct_space_state
	var half_y: float = tan(deg_to_rad(eye.fov) * 0.5)
	var half_x: float = half_y * 9.0 / 16.0
	var blocked: int = 0
	for gx: int in 9:
		for gy: int in 16:
			var dir: Vector3 = eye.global_basis * Vector3(((gx + 0.5) / 9.0 * 2.0 - 1.0) * half_x, (1.0 - (gy + 0.5) / 16.0 * 2.0) * half_y, -1.0).normalized()
			var q := PhysicsRayQueryParameters3D.create(eye.global_position, eye.global_position + dir * 8.0)
			q.exclude = [_bodies[SPARE].get_rid()]
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty() and (hit["normal"] as Vector3).y < 0.7 and not (hit["collider"] is PlayerController):
				blocked += 1
	var mid: PlayerController = _bodies[MID]
	var seen: String = "-"
	if is_instance_valid(mid):
		var q2 := PhysicsRayQueryParameters3D.create(eye.global_position, mid.global_position + Vector3.UP * 1.2)
		q2.exclude = [_bodies[SPARE].get_rid(), mid.get_rid()]
		seen = "seen" if space.intersect_ray(q2).is_empty() else "HIDDEN"
	say("view blocked %.2f, mid %s" % [blocked / 144.0, seen])
