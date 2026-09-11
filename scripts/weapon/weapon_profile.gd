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
##
## [b]Every option here is OFF or NEUTRAL by default[/b]
##
## The shipped rifle is a perfectly accurate hitscan weapon with a flat reload,
## a full-length tracer and no charge. Every field added since is either a
## master switch that defaults to the shipped behaviour ([member shot_model],
## [member charge_enabled], [member tracer_enabled]) or a magnitude that
## defaults to zero or one ([member spread_degrees],
## [member reload_windup_fraction], [member tracer_segment_length]). A field
## whose neighbours' switches are off does nothing at all, and each group below
## says which switch governs it. Loading this resource with its defaults
## reproduces the shipped game exactly.

## How a shot gets from the muzzle to whatever it strikes.
##
## Not a balance knob -- these are two different games sharing one weapon. See
## [member shot_model].
enum ShotModel {
	## The shot arrives the instant the trigger is pulled. Skill is pure aim.
	HITSCAN,
	## The shot is a body that flies at [member projectile_speed] and can be
	## outrun sideways. Skill is leading a moving target.
	PROJECTILE,
}

# --- Reload -------------------------------------------------------------------

## Seconds of enforced downtime after a shot, at the start of a match.
##
## The single most important number in PANOPTICON. At 8 m/s (see
## [member MovementProfile.ground_speed]) a runner covers roughly
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

# --- Reload shape -------------------------------------------------------------
#
# The DURATION of the reload is not settled here. [MatchRules] owns it -- see
# [member MatchRules.base_reload_seconds] and
# [member MatchRules.reload_floor_seconds] -- because it is the clock the round
# runs on and has to be sweepable per match. What this group settles is the
# SHAPE of that duration: whether the wait is one flat block or splits into a
# dead phase and a wind-up, and whether the wind-up can be knocked back.
#
# Nothing here can change how long a reload lasts. The wind-up is a fraction of
# whatever duration the match asked for.

@export_group("Reload shape")

## The trailing fraction of the reload that counts as a WIND-UP rather than
## dead time.
##
## 0.0 is the shipped behaviour: a flat wait. The weapon is unavailable for the
## whole duration and then it is available, with no internal structure.
##
## Above 0.0 the same duration splits in two. The leading part is dead -- the
## round is being fetched, nothing can be done to it -- and the trailing
## [code]reload_windup_fraction[/code] of it is a wind-up: the weapon is
## visibly, audibly coming back, [method Rifle.is_winding_up] is true, and
## [signal Rifle.reload_windup_started] has gone out for lighting and audio to
## hang a tell on. At 1.0 the entire reload is wind-up.
##
## This is the field that makes [member reload_interruptible] mean anything: an
## interrupt only bites during the wind-up, so a flat reload cannot be
## interrupted at all.
@export_range(0.0, 1.0, 0.01) var reload_windup_fraction: float = 0.0

## Whether [method Rifle.interrupt_reload] does anything.
##
## Off by default, which is the shipped behaviour: once the shot is spent the
## reload runs to completion no matter what happens to the shooter. On, a
## caller -- a hit, a sprint, a fall, whatever the design decides -- can knock
## the wind-up back to its start, costing the shooter the wind-up but never
## more than that.
##
## The weapon deliberately does not decide what interrupts it. It exposes the
## verb and something with an opinion calls it, exactly as [Rifle] reports what
## it struck and lets something else decide what that means.
##
## Inert while [member reload_windup_fraction] is 0.0.
@export var reload_interruptible: bool = false

# --- Shot model ---------------------------------------------------------------

@export_group("Shot model")

