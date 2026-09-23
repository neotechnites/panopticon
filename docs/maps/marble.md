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
2. Walkway: a marble gallery slab, top at y 23.0 (Map 1's lane height), r 46.7 to the wall at 59.55, 1.0 m thick (underside y 22.0); paving r 46.8..57.3 in 128 facets with a plain stone margin to the wall; a chamfered nosing at the inner lip. The inner edge is OPEN: no parapet, no bed beside the lane; step off and you fall 24 m to the spikes, the only hazard. Run 5 deg -> 345 deg at r 52; the bars between finish and start (353 deg) and the portal at the finish are THIS map's own fixtures, not Map 1's hell rock (pass 7, Ryan: "now create bars and portals that match the actual maps"). `marble_bars.glb` is an iron portcullis in a marble frame in the wall's own architecture -- ashlar plinth, fluted pilaster jambs 0.45 m proud, a 6.00 x 6.20 m mouth under a semicircular head r 3.00 crowning at 7.20, a cornice moulding across the top, 12 bars 0.13 m square at a 0.342 m pitch with 3 cross-bars, the iron the cells' own near-black -- in rock_bars.glb's exact envelope (10.6 x 8.5 x 0.5 m, origin the base centre) and keeping its guarantee that no gap exceeds 0.38 m. `marble_portal.glb` is the same architecture as a 4.5 x 4.0 x 0.8 m aedicule round portal.glb's exact opening (2.7 m clear, springing 2.60, apex 3.15, surface centre 1.50), so scenes/ring/marble_portal.tscn is portal.tscn node for node -- same Glow, same Gate, same finish_gate group -- and the effect surface keeps portal_build's own swirl and material, painted into marble's spare atlas cell. 1,384 and 172 visual tris; each is one closed contiguous mesh (components 1, boundary 0, duplicate positions 0). The slab is the third tier's cornice, extended.
3. Wall: face at r 60 from y -1.0, 64 bays of 5.9 m; SEVEN tiers of 8.0 m (bases -1 / 7 / 15 / 23 / 31 / 39 / 47): three below the walkway down to the spike floor, four above it. A 0.6 m cornice on each tier and a 1.0 m pilaster on every pier, both 0.45 m proud; a 1.0 m socle under every sill.
4. Cells: one arched recess per bay per tier -- 448 cells -- 4.0 m wide, 5.5 m tall (3.5 m jamb + semicircular head), Map 1's tallest cell, 3.0 m deep to a dark back wall. Every cell has five iron bars 0.13 m square over the arch, dark cool iron with a lit rim so they read from the lane, standing on the sill 0.5 m into the reveal and set into the head -- open cells, not screens.
5. Wall top: 1.8 m Greek-key frieze 55.0..56.8, great cornice 56.8..57.8 (0.8 m proud).
6. Dome: solid, springs at y 57.8 from r 60, rise 27.0, apex y 84.8, flat medallion r 4.2 at the crown, no oculus -- and its pattern is the DRAWING'S (pass 6, Ryan: "make the roof's design match the drawing"), not coffers, rebuilt clean in pass 7 (Ryan: "the ceiling of the marble room, its design became completely garbled"). Off the spring ring a smooth collar takes the first 3.2 m of arc, one quad per wall station (192) so every joint is vertical, up to a ring moulding 0.25 m proud and 0.7 m of arc tall; the wall's 192 stations become the dome's 176 on the moulding's foot step, a 0.25 m face looking down the sphere that nobody sees. On the moulding's head (r1) stand SIXTEEN broad meridional ribs, 6 deg wide and 0.85 m proud, running through six rings (r1 .. r6 at 0, 0.15, 0.30, 0.61, 0.89, 1.0 of the arc from the moulding to the cap) to the medallion, with ten plain panel facets between each pair; the five odd panel stations carry the flutes: each a V-groove two facets wide, 0.85 m deep where it stands on the ring, two PLANAR flanks tapering to a point at r3, a two-triangle foot on the moulding. Every face is a regular quad or a deliberate triangle: no zipper crosses a seen surface, so no chevrons, no crumpled pleats, no rib foot cut off over the collar (pass 6's 192-to-112 collar zipper, with the moulding's stripes fitted to each sliver, was the garble).
7. Tower (own glb, origin = guard-room datum, scene node at y 25.35), pass 6 to Ryan's verdict on pass 5: ONE round ashlar shaft of constant diameter, r 7.0 on two low steps (foot r 8.0 on the spike floor at y -1.0), from the floor to the roof -- no wider room at the top. At the guard floor (y 27.05) the shaft opens into a colonnade: sixteen 0.30 m columns on the shaft's own line at bearings 25 + 22.5k, open between them (openings 36.25 + 22.5k, 2.43 m wide, 27.05..31.47) and joined by ROUND ARCHES (pass 6, Ryan: "the columns aren't just holding a dome, they are arches"): each opening is a 2.43 m span springing at y 30.25 off the columns' sides and crowning at y 31.47 on the pier line between two facets, the spandrel over it solid to the beam, so the beam and the dome sit on the arcade and not on sixteen posts. It carries a 0.5 m ring beam (32.35..32.85) and a dome that sits on the arches (springs at y 32.85 from r 7.0, apex y 38.25, coffered inside). A functional balcony FLAT with the room floor (pass 5, Ryan): one level at y 27.05 through the columns onto a 1.2 m ledge on a 0.35 m slab, with a 1.0 m iron railing -- 32 posts 0.10 square, a mid rail and a top rail at y 28.05 -- and an invisible collider band in the railing's place, so nobody walks off. Room floor: the lane's paving in two rings of radial slabs, a plain margin to the columns, and at the centre a 0.6 m DAIS (r 2.2, plain grey top) the seat stands on: it lifts the guard's eye to y 29.3, 0.14 m over the rail top on the line to the lane's inner edge (0.26 m to the lane).
8. Guard: seat on the dais (TowerSpawn at +0.25), eye at y 29.3, 6.3 m over the lane at 52 m (7 deg down), as Map 1: the runners nearly at the tower's height, a little down. Light: one shadowed GOLD omni under the arcade at y 30.95 (over the guard's head, under the arches' crowns, so the beams go out THROUGH the arches) over a cool grey ambient; no sun, no sky. It is a SOFT lamp (pass 6, Ryan: "it's way way harsh in the middle of the tower"): 2.4 m wide, energy 22 against pass 5's 70, specular 0.25, shadow blur 3.0, and a falloff flat enough over a 140 m reach (attenuation 0.3) that the room's floor and the wall 60 m away are within a stop of each other -- no pool, no hot spot. Every number is `scenes/ring/marble_tower_light_profile.tres`; the review renders mirror it.
9. Budget: map 70,432 tris (floor + slab 12,096 / wall 58,336, of which 448 cells 31,360, 2,240 bars 8,960, pilasters 7,168, cornices 7,040, dome 3,424; collider 2,304), tower 4,380 (collider 1,278; the sixteen arched screens are 1,536 of it, the railing's 32 posts and two rails 1,344) -- map_base's class (71k): seven tiers of barred cells is what the drawing costs. One painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors.

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

## Course

Ryan: *"spin up a tree map, and marble map, to do its best job making an
obstacle course for both of those with the elements it created. no rules, just
let them try their best."* Six stretches with a rest pocket between, all placed
instances under `Sections` in `scenes/ring/marble.tscn` -- nothing is welded
into `marble.glb`. The guard's eye is 6.5 m over the lane and only 45 m inboard
of it, so a prop's shadow runs radially OUTWARD and reaches to about 1.16x its
own radius: cover stands on the INNER side of the ground it protects, and a
2.2 m stump shelters a body for about five metres while a 5.0 m column shelters
one to the wall. That one number shapes every stretch.

| deg | stretch | the problem | props |
|---|---|---|---|
| 5-14 | start | first shade | 1 broken column, r 56 |
| 14-70 | **The Arcade** | seven broadside arches at r 50 stripe the whole outer lane with full-height cover and slit it with their own windows; the open fast line is the 1.5 m of lip inboard of them. Three of the best stripes hold a spike patch | 7 arch, 3 spike patch |
| 78-130 | **The Ledge** | spiked thresholds shut the wall side, so the run is pinned to the open inner edge over the 24 m drop; the crux at 106 deg leaves 4 m of lip | 6 spike strip, 3 column, 1 orb |
| 138-195 | **The Ruin** | five heaps staggered across the width, one column still standing between two stumps -- shelter you cross to, not along. One spike patch at the wall, one on the lip | 5 column, 10 broken, 2 spike patch |
| 203-258 | **The Gauntlet** | the mirror of the Ledge: thresholds shut the lip for the whole stretch, so the run is a 4 m wall lane with no cover in it, flown in 15 m hops by three pads at a 3.7 m apex -- the most visible a runner ever is | 5 spike strip, 3 demon pad |
| 266-320 | **The Palisade** | ten columns along the open lip every 5 deg throw shadows one body wide right across the lane: cover you can stand in and cannot travel in. Five stumps at r 55.5 are the only pockets | 10 column, 5 broken, 1 orb |
| 328-344 | **The Last Gate** | two arches face-on across the lane, the way round each shut by a spike patch -- inner at the first, outer at the second | 2 arch, 2 spike patch |

Every spike footprint carries its own `TrapVolume` 2.6 m tall
(`scenes/ring/marble_spike_patch.tscn`, `marble_spike_strip.tscn`); the height
is load-bearing, because `RingBake` finds every jump arc over one lethal and so
links none. Two rules the bot harness wrote, both paid for: every hazard leaves
at least 4 m of navigable bypass, and no pad flight crosses one -- a pad's apex
is 3.7 m and a capsule's feet 0.9 m under that, which is 0.2 m over a spike
volume's roof. `RingBake`: 164 cover points on the bare lane, 209 with the
course, against 192 on Map 1.
