class_name AudioEvents
extends RefCounted

## The names of every sound PANOPTICON can ask for. This file is the contract.
##
## Gameplay code says [b]what happened[/b]. It posts one of the constants below
## to an [AudioDirector] and stops there: it never names a file, never picks a
## bus, never sets a volume and never learns whether the sound it asked for
## exists. An [AudioBank] maps these names onto streams and playback settings,
## and the bank is the only place in the project that knows a filename.
##
## [codeblock]
## AudioDirector.post_event_at(AudioEvents.RIFLE_FIRED, origin)
## AudioDirector.post_event(AudioEvents.UI_CLICK)
## [/codeblock]
##
## [b]Why a flat string namespace and not an enum.[/b] An enum would be
## marginally faster and would catch a typo at compile time, and it would also
## make the bank -- a [Resource], edited in the inspector and eventually handed
## to whoever is doing the sound design -- depend on a script's ordinal values.
## Reorder the enum and every saved bank silently remaps. [StringName]s compare
## by pointer after interning, so the speed argument is close to moot, and a
## name that is missing from the bank is a no-op rather than a crash (see
## [method AudioDirector.post]), which is exactly the failure mode wanted while
## the audio is still placeholder.
##
## Names are dotted and grouped by source: [code]weapon.[/code],
## [code]match.[/code], [code]ui.[/code], [code]music.[/code]. The prefix is
## convention, not machinery -- nothing parses it.

# --- Weapon -------------------------------------------------------------------
#
# All five come from scripts/weapon/rifle.gd, which emits them and is not
# modified: MatchAudioListener subscribes from outside. The first three are
# positional because a shot in PANOPTICON is a broadcast of the shooter's
# position -- the tracer is the visual half of that tell and the report is the
# other half. The two reload cues are NOT positional: they are the tower
# player's own feedback on a weapon they are holding, and panning them would be
# both wrong and, at a listener distance of zero, unstable.

## [signal Rifle.fired]. Positional, at the shot's origin.
const RIFLE_FIRED: StringName = &"weapon.rifle.fired"

## [signal Rifle.target_hit]. Positional, at the impact point.
const RIFLE_HIT: StringName = &"weapon.rifle.hit"

## [signal Rifle.missed]. Positional, at the far end of the shot.
const RIFLE_MISSED: StringName = &"weapon.rifle.missed"

## [signal Rifle.reload_started]. Non-positional.
const RIFLE_RELOAD_STARTED: StringName = &"weapon.rifle.reload_started"

## [signal Rifle.reload_finished]. Non-positional. The single most important
## sound in the game for the player in the tower.
const RIFLE_RELOAD_FINISHED: StringName = &"weapon.rifle.reload_finished"

# --- Match --------------------------------------------------------------------
#
# All seven come from scripts/match/match_controller.gd. None is positional:
# they are announcements about the state of the match, not events at a place.
# match.runner_converted is the arguable one -- it does happen somewhere -- but
# the controller's runner_removed signal carries a count and not a position, and
# the conversion is already reported positionally by RIFLE_HIT one call earlier.

## [signal MatchController.match_started].
const MATCH_STARTED: StringName = &"match.started"

## [signal MatchController.race_started]: the opening race, no shooter.
const RACE_STARTED: StringName = &"match.race_started"

## [signal MatchController.round_started].
const ROUND_STARTED: StringName = &"match.round_started"

## [signal MatchController.seat_changed]: the tower has changed hands.
const SEAT_CHANGED: StringName = &"match.seat_changed"

## [signal MatchController.round_resolved].
const ROUND_RESOLVED: StringName = &"match.round_resolved"

## [signal MatchController.runner_removed].
const RUNNER_CONVERTED: StringName = &"match.runner_converted"

## [signal MatchController.match_won]. The last sound of a match.
const MATCH_WON: StringName = &"match.won"

