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

## Emitted on the tick a slide opens, carrying the horizontal speed the body has
## [b]after[/b] the entry boost -- the number a slide's dust, camera dip and
## audio should be scaled by.
signal slide_started(entry_speed: float)

## Emitted on the tick a slide closes, however it closed: the timer ran out, the
## speed floor was hit, the key was released, the body left the floor, or the
## player jumped out of it.
signal slide_ended()

## Emitted on the tick the body drops into the crouch stance, and on the tick it
## stands back up. Carries the state rather than being two signals, because a
## crouch has no "how it ended" to report the way a slide does -- the key went
## up, or the body left the floor.
signal crouch_changed(crouching: bool)

## Emitted whenever a timed speed boost (see [method apply_speed_boost]) ticks
## or ends. [param remaining] is seconds left, 0.0 on the tick it ends.
signal speed_boost_changed(remaining: float)

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

## The capsule the crouch shrinks. Optional, and the one export whose absence is
## not an error: a body without it still crouches -- the head still drops, the
## speed still falls -- it simply never gets smaller, which is the behaviour
## every body in the game had before the crouch existed.
##
## It is named rather than searched for so a scene that means to have a shrinking
## crouch says so. See [method _apply_stance] for what is done to it, and
## [method _has_headroom_to_stand] for the check that keeps standing up from
## pushing the capsule through a ceiling.
@export var collision: CollisionShape3D

## Multiplier on the target ground speed this body is driven at. 1.0 is the
## [MovementProfile]'s own pace and is what every living body runs on.
##
## It scales the WISH SPEED and nothing else, so a body running at 1.25 is
## accelerated by the same Quake routine, held by the same friction and capped
## by the same air-strafe rule as one running at 1.0 -- it is only asking to go
## somewhere faster. It is deliberately not a field on [MovementProfile]: the
## profile describes what a body IS, and this is a state the match puts a body
## into and takes back off it.
##
## [MatchController] is the only thing that writes it, for a ghost. See
## [member GhostProfile.speed_multiplier].
var speed_scale: float = 1.0

## Set every tick, either from [member intent_source] or by an outside caller
## via [method set_intent].
var _intent: MoveIntent = MoveIntent.new()

## Head pitch in radians, kept here rather than read back off the node so the
## clamp cannot drift through repeated euler conversions.
var _pitch: float = 0.0

## Time left in which a jump is still allowed after leaving the ground.
var _coyote_timer: float = 0.0
## Velocity a boost pad asked for, applied on the next physics tick. See launch().
var _pending_launch: Vector3 = Vector3.ZERO
var _has_pending_launch: bool = false

## Time left in which a jump press made in the air still counts on landing.
var _jump_buffer_timer: float = 0.0

## Multiplier a timed speed boost (a race power-up) applies to ground max
## speed and ground acceleration while [member _speed_boost_timer] is running.
## 1.0 outside one; scaled in at the point of use in [method _physics_process],
## never written into [member profile].
var _speed_boost_multiplier: float = 1.0
var _speed_boost_timer: float = 0.0

## Downward speed on the last airborne tick, reported by [signal landed].
var _fall_speed: float = 0.0

var _was_on_floor: bool = true

## True while the slide state owns the movement. See [method _update_slide].
var _sliding: bool = false

## Seconds the current slide has been open, against
## [member MovementProfile.slide_max_duration].
var _slide_timer: float = 0.0

## Dead time left before another slide may open.
var _slide_cooldown_timer: float = 0.0

## Time left in which a slide press made in the air still counts on landing.
var _slide_buffer_timer: float = 0.0