## Whether a shot arrives instantly or has to fly.
##
## [constant ShotModel.HITSCAN] is shipped and is the whole of today's game:
## the ray resolves on the frame of the trigger pull, so where the crosshair was
## is where the shot went and nothing a runner does after the trigger matters.
##
## [constant ShotModel.PROJECTILE] is a different game rather than a tuned
## version of the same one. A round crossing a 120 m arena at
## [member projectile_speed] takes most of a second, so the tower must aim where
## a runner WILL be, and a runner who changes direction after the muzzle flash
## can survive a shot that was perfectly aimed. It converts the tower's skill
## from reading a position to reading an intention, and it hands the runner a
## counter-play that hitscan does not have at any tuning.
##
## Both models emit the same [signal Rifle.fired], [signal Rifle.target_hit] and
## [signal Rifle.missed], both are driven by [method Rifle.try_fire], and both
## therefore work unchanged for a bot, for telemetry and for the match. The only
## difference downstream is WHEN the hit or miss arrives: on the same frame
## under hitscan, some frames later under projectile.
@export var shot_model: ShotModel = ShotModel.HITSCAN

## Metres per second a round travels. Inert under [constant ShotModel.HITSCAN].
##
## The number to think in is arena crossings: at 120 m/s a shot across a 120 m
## ring lands in a second, which at [member MovementProfile.ground_speed] is eight
## metres of lead. Raise it and the model converges on hitscan; lower it and
## leading becomes the entire skill.
@export_range(5.0, 2000.0, 1.0, "or_greater") var projectile_speed: float = 120.0

## Downward acceleration on a round in flight, m/s^2. Inert under
## [constant ShotModel.HITSCAN], and 0.0 -- a perfectly flat shot -- by default
## even under it.
##
## Above zero the tower also has to hold over at range, which is a second,
## separate skill from leading and worth being able to switch on independently.
@export_range(0.0, 40.0, 0.1, "or_greater") var projectile_gravity: float = 0.0

## Longest distance a round may cross in one collision step, metres. Inert under
## [constant ShotModel.HITSCAN].
##
## A round is swept by raycasting the segment it crossed, so it cannot tunnel
## through a wall however fast it goes -- but a single 2 m step keeps the
## segments short enough that the impact NORMAL is read off the right face on
## thin cover. Lower is more faithful and more raycasts; there is at most one
## round in the air at a time, so the cost is not worth optimising.
@export_range(0.05, 50.0, 0.05, "or_greater") var projectile_step_metres: float = 2.0

## Seconds a round may stay in the air before it gives up and reports a miss.
## Inert under [constant ShotModel.HITSCAN]. A backstop against a round that
## somehow never resolves, not a design knob: at the default speed and range a
## round is spent in well under a second.
@export_range(0.1, 60.0, 0.1, "or_greater") var projectile_max_flight_seconds: float = 10.0

## Radius of the visible round, metres. 0.0 -- invisible -- by default, so
## switching to [constant ShotModel.PROJECTILE] costs a headless sweep no
## geometry at all and the tracer remains the only tell. Raise it to see the
## round in a play session.
@export_range(0.0, 1.0, 0.005) var projectile_visual_radius: float = 0.0

# --- Recoil --------------------------------------------------------------------
#
# VIEW-MODEL ONLY. This group moves [code]Rifle/ViewModel[/code] -- the mesh and
# the muzzle hung off it, together, since the muzzle is parented to exactly that
# transform -- and nothing else. It never touches [member Rifle.aim_source], so
# it cannot be the thing that decides where a shot goes; see
# [method Rifle._resolve_shot], which reads the aim source and nothing about the
# view model. A camera-facing kick is a different, already-existing system --
# [FxWeaponFeel] and [FxCameraKick], wired through [FeedbackProfile] -- and this
# group does not replace or duplicate it.

@export_group("Recoil")

## How far the view model is shoved back along its own local axis (towards the
## eye) at the peak of the kick, in metres. 0.0 -- together with
## [member recoil_kick_pitch_degrees] at 0.0 -- is off: the shipped rifle does
## not kick at all, and a profile that wants a dead-still rifle only has to leave
## both at zero rather than find a separate switch.
##
## Keep this well under the view model's own near-plane clearance: the rest
## transform in [code]scenes/weapon/rifle.tscn[/code] holds its nearest vertex
## about 0.13 m from the camera against a 0.05 m near plane, so a kick distance
## anywhere near that 0.08 m margin will punch the stock through the near plane
## at the peak of the kick. This default leaves comfortable room.
@export_range(0.0, 0.5, 0.001, "or_greater") var recoil_kick_distance: float = 0.035

