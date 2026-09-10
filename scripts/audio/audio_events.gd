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
]


## True when [param event] is one of the names above. Used by tooling; the
## director does not gate on it, because a bank is allowed to carry cues this
## file has not heard of.
static func is_known(event: StringName) -> bool:
	return ALL.has(event)
