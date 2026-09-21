extends Node

## B-roll only: the guard's head driven like a hand on a mouse, for a guard POV.
##
## Ryan: "it should look like a normal person aiming" and "the sniper should
## hit some shots". The tower's own brain is stood down the moment it holds
## the rifle; this node then moves the head through a list of beats -- ease
## onto a runner with a slight overshoot, settle, track him for a moment
## (leading him, so the crosshair sits ON him rather than a step behind),
## squeeze at [code]fire_at[/code], take the recoil and let the same spring
## bring the scope back down onto the drop, then ease off to the next beat.
##
## A beat's [code]lead[/code] (1.0) is the fraction of the round's flight the
## squeeze leads the runner by. It exists because a travelling round can be
## missed, and [code]behind[/code] (0.0) puts the round a fixed number of metres
## back along his own line of travel. Both do nothing while the rifle is hitscan.
## [code]clear[/code] (false) holds the trigger past [code]fire_at[/code] until the
## eye can see both the man and the ground he is led into, for up to CLEAR_WAIT.
##
## [codeblock]
## var hand: Node = GUARD_HAND.new()
## root.add_child(hand)
## hand.install(guard_body, controller)
## hand.beats = [
##     {"body": runner_a, "seconds": 1.7, "fire_at": 1.25},
##     {"body": runner_b, "seconds": 1.7, "fire_at": 1.25, "behind": 2.2},
##     {"at": Vector3, "seconds": 1.0},               # a look at a point, no shot
## ]
## hand.park = Vector3   # where the scope rests until the first beat
## hand.start_at = 1.8   # clip seconds the hand starts moving (install passes the clip clock)
## [/codeblock]
##
## The hand is a second-order response to the aim error: OMEGA sets how quick,
## ZETA under one gives the overshoot a real hand has, and the rate cap is a
## wrist. The breathing sway dies out before the trigger, the way a hand settles
## before it squeezes. Everything is on the guard body's own camera, so the
## scope, the zoom and the vignette are the game's.

const HAND_OMEGA: float = 6.0
const HAND_ZETA: float = 0.7
const HAND_MAX_RATE: float = deg_to_rad(140.0)
const SETTLE_SECONDS: float = 0.35
const RECOIL_PITCH_RATE: float = deg_to_rad(80.0)
const RECOIL_YAW_RATE: float = deg_to_rad(14.0)
const SWAY_DEGREES: float = 0.25
const SWAY_HZ: float = 0.6
const AIM_HEIGHT: float = 1.0
## Seconds the measured target velocity is averaged over before the squeeze reads
## it. Long, because a runner's gait is stop-start: the field and a short window
## both read anything between 0 and 7 m/s, and the round has to be led by the
## speed he is actually covering ground at.
const VELOCITY_WINDOW: float = 0.45
## The short average the steadiness test compares against the long one.
const FAST_WINDOW: float = 0.12
## How far apart those two may be, m/s, and how slowly he may be moving, before
## the hand calls the shot off and waits.
const STEADY_TOLERANCE: float = 1.6
const STEADY_FLOOR: float = 2.0
## Longest a "clear" beat waits for a gap in the columns before it fires anyway.
const CLEAR_WAIT: float = 1.2

var beats: Array = []
var park: Vector3 = Vector3.ZERO
var start_at: float = 0.0
var hold_scope: bool = true

var _guard: PlayerController = null
var _controller: MatchController = null
var _elapsed: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _rate: Vector2 = Vector2.ZERO
var _fired: Array = []
var _last_aim: Array = []
var _installed: bool = false
## Per body: where it was, a slow average of its velocity, and a fast one.
var _seen: Dictionary = {}
var _ray: PhysicsRayQueryParameters3D = null
var _picked: Array = []


## [param clock] is the clip's elapsed time now, so start_at and the log are in clip seconds.
func install(guard: PlayerController, match_controller: MatchController, clock: float = 0.0) -> void:
	_guard = guard
	_controller = match_controller
	_elapsed = clock
	_yaw = _guard.rotation.y
	_pitch = _guard.head.rotation.x if _guard.head != null else 0.0
	_installed = true


