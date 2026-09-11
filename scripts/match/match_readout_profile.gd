class_name MatchReadoutProfile
extends Resource

## Every word and colour the match HUD's role readout is made of.
##
## Same rule as [MatchAnnouncementProfile], [FeedbackProfile] and
## [SpectatorProfile]: nothing a player READS may be hard-coded in the node that
## draws it. What the HUD says is a design decision with no obviously right
## answer, and this project settles those by editing a [Resource] and playing
## again.
##
## [b]What this is NOT[/b]
##
## It is not a rule. Nothing here is read by [MatchController], by [Rifle] or by
## a bot; no count, no win condition and no timer is decided here. It is the
## vocabulary a readout uses to describe rules that already exist, plus the
## colours it draws them in. Set [member enabled] false and the match is exactly
## the match it was, played without a readout.
##
## [b]Why the objective wordings live here and not in the HUD[/b]
##
## [MatchRules] can be swept: a round may be running
## [constant MatchRules.RunnerWinCondition.ALL_ARRIVALS] rather than first past
## the post, and a shooter may be playing a win condition that is declared but
## not implemented. A HUD that said "FIRST TO THE END TAKES THE TOWER" under
## either would be lying to the player about the game they are in, and a lying
## HUD is worse than no HUD. So the mapping from a rule to a sentence is a pure
## function on this resource -- [method shooter_objective],
## [method runner_objective], [method match_progress] -- which means a test can
## vary the rules and read the sentence back without owning a [MatchController],
## a viewport or a [Label].
##
## [b]Colour, and the red room[/b]
##
## The arena is lit by one red light above the tower and is deliberately dark.
## Two things follow, and both are decisions rather than taste:
##
## 1. Nothing important is drawn RED. Red text on red-lit concrete is the one
##    combination this arena can actually hide, and the reload countdown is the
##    single most important number in the guard's life.
## 2. Every colour here is near-full value against black. The scene pairs them
##    with a black outline and a dark backdrop, so the readout is legible over
##    the lit deck, the unlit deck and the sky alike.

## Kills the whole readout. The honest control for "is this better than the
## silence it replaced": false here and the HUD is a crosshair, a centre line
## and the handover banner, exactly as it was.
@export var enabled: bool = true

# --- What a player IS ---------------------------------------------------------

## The role line for whoever holds the tower.
@export var guard_role: String = "TOWER"

## The role line for a living prisoner on the ring.
@export var prisoner_role: String = "PRISONER"

## The role line for a ghost.
@export var ghost_role: String = "GHOST"

## The role line for a participant with nothing to play: a converted prisoner in
## a round with no ghosts, or a racer who fell and is out for the rest of the
## race. [MatchDeathScreen] says why; this only says what.
@export var spectator_role: String = "WATCHING"

## Prefixes the seat holder's own turn count on the role line. The turn count is
## on the role line rather than buried below it because the reload shortens with
## every turn, so it is the number that says how dangerous this tower is.
@export var turn_word: String = "TURN"

# --- The guard's one number ---------------------------------------------------

## The rifle will answer the trigger.
@export var ready_text: String = "READY"

## Prefixes the seconds until the rifle will answer the trigger.
@export var reload_word: String = "RELOAD"

## Decimals on the live reload countdown. One, because two read as a debug
## print and none reads as having stalled on the last second.
@export_range(0, 3, 1) var reload_decimals: int = 1

# --- The prisoner's one number ------------------------------------------------

## Follows the metres of ring left to run.
@export var distance_suffix: String = "M TO THE END"

## Shown instead of a distance once this participant's lap has been scored.
@export var arrived_text: String = "AT THE END"

## Shown instead of a distance when there is no lap to measure -- before a round
## is armed, or for a participant who is not running one.
@export var no_distance_text: String = "--"

# --- The ghost's orders -------------------------------------------------------

## What a ghost is FOR, in the one line that replaces their distance readout.
##
## The whole point of the line: a ghost's job is not the job they had a second
## ago. They are no longer running a lap -- the lap they were running has stopped
## being scored -- and a HUD that went on counting metres for them would be
## describing a game they are no longer playing.
@export var ghost_orders: String = "CATCH A PRISONER"

## The rest of the sentence: what a ghost gets in exchange. Composed with the
## live numbers off [GhostProfile] rather than restated here, so a swept ghost
## speed is the speed the readout claims.
@export var ghost_take_place_text: String = "TAKE THEIR PLACE"

## Follows the ghost's speed multiplier, e.g. "3.0x FASTER".
@export var ghost_speed_suffix: String = "x FASTER"

## Shown for a ghost while [member GhostProfile.shootable] is false.
@export var ghost_unshootable_text: String = "CANNOT BE SHOT"

# --- Everybody's shared number ------------------------------------------------

## Prefixes "n / m" living prisoners. The one count both roles read, from
## opposite ends: it is the guard's progress and the prisoners' strength.
@export var prisoners_word: String = "PRISONERS"

# --- The rules in play, said out loud -----------------------------------------

## [constant MatchRules.ShooterWinCondition.TOTAL_CONVERSION].
@export var total_conversion_objective: String = "CONVERT THEM ALL"

## [constant MatchRules.ShooterWinCondition.SHUTOUT_COUNT]. Takes
## [member MatchRules.shutout_count], because the count IS the rule -- "convert
## some of them" is not an objective anybody can play to.
@export var shutout_objective: String = "CONVERT %d OF THEM"