## Last tick's [member MoveIntent.slide_pressed], so the buffer is filled by the
## rising edge and never by the level.
##
## [member MoveIntent.slide_pressed] is documented as an edge and every shipped
## [IntentSource] consumes it as one, but [method set_intent] hands this node
## whatever the caller last wrote: a replay, a harness or a peer that fills one
## struct and reuses it delivers a press that stays true for as long as the
## button is down. Read as a level, that press refills the buffer on every tick
## and so defeats the zeroing in [method _begin_slide] -- a held key would
## re-open a slide the instant [member MovementProfile.slide_cooldown] lapsed,
## and the player would be locked into a chain of slides they never asked for,
## steering at [member MovementProfile.slide_acceleration] until the speed floor
## finally broke the chain. Latching here means the rule holds however careful
## the source is: one press, one slide, and re-pressing is how you slide again.
var _was_slide_pressed: bool = false

## The head's authored local height, captured once so the slide crouch is an
## offset from the scene's value rather than a number this file invents.
var _head_base_y: float = 0.0

## Current crouch offset applied to the head, in metres (negative is down).
var _head_offset: float = 0.0

## True while the body is held in the crouch stance. See [method _update_crouch].
var _crouching: bool = false

## The capsule's authored height, captured once so the crouch is a change to the
## scene's value rather than to a number this file invents. Zero when there is no
## [member collision] to measure.
var _standing_height: float = 0.0

## The capsule's radius, which the crouch never changes. It is the floor the
## crouch height is clamped against (Godot will not hold a capsule shorter than
## twice its radius) and the radius the headroom probe is built at.
var _capsule_radius: float = 0.0

## The [member collision] node's authored local height. The crouch moves the node
## DOWN by half the height it removes, which is what keeps the bottom of the
## capsule -- the part that stands on the floor -- exactly where it was.
var _collision_base_y: float = 0.0

## This body's own copy of the capsule, so resizing it crouches THIS prisoner and
## not every prisoner in the match. See [method _ready].
var _capsule: CapsuleShape3D = null

## The shape and the query the headroom check reuses, built once on first use.
## Allocating a [PhysicsShapeQueryParameters3D] per tick would put the one part
## of the movement that runs a space query on the allocator's critical path.
var _headroom_shape: CapsuleShape3D = null
var _headroom_query: PhysicsShapeQueryParameters3D = null


func _ready() -> void:
	if profile == null:
		push_error("PlayerController has no MovementProfile; the body cannot move.")
		set_physics_process(false)
		return

	if head != null:
		_head_base_y = head.position.y

	_capture_capsule()
	_adopt_profile()


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
	_tick_slide_timers(delta)
	_tick_speed_boost(delta)

	if on_floor:
		# Gravity accumulated while falling is spent; keep it and every landing
		# would drag the body downhill and confuse the floor snap.
		velocity.y = 0.0

	# A launch (boost pad) is applied HERE, after the floor zeroing, for the same
	# reason a jump is: written any earlier it is wiped on this line.
	if _has_pending_launch:
		velocity = _pending_launch
		_has_pending_launch = false
		_coyote_timer = 0.0

	# Slide OPENS before the jump, and deliberately so: a slide opened on this
	# tick can be jumped out of on this same tick, which is what makes "slide,
	# then hop out of it" one motion rather than two. The entry boost is already
	# in the velocity by the time _try_jump runs, so the hop carries it. A slide
	# CLOSES after the move instead -- see _update_slide_exit.
	_try_begin_slide(on_floor)

	if _try_jump(on_floor):
		_end_slide()
		# A jump makes the rest of this tick an air tick. This is not a detail:
		# skipping ground friction on the launch frame is precisely what lets a
		# bunny hop keep the speed it arrived with. Apply friction first and the
		# technique dies.
		on_floor = false

	# After the slide and after the jump, both of which outrank it: a tick that
	# opened a slide or left the ground is not a tick spent crouching.
	_update_crouch(on_floor)

	# Quake splits the request into a unit direction and a scalar target speed;
	# a part-pressed stick is a proportionally lower target, not a shorter
	# vector, so that the accelerate routines stay dimensionally correct.
	var wish_vector: Vector3 = _get_wish_vector()
	var wish_direction: Vector3 = wish_vector.normalized()
	var wish_speed: float = _target_speed(on_floor) * wish_vector.length() * speed_scale

	if _sliding:
		# --- Slide phase ---
		# The third branch the ground and air cases always had room for. Same
		# three primitives, different numbers: a fraction of standing friction,
		# a weak version of ground acceleration for steering, and gravity's pull
		# along whatever the body is lying on.
		_apply_friction(profile.slide_friction, delta)
		_accelerate(wish_direction, wish_speed, profile.slide_acceleration, delta)
		_apply_slope_assist(delta)
	elif on_floor:
		# --- Ground phase ---
		# A speed boost scales ground max speed and ground acceleration HERE,
		# at the point of use -- profile.ground_acceleration itself is never
		# touched, so a boost cannot bleed into the slide or air phases, which
		# read wish_speed and the profile unscaled.
		_apply_friction(profile.friction, delta)
		_accelerate(
			wish_direction,
			wish_speed * _speed_boost_multiplier,
			profile.ground_acceleration * _speed_boost_multiplier,
			delta,
		)
	else:
		# --- Air phase ---
		_apply_friction(profile.air_friction, delta)
		_air_accelerate(wish_direction, wish_speed, delta)
		_apply_gravity(delta)

	_settle_head(delta)
	move_and_slide()
	_update_floor_state()
	_update_slide_exit(delta)


