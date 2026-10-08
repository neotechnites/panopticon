# Map 4: the Ice

An ice cavern: what map 1 does in rock, in ice (Ryan: "ice cavern, not a rock cavern with ice ... just like
thell rock, but with ice"). Every wall, rim, gate and floor surface is blue ice; snow only as contrast
(Ryan: "blue ice, potentially transparent, not white snow as much"). The gimmick will be ice physics; not
in this pass. No cover, traps or obstacles: Ryan designs the level. World coordinates, Godot y up; bearings
as map 1 (`pol(bearing, r, z)`). Every open number is map 1's.

Pass 4: the runners are in a tall ring room with a ceiling, not inside a dome (Ryan: a cutout of a
cylinder like hell and marble, carved from a block of ice, no icicles). Pass 3's leaning faceted wall,
scalloped roof, keels and icicles are gone.

1. One sculpt, four chunks (decision 84): `tools/modelling/maps/ice/ice_build.py` builds ONE closed mesh
   (components 1, no open edge) and exports it as `ice_ground.glb`, `ice_wall.glb`, `ice_gate.glb` and
   `ice_roof.glb`, sharing their seam vertices. `tools/modelling/model build ice [--chunk wall]`;
   `python3 tools/modelling/maps/ice/ice_build.py --check` proves the mesh without Blender.
2. The rim is not a circle: 34 straight-fronted slabs set en echelon (each turned up to 15 deg off the
   tangent and pushed 0.5..2.4 m out over the pit), a crevasse notch between most; a notch's cleft runs
   9..22 m down the pit wall and a blue vein runs on into the lane.
3. Lane: lake ice at y 23.0, r from the lip (never outside 46.7) to the wall at 57.6. The collider is flat
   on the sculpt's own lip line; the wall's collider is its own face.
4. Wall: a smooth upright cylinder, r 57.6, cut clean (no facets), 8.5 m from the lane to the spring line
   at y 31.5 (map 1's ceiling height), darker into the dome's thick rim.
5. Cells: rooms cut into the ice like map 1's and marble's. An arched mouth (crown 0.78..0.95 of the way
   to the head, superellipse 1.7..2.6, lopsided), a level room 2.6..3.4 m deep behind it (floor, side
   walls, a vault that carries the arch back, a back wall lit by `ice_glow_albedo`), and square ice bars
   0.2..0.3 m wide, 0.18 m thick, standing 0.4 m in from floor to vault. A mouth replaces a block of the
   wall's quads and shares every vertex with it. Two tiers in the wall (sill 1.1 / 4.7 m) packed round
   the ring clear of the gate; three tiers in the pit wall (y 15..20, 7..13, 0..5) clear of the crevasse
   notches and the calved shelves.
6. Pit: blue ice at each slab's head, dark ice below y 8 +- 5, calved shelves with snow on them, a frozen
   pool of pressure plates at y -11.05 under the fog.
7. Roof: one smooth carved shell sprung from the wall's top ring to y 61, a 2.2 m raised cupola over the
   tower (the oculus). COLOR_0 carries how thin the ice is: rgb the light through it, alpha how much of
   `IceRoofOuter` shows (a bright shell 4 m above); the cupola is the thinnest, brightest ice.
   `maps/ice/materials/ice_roof.gdshader`, unshaded.
8. Gate at 353 deg, map 1's idiom (a wall with slots cut through it, not bars): the lane's own surface
   rising between columns 351 and 355 into a screen of fused ice columns 0.9 m thick, each ridged down its
   middle, seven slots 0.34..0.44 m wide cut clean through it between 1.1 m and 4..6.3 m, a solid lintel to a
   ragged crest at 7.5 m (under the spring line), flaring over its last 2 m into the wall's own columns.
   Collider: one prism.
9. Tower, `ice_tower.glb` (`ice_tower_build.py`): map 1's tower in ice: a fused ice column on a
    7-corner plan of unequal fracture planes, five flutes standing 0.65..1.45 m proud on one side, map 1's
    waist, buttress blocks and shards at its foot under the pit floor; the guard chamber on map 1's datum
    (floor +1.70, eight arches at 25 + 45k, sill 2.35, crown 7.00) between unequal piers, a frozen ledge
    under the sill, a low dome of seven planes under a slumped snow cap.
10. Portal, `ice_portal.glb` + `maps/ice/props/ice_portal.tscn`: an ice arch round portal.glb's opening.
11. Light: flat cool ambient 0.7, one shadowed sun from bearing 150 at 62 deg (0.55), cool depth fog that
    thickens in the pit, a cold glow in the tower's chamber (`ice_tower_light_profile.tres`). Players stay
    unshaded. The lane's vertex colour carries the roof down the sun's line (`sun_pool`), and nine shafts
    (`maps/ice/props/ice_ray.tscn`, the forest streak's mesh and shader, cold tint) stand under the
    thinnest ice along the same line; they are scene nodes under `LightStreaks`, free to move.
12. Budget (`--check`, the tower's and the portal's own counts): ground 23616 (538 of them cell light),
    wall 25742 (2432), gate 950, roof 2544 + 1368 shell, tower 6112, portal 596, shafts 324: 61252 tris;
    140 cells in the wall, 29 in the pit. The `DRAW_BUDGETS` row (pass 3, 63004) still holds.

Textures: `maps/ice/textures/ice.ase`, drawn 256 px tiles (the glow 32 px, the swirl 64 px), 6..10 colours
each, 0.05 m per texel, nearest-filtered like map 1's (the roof's own shader stays linear); the table is in
`docs/TEXTURES.md`. Ryan repaints them in the sheet.
