class_name ZoomProfile
extends Resource

## Every tunable number for [WeaponOptic] lives here.
##
## Same rule as [MovementProfile] and [WeaponProfile]: nothing about how the
## optic behaves may be hard-coded in the node. The project settles design
## questions by sweeping variants of a resource in headless bot matches, so a
## constant buried in code is a constant that can never be tested. Add new knobs
## here, never there.
##
## [b]Why every number here is a ratio and not an angle[/b]
##
## Not one field in this file is a field of view in degrees, and that is the
## single most important thing about it. A player-configurable display FOV lives
## in the game's settings and is written straight onto the [Camera3D]; if the
## optic held an absolute zoomed FOV it would quietly overrule that preference
## every time the player aimed, and the setting would appear to work right up
## until the moment it mattered. A factor composes with the player's choice
## instead of replacing it: whatever FOV they picked, aiming narrows it by the
## same proportion, and the two settings never fight.

## How the zoom is held. Both are common preferences and neither is more
## correct; the choice belongs to the player, so it is a setting rather than an
## argument in the input layer.
enum Activation {
	## Zoomed only while the button is down. The default: it cannot leave the
	## player zoomed in without their knowing, and releasing under pressure is
	## faster than clicking twice.
	HOLD,
	## Press to zoom in, press again to zoom out. Kinder to the hand over a long
	## session, and the preference of anyone used to a scope key.
	TOGGLE,
}

# --- Magnification ------------------------------------------------------------

## The zoomed field of view as a FRACTION of the camera's own field of view --
## never an angle. See the class notes: this multiplies the player's display FOV
## setting rather than replacing it.
##
## The reciprocal is the magnification the player perceives, so the default
## 0.45 is a touch over 2.2x. At the ring's roughly 120 m across that is the
## difference between "a grey smudge is moving" and "that runner is committed to
## the open stretch"; much more and tracking a crossing target becomes a wrist
## exercise, much less and the zoom is not worth the button.
@export_range(0.05, 1.0, 0.01) var zoom_factor: float = 0.45

# --- Transition ---------------------------------------------------------------

## Seconds to travel the whole way between hipfire and full zoom, at a constant
## rate. A partial transition that reverses costs proportionally less, so
## feathering the button is cheap and never leaves the optic stuck.
##
## Deliberately not instant. The rifle's reload already makes a shot an
## expensive, deliberate act (see [member WeaponProfile.base_reload_seconds]);
## a zoom that snaps invites the flick-and-click reflex the reload exists to
## rule out. Long enough to be a decision, far shorter than the reload, so it
## never becomes the thing gating the next shot.
##
## Zero is honoured and means snap.
@export_range(0.0, 2.0, 0.01) var transition_seconds: float = 0.25

# --- Aim ----------------------------------------------------------------------

## How strongly mouse sensitivity is scaled down as the view narrows, as an
## exponent on the FOV ratio: the multiplier [WeaponOptic] reports is
## [code]pow(current_fov / base_fov, sensitivity_compensation)[/code].
##
## Leave it at 1.0 unless you know you want otherwise. At 1.0 a given mouse
## movement sweeps the same fraction of the VISIBLE field whether zoomed or not,
## which is the only setting under which a scope feels like the same weapon it
## was a moment ago. At 0.0 there is no compensation at all and the zoomed view
## whips across the ring untrackably -- that is the bug this field exists to
## prevent, exposed as a number only so a sweep can measure the difference.
## Values in between are the "partial monitor-distance" compensation some
## players prefer.
@export_range(0.0, 1.5, 0.05) var sensitivity_compensation: float = 1.0

# --- Input --------------------------------------------------------------------

## Hold to zoom, or press to toggle. Read by [ZoomInput]; the optic itself never
## looks at it, because a bot has no buttons to hold.
@export var activation: Activation = Activation.HOLD
