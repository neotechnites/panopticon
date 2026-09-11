class_name SpectatorProfile
extends Resource

## Every number the dead player's camera is made of.
##
## Same rule as [FeedbackProfile] and [GhostProfile]: nothing about how the view
## behaves may be hard-coded in the component. The one question this file exists
## to answer is what a player LOOKS AT while they are not playing, and that is a
## design question with no obviously right answer -- so it is a resource, and it
## can be swept.
##
## [b]Two anchors, because there are two kinds of dead[/b]
##
## [constant MatchController.Spectating.RESPAWNING] is three seconds long and you
## know exactly when it ends, so the camera stays with your body: you see the
## spot you were taken from and, usually, the tower that took you. The
## [code]death_[/code] fields below are that view.
##
## [constant MatchController.Spectating.ELIMINATED] is a racer who fell during
## the opening race, and it can last the rest of the race. Orbiting your own
## corpse for thirty seconds is a punishment, and the corpse is buried a hundred
## metres under the deck anyway -- see [method MatchController._park_body] -- so
## the camera goes UP instead and watches the ring finish the race. The
## [code]overlook_[/code] fields are that view, and it is the panopticon's own
## point of view, which is the joke.

## Turn the whole spectator camera off and leave the view where it was. The
## honest control for "is this better than the frozen first-person shot it
## replaced".
@export var enabled: bool = true

# --- The death view: orbiting the body you just lost --------------------------

## Seconds after the hit before the camera lets go of the body, for a death that
## has a hit reaction behind it.
##
## [b]Zero here would eat the hit.[/b] [FxHitReaction] whips the PLAYER's camera,
## and this node's camera is a different one -- so a spectator view that took
## over on the frame of the kill would cut away one frame into the whip and throw
## away the most dramatic part of being shot. The delay lets the reaction play
## out from inside the victim's own eyes first, and only then pulls back.
##
## Must stay comfortably under [member GhostProfile.respawn_delay_seconds], or
## there is nothing left of the hold to spectate. Slightly longer than
## [member FeedbackProfile.impact_recover_seconds] is the number that means
## "after the hit has finished".
@export_range(0.0, 1.5, 0.01) var enter_delay_seconds: float = 0.35

## How far the camera sits from the body, in metres. Unused since the gallery
## reframe below replaced the orbit; kept so an old save does not lose a tuned
## number.
@export_range(1.0, 40.0, 0.1) var death_radius_metres: float = 5.5

## How far above the body's feet the camera sits, in metres. Unused, see
## [member death_radius_metres].
@export_range(0.0, 40.0, 0.1) var death_height_metres: float = 2.8

## How high up the body the camera looks, in metres. Roughly chest height, so
## the body sits in the frame rather than at the bottom of it.
@export_range(0.0, 5.0, 0.05) var death_focus_height_metres: float = 1.1

## How far behind the body, opposite the way it was facing, the camera sits --
## the over-the-shoulder distance, in metres.
@export_range(0.0, 10.0, 0.1) var death_over_shoulder_distance_metres: float = 2.5

## How far above the gallery deck the camera sits, in metres.
@export_range(0.0, 10.0, 0.1) var death_over_shoulder_height_metres: float = 1.8

## The gallery is a ring of rock: any camera outside this radius band or the
## height band below is inside solid wall or ceiling. The death shot is always
## clamped into both, whatever the body is doing.
@export_range(0.0, 200.0, 0.1) var death_gallery_min_radius_metres: float = 48.0
@export_range(0.0, 200.0, 0.1) var death_gallery_max_radius_metres: float = 56.0
@export_range(-100.0, 200.0, 0.1) var death_gallery_min_height_metres: float = 24.5
@export_range(-100.0, 200.0, 0.1) var death_gallery_max_height_metres: float = 30.0

## How fast the camera drifts round the body, in degrees per second. Unused,
## see [member death_radius_metres] -- the gallery shot is a fixed cut.
@export_range(-180.0, 180.0, 0.5) var death_orbit_degrees_per_second: float = 16.0

