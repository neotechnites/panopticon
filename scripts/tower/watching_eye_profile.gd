class_name WatchingEyeProfile
extends Resource

## Every tunable of [WatchingEye]: how big the eyeball is, how high it floats
## over the tower, how fast its gaze turns, and how much of the tower's own
## column counts as "the guard is in here, do not watch them".
##
## [b]What is deliberately not here[/b]
##
## Nothing on this resource refers to the guard's camera, to what the guard is
## looking at, to the rifle, to the seat or to match state, and nothing ever may.
## The one knob that mentions the tower at all -- [member tower_radius_metres]
## and the band either side of it -- describes a [b]volume of space[/b], not a
## person: it is answered by asking where the local viewer's own camera is, and
## the local viewer already knows where they are standing. See [WatchingEye] for
## why that distinction is the whole of the no-leak argument.
##
## Every number here is a starting point, not a measured constant. Nobody has
## seen this running: Godot must not be launched on Ryan's Mac.

## Radius of the eyeball in metres.
##
## [code]assets/models/eye.glb[/code] is authored as a unit sphere -- the sclera
## spans -1..+1 on every axis -- so this number is applied to the model as a
## uniform scale and is therefore literally the radius in metres. 2.5 gives a 5 m
## ball: big enough to read as an eye from the far rail at r=60, small enough to
## sit clear of the top of the eye box below it (y=4.15) and of [code]KeyLight[/code]
## above it (y=20).
@export_range(0.5, 8.0, 0.1) var radius_metres: float = 2.5

## Height of the eyeball's centre above the tower node's local origin, in metres.
##
## Measured from the tower, not from the world, and applied by [WatchingEye] to
## its own [member Node3D.position] on ready -- exactly the way [TowerLight]
## places itself from [member TowerLightProfile.height_metres]. That is what lets
## the eyeball ride along if the tower is raised: it is at (0, this, 0) in the
## tower's space, and it never reads a world coordinate to place itself.
##
## 7.2 puts a 2.5 m ball between the two things Ryan asked it to go between: its
## underside at y=4.7 clears the top of [PanopticonEye]'s box (y=4.15) by half a
## metre, and its crown at y=9.7 sits well under [code]KeyLight[/code] at y=20 --
## the light above the tower, and the one that actually lights this.
##
## [b]Not measured against [TowerLight].[/b] That node overwrites its own height
## from [member TowerLightProfile.height_metres] on ready, and that number is
## currently 2.2: the omni was shrunk from a ring-wide flood into a local glow and
## now sits [i]inside[/i] the eye box (y=-0.35..4.15), so it is no longer anything
## to hang below. There is deliberately no coupling between this number and either
## light -- neither [TowerLight] nor [code]KeyLight[/code] should have to know this
## node exists -- so if somebody raises the glow back over the box, check this by
## eye.
@export_range(0.0, 40.0, 0.1) var height_metres: float = 7.2

## How fast the gaze swings onto a viewer, as an exponential rate per second.
## Lower is laggier. 0.0 is an instant, unsmoothed snap.
##
## [b]Why the lag is the feature, 2026-09-10.[/b] Ryan played it and the tracking
## worked -- and read as a flat image rather than a ball: [i]"because its always
## directly pointed at me, it almost looks like a 2d image, not a 3d model
## following me."[/i] He is right, and the cause is geometric. A sphere is
## radially symmetric, so a sphere aimed [b]exactly[/b] at the viewer presents an
## identical silhouette from every bearing: nothing changes as he moves, and
## something that never changes as you move is indistinguishable from a decal
## pinned to the camera. Perfect tracking is what destroys the illusion of a
## solid. [b]Movement relative to the viewer is the only depth cue a bare sphere
## has[/b], so the eye has to be caught turning rather than found already turned.
## Ryan chose this fix on its own, over a carved socket and a swivel limit that
## were also on the table; neither of those was built.
##
## [b]What the number does.[/b] The remaining angle decays by
## [code]exp(-rate * t)[/code], so the eye settles [i]onto[/i] its target rather
## than trailing forever, and a viewer moving at a steady angular speed
## [code]w[/code] is followed at a constant lag of about [code]w / rate[/code]
## radians. At 2.0, a prisoner sprinting the deck (11 m/s at r=44, so
## w = 0.25 rad/s) is followed about 7 degrees behind -- enough that the ball is
## visibly turning the whole time they run, and enough that a change of direction
## shows as a swing. A big jump, such as a respawn across the ring, takes about a
## second and a half to settle.
##
## [b]It cannot overshoot or wobble.[/b] This is a first-order approach, not a
## spring: every step moves some fraction of the way along the single shortest arc
## to the target and never past it. That is deliberate. An eye that overshoots and
## rocks back reads as a servo with slack in it; an eye that decelerates onto you
## reads as something that decided to look. [code]tests/test_watching_eye.gd[/code]
## drives five seconds of it and asserts the remaining angle never once grows.
##
## The form is [code]1 - exp(-rate * delta)[/code] rather than
## [code]rate * delta[/code] so the result is identical at 30 fps and at 240; the
## naive version lags further on a slower machine, which is a difference between
## players nobody chose.
@export_range(0.0, 30.0, 0.5) var track_rate: float = 2.0

## Horizontal radius, in metres, of the column of space that counts as "on the
## tower" -- the volume the eye refuses to watch anybody inside.
##
## 9.0 is the half-width of [PanopticonEye]'s 18 m box, so the excluded column is
## exactly the footprint of the guard's cover. The nearest a prisoner can get is
## the inner kerb at r=35, so there are 26 m of margin before this can ever
## exclude somebody it should be watching.
@export_range(0.0, 34.0, 0.5) var tower_radius_metres: float = 9.0

## Bottom of that column, in metres above the tower node's local origin.
##
## Negative, and generously so. Its only job is to let the courtyard floor out:
## that floor is 12.5 m below the deck and spans r=0..35, so a body down there is
## inside the radius above and must still be watched -- it is a prisoner who fell,
## not the guard. -4.0 clears the platform slab (underside at y=-1) with room for
## the tower to be raised a little without the band having to be retuned.
@export_range(-40.0, 0.0, 0.5) var tower_band_low_metres: float = -4.0

## Top of that column, in metres above the tower node's local origin.
##
## Only has to clear the top of a jumping guard's head (y=3.16 with the tuned
## movement profile) and any future stand raised above it. 24.0 is far more than
## either; nothing but the guard is ever inside a 9 m radius of the tower axis and
## above the platform, so making this generous costs nothing and survives another
## agent raising the tower.
@export_range(0.0, 60.0, 0.5) var tower_band_high_metres: float = 24.0
