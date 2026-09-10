class_name RunnerProfile
extends Resource

## Every tunable number the cover-playing [RingRunner] uses, and the switch that
## turns it back into the baseline.
##
## Same doctrine as [ShooterProfile], [BotProfile], [MovementProfile] and
## [WeaponProfile]: nothing about how the bot behaves may be hard-coded in the
## brain, because this project settles design questions by sweeping variants of
## a resource through headless matches. A constant buried in [RingRunner] is a
## question that can never be asked, and "how patient does a prisoner have to be
## before the tower stops converting the ring in round one" is exactly the
## question this file exists to let a sweep ask a hundred times with different
## numbers.
##
## [b]Why this is a separate resource from [BotProfile][/b]
##
## [BotProfile] is the LANE: which radius this body runs, how hard it steers,
## when its lap counts as finished. It is per-runner geometry and
## [MatchController] rewrites its radius on every placement. This resource is the
## OPPONENT: how well it plays the game of crossing open ground. One is tuning of
## a body, the other is a difficulty setting, and a sweep wants to move the
## second without disturbing the first.
##
## [b]This resource is the difficulty dial[/b]
##
## A runner that never leaves cover measures nothing, because the round simply
## times out; a runner that ignores the tower measures nothing either, because
## that is the baseline this one replaced. The fields below are the whole of what
## makes one prisoner harder to shoot than another, and they are deliberately
## separated into axes a sweep can move one at a time:
##
## 1. [b]How patient it is[/b] -- [member min_hold_seconds] and
##    [member max_hold_seconds].
## 2. [b]How much risk it accepts[/b] -- [member break_confidence_threshold]
##    against [member watched_confidence_penalty], [member free_crossing_metres]
##    and [member max_crossing_metres].
## 3. [b]How well it reads the reload[/b] -- [member reload_read_accuracy],
##    [member reload_safety_margin] and [member assumed_reload_seconds].
## 4. [b]How quickly and how clearly it perceives[/b] --
##    [member reaction_seconds], [member attention_cone_degrees],
##    [member attention_read_error_degrees], [member threat_memory_seconds].
##
## Units are metres, seconds and radians unless a field name says otherwise.
## Angles are exported in DEGREES because they are read by humans, and converted
## once by the accessors at the bottom of this file so the brain never does the
## conversion itself and cannot get it wrong in one place out of three.

## Which prisoner is on the ring.
enum Behaviour {
	## The original straight-line lap runner: one counter-clockwise circuit at a
	## fixed radius, no cover, no threat awareness, no decisions. Kept because
	## every claim about the cover runner is a comparison, and the only honest
	## thing to compare against is a prisoner that does nothing at all. Do not
	## delete it to tidy up: the moment it is gone, "the new bot survives longer"
	## stops being a measurement and becomes an opinion.
	BASELINE,
	## Hold cover, watch the tower, break for the next piece when the shooter is
	## reloading or looking elsewhere. See [RingRunner].
	COVER,
}

## Which prisoner this profile builds. Defaults to the one that plays the game.
@export var behaviour: Behaviour = Behaviour.COVER

# --- Perception ---------------------------------------------------------------
#
# The runner is allowed to know two things for free, because both are public
# facts of a panopticon rather than private facts about the shooter: that there
# IS a shooter this round, and where the tower stands. Everything else -- which
# way the guard is facing, whether the rifle is loaded -- has to be perceived,
# and these fields are what perceiving costs.

## Vertical field of view the runner is assumed to have, in degrees.
##
## The runner has no viewport of its own -- headless is the normal case -- so the
## arc it can watch has to come from somewhere. Matches the shipped player
## camera, so a bot notices the tower turn at the same moment across the same
## arc a human would. See [member view_aspect] for the horizontal half.
@export_range(20.0, 179.0, 1.0) var view_fov_degrees: float = 100.0

