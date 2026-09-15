extends Node

## B-roll only: drives one prisoner by hand through a list of steps, for a clip.
## Nothing here is reachable from a match.
##
## The vocabulary (every primitive the shove short proved; see
## tools/capture/stages/README.md for the stages built out of them):
## [codeblock]
## {"do": "place", "at": Vector3, "face": Vector3}                # or "deg", "r", "h" (ring polar)
## {"do": "hold", "seconds": 2.0, "crouch": true, "sway": 14.0, "period": 2.6, "fidget": true}
## {"do": "until", "t": 8.0, "crouch": false}   # hold until the driver's clock reads t (a timed beat)
## {"do": "run", "to": Vector3, "weave": 0.9, "period": 1.1, "hop": 1.6, "within": 0.6, "timeout": 8.0, "speed": 1.0, "look_at": Vector3}
## {"do": "lane", "to": deg, "r": 52.0, "dir": 1, "speed": 1.0, ...run's weave/period/hop}   # along the ring; dir -1 runs it backwards
##     ... "glances": [{"t": 0.7, "right": -52.0, "pitch": -4.0}, ...], "flinch_on": "hit"   # look around while running (see _gaze)
## {"do": "leap", "to": Vector3, "speed": 8.0, "lock": 0.9}
## {"do": "land", "look_at": Vector3, "look_ahead": Vector3, "ahead_until": 0.3, "correct": 5.0, "stick_after": 0.3}
## {"do": "wait_launch", "timeout": 6.0}        # until the body is thrown off the floor
## {"do": "shove_when", "victim": PlayerController, "range": 3.0, "timeout": 12.0, "face": Vector3}   # the tick they are airborne in reach
## {"do": "chase", "victim": PlayerController, "range": 2.5, "timeout": 10.0, "speed": 1.0}   # run at them, shove in reach
## {"do": "shove", "face": Vector3}              # tap it now, turned to face first (a beat)
## {"do": "face_hold", "victim": PlayerController, "seconds": 3.0}   # square to them until thrown
## {"do": "advance", "victim": PlayerController, "speed": 0.3, "sway": 0.35, "until": 4.0, "timeout": 6.0}   # walk at them to a range
## {"do": "brawl", "others": Array, "safe": {"from": deg, "to": deg, "r_min": f, "r_max": f}, "seconds": 8.0}
## {"do": "ability", "slot": 2}
## {"do": "pitch", "down": 12.0, "seconds": 0.0}
## {"do": "turn", "degrees": -140.0, "seconds": 0.5}   # yaw the body over seconds; positive is to its right
## {"do": "glance", "right": -52.0, "pitch": -4.0, "seconds": 0.4}   # a turn and a pitch together
## {"do": "look_back", "degrees": -140.0, "seconds": 0.42, "hold": 0.3, "back": 0.6}   # over the shoulder and back
## {"do": "hesitate", "seconds": 0.3}            # a fidgeting pause, its length jittered
## {"do": "flinch", "right": 22.0}               # a jerk, a look over the shoulder, eyes front (macro)
## {"do": "wait_flag", "flag": "shot", "timeout": 6.0}   # until the stage raises the flag
## {"do": "steer", "on": true, "rate": 720.0, "gain": 14.0}   # yaw through the mouse, not snapped
## {"do": "human", "on": true}    # mouse drift, eased turns with an overshoot and settle, a wavering walk, fidget on holds
## {"do": "slowfeet", "floor": 0.5}              # a private movement profile whose friction floor lets it creep
## {"do": "release"}     # hand the body back to its own brain
## [/codeblock]
##
## Every step may carry "look_at" (a point the head eases onto) or "look_down"
## (degrees) once "steer" is on. Timing under the human layer is seeded per
## body ([method seed_with]) so a group never moves in lockstep.

const FALLBACK_GRAVITY: float = 22.0

var _body: PlayerController = null
var _brain: RunnerBrain = null
var _match: MatchController = null
var _steps: Array = []
var _index: int = 0
var _clock: float = 0.0
var _total: float = 0.0             # seconds since install: the "until" clock
var _hop_clock: float = 0.0
var _intent: MoveIntent = MoveIntent.new()
var _released: bool = false
var _flags: Dictionary = {}
## The human layer (see the "human" step): a seeded random walk on the look,
## a wavering walk speed and the occasional strafe tap while standing.
var _human: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _drift: Vector2 = Vector2.ZERO      # look velocity, degrees per second (yaw, pitch)
var _sway: float = 0.0                  # strafe wobble while walking
var _fidget_next: float = 0.0
var _fidget_until: float = 0.0
var _fidget_move: Vector2 = Vector2.ZERO
## The steering layer: with it on, _face no longer snaps the body's yaw but
## turns it through the intent's look_delta at a capped rate, the way a hand on
## a mouse would, and a step may carry a "look_at" point or a "look_down" angle
## the head eases onto.
var _steer: bool = false
var _steer_rate: float = 720.0          # degrees per second, the wrist's cap
var _steer_gain: float = 14.0           # per second, how hard the error is chased
var _pitch_goal: float = 0.0            # degrees down the head is easing onto
var _has_pitch_goal: bool = false
var _pitch_rate: float = 200.0
var _pitch_gain: float = 9.0
var _dt: float = 1.0 / 60.0
## A mid-air correction: a small yaw flick partway through a flight ("land").
var _correction: float = 0.0
var _correction_done: float = 0.0
## The gaze while running: a schedule of glances (yaw and pitch offsets from
## the direction of travel, degrees) chased by an underdamped spring, so every
## turn of the head accelerates, overshoots a little and settles -- never a
## constant-rate turn -- while the feet keep to the lane. From the pack POV.
const GAZE_OMEGA: float = 15.0
const GAZE_ZETA: float = 0.5
const GAZE_STRAFE_LAG: float = 0.15
var _gaze: Vector2 = Vector2.ZERO          # yaw, pitch offsets, radians
var _gaze_rate: Vector2 = Vector2.ZERO
var _gaze_target: Vector2 = Vector2.ZERO
var _gaze_strafe: float = 0.0
var _gaze_strafe_target: float = 0.0
var _gaze_index: int = 0
var _gaze_step_index: int = 0
var _gaze_schedule: Array = []
var _gaze_strafes: Array = []
var _gaze_flinched: bool = false
## brawl: this body's own cadence.
var _brawl_target: PlayerController = null
var _brawl_reach: float = 2.2
var _brawl_ready_at: float = 0.0
var _brawl_seen_at: float = -1.0
var _brawl_reaction: float = 0.1
var _brawl_circle: float = 1.0
## A human turn: fast out of the gate, past the mark, and back onto it.
const TURN_OVERSHOOT: float = 1.06
const TURN_FLICK_SHARE: float = 0.72
## Mouse drift, in degrees per second of standard deviation around zero.
const DRIFT_YAW: float = 2.4
const DRIFT_PITCH: float = 1.6
const DRIFT_RETURN: float = 2.5