## Supply intent from outside. Use it when [member intent_source] is unset --
## a bot harness stepping the physics by hand, or a replay. Must be called
## before the physics tick that should act on it.
func set_intent(intent: MoveIntent) -> void:
	_intent.copy_from(intent)


## Swap the tunables this body moves under, mid-session and mid-stride.
##
## Assigning [member profile] alone is not enough and is the trap this method
## exists to close: three things are read out of the profile exactly once, at
## ready -- the floor angle, the floor snap length, and whatever the
## [IntentSource] took from [method IntentSource.configure] (mouse sensitivity,
## today). A raw assignment leaves all three describing the profile that was
## replaced, so a body handed a new profile keeps the old one's walkable slope
## and the old one's aim speed while obeying the new one's physics. Nothing
## errors; the body simply behaves like neither profile.
##
## Velocity, the slide state and the jump timers are deliberately left alone: a
## swap made in mid-air must not teleport, stop or re-launch the body, or the
## profiles being compared cannot be compared back to back.
##
## [b]Not part of the game.[/b] Nothing in a match calls this; it exists so a
## dev scene can put two tunings under the same hands a second apart, and so a
## headless sweep can drive one body through a list of profiles without
## rebuilding the world between them.
func set_profile(new_profile: MovementProfile) -> void:
	if new_profile == null:
		push_error("PlayerController.set_profile was handed null; keeping the current profile.")
		return
	profile = new_profile
	_adopt_profile()


## Push the profile's values into the things that cache them. Called at ready
## and by [method set_profile]; see there for why it is not inlined.
func _adopt_profile() -> void:
	floor_max_angle = deg_to_rad(profile.max_floor_angle_degrees)
	floor_snap_length = profile.floor_snap_length
	floor_stop_on_slope = true

	if intent_source != null:
		intent_source.configure(profile)

	# The capsule is sized from the profile too, and a body mid-crouch when the
	# swap happens must end the tick at the NEW profile's crouch height rather
	# than at the height the retired profile asked for.
	_apply_stance()


## Horizontal speed in m/s. The number that matters for strafe telemetry: air
## strafing raises it without bound, so it is the readout a movement sweep
## scores against.
func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Start (or refresh) a timed ground-speed boost -- a race power-up. Ground max
## speed and ground acceleration run at [param multiplier] for [param seconds].
func apply_speed_boost(multiplier: float, seconds: float) -> void:
	_speed_boost_multiplier = multiplier
	_speed_boost_timer = seconds
	speed_boost_changed.emit(_speed_boost_timer)


