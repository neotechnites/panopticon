class_name PlayerController
extends CharacterBody3D

## The first-person body used by every player in PANOPTICON.
##
## Canon: the shooter in the tower and the prisoners on the ring move
## identically. Equipment is the only asymmetry between the roles, so there is
## one controller, not two, and any change made here changes the game for both
## sides at once.
##
## [b]Structure[/b]
##
## Input and movement are separate. This node never reads the keyboard or the
## mouse; it asks an [IntentSource] for a [MoveIntent] -- a wish direction, a
## look delta and three buttons -- and applies physics to it. A
## [HumanIntentSource] fills that struct from a device, a [BotIntentSource]
## fills it from AI, and neither the physics below nor the feel it produces can
## tell which. That is what makes headless bot matches a valid way to answer
## design questions.
##
## Every number lives in [MovementProfile]. There are no movement constants in
## this file, deliberately: a hard-coded value is a value that can never be
## swept.
##
## [b]The movement model[/b]
##
## The acceleration, friction and air-acceleration routines are the Quake
## family's, ported rather than approximated, because the STRAFTAT feel is not a
## vibe -- it is these exact three functions. Sources:
##
## - [code]PM_Friction[/code], [code]PM_Accelerate[/code], [code]PM_AirMove[/code]
##   in [code]code/game/bg_pmove.c[/code], id Software, Quake III Arena (GPL).
## - [code]SV_AirAccelerate[/code], [code]SV_UserFriction[/code] in
##   [code]QW/server/sv_user.c[/code], id Software, QuakeWorld (GPL) -- the
##   origin of the clamped air wish speed.
## - [code]CGameMovement::AirAccelerate[/code] and
##   [code]CGameMovement::Friction[/code] in [code]game/shared/gamemovement.cpp[/code],
##   Valve, Source SDK -- the same model, with [code]sv_airaccelerate[/code] left
##   high, which is the Half-Life / CPMA / STRAFTAT lineage this game wants.
##
## See [method _air_accelerate] for why air strafing falls out of it.

## Emitted on the tick a jump leaves the ground. Feet, camera kick and audio
## hang off this rather than polling for a state change.
signal jumped()

## Emitted on the tick the body touches down, carrying the downward speed it
## arrived with (m/s, positive). Fall damage and landing audio use it.
signal landed(impact_speed: float)

## Tunables. Without one the body cannot move and says so rather than falling
## back on invented numbers.
@export var profile: MovementProfile

## Where intent comes from. Leave it unset and drive the body by calling
## [method set_intent] every physics tick instead -- a network peer replaying
## another player's commands would do exactly that.
@export var intent_source: IntentSource

## Pitch pivot. Only the head pitches; the whole body yaws, so the wish
## direction always follows where the player is aiming, which is what makes
## air strafing steerable by the mouse.
@export var head: Node3D

## Set every tick, either from [member intent_source] or by an outside caller
## via [method set_intent].
var _intent: MoveIntent = MoveIntent.new()

## Head pitch in radians, kept here rather than read back off the node so the
## clamp cannot drift through repeated euler conversions.
var _pitch: float = 0.0

## Time left in which a jump is still allowed after leaving the ground.
var _coyote_timer: float = 0.0

## Time left in which a jump press made in the air still counts on landing.
var _jump_buffer_timer: float = 0.0

## Downward speed on the last airborne tick, reported by [signal landed].
var _fall_speed: float = 0.0

var _was_on_floor: bool = true


func _ready() -> void:
	if profile == null:
		push_error("PlayerController has no MovementProfile; the body cannot move.")
		set_physics_process(false)
		return

	floor_max_angle = deg_to_rad(profile.max_floor_angle_degrees)
	floor_snap_length = profile.floor_snap_length
	floor_stop_on_slope = true

	if intent_source != null:
		intent_source.configure(profile)