## Viewport aspect ratio used to turn [member view_fov_degrees] into the
## horizontal arc. [member Camera3D.fov] is the VERTICAL angle under Godot's
## default [constant Camera3D.KEEP_HEIGHT], and the width is
## [code]2*atan(tan(fov/2) * aspect)[/code]. Getting it wrong does not error; it
## silently gives the runner a wider or narrower world than a human has.
@export_range(0.5, 4.0, 0.01) var view_aspect: float = 1.7778

## Fraction of the frustum the runner treats as "seen". Below 1.0 there is a dead
## margin at the edge of vision, which stops the tower being noticed, lost and
## re-noticed on alternate ticks as it brushes the exact boundary. Mirrors
## [member ShooterProfile.fov_margin], and for the same reason.
@export_range(0.1, 1.0, 0.01) var fov_margin: float = 0.9

## Height above the body origin the runner looks FROM, in metres. The shipped
## capsule is 1.8 m with its origin at 0.9, and the head node sits at 1.65.
@export_range(0.0, 3.0, 0.05) var eye_height: float = 1.6

## Height above the body origin the runner tests COVER at, in metres.
##
## Deliberately equal to [member ShooterProfile.target_aim_height]: the question
## "am I behind cover" has exactly one correct answer, and it is the one the
## shooter's own line-of-sight test will give. A runner that tested a different
## height would believe itself safe on a line the rifle can actually shoot down,
## which is the single worst bug this file can have.
@export_range(0.0, 2.0, 0.05) var cover_test_height: float = 0.9

## Seconds a changed reading of the tower's attention must hold before the runner
## believes it. The reaction-time knob.
##
## Paid on every change of mind, in both directions, so a guard who sweeps past
## and back faster than this is never registered as having looked away. Zero is a
## prisoner with no reaction time at all, which is the unbeatable end of the dial
## and therefore measures nothing.
@export_range(0.0, 3.0, 0.01) var reaction_seconds: float = 0.35

## How near the tower's facing has to come, in degrees off the line to this
## runner, before the runner reads it as "pointed at me".
##
## Not the guard's field of view and not meant to be: it is one prisoner's
## opinion, at forty-odd metres, of where a distant figure is looking. Widen it
## for a jumpier prisoner that treats the whole near arc as attention; narrow it
## for one that only reacts when it is plainly being stared at.
@export_range(1.0, 180.0, 1.0) var attention_cone_degrees: float = 30.0

## Radius of the random angular error on that reading, in degrees.
##
## [b]This is the field that stops the runner being omniscient.[/b] Judging a
## body's facing across a 45 m ring is a guess, so the runner adds an offset
## drawn uniformly from this range to the true angle before testing it against
## [member attention_cone_degrees], and is therefore wrong about being watched
## some fraction of the time in both directions. At 0.0 the runner reads the
## guard's yaw as ground truth, which is exactly the omniscient bot this design
## forbids -- it is left reachable only so a sweep can measure what omniscience
## would be worth.
@export_range(0.0, 90.0, 0.5) var attention_read_error_degrees: float = 14.0

## How often that error is re-drawn, in seconds. Long values read as a prisoner
## who is consistently wrong about one guard; short values as one whose read
## flickers. It interacts with [member reaction_seconds] exactly as
## [member ShooterProfile.aim_error_resample_seconds] interacts with the
## shooter's: resampling much faster than the reaction time averages the error
## away and makes the runner better than this field suggests.
@export_range(0.02, 5.0, 0.01) var attention_resample_seconds: float = 0.4

## How long a belief about the tower's attention outlives the sight of it, in
## seconds.
##
## Cover cuts both ways: a prisoner tucked behind a box cannot see the guard
## either, so it is working from a memory that is going stale. When the memory
## expires the runner falls back on the assumption in the game's title -- that it
## is being watched -- and its only remaining evidence is the reload. That is the
## intended shape of the game, not a limitation: from cover the rhythm of the
## rifle is the whole of what a prisoner knows.
@export_range(0.0, 20.0, 0.1) var threat_memory_seconds: float = 1.5

