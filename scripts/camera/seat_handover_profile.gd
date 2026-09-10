class_name SeatHandoverProfile
extends Resource

## Every number the seat handover camera is made of.
##
## Same rule as [SpectatorProfile], [FeedbackProfile] and [MovementProfile]:
## nothing about how the move behaves may be hard-coded in the node, because the
## question this file answers -- what a change of tower should FEEL like -- has
## no obviously right answer and has to be tuned by watching it.
##
## [b]The two moves are not the same move[/b]
##
## Taking the tower is the reward the whole match is played for, and the camera
## should take its time saying so. Losing it is a reset the player wants to be
## finished with, so they can get on with running. That asymmetry is the reason
## there are two durations here and not one -- and, now, the reason there are two
## SWITCHES here and not one. Both ship off; see [member fly_to_tower].

## Turn the whole handover off and let the seat change cut, exactly as it did
## before this node existed. The honest control for "is this better than what it
## replaced".
##
## [b]Leave this ON even though both flights below ship OFF.[/b] The node still
## does one thing on a cut seat change that nothing else does:
## [member reset_zoom_on_handover]. Switching the whole file off to get a cut
## takes that fix with it.
@export var enabled: bool = true

# --- Which seat changes are flown at all --------------------------------------

## Fly the camera when the player TAKES the tower.
##
## [b]Off, on Ryan's ruling, and it is a ruling about the round card rather than
## about this flight.[/b] His objection was to "the camera jumping from the
## middle to the start when you loose" -- see [member fly_to_ring] -- and the
## answer to that was a between-rounds transition screen
## ([RoundTransitionScreen]). That screen is raised on
## [signal MatchController.round_started], and EVERY seat change restarts the
## round, so the card now covers every handover in the match including this one.
## A flight underneath it would be a second of camera work drawn behind an opaque
## screen.
##
## The flight is not deleted, because it is the better answer the day the round
## card is switched off: turn this on and taking the tower is flown again,
## exactly as it was, with no other edit anywhere.
@export var fly_to_tower: bool = false

## Fly the camera when the player is put back on the RING -- because they lost
## the tower, or because somebody else's seat change restarted the round around
## them.
##
## [b]Off because Ryan asked for it in those words:[/b] "i dont like the camera
## jumping from the middle to the start when you loose, i dont mind that just
## being a jump cut." So this one cuts. It is the case the flight was worst for
## anyway -- losing the tower is a reset the player wants to be finished with,
## and 0.73 s of it was 0.73 s of not running while three other prisoners were.
@export var fly_to_ring: bool = false

# --- The beat -----------------------------------------------------------------

## Seconds the camera holds still at the pose it was in when the seat changed,
## before it starts travelling.
##
## [b]This is the part that makes it read as an event.[/b] The seat change
## happens the instant a runner crosses the line, and [method
## MatchController.start_round] teleports every body in the match on the same
## tick. Without a beat, the move starts before the player has registered that
## anything happened and reads as a camera glitch. Held first, it reads as the
## match stopping to look at you.
@export_range(0.0, 1.5, 0.01) var hold_seconds: float = 0.18

# --- The travel ---------------------------------------------------------------

## Seconds to fly from where the player was to the tower, when the player is the
## one who has just taken it. Read only when [member fly_to_tower] is on.
##
## The slower of the two on purpose: this is the arrival, the camera is rising
## over the ring towards the thing everyone else is about to be shot from, and
## there is nothing to rush back to -- the round has not armed a runner who can
## reach the line in under a second.
@export_range(0.05, 3.0, 0.01) var to_tower_seconds: float = 0.85

## Seconds to fly from where the player was to the start line, when the player
## has lost the tower or is simply being reset by somebody else's seat change.
## Read only when [member fly_to_ring] is on.
##
## Shorter, because being put back on the ring is not a moment, it is the price
## of one -- and every one of these seconds is a second the player is not
## running while three other prisoners are.
@export_range(0.05, 3.0, 0.01) var to_ring_seconds: float = 0.55

## Metres the camera lifts above the straight line between the two poses, at the
## midpoint of the travel.
##
## A straight interpolation between two eye-height poses skims the deck and
## clips through the ring's cover for most of its length, which looks like a
## bug. Arcing over it also happens to be the shot the game is about: for half a
## second the player is looking down on the ring from above, which is the
## tower's own point of view whether they just won it or just lost it.
@export_range(0.0, 60.0, 0.5) var arc_height_metres: float = 6.0

## How much the travel is eased, from 0.0 (constant rate) to 1.0 (smoothstep:
## it leaves and arrives gently and covers the middle fast).
##
## The same shaping [WeaponOptic] uses, for the same reason: a camera that
## lurches into motion and stops dead reads as a teleport with extra steps. At
## 1.0 the move has weight.
@export_range(0.0, 1.0, 0.05) var smoothing: float = 1.0

# --- The lens -----------------------------------------------------------------

## Degrees the field of view widens by at the midpoint of the travel, on top of
## whatever the player's display FOV is.
##
## Free speed. The camera is already moving tens of metres in under a second;
## widening slightly through the middle and closing again on arrival sells that
## as travel rather than as a dissolve, and costs one sine.
@export_range(0.0, 40.0, 0.5) var fov_surge_degrees: float = 8.0

## Metres the player's eye has to have actually moved for the seat change to be
## worth carrying.
##
## [b]Not every seat change moves the player.[/b] A shooter who converts the
## whole field defends the tower and takes the seat again -- see
## [method MatchController._award_round_to_shooter] -- which restarts the round
## around them and puts every runner back on the line, but leaves the defender
## standing exactly where they were. Flying a camera from a pose to itself is a
## second of held breath for nothing, so the handover measures the distance on
## its first frame, once the placement has actually happened, and cancels
## silently if the answer is "nowhere".
##
## A couple of metres, so a body that merely settles onto the deck under it does
## not read as travel.
@export_range(0.0, 20.0, 0.1) var minimum_travel_metres: float = 2.0

# --- What the handover clears -------------------------------------------------

## Drop the player's zoom to hipfire when the seat changes.
##
## [b]A fix, not a flourish.[/b] Nothing else in the game resets the optic on a
## seat change, so a player who lost the tower mid-shot began their next lap
## looking down a 2.5x scope at the inside of the start pad, and a player who
## took it arrived already scoped at nothing. Both are states the player never
## asked for and would have to notice before they could undo. The handover is
## the one moment where clearing it is invisible, because the view is somewhere
## else entirely.
@export var reset_zoom_on_handover: bool = true


## Whether a handover in this direction is flown at all.
##
## [param to_tower] is true when the player has just taken the seat. The one
## place either switch is consulted, so "does this seat change cut" has a single
## answer rather than one per caller.
func flies(to_tower: bool) -> bool:
	if not enabled:
		return false
	return fly_to_tower if to_tower else fly_to_ring
