class_name EyeProfile
extends Resource

## Every tunable of [PanopticonEye]: the picture, and how big the box is.
##
## There are two, and there used to be twelve. The eye was a lit red ball with a
## black band round it, a breathing glow and a full material model on each; on
## 2026-09-10 Ryan asked, for the third time, for something simpler -- "i dont
## want the cylinder, all i want is a one way mirror, it can be the simple jpg of
## an eye four times in a box if needed" -- and that is now literally what it is.
## A box with a picture of an eye on each side. Colour, polish, glow and pulse
## are gone because a picture already decides all of them, and a knob that no
## longer describes anything is worse than no knob.
##
## [b]What is deliberately not here[/b]
##
## There is no field on this resource that refers to the guard, to aim, to a
## camera, or to match state, and there must never be one. Prisoners have to fear
## being watched precisely because they cannot tell whether they are, and a
## single knob wired to where the guard is looking would end that.
##
## A box is not a solid of revolution, so unlike the old ball it does have four
## distinguishable sides -- which means this promise is now kept by [b]every side
## carrying the same picture[/b], not by the form. See [PanopticonEye] for how
## that is enforced rather than merely intended.

## The eye itself: one square image, drawn upright and unshaded on all four
## vertical faces of the box (and, incidentally, on its lid and its floor).
##
## Square, because it is stretched to fill each face and each face is square. It
## wants a dark, flat surround rather than a cut-out, since the surround is what
## the body of the box is made of and neighbouring faces meet at the image edge.
@export var eye_texture: Texture2D

## Uniform scale of the box, applied to the rig root.
##
## 1.0 is the authored form: an 8 m cube centred at y=16.7 -- the eye height the
## ring's own cover and kerb were cut against. This is the one number to turn
## when the question is "is it big enough to loom from the far side of the ring",
## and it moves the box's height with its width so the proportions never change.
##
## The lower bound is clearance, not taste. The box must stay entirely above the
## guard, whose camera reaches y=3.0 at the top of a jump; its underside sits at
## 12.7 * size_scale, so 0.5 leaves it more than twice as high as the guard can
## ever get. [code]tests/test_tower.gd[/code] asserts that across this whole
## range.
@export_range(0.5, 3.0, 0.05) var size_scale: float = 1.0
