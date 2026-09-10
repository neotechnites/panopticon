class_name ShooterProfile
extends Resource

## Every tunable number a [TowerShooter] uses.
##
## Same doctrine as [BotProfile], [MovementProfile] and [WeaponProfile]: nothing
## about how the bot behaves may be hard-coded in the brain, because this
## project settles design questions by sweeping variants of a resource through
## headless matches. A constant buried in [TowerShooter] is a question that can
## never be asked, and "how good does the tower have to be before three runners
## stop getting through" is exactly the question this file exists to let a sweep
## ask a hundred times with different numbers.
##
## [b]This resource is the difficulty dial[/b]
##
## A hitscan bot with perfect aim wins every round and measures nothing; a bot
## that never shoots measures nothing either. The fields below are the whole of
## what makes one shooter harder than another, and they are deliberately
## separated into four independent axes so a sweep can move one at a time:
##
## 1. [b]How long before it commits[/b] -- [member reaction_seconds].
## 2. [b]How wrong its aim is[/b] -- [member aim_error_degrees] and
##    [member aim_error_resample_seconds].
## 3. [b]How well it follows a crossing target[/b] -- [member tracking_gain],
##    [member max_yaw_rate], [member max_pitch_rate], [member target_lead_seconds].
## 4. [b]How bad a shot it will accept[/b] -- [member shot_confidence_threshold]
##    against [member aim_tolerance_degrees],
##    [member max_comfortable_track_rate] and the two ranges.
##
## Units are metres, seconds and radians unless a field name says otherwise.
## Angles are exported in DEGREES because they are read by humans, and converted
## once by the accessors at the bottom of this file so the brain never does the
## conversion itself and cannot get it wrong in one place out of three.

# --- Attention ----------------------------------------------------------------

## How fast the head sweeps while searching, in radians per second.
##
## This is the single most important number in the file after the reload,
## because attention is the shooter's real constraint: it has clear sightlines
## to the whole ring and a view that covers maybe a third of it, so everything
## it does not happen to be pointing at is free ground for a runner. Raise this
## and the ring gets smaller; lower it and a runner can time a crossing against
## the sweep.
##
## Kept well under [member max_yaw_rate] on purpose. A scan is a search, not a
## reaction, and a tower that spins as fast as it tracks reads as a turret
## rather than as a player looking around.
@export_range(0.1, 8.0, 0.05) var scan_yaw_rate: float = 1.2

## How much arc the sweep covers before it reverses, in degrees.
##
## 360 means it never reverses and simply turns on the spot forever, which is the
## honest default for a tower in the middle of a closed ring: there is no
## direction that is not worth watching. Set it lower to model a shooter
## concentrating on a sector -- 120 makes the far arc genuinely safe, which is a
## design question worth measuring rather than assuming.
@export_range(10.0, 360.0, 1.0) var scan_sweep_degrees: float = 360.0

## Head pitch held while searching, in degrees; negative looks down.
##
## The deck is level with the tower platform and a runner's centre of mass is at
## y=0.9 against an eye at y=1.65, so the whole ring lives about a degree below
## the horizon. Scanning flat would put every target in the bottom half of the
## view and cost the bot pitch travel on every single acquisition.
@export_range(-45.0, 45.0, 0.5) var scan_pitch_degrees: float = -1.0

## Viewport aspect ratio used to turn the camera's vertical field of view into
## the horizontal one.
##
## The bot has no viewport -- it is usually running headless -- so the width of
## what it can see has to come from somewhere. [member Camera3D.fov] is the
## VERTICAL angle under Godot's default [constant Camera3D.KEEP_HEIGHT], and the
## horizontal arc that actually decides what a tower can watch is
## [code]2*atan(tan(fov/2) * aspect)[/code]. Getting this wrong does not error;
## it silently gives the bot a wider or narrower ring than a human would have.
@export_range(0.5, 4.0, 0.01) var view_aspect: float = 1.7778

## Field of view assumed when the bot has no camera to read one off, in degrees.
## Matches the shipped player scene, so a shooter built without a camera behaves
## like one that has the standard camera rather than like a cyclops.
@export_range(20.0, 179.0, 1.0) var fallback_fov_degrees: float = 100.0

## Fraction of the view frustum the bot is willing to treat as "seen".
##
## Below 1.0 there is a dead margin at the edge of vision, which is what stops a
## target from being acquired, lost and re-acquired on alternate ticks as it
## brushes the exact frustum boundary -- and is also a fair model of a player not
## noticing something in the last few degrees of peripheral vision. 1.0 is
## honest and jittery; 0.9 is honest and stable.
@export_range(0.1, 1.0, 0.01) var fov_margin: float = 0.9