## Take [param body] off [param brain] and start on [param steps]. [param match]
## lets chase read the shove cooldown off the participant instead of wasting a tap.
func install(body: PlayerController, brain: RunnerBrain, steps: Array, match_controller: MatchController = null) -> void:
	_body = body
	_brain = brain
	_match = match_controller
	_steps = expand(steps)
	# Seeded off the take's own RNG (run_clip seeds it), so a seed is a take.
	_rng.seed = hash(body.name) ^ randi()
	if _brain != null:
		_brain.process_mode = Node.PROCESS_MODE_DISABLED
	_body.intent_source = null


## Give this body its own timing: the take seed and its index in the group, so
## five bodies given the same steps never swing on the same tick.
func seed_with(take_seed: int, index: int) -> void:
	_rng.seed = take_seed * 7 + index


func is_done() -> bool:
	return _released or _index >= _steps.size()


## Seconds since install, the clock "until" reads.
func clock() -> float:
	return _total


func body() -> PlayerController:
	return _body


## The stage saw something (a shot, a shove): a "wait_flag" step on it finishes.
func flag(flag_name: String) -> void:
	_flags[flag_name] = true


func _physics_process(delta: float) -> void:
	if _released or _body == null or not is_instance_valid(_body):
		return
	_dt = delta
	_total += delta
	_intent.clear()
	if _index >= _steps.size():
		_body.set_intent(_intent)
		return
	var step: Dictionary = _steps[_index]
	_clock += delta
	if step.has("look_down"):
		_pitch_goal = float(step["look_down"])
		_has_pitch_goal = true
	elif step.has("look_at"):
		_pitch_goal = _pitch_to(step["look_at"] as Vector3)
		_has_pitch_goal = true
	var finished: bool = false
	match String(step["do"]):
		"place":
			_body.global_position = step["at"] if step.has("at") else ring_point(float(step["deg"]), float(step["r"]), float(step.get("h", 0.1)))
			_body.velocity = Vector3.ZERO
			_snap_face(step.get("face", _tangent_at(_body.global_position)))
			finished = true
		"steer":
			_steer = bool(step.get("on", true))
			_steer_rate = float(step.get("rate", 720.0))
			_steer_gain = float(step.get("gain", 14.0))
			_pitch_rate = float(step.get("pitch_rate", 200.0))
			_pitch_gain = float(step.get("pitch_gain", 9.0))
			finished = true
		"run":
			finished = _run(step, delta, step["to"], float(step.get("within", 0.6)))
		"lane":
			finished = _lane(step, delta)
		"leap":
			_leap(step["to"], float(step.get("speed", 8.0)), float(step.get("lock", 0.9)))
			finished = true
		"land":
			_in_flight(step, delta)
			finished = _clock > 0.15 and _body.is_on_floor()
		"wait_launch":
			finished = not _body.is_on_floor() or _clock > float(step.get("timeout", 6.0))
		"hold":
			_hold(step, delta)
			finished = _clock >= float(step.get("seconds", 1.0))
		"until":
			_hold(step, delta)
			finished = _total >= float(step.get("t", 0.0))
		"hesitate":
			# A pause before the next thing, never the same length twice.
			if not step.has("_seconds"):
				step["_seconds"] = float(step.get("seconds", 0.3)) * _rng.randf_range(0.7, 1.4)
			step["fidget"] = true
			_hold(step, delta)
			finished = _clock >= float(step["_seconds"])
		"human":
			_human = bool(step.get("on", true))
			finished = true
		"shove_when":
			finished = _shove_when(step)
		"chase":
			finished = _chase(step)
		"shove":
			var facing: Vector3 = step.get("face", Vector3.ZERO) as Vector3
			if step.has("victim") and is_instance_valid(step["victim"]):
				facing = (step["victim"] as Node3D).global_position - _body.global_position
				facing.y = 0.0
			if facing.length_squared() > 0.0:
				_snap_face(facing.normalized())
			_intent.shove_pressed = true
			finished = true
		"face_hold":
			finished = _face_hold(step)
		"advance":
			finished = _advance(step, delta)
		"brawl":
			finished = _brawl(step, delta)
		"ability":
			_intent.ability_slot = int(step.get("slot", 2))
			finished = true
		"turn", "glance":
			# PlayerController yaws by -look_delta.x: a positive turn is to the right.
			var over_turn: float = float(step.get("seconds", 0.0))
			var share: float = _share(over_turn, delta)
			var by: float = deg_to_rad(float(step.get("degrees", step.get("right", 0.0)))) * share
			var up: float = deg_to_rad(float(step.get("pitch", 0.0))) * share
			var inverted_look: bool = _body.profile != null and _body.profile.invert_look_y
			_intent.look_delta = Vector2(by, up if inverted_look else -up)
			if step.has("strafe"):
				_intent.move_direction = Vector2(float(step["strafe"]), 0.0)
			finished = _clock >= over_turn
		"pitch":
			# PlayerController pitches by -look_delta.y (unless the profile inverts).
			var over: float = float(step.get("seconds", 0.0))
			var down: float = deg_to_rad(float(step.get("down", 0.0))) * _share(over, delta)
			var inverted: bool = _body.profile != null and _body.profile.invert_look_y
			_intent.look_delta = Vector2(0.0, -down if inverted else down)
			finished = _clock >= over
		"wait_flag":
			finished = _flags.get(String(step.get("flag", "")), false) or _clock > float(step.get("timeout", 10.0))
		"slowfeet":
			_slow_the_feet(float(step.get("floor", 0.5)))
			finished = true
		"release":
			_release()
			return
		_:
			finished = true
	if _steer and _has_pitch_goal and _body.head != null:
		var down_now: float = -rad_to_deg(_body.head.rotation.x)
		var err: float = _pitch_goal - down_now
		var by_pitch: float = clampf(err * _pitch_gain * delta, -_pitch_rate * delta, _pitch_rate * delta)
		var inverted_pitch: bool = _body.profile != null and _body.profile.invert_look_y
		_intent.look_delta.y += deg_to_rad(-by_pitch if inverted_pitch else by_pitch)
	if _human:
		_intent.look_delta += _mouse_drift(delta)
	_body.set_intent(_intent)
	if finished:
		if OS.has_environment("STAGE_DEBUG"):
			print("[step] %s done for %s at r %.2f (%.2fs, clock %.2f)" % [step["do"], _body.name, Vector2(_body.global_position.x, _body.global_position.z).length(), _clock, _total])
		_index += 1
		_clock = 0.0
		_hop_clock = 0.0


