class_name MatchRules
extends Resource

## Every design parameter of a PANOPTICON round, in one swappable resource.
##
## [b]Why this exists[/b]
##
## This project settles design arguments by running headless bot matches across
## rule variants and comparing the outcomes, not by reasoning about them. That
## only works if every design decision is DATA the harness can vary per match. A
## value hard-coded in a script is a question that can never be asked, and a
## question that can never be asked is a design decision made permanently by
## accident. So: if it is a rule of the round, it lives here, even when it is
## not yet implemented -- because a field with a default is a value change later,
## and an absent field is a refactor later.
##
## [b]Which resource does a number belong in?[/b]
##
## This is the seam people get wrong, so it is stated plainly:
##
## - [MatchRules] -- DESIGN. What the round is: how many prisoners, what wins,
##   what loses, how long the rifle is silent, whether a shot prisoner is gone.
##   Change one of these and you are playing a different game. One instance per
##   match, and the harness sweeps it.
## - [MovementProfile] -- COMPONENT tuning. How a body accelerates, how high it
##   jumps, how it handles slopes. Intrinsic to the character controller and the
##   same for every match; a human and a bot share it deliberately, so that bot
##   telemetry describes the game humans play.
## - [WeaponProfile] -- COMPONENT tuning. What the rifle IS: range, hit mask,
##   tracer look, the committed firing window, the weapon's own hard floor on
##   reload. Intrinsic to the gun.
## - [BotProfile] -- COMPONENT tuning. How the runner's steering loop behaves:
##   gain, yaw ceiling, lookahead, arrival tolerance. Intrinsic to the brain.
##
## The one deliberate overlap is the reload. [member WeaponProfile.base_reload_seconds]
## is what the rifle does when nobody has said otherwise, and
## [member WeaponProfile.min_reload_seconds] is the weapon's own safety floor
## that no match rule may drill through. [member base_reload_seconds] here is
## the match's answer, and it wins when a match supplies one -- because "how long
## is the tower silent" is the single most important design question in the game
## and it must be sweepable per match, not per gun.
##
## [b]LIVE vs DEFERRED[/b]
##
## Every field below is marked one of the two. [b]LIVE[/b] means code reads it
## today and changing it changes the game. [b]DEFERRED[/b] means the design
## question is open, the field exists so that answering it later is a value
## change rather than a refactor, and its default reproduces exactly what the
## game does today. No default here invents an answer to an open question.
##
## Units are metres, seconds and degrees unless a field name says otherwise.

# --- Enums --------------------------------------------------------------------

## How the shooter wins.
##
## Only [constant ShooterWinCondition.TOTAL_CONVERSION] is implemented; the
## others are the alternatives already known to be worth measuring, named now so
## that a sweep can be pointed at them the day they are built. Selecting an
## unimplemented condition warns and produces a round the shooter cannot win --
## it does not silently fall back on total conversion, because a sweep that
## quietly measured the wrong rule is worse than one that refuses to run.
enum ShooterWinCondition {
	## Remove every prisoner. Today's rule, and the one the arena was built for:
	## the tower must stop all of them, the runners need only one through.
	TOTAL_CONVERSION,
	## Remove at least [member shutout_count] prisoners, arrivals notwithstanding.
	## A softer, scored win. OPEN QUESTION -- whether a partial win is a win at
	## all, and at what count, is exactly what a sweep should answer. NOT
	## IMPLEMENTED.
	SHUTOUT_COUNT,
	## Survive [member hold_duration_seconds] without a prisoner arriving. Turns
	## the round from an elimination into a siege. OPEN QUESTION, and the one
	## most likely to change how the ring should be laid out. NOT IMPLEMENTED.
	HOLD_DURATION,
}

## How the runners win -- equivalently, what loses the round for the shooter.
##
## Both are implemented. [constant RunnerWinCondition.FIRST_ARRIVAL] is today's
## rule and the asymmetry the whole game is built on.
enum RunnerWinCondition {
	## One prisoner reaching the end ends the round, immediately, with survivors
	## still on the ring. Today's rule.
	FIRST_ARRIVAL,
	## Every prisoner still in the round must reach the end. Makes the round a
	## question of throughput rather than of leakage. OPEN QUESTION: it is not
	## known whether this produces a better game or merely a longer one.
	ALL_ARRIVALS,
}