func _physics_process(delta: float) -> void:
	if not _installed or _guard == null or not is_instance_valid(_guard):
		return
	_elapsed += delta
	if hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(true)
	var t: float = _elapsed - start_at
	if beats.is_empty() or t < 0.0:
		if park != Vector3.ZERO:
			var angles: Vector2 = _angles_to(park)
			_yaw = angles.x
			_pitch = angles.y
		_rate = Vector2.ZERO
		_apply_head()
		return
	while _last_aim.size() < beats.size():
		_last_aim.append(Vector3.ZERO)
	# Which beat, and how far into it.
	var k: int = 0
	var into: float = t
	while k < beats.size() - 1 and into >= float(beats[k].get("seconds", 1.7)):
		into -= float(beats[k].get("seconds", 1.7))
		k += 1
	var beat: Dictionary = beats[k]
	var fire_at: float = float(beat.get("fire_at", -1.0))
	var body: PlayerController = beat.get("body") as PlayerController
	# from ([]): a beat may name a pool of men instead of one. Until it fires,
	# the hand keeps swinging onto whichever of them is in the open and nearest
	# the line it is already on -- what a player does when the man he was on
	# ducks behind a column. With live brains on the lap nobody can be promised
	# to be anywhere, so a beat that names one body alone will sooner or later
	# hold its shot on a man who is not coming out.
	var pool: Array = beat.get("from", [])
	var entry: Variant = null
	if not pool.is_empty():
		while _picked.size() < beats.size():
			_picked.append(null)
		# acquire (0.0): how long before fire_at the hand is allowed to come onto
		# this beat's man. It matters because the men watch the rifle: hold a
		# scope on a prisoner for three seconds and he breaks for cover, which
		# is exactly the thing a lead cannot predict. Coming on late and firing
		# inside his reaction time is how the shot lands -- and it is what a
		# player does.
		var acquire: float = float(beat.get("acquire", 0.0))
		if not _fired.has(k) and (acquire <= 0.0 or fire_at < 0.0 or into >= fire_at - acquire):
			_picked[k] = _pick_from(pool, _picked[k])
		entry = _picked[k]
		if entry != null:
			body = _body_of(entry)
	var aim: Vector3
	if _fired.has(k) or body == null or not is_instance_valid(body):
		aim = _last_aim[k] if _last_aim[k] != Vector3.ZERO else beat.get("at", park)
	else:
		aim = body.global_position + Vector3.UP * AIM_HEIGHT
		_last_aim[k] = aim
		# Tracking a runner is aiming where he is going: the lead cancels the
		# second-order lag, so once the hand has settled the crosshair sits on him.
		var lag_seconds: float = 2.0 * HAND_ZETA / HAND_OMEGA
		aim += Vector3(body.velocity.x, 0.0, body.velocity.z) * lag_seconds
	# The lead is taken from a velocity MEASURED off the body between frames, not
	# from PlayerController.velocity: read from outside the controller's own tick
	# that field is zero on most frames, so a round led by it is led by nothing.
	# Every man in the beat is measured, every frame, not just the one the hand
	# is on -- the hand swings between them, and a lead taken off an estimate
	# that started when the swing did is a lead of zero.
	_measure(body, delta)
	for one: Variant in pool:
		_measure(_body_of(one), delta)
	var wanted: Vector2 = _angles_to(aim)
	if not _fired.has(k):
		var settling: float = 1.0 if fire_at < 0.0 else clampf((fire_at - into) / SETTLE_SECONDS, 0.0, 1.0)
		var sway: float = deg_to_rad(SWAY_DEGREES) * settling
		wanted += Vector2(sin(t * TAU * SWAY_HZ) * sway, sin(t * TAU * SWAY_HZ * 1.7 + 1.0) * sway * 0.6)
	var error := Vector2(angle_difference(_yaw, wanted.x), wanted.y - _pitch)
	var accel: Vector2 = error * (HAND_OMEGA * HAND_OMEGA) - _rate * (2.0 * HAND_ZETA * HAND_OMEGA)
	_rate += accel * delta
	_rate = _rate.limit_length(HAND_MAX_RATE)
	_yaw = wrapf(_yaw + _rate.x * delta, -PI, PI)
	_pitch += _rate.y * delta
	if body != null and is_instance_valid(body) and fire_at >= 0.0 and not _fired.has(k) and into >= fire_at:
		# clear (false): hold the trigger until the shot is actually there -- the
		# man in the open AND the ground he is being led into in the open. On a
		# deck of columns a runner is visible about half the time, in windows a
		# couple of frames long, so a trigger on the clock alone fires at whoever
		# happens to be behind a rock that frame: it is why one beat killed on one
		# take and put the round in the wall on the next, off a 0.02 s difference.
		# Capped by CLEAR_WAIT so a take can never hang waiting for a gap.
		if bool(beat.get("clear", false)) and into < fire_at + CLEAR_WAIT and not _shot_is_there(beat, body, entry):
			_apply_head()
			return
		_fired.append(k)
		# The last of the error goes in the squeeze: the crosshair is on him,
		# led by the round's flight time when the shot travels.
		var mark: Vector3 = _mark_for(beat, body)
		var exact: Vector2 = _angles_to(mark)
		_yaw = exact.x
		_pitch = exact.y
		_apply_head()
		_fire(k)
		# The kick lands the frame after the shot line is resolved.
		_rate = Vector2(RECOIL_YAW_RATE * (1.0 if k % 2 == 0 else -1.0), RECOIL_PITCH_RATE)
		return
	_apply_head()


