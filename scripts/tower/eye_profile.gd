class_name EyeProfile
extends Resource

## Every tunable of [PanopticonEye] -- what the eye looks like, not what it does.
##
## The eye is the game's title made physical, so how it reads is a design
## question and design questions on this project are data: see [MatchRules] for
## the seam. Nothing about the eye's colour, size or pulse may be hard-coded in
## [PanopticonEye].
##
## [b]What is deliberately not here[/b]
##
## There is no field on this resource that refers to the guard, to aim, to a
## camera, or to match state, and there must never be one. Prisoners have to fear
## being watched precisely because they cannot tell whether they are, and a
## single knob wired to where the guard is looking would end that. See
## [PanopticonEye] for how that is enforced rather than merely intended.
##
## Colours are linear sRGB; rates are hertz.

# --- Size ---------------------------------------------------------------------

## Uniform scale of the whole eye, applied to the rig root.
##
## 1.0 is the authored form: a ball 8 m across with its pupil at y=16.7 -- the
## eye height the ring's own cover and kerb were cut against. This is the one
## number to turn when the question is "is it big enough to loom from the far
## side of the ring", and it moves the eye's height with its radius so the
## proportions never change.
##
## The lower bound is clearance, not taste. The eye must stay entirely above the
## guard, whose camera reaches y=3.0 at the top of a jump; the bottom of the ball
## sits at 12.7 * size_scale, so 0.5 leaves it more than twice as high as the
## guard can ever get. [code]tests/test_tower.gd[/code] asserts that across this
## whole range.
@export_range(0.5, 3.0, 0.05) var size_scale: float = 1.0

# --- Iris ---------------------------------------------------------------------

## The ball itself.
@export_group("Iris")

## Red, because that is what was asked for. The old blue-grey mirror finish went
## with the tower.
@export var iris_color: Color = Color(0.36, 0.04, 0.04)

## Mirror strength. Kept low so the eye reads as its own colour rather than as
## whatever it is reflecting -- at 0.95 it takes the sky's grey and stops being
## red at all.
@export_range(0.0, 1.0, 0.01) var iris_metallic: float = 0.1

## Polish. Low is a sharper, harder highlight.
@export_range(0.0, 1.0, 0.01) var iris_roughness: float = 0.4

## The light that leaks out of it, so the eye is legible from the far side of the
## ring at 95 m and in shadow. This is the crest of the breath -- the brightest
## the eye ever gets -- so what is set here is what is seen. Emission is used
## rather than a real light because an [OmniLight3D] would throw a lit patch onto
## the deck, and a lit patch that moved or brightened would be a signal about the
## tower -- see the class doc of [PanopticonEye].
@export var iris_glow: Color = Color(1.0, 0.11, 0.07)

@export_range(0.0, 8.0, 0.05) var iris_glow_energy: float = 1.0

# --- Pupil --------------------------------------------------------------------

## The black band round the middle. It is what turns a red ball into an eye.
@export_group("Pupil")

@export var pupil_color: Color = Color(0.02, 0.02, 0.025)

@export_range(0.0, 1.0, 0.01) var pupil_metallic: float = 0.0

@export_range(0.0, 1.0, 0.01) var pupil_roughness: float = 0.35

# --- Pulse --------------------------------------------------------------------

## A slow breath in the glow.
##
## [b]This is the one moving part of the eye, and it is driven by the wall clock
## alone.[/b] It is deliberately ignorant: it does not know whether a guard is in
## the tower, where they are looking, whether they have fired, or whether the
## round has started. A prisoner who watches the pulse for a hundred hours learns
## nothing from it, which is the only reason it is allowed to exist.
##
## It is here because a light that is perfectly constant reads as a lamp, and the
## eye has to read as something awake.
@export_group("Pulse")

## Breaths per second. Set to 0.0 to hold the glow perfectly still.
@export_range(0.0, 2.0, 0.005) var pulse_hz: float = 0.09

## How far the glow falls below [member iris_glow_energy] at the bottom of the
## breath, as a fraction of it. 0.0 also holds the glow still.
@export_range(0.0, 1.0, 0.01) var pulse_depth: float = 0.28
