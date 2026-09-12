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

## Hit points. Seeded from [member MatchRules.guard_health] in the tower and from
## [member MatchRules.finisher_health] when [member is_finisher] is set; spent
## one per hit, and only the hit that takes it to zero kills.
var health: int = 1

## True while this participant has reached the end and carries a rifle of their
## own, hunting the guard. Still a prisoner -- [member is_running] stays true, so
## the guard may shoot them -- and armed until one of the two is dead.
var is_finisher: bool = false

## Seconds before this participant may shove again, counting down. See
## [member MatchRules.shove_cooldown_seconds].
var shove_cooldown_remaining: float = 0.0

## The shove button's level last tick, so one hold is one shove.
var shove_was_pressed: bool = false

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
##
## [b]It is SET then and it starts RUNNING when the body lands[/b], which are not
## the same tick. [method MatchController._tick_ghosts] skips a ghost that is
## still on its respawn hold or still inside its placement settle, so the clock
## starts when the body is back in the world. Ticking it any earlier would spend
## grace on a frozen body and leave a freshly landed ghost catchable sooner than
## the number says -- which is exactly one physics tick of difference, and
## exactly the kind of thing that is never noticed until it oscillates.
var ghost_grace_remaining: float = 0.0

## Seconds this participant's body must stand frozen where it died before the
## match puts it back on the start line, counting down.
##
## Set from [member GhostProfile.respawn_delay_seconds] on the tick a
## participant is killed, by any of the four routes that can kill one -- shot,
## trapped, fallen, or a ghost a hazard has to return. Non-zero means the body
## is being held by [method MatchController._hold_body] and has not yet been
## moved: it is off every collision layer, is not being stepped, and
## [method MatchController._tick_ghosts] skips it, so it can neither catch nor
## be caught nor be shot nor fall while this is running.
##
## Cleared by [method MatchController._hold_body], so any other placement --
## a round arming, a seat change, a catch -- cancels a pending respawn rather
## than letting it fire into a round that has moved on.
var respawn_hold_remaining: float = 0.0

## Physics frames this participant's body must stay inert before the match gives
## it back its collision, counting down.
##
## Non-zero only while a ghost is being put back on the start line -- see
## [method MatchController._place_ghost_at_start]. Every other placement in a
## match happens when a round is armed and is woken by the controller's own
## settle; a ghost is made in the middle of one and needs a clock of its own.
var ghost_settle_frames: int = 0

## This participant's own body colour for the whole match: the [RunnerPalette]
## entry [method MatchController._assign_runner_color] deals it at [member index],
## painted on before anything else touches the body. Everything that is not this
## participant's own colour -- a ghost's translucency, the guard's grey -- is a
## temporary repaint, and this is what [method MatchController._tint_body] takes
## it back to. Null until the participant has been assigned one.
var home_body_material: Material = null

## Whether [member home_body_material] has been read off the body yet. A
## separate flag because the authored material may legitimately BE null, and
## restoring null is then the correct thing to do rather than a no-op.
var home_material_read: bool = false

## Where and which way the body was standing the instant it was last killed --
## shot, trapped, or fallen. Snapshotted by [method MatchController._park_body]
## and [method MatchController._place_ghost_at_start] before either moves the
## body, so [FxSpectatorView] has a fixed spot to anchor on rather than reading
## a body that may already be parked or back on the start line.
var death_position: Vector3 = Vector3.ZERO
var death_facing: Vector3 = Vector3.FORWARD

## How this participant was last taken. Written by [MatchController] on the two
## paths that take one: the rifle, and a hazard.
enum DeathCause { SHOT, LAVA, FELL }

var death_cause: DeathCause = DeathCause.SHOT


func is_human() -> bool:
	return kind == Kind.HUMAN


## Zero-based turn index for [method MatchRules.get_reload_seconds_for_turn].
func get_turn_index() -> int:
	return maxi(turns_in_tower - 1, 0)


## What the participant is doing right now, for the HUD and for logs.
func get_role_name() -> String:
	if is_shooter:
		return "TOWER"
	if is_finisher:
		return "HUNTING"
	if is_running:
		return "RUNNING"
	if is_ghost:
		return "GHOST"
	return "CONVERTED"


func describe() -> String:
	return "%s (%s, turns %d)" % [display_name, get_role_name(), turns_in_tower]
