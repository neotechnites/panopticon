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
## [b]What the number means[/b]: the reciprocal is the nominal magnification, so
## 0.40 reads as 2.5x. The magnification the EYE reports is the ratio of the
## tangents, not of the angles, and at the shipped 100 degree display FOV that
## is [code]tan(50) / tan(20)[/code] -- a little over 3.2x.
##
## [b]Why 0.40[/b]: the shot this optic exists to serve is a .50 at a runner on
## the far arc, 35 to 60 m out and crossing. At the un-zoomed 100 degrees a body
## at 50 m is about a centimetre of screen and the shot is a guess. 0.40 puts
## roughly a hand's width of the ring in frame at that range: enough that a
## crossing runner is a body with a direction rather than a smudge, and not so
## much that leading them becomes a wrist exercise. Going further -- 0.30 and
## below -- the target crosses the frame faster than the compensated mouse can
## comfortably follow, which is the exact failure a scope with no overlay and no
## breath-hold has no way to help with.
@export_range(0.05, 1.0, 0.01) var zoom_factor: float = 0.40

# --- Transition ---------------------------------------------------------------

## Seconds to travel the whole way from hipfire to full zoom.
##
## Deliberately not instant. The rifle's reload already makes a shot an
## expensive, deliberate act (see [member WeaponProfile.base_reload_seconds]);
## a zoom that snaps invites the flick-and-click reflex the reload exists to
## rule out. Long enough to be a decision, far shorter than the reload, so it
## never becomes the thing gating the next shot.
##
## Zero is honoured and means snap.
@export_range(0.0, 2.0, 0.01) var zoom_in_seconds: float = 0.24

## Seconds to travel the whole way from full zoom back to hipfire.
##
## [b]Its own number, and deliberately shorter than [member zoom_in_seconds].[/b]
## Going in is a commitment the player chose and can afford to pay for. Coming
## out is almost always a reaction -- somebody is close, something moved at the
## edge of a field of view the scope has cut to a third -- and a symmetric
## transition makes that reaction cost the same as the decision did, which is
## the wrong way round. Roughly half is enough to feel like letting go rather
## than winding back, without being the snap that would make feathering the
## button free.
##
## A partial transition that reverses costs proportionally less either way, so
## feathering stays cheap and the optic is never stuck part-way.
##
## Zero is honoured and means snap.
@export_range(0.0, 2.0, 0.01) var zoom_out_seconds: float = 0.13

## How much the transition is eased, from 0.0 (a constant rate, the whole way)
## to 1.0 (smoothstep: it leaves and arrives gently and covers the middle fast).
##
## [b]Why one number for both directions[/b]: this shapes the PROGRESS, not the
## rate, and the same shape is used going in and coming out. That is what makes
## feathering safe. Two different curves would mean the applied FOV jumped the
## instant the player reversed -- the shaped value under curve A at half way is
## not the shaped value under curve B at half way -- and that jump is a visible
## pop on the most common input in the whole scope. Asymmetry belongs in the two
## durations above, where it costs nothing.
##
## At 1.0 the linear ramp this optic shipped with becomes a camera move: the
## view does not lurch into motion, and it settles into the zoomed frame instead
## of stopping dead at it, which is the difference between a number changing and
## glass locking in. 0.0 restores the old behaviour exactly, for comparison.
@export_range(0.0, 1.0, 0.05) var transition_smoothing: float = 1.0

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

# --- Scope vignette -----------------------------------------------------------

## The optic is a picture on the screen, not a lens on the model: at full aim a
## dark border closes in around a clear centre, which is the whole of what
## makes a narrowed field of view read as "looking through a scope". Drawn by
## [ScopeVignette], on the guard's screen only. The rifle's own scope stays the
## solid brick it is modelled as -- see that class's notes.
##
## These four numbers are the entire look, and they live here for the same
## reason every other number in this file does: a constant buried in the shader
## is a constant no sweep can ever vary.

## How opaque the darkest part of the border gets, 0.0 (invisible) to 1.0
## (solid). At 1.0 the edges of the screen are gone entirely, which is the
## honest read of a scope -- what is outside the tube is not dimmed, it is not
## there. Pull it down to leave the ring peripherally visible.
@export_range(0.0, 1.0, 0.01) var vignette_opacity: float = 0.96

## Radius of the clear centre, as a fraction of HALF the screen height: 1.0
## would reach the top and bottom edges and leave only the corners dark.
##
## This is the field the guard actually shoots through, so it is the number to
## touch first. Too small and a crossing runner is lost behind the border
## before the shot can be led; too large and the optic stops reading as one.
## 0.46 leaves a circle a little under half the screen's height clear, which at
## the shipped [member zoom_factor] is comfortably more than the ring's width
## at 50 m.
@export_range(0.05, 1.2, 0.01) var vignette_clear_fraction: float = 0.46

## How far past [member vignette_clear_fraction] the border takes to reach full
## opacity, in the same fraction-of-half-height units. Small is a hard-edged
## tube; large is a soft fall-off that reads more like a camera than a scope.
@export_range(0.01, 1.5, 0.01) var vignette_softness: float = 0.30

## The transition progress at which the border STARTS to close, 0.0 to 1.0.
##
## Ryan asked for the vignette to appear as the aim completes rather than to
## fade in over the whole raise, so this remaps the shared progress instead of
## introducing a clock: below it there is no vignette at all, and from it to
## 1.0 the border closes the rest of the way. 0.55 puts the whole of the
## overlay in the back half of the raise, arriving exactly as the pose and the
## field of view do -- there is no second timer that could arrive late.
##
## 0.0 fades it in across the entire transition; values near 1.0 snap it on at
## the very end.
@export_range(0.0, 0.99, 0.01) var vignette_onset: float = 0.55