## What a prisoner becomes when the rifle takes their last life.
##
## Today they are simply removed and there is nothing left to be. The other
## members are the shapes the answer might take and are provisional names for
## provisional ideas; none is implemented.
enum GhostBehaviour {
	## The body is freed and the prisoner is out of the round. Today's rule.
	NONE,
	## The prisoner stays in the world as a non-interacting observer. OPEN
	## QUESTION -- whether a dead prisoner watching is atmosphere or dead time.
	## NOT IMPLEMENTED.
	SPECTATOR,
	## The prisoner keeps running their lane in a ghost state, still able to
	## reach the end, possibly counting for something less than an arrival. OPEN
	## QUESTION, and the one that most changes what a shot is worth. NOT
	## IMPLEMENTED.
	CONTINUE_LAP,
}

# --- The prisoners ------------------------------------------------------------

## How many prisoners run the round. [b]LIVE.[/b]
##
## Three is the shipped round and the number the arena's three clear channels
## were measured for. It is not a settled design answer: prisoner count against a
## single-shot rifle is the crudest difficulty dial the game has, and the
## relationship between count, reload and lap time is precisely the sort of thing
## this project exists to measure rather than argue about.
##
## Radii come from [member lane_radii]; see [method get_lane_radius] for what
## happens when the count outruns the list.
@export_range(1, 32, 1, "or_greater") var prisoner_count: int = 3

## The lane each prisoner holds, in metres from the arena centre. [b]LIVE.[/b]
##
## Not free numbers. The deck is an annulus from r=35 to r=60 and cover sits in
## three radial lanes centred on r=41, r=47.5 and r=54, each piece sweeping a
## band of roughly +/-0.9 m about its lane. A [RingRunner] does not path around
## anything, so a radius inside a cover band walks a 0.4 m capsule into a box and
## stands there for the rest of the round. 38.5 / 44.5 / 51.0 are the clear
## channels, and they are 6.5 m apart so the runners never touch.
##
## Whether prisoners should be free to choose or change lanes is an OPEN
## QUESTION; today the lane is assigned and held for the whole lap.
##
## This is a POOL, not a roster. A round takes the first [member prisoner_count]
## entries, so the three-runner round is unchanged by the fourth radius below;
## the fourth exists because the opening race puts EVERY participant on the ring
## at once and a match has [method get_participant_count] of them. 57.5 is the
## fourth clear channel: the outer cover lane sweeps 53.1-54.9 and the wall is at
## r=60, so 57.5 is 2.6 m clear of cover and 2.5 m clear of the wall.
@export var lane_radii: PackedFloat32Array = PackedFloat32Array([38.5, 44.5, 51.0, 57.5])

## Hits a prisoner absorbs before leaving the round. [b]LIVE[/b], default 1.
##
## 1 is one-shot-one-removal, which until now was an unwritten assumption spread
## across three files: the rifle has no damage number, the runner has no health,
## and the controller removed on the first hit. It is written down here so that
## "what if a prisoner could take two" is a number to sweep rather than a feature
## to build.
##
## Above 1 the surviving prisoner is given no feedback and no recovery -- there is
## no hit reaction, no stagger and no regeneration, because none of those are
## designed. Sweep it; do not ship it without deciding what a survived hit looks
## like.
@export_range(1, 10, 1, "or_greater") var prisoner_lives: int = 1

## Walk or sprint, for every prisoner in the round. [b]LIVE.[/b]
##
## Deliberately a mode rather than a speed: the actual m/s live in
## [MovementProfile] and are shared with the human, so bot telemetry keeps
## describing the game humans play. This overrides
## [member BotProfile.speed_mode] whenever a match supplies rules, because pace
## is a rule of the round, not a property of one brain.
##
## OPEN QUESTION, and a large one: a sprinting prisoner crosses a reload's worth
## of ring in 11 m/s * reload metres instead of 8, which is the difference
## between the tower denying ground and merely occupying it.
@export var bot_speed_mode: BotProfile.SpeedMode = BotProfile.SpeedMode.WALK