## How far the muzzle rises at the peak of the kick, degrees, rotating about the
## view model's own local right axis. Inert while this and
## [member recoil_kick_distance] are both 0.0.
@export_range(0.0, 45.0, 0.1, "or_greater") var recoil_kick_pitch_degrees: float = 10.0

## Seconds from the trigger to the peak of the kick. Short and sharp on purpose
## -- the impulse of a shot breaking is instant even on a heavy rifle -- while
## [member recoil_recover_seconds] is where the weight actually reads.
@export_range(0.0, 0.5, 0.005) var recoil_kick_seconds: float = 0.05

## Seconds from the peak back to exactly the authored rest transform.
##
## This is the number that makes a .50 calibre rifle feel heavy rather than
## light: raise it and the muzzle settles slowly under its own weight instead of
## snapping back. [member recoil_kick_seconds] plus this should stay well clear
## of [method get_cycle_seconds] (at the weapon's floor reload) or a kick still
## in flight would be visible the instant the weapon is ready again -- not a
## correctness problem, since the shot line never moves, but it would read as
## the rifle still recovering from a shot that has already been fired again.
@export_range(0.01, 3.0, 0.01) var recoil_recover_seconds: float = 0.38

## Shape of the return from the peak. Above 1.0 the muzzle falls fast and then
## settles the rest of the way, which is what a heavy barrel actually does under
## its own weight rather than a spring snapping it back at a constant rate.
@export_range(0.1, 8.0, 0.1) var recoil_fade_exponent: float = 2.0

# --- Hitscan ------------------------------------------------------------------

@export_group("Shot line")

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

# --- Accuracy -----------------------------------------------------------------
#
# All zero by default, which is today's rifle: a shot goes exactly where the
# aim source points, always, at any range, at any speed, on any shot. Every
# field in this group is a magnitude that has to be raised before anything
# scatters, so the group as a whole has an off switch per effect rather than one
# master flag.

@export_group("Accuracy")

## Half-angle of the base scatter cone, degrees. The cone a settled, stationary
## shooter fires into.
##
## 0.0 is the shipped rifle and is perfect accuracy: the shot line is the aim
## line exactly, and [Rifle] does not so much as touch its RNG.
@export_range(0.0, 15.0, 0.01, "or_greater") var spread_degrees: float = 0.0

## Extra half-angle added, in degrees, when the shooter is moving at
## [member spread_reference_speed] or faster.
##
## The tower can walk its platform, so "should walking cost accuracy" is a real
## design question and not a formality: at 0.0 the tower may reposition for
## free and the platform is pure advantage, and above 0.0 standing still becomes
## a decision with a price attached. Scales linearly with speed between a
## standstill and [member spread_reference_speed] and stops growing above it.
##
## 0.0 by default, so movement costs nothing and [Rifle] never measures its own
## speed.
@export_range(0.0, 15.0, 0.01, "or_greater") var moving_spread_degrees: float = 0.0

## The speed, m/s, at which [member moving_spread_degrees] is fully applied.
## Defaults to [member MovementProfile.ground_speed], so a walking shooter pays
## the whole movement penalty and a creeping one pays a fraction of it.
##
## Inert while [member moving_spread_degrees] is 0.0.
@export_range(0.1, 40.0, 0.1, "or_greater") var spread_reference_speed: float = 8.0

## Cone multiplier for a shot taken the instant the weapon becomes usable,
## easing to 1.0 over [member spread_settle_seconds].
##
## The single-shot analogue of first-shot accuracy. Every shot this rifle fires
## is a first shot -- there is no burst to walk off target -- so the question is
## not "does the group open up" but "is a shot snapped off the moment the reload
## ends worth as much as one taken by a shooter who waited". Above 1.0 it is
## worth less and patience is rewarded; below 1.0 the snap shot is the accurate
## one and hesitation is punished. Both are real designs.
##
## 1.0 by default, and inert regardless while [member spread_settle_seconds] is
## 0.0.
@export_range(0.0, 8.0, 0.01, "or_greater") var first_shot_spread_multiplier: float = 1.0