func _physics_process(delta: float) -> void:
	if intent_source != null:
		_intent.copy_from(intent_source.poll(delta))
	_intent.normalise()

	# Aim first, so this tick's wish direction reflects this tick's facing.
	# Quake's PM_UpdateViewAngles runs ahead of the move for the same reason:
	# a strafe turn must take effect on the frame the mouse moved, or the whole
	# air-strafe technique fights a frame of input lag.
	_apply_look(_intent.look_delta)

	var on_floor: bool = is_on_floor()
	_tick_jump_timers(on_floor, delta)

	if on_floor:
		# Gravity accumulated while falling is spent; keep it and every landing
		# would drag the body downhill and confuse the floor snap.
		velocity.y = 0.0

	if _try_jump(on_floor):
		# A jump makes the rest of this tick an air tick. This is not a detail:
		# skipping ground friction on the launch frame is precisely what lets a
		# bunny hop keep the speed it arrived with. Apply friction first and the
		# technique dies.
		on_floor = false

	# Quake splits the request into a unit direction and a scalar target speed;
	# a part-pressed stick is a proportionally lower target, not a shorter
	# vector, so that the accelerate routines stay dimensionally correct.
	var wish_vector: Vector3 = _get_wish_vector()
	var wish_direction: Vector3 = wish_vector.normalized()
	var wish_speed: float = profile.get_ground_speed(_intent.sprint_held) * wish_vector.length()

	if on_floor:
		# --- Ground phase ---
		# A future slide state belongs here, as a third branch alongside ground
		# and air with its own friction and acceleration numbers from the
		# profile. Nothing above needs to change to add it. Not implemented.
		_apply_friction(profile.friction, delta)
		_accelerate(wish_direction, wish_speed, profile.ground_acceleration, delta)
	else:
		# --- Air phase ---
		_apply_friction(profile.air_friction, delta)
		_air_accelerate(wish_direction, wish_speed, delta)
		_apply_gravity(delta)

	move_and_slide()
	_update_floor_state()


## Supply intent from outside. Use it when [member intent_source] is unset --
## a bot harness stepping the physics by hand, or a replay. Must be called
## before the physics tick that should act on it.
func set_intent(intent: MoveIntent) -> void:
	_intent.copy_from(intent)


## Horizontal speed in m/s. The number that matters for strafe telemetry: air
## strafing raises it without bound, so it is the readout a movement sweep
## scores against.
func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Look ---------------------------------------------------------------------

func _apply_look(look_delta: Vector2) -> void:
	if look_delta == Vector2.ZERO:
		return

	# Yaw is unclamped and lives on the body, so basis vectors used for the wish
	# direction rotate with the view for free.
	rotate_y(-look_delta.x)

	var pitch_delta: float = look_delta.y if profile.invert_look_y else -look_delta.y
	_pitch = clampf(
		_pitch + pitch_delta,
		deg_to_rad(profile.pitch_min_degrees),
		deg_to_rad(profile.pitch_max_degrees),
	)
	if head != null:
		head.rotation.x = _pitch


# --- Wish direction -----------------------------------------------------------

## The player's move request in world space, with a magnitude of at most 1.
##
## Flattened to the horizontal plane: vertical velocity is gravity's and the
## jump's business alone. Because only the head pitches, the body's basis is
## already horizontal and the projection is normally a no-op -- it is here so
## that anything which ever tilts the body (knockback, a ramp, a death ragdoll
## handing back control) cannot turn a forward key into lift.
func _get_wish_vector() -> Vector3:
	var basis_right: Vector3 = global_transform.basis.x
	var basis_forward: Vector3 = -global_transform.basis.z
	var wish: Vector3 = basis_right * _intent.move_direction.x + basis_forward * _intent.move_direction.y
	wish.y = 0.0
	return wish if wish.length_squared() <= 1.0 else wish.normalized()


# --- Jumping ------------------------------------------------------------------

func _tick_jump_timers(on_floor: bool, delta: float) -> void:
	_coyote_timer = profile.coyote_time if on_floor else maxf(_coyote_timer - delta, 0.0)
	if _intent.jump_pressed:
		_jump_buffer_timer = profile.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