# --- The rifle ----------------------------------------------------------------

## Seconds of enforced silence after a shot, at the start of the round.
## [b]LIVE.[/b]
##
## The clock the whole match runs on. At walk speed a prisoner covers roughly
## [code]base_reload_seconds * 8[/code] metres of ring between shots, so this is
## really "how many metres of forgiveness a prisoner is granted for being seen".
##
## The default equals [member WeaponProfile.base_reload_seconds] on the shipped
## weapon, so leaving it alone reproduces today's rifle exactly. Set it to 0.0 to
## defer to the weapon's own value instead of overriding it -- useful when a
## sweep is varying weapons rather than rules.
##
## The value is still clamped by the weapon's [member WeaponProfile.min_reload_seconds]:
## a match rule may retune the gun, not redesign it into an automatic.
@export_range(0.0, 15.0, 0.05, "or_greater") var base_reload_seconds: float = 2.5

## Seconds the reload shortens by for each turn a player has spent in the tower.
## [b]LIVE[/b], and the match's terminator. Default 0.0 = no escalation, which is
## what the game did before turns existed.
##
## The designed shape of "the tower gets better the longer you hold it": a player
## who keeps taking the tower is rewarded with a faster clock, which is also the
## only thing that stops a match between two evenly matched players running
## forever. [MatchController] reads it through
## [method get_reload_seconds_for_turn] on every seat change; which turns count
## is [member turn_count_resets_on_seat_loss]'s business.
##
## The shipped [code]resources/rules/default_match_rules.tres[/code] sets this to
## a real value, because with 0.0 there is no terminator and the match has no
## guaranteed end. The code default stays 0.0 so a rule set built in isolation
## reproduces the pre-turn behaviour exactly.
##
## OPEN QUESTION on two axes at once: the per-turn step, and whether the
## escalation should be linear at all rather than, say, halving toward the floor.
## [method get_reload_seconds_for_turn] implements the linear reading so that a
## sweep has something concrete to measure; it is a starting point, not an answer.
@export_range(0.0, 2.0, 0.01, "or_greater") var reload_reduction_per_turn: float = 0.0

## Floor the match rules impose on the reload, however far escalation runs.
## [b]LIVE[/b] as a clamp, default 0.0 = no match floor, defer to the weapon's
## own [member WeaponProfile.min_reload_seconds].
##
## Separate from the weapon's floor on purpose. The weapon's floor is a design
## guarantee about what a single-shot rifle IS and should essentially never move;
## this one is a per-match tuning bound a sweep can tighten. The effective floor
## is whichever is higher, so a sweep can never drill through the weapon's.
@export_range(0.0, 5.0, 0.01, "or_greater") var reload_floor_seconds: float = 0.0

# --- Winning and losing -------------------------------------------------------

## What the shooter must do to win. [b]LIVE[/b] for
## [constant ShooterWinCondition.TOTAL_CONVERSION], which is today's rule; the
## other members are declared but unimplemented and produce an unwinnable round
## plus a warning. See [enum ShooterWinCondition].
@export var shooter_win_condition: ShooterWinCondition = ShooterWinCondition.TOTAL_CONVERSION

## Prisoners the shooter must remove under
## [constant ShooterWinCondition.SHUTOUT_COUNT]. [b]DEFERRED[/b], inert while the
## win condition is total conversion. 0 means "unset", which is honest: no count
## has been chosen, and choosing one is what a sweep is for.
@export_range(0, 32, 1, "or_greater") var shutout_count: int = 0

## Seconds the shooter must hold out under
## [constant ShooterWinCondition.HOLD_DURATION]. [b]DEFERRED[/b], inert while the
## win condition is total conversion. 0.0 means unset.
@export_range(0.0, 600.0, 1.0, "or_greater") var hold_duration_seconds: float = 0.0

