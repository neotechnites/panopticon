class_name CatchProfile
extends Resource

## Every tunable number for THE CATCH -- the ghost taking a living prisoner's
## spot -- from both sides of it.
##
## Same rule as [FeedbackProfile], [SpectatorProfile] and [SeatHandoverProfile]:
## nothing about how the catch reads may be hard-coded in the component that
## draws it. Units are seconds and fractions of the screen, as the field names
## say.
##
## [b]Why this is not more fields on [FeedbackProfile][/b]
##
## [FeedbackProfile] is tuned to one register and says so in its own header:
## being shot is [i]"a baseball from a pro pitcher: instant, violent, over"[/i],
## and every duration in it is under a third of a second because of that. A
## catch is a different event with a different length -- it lands inside a three
## second respawn hold and is watched from a spectator camera that arrives
## partway through it -- and folding it into that file would mean either
## retuning the shot to make room or writing numbers into it that contradict its
## own stated register. The camera RIG is shared (see [FxCameraKick]); the
## numbers are not.
##
## [b]The two sides are deliberately asymmetric[/b]
##
## [codeblock]
## the taker   opens  -- thick at once, retreating outward, gone in a third of
##                       a second. A reward: the view is handed back to you.
## the caught  closes -- thin, growing inward, HELD, then released over half a
##                       second. A death: something has got hold of you.
## [/codeblock]
##
## Read them as one gesture running in opposite directions, because that is what
## makes the pair legible without a word of text on screen.

## Kills the whole layer. The honest control for "is this better than the
## silence it replaced": false here and a catch is exactly as mute as it was
## before any of this existed. No match rule reads this, and nothing here can
## change who ends up where.
@export var enabled: bool = true

# --- Being caught: this is a death, and not the rifle's ------------------------
#
# The shot's flash is white, full-screen, and finished in 110 ms. None of those
# three is true here, on purpose. This one is the OTHER player's colour, it is a
# frame rather than a fill, and it is still on screen when the spectator camera
# pulls out off the body -- so the thing that killed you is legible for as long
# as it takes to understand that you are dead.

## Draw anything at all for the player who was caught.
@export var caught_enabled: bool = true

## How long the frame takes to grow from nothing to its full thickness.
##
## Short, but NOT instant, and that is the whole difference from being shot: a
## rifle round is already over when you notice it, and a pair of hands closes.
@export_range(0.0, 2.0, 0.01) var caught_close_seconds: float = 0.16

## How long the closed frame is held at full strength before it starts to go.
##
## [FxSpectatorView] takes the view off the body about a third of a second after
## a death ([member SpectatorProfile.enter_delay_seconds]), so a hold shorter
## than that would finish before the player had been shown anything but their
## own boots. This is what carries the event across that cut.
@export_range(0.0, 4.0, 0.01) var caught_hold_seconds: float = 0.34

## How long the frame takes to fade out afterwards.
##
## Generous next to anything in [FeedbackProfile]. The whole reaction lands
## inside a three second hold with nothing else competing for the screen, so
## there is room, and a slow release is the part that reads as being held rather
## than being struck.
@export_range(0.0, 4.0, 0.01) var caught_fade_seconds: float = 0.50

## Thickness of the closed frame, as a fraction of the SHORTER screen axis.
##
## A fraction rather than pixels so the effect is the same gesture at 1600x900
## and on a 4K display. Thick enough to be unmistakably a colour, thin enough
## that the ring, the tower and the deck are all still visible through the
## middle -- a player being converted is entitled to see what the arena did with
## them.
@export_range(0.0, 0.5, 0.005) var caught_thickness_fraction: float = 0.130

## Peak opacity of the frame. Multiplied into the catching ghost's own runner
## colour, whose alpha is deliberately ignored -- see
## [method FxCatchReaction.get_color].
@export_range(0.0, 1.0, 0.01) var caught_alpha: float = 0.80

## Shape of the close. Below 1.0 the frame is most of the way in on the first
## frame and settles the rest of the way, which reads as a grab; above 1.0 it
## creeps, which reads as fog.
@export_range(0.1, 8.0, 0.05) var caught_close_exponent: float = 0.55

## Shape of the release. Squared, so it lets go quickly and then trails.
@export_range(0.1, 8.0, 0.1) var caught_fade_exponent: float = 2.0

## Weight of the camera whip, as a multiple of the shot's own
## ([member FeedbackProfile.impact_pitch_degrees] and its neighbours).
##
## Deliberately well under 1.0. A rifle round is the loudest thing that can
## happen to the camera and must stay so; a catch turns the head, it does not
## snap it. The direction is the direction the ghost was reaching in, so the
## view is turned towards where it came from.
@export_range(0.0, 3.0, 0.05) var caught_whip_scale: float = 0.50

## Weight of the backwards drag, as a multiple of
## [member FeedbackProfile.confirm_punch_metres].
##
## The channel a hitmarker uses, borrowed: it is translation only and it is
## backwards, which is exactly what being hauled off your feet is. The rifle
## never produces one of these on the victim's camera, so a pull with no muzzle
## flash and no white frame cannot be mistaken for a shot.
@export_range(0.0, 8.0, 0.05) var caught_drag_scale: float = 2.20

# --- Making the catch: you took a life back -----------------------------------
#
# The ghost is the only role in PANOPTICON that can improve its own position,
# and this is the moment it does. It gets the kill-confirm vocabulary -- the
# punch a hitmarker rides on -- because that is already the game's word for "I
# got one", and a second word for the same feeling would be a worse game.

## Draw anything at all for the ghost who made the catch.
@export var take_enabled: bool = true

## How long the burst takes to retreat off the edges of the screen.
##
## Short and rising: the player is alive again, at running pace, holding a spot
## somebody else ran for, and the one thing they now need is an unobstructed
## view of the ring.
@export_range(0.0, 2.0, 0.01) var take_open_seconds: float = 0.30

## Thickness the burst starts at, as a fraction of the shorter screen axis.
@export_range(0.0, 0.5, 0.005) var take_thickness_fraction: float = 0.085

## Peak opacity of the burst, in the caught prisoner's own runner colour.
##
## Lower than [member caught_alpha]. This is good news and it does not need to
## interrupt anybody.
@export_range(0.0, 1.0, 0.01) var take_alpha: float = 0.55

## Shape of the retreat. Above 1.0 it leaves fast and thins out, which reads as
## a release.
@export_range(0.1, 8.0, 0.05) var take_open_exponent: float = 1.60

## Weight of the confirm punch, as a multiple of
## [member FeedbackProfile.confirm_punch_metres].
##
## Bigger than a hitmarker's 1.0: a shot is one hit of several, and a catch is
## a whole life taken back off the round in one movement.
@export_range(0.0, 8.0, 0.05) var take_punch_scale: float = 2.60


## Seconds the caught player's frame is on screen for in total, or 0.0 when that
## half is switched off. The one place both flags are consulted.
func get_caught_seconds() -> float:
	if not enabled or not caught_enabled:
		return 0.0
	return (
		maxf(caught_close_seconds, 0.0)
		+ maxf(caught_hold_seconds, 0.0)
		+ maxf(caught_fade_seconds, 0.0)
	)


## Seconds the taker's burst is on screen for, or 0.0 when that half is switched
## off.
func get_take_seconds() -> float:
	if not enabled or not take_enabled:
		return 0.0
	return maxf(take_open_seconds, 0.0)