## How near a round has to land, in metres, before the prisoner takes the shot
## personally.
##
## Every shot draws a tracer that ends where the round ended, so a shot is
## information: one that strikes the deck beside you is proof you were the target
## and that the guard was looking straight at you a moment ago. Inside this
## radius the runner believes it is watched immediately, with no reaction time
## charged -- being shot at is not something you have to notice.
@export_range(0.0, 30.0, 0.5) var tracer_alarm_metres: float = 6.0

## Seed for this runner's perception generator. Non-zero makes a run
## reproducible, which is what a sweep comparing two profiles needs; 0 seeds from
## the system entropy so three prisoners built from one resource do not guess
## wrong in the same direction at the same moment.
@export var perception_seed: int = 0

# --- Reading the reload -------------------------------------------------------

## Seconds the runner assumes a reload lasts when the round's rules do not say.
##
## The length of the reload is public -- it is the rhythm every prisoner on the
## ring has been listening to all match -- so the runner reads it from
## [member MatchRules.base_reload_seconds] when a match supplies one. This is the
## prior it falls back on in a test scene with no rules, and the number
## [member reload_read_accuracy] degrades away from.
@export_range(0.1, 15.0, 0.05) var assumed_reload_seconds: float = 2.5

## How well this runner reads the reload, from 0 to 1.
##
## At 1.0 the believed window is the true one. Below that, the belief is drawn
## from a normal distribution about the truth whose spread grows as the accuracy
## falls, re-drawn on every shot -- so a poor reader is sometimes early, which
## gets it shot, and sometimes late, which wastes the window. This is the knob
## that decides how much the reload is worth to a prisoner, and it is the axis
## most likely to settle whether the reload is the right length.
@export_range(0.0, 1.0, 0.01) var reload_read_accuracy: float = 0.75

## Seconds shaved off the believed window before it is used, as a safety margin.
##
## A prisoner who plans to arrive exactly as the rifle comes back is a prisoner
## who arrives slightly late. Raising this buys caution at the cost of shorter
## crossings; zero is a runner that spends every millisecond it believes it has.
@export_range(0.0, 3.0, 0.01) var reload_safety_margin: float = 0.35

# --- Patience and risk --------------------------------------------------------

## Seconds a runner settles behind fresh cover before it will consider leaving.
##
## Small on purpose. Without it a runner that arrives with speed still on the
## body re-evaluates on the arrival tick, breaks again, and skitters between two
## pieces of cover without ever holding one.
@export_range(0.0, 60.0, 0.05) var min_hold_seconds: float = 0.4

## Seconds of holding after which the runner will take any crossing at all. The
## patience knob, and the thing that stops a round from deadlocking.
##
## A ring of prisoners who all hide perfectly gives a guard nothing to shoot at,
## which gives the prisoners no reload to run in, which is a stalemate that ends
## in a timeout and measures nothing. So impatience is built in: from
## [member min_hold_seconds] the confidence a crossing must reach ramps linearly
## down to zero here. A patient runner survives longer and finishes slower; an
## impatient one is the reverse. That trade is the whole difficulty curve.
##
## [b]It is also what decides whether the reload is the game.[/b] Measured on the
## shipped arena, 12 matches per arm, same shooter and same seed: at 3 seconds
## the runner breaks 0.52x as often per tick during a reload as outside one -- it
## runs out of patience long before a window arrives and the rifle is simply
## irrelevant to it. At 6 seconds, 1.25x. At 12, 1.74x. At 20, 2.95x, but its
## caution starves the guard of targets and the guard'"'"'s hit rate goes back UP,
## because the few crossings it does see are the desperate ones. The default is
## on the near side of that peak, at roughly one mean interval between shots,
## which is the point where waiting for a window is worth more than the wait
## costs.
@export_range(0.1, 120.0, 0.1) var max_hold_seconds: float = 12.0

## The confidence, from 0 to 1, at or above which a rested runner will break
## cover. The risk knob.
##
## The direct counterpart of [member ShooterProfile.shot_confidence_threshold],
## and read the same way: high is a prisoner who waits for a crossing it believes
## in, low is one who chances it. At 1.0 nothing is ever good enough and only
## patience moves the runner, which is a perfectly good thing to measure against.
@export_range(0.0, 1.0, 0.01) var break_confidence_threshold: float = 0.55

