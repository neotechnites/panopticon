class_name EyeProfile
extends Resource

## Every tunable of [PanopticonEye] -- what the tower looks like, not what it does.
##
## The eye is the game's title made physical, so how it reads is a design
## question and design questions on this project are data: see [MatchRules] for
## the seam. Nothing about the eye's colour, polish or pulse may be hard-coded
## in [PanopticonEye].
##
## [b]What is here and what is in the scene[/b]
##
## PROPORTION -- the radii and heights that make the silhouette an eye rather
## than a bollard -- is authored in [code]scenes/tower/panopticon_eye.tscn[/code],
## where a person can drag it and see it. Those numbers are interlocking: the
## lids only frame the iris because each rim is wider than the iris behind it,
## and pulling one of them out into a flat list of exports would let a tuner
## break the seal without noticing. So this resource carries the whole form's
## SIZE as one multiplier, and everything about its SURFACE.
##
## [b]What is deliberately not here[/b]
##
## There is no field on this resource that refers to the guard, to aim, to a
## camera, or to match state, and there must never be one. The tower is a
## one-way mirror: prisoners have to fear being watched precisely because they
## cannot tell whether they are, and a single knob wired to where the guard is
## looking would end that. See [PanopticonEye] for how the one-way property is
## enforced rather than merely intended.
##
## Colours are linear sRGB; rates are hertz.

# --- Size ---------------------------------------------------------------------

## Uniform scale of the whole eye, applied to the rig root.
##
## 1.0 is the authored form: 31 m tall, 21.6 m across at the brow, with the
## aperture at y=16.7 -- the eye height the ring's own cover was cut against.
## The proportions never change with this. It is the one number that answers
## "is the tower big enough to loom from the far side of the ring" without
## touching the geometry that makes it read as an eye.
##
## The lower bound is not taste, it is the seal: the socket wall is r=8.5 m and
## the platform the guard walks on is r=8.0 m, so anything under 0.95 pulls the
## wall inside the platform's edge and a guard who walks to the rail steps out
## of their own tower in full view of the ring. See [PanopticonEye].
@export_range(0.95, 1.3, 0.01) var size_scale: float = 1.0

# --- Shell --------------------------------------------------------------------

## The socket, the two lids and the crown: everything that is structure rather
## than glass. Deliberately close to the ring's own [code]MatStructure[/code]
## grey, so the eye reads as part of the building and the only thing that draws
## the look is the aperture.
@export_group("Shell")

@export var shell_color: Color = Color(0.17, 0.17, 0.19)

## Near-matte. The shell must not catch a highlight that competes with the iris.
@export_range(0.0, 1.0, 0.01) var shell_roughness: float = 0.85

# --- Iris ---------------------------------------------------------------------

## The mirrored band in the slot between the lids -- the eye itself.
@export_group("Iris")

@export var iris_color: Color = Color(0.07, 0.10, 0.14)

## Mirror strength. At 1.0 the iris takes its colour from what it reflects
## rather than from [member iris_color], which is what makes it read as glass
## instead of as paint. This is the number to pull down if the eye disappears
## against a dull sky.
@export_range(0.0, 1.0, 0.01) var iris_metallic: float = 0.95

## Polish. Low is a sharper, harder reflection.
@export_range(0.0, 1.0, 0.01) var iris_roughness: float = 0.16

## The light that leaks out of the glass, so the eye is legible from the far
## side of the ring at 95 m and in the tower's own shadow. This is the crest of
## the breath -- the brightest the eye ever gets -- so what is set here is what
## is seen. Emission is used
## rather than a real light because a [OmniLight3D] in the aperture would throw
## a lit patch onto the deck, and a lit patch that moved or brightened would be
## a signal about the tower -- see the class doc of [PanopticonEye].
@export var iris_glow: Color = Color(0.55, 0.72, 0.85)

@export_range(0.0, 8.0, 0.05) var iris_glow_energy: float = 0.55

# --- Pupil --------------------------------------------------------------------

## The black band across the middle of the iris. It is what turns a lit ring
## into an eye: without it the aperture reads as a window.
@export_group("Pupil")

@export var pupil_color: Color = Color(0.02, 0.02, 0.025)

@export_range(0.0, 1.0, 0.01) var pupil_metallic: float = 1.0

@export_range(0.0, 1.0, 0.01) var pupil_roughness: float = 0.05

# --- Pulse --------------------------------------------------------------------

## A slow breath in the iris glow.
##
## [b]This is the one moving part of the eye, and it is driven by the wall clock
## alone.[/b] It is deliberately ignorant: it does not know whether a guard is
## in the tower, where they are looking, whether they have fired, or whether the
## round has started. A prisoner who watches the pulse for a hundred hours
## learns nothing from it, which is the only reason it is allowed to exist.
##
## It is here because a light that is perfectly constant reads as a lamp, and
## the eye has to read as something awake.
@export_group("Pulse")

## Breaths per second. Set to 0.0 to hold the glow perfectly still.
@export_range(0.0, 2.0, 0.005) var pulse_hz: float = 0.09

## How far the glow falls below [member iris_glow_energy] at the bottom of the
## breath, as a fraction of it. 0.0 also holds the glow still.
@export_range(0.0, 1.0, 0.01) var pulse_depth: float = 0.28
