# Map 4: the Ice

An ice cavern: what map 1 does in rock, in ice (Ryan: "ice cavern, not a rock cavern with ice ... just like
thell rock, but with ice"). Every wall, rim, gate and floor surface is blue ice; snow only as contrast
(Ryan: "blue ice, potentially transparent, not white snow as much"). The gimmick will be ice physics; not
in this pass. No cover, traps or obstacles: Ryan designs the level. World coordinates, Godot y up; bearings
as map 1 (`pol(bearing, r, z)`). Every open number is map 1's.

Pass 5: the lane is a corridor cut through a solid block of ice, as in every other map (hell's
`CEIL_H` gallery, marble's cut walkway): cells over a runner's head, not the dome (Ryan: "the lane is a
corridor cut through a solid block of ice"). Pass 4's open ring room and its crevassed rim are gone.

1. One sculpt, five chunks (decision 84): `tools/modelling/maps/ice/ice_build.py` builds ONE closed mesh
   (components 1, no open edge) and exports `ice_ground.glb`, `ice_wall.glb`, `ice_block.glb`,
   `ice_gate.glb` and `ice_roof.glb`, sharing their seam vertices. `tools/modelling/model build ice
   [--chunk block]`; `python3 tools/modelling/maps/ice/ice_build.py --check` proves the mesh without Blender.
2. Lip: an imperfect smooth circle, r 44.56..46.11: INNER_R less 0.15 m and a wander of four low ring
   harmonics (`LIP_WAVES`). No slabs, notches or crevasses; not a polygon (one vertex a degree).
3. Lane: lake ice at y 23.0 from the lip to the wall at 57.6. The collider is flat on the sculpt's lip line.
4. Corridor: the outer wall a smooth upright cylinder, r 57.6, 8.5 m to a flat smooth ice ceiling at
   y 31.5 (hell's `CEIL_H`) that runs in to the lip's line (`ice_wall.glb`); colliders for both.
5. Cells: rooms cut into the ice like map 1's and marble's. An arched mouth (crown 0.78..0.95 of the way
   to the head, superellipse 1.7..2.6, lopsided), a level room 2.6..3.4 m deep behind it (floor, side
   walls, a vault, a back wall lit by `ice_glow_albedo`), and square ice bars 0.2..0.3 m wide, 0.18 m
   thick, 0.4 m in from floor to vault. Two tiers in the corridor wall (sill 1.1 / 4.7 m, 140 cells, clear
   of the gate); three tiers in the block's face over the corridor (sills 1.1 / 4.7 / 8.3 m over the
   ceiling, 168 cells); three in the pit wall (y 15..20, 7..13, 0..5, 101 cells).
6. Block (`ice_block.glb`): the corridor's ceiling edge rises as the block's inner face, smooth cut ice
   on the lip's line, 12.3 m to the spring line at y 43.8, looking across the pit at the tower.
   Pit: smooth cut ice under the lip carrying its wander down, blue over dark ice (y 8 +- 5), the frozen
   pool of pressure plates at y -11.05 under the fog.
7. Roof: one smooth carved shell sprung from the block's top to y 61, a 2.2 m raised cupola over the
   tower (the oculus). COLOR_0 carries how thin the ice is: rgb the light through it, alpha how much of
   `IceRoofOuter` shows (a bright shell 4 m above); the cupola is the thinnest, brightest ice.
   `maps/ice/materials/ice_roof.gdshader`, unshaded.
8. Gate at 353 deg, map 1's idiom (a wall with slots cut through it, not bars): the lane's own surface
   rising between columns 351 and 355 into a screen of fused ice columns 0.9 m thick, each ridged down its
   middle, seven slots 0.34..0.44 m wide cut clean through it between 1.1 m and 4..6.3 m, a solid lintel to a
   ragged crest at 7.5 m (under the ceiling), flaring over its last 2 m into the wall's own columns.
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
12. Budget (`--check`): ground 34602, wall 27182, block 32858, gate 950, roof 2544 + 1368 shell: 99504
    map tris, plus tower 6112, portal 596, shafts 324. Over pass 3's `DRAW_BUDGETS` row (63004).

Textures: `maps/ice/textures/ice.ase`, drawn 256 px tiles (the glow 32 px, the swirl 64 px), 6..10 colours
each, 0.05 m per texel, nearest-filtered like map 1's (the roof's own shader stays linear); the table is in
`docs/TEXTURES.md`. Ryan repaints them in the sheet.
