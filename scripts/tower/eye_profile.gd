class_name EyeProfile
extends Resource

## Every tunable of [PanopticonEye]: the picture, and how big the box is.
##
## There are two, and there used to be twelve. The eye was a lit red ball with a
## black band round it, a breathing glow and a full material model on each; on
## 2026-09-10 Ryan asked, for the third time, for something simpler -- "i dont
## want the cylinder, all i want is a one way mirror, it can be the simple jpg of
## an eye four times in a box if needed" -- and then, having seen the box, "the
## eye box is right but should be at eye level, and be a one way mirror to cover
## the shooter". So it is a box with a picture of an eye on each side, standing
## on the tower platform at the guard's own eye height with the guard inside it.
## Colour, polish, glow and pulse are gone because a picture already decides all
## of them, and a knob that no longer describes anything is worse than no knob.
##
## [b]What is deliberately not here[/b]
##
## There is no field on this resource that refers to the guard's camera, to aim,
## or to match state, and there must never be one. Prisoners have to fear being
## watched precisely because they cannot tell whether they are, and a single knob
## wired to where the tower is looking would end that.
##
## A box is not a solid of revolution, so unlike the old ball it does have four
## distinguishable sides -- which means this promise is now kept by [b]every side
## carrying the same picture[/b], not by the form. See [PanopticonEye] for how
## that is enforced rather than merely intended.

## The eye itself: one square image, drawn upright and unshaded, repeated along
## each of the four vertical faces of the box.
##
## Square, because [PanopticonEye] sizes the tiling so that every copy comes out
## square whatever the box's proportions -- a picture stretched four times wider
## than it is tall does not read as an eye. It wants a dark, flat surround rather
## than a cut-out, since the surround is what the body of the box is made of and
## neighbouring copies meet at the image edge.
@export var eye_texture: Texture2D

## Uniform scale of the box, applied to the rig root.
##
## 1.0 is the authored form: 18 m across and 4.5 m tall, centred at y=1.9 -- the
## guard's own eye height -- so it stands over the whole 8 m platform with a
## metre to spare in every direction and its four rows of pupils level with the
## eyes of everyone on the deck.
##
## [b]The lower bound is cover, not taste.[/b] The box's job is to hide the guard,
## and it can only do that while it still encloses the platform the guard walks
## on and still stands taller than the guard's head at the top of a jump. At 1.0
## it clears both by about a metre; below 1.0 it starts letting the guard out of
## their own cover, so 1.0 is the floor. [code]tests/test_tower.gd[/code] asserts
## the cover holds across this whole range.
@export_range(1.0, 2.0, 0.05) var size_scale: float = 1.0