# --- The overlook: watching the race you are out of ---------------------------

## How far from the ring axis the overlook sits, in metres. Unused now that the
## overlook lives in the pit below the deck; kept so an old save does not lose
## a tuned number. See [member overlook_orbit_radius_metres].
@export_range(1.0, 400.0, 1.0) var overlook_radius_metres: float = 78.0

## How high above the deck the overlook sits, in metres. Unused, see
## [member overlook_radius_metres].
@export_range(1.0, 400.0, 1.0) var overlook_height_metres: float = 46.0

## How high above the deck the overlook looks. Zero is the deck itself.
@export_range(-50.0, 50.0, 0.5) var overlook_focus_height_metres: float = 0.5

## How fast the overlook drifts round the arena, in degrees per second. Slower
## than the death view: this one may be held for the length of a race.
@export_range(-180.0, 180.0, 0.5) var overlook_orbit_degrees_per_second: float = 5.0

## How far out from the ring axis the overlook orbits, in metres -- the open
## void between the tower and the deck, not outside the ring's rock.
@export_range(1.0, 100.0, 0.5) var overlook_orbit_radius_metres: float = 34.0

## How far above the deck the overlook orbits, in metres.
@export_range(-50.0, 50.0, 0.5) var overlook_orbit_height_metres: float = 3.0

## How far out from the ring axis the overlook looks, in metres -- out on the
## deck itself, so runners are seen through the gallery's open inner side.
@export_range(1.0, 400.0, 1.0) var overlook_focus_radius_metres: float = 52.0

## The pit is open only between the tower and the deck's inner wall. The
## overlook's orbit radius and height are always clamped into this band,
## whatever the two fields above are tuned to.
@export_range(0.0, 200.0, 0.1) var overlook_min_radius_metres: float = 20.0
@export_range(0.0, 200.0, 0.1) var overlook_max_radius_metres: float = 40.0
@export_range(-100.0, 200.0, 0.1) var overlook_min_height_metres: float = 25.0
@export_range(-100.0, 200.0, 0.1) var overlook_max_height_metres: float = 30.0

# --- Free look ----------------------------------------------------------------

## Let the player steer the orbit with the mouse.
##
## [b]This is not decoration; it is what stops the wait being a punishment.[/b]
## A dead player with a camera they cannot move is watching a cutscene. A dead
## player who can look around is scouting the ring, watching who is where, and
## deciding what to do when they land -- which in a game about watching is the
## most on-theme thing they could possibly be doing.
@export var free_look_enabled: bool = true

## Radians of camera rotation per pixel of mouse motion.
##
## Its own number rather than [member MovementProfile.mouse_sensitivity]: this
## is an orbit and that is a first-person aim, they are different gestures, and
## a player who tuned their aim did not thereby tune this.
@export_range(0.0001, 0.05, 0.0001) var look_sensitivity: float = 0.0035

## How far the player may tip the orbit up and down, in degrees. Kept off the
## poles, where an orbit camera's up vector becomes ambiguous and the view rolls.
@export_range(-89.0, 0.0, 0.5) var pitch_min_degrees: float = -12.0
@export_range(0.0, 89.0, 0.5) var pitch_max_degrees: float = 72.0

## Where the orbit starts, vertically, in degrees above the horizontal. The
## death view's own default elevation is implied by the radius and height above,
## so this is the free-look offset applied on top -- zero means "start where the
## numbers put it".
@export_range(-89.0, 89.0, 0.5) var start_pitch_degrees: float = 0.0

## Field of view for the spectator camera, in degrees.
##
## Its own value rather than the player camera's, because the player camera's
## is owned by [WeaponOptic] and by the display settings, and borrowing it would
## mean a player who was zoomed when they died spectating down a rifle scope.
@export_range(20.0, 130.0, 1.0) var field_of_view_degrees: float = 75.0