## Seconds of being loaded and ready it takes for
## [member first_shot_spread_multiplier] to decay to 1.0.
##
## 0.0 by default: the weapon is settled the instant it is ready, so the
## multiplier never applies.
@export_range(0.0, 10.0, 0.01, "or_greater") var spread_settle_seconds: float = 0.0

## Extra half-angle, degrees, added per 100 m between the muzzle and whatever
## the shot line is pointing at.
##
## A cone already opens with range in absolute terms -- the same angle is a
## wider miss further out -- so this is the second, deliberate kind of falloff:
## the weapon getting genuinely less trustworthy at distance rather than merely
## less precise. It is what makes a long shot across the ring a worse bet than
## the same shot up close, which is the lever that decides whether the tower
## should hold the whole arena or only the near arc.
##
## 0.0 by default. Above 0.0 the weapon spends one extra centre-line raycast per
## shot to find out how far away it is aiming; at zero it spends none.
@export_range(0.0, 20.0, 0.01, "or_greater") var spread_growth_per_100m: float = 0.0

## Seed for the scatter RNG. 0 means seed from entropy.
##
## A sweep comparing two spread settings wants the same sequence of scatter
## draws in both arms or it is measuring luck. Set it to any non-zero value to
## get that; leave it at 0 for a play session, where a repeating scatter
## pattern would be learnable.
##
## Inert while every spread field above is zero, because nothing draws.
@export var spread_seed: int = 0

# --- Charged shot -------------------------------------------------------------

@export_group("Charged shot")

## Whether the trigger charges instead of firing. Off by default, and off means
## every field below it is dead.
##
## On, [method Rifle.begin_charge] starts a hold and
## [method Rifle.release_charge] takes the shot, with the shot improving over
## the hold as the fields below describe. This is one of the genuine alternative
## designs for a one-shot weapon: instead of the cost of shooting being paid
## entirely afterwards in the reload, part of it is paid up front in a window
## where the shooter is committed, aiming, and not moving well -- which gives a
## runner who sees the tell a reason to break cover early rather than late.
##
## [method Rifle.try_fire] keeps working exactly as it does today with this on:
## it takes the shot immediately at whatever charge has accumulated, which is
## 0.0 for a caller that never held. That is what keeps [TowerShooter] and every
## other bot able to fire a charged weapon without knowing it is one -- see
## [member charge_auto_begins_when_ready] for how a bot gets the benefit of the
## hold as well.
@export var charge_enabled: bool = false

## Seconds of holding that reach full charge. Inert while
## [member charge_enabled] is off.
@export_range(0.05, 10.0, 0.01, "or_greater") var charge_full_seconds: float = 0.8

## Whether the weapon starts charging by itself the moment it becomes ready.
##
## Off by default, which means a charge only exists because something asked for
## one -- a human holding the trigger through [WeaponInput].
##
## On, the rifle spools up on its own the instant the reload ends, so a shooter
## who has been tracking a target rather than snapping to it releases a charged
## shot without a second input. That is what lets a bot calling
## [method Rifle.try_fire] benefit from the charge model instead of always
## firing at zero, and therefore what makes the charged design measurable in a
## headless sweep at all.
##
## Inert while [member charge_enabled] is off.
@export var charge_auto_begins_when_ready: bool = false

## Least charge a shot may be taken at, 0.0 to 1.0.
##
## 0.0 by default, which is what keeps [method Rifle.try_fire] unconditional:
## a caller that never charged still gets its shot. Raise it for a design where
## a half-charged shot is not a shot at all -- and know that this is the one
## field in this file that can make [method Rifle.try_fire] refuse a weapon that
## [method Rifle.can_fire] called ready, which a bot that gates on
## [method Rifle.can_fire] will read as a wasted tick.
##
## Inert while [member charge_enabled] is off.
@export_range(0.0, 1.0, 0.01) var charge_min_fraction_to_fire: float = 0.0

