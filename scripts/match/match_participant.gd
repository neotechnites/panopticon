class_name MatchParticipant
extends RefCounted

## One player in a match, for the whole match, whoever they happen to be today.
##
## [b]Why this exists[/b]
##
## The seat in the tower is a ROLE, not a body and not a scene. A match is many
## rounds; across them the tower passes from player to player, and the thing that
## has to survive that pass is the player's IDENTITY -- their turn count, their
## lives, their body, whether they are the human. If the shooter were "the node
## called Player" and a runner were "a RingRunner in the live list", there would
## be no way to say "the same player took the tower again" and therefore no way
## to implement the terminator, which is defined entirely in terms of a player's
## own history.
##
## So [MatchController] deals in participants. A participant owns a body for the
## life of the match; what changes between rounds is [member is_shooter], where
## the body is standing, and which of its brains is switched on.
##
## [b]Human and AI are the same thing here[/b]
##
## The only field that distinguishes them is [member is_human], and it is read
## for exactly two purposes: whether the mouse may pull the trigger, and what to
## call the participant in the HUD. Everything else -- taking the seat, running
## a lap, being converted, winning the match -- goes through the identical code
## path. That is the requirement the design states plainly ("the seat must be
## able to pass to an AI participant"), and the cheapest way to keep it true is
## to give the two kinds one representation.

## Where this participant's intent comes from. Cosmetic and permissions only:
## no rule of the match branches on it.
enum Kind {
	## The player at the keyboard. At most one per match, and there may be none.
	HUMAN,
	## A bot body driven by a [RingRunner] while it runs.
	AI,
}

## Position in [method MatchController.get_participants]. Stable for the whole
## match, and the tiebreaker that keeps a dead heat on the start line and at the
## finish deterministic rather than a draw.
var index: int = 0

## What the HUD calls this participant.
var display_name: String = ""

var kind: Kind = Kind.AI

## The body this participant runs and shoots from, for the whole match. Never
## freed between rounds: a converted runner is parked, not destroyed, because
## the round restarts the moment the seat changes and they will be back on the
## ring in the same frame.
var body: PlayerController = null

## The lap-running brain, for an AI participant. Null for the human, who has one
## already and it is sitting at the keyboard.
##
## Switched off while this participant holds the seat -- a shooter does not run
## laps -- and reconfigured onto the track at the start of every round. See
## [member tower_brain] for what drives the body instead.
var brain: RingRunner = null

## The tower-playing brain, for an AI participant. Null for the human, whose
## trigger is a mouse, and null for an AI that has not yet held the seat -- it is
## built on the first turn in the tower and then kept for the life of the match.
##
## The other half of [member brain]. A participant owns two brains and exactly
## one of them is switched on at a time: [RingRunner] while they run the ring,
## [TowerShooter] while they hold the seat, neither while they are converted or
## while the opening race decides who the shooter is. Which one is running is
## the ONLY difference between a bot on the track and the same bot in the tower --
## the body, the head, the camera and the optic are the same ones either way,
## which is what makes the seat a role rather than a scene.
var tower_brain: TowerShooter = null

## Arc progress round the ring, for scoring. Every participant has one, human
## and AI alike, and it is the ONLY thing that says who reached the end: the
## race is only a race if all the racers are judged by one clock.
var tracker: MatchLapTracker = null

## Turns spent in the tower so far this match, counting the current one.
##
## Zero-based turn INDEX (this minus one) is what
## [method MatchRules.get_reload_seconds_for_turn] wants, so the first turn is
## always the base reload. Whether losing the seat resets this is
## [member MatchRules.turn_count_resets_on_seat_loss]; the shipped answer is that
## it does not.
var turns_in_tower: int = 0

## Rounds won from the tower. [member MatchRules.rounds_to_win_match] of these
## and the match is over.
var rounds_won: int = 0

## True while this participant is the shooter.
var is_shooter: bool = false

## True while this participant is a runner who has not yet been converted. False
## for the shooter, and false for a runner the rifle has taken out of the round.
var is_running: bool = false

## Rifle hits left before conversion, from [member MatchRules.prisoner_lives].
## Reseeded at the start of every round.
var lives: int = 1

## The body's collision layer and mask as authored, kept so that parking a
## converted runner out of the world can be undone exactly rather than
## approximately.
var home_collision_layer: int = 1
var home_collision_mask: int = 1

## True while this participant is a GHOST: shot out of the round under
## [constant MatchRules.GhostBehaviour.CATCH_AND_SWAP], faster than the living,
## unshootable, and chasing a living prisoner to take their spot.
##
## Mutually exclusive with [member is_running] and [member is_shooter] -- a
## ghost is not a legitimate target and cannot arrive, so nothing that counts
## runners counts them. It is a THIRD role rather than a flag on the second: a
## round has a tower, prisoners and ghosts in it, and every one of them plays for
## themselves.
var is_ghost: bool = false

## Seconds this ghost must wait before it may catch anybody, counting down.
##
## Set from [member GhostProfile.catch_grace_seconds] on the tick a participant
## becomes a ghost, by either route. Without it a swap oscillates: the new ghost
## is left standing inside the new prisoner's catch radius and takes them
## straight back, sixty times a second, forever.
var ghost_grace_remaining: float = 0.0

## The body mesh's material as authored, kept so that a ghost's colour can be
## taken back off exactly rather than approximately. Null until the first time
## this participant is tinted.
var home_body_material: Material = null

## Whether [member home_body_material] has been read off the body yet. A
## separate flag because the authored material may legitimately BE null, and
## restoring null is then the correct thing to do rather than a no-op.
var home_material_read: bool = false


func is_human() -> bool:
	return kind == Kind.HUMAN


## Zero-based turn index for [method MatchRules.get_reload_seconds_for_turn].
func get_turn_index() -> int:
	return maxi(turns_in_tower - 1, 0)


## What the participant is doing right now, for the HUD and for logs.
func get_role_name() -> String:
	if is_shooter:
		return "TOWER"
	if is_running:
		return "RUNNING"
	if is_ghost:
		return "GHOST"
	return "CONVERTED"


func describe() -> String:
	return "%s (%s, turns %d)" % [display_name, get_role_name(), turns_in_tower]