# --- Macros -------------------------------------------------------------------

## The composite steps, written out in the primitives. Static, so a stage can
## read what a macro does.
static func expand(steps: Array) -> Array:
	var out: Array = []
	for step: Dictionary in steps:
		match String(step["do"]):
			"look_back":
				# Over the shoulder (left by default), a beat, and back. Ryan:
				# "have the player look back and then get shoved off the edge".
				var degrees: float = float(step.get("degrees", -140.0))
				out.append({"do": "turn", "degrees": degrees, "seconds": float(step.get("seconds", 0.42))})
				out.append({"do": "hold", "seconds": float(step.get("hold", 0.3))})
				out.append({"do": "turn", "degrees": -degrees, "seconds": float(step.get("back", 0.6))})
			"flinch":
				# The one beside us dropped: a jerk away and up, a look back over
				# the shoulder at where they fell, a step away, then eyes front.
				var right: float = float(step.get("right", 22.0))
				var side: float = signf(right) if right != 0.0 else 1.0
				out.append({"do": "glance", "right": right, "pitch": 4.0, "seconds": 0.12})
				out.append({"do": "glance", "right": side * 18.0, "pitch": -7.0, "seconds": 0.2, "strafe": -side * 0.22})
				out.append({"do": "glance", "right": side * 84.0, "pitch": -9.0, "seconds": 0.5})
				out.append({"do": "hold", "seconds": float(step.get("look", 0.55)), "fidget": true})
				out.append({"do": "glance", "right": -side * 128.0, "pitch": 11.0, "seconds": 0.55})
				out.append({"do": "glance", "right": side * 4.0, "pitch": 1.0, "seconds": 0.4})
			_:
				out.append(step)
	return out


# --- The human layer ----------------------------------------------------------

## The share of a timed look this tick delivers: a flat rate when scripted, and
## when human a flick -- an ease-out to a little past the mark over most of the
## time, then a settle back onto it.
func _share(over: float, delta: float) -> float:
	if over <= 0.0:
		return 1.0 if _clock - delta <= 0.0 else 0.0
	var u1: float = clampf(_clock / over, 0.0, 1.0)
	var u0: float = clampf((_clock - delta) / over, 0.0, 1.0)
	if not _human:
		return u1 - u0
	return _flick(u1) - _flick(u0)


static func _flick(u: float) -> float:
	if u < TURN_FLICK_SHARE:
		var v: float = u / TURN_FLICK_SHARE
		return TURN_OVERSHOOT * (1.0 - pow(1.0 - v, 3.0))
	var w: float = (u - TURN_FLICK_SHARE) / (1.0 - TURN_FLICK_SHARE)
	return TURN_OVERSHOOT - (TURN_OVERSHOOT - 1.0) * (1.0 - pow(1.0 - w, 2.0))


## A hand on a mouse is never still: the look velocity random-walks around zero
## and is pulled back to it, so the view wanders a degree or two and no more.
func _mouse_drift(delta: float) -> Vector2:
	_drift += (
		-_drift * DRIFT_RETURN
		+ Vector2(_rng.randfn(0.0, DRIFT_YAW), _rng.randfn(0.0, DRIFT_PITCH)) * sqrt(2.0 * DRIFT_RETURN)
	) * delta
	return Vector2(deg_to_rad(_drift.x), deg_to_rad(_drift.y)) * delta


## Stood still, a player shuffles: a strafe tap every second or so. Only ever
## sideways -- a body that has turned its back on the rim would step off it.
func _fidget(_delta: float) -> void:
	if _clock >= _fidget_next:
		_fidget_next = _clock + _rng.randf_range(0.45, 1.1)
		_fidget_until = _clock + _rng.randf_range(0.1, 0.22)
		_fidget_move = Vector2(_rng.randf_range(0.28, 0.45) * (1.0 if _rng.randf() < 0.5 else -1.0), 0.0)
	if _clock < _fidget_until:
		_intent.move_direction = _fidget_move


## A hold, crouched or not, with the optional peeking sway and the human fidget.
## "hesitate" is a hold whose length is jittered and which always fidgets.
func _hold(step: Dictionary, delta: float) -> void:
	_intent.slide_held = bool(step.get("crouch", false))
	var sway: float = deg_to_rad(float(step.get("sway", 0.0)))
	if sway > 0.0:
		# A crouched body that peeks: a slow yaw sway of +/- sway degrees.
		var omega: float = TAU / float(step.get("period", 2.5))
		_intent.look_delta = Vector2(-sway * omega * cos(omega * _clock) * delta, 0.0)
	if _human and bool(step.get("fidget", false)):
		_fidget(delta)
	if step.has("strafe"):
		_intent.move_direction = Vector2(float(step["strafe"]), 0.0)


## Along the ring at radius r from where it stands to bearing "to": the target
## is always a few degrees ahead, so the body follows the arc rather than the
## chord. dir -1 runs the ring backwards (bearing falling).
func _lane(step: Dictionary, delta: float) -> bool:
	var here: Vector3 = _body.global_position
	var bearing: float = fposmod(rad_to_deg(atan2(here.z, here.x)), 360.0)
	var to: float = float(step["to"])
	var dir: float = float(step.get("dir", 1.0))
	var remaining: float = fposmod((to - bearing) * dir, 360.0)
	if remaining > 180.0 or remaining < 0.5 or _clock > float(step.get("timeout", 20.0)):
		return true
	var ahead: Vector3 = ring_point(bearing + 5.0 * dir, float(step.get("r", 52.0)), 0.0)
	return _run(step, delta, ahead, 0.0)


