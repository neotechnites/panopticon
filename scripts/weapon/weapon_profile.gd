class_name WeaponProfile
extends Resource

## Every tunable number for [Rifle] lives here.
##
## Same rule as [MovementProfile]: nothing about how the rifle behaves may be
## hard-coded in the weapon. The project settles design questions by sweeping
## variants of a resource in headless bot matches, so a constant buried in code
## is a constant that can never be tested. Add new knobs here, never there.
##
## Units are metres, seconds and radians unless a field name says otherwise.
##
## [b]Why the reload dominates this file[/b]
##
## The tower has exactly one tool and it is single-shot, so the reload is not a
## balance knob among many -- it is the clock the entire match runs on. It sets
## how far a runner can travel between shots, therefore how much ground the
## tower can deny, therefore whether the ring is a gauntlet or a stroll. Treat
## [member base_reload_seconds] as the primary independent variable of the game
## and everything else here as secondary.

# --- Reload -------------------------------------------------------------------

## Seconds of enforced downtime after a shot, at the start of a match.
##
## The single most important number in PANOPTICON. At 8 m/s (see
## [member MovementProfile.walk_speed]) a runner covers roughly
## [code]base_reload_seconds * 8[/code] metres of ring between shots, so this
## value is really "how many metres of forgiveness a runner is granted for
## being seen".
##
## This is only the starting value: [member Rifle.reload_seconds] is what the
## weapon actually uses, and match logic shortens it as the game progresses.
@export_range(0.1, 15.0, 0.05, "or_greater") var base_reload_seconds: float = 2.5

## Hard floor on [member Rifle.reload_seconds], however aggressively match logic
## shortens it. Exists so a runaway progression rule cannot quietly turn the
## single-shot rifle into an automatic weapon, which would delete the whole
## design rather than tune it.
@export_range(0.05, 5.0, 0.01, "or_greater") var min_reload_seconds: float = 0.5

## Length of the [constant Rifle.State.FIRING] state: the committed window
## between the trigger and the start of the reload.
##
## The shot itself is instantaneous, so this is not travel time. It is the beat
## the muzzle flash, the recoil kick and the shot report own, and it exists as a
## real state rather than a zero-length formality so that lighting and audio can
## hang off [signal Rifle.state_changed] instead of racing a one-frame flag.
@export_range(0.0, 1.0, 0.01) var shot_duration: float = 0.06

# --- Hitscan ------------------------------------------------------------------

## Furthest a shot reaches. Beyond this the ray simply stops and the shot is a
## miss; the tracer still draws to the full range, so a long miss still
## broadcasts the shooter's line.
##
## Must comfortably exceed the tower-to-far-wall diagonal of the arena, or the
## rifle develops an invisible dead zone at the ring's far side.
@export_range(1.0, 2000.0, 1.0, "or_greater") var max_range: float = 400.0

## Physics layers a shot can hit. Default is every layer: a rifle that silently
## ignores a body because of a mask mismatch is the worst class of bug in a
## one-shot game, so the safe default is "hits everything" and narrowing it is a
## deliberate act.
@export_flags_3d_physics var hit_mask: int = 0xFFFFF

## Whether shots stop on [Area3D]s as well as bodies. Off by default -- trigger
## volumes are not cover.
@export var hit_areas: bool = false

# --- Tracer -------------------------------------------------------------------

## How long the tracer stays visible after a shot.
##
## This is a mechanic, not a garnish. The tracer is the price of shooting: it
## draws a line from the muzzle to wherever the shot landed, so every shot tells
## every runner within sight roughly where the tower is looking and, worse,
## where it is standing. Raise this and shooting gets more expensive
## informationally; drop it to zero and the tower may fire with impunity, which
## removes the game's core tension.
@export_range(0.0, 5.0, 0.01) var tracer_lifetime: float = 0.35

## Tracer colour. The alpha channel is the tracer's brightness at the instant of
## the shot, before the fade begins.
@export var tracer_color: Color = Color(1.0, 0.86, 0.45, 0.9)

## Tracer thickness in metres. Real thickness, not a screen-space line width:
## the tracer is built as geometry precisely so that this number survives the
## GL Compatibility renderer, where hardware line width is pinned to one pixel
## and a [code]PRIMITIVE_LINES[/code] tracer would ignore this field entirely.
@export_range(0.001, 1.0, 0.001) var tracer_width: float = 0.045

## Shape of the tracer's fade. 1.0 is linear; higher values dim fast then linger
## faintly, which reads as a hot round cooling rather than a light switch.
@export_range(0.1, 8.0, 0.1) var tracer_fade_exponent: float = 2.2


## Clamp a requested reload duration to the range this profile permits. The
## single place the floor is applied, so runtime shortening and editor defaults
## cannot disagree about what the minimum is.
func clamp_reload_seconds(seconds: float) -> float:
	return maxf(seconds, min_reload_seconds)


## Total length of one shot-to-ready cycle for a given reload duration: the
## committed firing window plus the reload. What a bot should use when it plans
## its next shot, and what a sweep should divide match length by to get shots
## available.
func get_cycle_seconds(reload_seconds: float) -> float:
	return shot_duration + clamp_reload_seconds(reload_seconds)