## What the prisoners must do to win. [b]LIVE[/b], both members implemented.
## Default [constant RunnerWinCondition.FIRST_ARRIVAL] is today's rule: one
## through and the round is over.
@export var runner_win_condition: RunnerWinCondition = RunnerWinCondition.FIRST_ARRIVAL

## Wall-clock seconds before the round is cut short. [b]DEFERRED[/b], default 0.0
## = no limit, which is the current design.
##
## Nothing reads this yet, and deliberately so: the field records that a limit is
## a knob, but what a round SHOULD resolve to when the clock expires -- shooter
## win, prisoner win, or a third outcome the [enum MatchController.Outcome] enum
## does not yet have -- is undecided. Wiring a timer to an unnamed outcome would
## be inventing the answer. When the answer is measured, the outcome member and
## the timer land together.
@export_range(0.0, 1800.0, 1.0, "or_greater") var round_time_limit_seconds: float = 0.0

# --- The match ----------------------------------------------------------------
#
# A match is many rounds and produces exactly one winner. One player holds the
# tower; everyone else runs. A runner who reaches the end takes the tower and
# the round starts again from the beginning. Reaching the end never wins the
# match -- it wins the SEAT. The match is won by holding the seat through a
# round, and the reload escalation above is what guarantees that eventually
# happens.

## Open the match with a seatless race for the tower. [b]LIVE[/b], default true.
##
## With it on, the match begins with NO shooter: every participant runs the ring
## and the first to reach the end takes the tower. It is the design's answer to
## "who shoots first", and it is deliberately not a coin toss -- the seat is won
## by running, on the shipped map, with the shipped movement.
##
## Off, the match opens with the first participant already in the tower on turn
## one, which is what the game did before the race existed and what a harness
## measuring a single round wants.
@export var open_with_race: bool = true

## Rounds a player must win AS THE SHOOTER to win the match. [b]LIVE[/b],
## default 1 = the shipped design: hold the tower through one round and it is
## over.
##
## Above 1 the shooter keeps the seat after a won round and starts another,
## which makes the tower a thing to defend repeatedly rather than once. OPEN
## QUESTION; 1 is the decided answer today.
@export_range(1, 16, 1, "or_greater") var rounds_to_win_match: int = 1

## Whether a player's tower-turn count falls back to zero when they lose the
## seat. [b]LIVE[/b], default false = the count never resets.
##
## This is the "consecutive" in [member reload_reduction_per_turn], written down
## because the word has two readings and they produce different games:
##
## - [b]false (shipped)[/b] -- a player's turns accumulate for the whole match.
##   Turn three is turn three whether or not somebody else held the tower in
##   between. This is the reading the design's terminator REQUIRES: "a weak
##   shooter who keeps regaining the seat eventually becomes strong enough to
##   close it out" is only true if regaining the seat is progress.
## - [b]true[/b] -- losing the seat wipes the count and a returning shooter
##   starts again on the base reload. Under this reading two evenly matched
##   players can trade the tower forever, so the match has no terminator at all.
##   It is here to be measured, not to be shipped.
@export var turn_count_resets_on_seat_loss: bool = false

## How close to the finish, in metres of arc, counts as having reached the end.
## [b]LIVE.[/b]
##
## Every participant is judged by this one number, human and AI alike, which is
## what makes the opening race a race rather than two different tests run side by
## side. The default matches [member BotProfile.arrival_tolerance] on the shipped
## bot profile, so a baseline runner scores on the same tick it stops.
@export_range(0.1, 10.0, 0.1, "or_greater") var lap_arrival_tolerance: float = 1.5

