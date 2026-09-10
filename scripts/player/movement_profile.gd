class_name MovementProfile
extends Resource

## Every tunable number for [PlayerController] lives here.
##
## Nothing about how a body moves may be hard-coded in the controller: the
## project settles design questions by sweeping variants of this resource in
## headless bot matches, so a constant buried in code is a constant that can
## never be tested. Add new knobs here, never there.
##
## Units are metres, seconds and radians unless a field name says otherwise.
##
## The defaults are metric conversions of the Quake / Half-Life numbers the
## strafe model was tuned against, so the movement starts at a known-good point
## rather than at a guess. Those engines measure in units of one inch
## (0.0254 m; a 72-unit player is 1.83 m tall), giving:
## [codeblock]
##   sv_maxspeed      320 u/s -> 8.13 m/s     sv_gravity      800 u/s^2 -> 20.3 m/s^2
##   sv_maxairspeed    30 u/s -> 0.76 m/s     jump velocity   268 u/s   ->  6.81 m/s
##   sv_stopspeed     100 u/s -> 2.54 m/s     sv_friction/accel are unitless
## [/codeblock]
## The acceleration and friction coefficients are unitless in that model and are
## carried across unchanged.

# --- Ground speed -------------------------------------------------------------

## Target horizontal speed on the ground. The only ground speed there is.
##
## There were two -- a walk at 8.0 and a sprint at 11.0 held on Shift -- until
## the author retired sprint ("for now we dont need sprint"). The number kept is
## the SPRINT one, deliberately: dropping the input must not make the game
## slower than the pace it was actually played and tuned at, and 11 m/s is what
## a player holding Shift and every bot crossing open ground was already doing.
## (Quake/HL sv_maxspeed is 320 u/s -> 8.13 m/s; this is above it, and the
## strafe model does not care -- the air cap is [member max_air_speed] and is
## independent of this.)
@export_range(0.0, 40.0, 0.1, "or_greater") var ground_speed: float = 11.0

# --- Acceleration -------------------------------------------------------------

## Ground acceleration coefficient (Quake/HL sv_accelerate, 10). Unitless: the
## controller multiplies it by the target speed, so it reads as "top speeds
## gained per second". Higher is snappier off the line.
@export_range(0.0, 60.0, 0.1, "or_greater") var ground_acceleration: float = 12.0

## Air acceleration coefficient (Quake/HL sv_airaccelerate, 10). Same units as
## [member ground_acceleration]. Note that in the source model this scales the
## *unclamped* wish speed, so at any sane value the per-tick air acceleration
## saturates against [member max_air_speed]; that saturation is normal and is
## what makes the strafe gain stable across framerates and speeds.
@export_range(0.0, 60.0, 0.1, "or_greater") var air_acceleration: float = 12.0

## Ceiling on the wish speed that air acceleration is allowed to accelerate
## *towards* -- it is NOT a cap on actual velocity, and the body routinely flies
## far faster than this. Deliberately tiny (Quake/HL sv_maxairspeed, 30 u/s).
##
## This single number is the entire reason air strafing exists: see
## [method PlayerController._air_accelerate]. Raise it and the air starts to
## behave like the ground, which kills strafe gain; lower it and turning in the
## air goes sluggish.
@export_range(0.0, 10.0, 0.01, "or_greater") var max_air_speed: float = 0.8

# --- Friction -----------------------------------------------------------------

## Ground friction coefficient (Quake III sv_friction, 6; Half-Life uses 4).
## Unitless -- see [method PlayerController._apply_friction]. Higher stops harder.
@export_range(0.0, 30.0, 0.1, "or_greater") var friction: float = 6.0

## Speed floor used by friction, so a nearly-stopped body still gets a full
## friction bite instead of creeping asymptotically (Quake sv_stopspeed).
@export_range(0.0, 20.0, 0.1, "or_greater") var friction_stop_speed: float = 2.5