# --- Acquisition --------------------------------------------------------------

## Seconds a target must stay continuously visible before the bot will consider
## shooting it. The reaction-time knob.
##
## Paid once per acquisition, not once per shot: a target that stays in view
## across a whole reload is already acquired when the rifle comes back, which is
## what a human who has been watching a runner the whole time would experience.
## Lose sight of it and the clock starts again from zero.
@export_range(0.0, 3.0, 0.01) var reaction_seconds: float = 0.45

## Height above a target's origin that the bot aims at, in metres.
##
## The shipped body is a 1.8 m capsule whose collision origin sits at y=0.9, so
## 0.9 is centre mass. Raising it towards 1.5 aims at the head, which is a
## smaller target and therefore a harder bot; the field is here so that is a
## number to sweep rather than an opinion in the code.
@export_range(0.0, 2.0, 0.05) var target_aim_height: float = 0.9

## How far ahead of a moving target the bot aims, in seconds of the target's own
## velocity.
##
## Not projectile lead -- the rifle is hitscan and its round arrives instantly.
## This compensates for the bot's OWN lag: the tracking loop is a proportional
## controller and a proportional controller always trails a constant-velocity
## target by a fixed angle of [code]angular_speed / tracking_gain[/code]. Aiming
## ahead by [code]1.0 / tracking_gain[/code] seconds cancels that trail exactly,
## whatever the target's speed and range -- which is where the default comes
## from, and is the value to move this to whenever
## [member tracking_gain] changes. Zero is a bot that permanently shoots just
## behind every crossing runner, which is a perfectly reasonable thing for an
## easy setting to do.
@export_range(0.0, 1.0, 0.01) var target_lead_seconds: float = 0.14

# --- Tracking -----------------------------------------------------------------

## Proportional gain on the aim error, in radians per second of turn per radian
## of error. How hard the bot snaps onto a target and how tightly it holds a
## crossing one.
##
## The brain is a plain P controller with no damping, exactly like
## [RingRunner]'s steering, and this is the whole of its aiming skill. Too low
## and it never catches a sprinting runner; too high and it overshoots and
## oscillates about the target, which shows up as a lower hit rate rather than
## as an error.
@export_range(0.5, 40.0, 0.1) var tracking_gain: float = 7.0

## Ceiling on the yaw rate the bot will ask for, in radians per second. The turn
## speed of the hand on the mouse: it is what stops a large error from producing
## an instant, inhuman snap, and it is what makes a runner crossing behind the
## bot genuinely expensive to answer.
@export_range(0.1, 30.0, 0.1) var max_yaw_rate: float = 3.5

## Ceiling on the pitch rate, in radians per second. Lower than the yaw ceiling
## because the ring is a horizontal band: a tower that needs a lot of pitch is
## looking at something that is not the game.
@export_range(0.1, 30.0, 0.1) var max_pitch_rate: float = 2.5

# --- Aim error ----------------------------------------------------------------

## Radius of the random angular offset added to every aim, in degrees.
##
## The bot aims at target centre plus an offset drawn uniformly from a disc of
## this radius, so it is wrong by up to this much at all times. At 44 m the
## shipped capsule is about 1.0 degree wide and 2.3 degrees tall, so the chance
## of a hit falls off as roughly the square of this value: near 0.1 it cannot
## miss a stationary target, the default lands about half its shots, and 3.0 is
## a shooter that has to be lucky.
##
## This is the difficulty knob with the most direct effect on hit rate, and the
## reason it exists at all: a hitscan bot with zero aim error is unbeatable and
## therefore measures nothing.
@export_range(0.0, 30.0, 0.05) var aim_error_degrees: float = 1.1

## How often the aim offset is re-drawn, in seconds.
##
## Long values read as a bot that is consistently wrong in one direction and can
## be waited out; short values read as a jittery hand that is briefly right. It
## interacts with [member reaction_seconds] -- a resample interval much shorter
## than the reaction time averages the error away and makes the bot better than
## [member aim_error_degrees] suggests.
@export_range(0.02, 5.0, 0.01) var aim_error_resample_seconds: float = 0.35

## Seed for the aim-error generator. Non-zero makes a run reproducible, which is
## what a sweep comparing two profiles needs; 0 seeds from the system entropy so
## two shooters in one match do not share a hand.
@export var aim_random_seed: int = 0