## Stagger the race's starting angles so every lane is the same length.
## [b]DEFERRED[/b], default false = every racer starts on the start pad, which is
## where runners have always started.
##
## The problem it addresses is real: at r=38.5 a lap is 235 m and at r=57.5 it is
## 351 m, so a racer's lane is worth up to a third of the race. The reason it is
## off by default is that the fix is only a fix for a runner that stays in its
## lane. A lane is a spawn position, not a rail -- only the baseline [RingRunner]
## holds a radius, and a human handed the outer lane would simply cut inside and
## keep the shorter arc as a gift. Equal ARC from a shared start pad is the
## honest rule for bodies that may run anywhere; equal LENGTH is the honest rule
## for bodies on rails. The game has both, so this is a question to measure.
##
## When true, each racer starts at the angle that leaves them
## [code](full lap arc) * (smallest lane radius)[/code] metres of their own lane
## to run, so the outer lanes start further round.
@export var equalise_race_lane_distance: bool = false

# --- Ghosts -------------------------------------------------------------------

## What becomes of a prisoner the rifle finishes. [b]DEFERRED[/b], default
## [constant GhostBehaviour.NONE] = removed outright, which is today's behaviour.
##
## The whole ghost design hangs off this one value, and while it is
## [constant GhostBehaviour.NONE] the two fields below are inert by definition.
## See [enum GhostBehaviour] for what the alternatives would mean.
@export var ghost_behaviour: GhostBehaviour = GhostBehaviour.NONE

## Multiplier on a ghost's movement speed. [b]DEFERRED[/b], inert while
## [member ghost_behaviour] is [constant GhostBehaviour.NONE]. 1.0 = a ghost
## moves exactly as it did alive, which is the neutral assumption rather than a
## decision -- whether death should cost or grant pace is an OPEN QUESTION.
@export_range(0.0, 4.0, 0.05, "or_greater") var ghost_speed_multiplier: float = 1.0

## Whether the rifle can hit a ghost. [b]DEFERRED[/b], inert while
## [member ghost_behaviour] is [constant GhostBehaviour.NONE]. False = shots pass
## through, so ghosts cannot soak the tower's one shot. OPEN QUESTION: shootable
## ghosts turn a corpse into cover, which is either a good mechanic or a
## griefing tool and only measurement will say which.
@export var ghosts_shootable: bool = false

# --- Guard vision -------------------------------------------------------------

## The guard's horizontal field of view for game-rule purposes, in degrees.
## [b]DEFERRED[/b], default 360.0 = unrestricted, which is today's behaviour.
##
## Not the camera's FOV -- that is a rendering and feel setting on the player
## scene and has no business being a match rule. This is the arc within which the
## guard is considered to be able to SEE a prisoner, for anything that will
## eventually depend on being seen: a prisoner's read on whether they are marked,
## a detection tell, an AI guard's targeting. Nothing reads it yet because no
## such rule exists yet; 360.0 encodes "seeing is not currently gated on an arc".
@export_range(1.0, 360.0, 1.0) var guard_fov_degrees: float = 360.0

## Whether the guard's sightlines ignore geometry. [b]DEFERRED[/b], default false
## = cover blocks sight, which is today's behaviour and the reason cover exists.
##
## True would mean the guard sees through the ring's cover for rule purposes --
## a debug and measurement setting first (it isolates "how much does cover
## actually buy a prisoner" by removing it without moving a single box), and
## conceivably a difficulty setting later. It does NOT make the rifle's raycast
## pass through walls; the ray is the weapon's business and stops on what it
## stops on.
@export var guard_sightlines_unobstructed: bool = false

# --- The AI in the tower ------------------------------------------------------

## The [ShooterProfile] an AI participant plays the tower on. [b]LIVE[/b],
## default null = no match opinion, and [MatchController] falls back to the
## shipped profile at [constant MatchController.DEFAULT_SHOOTER_PROFILE_PATH].
##
## This is the match's GUARD DIFFICULTY dial, and it belongs here for exactly
## the reason every other rule does: "how good is the tower" is a design
## question this project settles by sweeping it, and a difficulty baked into a
## scene is a question that can never be asked.
##
## The seam is the usual one. What is inside the profile -- reaction time, aim
## error, confidence threshold -- is COMPONENT tuning of the brain, exactly as
## [BotProfile] is for a runner. What is a rule of the MATCH is which profile
## the tower is played on, which is this field.
##
## The resource is never mutated: [MatchController] duplicates it per
## participant, so a sweep that varies the seed cannot retune the shared .tres
## for whatever runs next in the same process.
@export var ai_shooter_profile: ShooterProfile

