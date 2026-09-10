class_name MovementAudioTuning
extends Resource

## Every number [MovementAudioListener] needs that is not already a mixing
## decision on an [AudioCue].
##
## [b]Why this is not on [MovementProfile].[/b] [MovementProfile] is documented
## as holding every number [PlayerController] itself is swept against in a
## headless movement test, and none of these are read by the controller -- the
## listener reads a body's existing public surface
## ([method PlayerController.get_horizontal_speed], [method CharacterBody3D.is_on_floor],
## [method PlayerController.is_sliding], [signal PlayerController.landed]'s
## impact speed) and never touches the controller at all. Keeping these numbers
## here means the whole movement-audio feature is addable and tunable without
## a second file outside [code]scripts/audio/[/code] and [code]assets/audio/[/code]
## having to change.
##
## [b]Why this is not on [AudioCue].[/b] Volume, falloff and retrigger rate are
## already tunable per event on the shipped cue in the bank -- see
## [code]scenes/audio/placeholder_bank.tres[/code]. What is here instead is the
## GAMEPLAY-side pacing decision that decides whether and how hard an event
## posts at all: how far a body must travel between footsteps, how soft a
## landing has to be to stay silent, and whether a ghost is audible.

# --- Footsteps ------------------------------------------------------------

## Metres a body must cover, on the floor and not sliding, between one
## [constant AudioEvents.MOVEMENT_FOOTSTEP] and the next.
##
## This is the whole answer to "paced by speed, not a timer": the listener
## accumulates horizontal distance every physics tick and posts on crossing this
## many metres, so a sprint posts twice as often as a walk at half the speed
## without either of them being told its own pace, and a ghost at
## [member GhostProfile.speed_multiplier] posts fastest of all for the same
## reason. 1.6 m is a placeholder stride length, not a measured one -- tune by
## ear against the placeholder cue.
@export_range(0.1, 6.0, 0.05, "or_greater") var footstep_stride_metres: float = 1.6

## Horizontal speed, in m/s, below which a grounded body is standing rather
## than walking and posts no footsteps at all. Mirrors the idea behind
## [member PrisonerAvatar.idle_speed] without depending on that node -- a
## shooter in the tower has no [PrisonerAvatar] and must still go quiet when
## stationary.
@export_range(0.0, 5.0, 0.05, "or_greater") var footstep_min_speed: float = 0.6

# --- Landing ----------------------------------------------------------------

## Downward impact speed, in m/s, below which [signal PlayerController.landed]
## is too soft to bother with -- a step off a kerb, not a landing. No
## [constant AudioEvents.MOVEMENT_LAND] posts under this.
@export_range(0.0, 10.0, 0.1, "or_greater") var landing_min_impact_speed: float = 1.5

## Impact speed, in m/s, at or above which a landing is posted at full gain
## ([member landing_gain_max_db], i.e. the cue's own volume with nothing added).
## Above this the landing is already as loud as this system will make it; only
## real sound design pitching the sample harder would go further.
@export_range(0.1, 40.0, 0.1, "or_greater") var landing_full_impact_speed: float = 9.0

## Extra gain, in dB, applied to a landing at exactly [member landing_min_impact_speed].
## Negative: the softest landing this system still bothers to post is quieter
## than the cue's authored volume, not louder.
@export_range(-40.0, 0.0, 0.1) var landing_gain_min_db: float = -8.0

## Extra gain, in dB, applied to a landing at or above [member landing_full_impact_speed].
## 0.0 by default -- full impact plays the cue exactly as authored.
@export_range(-40.0, 12.0, 0.1) var landing_gain_max_db: float = 0.0

## The gain, in dB, [method AudioDirector.post_at_gain] should be called with for
## a landing of [param impact_speed]. Returns a very negative number (not a
## sentinel) for anything under [member landing_min_impact_speed]; the caller is
## expected to check that threshold itself before posting at all -- see
## [method MovementAudioListener._on_landed] -- so this function never has to
## answer "should this post", only "how loud".
func landing_gain_db(impact_speed: float) -> float:
	var span: float = maxf(landing_full_impact_speed - landing_min_impact_speed, 0.001)
	var t: float = clampf((impact_speed - landing_min_impact_speed) / span, 0.0, 1.0)
	return lerpf(landing_gain_min_db, landing_gain_max_db, t)

# --- Ghosts -------------------------------------------------------------------

## Whether a ghost's own movement -- footsteps, jump, land, slide -- is audible
## at all.
##
## [b]The ruling this ships with is TRUE, and it is a design call, not an
## oversight.[/b] A ghost's whole job is to be "faster than the living" and to
## close on a runner from behind (see [GhostProfile]), and the entire brief this
## feature was built against names "no ghost closing on you" as the gap being
## closed. Muting the one thing in the match that is actively hunting the player
## would be the most surprising possible choice, so the default is the least
## surprising one: a ghost sounds exactly like a living prisoner, through the
## same five events, off the same distance-paced footsteps and the same
## signals -- the only ghost-specific code in [MovementAudioListener] is this
## one on/off switch. The 3x speed multiplier already makes a ghost's footsteps
## come three times as often with no extra code beyond that, which reads as
## urgency for free.
##
## Ryan has not ruled on this; flip it to false for total silence instead, with
## no code change, if a hunt that announces itself turns out to be the wrong
## call.
@export var ghosts_make_movement_sound: bool = true