## Scatter cone multiplier at full charge, interpolated from 1.0 at no charge.
##
## 0.0 by default: a fully charged shot is perfectly accurate and an uncharged
## one pays the full cone from the Accuracy group. This is the main thing a
## charge buys, and it does nothing unless some spread has been dialled in --
## with the shipped zero spread there is no accuracy left to improve.
##
## Inert while [member charge_enabled] is off.
@export_range(0.0, 4.0, 0.01, "or_greater") var charge_spread_multiplier: float = 0.0

## [member max_range] multiplier at full charge, interpolated from 1.0 at no
## charge. 1.0 -- no effect -- by default. Inert while [member charge_enabled]
## is off.
@export_range(0.1, 8.0, 0.01, "or_greater") var charge_range_multiplier: float = 1.0

## [member projectile_speed] multiplier at full charge, interpolated from 1.0 at
## no charge. 1.0 -- no effect -- by default, and doubly inert under
## [constant ShotModel.HITSCAN], where nothing travels. Above 1.0 a charged shot
## needs less lead as well as landing tighter, which stacks the two skills
## rather than trading them.
@export_range(0.1, 8.0, 0.01, "or_greater") var charge_projectile_speed_multiplier: float = 1.0

# --- Tracer -------------------------------------------------------------------
#
# The tracer is a MECHANIC, not decoration, and this group exists so that claim
# can be measured rather than asserted. Every shot draws a line an observer can
# back-project to the shooter, which is the price the tower pays for firing.
# Turn the group off with [member tracer_enabled] and run the same sweep to find
# out what that price is actually worth.

@export_group("Tracer")

## Whether a shot leaves a tracer at all.
##
## On by default. Off is not a graphics setting -- it deletes the tower's only
## involuntary tell, so shooting becomes free information and the runners lose
## their read on where the shot came from. The reason it exists is so that a
## sweep can run the identical rules with and without it and put a number on
## what the tracer costs the tower.
@export var tracer_enabled: bool = true

## How long the tracer stays visible after a shot.
##
## Raise this and shooting gets more expensive informationally: the line hangs
## in the air for longer and more runners get a chance to see it. Drop it and
## only a runner already looking that way learns anything. At 0.0 no tracer is
## built, exactly as if [member tracer_enabled] were off.
##
## It was 0.35 s, and with [member tracer_fade_exponent] at 2.2 on top of it the
## line was under half brightness a tenth of a second in -- gone before a runner
## who was not already staring at it could turn their head. A tell nobody has
## time to read is not a tell.
@export_range(0.0, 5.0, 0.01) var tracer_lifetime: float = 0.8

## Tracer colour. The alpha channel is the tracer's brightness at the instant of
## the shot, before the fade begins, and is scaled by
## [member tracer_brightness].
@export var tracer_color: Color = Color(1.0, 0.72, 0.24, 1.0)

## Multiplier on the tracer's starting alpha. 1.0 -- no change -- by default.
##
## Separate from [member tracer_color] so that a sweep, which sets scalars from
## a JSON spec and cannot express a [Color], can still dim or brighten the tell
## across arms without a second resource. How VISIBLE the line is decides how
## far away it can be read, which is a different question from how LONG it can
## be read; [member tracer_lifetime] answers that one.
@export_range(0.0, 4.0, 0.01, "or_greater") var tracer_brightness: float = 1.0

## Tracer thickness in metres. Real thickness, not a screen-space line width:
## the tracer is built as geometry precisely so that this number survives the
## GL Compatibility renderer, where hardware line width is pinned to one pixel
## and a [code]PRIMITIVE_LINES[/code] tracer would ignore this field entirely.
##
## [b]It is not a calibre and it must not be set like one.[/b] It was 0.045 m --
## a plausible round -- and that is why prisoners never saw a shot. Real
## thickness means the tracer shrinks with distance, and the observers this
## mechanic is for stand on a deck 35 to 60 m from the tower: at 1600x900 and
## the player's 100 degree field of view that is about 515 px per radian, so
## 0.045 m subtended 0.45 px at ring mid-radius. Under one pixel is not "thin",
## it is a line the rasteriser is entitled to drop entirely, and it did. Divide
## the width by the distance and multiply by 515 to get pixels; keep the answer
## at three or more across the whole deck, which 0.3 m does (3.3 px at 47.5 m,
## 2.6 px at the outer wall).
@export_range(0.001, 2.0, 0.001) var tracer_width: float = 0.3