## Speed below which the body is simply stopped, avoiding a divide by a
## vanishing speed in the friction scale (Quake's 1 u/s epsilon).
@export_range(0.0, 1.0, 0.001) var friction_speed_epsilon: float = 0.025

## Friction applied while airborne. Keep at 0.0 for the classic model: any
## non-zero value bleeds off strafe gain, which is the point of the movement.
@export_range(0.0, 30.0, 0.1, "or_greater") var air_friction: float = 0.0

# --- Jump ---------------------------------------------------------------------

## Upward velocity applied on jump (Quake/HL 268 u/s).
@export_range(0.0, 30.0, 0.1, "or_greater") var jump_velocity: float = 7.0

## Grace period after walking off a ledge during which a jump still counts.
## Quake has no such thing; every arena game shipped since does, because losing
## a jump to a one-tick timing miss reads as an engine fault, not as difficulty.
@export_range(0.0, 0.5, 0.005) var coyote_time: float = 0.1

## How long a jump press is remembered while airborne, so a press made just
## before touchdown still fires on landing.
@export_range(0.0, 0.5, 0.005) var jump_buffer_time: float = 0.12

## When true, holding jump re-jumps on the tick of landing (bunny hopping).
## When false, jump must be released and re-pressed.
@export var auto_bunny_hop: bool = true

# --- Gravity ------------------------------------------------------------------

## Base downward acceleration (Quake/HL sv_gravity, 800 u/s^2 -> 20.3 m/s^2;
## nudged up because arena movement wants a fast arc and no floaty airtime).
@export_range(0.0, 100.0, 0.1, "or_greater") var gravity: float = 22.0

## Per-profile multiplier on [member gravity]; the effective value is
## [code]gravity * gravity_scale[/code]. Exists so a sweep can scale gravity
## without disturbing the tuned base value.
@export_range(0.0, 4.0, 0.01, "or_greater") var gravity_scale: float = 1.0

## Maximum fall speed.
@export_range(0.0, 200.0, 1.0, "or_greater") var terminal_velocity: float = 60.0

# --- Slide --------------------------------------------------------------------
#
# The slide is a third movement state beside ground and air, with its own
# friction and its own acceleration, and it is the game's on-ramp: it is how a
# player converts a run into the speed that air strafing then compounds. The
# numbers below are chosen so that
#
#   ground_speed (11) -> slide entry boost -> slide_boost_speed_cap (14)
#
# is the fastest a player can go without ever leaving the ground, and everything
# past 14 m/s has to be earned in the air. That division is deliberate: the
# floor of the skill curve is a keypress, the ceiling is a technique.

## Smallest forward component of [member MoveIntent.move_direction] that still
## reads as "moving forward" for the purpose of opening a slide. Dimensionless:
## the intent is a unit-disc vector whose y is forward.
##
## [b]This is the discriminator between the two things the slide key does.[/b]
## Above it, with enough speed, the key opens a slide; below it -- or too slow --
## the same key holds a crouch. 0.5 is the cosine of 60 degrees, so W alone
## (1.0) and any W+strafe diagonal (0.707) both still slide, while a pure
## sideways or backwards run does not. It is read off [MoveIntent] and nothing
## else, which is what makes a bot's and a network peer's slide open on exactly
## the same condition a hand on the keyboard does.
@export_range(0.0, 1.0, 0.01) var slide_min_forward_intent: float = 0.5

## Slowest a body may be moving and still open a slide. Under the ground speed on
## purpose -- a slide is something you do out of a run, not a way to start
## moving, and a standing slide would be a free dodge with no commitment.
@export_range(0.0, 30.0, 0.1, "or_greater") var slide_min_entry_speed: float = 7.0

## Speed added along the current heading when a slide opens. The reward for
## timing an entry, and the reason a slide feels like a launch rather than a
## crouch.
@export_range(0.0, 20.0, 0.1, "or_greater") var slide_entry_boost: float = 3.0