## What the runner's confidence is multiplied by for the part of a crossing the
## reload does not cover, when it believes the guard is looking at it.
##
## Zero is a prisoner that will not step out under a watching eye at all;
## 1.0 is one that does not care where the guard is looking and plays the reload
## alone. It only ever applies to the exposed remainder -- a crossing the runner
## believes fits inside the reload is safe whatever the guard is looking at,
## because a reloading rifle cannot fire.
@export_range(0.0, 1.0, 0.01) var watched_confidence_penalty: float = 0.2

## How many points along a proposed path are tested for exposure.
##
## The runner prices a move by the OPEN GROUND on it, not by its length, so the
## straight line to a candidate is sampled this many times and each sample asked
## whether a shot could reach a body standing there. Too few and a narrow gap
## between two boxes is missed entirely and the move is priced as free; too many
## and a decision costs more raycasts than it is worth. Twelve puts a sample
## every two metres on a typical crossing.
@export_range(2, 64, 1) var path_samples: int = 12

## Metres of open ground that cost the runner nothing. Inside this a crossing
## scores a full exposure term.
@export_range(0.0, 200.0, 0.5) var free_crossing_metres: float = 8.0

## Metres of open ground at which the runner will not choose to cross at all: the
## exposure term falls linearly from 1.0 at [member free_crossing_metres] to 0.0
## here. Beyond it, only patience moves the runner.
@export_range(1.0, 400.0, 1.0) var max_crossing_metres: float = 60.0

# --- Finding cover ------------------------------------------------------------
#
# None of these name a position. The runner probes the world it is standing in
# with real raycasts and finds out where it can hide, so a new map needs no new
# numbers -- see RunnerCoverFinder.

## How far around the ring ahead of itself, in degrees, the runner looks for the
## next piece of cover. Too small and it cannot see past a wide gap and holds
## forever; too large and it will happily pick a piece forty metres away.
@export_range(5.0, 180.0, 1.0) var cover_search_arc_degrees: float = 75.0

## How many angular samples that arc is cut into. Together with the arc this sets
## the resolution of the search: at the defaults a sample every 2.7 degrees,
## which is about 2 m of track and comfortably finer than the 6 m cover pieces.
@export_range(2, 128, 1) var cover_search_steps: int = 28

## How wide a band of radii the runner probes, in metres, centred on the track.
##
## The deck is 25 m across and cover sits in three radial bands, so a prisoner
## that only ever probed the track's own radius could not use two thirds of the
## map. This is how far it is willing to leave the track to get behind
## something.
@export_range(0.0, 60.0, 0.5) var cover_search_radial_span: float = 22.0

## How many radii that band is cut into. Odd values keep one sample exactly on
## the track.
@export_range(1, 33, 2) var cover_search_radial_steps: int = 9

## How far into a cover shadow, in metres of arc, a candidate must still be
## hidden before the runner will accept it.
##
## The near edge of a shadow is a place you are hidden and one step from not
## being. Requiring the point this far further along to be hidden too is what
## makes the runner stop somewhere it can stand rather than on the boundary.
@export_range(0.0, 20.0, 0.1) var cover_depth_metres: float = 2.5

## The least a candidate must advance the lap, in metres of arc, to be worth
## crossing to. Stops the runner from re-picking the cover it is already behind.
@export_range(0.0, 60.0, 0.5) var cover_min_advance_metres: float = 5.0

## How close, in metres, counts as having arrived at a chosen spot.
@export_range(0.1, 10.0, 0.1) var cover_arrival_tolerance: float = 1.5

## The most a candidate's floor may sit above or below the runner's own feet, in
## metres, and still be somewhere it could walk to.
##
## This is what rejects the TOP of a cover box -- a point that is genuinely
## hidden from the tower and genuinely unreachable -- and the pit floor twelve
## metres down, without either being named anywhere.
@export_range(0.05, 10.0, 0.05) var cover_max_step_height: float = 1.0

