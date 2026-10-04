# Map 4: the Ice

An ice cavern: what map 1 does in rock, in ice (Ryan: "ice cavern, not a rock cavern with ice ... just like
thell rock, but with ice"). Every wall, rim, gate and floor surface is blue ice; snow only as contrast
(Ryan: "blue ice, potentially transparent, not white snow as much"). The gimmick will be ice physics; not
in this pass. No cover, traps or obstacles: Ryan designs the level. World coordinates, Godot y up; bearings
as map 1 (`pol(bearing, r, z)`). Every open number is map 1's.

Pass 3. Pass 1 (a lathed blockout) was reverted; pass 2 kept its roof (Ryan: "the roof is very cool") and
lost its grey serac walls, its photo textures and its lighthouse, and had no cells.

1. One sculpt, four chunks (decision 84): `tools/modelling/maps/ice/ice_build.py` builds ONE closed mesh
   (components 1, no open edge) and exports it as `ice_ground.glb`, `ice_wall.glb`, `ice_gate.glb` and
   `ice_roof.glb`, sharing their seam vertices. `tools/modelling/model build ice [--chunk wall]`;
   `python3 tools/modelling/maps/ice/ice_build.py --check` proves the mesh without Blender.
2. Nothing is a circle. The rim is 34 straight-fronted slabs set en echelon (each turned up to 15 deg off the
   tangent and pushed 0.5..2.4 m out over the pit), a crevasse notch between most; a notch's cleft runs
   9..22 m down the pit wall and a blue vein runs on into the lane. The wall is 10 piers (the roof's keels
   spring from them) with a bay of flat faces between each pair: faces 6..11 deg wide, set back 0.4..3.1 m,
   turned up to 8 deg, stepping past one another at an arris; the lane's edges are those two broken lines.
3. Lane: lake ice at y 23.0, never narrower than map 1's r 46.7..57.3 (the lip only ever stands further
   out, the wall foot only ever further back). The collider is flat on the sculpt's own lip and foot lines.
4. Wall: 12 rows from the lane to the roof's spring ring (11.6 m at a pier, up to 16.8 m under a vault),
   a cove off the foot, upright to 4 m and then leaning in to the ring, darker into the roof's thick rim.
5. Cells, as map 1's: an arched mouth cut through the ice, splayed reveals back to a screen 0.45..0.8 m
   behind it, ice bars (two faces meeting on a ridge that stands 0.08..0.24 m off the screen) and cold
   light between them (`ice_glow_albedo`, albedo and emission, as map 1's HellGlow). A cell replaces a block
   of the wall's own quads and shares every vertex with it: sill row, springing row, head row, 2..4 columns
   wide; no two share an arch (crown 0.78..0.95 of the way to the head, superellipse 1.7..2.6, lopsided),
   a sill or a head height. Three tiers in the wall (rows 2-4, 5-7 and, where the vault has risen 3 m,
   8-10 on the lean) packed along every face with a column of ice between two; three tiers in the pit
   wall (y 15..20, 7..13, 0..5) clear of the crevasse notches and the calved shelves.
6. Pit: blue ice at each slab's head, dark ice below y 8 +- 5, calved shelves with snow on them, icicles
   under the cornice, a frozen pool of pressure plates at y -11.05 under the fog.
7. Roof (unchanged from pass 2 but for its tile, redrawn to the same read): an ice-cave ceiling, not a
   dome of revolution. It springs from the wall's head on a line that rises 5 m in a vault between each
   pair of piers; a keel hangs from every pier and fades toward an oculus over the tower. Its scallops are
   the Delaunay dual of 611 sites. COLOR_0 carries how thin the ice is: rgb the light through it, alpha how
   much of `IceRoofOuter` shows (a bright shell 4 m above). `maps/ice/materials/ice_roof.gdshader`,
   unshaded. The piers and vault rises are fixed data in the build script so the roof cannot move.
8. Gate at 353 deg, map 1's idiom (a wall with slots cut through it, not bars): the lane's own surface
   rising between columns 351 and 355 into a screen of fused ice columns 0.9 m thick, each ridged down its
   middle, seven slots 0.34..0.44 m wide cut clean through it between 1.1 m and 6..8 m, a solid lintel to a
   ragged crest at 9.4 m, flaring over its last 2 m into the wall's own columns. Collider: one prism.
9. Icicles are spikes grown out of the faces they hang from (the wall's lean, the pit's cornice, the
   roof's keels); the roof's ride as their own node so the roof keeps its vertex alpha.
10. Tower, `ice_tower.glb` (`ice_tower_build.py`): map 1's tower in ice: a fused ice column on a
    7-corner plan of unequal fracture planes, five flutes standing 0.65..1.45 m proud on one side, map 1's
    waist, buttress blocks and shards at its foot under the pit floor; the guard chamber on map 1's datum
    (floor +1.70, eight arches at 25 + 45k, sill 2.35, crown 7.00) between unequal piers, a frozen ledge
    with an icicle fringe under the sill, a low dome of seven planes under a slumped snow cap.
11. Portal, `ice_portal.glb` + `maps/ice/props/ice_portal.tscn`: an ice arch round portal.glb's opening.
12. Light: flat cool ambient 0.7, one shadowed sun from bearing 150 at 62 deg (0.55), cool depth fog that
    thickens in the pit, a cold glow in the tower's chamber (`ice_tower_light_profile.tres`). Players stay
    unshaded. The lane's vertex colour carries the roof down the sun's line (`sun_pool`), and nine shafts
    (`maps/ice/props/ice_ray.tscn`, the forest streak's mesh and shader, cold tint) stand under the
    thinnest cells along the same line; they are scene nodes under `LightStreaks`, free to move.
13. Budget: ground 24776 (288 of them cell light), wall 21548 (896), gate 950, roof 5275 + 321 icicles +
    1368 shell, tower 7832, portal 610, shafts 324: 63004 drawn tris, 37 surfaces, one shadowed sun;
    107 cells in the wall, 29 in the pit. The `DRAW_BUDGETS` row is these counts off the built files + 20 %, not a suite
    measurement.

Textures: `maps/ice/textures/ice.ase`, drawn 256 px tiles (the glow 32 px, the swirl 64 px), 6..10 colours
each, 0.05 m per texel, nearest-filtered like map 1's (the roof's own shader stays linear); the table is in
`docs/TEXTURES.md`. Ryan repaints them in the sheet.
