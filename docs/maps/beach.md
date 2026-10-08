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
3. Shore: waterline r 63.5 (wandering 0.8), 8 to 14 m of wadeable shallows about 1.1 m deep at their edge,
   then the slope to deep water. KillBox: roof 1.6 m under the surface (y 21.0), 10 to 16 m out from the waterline past the shallows, r 600: the bay and the open sea are the pit.
4. Wall: foot r 74.1, 10.6 m of sand from the waterline. Two courses of stones (each its own size, lean,
   broken faces and tone, darker and warmer at the foot) on a low core; tops 1.6..2.2 m; the island's ground behind sits at 1.55 m.
   Collider: a sheer face 3.4 m tall just in front of the stones.
5. Island: the jetties carry a narrow grass strip; the big island behind the beach rises into ridged hills
   (40..105 m) under a canopy of crowns, three greens, valleys darker, haze far off. Palms: clusters along
   the wall, leaning palms on the sand at its foot, singles on the slopes.
6. Sea, after Hanauma Bay: 8 to 14 m of wadeable shallows, then reef flats (`beach_reef_albedo`, dark
   heads with sand pockets, 55 low reef rock clusters) and pale sand channels 1.7 to 3.5 m deep across the
   inner bay, deepening out through the mouth to 16 m and more (the yacht rides in 12 m). The water never
   goes opaque in the bay: sand, reef and rock take the depth by absorption (`exp(-(0.3,0.07,0.055) m)`),
   the surface thickens slowly, and deep blue takes over only out through the mouth. Refraction (screen
   copy bent by ripples), bed caustics, swell, fresnel, glint and sparkle as before. The waves are
   `beach_waves.glb` + `beach_waves.gdshader` (two continuous trains along one shore strip).
7. Sky: `maps/beach/materials/beach_sky.gdshader`, a gradient and the drawn clouds (`beach_clouds_albedo.png`,
   RGBA). The sun (bearing 15, 35 deg up, the DirectionalLight's) is `beach_sun.gdshader`'s camera-square
   quad 2.5 km out, so the disc stays round at any FOV. Linear tonemap; GL Compatibility.
8. Tower: the yacht (`beach_yacht_build.py`, a generic placeholder after the Prestige 680), broadside to
   the beach, static, no chain. Flybridge floor on the tower datum (y 27.05), an open rail with a 0.65 m
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

Textures: `maps/beach/textures/beach.ase`, 256 px tiles at 0.05 m per texel, placeholders for Ryan to
repaint; the table is in `docs/TEXTURES.md`.