## Full speed at the target, weaving sideways and hopping if asked. True on arrival.
func _run(step: Dictionary, delta: float, to: Vector3, within: float) -> bool:
	var flat: Vector3 = Vector3(to.x - _body.global_position.x, 0.0, to.z - _body.global_position.z)
	if flat.length() <= within or _clock > float(step.get("timeout", 8.0)):
		return true
	var direction: Vector3 = flat.normalized()
	if step.has("glances"):
		return _run_gazing(step, delta, direction)
	_face(direction)
	var weave: float = float(step.get("weave", 0.0))
	var strafe: float = 0.0
	if weave > 0.0:
		strafe = sin(_clock * TAU / float(step.get("period", 1.1))) * weave
	var speed: float = float(step.get("speed", step.get("pace", 1.0)))
	if _human:
		# The walk wavers: the pace drifts a little and the line is not straight.
		_sway = lerpf(_sway, _rng.randf_range(-0.18, 0.18), 3.0 * delta)
		strafe += _sway
		speed *= 1.0 + 0.12 * sin(_clock * 4.1 + _sway * 20.0)
	# Steered, the body may not yet face the target: the stick is pushed toward
	# the target in the body's own frame (a strafe-run), so the feet go where the
	# step says while the head is still coming round.
	var local: Vector2 = Vector2(0.0, 1.0)
	if _steer:
		local = Vector2(_body.global_transform.basis.x.dot(direction), (-_body.global_transform.basis.z).dot(direction))
		if local.length_squared() > 0.0001:
			local = local.normalized()
	_intent.move_direction = local * speed + Vector2(strafe, 0.0)
	_intent.slide_held = bool(step.get("crouch", false))
	var hop: float = float(step.get("hop", 0.0))
	if hop > 0.0:
		_hop_clock += delta
		if _hop_clock >= hop:
			_intent.jump_pressed = true
			_hop_clock = 0.0
	return false


## The run with the head on a schedule of glances: the body yaws where the
## gaze says (the lane's yaw plus the offset), through the controller's own
## look path, and the run along the lane is re-expressed in the body's turned
## frame so the legs keep to the lane while the eyes do not. "flinch_on" names
## a flag (shot, hit, shove) that swaps the schedule for the flinch: a jerk
## away and up, a look back over the shoulder, a step away, then eyes front.
func _run_gazing(step: Dictionary, delta: float, direction: Vector3) -> bool:
	if _gaze_schedule.is_empty() and _gaze_index == 0 and not _gaze_flinched:
		_gaze_schedule = step.get("glances", [])
		_gaze_strafes = step.get("strafes", [])
	var flinch_flag: String = String(step.get("flinch_on", ""))
	if flinch_flag != "" and not _gaze_flinched and _flags.get(flinch_flag, false):
		_gaze_flinched = true
		var now: float = _clock
		var side: float = float(step.get("flinch_side", 1.0))
		_gaze_schedule = [
			{"t": now, "right": 22.0 * side, "pitch": 4.0},
			{"t": now + 0.12, "right": 40.0 * side, "pitch": -3.0},
			{"t": now + 0.32, "right": 124.0 * side, "pitch": -12.0},   # over the shoulder: he is behind us now
			{"t": now + 0.9, "right": 114.0 * side, "pitch": -10.0},
			{"t": now + 1.05, "right": -4.0 * side, "pitch": -1.0},    # eyes front
			{"t": now + 1.75, "right": -14.0 * side, "pitch": -1.5},   # a check on the others
			{"t": now + 2.2, "right": 2.0 * side, "pitch": -1.0},
		]
		_gaze_index = 0
		_gaze_strafes = [
			{"t": now + 0.05, "strafe": -0.22 * side},
			{"t": now + 0.6, "strafe": -0.05 * side},
			{"t": now + 1.4, "strafe": 0.08 * side},
			{"t": now + 2.3, "strafe": -0.06 * side},
		]
		_gaze_step_index = 0
	while _gaze_index < _gaze_schedule.size() and float(_gaze_schedule[_gaze_index]["t"]) <= _clock:
		_gaze_target = Vector2(deg_to_rad(-float(_gaze_schedule[_gaze_index].get("right", 0.0))), deg_to_rad(float(_gaze_schedule[_gaze_index].get("pitch", 0.0))))
		_gaze_index += 1
	while _gaze_step_index < _gaze_strafes.size() and float(_gaze_strafes[_gaze_step_index]["t"]) <= _clock:
		_gaze_strafe_target = float(_gaze_strafes[_gaze_step_index].get("strafe", 0.0))
		_gaze_step_index += 1
	var accel: Vector2 = (_gaze_target - _gaze) * GAZE_OMEGA * GAZE_OMEGA - _gaze_rate * 2.0 * GAZE_ZETA * GAZE_OMEGA
	_gaze_rate += accel * delta
	_gaze += _gaze_rate * delta
	_gaze_strafe = lerpf(_gaze_strafe, _gaze_strafe_target, 1.0 - exp(-delta / GAZE_STRAFE_LAG))
	var lane_yaw: float = atan2(-direction.x, -direction.z)
	var target_yaw: float = lane_yaw + _gaze.x
	var yaw_error: float = wrapf(target_yaw - _body.rotation.y, -PI, PI)
	var pitch_now: float = _body.head.rotation.x if _body.head != null else 0.0
	var pitch_error: float = _gaze.y - pitch_now
	_intent.look_delta = Vector2(-yaw_error, -pitch_error)
	var weave: float = float(step.get("weave", 0.0))
	var strafe: float = _gaze_strafe
	if weave > 0.0:
		strafe += sin(_clock * TAU / float(step.get("period", 1.1))) * weave
	var speed: float = float(step.get("speed", step.get("pace", 1.0)))
	var right: Vector3 = Vector3(cos(target_yaw), 0.0, -sin(target_yaw))
	var forward: Vector3 = Vector3(-sin(target_yaw), 0.0, -cos(target_yaw))
	var lane_right: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var wish: Vector3 = direction * speed + lane_right * strafe
	_intent.move_direction = Vector2(wish.dot(right), wish.dot(forward))
	return false


## In flight ("land"): keep the eyes on where the body is going, hold the stick
## forward a little for the last part (air control is tiny; it is the hands
## doing something), and once per flight a small yaw correction, the flick a
## player makes lining up the landing. Early in the flight the eyes are up the
## line on the platform after this one ("look_ahead"); then they come down.
func _in_flight(step: Dictionary, delta: float) -> void:
	var ahead: bool = step.has("look_ahead") and _clock < float(step.get("ahead_until", 0.3))
	if ahead or step.has("look_at"):
		var to: Vector3 = (step["look_ahead"] if ahead else step["look_at"]) as Vector3
		var flat: Vector3 = Vector3(to.x - _body.global_position.x, 0.0, to.z - _body.global_position.z)
		if flat.length() > 0.3:
			_face(flat.normalized())
		if ahead:
			_pitch_goal = _pitch_to(to)
			_has_pitch_goal = true
	if _clock > float(step.get("stick_after", 0.3)):
		_intent.move_direction = Vector2(float(step.get("strafe", 0.0)), 0.6)
	if _human and step.has("correct"):
		if _clock - delta <= 0.0:
			_correction = _rng.randf_range(-float(step["correct"]), float(step["correct"]))
			_correction_done = 0.0
		var t0: float = float(step.get("correct_at", 0.18))
		var u: float = clampf((_clock - t0) / 0.22, 0.0, 1.0)
		var share: float = _flick(u) - _correction_done
		_correction_done = _flick(u)
		_intent.look_delta.x += deg_to_rad(_correction * share)


