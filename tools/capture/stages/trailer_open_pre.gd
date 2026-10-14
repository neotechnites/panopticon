extends "res://tools/capture/stages/trailer_open.gd"

## The cold open's lead-in (v52): the POV behind the lip rock on 66 deg, the other two run past him, he follows; the
## guard watches the rock, tracks them out unzoomed and settles on the park mark. Spliced onto tape open at its tick 70.

## The open tape's runners entering tick 70 (lead, victim, POV): bearing, radius, deg/s along the ring.
const AT_SPLICE: Array = [[98.2686, 48.4855, 10.203], [94.6818, 49.0468, 10.037], [91.6667, 49.0760, 8.997]]
const AIM_OMEGA: float = 3.4
const AIM_ZETA: float = 0.85
const AIM_MAX_RATE: float = deg_to_rad(70.0)

var _aim := Vector2.ZERO
var _aim_rate := Vector2.ZERO
var _aimed: bool = false
var _seen_at: Vector3 = Vector3.ZERO
var _seen_vel: Vector3 = Vector3.ZERO
var _told: bool = false
var _corpse: PlayerController = null
var _out_at: float = -1.0
var _corpse_at: Vector3 = Vector3.ZERO


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < RADII.size():
		return false
	for index: int in RADII.size():
		if runners[index].controller == null:
			return false
	_start = float(option("start", 90.0))
	var starts: Array[float] = [float(option("b1", 42.0)), float(option("b2", 38.5))]
	var paces: Array[float] = [float(option("s1", 0.74)), float(option("s2", 0.74))]
	for index: int in [0, 1]:
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(starts[index], 49.2, 0.1), "face": LIB.tangent_at(starts[index])},
			{"do": "human", "on": true},
			{"do": "lane", "to": 71.5, "r": 49.2, "speed": paces[index], "weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0},
			{"do": "lane", "to": 165.0, "r": RADII[index], "speed": PACE[index], "weave": WEAVE[index], "period": PERIOD[index], "timeout": 30.0},
			{"do": "hold", "seconds": 60.0},
		], index)
		_bodies.append(runners[index].controller)
	# Behind the rock, eyes up the lane; a look up at the rock, back down the lane at them coming, onto them as they pass.
	var cover: float = float(option("cover", 65.0))
	drive(runners[POV], [
		{"do": "place", "at": LIB.ring_point(cover, 50.5, 0.1), "face": LIB.tangent_at(cover)},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.6, "fidget": true},
		{"do": "glance", "right": -5.0, "pitch": -3.0, "seconds": 0.3},
		{"do": "hold", "seconds": 0.25, "fidget": true},
		{"do": "glance", "right": 28.0, "pitch": 10.0, "seconds": 0.4},
		{"do": "hold", "seconds": 0.2, "fidget": true},
		{"do": "glance", "right": 72.0, "pitch": -12.0, "seconds": 0.4},
		{"do": "hold", "seconds": 0.2, "fidget": true},
		{"do": "glance", "right": -70.0, "pitch": 3.0, "seconds": 0.45},
		{"do": "glance", "right": -30.0, "pitch": -1.0, "seconds": 0.35},
		{"do": "until", "t": float(option("go", 3.18))},
		{"do": "lane", "to": 80.0, "r": 49.6, "speed": float(option("s3", 0.76)), "timeout": 10.0, "carry": true,
			"glances": [{"t": 0.0, "right": 2.0, "pitch": -3.0}, {"t": 0.5, "right": -8.0, "pitch": -2.0}, {"t": 1.1, "right": 6.0, "pitch": -2.0}]},
		{"do": "lane", "to": 165.0, "r": RADII[POV], "speed": PACE[POV], "weave": WEAVE[POV], "period": PERIOD[POV], "timeout": 30.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -2.0}]},
		{"do": "hold", "seconds": 60.0},
	], POV)
	_bodies.append(runners[POV].controller)
	victim_body(_bodies[VICTIM])
	stage_body(_bodies[POV])
	say("trailer_open_pre: POV behind the rock on %.1f, the two from %.1f and %.1f" % [cover, starts[0], starts[1]])
	return true


func tick(delta: float) -> void:
	if _corpse != null and _guard != null:
		_rest_on_the_corpse(delta)
		return
	# From the splice on the tape is the open tape: a write here would be drawn over it before the next tick undoes it.
	if _bodies.is_empty() or (clip._tape != null and int(clip._tape.get("_tick")) >= int(option("splice_tick", 400))):
		return
	if _guard == null:
		var shooter: TowerShooter = LIB.stand_down(seat())
		if shooter == null or shooter.controller == null:
			return
		_guard = shooter.controller
		LIB.guard_to_window(_guard, float(option("window", 115.0)), 5.6)
		LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
	if optic != null and elapsed() < float(option("zoom_at", 1.9)):
		optic.set_zoomed(false)
	_aim_the_guard(delta)
	_bring_them_in()


