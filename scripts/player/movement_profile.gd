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

## Target horizontal speed while walking. (Quake/HL sv_maxspeed, 320 u/s.)
@export_range(0.0, 40.0, 0.1, "or_greater") var walk_speed: float = 8.0

## Target horizontal speed while sprint is held.
@export_range(0.0, 40.0, 0.1, "or_greater") var sprint_speed: float = 11.0

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


## Target ground speed for the given sprint state.
func get_ground_speed(sprinting: bool) -> float:
	return sprint_speed if sprinting else walk_speed
