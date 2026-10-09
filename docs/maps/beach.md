# Map 4: the Beach

A bay between two curved sand jetties that run out from a beach; the island rises behind a low wall of
stacked beach rock; the guard keeps the flybridge of a yacht anchored in the bay (Ryan: "boat anchored in
basically a bay ... they run from one end of a curved beach to the other, not making a full 360").
Palms, rock, beach props, a moving GameCube-era sea (Ryan: "think mario sunshine and sonic adventure"); no roof. World coordinates, Godot y up; bearings as
the scene's markers (`pol(bearing, r, z)`); the mouth faces bearing 0.

1. One sculpt, six chunks (decision 84): `tools/modelling/maps/beach/beach_build.py` exports
   `beach_ground.glb` (shelf, sand, the wall's core, the jetty heads), `beach_island.glb`, `beach_rocks.glb`,
   `beach_palms.glb`, `beach_props.glb` and `beach_water.glb`. `tools/modelling/model build beach [--chunk island]`;
   `python3 tools/modelling/maps/beach/beach_build.py --check` proves it without Blender.
2. Lap: sand at y 23.0, lane r 68.5 from 60 to 300 deg (287 m, map 1's 299 m); start and portal at the
   jetty tips, a rock knoll beyond each. The mouth spans the other 120 deg.
3. Shore: waterline r 63.5 (wandering 0.8), 8 to 14 m of wadeable shallows, ending in a drop-off ledge exactly
   at the death line (`LEDGE` in `beach_build.py`: the shelf eases to 1.4 m, falls to 3.4 m over 0.7 m, showing through
   the water's soft gradient, no line drawn on it; `LEDGE = False` and a rebuild restores the soft slope, or revert 7362728f). KillBox: roof 1.6 m under the surface (y 21.0), 10 to 16 m out from the waterline past the shallows, r 600: the bay and the open sea are the pit.
4. Wall: foot r 74.1, 10.6 m of sand from the waterline. Two courses of stones (each its own size, lean,
   broken faces and tone, darker and warmer at the foot) on a low core; tops 1.6..2.2 m; the island's ground behind sits at 1.55 m.
   Collider: a sheer face 3.4 m tall just in front of the stones.
5. Island: the jetties carry a narrow grass strip; the big island behind the beach rises into ridged hills
   (40..105 m) under a canopy of crowns, three greens, valleys darker, haze far off. Palms: clusters along
   the wall, leaning palms on the sand at its foot, singles on the slopes.
6. Sea (Hanauma Bay was the reference for water behaviour only): 8 to 14 m of wadeable shallows, a sandy
   bed 2 to 3 m deep across the back half, deepening from mid-bay to 12 m between the jetty tips and 22 m
   at sea, a 5.5 m anchorage under the yacht, a few coral patches (low heads, `beach_reef_albedo`).
   Built the way the GameCube drew water (Flipper: fixed-function TEV, 8 stages, ~1 MB texture cache;
   every texture here is 256 px or less):
   - depth colour: vertex colour baked by `beach_build.py` (COLOR; dark blue fading in over 44 m, full
     8 m mouth-side of the yacht). See-through: per vertex from the length of the view path through the water (depth in
     UV2.x / sin of the view's elevation, Beer-Lambert; `extinction` = 7.5 m in `beach_water.gdshader`),
     as the GameCube's per-vertex fog; the bed's tint and absorption likewise baked into its
     vertex colours, and its caustic weight into UV2.x.
   - refraction: one copy of the frame (EFB copy; `hint_screen_texture`) read through a scrolling offset
     texture (`beach_water_normal`), as Sunshine's indirect texturing.
   - surface: two scrolling ripple layers; a sparkle layer (`beach_water`) offset by them (EMBM-style
     glints), lit along the sun's path by a per-vertex glint and the sky by a per-vertex fresnel (the
     transform unit's vertex lighting); a vertex swell (CPU vertex animation on the GameCube).
   - caustics: two scrolling copies of `beach_water` on the bed at two scales, weighted per vertex.
   - foam and waves: textured strips (`beach_waves.glb`, `beach_wave_albedo`) with animated UVs and
     fades, a standing lace band (`beach_foam_albedo`) at the waterline, lace rings round rocks (UV2.y).
   - geometry: 11.4k water triangles, 2 deg columns at the shore.
7. Sky: `maps/beach/materials/beach_sky.gdshader`, a gradient, no clouds. The sun (bearing 15, 35 deg up, the DirectionalLight's) is Sunshine's: `beach_sun.gdshader`, a
   soft sprite (core, halo, star rays to ~11 deg, all tapering to nothing) square to the camera 2.5 km out, and `beach_sun_glare.gdshader`, a
   screen wash and rays that rise as the view turns to it (`glare_strength` 0.55 dead-on, gone by
   `glare_degrees` 22), cut by five depth taps at the sun's screen position when it is hidden. Linear tonemap; GL Compatibility.
8. Tower: the yacht (`beach_yacht_build.py`), a stylized Prestige 680 (rounded flared hull, dark window slots,
   red boot stripe, blue saloon glass, rolled flybridge, winged hardtop, chunky rails), broadside to the beach,
   static, no chain, lace round its waterline (`yacht_foam` in `beach_build.py`); its collider is unchanged. Flybridge floor on the tower datum (y 27.05), an open rail with a 0.65 m
   collider (the towers' sill). `Tower` is a plain node: no window plugs.
9. Portal: `beach_portal.glb` + `maps/beach/props/beach_portal.tscn`, a sea arch of beach rock.
10. Props (`beach_props.glb`): seven umbrella sets (loungers, towels, coolers) on the wall side of the
    sand, 3 m and more off the lane; driftwood at the wall's foot and two logs by the water; shells; a tiki
    bar 7 m short of the portal. Collider: loungers, coolers, poles, posts, the counter, logs.
11. Import: Godot drops the first surface's vertex colour on import, so `beach.tscn` restates surface 0 of
    the ground (rock), the island (grass) and the props (canvas).

Display: Ryan plays on a Windows HDR desktop that shows SDR at 2x linear (`scripts/fx/mac_lift.gdshader`).
Sun 0.185 and ambient 0.16 light for it; the unshaded sky, sea, sun and underwater shells scale by 0.73
(`display_gain`). Judge captures through that lift, never raw.

Style (after the forest map): chunky palms (fat ringed trunks, 7-8 broad fronds), bulbous rounded rocks, rolling
round hills and blob canopy, and a stepped palette (`PAL_*` in `beach_build.py`: sand 3, grass 2, canopy 4, haze 2,
rock 3 bands, fronds 2) instead of gradients. Banded water is a switch: `banded` on `WaterMat` in `beach.tscn`
(default off; the water as it was is tagged `beach-water-pre-stylize`).

Textures: `maps/beach/textures/beach.ase`, 256 px tiles at 0.05 m per texel, placeholders for Ryan to
repaint; the table is in `docs/TEXTURES.md`.

## Sunset trial (branch beach-sunset; midday is tag beach-midday)

Golden hour, tuned in plain SDR (no HDR lift) against raw frames of hell, forest and marble. Sun 7 deg up at
bearing 15 over the mouth, orange (1, 0.62, 0.34) at 1.5; ambient purple-blue (0.48, 0.45, 0.85) at 0.11.
Sky violet to rose to orange-gold round the sun, no clouds. Water: the baked colour graded to dark teal
(`body_tint`), warm sky in the reflection, a glitter path to the sun (`path_strength`). Sand graded warm tan
(`grade`), caustics faint and warm, grass olive (GrassMat albedo_color), foam warm. Geometry untouched.
