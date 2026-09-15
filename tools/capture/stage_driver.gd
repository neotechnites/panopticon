extends Node

## B-roll only: drives one prisoner by hand through a list of steps, for a clip.
## Nothing here is reachable from a match.
##
## A step is a Dictionary with a [code]do[/code] and its arguments:
## [codeblock]
## {"do": "place", "at": Vector3, "face": Vector3}
## {"do": "run", "to": Vector3, "weave": 0.9, "period": 1.1, "hop": 1.6, "within": 0.6, "timeout": 8.0, "speed": 1.0}   # speed < 1 walks
## {"do": "lane", "from": deg, "to": deg, "r": 52.0, ...run's weave/period/hop}   # along the ring
## {"do": "leap", "to": Vector3, "speed": 8.0}
## {"do": "land"}
## {"do": "hold", "seconds": 2.0, "crouch": true}
## {"do": "shove_when", "victim": PlayerController, "range": 3.0, "timeout": 12.0, "face": Vector3}   # face: swing this way, not straight at them
## {"do": "chase", "victim": PlayerController, "range": 2.5, "timeout": 10.0}   # run at them, shove in reach
## {"do": "ability", "slot": 2}
## {"do": "pitch", "down": 12.0, "seconds": 0.0}     # tip the head down this many degrees, at once or over seconds
## {"do": "turn", "degrees": -140.0, "seconds": 0.5}  # yaw the body over seconds; positive is to its right
## {"do": "human", "on": true}    # from here on: mouse drift on every look, eased turns with
##                                # an overshoot and settle, a walk that wavers, and fidget:
##                                # true on a hold adds small strafe taps and a step back
## {"do": "release"}     # hand the body back to its own brain
## [/codeblock]

const FALLBACK_GRAVITY: float = 22.0

var _body: PlayerController = null
var _brain: RunnerBrain = null
var _steps: Array = []
var _index: int = 0
var _clock: float = 0.0
var _hop_clock: float = 0.0
var _intent: MoveIntent = MoveIntent.new()
var _released: bool = false
## The human layer (see the "human" step): a seeded random walk on the look,
## a wavering walk speed and the occasional strafe tap while standing.
var _human: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _drift: Vector2 = Vector2.ZERO      # look velocity, degrees per second (yaw, pitch)
var _sway: float = 0.0                  # strafe wobble while walking
var _fidget_next: float = 0.0
var _fidget_until: float = 0.0
var _fidget_move: Vector2 = Vector2.ZERO
## A human turn: fast out of the gate, past the mark, and back onto it.
const TURN_OVERSHOOT: float = 1.06
const TURN_FLICK_SHARE: float = 0.72
## Mouse drift, in degrees per second of standard deviation around zero.
const DRIFT_YAW: float = 2.4
const DRIFT_PITCH: float = 1.6
const DRIFT_RETURN: float = 2.5


## Take [param body] off [param brain] and start on [param steps].
func install(body: PlayerController, brain: RunnerBrain, steps: Array) -> void:
	_body = body
	_brain = brain
	_steps = steps
	# Seeded off the take's own RNG (run_clip seeds it), so a seed is a take.
	_rng.seed = hash(body.name) ^ randi()
	if _brain != null:
		_brain.process_mode = Node.PROCESS_MODE_DISABLED
	_body.intent_source = null


func is_done() -> bool:
	return _released or _index >= _steps.size()


func _physics_process(delta: float) -> void:
	if _released or _body == null or not is_instance_valid(_body):
		return
	_intent.clear()
	if _index >= _steps.size():
		_body.set_intent(_intent)
		return
	var step: Dictionary = _steps[_index]
	_clock += delta
	var finished: bool = false
	match String(step["do"]):
		"place":
			_body.global_position = step["at"]
			_body.velocity = Vector3.ZERO
			_face(step.get("face", _tangent_at(_body.global_position)))
			finished = true
		"run":
			finished = _run(step, delta, step["to"], float(step.get("within", 0.6)))
		"lane":
			finished = _lane(step, delta)
		"leap":
			_leap(step["to"], float(step.get("speed", 8.0)))
			finished = true
		"land":
			finished = _clock > 0.15 and _body.is_on_floor()
		"hold":
			_intent.slide_held = bool(step.get("crouch", false))
			if _human and bool(step.get("fidget", false)):
				_fidget(delta)
			finished = _clock >= float(step.get("seconds", 1.0))
		"human":
			_human = bool(step.get("on", true))
			finished = true
		"shove_when":
			finished = _shove_when(step)
		"chase":
			finished = _chase(step)
		"ability":
			_intent.ability_slot = int(step.get("slot", 2))
			finished = true
		"turn":
			# PlayerController yaws by -look_delta.x: a positive turn is to the right.
			var over_turn: float = float(step.get("seconds", 0.0))
			var by: float = deg_to_rad(float(step.get("degrees", 0.0))) * _share(over_turn, delta)
			_intent.look_delta = Vector2(by, 0.0)
			finished = _clock >= over_turn
		"pitch":
			# PlayerController pitches by -look_delta.y (unless the profile inverts).
			var over: float = float(step.get("seconds", 0.0))
			var down: float = deg_to_rad(float(step.get("down", 0.0))) * _share(over, delta)
			var inverted: bool = _body.profile != null and _body.profile.invert_look_y
			_intent.look_delta = Vector2(0.0, -down if inverted else down)
			finished = _clock >= over
		"release":
			_release()
			return
		_:
			finished = true
	if _human:
		_intent.look_delta += _mouse_drift(delta)
	_body.set_intent(_intent)
	if finished:
		if OS.has_environment("STAGE_DEBUG"):
			print("[step] %s done for %s at r %.2f (%.2fs)" % [step["do"], _body.name, Vector2(_body.global_position.x, _body.global_position.z).length(), _clock])
		_index += 1
		_clock = 0.0
		_hop_clock = 0.0


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