## Seconds a crossing may overrun the time it should have taken before the runner
## gives up on it and looks for cover again, as a multiple of the estimate.
##
## Being shoved by another prisoner, or catching a corner, leaves a runner
## walking at a spot it will never reach. This is the only thing that notices.
@export_range(1.0, 10.0, 0.1) var cross_timeout_multiple: float = 2.5

# --- Sliding --------------------------------------------------------------

## Metres of open ground a crossing must have before the runner bothers sliding
## across it. Judged once, at the moment the crossing is committed to -- see
## [method RingRunner._begin_cross] -- because CROSS faces the destination and
## the runner cannot read the tower again until it arrives, so that is the only
## tick with anything left to decide.
##
## A slide trades weak steering and a lower profile for a burst of speed. That
## is worth it on essentially any real crossing -- the floor here exists only to
## keep a shuffle of a few centimetres along the inside of the runner's own
## cover, where [method RingRunner._measure_exposure] returns something above
## zero purely from sampling and floor noise, from reading as a "crossing" at
## all. It is deliberately low: this is meant to fire on most real crossings a
## match sees, not to be a second risk gate sitting on top of the cover game's
## own -- that belongs to [member break_confidence_threshold] and the rest of
## the patience knobs above, not to this one.
@export_range(0.0, 60.0, 0.1) var slide_min_exposed_metres: float = 1.0

# --- Jumping ------------------------------------------------------------------
#
# Two triggers, and neither of them is a die roll. See [method
# RingRunner._maybe_jump] for the whole argument; the short of it is that a hop
# costs steering authority and buys two things -- the ground's friction is not
# applied on the tick a body leaves it, and a body in the air is not on the line
# a rifle led along the floor -- so the runner hops exactly where those are worth
# having, and nowhere else.
#
# Every field here is read only by the cover-playing prisoner. The BASELINE lap
# never jumps, deliberately: it is the control case this whole resource exists to
# be measured against, and a control that changes is not one.

## Whether this prisoner may jump at all.
##
## The A/B switch, and the reason it is a field rather than a constant: "does
## hopping across open ground actually help a prisoner live" is a question for a
## sweep to answer by running the same profile twice, not for this file to assume
## either way.
@export var jump_enabled: bool = true

## Seconds between hops, however either of them was triggered.
##
## What stops a runner from bunny-hopping the lap. [member
## MovementProfile.auto_bunny_hop] is on, so a HELD jump re-launches on the
## landing tick and a body can chain hops with about four ticks of floor in every
## hundred and eighty -- fast, but with air control instead of ground
## acceleration for the whole crossing, and with no floor under it long enough
## for [method PlayerController._try_begin_slide] to ever open a slide. This
## brain therefore never holds jump; it presses, once, and this is the wait
## before it may press again. Roughly twice a hop's 0.64 s hang time, so a hopping
## runner spends about a third of its crossing airborne rather than all of it.
@export_range(0.0, 10.0, 0.05) var jump_cooldown_seconds: float = 1.2

## Metres of crossing that must still be left before the runner will hop to carry
## speed.
##
## The approach is not the place for it. A hop is 0.64 s of weak steering, and
## spending it on the last few metres means arriving past the cover rather than
## behind it -- which on a crossing is the one mistake that leaves a prisoner
## standing in the open having done everything else right. It is also the gate
## that keeps an airborne body away from the far end of a path this brain has
## never checked for floor.
@export_range(0.0, 60.0, 0.5) var jump_min_remaining_metres: float = 6.0

## Horizontal speed, in m/s, under which a runner that is pressed against
## something and still asking to move counts as stuck.
##
## Comfortably under [member MovementProfile.crouch_speed] so that walking, in
## any stance, is never mistaken for being blocked.
@export_range(0.0, 20.0, 0.05) var jump_blocked_speed: float = 1.5