# --- Movement -------------------------------------------------------------------
#
# All five come from scripts/audio/movement_audio_listener.gd, which watches
# every PlayerController in the scene -- the human, every bot, and a ghost --
# rather than one authored body, because a match can spawn and reparent bodies
# at runtime (see MovementAudioListener's own header). All five are positional:
# the whole reason they exist is so a runner can hear somebody else's feet,
# jump, landing or slide, at a place in the world -- see the design note on
# [constant POSITIONAL] and PANOPTICON.md's brief for this system: "you cannot
# hear anyone else -- no approaching footsteps, no ghost closing on you, no
# slide going past."
#
# FOOTSTEP is paced by distance travelled, not by a timer -- see
# [member MovementAudioTuning.footstep_stride_metres] -- so a sprint posts more
# often than a walk and a slide (which does not accumulate stride distance at
# all) never machine-guns them. JUMP and the two SLIDE events are one-shots off
# [signal PlayerController.jumped], [signal PlayerController.slide_started] and
# [signal PlayerController.slide_ended]. LAND is the one that scales: posted
# through [method AudioDirector.post_at_gain] with a gain derived from
# [signal PlayerController.landed]'s impact speed, so a step down and a fall off
# a ledge are not the same volume.

## A body's foot struck the ground while running.
const MOVEMENT_FOOTSTEP: StringName = &"movement.footstep"

## [signal PlayerController.jumped].
const MOVEMENT_JUMP: StringName = &"movement.jump"

## [signal PlayerController.landed]. Gain-scaled by impact speed; see
## [method AudioDirector.post_at_gain].
const MOVEMENT_LAND: StringName = &"movement.land"

## [signal PlayerController.slide_started].
const MOVEMENT_SLIDE_START: StringName = &"movement.slide_start"

## [signal PlayerController.slide_ended].
const MOVEMENT_SLIDE_END: StringName = &"movement.slide_end"

# --- The victim ---------------------------------------------------------------

## [signal FxHitReaction.struck]: THIS player was hit.
##
## Not [constant RIFLE_HIT], and the difference is the whole reason it exists.
## [constant RIFLE_HIT] is the impact as the WORLD hears it -- positional, at the
## point struck, quiet at range, and posted for every hit anybody lands on
## anybody. This one is posted only on the body the local player is looking out
## of, and it is the sound of it happening to you.
##
## NOT positional, deliberately. The listener is inside the head that was hit;
## there is no distance to attenuate and no direction to pan, and a 3D source
## placed at a listener's own position is numerically unstable besides. The
## direction is carried by the camera whip, which is the channel that can
## actually express it -- see [FxHitReaction].
##
## Wired by [MatchAudioListener], which finds the [FxHitReaction] in the scene
## the same way it finds the rifle. The reaction is inert with no display
## server, so a headless sweep never posts this.
const PLAYER_HIT_TAKEN: StringName = &"player.hit_taken"

# --- The catch ----------------------------------------------------------------
#
# The two halves of one event, posted on two different machines. Both come from
# [FxCatchReaction], which is the node that already had to work out which side
# of a catch the local player was on; MatchAudioListener subscribes to it the
# same way it subscribes to FxHitReaction, and MatchController is untouched.
#
# NEITHER IS POSITIONAL, for the same reason PLAYER_HIT_TAKEN is not: a catch
# happens at arm's length, so the listener is standing inside the sound, and a
# 3D source at zero distance is numerically unstable as well as pointless.
#
# A catch between two bots posts NOTHING. FxCatchReaction returns before it
# emits either signal when neither participant is the local body, so a round in
# which the bots swap spots twenty times is exactly as quiet as one in which
# they do not.

## [signal FxCatchReaction.catch_made]: THIS player's ghost took somebody's spot.
##
## The ghost's reward and the only good news a ghost can generate, so it is
## pitched and shaped as an ASCENT. Deliberately not [constant RIFLE_HIT]: that
## is the tower's confirmation, heard by whoever is holding the rifle, and a
## catch is the one kill in PANOPTICON that the rifle had nothing to do with.
const PLAYER_CATCH_MADE: StringName = &"player.catch_made"