## Seconds left on the current speed boost; 0.0 when none is active.
func get_speed_boost_remaining() -> float:
	return _speed_boost_timer


## The multiplier a speed boost is applying; 1.0 when none is active.
func get_speed_boost_multiplier() -> float:
	return _speed_boost_multiplier if _speed_boost_timer > 0.0 else 1.0


func _tick_speed_boost(delta: float) -> void:
	if _speed_boost_timer <= 0.0:
		return
	_speed_boost_timer = maxf(_speed_boost_timer - delta, 0.0)
	speed_boost_changed.emit(_speed_boost_timer)
	if _speed_boost_timer <= 0.0:
		_speed_boost_multiplier = 1.0


## True while the body is in the slide state.
func is_sliding() -> bool:
	return _sliding


## Seconds the current slide has left before it times out; 0.0 when not sliding.
## The other two ways a slide can end -- the speed floor and the released key --
## are not clocks and are not reported here.
func get_slide_time_remaining() -> float:
	if not _sliding:
		return 0.0
	return maxf(profile.slide_max_duration - _slide_timer, 0.0)


## Seconds until another slide may be opened; 0.0 when one may be opened now.
func get_slide_cooldown_remaining() -> float:
	return _slide_cooldown_timer


## True while the body is held in the crouch stance.
##
## Deliberately has no companion clock: unlike [method get_slide_time_remaining]
## there is nothing to count down. A crouch lasts exactly as long as the key.
func is_crouching() -> bool:
	return _crouching


## The collision capsule's current height in metres -- the standing height, or
## [member MovementProfile.crouch_height] while crouched. 0.0 when this body has
## no [member collision] to measure.
##
## This is the number the guard is really shooting at, so it is exposed rather
## than left for a caller to dig out of the shape.
func get_stance_height() -> float:
	if _capsule == null:
		return 0.0
	return _capsule.height


## The head's current local height, crouch and slide offsets included. The eye
## position a spectator camera or a test should read, rather than reaching into
## [member head] and having to know about [member _head_base_y].
func get_eye_height() -> float:
	if head == null:
		return 0.0
	return head.position.y


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
## Throw the body at [param velocity_vector] on the next tick, surviving floor contact.
func launch(velocity_vector: Vector3) -> void:
	_pending_launch = velocity_vector
	_has_pending_launch = true


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


# --- Sliding ------------------------------------------------------------------
#
# The slide is the game's third movement state and its only deliberate source of
# free speed. Everything about it is a number in [MovementProfile]; the rules it
# obeys are:
#
#   ENTER  on the floor, above slide_min_entry_speed, MOVING FORWARD (see
#          _press_asks_for_a_slide), off cooldown, with a fresh slide press
#          inside the buffer window. Fresh, not held: holding the key through a
#          slide-hop does not re-open a slide on landing, and the player
#          re-presses to slide again. A press that fails the speed or the
#          forward test is not an error -- it is a crouch, which is the same
#          key's other meaning. See the Crouching section below.
#   REWARD one boost along the current heading, up to slide_boost_speed_cap and
#          never downwards -- a body already faster than the cap keeps its speed
#          and is simply not paid again.
#   HOLD   slide_friction instead of friction, weak ground acceleration for
#          steering, and gravity's tangential pull on a slope.
#   END    on the timer, on the speed floor, on releasing the key, on leaving
#          the floor, or on jumping out of it -- and then a cooldown.
#
# The state deliberately owns no velocity clamp of its own. A slide never takes
# speed away except through friction, which is what lets it be the way a player
# carries air-strafe speed through a landing rather than a thing that resets it.