## Pull the trigger with the head already on the runner. Hitscan: the rifle's
## own ray decides, along the eye it is aimed from.
func _fire(k: int) -> void:
	var rifle: Rifle = _controller.rifle
	if rifle == null:
		printerr("[event] %6.2f  no rifle to fire on beat %d" % [_elapsed, k])
		return
	if not rifle.can_fire():
		printerr("[event] %6.2f  rifle not ready (%s) on beat %d" % [_elapsed, rifle.get_state_name(), k])
		return
	var ok: bool = rifle.try_fire()
	print("[event] %6.2f  hand  beat %d %s" % [_elapsed, k, "fired" if ok else "REFUSED"])


func _eye_position() -> Vector3:
	var camera: Node3D = _guard.get_node_or_null(^"Head/Camera") as Node3D
	return camera.global_position if camera != null else _guard.global_position + Vector3.UP * 1.65


## Yaw and pitch that put the head on [param point], in the controller's own convention.
func _angles_to(point: Vector3) -> Vector2:
	var d: Vector3 = point - _eye_position()
	var flat: float = Vector2(d.x, d.z).length()
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, maxf(flat, 0.001)))


## Where this beat's round is actually sent: his chest, led by the round's flight
## when the shot travels, then pushed back along his line of travel by
## [code]behind[/code] metres when the beat wants a miss of a fixed size.
func _mark_for(beat: Dictionary, body: PlayerController) -> Vector3:
	var mark: Vector3 = body.global_position + Vector3.UP * AIM_HEIGHT
	var shot_speed: float = _controller.rifle.get_shot_speed() if _controller.rifle != null else 0.0
	if shot_speed <= 0.0:
		return mark
	# lead (1.0): how much of the round's flight the squeeze leads by. At 0.0 the
	# shot goes where he IS -- which a travelling round reaches after he has left
	# it, so it crosses behind him and the miss is one you can read. Only the
	# squeeze is scaled; the tracking crosshair still sits on him.
	var flight: float = mark.distance_to(_eye_position()) / shot_speed
	var along: Vector3 = _velocity_of(body)
	mark += along * flight * float(beat.get("lead", 1.0))
	# behind (0.0): metres the round is put behind him on purpose, along his own
	# line of travel. A miss has to be a fixed size to be filmed: scaling the
	# lead instead makes the miss whatever his gait happened to be doing at the
	# squeeze, which is anything from 0.8 to 1.6 m and lands on him as often as
	# not.
	var behind: float = float(beat.get("behind", 0.0))
	if behind != 0.0 and along.length_squared() > 0.0001:
		mark -= along.normalized() * behind
	return mark


## A pool entry is either the body itself or the brain playing it: a stage that
## wants the hand to respect what a man is DOING hands over brains.
func _body_of(entry: Variant) -> PlayerController:
	var brain: RunnerBrain = entry as RunnerBrain
	if brain != null:
		return brain.controller
	return entry as PlayerController