## Throw the body at [param target] so it lands there, air friction included.
func _leap(target: Vector3, speed: float, lock: float = 0.9) -> void:
	var velocity: Vector3 = launch_velocity(_body, target, speed)
	if velocity == Vector3.ZERO:
		return
	_snap_face(Vector3(velocity.x, 0.0, velocity.z).normalized())
	_body.launch(velocity, flight_seconds(_body, target, speed) * lock)


## Seconds a leap to [param target] takes at a nominal [param speed] over the ground.
static func flight_seconds(body_node: PlayerController, target: Vector3, speed: float) -> float:
	var here: Vector3 = body_node.global_position
	return Vector2(target.x - here.x, target.z - here.z).length() / speed


## The launch that puts [param body_node] on [param target]: horizontal speed
## solved against the profile's air friction (v decays as e^-ct) and the one
## ground tick of friction the launch frame pays; rise solved against gravity.
static func launch_velocity(body_node: PlayerController, target: Vector3, speed: float) -> Vector3:
	var here: Vector3 = body_node.global_position
	var flat: Vector3 = Vector3(target.x - here.x, 0.0, target.z - here.z)
	var distance: float = flat.length()
	if distance < 0.001:
		return Vector3.ZERO
	var flight: float = distance / speed
	var gravity: float = FALLBACK_GRAVITY
	var air_friction: float = 0.0
	var ground_friction: float = 0.0
	if body_node.profile != null:
		gravity = body_node.profile.gravity * body_node.profile.gravity_scale
		air_friction = body_node.profile.air_friction
		ground_friction = body_node.profile.friction
	var horizontal: float = speed
	if air_friction > 0.0:
		horizontal = distance * air_friction / (1.0 - exp(-air_friction * flight))
	horizontal /= maxf(1.0 - ground_friction / float(Engine.physics_ticks_per_second), 0.5)
	var direction: Vector3 = flat / distance
	var rise: float = (target.y - here.y + 0.5 * gravity * flight * flight) / flight
	return Vector3(direction.x * horizontal, rise, direction.z * horizontal)


## Face the victim and tap shove the tick they are airborne inside range. True once swung.
func _shove_when(step: Dictionary) -> bool:
	var victim: PlayerController = step.get("victim") as PlayerController
	if victim == null or not is_instance_valid(victim) or _clock > float(step.get("timeout", 12.0)):
		return true
	var offset: Vector3 = victim.global_position - _body.global_position
	offset.y = 0.0
	# The swing goes where the body faces: straight at them unless the step
	# says otherwise (it must still be within the shove's facing cone).
	var facing: Vector3 = step.get("face", Vector3.ZERO) as Vector3
	if facing.length_squared() > 0.0:
		_face(facing.normalized())
	elif offset.length() > 0.01:
		_face(offset.normalized())
	if victim.is_on_floor() or offset.length() > float(step.get("range", 3.0)):
		return false
	_intent.shove_pressed = true
	return true


## Run at the victim, wherever they are now, and tap shove the tick they are in
## reach and in front -- and the shove is off cooldown, when the match is known.
## True once swung, or when the chase has timed out.
func _chase(step: Dictionary) -> bool:
	var victim: PlayerController = step.get("victim") as PlayerController
	if victim == null or not is_instance_valid(victim) or _clock > float(step.get("timeout", 10.0)):
		return true
	var offset: Vector3 = victim.global_position - _body.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > 0.01:
		_face(offset.normalized())
	_intent.move_direction = Vector2(0.0, clampf(float(step.get("speed", 1.0)), 0.2, 1.0))
	if distance > float(step.get("range", 2.5)) or not _shove_ready():
		return false
	_intent.shove_pressed = true
	return true


## Stand square to the victim, on the spot, until the timer runs out or the
## body is thrown off the floor (the shove that answers this one).
func _face_hold(step: Dictionary) -> bool:
	var victim: PlayerController = step.get("victim") as PlayerController
	if victim == null or not is_instance_valid(victim):
		return true
	var offset: Vector3 = victim.global_position - _body.global_position
	offset.y = 0.0
	if offset.length() > 0.01:
		_face(offset.normalized())
	if _clock > 0.15 and not _body.is_on_floor():
		return true
	return _clock >= float(step.get("seconds", 3.0))


## Walk at the victim, facing them, swaying a little, until within "until"
## metres. True on arrival or at the timeout.
func _advance(step: Dictionary, delta: float) -> bool:
	var victim: PlayerController = step.get("victim") as PlayerController
	if victim == null or not is_instance_valid(victim) or _clock > float(step.get("timeout", 6.0)):
		return true
	var offset: Vector3 = victim.global_position - _body.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= float(step.get("until", 4.0)):
		return true
	if distance > 0.01:
		_face(offset.normalized())
	var sway: float = float(step.get("sway", 0.35))
	_sway = lerpf(_sway, _rng.randf_range(-sway, sway), 2.5 * delta)
	_intent.move_direction = Vector2(_sway, clampf(float(step.get("speed", 0.3)), 0.15, 1.0))
	return false