## Returns true if the body left the ground this tick.
func _try_jump(on_floor: bool) -> bool:
	if not on_floor and _coyote_timer <= 0.0:
		return false

	# Held jump re-launches on the landing tick when auto bunny hopping is on;
	# otherwise only a buffered press counts, and the player must re-press.
	var wants_jump: bool = _jump_buffer_timer > 0.0 or (profile.auto_bunny_hop and _intent.jump_held)
	if not wants_jump:
		return false

	# Assigned, not added: an assignment makes jump height independent of the
	# vertical speed the body happened to have, so a hop off a downhill slope is
	# the same height as a hop off flat ground.
	velocity.y = profile.jump_velocity
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	jumped.emit()
	return true


# --- Quake movement primitives ------------------------------------------------

## Quake's PM_Accelerate.
##
## The rule is that acceleration may only ever raise the component of velocity
## that lies [i]along[/i] the wish direction, and only up to [param wish_speed].
## Once you are already moving that fast in that direction, add_speed goes
## non-positive and nothing is added at all -- no clamping of the velocity
## vector, no drag term. Speed above wish_speed is therefore never taken away
## here, only by friction. That asymmetry is the foundation the whole strafe
## model is built on.
func _accelerate(wish_direction: Vector3, wish_speed: float, acceleration: float, delta: float) -> void:
	var speed_along_wish: float = velocity.dot(wish_direction)
	var add_speed: float = wish_speed - speed_along_wish
	if add_speed <= 0.0:
		return
	var accel_speed: float = minf(acceleration * wish_speed * delta, add_speed)
	velocity += wish_direction * accel_speed


## Quake's air acceleration (QuakeWorld SV_AirAccelerate / Source
## CGameMovement::AirAccelerate).
##
## Identical to [method _accelerate] but for one line: the wish speed used to
## compute add_speed is clamped to the very small
## [member MovementProfile.max_air_speed], while the wish speed that scales the
## acceleration is left unclamped. Two consequences, and they are the technique:
##
## 1. add_speed saturates the acceleration at essentially every tick, so the
##    body gains at most max_air_speed of velocity per tick, [i]in the wish
##    direction[/i].
## 2. Point the wish direction nearly perpendicular to current velocity -- hold
##    a strafe key and turn the mouse the same way -- and that small addition is
##    almost entirely perpendicular, so the dot product it feeds back into
##    add_speed barely grows while the resulting vector is longer than what you
##    started with. Speed accumulates every tick you keep the angle, without
##    limit, and is only lost on touching the ground.
##
## Sprinting deliberately does not raise the cap, matching sv_maxairspeed being
## an absolute in every engine in this family: the air is where skill decides
## your speed, not the sprint key.
func _air_accelerate(wish_direction: Vector3, wish_speed: float, delta: float) -> void:
	var capped_wish_speed: float = minf(wish_speed, profile.max_air_speed)
	var speed_along_wish: float = velocity.dot(wish_direction)
	var add_speed: float = capped_wish_speed - speed_along_wish
	if add_speed <= 0.0:
		return
	var accel_speed: float = minf(profile.air_acceleration * wish_speed * delta, add_speed)
	velocity += wish_direction * accel_speed


## Quake's PM_Friction.
##
## Scales horizontal velocity down by a drop proportional to speed, except that
## below stop_speed the drop is computed as if the body were moving at
## stop_speed. Without that floor the decay is exponential and the last fraction
## of a metre per second takes forever, which reads as ice.
func _apply_friction(coefficient: float, delta: float) -> void:
	if coefficient <= 0.0:
		return

	var speed: float = get_horizontal_speed()
	if speed < profile.friction_speed_epsilon:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var control: float = maxf(speed, profile.friction_stop_speed)
	var new_speed: float = maxf(speed - control * coefficient * delta, 0.0)
	var scale: float = new_speed / speed
	velocity.x *= scale
	velocity.z *= scale


func _apply_gravity(delta: float) -> void:
	velocity.y = maxf(
		velocity.y - profile.get_effective_gravity() * delta,
		-profile.terminal_velocity,
	)


# --- Floor state --------------------------------------------------------------

func _update_floor_state() -> void:
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(_fall_speed)
	elif not on_floor:
		_fall_speed = maxf(-velocity.y, 0.0)
	_was_on_floor = on_floor