func _tick_slide_timers(delta: float) -> void:
	# The rising edge fills the buffer; holding the key only lets it run down.
	# See _was_slide_pressed. A press made in the air is unaffected -- it fills
	# the buffer where it happened and still opens the slide on landing, which is
	# the whole reason slide_buffer_time exists.
	if _intent.slide_pressed and not _was_slide_pressed:
		_slide_buffer_timer = profile.slide_buffer_time
	else:
		_slide_buffer_timer = maxf(_slide_buffer_timer - delta, 0.0)
	_was_slide_pressed = _intent.slide_pressed
	_slide_cooldown_timer = maxf(_slide_cooldown_timer - delta, 0.0)


## Open a slide if this tick may open one. Runs before the jump and before any
## acceleration is applied.
##
## A press that gets this far and fails [method _press_asks_for_a_slide] is not
## wasted and is not an error: it falls through to the crouch, which is the other
## half of what this key now means. The buffer is deliberately NOT spent on the
## way past, so a press made in the air while turning still opens the slide on
## the tick the body is finally pointing where it is going.
func _try_begin_slide(on_floor: bool) -> void:
	if _sliding:
		return
	if not on_floor or _slide_cooldown_timer > 0.0 or _slide_buffer_timer <= 0.0:
		return
	if not _press_asks_for_a_slide():
		return
	_begin_slide()


## Which of the slide key's two meanings this press carries: true for the slide,
## false for the crouch.
##
## [b]The author's rule, in two lines of code[/b] ("you shoudl slide when moving
## forward and crouching. otherwise just crouch"). Moving: horizontal speed at or
## above [member MovementProfile.slide_min_entry_speed], the threshold a slide
## always had. Forward: the wish direction's forward component at or above
## [member MovementProfile.slide_min_forward_intent].
##
## [b]Why the intent and not the velocity.[/b] The discriminator reads
## [MoveIntent] and the body's own speed and nothing else, so it is identical for
## a hand on a keyboard, a [BotIntentSource] and a [RemoteIntentSource] replaying
## a peer's commands -- there is no branch anywhere that asks what kind of thing
## is driving. Reading the velocity's alignment with the facing instead would
## make the answer depend on which way the mouse had been turned since, so a
## player who flicks the view while running would get a crouch out of a key they
## pressed to slide.
func _press_asks_for_a_slide() -> bool:
	if get_horizontal_speed() < profile.slide_min_entry_speed:
		return false
	return _intent.move_direction.y >= profile.slide_min_forward_intent


## Close the slide if this tick was its last. Runs [b]after[/b] the move.
##
## Closing after the move rather than before it is the whole reason the slide's
## outcome does not depend on the physics tick rate. Test the conditions first
## and the tick that finds one true is a tick the body spends under standing
## friction, not slide friction -- a single tick that costs
## [code]friction * delta[/code] of speed, which is 10% at 60 Hz and 20% at
## 30 Hz. The same slide then ends 12% faster on a slower machine. Closing here
## means a slide is always a whole number of slide-friction ticks and the tick
## after it is an ordinary ground tick.
##
## It also reads a fresher [method CharacterBody3D.is_on_floor] than the value
## the top of the tick had, which is what catches a slide off the end of a
## ledge on the tick it actually leaves.
func _update_slide_exit(delta: float) -> void:
	if not _sliding:
		return
	_slide_timer += delta

	if not is_on_floor():
		# Slid off an edge. Ending it here rather than letting it run in the air
		# is what stops a slide from being a flight mode with no gravity branch.
		_end_slide()
	elif profile.slide_requires_hold and not _intent.slide_held:
		_end_slide()
	elif _slide_timer + delta * 0.5 >= profile.slide_max_duration:
		# Half a tick of slack, so the deadline rounds to the nearest tick
		# instead of always overshooting it. Without it a duration that is not a
		# whole multiple of the tick length buys an extra tick at one rate and
		# not at another, and the two rates part company by that tick's friction.
		_end_slide()
	elif get_horizontal_speed() < profile.slide_exit_speed:
		_end_slide()


