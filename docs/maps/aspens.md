# Map 6: the Aspens (first pass)

Ryan, 2026-11-25: "a big forest, where each person starts at a different spot in the forest, all eqidistant
from teh tower, which in this case will be closer to the ground, then they all have to run directly at the
tower, in a straight line ... for this first pass, it will just be the forest, with a short tower in the
middle, that can be, lets say a tree stump. no roof ... skybox". "the tree colors hsould be like the istock
image, the ground colors should be like the minegraft grass. dont worry about falling leaves right now. no
cells on this right now."

In this pass: the grove, the ground, the stump, the sky. Not in it: cells, falling leaves, traps, gates, a
ring, a pit, cover design, the straight-run mode. World coordinates, Godot y up; bearings as map 1.

1. One sculpt, 14 chunks (decision 84): `tools/modelling/maps/aspens/aspens_build.py` builds one scene and
   exports `aspens_ground.glb`, `aspens_stump.glb`, `aspens_near0..7.glb` (45 deg each) and
   `aspens_far0..3.glb` (90 deg each); `--check` prints the counts and the sightlines without Blender.
2. Ground: rings from the stump's own foot ring (shared positions) to r 900, y 23.0, rolling +-0.45 m over
   ~46 m; flat at the stump and on r 104..116. Olive and green grass by vertex colour over one tile.
3. Stump (`Tower/Stump`): a giant aspen's, sawn flat. Cut face y 25.0 (2.0 m over the ground), r 2.25 m;
   seven roots run out to r 3.4..3.95 into the ground. The guard stands on the face: eye 3.65 m over the
   ground (5.95 m on the rings). No wall, no roof: he can step off.
4. Trees: five modelled aspens (13..23.5 m, trunks 0.24..0.50 m at the foot, five-sided, leaves from 6..12 m
   up in 4..7 faceted masses, thin dark limbs) placed turned and scaled 0.88..1.12; 1425 of them out to
   r 138. Past that 2451 far trees (four-sided trunk, two leaf masses, leaves lower toward the edge) to r 215.
   Trunks are colliders to 8 m; leaves are not.
5. Light: flat white ambient 0.44, one shadowed sun 0.22 from bearing 140 at 50 deg, linear tonemap, depth
   fog 70..380 m at 0.8 in the photo's far gold, `aspens_sky.gdshader` (pale gradient). A `NoSun` at energy 0.
   Authored for the 2x display lift (`scripts/fx/mac_lift.gdshader`).
6. The match engine still runs its ring: `Route/Level1` lays it at the start distance (r 110, 5 to 335 deg)
   so a loaded match spawns among the trees. The straight run is not built.

## Size

| | |
|---|---|
| runner | 11 m/s (`default_movement_profile.tres`), 1.8 m tall, 0.5 m across |
| today's ring | lane r 52 (beach 68.5): a 330 deg lap is 299.5 m, 27.2 s |
| camera | 100 deg unscoped, 20 deg scoped (`default_zoom_profile.tres`, x 0.2) |
| a runner on screen at 1080p | 816 / d px tall unscoped, 5512 / d scoped: 15.7 and 106 px on the ring |
| a full lap's run (299.5 m) | 2.7 x 0.8 px unscoped: not drawn as a figure |
| start distance | **110 m: 10.0 s**. 7.4 x 2.1 px unscoped (the last distance a runner is 2 px wide), 50 x 14 px scoped |
| trunks | mean 0.36 m at chest; 0.0239 per m2 (5.1 m to the nearest neighbour, never under 4.2 m) |
| sightlines from the stump | clear on 80 % of bearings to 30 m, 65 % to 55 m, 40 % to 110 m |

Spacing is set so a sightline's mean clear run (1 / (density x trunk width)) equals the start distance.

## Colours (sRGB, measured)

| | reference | texture |
|---|---|---|
| trunk, lit / shade | istock (216, 209, 199) / (190, 179, 167) | bark (205, 198, 190), (190, 180, 169) |
| knots | istock (48, 34, 23) | (47, 34, 23) |
| leaves, all / bright / mid | istock (227, 162, 10) / (247, 189, 7) / (208, 149, 12) | leaf (250, 180, 10), (252, 204, 34), (226, 160, 14) |
| grass, olive / green / dry tuft | frame0 (120, 111, 48) / (74, 89, 39) / (160, 145, 65) | grass (135, 127, 49), vertex green, (159, 152, 79) |
| sky, top / horizon | istock (214, 209, 235) / (246, 244, 239) | the shader's two colours |
| far haze | istock, between the far trunks (244, 179, 75) | the fog |

Textures: `maps/aspens/textures/aspens.ase`, four drawn placeholder tiles at 0.05 m per texel for Ryan to
replace; `maps/aspens/textures/PIPELINE.md`.
