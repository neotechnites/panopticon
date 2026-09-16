# Map 2 -- marble

The Bentham drawing built in the Temple of Time's stone: one closed rotunda,
seven tiers of barred arched cells in the wall, a tall round guard lodge in
the middle, and the ring lane a gallery walkway partway up the wall of cells
with its inner edge open over a floor of marble spikes. Warm sandy grey-green
ashlar with darker mortar joints, gold light pools from the lantern, cool
grey-olive shadow (the palette sampled below). Nothing on the lane.

Two models, as Map 1: `assets/models/marble.glb` (the whole rotunda, one
contiguous mesh) and `assets/models/marble_tower.glb` (the tower, one
contiguous mesh, dropped in by the scene at the guard-room datum). The build
scripts prove contiguity on every build (`--check`): one connected component,
every edge on exactly two faces, no duplicate positions.

The shape, as numbers (world y; the scene instances both at identity /
the Map 1 tower datum):

1. Spike floor: the rotunda's ground, a flat disc at y -1.0 from the axis to the wall foot at r 60. Square marble spikes stitched into the floor's own cells on a low plinth, 1.4..2.8 m tall, from r 10.3 (the tower's foot) to r 45.5 (under the walkway's lip), clustered by a seeded field; every tip under y 2.0. Lethal: one KillVolume cylinder r 46.3 (a capsule's radius inside the lip), roof y 23.5 -- over the lane, so RingBake carves it out of the bots' mesh -- down to y -3.0.
2. Walkway: a marble gallery slab, top at y 23.0 (Map 1's lane height), r 46.7 to the wall at 59.55, 1.0 m thick (underside y 22.0); paving r 46.8..57.3 in 128 facets with a plain stone margin to the wall; a chamfered nosing at the inner lip. The inner edge is OPEN: no parapet, no bed beside the lane; step off and you fall 24 m to the spikes, the only hazard. Run 5 deg -> 345 deg at r 52; the bars between finish and start (353 deg) are Map 1's RockBars scene node, not marble. The slab is the third tier's cornice, extended.
3. Wall: face at r 60 from y -1.0, 64 bays of 5.9 m; SEVEN tiers of 8.0 m (bases -1 / 7 / 15 / 23 / 31 / 39 / 47): three below the walkway down to the spike floor, four above it. A 0.6 m cornice on each tier and a 1.0 m pilaster on every pier, both 0.45 m proud; a 1.0 m socle under every sill.
4. Cells: one arched recess per bay per tier -- 448 cells -- 4.0 m wide, 5.5 m tall (3.5 m jamb + semicircular head), Map 1's tallest cell, 3.0 m deep to a dark back wall. Every cell has five iron bars 0.13 m square over the arch, dark cool iron with a lit rim so they read from the lane, standing on the sill 0.5 m into the reveal and set into the head -- open cells, not screens.
5. Wall top: 1.8 m Greek-key frieze 55.0..56.8, great cornice 56.8..57.8 (0.8 m proud).
6. Dome: solid, springs at y 57.8 from r 60, rise 27.0, apex y 84.8, 64 x 8 coffered facets, flat medallion r 4.2 at the crown. No oculus.
7. Tower (own glb, origin = guard-room datum, scene node at y 25.35), pass 4 to Ryan's verdict on pass 3: ONE round ashlar shaft of constant diameter, r 7.0 on two low steps (foot r 8.0 on the spike floor at y -1.0), from the floor to the roof -- no wider room at the top. At the guard floor (y 27.05) the shaft opens into a colonnade: sixteen 0.30 m columns on the shaft's own line at bearings 25 + 22.5k, open all round between them (openings 36.25 + 22.5k, 2.4 m wide, 27.05..32.35), carrying a 0.5 m ring beam (32.35..32.85) and a dome that sits directly on the columns (springs at y 32.85 from r 7.0, apex y 38.25, coffered inside). A functional balcony FLAT with the room floor (pass 5, Ryan): one level at y 27.05 through the columns onto a 1.2 m ledge on a 0.35 m slab, with a 1.0 m iron railing -- 32 posts 0.10 square, a mid rail and a top rail at y 28.05 -- and an invisible collider band in the railing's place, so nobody walks off. Room floor: the lane's paving in two rings of radial slabs, a plain margin to the columns, and at the centre a 0.6 m DAIS (r 2.2, plain grey top) the seat stands on: it lifts the guard's eye to y 29.3, 0.14 m over the rail top on the line to the lane's inner edge (0.26 m to the lane).
8. Guard: seat on the dais (TowerSpawn at +0.25), eye at y 29.3, 6.3 m over the lane at 52 m (7 deg down), as Map 1: the runners nearly at the tower's height, a little down. Light: one shadowed GOLD omni a metre under the lantern's ceiling (beams down and out between the columns) over a cool grey ambient; no sun, no sky.
9. Budget: map 68,064 tris (floor + slab 12,096 / wall 55,968, of which 448 cells 31,360, 2,240 bars 8,960, pilasters 7,168, cornices 7,040, dome 1,056; collider 2,304), tower 3,164 (collider 1,246; the railing's 32 posts and two rails are 1,344 of it) -- map_base's class (71k): seven tiers of barred cells is what the drawing costs. One painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors.

## Palette

Sampled off the Temple of Time references (`~/Desktop/panopticon-refs/Map 2/images-5.jpg`, `images-6.jpg`), 8-bit sRGB, box means:

| where (ref) | sample | used for |
|---|---|---|
| upper wall, lit (5) | `#808368` (128,131,104) p90; `#62634e` mean | the ashlar's lit face |
| wall, right (6) | `#8b8160` (139,129,96); p90 `#c2b68e` | the tower shaft's ashlar `#8b8160` |
| statue stone (5) | `#76775d` (118,119,93) | cornice fillets, pilaster shadow half |
| floor light pool (5) | `#b8b58f` (184,181,143); p90 `#f3efca` | the lantern's light `(1.0, 0.90, 0.66)` gold; paving under it |
| floor, mid (5) | `#78765d` (120,118,93) | the spike floor `#7d7a62` |
| floor dark tile (5) | `#7d7a62` (125,122,98) | paving inlays, spike floor |
| pier in shadow (5) | `#414233` (65,66,51) | frieze key `#45463a`, reveal joints |
| wall, lower shadow (5) | `#3e3e2f` (62,62,47) | cell interiors `#2f3028` |
| railing gold (6) | `#bcae82` (188,174,130) | the paving's centre inlay |

Atlas cells (paint values, before lighting): ashlar `#9a9676` with mortar joints `#6c6950` (half-bond courses); second sheet `#928e70` / `#66634a`; grey-olive (reveals, undersides, cap) `#6b6b55` / `#505042`; paving slabs `#aaa683` with joints `#66634a` and inlays `#7d7a62` (centre `#bcae82`); spike floor `#7d7a62` with a tile grid `#55533f`; cell interior `#2f3028` (+ faint emissive); frieze ground `#9a9676`, key `#45463a`; coffer `#9a9676` stepping down to `#565542`; spike `#a8a488` with grain `#8c8970`; fluting `#9e9a7a` / `#64634e`; cornice fillets `#a29e7e` / `#5e5c44`; iron `#181a1f` with a rim `#686e7a`; tower ashlar `#8b8160` / `#625b44`; socles `#928e70` / `#6c6950`.