func _begin_slide() -> void:
	_sliding = true
	_slide_timer = 0.0
	# Spent, so a single press cannot open a second slide the moment this one's
	# cooldown expires.
	_slide_buffer_timer = 0.0
	_apply_slide_boost()
	slide_started.emit(get_horizontal_speed())


## Scale horizontal velocity up by [member MovementProfile.slide_entry_boost],
## but never past [member MovementProfile.slide_boost_speed_cap] and never
## downwards.
##
## The direction is untouched: a slide is a commitment to the heading you
## entered on, and rotating the velocity here would make it a free turn as well
## as free speed.
func _apply_slide_boost() -> void:
	var speed: float = get_horizontal_speed()
	if speed <= 0.0:
		return
	# maxf against the current speed is what makes the cap a ceiling on the
	# reward rather than a cap on the body: arrive at 20 m/s off an air strafe
	# and you keep all 20.
	var ceiling: float = maxf(speed, profile.slide_boost_speed_cap)
	var boosted: float = minf(speed + profile.slide_entry_boost, ceiling)
	var scale: float = boosted / speed
	velocity.x *= scale
	velocity.z *= scale


func _end_slide() -> void:
	if not _sliding:
		return
	_sliding = false
	_slide_timer = 0.0
	_slide_cooldown_timer = profile.slide_cooldown
	slide_ended.emit()


## Gravity's pull along the floor, applied only while sliding.
##
## The floor normal's horizontal part points downhill and has length sin(theta);
## multiplying by the normal's own y component (cos(theta)) gives the horizontal
## component of a frictionless body's acceleration on that slope. So with
## [member MovementProfile.slide_slope_acceleration] set equal to
## [member MovementProfile.gravity], a slide down a ramp accelerates exactly as
## a body on a frictionless plane would, minus slide friction.
##
## It is signed, not one-way: sliding uphill is slowed by the same term.
func _apply_slope_assist(delta: float) -> void:
	if profile.slide_slope_acceleration <= 0.0 or not is_on_floor():
		return
	var normal: Vector3 = get_floor_normal()
	var downhill: Vector3 = Vector3(normal.x, 0.0, normal.z)
	if downhill.length_squared() <= 0.0:
		return
	velocity += downhill * (profile.slide_slope_acceleration * normal.y * delta)


# --- Crouching ----------------------------------------------------------------
#
# The slide key's other meaning, and structurally the opposite of the slide in
# every respect except the button it shares.
#
#   SLIDE   edge-triggered, buffered, boosted, timed, on a cooldown.
#   CROUCH  level-driven, unbuffered, unpaid, untimed, on nothing.
#
# [b]How those two live on one key.[/b] They read DIFFERENT FIELDS of it.
# [member MoveIntent.slide_pressed] is the edge and it belongs to the slide
# alone -- [method _tick_slide_timers] still latches its rising edge, still fills
# the buffer from it and never from the level, so holding the key through a
# slide-hop still cannot re-open a slide on landing and slide-hopping is exactly
# the technique it was. [member MoveIntent.slide_held] is the level and it is all
# the crouch ever looks at: no buffer to arm, no edge to spend, no cooldown to
# clear. A key held down is therefore a crouch by construction and a slide only
# on the tick it went down, which is the only arrangement in which "held" and
# "edge-triggered" are both true of the same button and neither is a special
# case of the other.
#
# The fall-through is the whole feel of it: a press that asks for a slide and is
# refused -- too slow, or not going forward -- is not swallowed, it simply lands
# on the crouch. And a slide that ends under a still-held key drops into a crouch
# on the next tick rather than popping the prisoner upright in the open.

