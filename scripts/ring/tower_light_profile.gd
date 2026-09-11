class_name TowerLightProfile
extends Resource

## Every tunable of [TowerLight]: colour, brightness, reach and height.
##
## On 2026-09-10 Ryan asked for the only light source in the ring to be
## directly above the tower, and reddish: "the tower is watching, so the
## tower is the only thing that lights anything." One point source above the
## platform makes every shadow in the ring point outward, away from the
## tower -- a prisoner's cover is defined by where that single source is, not
## by an arbitrary sun. See [TowerLight] for how this is wired onto an
## [OmniLight3D], and [code]scenes/ring/bentham_ring.tscn[/code]'s
## [code]WorldEnvironment[/code] for the ambient side of the same decision
## (ambient is turned down hard and tinted to match, so it cannot become a
## second, colourless light source).
##
## Every number here is a starting point, not a measured constant the way
## [WeaponProfile]'s are -- nobody has run this renderer yet. Tune it in the
## editor against the actual GL Compatibility output rather than trusting the
## defaults shipped here.

## The colour of the one light in the scene. Warm red rather than pure
## spectral red (0,1,0 in G/B terms reads as near-black at range) so there is
## still enough per-channel signal at 35-60 m for the guard to resolve a
## prisoner's silhouette.
@export var color: Color = Color(0.9, 0.14, 0.08, 1.0)

## Multiplier on [member OmniLight3D.light_energy].
##
## [b]2026-09-10, corrected after the first real look at this:[/b] the first
## shipped value (12.0) read as total black -- only the unshaded eye box,
## unshaded trap blocks and the skybox were visible, i.e. everything that
## does NOT depend on a light at all. The cause was the combination of this
## number with [member attenuation]: Godot 4's omni falloff multiplies by
## [code]distance^-attenuation[/code], and at attenuation 1.0 across the
## 46-69 m band this light actually has to cover, that term alone divides
## the energy by roughly 45-70x before it ever reaches albedo and the NdotL
## term. 12.0 was nowhere near enough to survive that. Raised to 80.0, paired
## with [member attenuation] lowered to 0.5, to put real radiance on the deck
## at 35-60 m instead of a rounding error.
@export_range(0.0, 200.0, 0.5) var energy: float = 80.0

## [member OmniLight3D.omni_range], in metres. Must clear the straight-line
## distance from the light to the far side of the outer wall (r=62) or the
## edge of the ring goes to true black regardless of [member energy]. At the
## default height (30 m) that distance is ~69 m; this ships with generous
## headroom above that so the falloff curve is still doing something out at
## the wall rather than hitting a hard zero.
@export_range(10.0, 300.0, 1.0) var range_metres: float = 130.0

## [member OmniLight3D.omni_attenuation] -- the exponent on
## [code]distance^-attenuation[/code] in Godot 4's falloff. Godot's own
## default (1.0) is what made the first version of this light read as black:
## over the 46-69 m this light has to actually cover, an inverse-distance
## term that steep eats almost the entire energy budget before it reaches the
## deck. Lowered to 0.5 (a flatter, more "flood" falloff) so brightness stays
## closer to even across the whole ring instead of collapsing with distance.
## Raise it back toward 1.0-2.0 only if you also raise [member energy] to
## compensate, for a hotter core and a darker rim.
@export_range(0.1, 4.0, 0.05) var attenuation: float = 0.5

## Height above the tower's local origin, whose origin is the top of
## Tower/Platform. [TowerLight] is parented under Tower and places itself at
## (0, height_metres, 0) in that node's local space, so this number moves with
## the tower and never has to be re-derived when the tower is raised.
##
## [b]NEGATIVE, AND THAT IS THE WHOLE POINT NOW.[/b] The guard no longer stands
## on an open stage: they stand INSIDE a hollow chamber whose concealment is its
## walls, eleven splayed arrow-loops that make a body in there a smudge you can
## only find if you already know which slit to look at. A lamp in that room lights
## the guard from behind, and a lit figure in a dark slit is the most readable
## thing on the map -- the mechanic inverted by one number.
##
## So the glow is put BELOW the chamber floor. Tower/Platform is a 1 m slab
## spanning local y=-1 to y=0 with collision and this light casts shadows, so the
## floor the guard stands on is itself the occluder: nothing from this lamp
## reaches the room. What it does light is the column under the tower and the
## sky-facing underside of the stand, which is what makes the tower read as a lit
## thing from the galleries without lighting the one thing that has to stay dark.
##
## Its range is the other half. At -3 m the lamp is 45 m from the nearest deck
## corner and [member range_metres] would have to be raised a long way to reach
## it, so the galleries are lit by KeyLight, as they already were, and this is a
## local glow and nothing else.
@export_range(-40.0, 120.0, 0.1) var height_metres: float = -3.0

## Whether the tower light casts shadows at all. This is the one thing in
## this resource that is not free: a single shadow-casting light over CSG
## greybox geometry is cheap, but shadow-casting is also the entire point of
## "throws long shadows outward across the ring" -- turning it off would
## light the ring evenly and erase the reason to pick an [OmniLight3D] over
## flat ambient. Left on by default; exposed in case it costs more than
## expected on the target hardware.
@export var shadow_enabled: bool = true