## Five in a scrap: run at the nearest other body whose throw would land inside
## the safe zone and shove it in reach; circle it between swings. Every body has
## its own reach, reaction and breather off its own RNG (seed_with), so the
## cadence never locks. Ryan on the first melee: "they all shove on the same
## cadence"; then "just let them shove more".
func _brawl(step: Dictionary, delta: float) -> bool:
	if _clock > float(step.get("seconds", 8.0)):
		return true
	if _brawl_ready_at == 0.0 and _clock < delta * 1.5:
		# Opening: a hold of its own, its own reach.
		_brawl_ready_at = _rng.randf_range(0.15, 1.0)
		_brawl_reach = _rng.randf_range(2.0, 2.4)
		_brawl_circle = 1.0 if _rng.randf() < 0.5 else -1.0
	var others: Array = step.get("others", [])
	var safe: Dictionary = step.get("safe", {})
	var along: float = float(step.get("along", 0.55))
	# The leash: a body drifting to the zone's edge walks back in before anything else.
	if not safe.is_empty() and not _inside(_body.global_position, safe, 0.8):
		var home: Vector3 = ring_point(
			fposmod(float(safe.get("from", 0.0)) + 0.5 * fposmod(float(safe.get("to", 360.0)) - float(safe.get("from", 0.0)), 360.0), 360.0),
			0.5 * (float(safe.get("r_min", 47.0)) + float(safe.get("r_max", 57.0))), 0.0)
		var back: Vector3 = Vector3(home.x - _body.global_position.x, 0.0, home.z - _body.global_position.z).normalized()
		_face(back)
		_intent.move_direction = Vector2(0.0, 0.8)
		return false
	var best: PlayerController = null
	var best_distance: float = INF
	var best_facing: Vector3 = Vector3.ZERO
	for other: Variant in others:
		var candidate: PlayerController = other as PlayerController
		if candidate == null or candidate == _body or not is_instance_valid(candidate):
			continue
		if absf(candidate.global_position.y - _body.global_position.y) > 4.0:
			continue
		var to: Vector3 = candidate.global_position - _body.global_position
		to.y = 0.0
		var d: float = to.length()
		if d < 0.01 or d >= best_distance:
			continue
		# Turned toward the ring's tangent, inside the shove's cone, so throws
		# run along the lane instead of across it.
		var tangent: Vector3 = _tangent_at(_body.global_position)
		if tangent.dot(to) < 0.0:
			tangent = -tangent
		var facing: Vector3 = to.normalized().slerp(tangent, along).normalized()
		if _throw_is_safe(candidate, facing, safe):
			best = candidate
			best_distance = d
			best_facing = facing
	if best == null:
		if OS.has_environment("STAGE_DEBUG") and int(_clock * 4.0) != int((_clock - delta) * 4.0):
			print("[brawl] %s: no safe target (%d others)" % [_body.name, others.size()])
		return false
	var offset: Vector3 = best.global_position - _body.global_position
	offset.y = 0.0
	_face(best_facing)
	if _clock < _brawl_ready_at or not _shove_ready():
		# Between swings: circle the target instead of leaning on it.
		var side: Vector3 = Vector3(-best_facing.z, 0.0, best_facing.x) * _brawl_circle
		var wish: Vector3 = (side * 0.7 + offset.normalized() * (0.4 if best_distance > _brawl_reach else -0.2)).normalized()
		_intent.move_direction = Vector2(_body.global_transform.basis.x.dot(wish), (-_body.global_transform.basis.z).dot(wish))
		_brawl_seen_at = -1.0
		return false
	var chase: Vector3 = offset.normalized()
	_intent.move_direction = Vector2(_body.global_transform.basis.x.dot(chase), (-_body.global_transform.basis.z).dot(chase))
	if best_distance > _brawl_reach:
		_brawl_seen_at = -1.0
		return false
	if _brawl_seen_at < 0.0:
		_brawl_seen_at = _clock
		_brawl_reaction = _rng.randf_range(0.05, 0.3)
	if _clock - _brawl_seen_at < _brawl_reaction:
		return false
	_intent.shove_pressed = true
	_brawl_ready_at = _clock + _rng.randf_range(0.0, 0.35)
	_brawl_circle = -_brawl_circle
	_brawl_seen_at = -1.0
	return false


## Where a shove thrown along [param facing] would put [param victim]: inside the zone, or not.
func _throw_is_safe(victim: PlayerController, facing: Vector3, safe: Dictionary) -> bool:
	if safe.is_empty():
		return true
	var impulse: float = 16.0
	var lock: float = 1.4
	if _match != null:
		impulse = _match.get_rules().shove_impulse
		lock = _match.get_rules().shove_air_lock_seconds
	# The shipped 16 m/s shove carries a body about 5.5 m along the deck
	# (measured on the face-to-face takes); the estimate scales with the impulse.
	var landing: Vector3 = victim.global_position + facing * impulse * 0.34 * minf(lock / 1.4, 1.0)
	return _inside(landing, safe, 0.0)


## True when [param point] is inside the zone, [param margin] metres in from its edges.
static func _inside(point: Vector3, safe: Dictionary, margin: float) -> bool:
	var deg: float = fposmod(rad_to_deg(atan2(point.z, point.x)), 360.0)
	var r: float = Vector2(point.x, point.z).length()
	var from: float = float(safe.get("from", 0.0))
	var to: float = float(safe.get("to", 360.0))
	var span: float = fposmod(to - from, 360.0)
	var margin_deg: float = rad_to_deg(margin / maxf(r, 1.0))
	var inside: bool = fposmod(deg - from, 360.0) >= margin_deg and fposmod(deg - from, 360.0) <= span - margin_deg
	return inside and r >= float(safe.get("r_min", 0.0)) + margin and r <= float(safe.get("r_max", 999.0)) - margin


## True when the match would let this body swing now.
func _shove_ready() -> bool:
	if _match == null:
		return true
	var participant: MatchParticipant = _match.resolve_participant(_body)
	return participant == null or participant.shove_cooldown_remaining <= 0.0


## A private copy of the movement profile whose friction floor is lowered: the
## shipped 2.5 m/s floor turns any walk under 1.25 m/s into a crawl of a fifth
## of it, and a body creeping up behind someone wants to actually creep.
func _slow_the_feet(floor_speed: float) -> void:
	if _body.profile == null:
		return
	var copy: MovementProfile = _body.profile.duplicate() as MovementProfile
	copy.friction_stop_speed = floor_speed
	_body.set_profile(copy)


## Finish the current step now: the stage saw something the steps could not
## (a shove landing) and the next step is the answer to it.
func advance() -> void:
	_index += 1
	_clock = 0.0
	_hop_clock = 0.0


## Drop the current step list for [param steps], from the top.
func retarget(steps: Array) -> void:
	_steps = expand(steps)
	_index = 0
	_clock = 0.0
	_hop_clock = 0.0


## Give the body back to its brain now, whatever step it was on.
func release() -> void:
	_release()


## Give the body back to its brain: the bot finishes the clip on its own.
func _release() -> void:
	_released = true
	if _brain != null and _body != null and is_instance_valid(_body):
		_body.intent_source = _brain.input
		_brain.process_mode = Node.PROCESS_MODE_INHERIT


