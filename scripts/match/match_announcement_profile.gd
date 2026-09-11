class_name MatchAnnouncementProfile
extends Resource

## Every number the match's three announcements are made of: the tower changing
## hands, the round turning over, and the match being won.
##
## Same rule as [FeedbackProfile] and [SpectatorProfile]: nothing about how long
## an announcement stays up may be hard-coded in the component that shows it.
## Both of these are pacing decisions with no obviously right answer, and pacing
## is exactly the kind of question this project settles by editing a [Resource]
## and playing again rather than by editing a script.
##
## [b]One resource, three consumers.[/b] [MatchHud] shows the handover banner,
## [RoundTransitionScreen] shows the round card and [MatchResultScreen] shows the
## win beat. They are separate nodes on separate layers with separate lifetimes,
## but they are one design question -- how long does PANOPTICON hold the player's
## attention on an event -- so they are tuned from one file. Both fall back on the defaults written here when the export is
## left unset, so a scene that has not been wired up is under-decorated rather
## than broken.
##
## Units are seconds throughout, as the field names say.

## Kills all three announcements. The honest control for "is this better than the
## silence it replaced": false here and the match behaves exactly as it did
## before any of this existed. No match rule reads this, and nothing here can
## change who won.
@export var enabled: bool = true

# --- The handover: the tower changes hands ------------------------------------

## Show a banner when the seat changes hands.
@export var handover_enabled: bool = true

## How long the handover banner stays up, fade included.
##
## The seat changes at the moment a round restarts, so the player is being put
## back on the start line while this is on screen and is about to need the whole
## view. Long enough to read a name at a glance and no longer.
@export_range(0.2, 10.0, 0.1) var handover_seconds: float = 2.6

## How much of [member handover_seconds] is spent fading out.
##
## Non-zero on purpose: a banner that vanishes between two frames reads as a
## glitch, and one that fades reads as having finished saying something. Clamped
## against the hold at read time, so a fade longer than the banner's whole life
## is harmless rather than a negative alpha.
@export_range(0.0, 4.0, 0.05) var handover_fade_seconds: float = 0.7

# --- The round card: a round turns over ---------------------------------------

## Show a card between rounds.
##
## [b]What it is for.[/b] A round used to end and the next one begin on the same
## tick, with every body in the match teleported and nothing said. Ryan asked for
## "a transition screen each round that shows the map or something"; this is the
## switch that turns it off again.
@export var round_card_enabled: bool = true

## How long the round card is held, fade included.
##
## [b]Short on purpose, and this is the number to zero first.[/b] Ryan tests
## constantly and will see this hundreds of times. It is skippable and it is
## never shown headless, but the hundredth viewing is the one it has to survive,
## so it is tuned to be read at a glance rather than watched.
##
## Set it to 0.0 and the round card never appears at all -- the round turns over
## exactly as it did before the card existed.
@export_range(0.0, 10.0, 0.1) var round_card_seconds: float = 1.6

## How much of [member round_card_seconds] is spent fading the card out into the
## round behind it. Same reasoning as [member handover_fade_seconds]: a card that
## vanishes between two frames reads as a glitch.
@export_range(0.0, 4.0, 0.05) var round_card_fade_seconds: float = 0.35

## How long the card refuses to be skipped, from the frame it appears.
##
## The same bug fix [member win_beat_skip_lockout_seconds] is. A round ends with
## a shot or with a runner crossing the line, and a player holding fire -- or
## holding forward on a keyboard that repeats -- would otherwise skip the card
## with the input that ended the round and never see it. Under human reaction
## time, so nobody deliberately skipping is ever refused.
@export_range(0.0, 2.0, 0.01) var round_card_skip_lockout_seconds: float = 0.2

## Degrees per second the round card's map camera orbits the tower while the
## card is up. Sign is direction; magnitude is speed. Zero holds the camera
## dead still at [member RoundTransitionScreen.map_yaw_degrees], which is the
## exact framing the card used before this existed -- static, not broken.
##
## [b]Subtle is the word Ryan used.[/b] The default is a slow drift, not a
## spin: over [member round_card_seconds] at its default the camera turns only
## a few degrees. Tune it here, alongside the durations, rather than in the
## screen's own script.
@export_range(-30.0, 30.0, 0.5) var round_card_rotation_degrees_per_second: float = 4.0

# --- The win: the match is over -----------------------------------------------

## Hold a beat on the finished match before the result dialog appears.
##
## The beat is drawn over a match [MatchController] has already frozen. It
## changes nothing about the result, it delays being ASKED something about it.
@export var win_beat_enabled: bool = true

## How long the beat holds before the result dialog is offered.
##
## Deliberately short. Ryan is testing constantly and will see this hundreds of
## times, so anything that cannot be sat through comfortably on the hundredth
## viewing is too long -- and it is skippable besides.
@export_range(0.0, 10.0, 0.1) var win_beat_seconds: float = 2.4

## How much of [member win_beat_seconds] is spent fading the beat out into the
## dialog. Same reasoning as [member handover_fade_seconds].
@export_range(0.0, 4.0, 0.05) var win_beat_fade_seconds: float = 0.5

## How long the beat refuses to be skipped, from the frame it appears.
##
## [b]This is not a nag, it is a bug fix.[/b] The match is won by a shot, and a
## player who wins with the fire button held down -- or who is mashing it at a
## last runner -- would otherwise skip the beat with the same press that ended
## the match and never see it at all. A fifth of a second is under human
## reaction time, so nobody deliberately skipping is ever refused.
@export_range(0.0, 2.0, 0.01) var win_beat_skip_lockout_seconds: float = 0.2


## The fade, clamped so it can never be longer than the hold it belongs to.
static func fade_within(fade_seconds: float, hold_seconds: float) -> float:
	return clampf(fade_seconds, 0.0, maxf(hold_seconds, 0.0))


## Seconds the handover banner should be held for, or 0.0 when it is switched
## off. The one place either flag is consulted.
func get_handover_seconds() -> float:
	if not enabled or not handover_enabled:
		return 0.0
	return maxf(handover_seconds, 0.0)


## Seconds the win beat should be held for, or 0.0 when it is switched off.
func get_win_beat_seconds() -> float:
	if not enabled or not win_beat_enabled:
		return 0.0
	return maxf(win_beat_seconds, 0.0)


## Seconds the round card should be held for, or 0.0 when it is switched off.
func get_round_card_seconds() -> float:
	if not enabled or not round_card_enabled:
		return 0.0
	return maxf(round_card_seconds, 0.0)
