class_name FeedbackProfile
extends Resource

## Every tunable number for the hit-and-kill feedback layer lives here.
##
## Same rule as [WeaponProfile] and [MovementProfile]: nothing about how the
## feedback behaves may be hard-coded in a component. The project settles design
## questions by sweeping variants of a resource, and a constant buried in code is
## a constant that can never be tested. Add new knobs here, never there.
##
## Units are seconds, degrees, metres and pixels, as the field names say.
##
## [b]The register this file is tuned to[/b]
##
## Being shot should feel like being hit in the side of the head with a baseball
## from a pro pitcher: instant, violent, over. Every duration below is therefore
## short enough that the effect has finished before the player has finished
## reacting to it. The longest thing here is [member impact_recover_seconds] at
## well under a third of a second, and the flash is gone in a tenth. Nothing in
## this file holds a player hostage watching an animation, because there is no
## animation -- only numbers decaying to zero.
##
## [b]The one hard constraint[/b]
##
## [member recoil_attack_seconds] + [member recoil_recover_seconds] must stay
## below [member WeaponProfile.min_reload_seconds]. The rifle aims down the
## camera, so a camera kick that is still running when the weapon comes off
## reload would move the next shot. Keeping the whole kick shorter than the
## shortest possible reload makes that structurally impossible rather than
## merely unlikely. [FxWeaponFeel] checks it at startup and complains.

# --- Master -------------------------------------------------------------------

## Kills the whole layer. Every component checks it first, so one false here
## turns the game back into the greybox it was before any of this existed.
@export var enabled: bool = true

# --- 1. Shooter: did I hit? ---------------------------------------------------

## The hitmarker: four ticks that snap open around the crosshair when a shot
## takes a PERSON out, and only then.
##
## This is the single most important signal in the game for the tower player.
## One shot, a multi-second reload, and a target that is a few grey pixels on the
## far arc: the shooter's whole feedback loop is "did that connect", and there is
## no health bar, no damage number and no scoreboard update fast enough to answer
## it. So the answer is drawn at the centre of the screen, where the eye already
## is, on the frame the shot resolves.
@export var hit_confirm_enabled: bool = true

## How long the hitmarker lives. Long enough to register at a glance, short
## enough that it is gone before the player has looked away.
@export_range(0.02, 2.0, 0.01) var hitmarker_seconds: float = 0.26

## Hitmarker colour. Deliberately the brightest thing the layer draws: a
## confirmed kill is the only event that gets full-intensity white.
@export var hitmarker_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Distance from screen centre to the inner end of each tick, before spread.
## Wide enough to clear the crosshair glyph rather than sit on top of it.
@export_range(0.0, 64.0, 0.5) var hitmarker_gap_pixels: float = 7.0

## How far the ticks travel outwards over their life. The outward pop is what
## makes the mark read as an EVENT rather than as a symbol that appeared.
@export_range(0.0, 64.0, 0.5) var hitmarker_spread_pixels: float = 9.0

## Length of each of the four ticks.
@export_range(1.0, 64.0, 0.5) var hitmarker_length_pixels: float = 11.0

## Thickness of each tick.
@export_range(1.0, 16.0, 0.5) var hitmarker_width_pixels: float = 3.0

## Shape of the fade. Above 1.0 the mark holds near full brightness and then
## drops away, which reads as a snap rather than as a dissolve.
@export_range(0.1, 8.0, 0.1) var hitmarker_fade_exponent: float = 2.0

## The negative mark: what a shot that hit the world, or nothing at all, draws.
##
## Absence of a hitmarker is technically enough information, but it is
## indistinguishable from "the effect is broken" or "I blinked", and a player who
## has just spent their only bullet deserves a positive answer either way. So a
## miss draws something too -- and it differs from a hit in SHAPE (a flat pair of
## dashes against four converging diagonals), in BRIGHTNESS and in DURATION, so
## the two cannot be confused at a glance, at speed, or by a colour-blind player.
@export var miss_mark_enabled: bool = true

## How long the miss mark lives. Shorter than the hitmarker on purpose: the good
## news gets more screen time than the bad.
@export_range(0.02, 2.0, 0.01) var miss_mark_seconds: float = 0.14

## Miss-mark colour. Dim and neutral -- it must never compete with a hitmarker
## in peripheral vision.
@export var miss_mark_color: Color = Color(0.62, 0.62, 0.62, 0.75)

## Distance from screen centre to the inner end of each miss dash.
@export_range(0.0, 64.0, 0.5) var miss_mark_gap_pixels: float = 15.0

## Length of each miss dash.
@export_range(1.0, 64.0, 0.5) var miss_mark_length_pixels: float = 6.0

## Thickness of each miss dash.
@export_range(1.0, 16.0, 0.5) var miss_mark_width_pixels: float = 2.0

## Shape of the miss mark's fade.
@export_range(0.1, 8.0, 0.1) var miss_mark_fade_exponent: float = 1.6

## A tiny camera punch on a confirmed kill, on top of the hitmarker.
##
## PURE TRANSLATION, never rotation. The rifle's aim line is the camera's -Z
## axis, so a rotation here would move the shot; a dolly along that axis cannot,
## no matter how big it gets or how long it lasts. That is why the shooter's
## confirmation is the one camera response in this file with no angular
## component at all.
@export var confirm_punch_enabled: bool = true

