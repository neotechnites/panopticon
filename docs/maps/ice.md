# Map 4: the Ice Dome

Blue ice, not white snow (snow only as contrast), under a blue see-through ice dome. N64 look (OoT Ice
Cavern, Sherbet Land). The gimmick will be ice sliding physics; not in this pass. No see-through cover on
this map. Ryan designs the level: this pass is a clean shell to build on, not a designed level.
World coordinates, Godot y up; bearings as map 1.

## Pass 1: the blockout

Ryan: "ok, start on the ice map. just do a blue slightly transparent ice dome for the roof for now."
Every open number is map 1's.

1. Shell, `maps/ice/models/ice.glb` (`tools/modelling/maps/ice/ice_build.py`): one closed contiguous
   mesh turned from one profile. Pit floor dark ice at y -11.0; the pit bank at r 46.7; a flat ice lane
   r 46.7..57.3 at y 23.0, inner edge open; the ice wall at r 57.3 up to y 35.0. Nothing on the lane.
   Collider `IceCollision-colonly`: pit floor, bank, lane, wall to the spring.
2. Roof: the dome springs from the wall head at y 35.0, apex y 65.0. Its profile is a quarter ellipse
   whose tangent at the spring is the wall's own vertical, so wall and dome are one surface with a broad
   cove (radius 15.7 m), no corner. Alpha blend (glTF BLEND, Godot blend_mix), 0.83 opaque, smooth
   shaded, single-sided facing in. The import has `generate_lods=false`.
3. Tower, `ice_tower.glb`: a PLACEHOLDER plain ice drum on map 1's guard datum (y 25.35): room floor
   +1.70 (eye y 28.7), room r 6.86, eight 40 deg openings at 25 + 45k from a 0.65 m sill to 7.00,
   ceiling 7.25, top 9.60, drum r 7.80, foot on the pit floor. Collider kerb 1.25 m, as map 1.
4. Portal, `ice_portal.glb` + `maps/ice/props/ice_portal.tscn`: a plain ice frame round portal.glb's
   opening, `lib/portal_disc.py`'s swirl on `IcePortalSwirl` (portal_wave.gdshader, glow 0.5).
5. Gate, `ice_gate.glb` at 353 deg: a plain solid ice slab 10.9 x 0.8 x 8.5 m from the lane's open edge
   into the wall, `-boxcol`. It is there for RingBake, as every map's bars are.
6. Scene `maps/ice/ice.tscn`: map 1's markers, route (5 to 335 deg, lane r 52), kill box (roof y -8, r 62)
   and watch points. Cool, even light: flat cool ambient 0.9, one unshadowed cool light from above (0.5),
   the tower lamp (`ice_tower_light_profile.tres`). Sky a plain cold gradient. Characters use the
   default CharacterLight (unlit).

## Textures: `maps/ice/textures/ice.ase`

Flat single colours only, for Ryan to paint. 20 px/m (texel.MPT), 128 px sheets (6.4 m).

| Slice | Colour | Worn by |
|---|---|---|
| ice_albedo | 104,178,216 | lane, bank, wall, tower, gate, portal frame |
| ice_dark_albedo | 30,76,114 | pit floor |
| ice_dome_albedo | 150,206,236 | the dome |
| ice_snow_albedo | 226,236,244 | nothing yet: the contrast slice |
| ice_portal_swirl_albedo | 186,234,255 | the portal swirl (64 px) |