func _face(direction: Vector3) -> void:
	if not _steer:
		_snap_face(direction)
		return
	var wanted: float = atan2(-direction.x, -direction.z)
	var err: float = wrapf(wanted - _body.rotation.y, -PI, PI)
	var cap: float = deg_to_rad(_steer_rate) * _dt
	var by: float = clampf(err * _steer_gain * _dt, -cap, cap)
	# PlayerController yaws by -look_delta.x.
	_intent.look_delta.x += -by


func _snap_face(direction: Vector3) -> void:
	_body.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)


## Degrees down from the eye to [param point].
func _pitch_to(point: Vector3) -> float:
	var eye: Vector3 = _body.global_position + Vector3.UP * 1.6
	var flat: float = Vector2(point.x - eye.x, point.z - eye.z).length()
	# Never further down than a player lining up a landing actually looks.
	return minf(rad_to_deg(atan2(eye.y - point.y, maxf(flat, 0.1))), 30.0)


static func _tangent_at(point: Vector3) -> Vector3:
	return tangent_at(rad_to_deg(atan2(point.z, point.x)))


static func tangent_at(degrees: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(-sin(angle), 0.0, cos(angle))


# --- The stages ---------------------------------------------------------------
## The stages that ship in this file are the shove short's first four beats and
## the older b-roll ones. Every later stage is a plugin under
## tools/capture/stages/ (run_clip loads --stage=NAME from there first).

const DECK_Y: float = 23.0
## S2 boulder chain: landing 2 sits at 99.8 deg on r 54.7, top y 22.95.
const CHAIN_R: float = 54.7
const LANDING_2_DEGREES: float = 99.8
const LANDING_2_Y: float = 22.95
## S3: flat open deck r 47-59 from 140 to 200 deg, nothing to hide behind.
const OPEN_LANE_R: float = 52.0
## S3 chase: the victim sets off here on the open lane and the ghost this far
## behind it, inside the pocket slab at 138 (r 52) rather than on it.
const CHASE_VICTIM_DEGREES: float = 149.0
const CHASE_GHOST_DEGREES: float = 141.0
const CHASE_GHOST_R: float = 49.5
## S3: the tower's own pillar hides 180-184 deg on the lane; the decoy runs out of it.
const HIDDEN_DEGREES: float = 182.0
## The demon pad on the S3 lane at 148.4 deg, r 51.
const PAD_DEGREES: float = 148.4
const PAD_R: float = 51.0
## S4: raised lane r 48-50 at 236 deg, lava from r 51 out.
const S4_LEDGE_DEGREES: float = 236.0
## The pit: the deck's inner rim is at r 46.7 and drops 31 m into the kill box.
## shoveedge plays on the flat S3 deck, the victim a metre back from the rim.
const RIM_DEGREES: float = 182.0
const RIM_VICTIM_R: float = 47.2
## The shover starts on the deck behind the victim, a step to one side: its
## run-up is straight at their back, and the shove carries them inward over the
## rim, straight away from a lens on the outer deck (rim_edge).
const RIM_SHOVER_DEGREES: float = 184.5
const RIM_SHOVER_R: float = 52.0
## The S3/S4 pocket rock at 194-198 deg on the rim hides a body crouched just
## outboard of it (r 47.9) from the tower; the deck from 200 deg on is open.
const COVER_DEGREES: float = 196.5
const COVER_R: float = 47.9
const COVER_SHOVER_DEGREES: float = 189.0
## S5: the lava lake fills the corridor from 293 to 335 deg, r 47-57, with a
## few stones; the bank at 286-291 is solid deck. shovelake stands the victim
## on the lip of the bank and throws them out over the open lake, clear of the
## stones at 298 (r 54-56).
const LAKE_LIP_DEGREES: float = 291.5
const LAKE_LIP_R: float = 50.0
## Five metres behind the lip along the lane and a little outboard: a shove
## from here carries the victim ten metres up the lake at r 52-54, between the
## stones at 298 and 310 (r 54-56) and well short of the inner rim.
const LAKE_SHOVER_DEGREES: float = 285.6
const LAKE_SHOVER_R: float = 51.0


## The step list for [param stage], or empty when the stage is not one of these.
static func steps_for(stage: String, victim: PlayerController) -> Array:
	match stage:
		"shovecatch", "ghostcatch":
			# On the landing the runner is jumping to, facing back up the chain.
			# The swing itself is skewed fifty degrees inward, the most the facing
			# cone allows: the runner is thrown off the chain at the ridge and
			# drops into the lava between, instead of back onto the boulder
			# they jumped from.
			var back: Vector3 = -tangent_at(LANDING_2_DEGREES)
			var swing: Vector3 = (back - radial_at(LANDING_2_DEGREES) * 1.2).normalized()
			return [
				{"do": "place", "at": ring_point(LANDING_2_DEGREES, CHAIN_R, LANDING_2_Y + 0.1 - DECK_Y), "face": back},
				{"do": "hold", "seconds": 0.2},
				{"do": "shove_when", "victim": victim, "range": 3.0, "timeout": 16.0, "face": swing},
				{"do": "hold", "seconds": 5.0},
			]
		"ghostchase":
			# The ghost, starting on the S3 lane behind the victim: run them down
			# and shove. Its brain takes the body back afterwards, so whichever of
			# the two is alive after the swap keeps running on its own.
			return [
				{"do": "place", "at": ring_point(CHASE_GHOST_DEGREES, CHASE_GHOST_R, 0.1)},
				{"do": "hold", "seconds": 0.2},
				{"do": "chase", "victim": victim, "range": 2.4, "timeout": 12.0},
				{"do": "release"},
			]
		"ghostchase_victim":
			# The runner being chased: down the open S3 lane, a little weave, never looking back.
			return [
				{"do": "place", "at": ring_point(CHASE_VICTIM_DEGREES, OPEN_LANE_R, 0.1)},
				{"do": "lane", "from": CHASE_VICTIM_DEGREES, "to": 199.0, "r": OPEN_LANE_R, "weave": 0.35, "period": 1.3, "timeout": 12.0},
				{"do": "release"},
			]
		"missstreak":
			return [
				{"do": "place", "at": ring_point(146.0, OPEN_LANE_R, 0.1)},
				{"do": "lane", "from": 146.0, "to": 198.0, "r": OPEN_LANE_R, "weave": 0.7, "period": 1.1, "hop": 1.7, "timeout": 24.0},
				{"do": "release"},
			]
		"decoy":
			# Facing back down the lane: the hologram runs out into the open deck
			# the guard is watching, while the runner stays behind the pillar.
			return [
				{"do": "place", "at": ring_point(HIDDEN_DEGREES, OPEN_LANE_R, 0.1), "face": -tangent_at(HIDDEN_DEGREES)},
				{"do": "hold", "seconds": 1.2, "crouch": true},
				{"do": "ability", "slot": 2},
				{"do": "hold", "seconds": 3.5, "crouch": true},
				{"do": "release"},
			]
		"padflight":
			return [
				{"do": "place", "at": ring_point(PAD_DEGREES, PAD_R, 0.4)},
				{"do": "hold", "seconds": 0.4},
				{"do": "land"},
				{"do": "release"},
			]
		"shovecover":
			# The shover, on the open deck behind the hidden runner: run up the
			# lane at them and shove them along it, out past the rock into the
			# tower's view; then step back into the same cover and stay down.
			return [
				{"do": "place", "at": ring_point(COVER_SHOVER_DEGREES, COVER_R + 0.4, 0.1), "face": tangent_at(COVER_SHOVER_DEGREES)},
				{"do": "hold", "seconds": 0.9},
				{"do": "chase", "victim": victim, "range": 2.2, "timeout": 8.0},
				{"do": "run", "to": ring_point(COVER_DEGREES - 0.5, COVER_R, 0.0), "within": 0.5, "timeout": 3.0},
				{"do": "hold", "seconds": 12.0, "crouch": true},
			]
		"shovecover_victim":
			# Crouched behind the pocket rock, facing up the lane, never looking
			# back. The crouch is held until the shove lands (run_clip advances
			# the driver on it); from then on they are up, and are shot standing.
			return [
				{"do": "place", "at": ring_point(COVER_DEGREES, COVER_R, 0.1), "face": tangent_at(COVER_DEGREES)},
				{"do": "hold", "seconds": 20.0, "crouch": true},
				{"do": "hold", "seconds": 20.0},
			]
		"shovelake":
			# The shover, back on the bank behind and outboard of the victim:
			# run at them and shove; the line from here to the lip crosses the
			# lake's open middle, so they land in lava, not on a stone.
			var lip: Vector3 = ring_point(LAKE_LIP_DEGREES, LAKE_LIP_R, 0.0)
			var from: Vector3 = ring_point(LAKE_SHOVER_DEGREES, LAKE_SHOVER_R, 0.1)
			return [
				{"do": "place", "at": from, "face": Vector3(lip.x - from.x, 0.0, lip.z - from.z).normalized()},
				{"do": "hold", "seconds": 0.8},
				{"do": "chase", "victim": victim, "range": 2.2, "timeout": 8.0},
				{"do": "hold", "seconds": 12.0},
			]
		"shovelake_victim":
			# Stood on the lip of the bank, looking out along the lane over the lake.
			return [
				{"do": "place", "at": ring_point(LAKE_LIP_DEGREES, LAKE_LIP_R, 0.1), "face": tangent_at(LAKE_LIP_DEGREES)},
				{"do": "hold", "seconds": 20.0},
			]
		"shoveedge", "shoveedge_look":
			# The shover, out on the deck behind a runner stood at the pit rim:
			# run straight at their back and shove them over it.
			return [
				{"do": "place", "at": ring_point(RIM_SHOVER_DEGREES, RIM_SHOVER_R, 0.1), "face": -tangent_at(RIM_SHOVER_DEGREES)},
				{"do": "hold", "seconds": 1.6},
				{"do": "chase", "victim": victim, "range": 2.2, "timeout": 8.0},
				{"do": "hold", "seconds": 12.0},
			]
		"shoveedge_victim":
			# Walks the last couple of metres to the rim, then looks out and a
			# little down over the pit at the tower; never sees the shover.
			var facing: Vector3 = (-radial_at(RIM_DEGREES) + tangent_at(RIM_DEGREES) * 0.25).normalized()
			return [
				{"do": "place", "at": ring_point(RIM_DEGREES, RIM_VICTIM_R + 2.2, 0.1), "face": facing},
				{"do": "run", "to": ring_point(RIM_DEGREES, RIM_VICTIM_R + 0.3, 0.0), "within": 0.25, "speed": 0.4, "timeout": 2.5},
				{"do": "pitch", "down": 14.0, "seconds": 0.9},
				{"do": "hold", "seconds": 20.0},
			]
		"shoveedge_look_victim":
			# The same, but they hear something: a look back over the left
			# shoulder as the shover comes in, and the shove lands as they are
			# turning back to the pit. Ryan: "have the player look back and
			# then get shoved off the edge so we can see what's happening".
			# Played like a person: mouse drift throughout, a wavering walk up,
			# a hesitation with a shuffle, the look back a flick that overshoots
			# and settles, the turn back the same. Ryan: "make it look more like
			# a human playing and make it less rigid".
			var facing_back: Vector3 = (-radial_at(RIM_DEGREES) + tangent_at(RIM_DEGREES) * 0.25).normalized()
			return [
				{"do": "place", "at": ring_point(RIM_DEGREES, RIM_VICTIM_R + 2.2, 0.1), "face": facing_back},
				{"do": "human", "on": true},
				{"do": "run", "to": ring_point(RIM_DEGREES, RIM_VICTIM_R + 0.8, 0.0), "within": 0.3, "speed": 0.25, "timeout": 2.5},
				{"do": "pitch", "down": 8.0, "seconds": 0.35},
				{"do": "hold", "seconds": 0.2, "fidget": true},
				{"do": "look_back", "degrees": -140.0, "seconds": 0.42, "hold": 0.3, "back": 0.6},
				{"do": "hold", "seconds": 20.0, "fidget": true},
			]
		"lavadeath":
			return [
				{"do": "place", "at": ring_point(S4_LEDGE_DEGREES, 49.0, 1.5)},
				{"do": "hold", "seconds": 0.4},
				{"do": "run", "to": ring_point(S4_LEDGE_DEGREES + 2.0, 56.0, 0.0), "hop": 0.5, "timeout": 5.0},
				{"do": "hold", "seconds": 3.0},
			]
	return []


## True when [param stage] is one [method steps_for] knows.
static func is_stage(stage: String) -> bool:
	return not steps_for(stage, null).is_empty()


static func ring_point(degrees: float, radius: float, height: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(cos(angle) * radius, DECK_Y + height, sin(angle) * radius)


static func radial_at(degrees: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(cos(angle), 0.0, sin(angle))