## [constant MatchRules.ShooterWinCondition.HOLD_DURATION]. Takes
## [member MatchRules.hold_duration_seconds], rounded to whole seconds: the HUD
## says what the round is FOR, and the clock ticking down is
## [method MatchController.get_hold_remaining_seconds].
@export var hold_duration_objective: String = "HOLD OUT FOR %d SECONDS"

## What the tower is playing for under a win condition [MatchRules] declares but
## does not implement. Said plainly, because the alternative is a readout that
## quietly describes total conversion while the round refuses to end.
@export var unwinnable_objective: String = "THIS TOWER CANNOT WIN THE ROUND"

## [constant MatchRules.RunnerWinCondition.FIRST_ARRIVAL].
@export var first_arrival_objective: String = "FIRST TO THE END TAKES THE TOWER"

## [constant MatchRules.RunnerWinCondition.ALL_ARRIVALS].
@export var all_arrivals_objective: String = "ALL OF YOU MUST REACH THE END"

## The opening race, which has no shooter and no win condition yet.
@export var race_objective: String = "RACE FOR THE TOWER"

## Match progress when [member MatchRules.rounds_to_win_match] is 1 -- the
## shipped rule. There is no score to show, so it says what winning is instead.
@export var final_round_text: String = "HOLD THIS ROUND TO WIN THE MATCH"

## Prefixes "n / m" round wins when the match takes more than one.
@export var round_wins_word: String = "ROUND WINS"

# --- Context ------------------------------------------------------------------

## Shown where the seat holder's name would go during the opening race.
@export var empty_tower_text: String = "TOWER EMPTY"

## Follows the length of the reload the tower is currently running on. Shown to
## the RUNNERS: how long the tower's silence lasts is a property of the tower
## they are entitled to know, where the live countdown is not.
@export var reload_length_suffix: String = "S RELOAD"

## The separator between the parts of a composed line. A middle dot reads as one
## line at a glance where a comma reads as a list.
@export var separator: String = "  ·  "

## Show the restart key at the bottom of the screen.
@export var show_restart_hint: bool = true

## What the restart key hint says.
@export var restart_hint: String = "[R] restart match"

# --- Colour -------------------------------------------------------------------

## The rifle is ready. Cold white-green: the one state the guard may act on.
@export var ready_color: Color = Color(0.72, 1.0, 0.78, 1.0)

## The rifle is reloading. Amber rather than red -- see the class docs: this
## arena's only light is red, and this is the number that must never be lost.
@export var reloading_color: Color = Color(1.0, 0.78, 0.32, 1.0)

## A living prisoner's distance readout.
@export var prisoner_color: Color = Color(0.94, 0.96, 1.0, 1.0)

## A ghost's orders. Cyan, which nothing in a red-lit arena competes with, and
## which matches nothing a prisoner ever sees on their own readout.
@export var ghost_color: Color = Color(0.55, 0.94, 1.0, 1.0)

## The role line and the shared counts.
@export var neutral_color: Color = Color(0.96, 0.96, 0.96, 1.0)

## Context: things that are true but that nobody should be reading mid-run.
@export var dim_color: Color = Color(0.74, 0.76, 0.80, 1.0)


## What the tower is playing for under [param rules], as a sentence.
##
## One sentence per implemented condition, and honest about the rest rather than
## silently describing the one it is not playing. Two kinds of round get
## [member unwinnable_objective]: a condition this build does not implement, and
## an implemented one handed a number it cannot be won with -- an unset shutout
## count or an unset hold -- because from the player's chair those are the same
## round. See [method MatchRules.is_shooter_win_condition_implemented] and
## [method MatchRules.validate].
func shooter_objective(rules: MatchRules) -> String:
	if rules == null:
		return ""
	if not rules.is_shooter_win_condition_implemented():
		return unwinnable_objective
	match rules.shooter_win_condition:
		MatchRules.ShooterWinCondition.SHUTOUT_COUNT:
			if rules.shutout_count <= 0:
				return unwinnable_objective
			return shutout_objective % rules.shutout_count
		MatchRules.ShooterWinCondition.HOLD_DURATION:
			if rules.hold_duration_seconds <= 0.0:
				return unwinnable_objective
			return hold_duration_objective % int(roundf(rules.hold_duration_seconds))
	return total_conversion_objective


## What the prisoners are playing for under [param rules], as a sentence. Both
## members of [enum MatchRules.RunnerWinCondition] are implemented, so both get a
## true sentence.
func runner_objective(rules: MatchRules) -> String:
	if rules == null:
		return ""
	if rules.runner_win_condition == MatchRules.RunnerWinCondition.ALL_ARRIVALS:
		return all_arrivals_objective
	return first_arrival_objective


## How close [param rounds_won] is to taking the match under [param rules].
##
## [member MatchRules.rounds_to_win_match] is 1 on the shipped rules, where a
## score of "0 / 1" is noise; above 1 the tower is a thing to defend repeatedly
## and the score is the whole story.
func match_progress(rules: MatchRules, rounds_won: int) -> String:
	if rules == null:
		return ""
	var needed: int = maxi(rules.rounds_to_win_match, 1)
	if needed <= 1:
		return final_round_text
	return "%s %d / %d" % [round_wins_word, maxi(rounds_won, 0), needed]


## "PRISONERS n / m", the one count both roles read.
func prisoner_count_text(remaining: int, total: int) -> String:
	return "%s %d / %d" % [prisoners_word, maxi(remaining, 0), maxi(total, 0)]


## Join the non-empty [param parts] with [member separator].
func join(parts: PackedStringArray) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for part: String in parts:
		if not part.is_empty():
			kept.append(part)
	return separator.join(kept)