## Along the ring at radius r from one bearing to the next: the target is always
## a few degrees ahead, so the body follows the arc rather than the chord.
func _lane(step: Dictionary, delta: float) -> bool:
	var here: Vector3 = _body.global_position
	var bearing: float = fposmod(rad_to_deg(atan2(here.z, here.x)), 360.0)
	var to: float = float(step["to"])
	if fposmod(to - bearing, 360.0) > 180.0 or absf(to - bearing) < 0.5:
		return true
	var ahead: Vector3 = ring_point(bearing + 5.0, float(step.get("r", 52.0)), 0.0)
	return _run(step, delta, ahead, 0.0)


## Full speed at the target, weaving sideways and hopping if asked. True on arrival.
func _run(step: Dictionary, delta: float, to: Vector3, within: float) -> bool:
	var flat: Vector3 = Vector3(to.x - _body.global_position.x, 0.0, to.z - _body.global_position.z)
	if flat.length() <= within or _clock > float(step.get("timeout", 8.0)):
		return true
	_face(flat.normalized())
	var weave: float = float(step.get("weave", 0.0))
	var strafe: float = 0.0
	if weave > 0.0:
		strafe = sin(_clock * TAU / float(step.get("period", 1.1))) * weave
	var speed: float = float(step.get("speed", 1.0))
	if _human:
		# The walk wavers: the pace drifts a little and the line is not straight.
		_sway = lerpf(_sway, _rng.randf_range(-0.18, 0.18), 3.0 * delta)
		strafe += _sway
		speed *= 1.0 + 0.12 * sin(_clock * 4.1 + _sway * 20.0)
	_intent.move_direction = Vector2(strafe, speed)
	_intent.slide_held = bool(step.get("crouch", false))
	var hop: float = float(step.get("hop", 0.0))
	if hop > 0.0:
		_hop_clock += delta
		if _hop_clock >= hop:
			_intent.jump_pressed = true
			_hop_clock = 0.0
	return false


## Throw the body at [param target] so it lands there, air friction included.
func _leap(target: Vector3, speed: float) -> void:
	var velocity: Vector3 = launch_velocity(_body, target, speed)
	if velocity == Vector3.ZERO:
		return
	_face(Vector3(velocity.x, 0.0, velocity.z).normalized())
	_body.launch(velocity, flight_seconds(_body, target, speed) * 0.9)


## Seconds a leap to [param target] takes at a nominal [param speed] over the ground.
static func flight_seconds(body: PlayerController, target: Vector3, speed: float) -> float:
	var here: Vector3 = body.global_position
	return Vector2(target.x - here.x, target.z - here.z).length() / speed


## The launch that puts [param body] on [param target]: horizontal speed solved
## against the profile's air friction (v decays as e^-ct) and the one ground
## tick of friction the launch frame pays; rise solved against gravity.
static func launch_velocity(body: PlayerController, target: Vector3, speed: float) -> Vector3:
	var here: Vector3 = body.global_position
	var flat: Vector3 = Vector3(target.x - here.x, 0.0, target.z - here.z)
	var distance: float = flat.length()
	if distance < 0.001:
		return Vector3.ZERO
	var flight: float = distance / speed
	var gravity: float = FALLBACK_GRAVITY
	var air_friction: float = 0.0
	var ground_friction: float = 0.0
	if body.profile != null:
		gravity = body.profile.gravity * body.profile.gravity_scale
		air_friction = body.profile.air_friction
		ground_friction = body.profile.friction
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


## Run flat out at the victim, wherever they are now, and tap shove the tick they
## are in reach and in front. True once swung, or when the chase has timed out.
func _chase(step: Dictionary) -> bool:
	var victim: PlayerController = step.get("victim") as PlayerController
	if victim == null or not is_instance_valid(victim) or _clock > float(step.get("timeout", 10.0)):
		return true
	var offset: Vector3 = victim.global_position - _body.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > 0.01:
		_face(offset.normalized())
	_intent.move_direction = Vector2(0.0, 1.0)
	if distance > float(step.get("range", 2.5)):
		return false
	_intent.shove_pressed = true
	return true


## Finish the current step now: the stage saw something the steps could not
## (a shove landing) and the next step is the answer to it.
func advance() -> void:
	_index += 1
	_clock = 0.0
	_hop_clock = 0.0


## Give the body back to its brain now, whatever step it was on.
func release() -> void:
	_release()


## Give the body back to its brain: the bot finishes the clip on its own.
func _release() -> void:
	_released = true
	if _brain != null:
		_body.intent_source = _brain.input
		_brain.process_mode = Node.PROCESS_MODE_INHERIT


func _face(direction: Vector3) -> void:
	_body.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)


static func _tangent_at(point: Vector3) -> Vector3:
	return tangent_at(rad_to_deg(atan2(point.z, point.x)))


static func tangent_at(degrees: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(-sin(angle), 0.0, cos(angle))


# --- The stages ---------------------------------------------------------------

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
				{"do": "turn", "degrees": -140.0, "seconds": 0.42},
				{"do": "hold", "seconds": 0.3},
				{"do": "turn", "degrees": 140.0, "seconds": 0.6},
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