# --- The shot decision --------------------------------------------------------

## The angular error at which confidence in the aim falls to zero, in degrees.
##
## The denominator of the aim term in [method TowerShooter.get_shot_confidence]:
## pointing exactly at the target scores 1.0, pointing this far off scores 0.0,
## and it is linear in between. Roughly "how close do I have to be before I
## believe the shot", so it should be read together with
## [member shot_confidence_threshold] -- a wide tolerance and a low threshold is
## a bot that sprays, a tight tolerance and a high threshold is a bot that waits.
@export_range(0.05, 45.0, 0.05) var aim_tolerance_degrees: float = 2.0

## Target angular speed, in radians per second across the bot's view, at which
## confidence is halved. The bot's opinion of how hard a crossing target is.
##
## A runner at 8 m/s and r=44 crosses the tower's view at about 0.18 rad/s and a
## sprinter cutting inside at about 0.29, so the default costs a walking
## target roughly 15 percent of the shot's confidence and a sprinting one
## roughly 20. Lower it to model a shooter who will not take a moving shot at
## all.
@export_range(0.05, 20.0, 0.05) var max_comfortable_track_rate: float = 1.2

## Distance out to which range costs the bot nothing, in metres. Inside it the
## range term of the confidence is 1.0.
@export_range(1.0, 500.0, 1.0) var confident_range: float = 55.0

## Distance at which the bot will not shoot at all, in metres: the range term
## falls linearly from 1.0 at [member confident_range] to 0.0 here.
##
## The arena's longest sightline is a little over 120 m, so the default lets the
## bot take a shot anywhere on the ring while still preferring the near arc.
@export_range(1.0, 2000.0, 1.0) var max_engagement_range: float = 120.0

## The confidence, from 0 to 1, at or above which the bot spends its shot.
##
## [b]This is the field the third design requirement is about.[/b] A shot costs
## the whole reload and draws a tracer that tells every runner where the tower
## is standing and what it was looking at, so whether to take a marginal shot is
## a real decision with a real price, and it is made HERE, as one explicit
## number, rather than falling out of some threshold buried in the aiming code.
##
## At 1.0 the bot never fires, because confidence is a product of three terms
## none of which is ever exactly 1.0 in practice. At 0.0 it fires the instant it
## has a target and a loaded rifle, which is the "sprays and prays" end of the
## dial and a perfectly good thing to measure against.
@export_range(0.0, 1.0, 0.01) var shot_confidence_threshold: float = 0.6

# --- Optic --------------------------------------------------------------------

## Whether the bot uses the zoom optic at all. Off makes every shot a hipfire
## shot, which is the baseline the optic's value should be measured against.
@export var use_optic: bool = true

## Distance beyond which zooming is worth it, in metres. Under it the target is
## already large and the narrowed view is pure cost.
@export_range(0.0, 500.0, 1.0) var optic_min_distance: float = 25.0

## How far inside the ZOOMED frustum a target must sit before the bot will zoom,
## as a fraction of the zoomed half-angles.
##
## The whole hazard of the optic is that zooming narrows the view, so a bot that
## zooms on a target near the edge of its vision loses that target the instant
## the transition starts, zooms out, re-acquires and oscillates forever. Zooming
## only when the target is comfortably central means the target is still inside
## the view after the field has shrunk.
@export_range(0.05, 1.0, 0.05) var optic_centre_fraction: float = 0.6


# --- Derived values -----------------------------------------------------------

## [member scan_sweep_degrees] in radians. Kept here so the brain never converts.
func get_scan_sweep_radians() -> float:
	return deg_to_rad(scan_sweep_degrees)


## [member scan_pitch_degrees] in radians.
func get_scan_pitch_radians() -> float:
	return deg_to_rad(scan_pitch_degrees)


## [member aim_error_degrees] in radians.
func get_aim_error_radians() -> float:
	return deg_to_rad(aim_error_degrees)


## [member aim_tolerance_degrees] in radians.
func get_aim_tolerance_radians() -> float:
	return deg_to_rad(aim_tolerance_degrees)


## True when the bot should reach for the scope. One place, so no caller grows
## its own idea of what "uses the optic" means -- the same rule
## [method BotProfile.wants_sprint] follows.
func wants_optic() -> bool:
	return use_optic


## A generator seeded as this profile asks. [member aim_random_seed] of 0 means
## "seed from entropy", so two shooters built from the same resource still miss
## in different directions.
func make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if aim_random_seed == 0:
		rng.randomize()
	else:
		rng.seed = aim_random_seed
	return rng