## Per-participant difficulty, indexed by [member MatchParticipant.index].
## [b]LIVE[/b], default empty = every AI plays the tower on
## [member ai_shooter_profile].
##
## An entry that is null, and any index past the end, falls back to
## [member ai_shooter_profile]. Index 0 is the human when a match has one and a
## human never reads a shooter profile, so slot 0 is simply unused there -- the
## index stays the participant's own rather than becoming a second, shifted one
## that has to be corrected at every call site.
##
## The point is asymmetric matches. Measuring what a change to the guard is
## worth needs the guards to DIFFER within one match; a single profile can only
## produce a field where every tower plays identically and the sole remaining
## variable is who happened to reach the end first.
@export var ai_shooter_profiles: Array[ShooterProfile] = []

## Seed for the AI shooters' aim error. [b]LIVE[/b], default 0 = seed from
## entropy, exactly as [member ShooterProfile.aim_random_seed] reads it.
##
## Non-zero makes a match replayable: participant [code]i[/code] is given
## [code]seed + i + 1[/code], so the bots miss in different directions while the
## whole match still replays identically from one number. It is written into the
## per-participant COPY of the profile, never into the profile itself.
@export var ai_shooter_aim_seed: int = 0


# --- Derived values -----------------------------------------------------------

## Lane radius for prisoner [param index], in metres.
##
## When [member prisoner_count] exceeds [member lane_radii], the last radius is
## reused rather than wrapping or inventing a spacing: two capsules on the same
## lane is an obvious, visible misconfiguration, whereas a silently invented
## radius could land inside a cover band and produce a round that looks fine and
## measures nothing. Returns 0.0 only if the list is empty, which
## [method validate] reports.
func get_lane_radius(index: int) -> float:
	if lane_radii.is_empty():
		return 0.0
	return lane_radii[clampi(index, 0, lane_radii.size() - 1)]


## Exactly [member prisoner_count] radii, padded from the last entry if the list
## is short. What a round's spawner should iterate.
func get_lane_radii() -> PackedFloat32Array:
	return get_lane_radii_for(prisoner_count)


## Exactly [param count] radii, padded from the last entry if the pool is short.
##
## The opening race puts every participant on the ring at once, which is one more
## body than a round has, so the number of lanes wanted is not always
## [member prisoner_count]. Padding repeats the last radius, which is a visible
## misconfiguration rather than an invented lane -- see [method get_lane_radius].
func get_lane_radii_for(count: int) -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	for index: int in maxi(count, 0):
		radii.append(get_lane_radius(index))
	return radii


## How many players a match has: one in the tower and [member prisoner_count] on
## the ring.
##
## Derived rather than exported, because a round with fewer runners than
## [member prisoner_count] is a different round, and a match that cannot field
## one is not a match. The human is one of these when a match has a human; the
## rest are AI.
func get_participant_count() -> int:
	return maxi(prisoner_count, 1) + 1


## True when the prisoners should hold sprint. Keeps the enum comparison in one
## place, exactly as [method BotProfile.wants_sprint] does, so no caller grows
## its own idea of what SPRINT means.
func wants_sprint() -> bool:
	return bot_speed_mode == BotProfile.SpeedMode.SPRINT


## The reload these rules ask for, given what the weapon would do on its own.
##
## [param weapon_base] is [member WeaponProfile.base_reload_seconds]. A
## [member base_reload_seconds] of 0.0 means "no match opinion", and the weapon's
## own value is returned untouched.
func get_base_reload_seconds(weapon_base: float) -> float:
	if base_reload_seconds <= 0.0:
		return weapon_base
	return base_reload_seconds