## Decide this tick's stance. Runs after [method _try_begin_slide] and after
## [method _try_jump], both of which outrank it.
##
## The one thing that can hold a crouch against the player's will is geometry:
## see [method _has_headroom_to_stand]. A crouch that cannot be left is left
## crouched, every tick, until there is room -- which is what stops a body from
## growing back into a ceiling.
func _update_crouch(on_floor: bool) -> void:
	# Airborne is not a stance. Leaving the crouch out of the air keeps the air
	# phase bit-for-bit what it was -- same wish speed, same capsule, same
	# saturation against max_air_speed -- so nothing about air strafing or
	# slide-hopping can be changed by a key that happens to still be down.
	var wants: bool = _intent.slide_held and not _sliding and on_floor
	if not wants and _crouching and not _has_headroom_to_stand():
		return
	_set_crouched(wants)


func _set_crouched(crouching: bool) -> void:
	if crouching == _crouching:
		return
	_crouching = crouching
	_apply_stance()
	crouch_changed.emit(_crouching)


## The target speed the ground phase accelerates towards.
##
## [param on_floor] rather than [member _crouching] alone, so the speed penalty
## is a property of crouched GROUND movement. A body still crouched in the air --
## which only happens when a ceiling refused to let it stand -- flies on the
## standing number, because the alternative is a wish speed that silently changes
## the air-acceleration rate mid-flight.
func _target_speed(on_floor: bool) -> float:
	if _crouching and on_floor:
		return profile.crouch_speed
	return profile.ground_speed


## Read the authored capsule once, and take a private copy of it.
##
## [b]The copy is not optional.[/b] A [SubResource] written inside a
## [PackedScene] is one object shared by every instance of that scene, so
## resizing the shape on the node would crouch all four prisoners and the guard
## together, from whichever one of them pressed the key. Duplicating here makes
## the capsule this body's own.
func _capture_capsule() -> void:
	if collision == null:
		return
	var authored: CapsuleShape3D = collision.shape as CapsuleShape3D
	if authored == null:
		# Not an error: a body shaped out of something else still crouches, it
		# just does not shrink. Said out loud so it is not mistaken for one.
		push_warning("PlayerController's collision shape is not a CapsuleShape3D; the crouch will not shrink it.")
		return
	_capsule = authored.duplicate() as CapsuleShape3D
	collision.shape = _capsule
	_standing_height = _capsule.height
	_capsule_radius = _capsule.radius
	_collision_base_y = collision.position.y


## The height the capsule takes while crouched, clamped to what a capsule can
## actually be: Godot holds a capsule to at least twice its radius, and clamping
## here rather than letting the physics server do it silently means a profile
## that asks for the impossible gets the nearest legal body instead of a body
## whose height does not match its own tunables.
func _crouched_capsule_height() -> float:
	return clampf(profile.crouch_height, _capsule_radius * 2.0, _standing_height)


## Resize the capsule to the current stance.
##
## The height changes in one step, not over a settle: an interpolated collision
## volume is a body that is briefly neither size, and the shooter would be
## leading a hitbox that is a different height on his machine than on the
## runner's. The HEAD eases (see [method _settle_head]) because that is a camera
## and nobody is hit by it.
##
## Only the TOP moves. The node is dropped by half the height removed, so the
## bottom of the capsule -- the part standing on the floor -- does not move, the
## body cannot be pushed through the ground by crouching, and standing back up
## can only ever grow upwards, into the space [method _has_headroom_to_stand] has
## already been asked about.
func _apply_stance() -> void:
	if _capsule == null:
		return
	var height: float = _crouched_capsule_height() if _crouching else _standing_height
	_capsule.height = height
	collision.position.y = _collision_base_y - (_standing_height - height) * 0.5