## Fold this frame's movement of [param body] into its two running averages.
func _measure(body: PlayerController, delta: float) -> void:
	if body == null or not is_instance_valid(body) or delta <= 0.0:
		return
	var key: int = body.get_instance_id()
	var here: Vector3 = body.global_position
	if not _seen.has(key):
		_seen[key] = {"at": here, "slow": Vector3.ZERO, "fast": Vector3.ZERO}
		return
	var row: Dictionary = _seen[key]
	var step: Vector3 = (here - row["at"]) / delta
	row["at"] = here
	row["slow"] = (row["slow"] as Vector3).lerp(step, clampf(delta / VELOCITY_WINDOW, 0.0, 1.0))
	row["fast"] = (row["fast"] as Vector3).lerp(step, clampf(delta / FAST_WINDOW, 0.0, 1.0))


## The velocity the lead is taken from: the slow average, flattened.
func _velocity_of(body: PlayerController) -> Vector3:
	if body == null or not _seen.has(body.get_instance_id()):
		return Vector3.ZERO
	var slow: Vector3 = _seen[body.get_instance_id()]["slow"]
	return Vector3(slow.x, 0.0, slow.z)


## True when he is running the same way he was: the fast average and the slow
## one agree. A lead is a prediction, and a prediction only holds while he is
## not changing his mind -- a man breaking for cover or juking off a round that
## just landed is the one case where the round arrives where he WAS going. It is
## also when a player would not take the shot.
func _running_steady(body: PlayerController) -> bool:
	if body == null or not _seen.has(body.get_instance_id()):
		return false
	var row: Dictionary = _seen[body.get_instance_id()]
	var slow: Vector3 = row["slow"]
	var fast: Vector3 = row["fast"]
	if Vector2(slow.x, slow.z).length() < STEADY_FLOOR:
		return false
	return Vector2(fast.x - slow.x, fast.z - slow.z).length() <= STEADY_TOLERANCE


## The man this beat should be on right now: of [param pool], the one the eye
## can see that is nearest the line the hand already holds. [param current] is
## kept when nobody is in the open, so the hand stays where it was rather than
## snapping about between rocks.
func _pick_from(pool: Array, current: Variant) -> Variant:
	var best: Variant = null
	var best_error: float = INF
	for entry: Variant in pool:
		var body: PlayerController = _body_of(entry)
		if body == null or not is_instance_valid(body) or not _can_see(body):
			continue
		var to: Vector2 = _angles_to(body.global_position + Vector3.UP * AIM_HEIGHT)
		var error: float = absf(angle_difference(_yaw, to.x)) + absf(to.y - _pitch)
		if error < best_error:
			best_error = error
			best = entry
	if best == null:
		return current
	return best


## True when nothing stands between the eye and his chest.
func _can_see(body: PlayerController) -> bool:
	_ready_ray()
	_ray.exclude = [_guard.get_rid(), body.get_rid()]
	_ray.from = _eye_position()
	_ray.to = body.global_position + Vector3.UP * AIM_HEIGHT
	return _guard.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func _ready_ray() -> void:
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collide_with_areas = false


## True when the eye can see both the man and the point the round is being sent
## to. One query object, reused: this runs every frame of the hold.
func _shot_is_there(beat: Dictionary, body: PlayerController, entry: Variant = null) -> bool:
	_ready_ray()
	var space: PhysicsDirectSpaceState3D = _guard.get_world_3d().direct_space_state
	var eye: Vector3 = _eye_position()
	_ray.exclude = [_guard.get_rid(), body.get_rid()]
	_ray.from = eye
	_ray.to = body.global_position + Vector3.UP * AIM_HEIGHT
	if not space.intersect_ray(_ray).is_empty():
		return false
	_ray.from = eye
	_ray.to = _mark_for(beat, body)
	if not space.intersect_ray(_ray).is_empty():
		return false
	# A man who is breaking for cover, mid-jump or juking off the last round is
	# the one who will not be where the lead says. His own brain knows which he
	# is doing, so ask it rather than guess from the velocity.
	var brain: RunnerBrain = entry as RunnerBrain
	if brain != null and brain.get_state() != RunnerBrain.State.RUN:
		return false
	return _running_steady(body)


func _apply_head() -> void:
	_guard.rotation = Vector3(0.0, _yaw, 0.0)
	if _guard.head != null:
		_guard.head.rotation.x = _pitch
	# The controller keeps its own pitch and would snap the head back to it on
	# the next look input; kept in step so nothing ever arrives to undo this.
	_guard.set(&"_pitch", _pitch)
