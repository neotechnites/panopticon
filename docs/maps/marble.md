# Map 2 -- marble

The Bentham drawing built in marble: one closed rotunda, tiers of arched cells
in the wall, a round guard lodge in the middle, and the ring lane a bridge of
marble between two beds of marble spikes. Warm-grey off-white with a faint
tinge (the Temple of Time's stone, sampled below), cool grey in shadow, the
light the tower's. Nothing on the lane.

Two models, as Map 1: `assets/models/marble.glb` (the whole rotunda, one
contiguous mesh) and `assets/models/marble_tower.glb` (the tower, one
contiguous mesh, dropped in by the scene at the guard-room datum). The build
scripts prove contiguity on every build (`--check`): one connected component,
every edge on exactly two faces, no duplicate positions.

The shape, as numbers (world y; the scene instances both at identity /
the Map 1 tower datum):

1. Lane: flat marble annulus r 46.7..57.3 at y 23.0 (the same ring as Map 1), 128 facets round; run 5 deg -> 345 deg. Nothing on it: the bars between finish and start (353 deg) are Map 1's RockBars scene node, not marble.
2. Inner spike bed: floor at y 20.9 under the lane's podium wall (r 46.7) -- 2.1 m down, past the bots' 2.0 m drop probe so their mesh stops a metre short of the lip -- stepping down toward the tower in three terraces: 19.4 inside r 38, 17.9 inside r 30, 16.9 inside r 22, to the tower's foot. Square marble spikes stitched into the bed's own floor cells on a low plinth, 1.0 m at the lane rising to 2.6 m at the tower, clustered by a seeded field; every tip under the guard's sight line to the lane (clearance 1.47 m), tips near the lane <= y 22.3. Lethal: one KillVolume cylinder r 46.3 (a capsule's radius inside the lip), roof y 23.5 -- over the lane, so RingBake carves it out of the bots' mesh too.
3. Outer spike bed: a trough r 57.3..60.0, floor y 20.9, spikes 2.2..2.9 m -- every tip over the lane level, a fence of teeth beside the run (tips <= 24.2); lethal by 48 TrapVolume boxes (7.5 deg each, r 57.7..60.0, y 20.4..23.5, full boxes). The lane is the only run; the bots' mesh runs r 47.7..56.2.
4. Outer wall: face at r 60.0 from y 20.9, 64 bays of 5.9 m; three tiers 8.8 m each (bases 20.9 / 29.7 / 38.5) with a 0.6 m cornice on each and a 1.0 m pilaster on every pier, both 0.45 m proud; a 2.1 m socle under every sill.
5. Cells: one arched recess per bay per tier -- 192 cells -- 4.0 m wide, 5.5 m tall (3.5 m jamb + semicircular head), Map 1's tallest cell; tier 1 (sill = lane level, 23.0) has a 0.6 m reveal to a slotted stone screen (three 0.34 m slots, Map 1's cell language) with dark plates behind; tiers 2 and 3 are 3.0 m recesses to a dark back wall.
6. Wall top: 1.8 m Greek-key frieze 47.3..49.1, great cornice 49.1..50.1 (0.8 m proud).
7. Dome: solid, springs at y 50.1 from r 60, rise 27.0 (sphere R 80.2), apex y 77.1, 64 x 8 coffered facets, flat medallion r 4.2 at the crown. No oculus.
8. Tower (own glb, origin = guard-room datum, scene node at y 25.35): a marble ashlar shaft r 6.6 on two steps (foot r 8.0 at y 16.9), corbelled balcony r 9.9 at y 26.35 with a 1.0 m parapet, lantern outer r 8.6 / inner r 6.86, room floor y 27.05, ceiling y 34.3, eight arched windows 2.26 m wide on the 25 + 45k grid (sill 27.7, crown 32.35 -- Map 1's arrangement), cornice at 34.55..34.95, conical cap to y 41.45.
9. Guard: seat on the room floor (TowerSpawn at +0.25), eye at y 28.7, 5.7 m over the lane at 52 m (6 deg down). Light: one shadowed warm-white omni a metre under the lantern's ceiling (beams down and out of the eight windows) over a cool grey ambient; no sun, no sky.
10. Budget: map 44,770 tris (lane 16,962 / wall 27,808; collider 3,074), tower 1,342 (collider 1,254); one painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors.

## Palette

Sampled off the Temple of Time references (`~/Desktop/panopticon-refs/Map 2/images-5.jpg`, `images-6.jpg`), 8-bit sRGB:

| where | sample | used for |
|---|---|---|
| lit wall, upper hall | `#a0a28a` (160,162,138) | the first pass copied this hue (R ~ G, B 15 % under) and drifted olive; the second keeps only a faint warm tinge, the hue toward neutral warm grey |
| brightest stone | `#fdfbc8`, `#ebeaba` | the tower's light, kept nearly white `(1.0, 0.98, 0.94)` so the stone's own tinge carries the warmth |
| light pool on the floor | `#cfcba8`, `#d9d5b0` (217,213,176) | the lane's slabs, `#d2cdc2` |
| floor, lit centre | `#979477` (151,148,119) | the beds' floor `#b2afa7` (darker than the walls) |
| floor inlay band | `#a4a078` (164,160,120) | slab joints `#b0aca2` and the mosaic diamonds `#a8a49a` |
| pier in shadow | `#575744`, `#4a4b39` | the scene's ambient, cool grey `(0.70, 0.72, 0.76) x 0.55`, cell interiors `#323337` |
| statue stone | `#74765e` (116,118,94) | frieze key `#807e78`, coffer steps down to `#908f8b` |

Atlas cells (paint values, before lighting), after the second correction -- warm-grey off-white, a faint tinge only, shadows cool: marble `#e2ded4`, second marble `#dedad0`, grey marble (reveals, podium walls, cap) `#96989c`, floor slabs `#d2cdc2` (a touch darker than the walls) with joints `#b0aca2`, cell interior `#323337` (+ faint emissive), frieze ground `#dedad0` with the key in `#807e78`, coffer `#ccc8be`..`#908f8b`, spike `#dad7ce`, fluting `#e2ded4`/`#c8c5bd`, cornice fillets `#e2ded4`/`#b8b6b0`, tower ashlar `#cac6bc`, bed floor `#b2afa7`.