## Shape of the tracer's fade. 1.0 is linear; higher values dim fast then linger
## faintly, which reads as a hot round cooling rather than a light switch.
##
## Keep it near linear. It multiplies with [member tracer_lifetime] rather than
## adding to it: at 2.2 the line spent most of its life too faint to read, so
## the lifetime on the tin was roughly triple the lifetime a prisoner got.
@export_range(0.1, 8.0, 0.1) var tracer_fade_exponent: float = 1.6

## Metres of the shot line the tracer actually draws, measured from
## [member tracer_segment_start]. 0.0 means the whole of it, which is shipped.
##
## This is the strongest tracer knob and the least obvious. A full-length line
## gives an observer two facts -- the direction of the shot and, by
## back-projection, the shooter's position. A short segment near the muzzle
## gives away the position but hides where the shot was going. A short segment
## far from the muzzle does the opposite. So this field decides WHICH of the
## tower's two secrets a shot spends, and it is the thing to sweep before
## reaching for [member tracer_enabled].
@export_range(0.0, 500.0, 0.1, "or_greater") var tracer_segment_length: float = 0.0

## Metres from the muzzle at which the drawn segment begins. 0.0 -- at the
## barrel -- by default.
##
## It applies whatever [member tracer_segment_length] is: with the length at 0.0
## the streak still starts here and then runs to the end of the shot. (This
## comment used to claim the field was inert in that case. It never was.)
##
## Two jobs, and the second one is not optional at the widths this tracer has to
## be drawn at. The first is the informational one above -- move the streak away
## from the muzzle and it stops giving the shooter's position away as precisely.
## The second is that the shooter is standing at the muzzle: [member tracer_width]
## is a real world thickness, so 0.3 m of it starting 0.45 m in front of the
## guard's eye is a blob across a third of their screen. Starting the streak
## outside the eye box costs a prisoner nothing -- that stretch is behind an
## opaque wall from every seat on the deck anyway -- and it lets the round read
## as leaving the eye instead of leaving the lens. The shipped profiles set
## 12 m, which clears the 18 m box. This class default stays at the barrel
## because a profile has no idea what arena it is being fired in.
@export_range(0.0, 500.0, 0.1, "or_greater") var tracer_segment_start: float = 0.0


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


# --- Reload shape -------------------------------------------------------------

## Seconds of [param reload_seconds] that are wind-up rather than dead time.
##
## Takes the live duration as an argument rather than reading
## [member base_reload_seconds], because [MatchRules] owns the duration and it
## changes as a match progresses. The shape is a fraction of whatever the match
## asked for, so shortening the reload shortens the wind-up with it.
func get_windup_seconds(reload_seconds: float) -> float:
	if reload_windup_fraction <= 0.0:
		return 0.0
	return maxf(reload_seconds, 0.0) * clampf(reload_windup_fraction, 0.0, 1.0)


# --- Shot model ---------------------------------------------------------------

## True when shots have to fly. The one branch the rest of the weapon takes on
## [member shot_model], so a third model later has one place to be added.
func is_projectile() -> bool:
	return shot_model == ShotModel.PROJECTILE


# --- Recoil ---------------------------------------------------------------------

## True when there is any kick to play at all. The gate a recoil player should
## check before doing anything, so a zeroed profile costs nothing and a rifle
## with no recoil is expressed by leaving both fields at 0.0 rather than by a
## separate switch.
func has_recoil() -> bool:
	return recoil_kick_distance > 0.0 or recoil_kick_pitch_degrees > 0.0