## Ceiling the entry boost may raise a body to. [b]Not a speed cap[/b]: a body
## already faster than this keeps every metre per second it arrived with, it
## simply gets no boost. This is the single number that decides how much speed
## is available for free, so it is the first knob to reach for if slide-hopping
## outruns the shooter.
@export_range(0.0, 40.0, 0.1, "or_greater") var slide_boost_speed_cap: float = 14.0

## Friction while sliding, in the same units as [member friction]. Roughly a
## twentieth of standing friction: a slide is slippery, which is what makes it
## worth entering, and the small non-zero value is what stops a slide from being
## a permanent state.
@export_range(0.0, 30.0, 0.01, "or_greater") var slide_friction: float = 0.25

## Acceleration coefficient for steering during a slide, in the same units as
## [member ground_acceleration]. Fed to the ordinary Quake accelerate routine
## with the ordinary ground wish speed, so a slide steers by the same rule the
## ground does, only weakly.
##
## Note what that combination cannot do: because the wish speed is the full
## ground speed rather than [member max_air_speed], the acceleration is
## rate-limited rather than saturated, which is what keeps a slide's outcome
## identical at any physics tick rate -- and it means a slide can never gain
## speed the way an air strafe does, because acceleration stops entirely once
## velocity along the wish direction reaches walk pace.
@export_range(0.0, 60.0, 0.1, "or_greater") var slide_acceleration: float = 3.0

## Downhill acceleration while sliding, in m/s^2 at a vertical face. The
## controller scales it by the floor's own gradient, so setting it equal to
## [member gravity] makes a slide down a ramp behave like a body on a
## frictionless slope. Lower it to make hills less rewarding; zero disables
## slope assist entirely.
@export_range(0.0, 100.0, 0.1, "or_greater") var slide_slope_acceleration: float = 22.0

## Longest a single slide may last. A slide ends on its own even at full speed,
## so it is a burst and never a stance.
@export_range(0.0, 5.0, 0.01, "or_greater") var slide_max_duration: float = 1.0

## Speed at which a slide ends itself. Without this a slide bleeds down to a
## crawl and leaves the player lying on the floor with no speed and no control.
@export_range(0.0, 20.0, 0.1, "or_greater") var slide_exit_speed: float = 5.0

## Dead time after a slide ends before another may open. Stops a slide from
## being re-triggered on the tick it closed, which would make the entry boost a
## per-tick income rather than a per-slide reward.
@export_range(0.0, 2.0, 0.005) var slide_cooldown: float = 0.25

## How long a slide press is remembered while airborne, so a press made just
## before touchdown opens the slide on the landing tick. The same courtesy
## [member jump_buffer_time] extends to jumping, and the thing that makes a
## slide-hop chain reachable by a human instead of frame-perfect.
@export_range(0.0, 0.5, 0.005) var slide_buffer_time: float = 0.12

## When true, releasing the slide button ends the slide. Turn it off for a
## fire-and-forget slide that always runs its full course.
@export var slide_requires_hold: bool = true

## How far the head drops while sliding, in metres. Cosmetic: the collision
## capsule does [b]not[/b] shrink, so a slide never makes a body harder to hit.
## That is still true now that the CROUCH does shrink it (see
## [member crouch_height]) and is the deliberate difference between the two
## halves of the same key: a slide buys speed, a crouch buys cover, and neither
## buys both. See [method PlayerController._settle_head].
@export_range(0.0, 1.5, 0.01) var slide_camera_drop: float = 0.45

## Rate the head moves to and from the slide crouch, per second. Applied as an
## exponential approach, so the settle takes the same wall-clock time at any
## tick rate.
@export_range(0.1, 60.0, 0.1, "or_greater") var slide_camera_settle_rate: float = 14.0