## How long that has to stay true before the runner tries hopping over whatever
## it is.
##
## Not one tick: a body leaving cover is genuinely near zero for a moment, and a
## body that clips a corner at speed is stopped for a moment. This is the wait
## that tells a snag from a stop.
@export_range(0.0, 5.0, 0.05) var jump_blocked_seconds: float = 0.35


# --- Derived values -----------------------------------------------------------

## True when this profile builds the cover-playing prisoner. One place, so no
## caller grows its own idea of what the mode means.
func plays_cover() -> bool:
	return behaviour == Behaviour.COVER


## The half-angles of the runner's view, horizontal then vertical, in radians,
## with [member fov_margin] already applied.
func get_view_half_angles() -> Vector2:
	var vertical: float = deg_to_rad(view_fov_degrees) * 0.5
	return Vector2(atan(tan(vertical) * view_aspect), vertical) * fov_margin


## [member attention_cone_degrees] in radians.
func get_attention_cone_radians() -> float:
	return deg_to_rad(attention_cone_degrees)


## [member attention_read_error_degrees] in radians.
func get_attention_read_error_radians() -> float:
	return deg_to_rad(attention_read_error_degrees)


## [member cover_search_arc_degrees] in radians.
func get_cover_search_arc_radians() -> float:
	return deg_to_rad(cover_search_arc_degrees)


## A generator seeded as this profile asks. [member perception_seed] of 0 means
## "seed from entropy", so three prisoners sharing one resource still guess
## independently.
func make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if perception_seed == 0:
		rng.randomize()
	else:
		rng.seed = perception_seed
	return rng


## The profile a round wants, or [param fallback] when it has no opinion.
##
## [b]The MatchRules seam.[/b] Difficulty in this project is decided by the
## round's rules and never by a scene, because that is the only way a headless
## sweep can vary it -- see [member MatchRules.ai_shooter_profile], which is the
## same seam for the other side of the game.
##
## Two routes are honoured, in order, and both name the same field:
##
## 1. An [code]ai_runner_profile[/code] PROPERTY on [MatchRules]. This is the
##    destination. [MatchRules] does not carry it yet, so the lookup is by
##    property list rather than by dot access -- the moment the export is added
##    it is picked up here with no further change.
## 2. An [code]ai_runner_profile[/code] entry in the rules resource's METADATA,
##    which a [code].tres[/code] can carry today without [MatchRules] knowing
##    anything about prisoners. This is what lets a sweep vary runner difficulty
##    now.
##
## Null rules, or rules with no opinion, leave the scene's own profile in charge,
## which is what a runner dropped into a test scene sees.
static func resolve(rules: MatchRules, fallback: RunnerProfile) -> RunnerProfile:
	if rules == null:
		return fallback

	for entry: Dictionary in rules.get_property_list():
		if String(entry.get("name", "")) == "ai_runner_profile":
			var exported: RunnerProfile = rules.get("ai_runner_profile") as RunnerProfile
			if exported != null:
				return exported
			break

	if rules.has_meta(&"ai_runner_profile"):
		var carried: Variant = rules.get_meta(&"ai_runner_profile")
		var from_meta: RunnerProfile = _as_profile(carried)
		if from_meta != null:
			return from_meta

	return fallback


## A metadata value read back as a profile.
##
## A [code].tres[/code] may carry either the resource itself, as an
## [code]ExtResource[/code], or a path to one -- and a sweep spec that writes the
## metadata from JSON can only write the path. Both are accepted; anything else
## is somebody's mistake and is reported rather than silently ignored, because a
## difficulty that quietly failed to apply would make a whole sweep a lie.
static func _as_profile(value: Variant) -> RunnerProfile:
	var direct: RunnerProfile = value as RunnerProfile
	if direct != null:
		return direct
	if typeof(value) == TYPE_STRING:
		var path: String = String(value)
		var loaded: RunnerProfile = load(path) as RunnerProfile
		if loaded == null:
			push_error("MatchRules.ai_runner_profile names %s, which is not a RunnerProfile." % path)
		return loaded
	push_error("MatchRules.ai_runner_profile is neither a RunnerProfile nor a path to one.")
	return null
