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
## All three are implemented and all three are selectable. They are genuinely
## different rules and none of them falls back on another: a round played under
## one is never quietly decided by the terms of a second, because a sweep that
## measured the wrong rule is worse than one that refuses to run. That refusal
## is still here for a member added to this enum LATER --
## [method is_shooter_win_condition_implemented] names the three by hand, so a
## fourth is unwinnable and loudly warned about until somebody builds it.
enum ShooterWinCondition {
	## Remove every prisoner. Today's rule, and the one the arena was built for:
	## the tower must stop all of them, the runners need only one through.
	TOTAL_CONVERSION,
	## Remove at least [member shutout_count] prisoners, arrivals notwithstanding.
	## A softer, scored win. OPEN QUESTION -- whether a partial win is a win at
	## all, and at what count, is exactly what a sweep should answer; the count
	## itself is [member shutout_count] and this file chooses none.
	##
	## Counted PER ROUND, over the removals of the round being played, because a
	## seat change restarts the round and no progress carries across one -- see
	## [MatchController]'s header. "Arrivals notwithstanding" is what separates
	## it from [constant ShooterWinCondition.TOTAL_CONVERSION]: the tower is not
	## asked to stop everybody, only to take [member shutout_count] of them, and
	## whoever got through in the meantime does not undo that.
	SHUTOUT_COUNT,
	## Survive [member hold_duration_seconds] without a prisoner arriving. Turns
	## the round from an elimination into a siege. OPEN QUESTION, and the one
	## most likely to change how the ring should be laid out.
	##
	## The clock is the ROUND's, started when the round is armed and restarted
	## with it, so "without a prisoner arriving" needs no separate test: an
	## arrival that satisfies [member runner_win_condition] resolves the round
	## before the hold can expire, and one that does not satisfy it has not
	## taken the tower and does not stop the clock. Removing every prisoner is
	## NOT a second way to win under this condition -- the tower still has to
	## hold out the time.
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
## [constant NONE] and [constant CATCH_AND_SWAP] are implemented; the two in
## between are provisional names for provisional ideas and are not.
enum GhostBehaviour {
	## The body is parked out of the world and the prisoner is out of the round.
	## The rule the match shipped with, and still the control case every claim
	## about ghosts is compared against.
	NONE,
	## The prisoner stays in the world as a non-interacting observer. OPEN
	## QUESTION -- whether a dead prisoner watching is atmosphere or dead time.
	## NOT IMPLEMENTED.
	SPECTATOR,
	## The prisoner keeps running the track in a ghost state, still able to
	## reach the end, possibly counting for something less than an arrival. OPEN
	## QUESTION, and the one that most changes what a shot is worth. NOT
	## IMPLEMENTED.
	CONTINUE_LAP,
	## [b]CANON.[/b] The prisoner becomes a ghost: faster than the living,
	## unshootable, and chasing. Reaching a living prisoner takes their spot --
	## the caught player becomes the ghost and the ghost becomes living. A swap,
	## not a revive and not a kill, so the number of living prisoners is
	## unchanged by it and only the rifle ever lowers that number.
	##
	## This is the author's answer to the no-sit-out constraint: a shot player
	## never watches, they change role and immediately have something to do.
	## Every number it is made of lives in [GhostProfile]; see
	## [member ghost_profile].
	CATCH_AND_SWAP,
}

## The one-shot power every prisoner carries. [b]LIVE[/b], default NONE.
enum RunnerAbility {
	## No power. Today's game.
	NONE,
	## A static translucent sphere the rifle hits instead of anyone inside.
	BUBBLE_SHIELD,
	## A decoy body that runs straight ahead; hitting it converts nobody.
	HOLOGRAM,
	## The body freezes and ignores hits; released early by letting go.
	ARMOR_LOCK,
	## The body goes near-transparent; the AI guard sees it only within 25 m.
	ACTIVE_CAMO,
}

# --- The map ------------------------------------------------------------------

## Which arena the round is played in, by [member MapDefinition.id]. [b]LIVE.[/b]
##
## The map is a rule of the round by the test this file's header sets: change it
## and you are playing a different game. It is named rather than pointed at --
## a [StringName] and not a [PackedScene] -- for three reasons. A resource path
## in here would put the arena in the load graph of every rules variant the sweep
## writes; the id is what a settings file can legibly hold across a rename of the
## scene; and [MapCatalog] is then the single list of what exists, instead of
## every rules resource carrying its own opinion.
##
## An id naming no map falls back to [method MapCatalog.default_map] rather than
## failing -- see [method MapCatalog.scene_path_for] -- because the callers are a
## running match and an unattended sweep. An EMPTY id means "whatever arena the
## scene was authored with", which is what lets a bespoke test world stand.
@export var map_id: StringName = MapCatalog.DEFAULT_ID

# --- How a body moves ---------------------------------------------------------

## Which air-control preset every body in the match runs, by
## [member AirControlPreset.id]. [b]LIVE.[/b]
##
## [b]Why this is here at all, given the seam in this file's header.[/b] A
## [MovementProfile] is COMPONENT tuning and stays that way -- nothing on this
## resource carries a walk speed or a slide boost, and nothing should. What is a
## rule of the MATCH is WHICH profile the bodies run, exactly as
## [member ai_shooter_profile] is a rule about which shooter brain plays rather
## than about what a shooter brain is made of. The four presets differ ONLY in
## air control ([AirControlPreset] holds that by construction), so naming one
## here can never smuggle a retune of anything else in with it.
##
## [b]It applies to every body, human and bot alike.[/b] That is the point: a
## preset felt against opponents that move differently is not the preset being
## felt. See [method MatchController.get_air_control_profile].
##
## An id naming no preset falls back to [method AirControlCatalog.default_preset]
## rather than failing -- see [method AirControlCatalog.profile_for] -- because
## the callers are a running match and an unattended sweep. An EMPTY id means
## "whatever profile each body's scene carries", which is [member map_id]'s
## empty case exactly: it is what lets a bespoke harness world stand.
@export var air_control_id: StringName = AirControlCatalog.DEFAULT_ID

# --- The prisoners ------------------------------------------------------------

## How many prisoners run the round. [b]LIVE.[/b]
##
## Three is the shipped round and the number the arena's three clear channels
## were measured for. It is not a settled design answer: prisoner count against a
## single-shot rifle is the crudest difficulty dial the game has, and the
## relationship between count, reload and lap time is precisely the sort of thing
## this project exists to measure rather than argue about.
##
## They all run the same track; see [member track_radius].
@export_range(1, 32, 1, "or_greater") var prisoner_count: int = 3

## The one track every prisoner runs, in metres from the arena centre.
## [b]LIVE.[/b]
##
## There is one track and everybody is on it. A prisoner is not on a side and is
## not racing a handicap: same start, same path, same finish, and the only thing
## that separates two of them is how fast they cover it.
##
## Not a free number. Every deck of the shipped arena is an annulus from r=44 to
## r=60 with cover in two radial bands at r=47 and r=57, each piece sweeping
## roughly +/-0.9 m about its band, and every trap and pit shaft flush against
## the shoulder those bands end at. A [RingRunner] does not path around anything,
## so a track radius inside a cover band walks a 0.4 m capsule into a box and
## stands there for the rest of the round. 52.0 is the clear channel between the
## two bands, and it is what [member BotProfile.track_radius] ships at.
##
## [b]On a map with a [RingRoute] this is the FALLBACK, not the track.[/b] The
## arena says where each of its levels' lanes are and [MatchController] reads
## them from there; this is what a flat map with no route of its own is run on,
## and what the round card frames itself against when there is nothing better.
@export_range(20.0, 200.0, 0.1) var track_radius: float = 52.0

## Metres between neighbouring bodies across the WIDTH of the track at the start
## line. [b]LIVE.[/b]
##
## Everyone starts on one line, and two capsules cannot start in the same cubic
## metre: the depenetration solver resolves that by throwing both of them across
## the arena, which is a bug this project has already paid for twice. So the
## field is dealt out sideways along the start line -- across the track, never
## onto a track of its own -- and closes up again the moment they are running.
##
## The body capsule is 0.8 m across. 2.0 m is a body and a half of clearance,
## which is enough to place four of them inside a 6 m spread on a 25 m deck.
@export_range(1.0, 10.0, 0.1) var start_line_spacing_metres: float = 2.0

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

# --- The rifle ----------------------------------------------------------------

## The whole gun, as data. [b]LIVE when set, null = the weapon keeps its own.[/b]
##
## Point this at a [WeaponProfile] and a sweep arm gets the entire rifle by
## swapping one resource: hitscan or projectile, spread, tracer behaviour, the
## shape of the reload, a charged shot. Presets live in [code]scenes/weapon/[/code].
##
## [Rifle] adopts it INTO [member Rifle.profile] rather than holding it alongside,
## so [code]rifle.profile[/code] stays the single answer that [MatchController],
## [TowerShooter] and the feedback rig all read. Left null the weapon keeps
## whatever its scene assigned, which is exactly today's behaviour.
##
## Note the seam with [member base_reload_seconds] below: the match owns the
## reload DURATION and its floor, the weapon profile owns the gun's SHAPE. A
## profile swapped in here does not seize the clock the match runs on.
@export var weapon_profile: WeaponProfile

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

## What the shooter must do to win. [b]LIVE[/b], all three members implemented.
## Default [constant ShooterWinCondition.TOTAL_CONVERSION] is today's rule and
## the shipped one. See [enum ShooterWinCondition].
@export var shooter_win_condition: ShooterWinCondition = ShooterWinCondition.TOTAL_CONVERSION

## Prisoners the shooter must remove under
## [constant ShooterWinCondition.SHUTOUT_COUNT]. [b]LIVE[/b] under that
## condition, inert under every other. 0 means "unset", which is honest: no
## count has been chosen, and choosing one is what a sweep is for.
##
## An unset count is NOT read as [member prisoner_count]. A round asked for a
## shutout of nobody cannot be won and says so through [method validate], for
## the reason [enum ShooterWinCondition] gives: silently playing total
## conversion under a SHUTOUT_COUNT label would be the sweep measuring a rule it
## did not select. A count above [member prisoner_count] is unwinnable for the
## opposite reason and is reported the same way -- only the rifle lowers the
## living count, and it can lower it [member prisoner_count] times at most.
@export_range(0, 32, 1, "or_greater") var shutout_count: int = 0

## Seconds the shooter must hold out under
## [constant ShooterWinCondition.HOLD_DURATION]. [b]LIVE[/b] under that
## condition, inert under every other. 0.0 means unset, and an unset hold cannot
## be won -- see [member shutout_count] for why an unset number is refused
## rather than guessed at.
##
## Measured from the tick the round is armed and restarted with the round, so it
## is a per-round siege timer and not a match clock. Distinct from
## [member round_time_limit_seconds], which is still deferred: this one resolves
## to a shooter WIN, which is an outcome the match already has.
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
## Off, the match opens with [member opening_seat_index] already in the tower on
## turn one, which is what the game did before the race existed, what a harness
## measuring a single round wants, and what the Match tab's race skip selects for
## a player who is testing something and will not run the lap first.
@export var open_with_race: bool = true

## Who is already in the tower when a match does not open with a race.
## [b]LIVE[/b], default 0 = the first participant, which is the human whenever
## there is one.
##
## Read only while [member open_with_race] is false, and read exactly once, by
## [method MatchController.start_match]. It grants the seat the same way the race
## does -- the same [method MatchController.take_seat], the same turn one, the
## same reload, the same round armed after it -- so a match that skipped the race
## is a match whose race was won instantly by the named seat, and not a second
## kind of match.
##
## An index this match has no participant for is clamped rather than refused: the
## seat count depends on [member prisoner_count], the value can outlive a change
## to it, and a saved preference naming a bot who no longer exists should hand
## the tower to somebody rather than stop the game.
@export_range(0, 31, 1, "or_greater") var opening_seat_index: int = 0

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

# --- Ghosts -------------------------------------------------------------------

## What becomes of a prisoner the rifle finishes. [b]LIVE[/b], default
## [constant GhostBehaviour.NONE] = parked out of the world, which is the rule
## the match shipped with.
##
## The whole ghost design hangs off this one value, and while it is
## [constant GhostBehaviour.NONE] [member ghost_profile] is inert by definition.
## [constant GhostBehaviour.CATCH_AND_SWAP] is the canon mechanic; see
## [enum GhostBehaviour].
##
## The CODE default here is [constant GhostBehaviour.NONE] and the SHIPPED
## default in [code]resources/rules/default_match_rules.tres[/code] is
## [constant GhostBehaviour.CATCH_AND_SWAP]. That is not an oversight: a rule set
## built from nothing is the control case a harness compares against, and the
## rule set the game is played on is the author's ruling. A sweep arm that wants
## the mechanic asks for it; a player gets it.
@export var ghost_behaviour: GhostBehaviour = GhostBehaviour.NONE

## Every number a ghost is made of: pace, catch radius, grace, and whether a
## catch carries lap progress. [b]LIVE[/b] under
## [constant GhostBehaviour.CATCH_AND_SWAP], inert otherwise.
##
## Null means "no match opinion" and the round falls back to the shipped profile
## at [constant MatchController.DEFAULT_GHOST_PROFILE_PATH], exactly as
## [member ai_shooter_profile] falls back to the shipped shooter. A JSON sweep
## spec, which can only write strings, may instead set the metadata key
## [code]ghost_profile[/code] to a resource path -- see
## [method GhostProfile.resolve].
##
## The seam is the usual one. WHETHER a shot prisoner becomes a ghost is a rule
## of the round and lives above; WHAT a ghost is once it exists is a bundle of
## design numbers and lives in its own resource, so one file is what a sweep
## varies.
@export var ghost_profile: GhostProfile

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

# --- Runner powers ------------------------------------------------------------

## Which power every prisoner carries, if any. See [enum RunnerAbility].
@export var runner_ability: RunnerAbility = RunnerAbility.NONE

## Seconds after a power ends before it can be used again.
@export_range(0.0, 120.0, 0.5, "or_greater") var ability_cooldown_seconds: float = 20.0

## Seconds a power lasts once used.
@export_range(0.5, 60.0, 0.5, "or_greater") var ability_duration_seconds: float = 5.0

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
## participant, so a sweep that varies the seed cannot retune the shared
## [code].tres[/code] for whatever runs next in the same process.
@export var ai_shooter_profile: ShooterProfile

## The [RunnerProfile] an AI prisoner runs on, as [member ai_shooter_profile] is
## the guard's. [b]LIVE.[/b] Null = each runner keeps whatever profile its scene
## assigned.
##
## [method RunnerProfile.resolve] already looks for this property, so setting it
## here is all a sweep needs to vary how well a prisoner plays. Presets ship in
## [code]scenes/bot/[/code]: baseline (the old straight-line lap, kept as the
## control case), default, patient and reckless.
@export var ai_runner_profile: RunnerProfile

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

## How many players a match has: one in the tower and [member prisoner_count] on
## the ring.
##
## Derived rather than exported, because a round with fewer runners than
## [member prisoner_count] is a different round, and a match that cannot field
## one is not a match. The human is one of these when a match has a human; the
## rest are AI.
func get_participant_count() -> int:
	return maxi(prisoner_count, 1) + 1


## What the participant in seat [param index] is called, given whether the match
## has a human in it at all.
##
## Static, and here rather than in [MatchController], because a seat has to be
## NAMEABLE before a match exists: the Match tab offers the player a seat to hand
## the tower to while the only thing in the tree is a menu. The controller builds
## its roster from this, so the name on the settings screen and the name in the
## HUD are one string and cannot drift into two.
##
## Seat 0 is the human whenever there is one -- [MatchController] gives the human
## the first slot -- and every other seat is an AI, numbered by its own index so
## that "Runner 2" means the same body to the screen, the HUD and the log.
static func get_participant_name(index: int, has_human: bool) -> String:
	if has_human and index == 0:
		return "You"
	return "Runner %d" % index


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


## Display name of a [enum RunnerAbility] member.
static func runner_ability_title(value: int) -> String:
	match value:
		RunnerAbility.NONE:
			return "None"
		RunnerAbility.BUBBLE_SHIELD:
			return "Bubble Shield"
		RunnerAbility.HOLOGRAM:
			return "Hologram"
		RunnerAbility.ARMOR_LOCK:
			return "Armor Lock"
		RunnerAbility.ACTIVE_CAMO:
			return "Active Camo"
	return String(RunnerAbility.keys()[value])


## True when a shot prisoner becomes a ghost rather than leaving the round.
##
## The one place the enum comparison lives, so no caller grows a second idea of
## what "ghosts are on" means.
func has_ghosts() -> bool:
	return ghost_behaviour == GhostBehaviour.CATCH_AND_SWAP


## True when [member ghost_behaviour] is one the round actually implements. A
## round configured with an unimplemented one still runs -- the prisoner is
## simply parked, as under [constant GhostBehaviour.NONE] -- and says so once.
func is_ghost_behaviour_implemented() -> bool:
	return (
		ghost_behaviour == GhostBehaviour.NONE
		or ghost_behaviour == GhostBehaviour.CATCH_AND_SWAP
	)


## True when [member shooter_win_condition] is one the round actually implements.
## A round configured with an unimplemented condition still runs -- it just
## cannot be won by the shooter -- and says so once, loudly.
##
## All three members are implemented today, so this is true for every value the
## enum currently holds. It is written as a list of the three rather than as
## [code]true[/code] deliberately: a member added to [enum ShooterWinCondition]
## tomorrow is unimplemented until somebody teaches
## [method MatchController._check_shooter_win] about it, and this is what makes
## that day a warning instead of a round that quietly never ends.
func is_shooter_win_condition_implemented() -> bool:
	return (
		shooter_win_condition == ShooterWinCondition.TOTAL_CONVERSION
		or shooter_win_condition == ShooterWinCondition.SHUTOUT_COUNT
		or shooter_win_condition == ShooterWinCondition.HOLD_DURATION
	)


## Problems with this rule set, as human-readable lines. Empty means usable.
##
## Checks only what is objectively broken -- a round that cannot spawn or cannot
## be won -- and never second-guesses a design choice, because the whole point of
## this resource is that the design choices are the harness's to make.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if prisoner_count < 1:
		problems.append("prisoner_count is %d; a round needs at least one prisoner." % prisoner_count)
	if track_radius <= 0.0:
		problems.append("track_radius is %.1f; there is nowhere to put a prisoner." % track_radius)
	if not String(map_id).is_empty() and not MapCatalog.has(map_id):
		problems.append(
			"map_id is %s, which is in no catalog; the match will fall back to %s."
			% [map_id, MapCatalog.DEFAULT_ID]
		)
	if not String(air_control_id).is_empty() and not AirControlCatalog.has(air_control_id):
		problems.append(
			"air_control_id is %s, which is in no catalog; every body will fall back to %s."
			% [air_control_id, AirControlCatalog.DEFAULT_ID]
		)
	if not is_shooter_win_condition_implemented():
		problems.append(
			"shooter_win_condition is %s, which is declared but not implemented; the shooter cannot win this round."
			% String(ShooterWinCondition.keys()[shooter_win_condition])
		)
	if shooter_win_condition == ShooterWinCondition.SHUTOUT_COUNT and shutout_count <= 0:
		problems.append(
			"shooter_win_condition is SHUTOUT_COUNT but shutout_count is unset; the shooter cannot win this round."
		)
	if (
		shooter_win_condition == ShooterWinCondition.SHUTOUT_COUNT
		and shutout_count > maxi(prisoner_count, 1)
	):
		# Only the rifle lowers the living count and a round arms exactly
		# prisoner_count runners, so a shutout of more than that is a number no
		# round can reach -- with or without ghosts, since a catch is a swap and
		# not a conversion.
		problems.append(
			"shooter_win_condition is SHUTOUT_COUNT with shutout_count %d, which is more prisoners than the %d a round has; the shooter cannot win this round."
			% [shutout_count, maxi(prisoner_count, 1)]
		)
	if shooter_win_condition == ShooterWinCondition.HOLD_DURATION and hold_duration_seconds <= 0.0:
		problems.append(
			"shooter_win_condition is HOLD_DURATION but hold_duration_seconds is unset; the shooter cannot win this round."
		)
	if not is_ghost_behaviour_implemented():
		problems.append(
			"ghost_behaviour is %s, which is declared but not implemented; a shot prisoner will simply be parked."
			% String(GhostBehaviour.keys()[ghost_behaviour])
		)
	if reload_reduction_per_turn <= 0.0:
		# Not broken, but worth saying out loud: this is the only rule that
		# guarantees a match ends.
		problems.append(
			"reload_reduction_per_turn is 0.0; the tower never gets faster, so a match has no terminator."
		)
	return problems