## Unzoomed: on the rock's end, then the victim as they break from it, then onto the park mark, exact by the splice.
func _aim_the_guard(delta: float) -> void:
	var t: float = elapsed()
	var splice: float = float(option("splice_at", 6.667))
	var park: Vector2 = _angles_to(LIB.ring_point(_start + float(option("park", 10.0)), 49.0, 0.6))
	var edge: Vector2 = _angles_to(LIB.ring_point(float(option("edge", 71.5)), 49.4, 1.0))
	if not _aimed:
		_aim = edge
		_aimed = true
	var victim: PlayerController = _bodies[VICTIM]
	var here: Vector3 = victim.global_position
	if delta > 0.0 and _seen_at != Vector3.ZERO:
		_seen_vel = _seen_vel.lerp((here - _seen_at) / delta, clampf(delta / 0.3, 0.0, 1.0))
	_seen_at = here
	var wanted: Vector2 = edge
	if t >= float(option("watch_until", 4.2)):
		var track: Vector2 = _angles_to(here + Vector3.UP * 1.0 + Vector3(_seen_vel.x, 0.0, _seen_vel.z) * 0.35)
		var w: float = smoothstep(splice - 1.2, splice - 0.45, t)
		wanted = Vector2(track.x + angle_difference(track.x, park.x) * w, lerpf(track.y, park.y, w))
	var sway: float = deg_to_rad(0.18) * (1.0 - smoothstep(splice - 1.0, splice - 0.5, t))
	wanted += Vector2(sin(t * TAU * 0.55) * sway, sin(t * TAU * 0.9 + 1.0) * sway * 0.6)
	var error := Vector2(angle_difference(_aim.x, wanted.x), wanted.y - _aim.y)
	_aim_rate += (error * AIM_OMEGA * AIM_OMEGA - _aim_rate * 2.0 * AIM_ZETA * AIM_OMEGA) * delta
	_aim_rate = _aim_rate.limit_length(AIM_MAX_RATE)
	_aim += _aim_rate * delta
	var q: float = smoothstep(splice - 0.5, splice - 0.15, t)
	var out := Vector2(_aim.x + angle_difference(_aim.x, park.x) * q, lerpf(_aim.y, park.y, q))
	_guard.rotation = Vector3(0.0, out.x, 0.0)
	if _guard.head != null:
		_guard.head.rotation.x = out.y
	_guard.set(&"_pitch", out.y)


## The last of the error to tape open's tick 70 shared over the frames before the splice, then locked on its line.
func _bring_them_in() -> void:
	var t: float = elapsed()
	var splice: float = float(option("splice_at", 6.667))
	var from: float = splice - float(option("nudge", 0.6))
	if t < from or t > splice + 0.1:
		return
	var errors: PackedStringArray = []
	for index: int in AT_SPLICE.size():
		var body: PlayerController = _bodies[index]
		var at: Array = AT_SPLICE[index]
		var want: Vector3 = LIB.ring_point(float(at[0]) - float(at[2]) * (splice - t), float(at[1]))
		var error: Vector3 = Vector3(want.x - body.global_position.x, 0.0, want.z - body.global_position.z)
		if not _told:
			errors.append("%s %.2f m (%.2f deg, r %.2f)" % [body.name, error.length(), float(at[0]) - float(at[2]) * (splice - t) - LIB.bearing_of(body.global_position), float(at[1]) - LIB.radius_of(body.global_position)])
		body.global_position += error / maxf((splice - t) * 60.0 - 6.0, 1.0)
	if not _told:
		_told = true
		say("off the splice line: " + ", ".join(errors))


func _angles_to(point: Vector3) -> Vector2:
	var camera: Node3D = _guard.get_node_or_null(^"Head/Camera") as Node3D
	var eye: Vector3 = camera.global_position if camera != null else _guard.global_position + Vector3.UP * 1.65
	var d: Vector3 = point - eye
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, maxf(Vector2(d.x, d.z).length(), 0.001)))


func on_out(participant: MatchParticipant) -> void:
	super(participant)
	if _corpse == null and participant.body != null:
		_corpse = participant.body
		_out_at = elapsed()


## After the kill the taped pan eases onto where the body lies, so the whole corpse stays inside the scope; drawn, then the tape takes the next tick.
func _rest_on_the_corpse(delta: float) -> void:
	var avatar: PrisonerAvatar = _corpse.get_node_or_null(^"Avatar") as PrisonerAvatar
	var at: Vector3 = avatar.drawn_centre() if avatar != null else _corpse.global_position + Vector3.UP
	_corpse_at = at if _corpse_at == Vector3.ZERO else _corpse_at.lerp(at, clampf(delta / float(option("corpse_lag", 0.15)), 0.0, 1.0))
	var taped := Vector2(_guard.rotation.y, _guard.head.rotation.x if _guard.head != null else 0.0)
	var want: Vector2 = _angles_to(_corpse_at)
	var w: float = smoothstep(0.0, float(option("corpse_ease", 0.5)), elapsed() - _out_at)
	var out := Vector2(taped.x + angle_difference(taped.x, want.x) * w, lerpf(taped.y, want.y, w))
	_guard.rotation = Vector3(0.0, out.x, 0.0)
	if _guard.head != null:
		_guard.head.rotation.x = out.y
	_guard.set(&"_pitch", out.y)
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 6 == 0:
		say("corpse %.2f deg off the taped aim, w %.2f" % [rad_to_deg(Vector2(angle_difference(taped.x, want.x), want.y - taped.y).length()), w])