## Total wall-clock length of one recoil kick, attack included: the time from
## the trigger until the view model is back on its authored rest transform.
func get_recoil_duration() -> float:
	return recoil_kick_seconds + recoil_recover_seconds


# --- Accuracy -----------------------------------------------------------------

## True when any accuracy field could scatter a shot.
##
## The gate on the whole accuracy system: while this is false the weapon does
## not measure its own speed, does not probe for range and never touches its
## RNG, so the shipped rifle pays nothing for the option existing.
func has_spread() -> bool:
	return spread_degrees > 0.0 or moving_spread_degrees > 0.0


## True when the weapon needs to know how fast its shooter is moving. False for
## the shipped profile, which is what lets [Rifle] skip sampling its own motion
## entirely.
func tracks_shooter_speed() -> bool:
	return moving_spread_degrees > 0.0


## True when the cone depends on how far away the shot is aimed, and therefore
## when the weapon has to spend a centre-line probe to find out.
func needs_range_probe() -> bool:
	return has_spread() and spread_growth_per_100m > 0.0


## The scatter cone's half-angle in degrees for one specific shot.
##
## [param speed] is the shooter's speed in m/s, [param settled_seconds] how long
## the weapon has been loaded and untouched, [param distance] how far away the
## shot is aimed (negative when unknown, which skips the range term) and
## [param charge] the hold from 0.0 to 1.0.
##
## Returns 0.0 for the shipped profile no matter what is passed, and [Rifle]
## reads a 0.0 here as "do not touch the aim vector at all" rather than as "draw
## a zero-width scatter", so a default weapon is bit-for-bit as accurate as it
## was before spread existed.
func get_spread_degrees(
	speed: float, settled_seconds: float, distance: float, charge: float
) -> float:
	if not has_spread():
		return 0.0

	var cone: float = spread_degrees
	if moving_spread_degrees > 0.0 and speed > 0.0:
		var reference: float = maxf(spread_reference_speed, 0.001)
		cone += moving_spread_degrees * clampf(speed / reference, 0.0, 1.0)
	if spread_growth_per_100m > 0.0 and distance > 0.0:
		cone += spread_growth_per_100m * (distance / 100.0)

	if spread_settle_seconds > 0.0 and not is_equal_approx(first_shot_spread_multiplier, 1.0):
		var settled: float = clampf(settled_seconds / spread_settle_seconds, 0.0, 1.0)
		cone *= lerpf(first_shot_spread_multiplier, 1.0, settled)

	if charge_enabled and charge > 0.0:
		cone *= lerpf(1.0, charge_spread_multiplier, clampf(charge, 0.0, 1.0))

	return maxf(cone, 0.0)


# --- Charged shot -------------------------------------------------------------

## [member max_range] as modified by a hold of [param charge]. Returns
## [member max_range] unchanged whenever charging is off.
func get_charged_range(charge: float) -> float:
	if not charge_enabled or charge <= 0.0:
		return max_range
	return max_range * lerpf(1.0, charge_range_multiplier, clampf(charge, 0.0, 1.0))


## [member projectile_speed] as modified by a hold of [param charge]. Returns
## [member projectile_speed] unchanged whenever charging is off.
func get_charged_projectile_speed(charge: float) -> float:
	if not charge_enabled or charge <= 0.0:
		return projectile_speed
	return projectile_speed * lerpf(
		1.0, charge_projectile_speed_multiplier, clampf(charge, 0.0, 1.0)
	)


# --- Tracer -------------------------------------------------------------------

## True when a shot should build a tracer at all. The single gate, so
## [member tracer_enabled], a zeroed lifetime and a zeroed width cannot disagree
## about whether geometry gets made.
func draws_tracer() -> bool:
	return tracer_enabled and tracer_lifetime > 0.0 and tracer_width > 0.0


## The tracer's starting alpha: the colour's own alpha scaled by
## [member tracer_brightness], clamped to a legal alpha.
func get_tracer_alpha() -> float:
	return clampf(tracer_color.a * tracer_brightness, 0.0, 1.0)