## [signal FxCatchReaction.catch_taken]: THIS player was caught and is a ghost.
##
## A death, and it must not be mistaken for the other one. [constant
## PLAYER_HIT_TAKEN] is a bright transient pitched down into a thud -- a blow
## landing from range. This is dull, low and dragged, because being caught is
## something arriving at contact and taking hold, and the player has to be able
## to tell which of the two just happened without looking at anything.
const PLAYER_CATCH_TAKEN: StringName = &"player.catch_taken"

# --- UI -----------------------------------------------------------------------
#
# Wired by UIAudioListener, which walks a Control subtree and subscribes to
# BaseButton signals rather than requiring every menu to learn about audio.
# Never positional: a menu is not in the world.

## Any [BaseButton] in a wired subtree was activated.
const UI_CLICK: StringName = &"ui.click"

## The keyboard focus or the mouse moved onto a button. Quiet, and rate limited
## by [member AudioCue.min_retrigger_seconds] -- a mouse dragged across a column
## of buttons must not machine-gun.
const UI_FOCUS: StringName = &"ui.focus"

## A screen was backed out of rather than confirmed.
const UI_BACK: StringName = &"ui.back"

## [signal PauseMenu.opened].
const UI_MENU_OPENED: StringName = &"ui.menu_opened"

## [signal PauseMenu.closed].
const UI_MENU_CLOSED: StringName = &"ui.menu_closed"

# --- Music --------------------------------------------------------------------

## Routed to the [code]Music[/code] bus rather than [code]Effects[/code], and
## deliberately shipped with no stream attached.
##
## It exists so the Music path is exercised and provably wired -- the settings
## screen already has a music slider driving that bus -- and so the "an event
## with nothing behind it is a silent no-op" case is a real entry in the
## shipping bank rather than a hypothetical. There is no dynamic music system
## and none is planned; attach a stream here and it plays.
const MUSIC_MATCH_THEME: StringName = &"music.match_theme"

# --- Roll calls ---------------------------------------------------------------

## Every event name, in the order above. A bank is complete when it has a cue
## for each of these; [method AudioBank.missing_events] checks exactly that.
const ALL: Array[StringName] = [
	RIFLE_FIRED,
	RIFLE_HIT,
	RIFLE_MISSED,
	RIFLE_RELOAD_STARTED,
	RIFLE_RELOAD_FINISHED,
	MATCH_STARTED,
	RACE_STARTED,
	ROUND_STARTED,
	SEAT_CHANGED,
	ROUND_RESOLVED,
	RUNNER_CONVERTED,
	MATCH_WON,
	MOVEMENT_FOOTSTEP,
	MOVEMENT_JUMP,
	MOVEMENT_LAND,
	MOVEMENT_SLIDE_START,
	MOVEMENT_SLIDE_END,
	PLAYER_HIT_TAKEN,
	PLAYER_CATCH_MADE,
	PLAYER_CATCH_TAKEN,
	UI_CLICK,
	UI_FOCUS,
	UI_BACK,
	UI_MENU_OPENED,
	UI_MENU_CLOSED,
	MUSIC_MATCH_THEME,
]

## The events that carry a world position. Advisory: the authority is
## [member AudioCue.positional] on the cue in the bank, because whether a sound
## is placed in the world is a mixing decision and mixing decisions live in the
## bank. This list is what the placeholder bank is built with and what a check
## can assert against.
const POSITIONAL: Array[StringName] = [
	RIFLE_FIRED,
	RIFLE_HIT,
	RIFLE_MISSED,
	MOVEMENT_FOOTSTEP,
	MOVEMENT_JUMP,
	MOVEMENT_LAND,
	MOVEMENT_SLIDE_START,
	MOVEMENT_SLIDE_END,
]


## True when [param event] is one of the names above. Used by tooling; the
## director does not gate on it, because a bank is allowed to carry cues this
## file has not heard of.
static func is_known(event: StringName) -> bool:
	return ALL.has(event)