## The effective reload floor: the higher of the match's and the weapon's.
##
## [param weapon_floor] is [member WeaponProfile.min_reload_seconds]. Taking the
## maximum is what makes the weapon's floor a guarantee -- a match rule may
## tighten the bound, never loosen it.
func get_reload_floor_seconds(weapon_floor: float) -> float:
	return maxf(reload_floor_seconds, weapon_floor)


## Reload duration on the [param turn_index]-th turn in the tower, zero-based,
## floored.
##
## The linear reading of [member reload_reduction_per_turn].
## [method MatchController.take_seat] calls it on every seat change with the new
## holder's own turn count minus one, so turn one is always the base reload.
## Which turns are counted is [member turn_count_resets_on_seat_loss]'s business,
## not this function's. See [member reload_reduction_per_turn] for what is still
## open.
func get_reload_seconds_for_turn(turn_index: int, weapon_base: float, weapon_floor: float) -> float:
	var base: float = get_base_reload_seconds(weapon_base)
	var reduced: float = base - reload_reduction_per_turn * float(maxi(turn_index, 0))
	return maxf(reduced, get_reload_floor_seconds(weapon_floor))


## The [ShooterProfile] participant [param index] plays the tower on, or null
## when these rules have no opinion and the caller should fall back to its own
## default. See [member ai_shooter_profiles].
func get_ai_shooter_profile_for(index: int) -> ShooterProfile:
	if index >= 0 and index < ai_shooter_profiles.size() and ai_shooter_profiles[index] != null:
		return ai_shooter_profiles[index]
	return ai_shooter_profile


## The aim-error seed participant [param index] draws with, or 0 for entropy.
##
## Derived from one number rather than exported per participant so that a whole
## match replays from a single [member ai_shooter_aim_seed], and so that two
## bots in the same match never share a seed and therefore never miss in
## lockstep.
func get_ai_shooter_seed_for(index: int) -> int:
	if ai_shooter_aim_seed == 0:
		return 0
	return ai_shooter_aim_seed + maxi(index, 0) + 1


## True when [member shooter_win_condition] is one the round actually implements.
## A round configured with an unimplemented condition still runs -- it just
## cannot be won by the shooter -- and says so once, loudly.
func is_shooter_win_condition_implemented() -> bool:
	return shooter_win_condition == ShooterWinCondition.TOTAL_CONVERSION


## Problems with this rule set, as human-readable lines. Empty means usable.
##
## Checks only what is objectively broken -- a round that cannot spawn or cannot
## be won -- and never second-guesses a design choice, because the whole point of
## this resource is that the design choices are the harness's to make.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if prisoner_count < 1:
		problems.append("prisoner_count is %d; a round needs at least one prisoner." % prisoner_count)
	if lane_radii.is_empty():
		problems.append("lane_radii is empty; there is nowhere to put a prisoner.")
	if not is_shooter_win_condition_implemented():
		problems.append(
			"shooter_win_condition is %s, which is declared but not implemented; the shooter cannot win this round."
			% String(ShooterWinCondition.keys()[shooter_win_condition])
		)
	if shooter_win_condition == ShooterWinCondition.SHUTOUT_COUNT and shutout_count <= 0:
		problems.append("shooter_win_condition is SHUTOUT_COUNT but shutout_count is unset.")
	if shooter_win_condition == ShooterWinCondition.HOLD_DURATION and hold_duration_seconds <= 0.0:
		problems.append("shooter_win_condition is HOLD_DURATION but hold_duration_seconds is unset.")
	if open_with_race and lane_radii.size() < get_participant_count():
		# Padding would put two racers on one radius, and the race for the tower
		# is the one moment every participant is on the ring at once.
		problems.append(
			"open_with_race needs %d lanes for %d participants but lane_radii has %d; racers would share a lane."
			% [get_participant_count(), get_participant_count(), lane_radii.size()]
		)
	if reload_reduction_per_turn <= 0.0:
		# Not broken, but worth saying out loud: this is the only rule that
		# guarantees a match ends.
		problems.append(
			"reload_reduction_per_turn is 0.0; the tower never gets faster, so a match has no terminator."
		)
	return problems