# --- Crouch -------------------------------------------------------------------
#
# The other half of the slide key, and the one that is a STANCE rather than a
# burst. Where a slide is edge-triggered, timed, boosted and on a cooldown, a
# crouch is none of those: it is held, it lasts exactly as long as the key does,
# it pays nothing and it costs speed.
#
# It is also the only thing in the movement kit that changes how big a body IS.
# The guard shoots at a silhouette, so a crouched prisoner is a smaller target
# and can shrink behind cover the kit previously had no answer for -- which
# makes these four numbers combat tuning as much as movement tuning.

## Height of the collision capsule while crouched, in metres, against a standing
## 1.8 (see [code]scenes/player/player.tscn[/code]). The bottom of the capsule
## stays where it is and the TOP comes down, so a crouched body keeps standing
## on the same floor while presenting two thirds of the silhouette.
##
## Two thirds is the point of the number: it is a real reduction in what a
## shooter can hit without being so extreme that a crouched prisoner reads as a
## different object. Godot clamps a capsule to at least twice its radius (0.8
## here), and [PlayerController] clamps to that as well rather than letting a
## sweep author a body the physics server will silently resize.
@export_range(0.2, 3.0, 0.01) var crouch_height: float = 1.2

## Target horizontal speed while crouched on the ground, replacing
## [member ground_speed]. Under half of it: a crouch buys a smaller silhouette
## and pays for it in the one currency this game is denominated in.
##
## Kept below [member slide_min_entry_speed] on purpose, so a crouch can never
## walk itself up into slide range -- the two states cannot blur into each other
## no matter how long the key is held.
@export_range(0.0, 40.0, 0.1, "or_greater") var crouch_speed: float = 5.0

## How far the head drops while crouched, in metres. Unlike
## [member slide_camera_drop] this one has a capsule behind it: 0.55 puts a
## 1.65 m eye at 1.10 m, just under the 1.2 m the crouched capsule tops out at,
## so what the player sees over is what the shooter can hit.
@export_range(0.0, 1.5, 0.01) var crouch_camera_drop: float = 0.55

## Rate the head moves to and from the crouch, per second, applied as the same
## exponential approach [member slide_camera_settle_rate] uses. Slower than the
## slide's, because dropping into a stance is a movement and a slide is an
## impact.
@export_range(0.1, 60.0, 0.1, "or_greater") var crouch_camera_settle_rate: float = 12.0

# --- Look ---------------------------------------------------------------------

## Radians of rotation per pixel of mouse motion.
@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity: float = 0.0022

## Lower pitch clamp, in degrees (looking down). Yaw is never clamped.
@export_range(-90.0, 0.0, 0.5) var pitch_min_degrees: float = -89.0

## Upper pitch clamp, in degrees (looking up).
@export_range(0.0, 90.0, 0.5) var pitch_max_degrees: float = 89.0

## Invert vertical look.
@export var invert_look_y: bool = false

# --- Body ---------------------------------------------------------------------

## Steepest slope that still counts as floor. (Quake III's MIN_WALK_NORMAL of
## 0.7 is 45.6 degrees.)
@export_range(0.0, 89.0, 0.5) var max_floor_angle_degrees: float = 46.0

## Distance the body snaps down by to stay glued to the floor; without it every
## downhill step becomes a launch and friction stops applying mid-slope.
@export_range(0.0, 2.0, 0.01) var floor_snap_length: float = 0.3


## Effective gravity, after the sweep multiplier.
func get_effective_gravity() -> float:
	return gravity * gravity_scale


## Height a jump from level ground reaches, in metres. Derived, not tuned:
## [code]v^2 / 2g[/code]. Level geometry is authored against it, and it is the
## number that says which of the playground's blocks are reachable.
func get_jump_apex_height() -> float:
	var effective_gravity: float = get_effective_gravity()
	if effective_gravity <= 0.0:
		return 0.0
	return (jump_velocity * jump_velocity) / (2.0 * effective_gravity)


## Seconds between leaving level ground and landing back on it.
func get_jump_air_time() -> float:
	var effective_gravity: float = get_effective_gravity()
	if effective_gravity <= 0.0:
		return 0.0
	return (2.0 * jump_velocity) / effective_gravity