## Is there room above the crouched capsule for the standing one?
##
## The probe is a capsule of the body's own radius that spans from inside the
## crouched volume up to exactly where the standing capsule's crown would be --
## height [code](standing - crouched) + 2 * radius[/code], centred so its top cap
## coincides with the standing cap. Two properties make that the right shape:
##
## 1. It is a strict subset of the standing capsule, so it can never report a
##    ceiling the body would have fitted under.
## 2. Its bottom sits well inside the crouched capsule, which is space the body
##    already occupies and is therefore known to be clear -- so it never touches
##    the floor the body is standing on. Probing with the standing capsule itself
##    would have its foot on the ground and report "blocked" every single tick.
##
## Returns true -- stand up -- when there is nothing to query against, which is
## the honest answer for a body that is not in a world yet rather than a body
## trapped by a space that does not exist.
func _has_headroom_to_stand() -> bool:
	if _capsule == null:
		return true
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var crouched: float = _crouched_capsule_height()
	var gained: float = _standing_height - crouched
	if gained <= 0.0:
		return true

	if _headroom_shape == null:
		_headroom_shape = CapsuleShape3D.new()
	_headroom_shape.radius = _capsule_radius
	_headroom_shape.height = gained + _capsule_radius * 2.0

	if _headroom_query == null:
		_headroom_query = PhysicsShapeQueryParameters3D.new()
		_headroom_query.shape = _headroom_shape
		_headroom_query.collide_with_bodies = true
		_headroom_query.collide_with_areas = false
		# Zero, not the character controller's safe margin: this is a question
		# about whether a volume is empty, and a margin would answer a slightly
		# larger question and refuse tight gaps the body does in fact fit.
		_headroom_query.margin = 0.0
		# Typed, and built once: the exclusion has to be this body or the query
		# trivially hits the very capsule it is asking about, and an untyped
		# array literal will not assign to an Array[RID] property.
		var exclusions: Array[RID] = [get_rid()]
		_headroom_query.exclude = exclusions
	# Refreshed every call, because a body is free to change which layers it
	# collides with between one crouch and the next.
	_headroom_query.collision_mask = collision_mask
	# Identity basis, not the body's: only yaw ever turns this body, a capsule is
	# a solid of revolution about its own Y, and taking the basis verbatim would
	# tip the probe over the day something ever tilts the body.
	var standing_top: float = _collision_base_y + _standing_height * 0.5
	_headroom_query.transform = Transform3D(
		Basis.IDENTITY,
		global_position + Vector3.UP * (standing_top - _headroom_shape.height * 0.5),
	)

	# One hit is all the answer needs; asking for more is asking the physics
	# server to sort a list nobody reads.
	return world.direct_space_state.intersect_shape(_headroom_query, 1).is_empty()


## Move the head towards or away from the low stance -- the slide's, or the
## crouch's.
##
## [b]The slide's drop is still cosmetic.[/b] A slide does not resize the capsule
## and never has: it already buys speed, and buying a smaller hitbox with the
## same key would make the runner harder to hit at the exact moment they are
## hardest to lead. [b]The crouch's is not.[/b] There the capsule really does come
## down (see [method _apply_stance]) and this drop is what keeps the eye inside
## the volume a shooter can hit, so a crouched player cannot see over cover their
## silhouette is hidden behind.
##
## The two states have their own drop and their own rate, and the slide outranks
## the crouch on the tick both are somehow true, because a slide is the more
## specific thing.
##
## The approach is exponential rather than a linear lerp so the settle takes the
## same wall-clock time at any physics tick rate.
func _settle_head(delta: float) -> void:
	if head == null:
		return
	# The slide's rate is the snap INTO a slide and belongs to the slide alone;
	# everything else -- dropping into a crouch, and rising out of either state --
	# uses the crouch's gentler rate, because standing back up is not an event.
	var target: float = 0.0
	var rate: float = profile.crouch_camera_settle_rate
	if _sliding:
		target = -profile.slide_camera_drop
		rate = profile.slide_camera_settle_rate
	elif _crouching:
		target = -profile.crouch_camera_drop

	if rate <= 0.0:
		_head_offset = target
	else:
		_head_offset = lerpf(_head_offset, target, 1.0 - exp(-rate * delta))
	head.position.y = _head_base_y + _head_offset


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
## The ground speed deliberately does not raise the cap, matching sv_maxairspeed
## being an absolute in every engine in this family: the air is where skill
## decides your speed, not the movement keys.
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
