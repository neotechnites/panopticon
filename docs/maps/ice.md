# Map 4: the Ice

A glacier chamber under an ice-cave roof, a lighthouse locked in ice in the middle. Blue ice, snow only as
contrast (Ryan: "blue ice, potentially transparent, not white snow as much"). The gimmick will be ice physics;
not in this pass. No see-through cover. Ryan designs the level: nothing stands on the lane.
World coordinates, Godot y up; bearings as map 1 (`pol(bearing, r, z)`). Every open number is map 1's.

Pass 2 (the first, a lathed blockout, was reverted: "perfect cirlces. completely flat texture. tower inspired
by nothing. roof looks like fucking nothing").

1. One sculpt, four chunks (decision 84): `tools/modelling/maps/ice/ice_build.py` builds ONE closed mesh
   (components 1, no open edge) and exports it as `ice_ground.glb`, `ice_wall.glb`, `ice_gate.glb` and
   `ice_roof.glb`, sharing their seam vertices. `tools/modelling/model build ice [--chunk wall]`;
   `python3 tools/modelling/maps/ice/ice_build.py --check` proves the mesh without Blender.
2. Nothing is a circle. The rim is 34 straight-fronted slabs set en echelon (each turned up to 15 deg off the
   tangent and pushed 0.5..2.4 m out over the pit), a crevasse notch between most; a notch's cleft runs
   9..22 m down the pit wall and a blue vein runs on into the lane. The wall is flat-faced seracs between
   prows (the piers), set back 0..3.4 m, skewed, leaned, cleft, ledged and overhung; the lane's edges are
   those two broken lines.
3. Lane: lake ice at y 23.0, never narrower than map 1's r 46.7..57.3 (the lip only ever stands further
   out, the wall foot only ever further back). The collider is flat on the sculpt's own lip and foot lines.
4. Pit: pale firn at each slab's head, blue ice under it, dark ice below y 8 +- 5, calved shelves with
   snow on them, icicles under the cornice, a frozen pool of pressure plates at y -11.05 under the fog.
5. Roof: an ice-cave ceiling (Jokulsarlon), not a dome of revolution. It springs from the wall's head on a
   line that rises 5 m in a vault between each pair of prows; a keel hangs from every prow and fades toward
   an oculus over the tower. Its scallops are the Delaunay dual of 611 sites: every site a faceted dish
   pushed out along the surface normal, every crest a shared edge. COLOR_0 carries how thin the ice is: rgb
   the light through it, alpha how much of `IceRoofOuter` shows (a bright shell 4 m above: bare ice, snow
   drifts, the sun's glare on the bearing-150 side). `maps/ice/materials/ice_roof.gdshader`, unshaded.
6. Gate at 353 deg: a ragged serac ridge that IS the lane's surface, rising between columns 351 and 355
   and running into the wall's own columns. Collider: a prism r 43.6..58.8, 8.4 m tall.
7. Icicles are spikes grown out of the faces they hang from (wall overhangs, the pit's cornice, the
   roof's keels); the roof's ride as their own node so the roof keeps its vertex alpha.
8. Tower, `ice_tower.glb` (`ice_tower_build.py`): a pier light encased in wind-driven ice (the frozen
   lights of Lake Michigan): red riveted shaft, gallery, glazed lantern as the guard room on map 1's datum
   (floor +1.70, eight openings at 25 + 45k), cupola; tiered icicle curtains heavy on the bearing-200 side.
9. Portal, `ice_portal.glb` + `maps/ice/props/ice_portal.tscn`: a glacier arch round portal.glb's opening.
10. Light: flat cool ambient 0.7, one shadowed sun from bearing 150 at 62 deg (0.55), cool depth fog that
    thickens in the pit, the lighthouse lamp warm (`ice_tower_light_profile.tres`). Players stay unshaded.
    The lane's vertex colour carries the roof down the sun's line (`sun_pool`: 0.74 under thick ice, 1.0 under
    thin), and nine shafts (`maps/ice/props/ice_ray.tscn`, the forest streak's mesh and shader, cold tint) stand
    under the thinnest cells along the same line; they are scene nodes under `LightStreaks`, free to move.
11. Budget: ground 22008, wall 11168, gate 304, roof 5275 + 321 icicles + 1368 shell, tower 11988, portal 610,
    shafts 324: 53366 drawn tris, 39 surfaces, one shadowed sun. The `DRAW_BUDGETS` row is these counts off
    the built files + 20 %, not a suite measurement.

Textures: `maps/ice/textures/ice.ase`, photo-derived 256 px tiles at 0.05 m per texel, bilinear; sources and
cuts in `docs/TEXTURES.md`.