## How far the camera snaps back along its own view axis on a confirmed kill.
@export_range(0.0, 1.0, 0.005) var confirm_punch_metres: float = 0.045

## How long the confirm punch takes to return to zero.
@export_range(0.01, 1.0, 0.01) var confirm_punch_seconds: float = 0.09

# --- 2. Victim: I was hit -----------------------------------------------------

## The victim's reaction: a held white frame and a camera whip, both gone inside
## a third of a second.
##
## There is no death animation here and there must never be one. A hit is
## terminal, the round restarts almost immediately, and the worst thing this
## layer could do is make the player watch something. So the entire reaction is
## front-loaded into the first two frames -- full-intensity flash at t=0, full
## angular whip at t=0 -- and everything after that is decay.
@export var hit_reaction_enabled: bool = true

## The full-screen flash colour and its peak alpha.
##
## White rather than red: the ring is greybox and the tower's light is neutral,
## so white is the only value that is unambiguously "not part of the world".
## Red also reads as damage-over-time, and there is no damage in this game --
## there is being alive and being converted.
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.85)

## Seconds the flash is held at full alpha before it starts to fall. Two frames
## at 60 Hz. This is the whole "baseball" -- a hard cut, not a fade in.
@export_range(0.0, 0.5, 0.005) var flash_hold_seconds: float = 0.03

## Total life of the flash, hold included.
@export_range(0.01, 2.0, 0.01) var flash_seconds: float = 0.11

## Shape of the flash's fall after the hold.
@export_range(0.1, 8.0, 0.1) var flash_fade_exponent: float = 2.2

## The camera whip: a decaying oscillation about the axis the shot came from.
@export var impact_shake_enabled: bool = true

## Peak pitch of the whip, applied along the shot's vertical component.
@export_range(0.0, 45.0, 0.1) var impact_pitch_degrees: float = 7.0

## Peak yaw of the whip, applied along the shot's lateral component. Shot from
## your left and your view snaps right, because that is where your head went.
@export_range(0.0, 45.0, 0.1) var impact_yaw_degrees: float = 9.0

## Peak roll of the whip. Roll is the cheapest way to sell a blow to the head
## and the only rotation a first-person camera cannot get from aiming, so it is
## the axis that makes the hit read as something done TO the player.
@export_range(0.0, 45.0, 0.1) var impact_roll_degrees: float = 6.5

## How fast the whip oscillates. About eleven cycles a second: fast enough to be
## a snap rather than a wobble, slow enough to survive a 60 Hz sample.
@export_range(0.1, 60.0, 0.1) var impact_frequency_hz: float = 11.0

## How long the whip takes to reach zero.
@export_range(0.01, 2.0, 0.01) var impact_recover_seconds: float = 0.28

## Shape of the whip's decay. High, so the first swing carries nearly all of it.
@export_range(0.1, 8.0, 0.1) var impact_fade_exponent: float = 2.5

## How far the camera is shoved along the shot's own direction of travel.
@export_range(0.0, 1.0, 0.005) var impact_punch_metres: float = 0.07

# --- 3. Shooter: weapon feel --------------------------------------------------

## The rifle's recoil: an upward kick with a little yaw and roll, and a shove
## back along the view axis, that returns exactly to where the player was
## pointing.
##
## The kick is applied to the CAMERA'S LOCAL TRANSFORM and decays to an exact
## zero, so the body's yaw and the head's pitch -- the things the player actually
## aimed -- are never written to. The shot that causes the kick has already been
## resolved by the time the first frame of it is applied, and the whole kick is
## over long before the reload ends. The rifle therefore cannot steal aim in
## either direction.
@export var weapon_recoil_enabled: bool = true

## Peak upward pitch of the kick.
@export_range(0.0, 30.0, 0.05) var recoil_pitch_degrees: float = 1.7

## Peak lateral yaw. Its sign alternates shot to shot -- deterministically, with
## a counter and no RNG, so a headless sweep replays identically.
@export_range(0.0, 30.0, 0.05) var recoil_yaw_degrees: float = 0.45

## Peak roll. Alternates with the yaw.
@export_range(0.0, 30.0, 0.05) var recoil_roll_degrees: float = 0.85

## How far the camera is shoved back along its view axis.
@export_range(0.0, 1.0, 0.005) var recoil_punch_metres: float = 0.05

## Rise time of the kick. Non-zero, unlike the victim's whip: a weapon has a
## mechanism and a fractional beat of travel reads as mass, where an instant
## snap reads as a glitch.
@export_range(0.0, 0.5, 0.005) var recoil_attack_seconds: float = 0.02

## Time from the peak back to exactly zero. Must leave
## [member recoil_attack_seconds] + this below the weapon's minimum reload; see
## the class description.
@export_range(0.01, 2.0, 0.01) var recoil_recover_seconds: float = 0.30

## Shape of the recovery. Above 1.0 the muzzle falls quickly and then settles,
## which is what a shoulder does.
@export_range(0.1, 8.0, 0.1) var recoil_fade_exponent: float = 2.0


## Total wall-clock length of one recoil kick, attack included.
func get_recoil_duration() -> float:
	return recoil_attack_seconds + recoil_recover_seconds
