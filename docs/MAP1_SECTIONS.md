# Map 1 — The Bentham Ring — section design

Ring: deck r 44–60, surface y = 23, ceiling y = 31.5, lane r = 52, run 5° → 335°, tower at centre, guard eye y = 27.
Rules that shape everything:
- The lane at r = 52 is walkable end to end (bots live there). Risk sits off the lane.
- Cover from the tower is only on the INNER side of what it protects → covered routes are OUTER, open routes are INNER.
- Lava never crosses the lane. Lava kills on touch (TrapVolume over a lava tile).
- Between sections: a rest pocket — one `slab` at r 52, and nothing else, for ~10°.

## Elements (assets/models/*.glb, each with its own `-colonly` collision, hell rock atlas)
| name        | size                                  | role                        |
|-------------|---------------------------------------|-----------------------------|
| spire       | 0.9 m base, 2.6 m tall stalagmite     | thin cover, stand exactly behind |
| slab        | 3.0 w × 1.6 h × 1.0 d low rock block  | thick cover, rest pockets   |
| rock_wall   | 8.0 l × 3.0 h × 1.2 t, ragged top     | walls, the Split divider    |
| boulder     | 2.0 dia × 1.2 h, flat top             | platform over lava          |
| lava_tile   | 4 × 4 m, 0.3 m thick, emissive        | hazard floor (kill on touch)|
| demon_pad   | 2.5 m dia disc, emissive sigil        | boost pad (BoostPad script) |

## Sections (angles in degrees along the run; r in metres)
**Start pocket 5–15**: slab at r 52 @ 10.

**S1 The Spires 15–60** — thin cover. 9 `spire`: @20 r48, @25 r56, @30 r52, @35 r48, @40 r56, @45 r52, @50 r48, @55 r56, @58 r52. Sprint spire to spire; each only hides a standing body exactly behind it.

**Pocket 60–75**: slab r 52 @ 68.

**S2 The Lava Shelf 75–130** — open inner lane vs covered outer platforms.
- `rock_wall` × 4 end to end at r 53.5 from 80 → 125, 1.3 m tall (scale y 0.43): crouch cover only.
- Lava field r 54.5–60 from 80 → 125 (`lava_tile` grid, TrapVolume over it).
- 7 `boulder` in the lava at r 57: @84, @90, @96, @102, @108, @114, @120 (gaps ≈ 3 m). Jumping exposes you above the wall.
- Inner lane r 44–53 open; 2 `spire` at r 47 @95 and @112 for the bots.

**Pocket 130–145**: slab r 52 @ 138.

**S3 The Demon Pad Grid 145–200** — chaos. Ryan: *"create a grid of fucking
demon pads. carve out a path from them. and create a half wall for cover."*
and *"no gaps in the fucking wall."*

The deck is FLAT at lane height (r 46.7–57.3, y 23.0): no crests, no dips. On
it, `demon_pad` nodes on a regular grid — rows 3.24° (2.94 m at r 52) apart
along the arc, 4 columns across the width (r 47.8, 50.5, 53.2, 55.9; 2.7 m
apart), so a pad row reads as tiled from wall to lip. The S3 block of
`tools/modelling/map_base_build.py` is the one layout the mesh, the collider,
the pad transforms in `scenes/ring/bentham_ring.tscn` (the build writes the
node block) and the proofs all come from. The section's deck grid is true
polar between the lip and the wall foot (those two rows stay the ring's own
chord vertices, so the weld is unchanged), so pads, wall and proofs share one
exact metric and the wall's edges fall on mesh lines.

- **No lava and no TrapVolume anywhere in this section.** A launch drops you
  back on the same deck; nothing here kills you.
- **Two pad blocks, each followed by its landing rows.** A pad's flight is
  14.7 m, five rows on, and the bot bake (`RingBake`) only links a pad whose
  flight lands on open navmesh at least 0.95 m (agent radius 0.50 plus its
  0.45 m landing margin) from every rim, wall foot and pad plate — pad models
  are physical, so a landing on the next pad is a DEAD pad, carved out of the
  mesh as a 3.5 m obstacle, and on a 2.7 m pitch a handful of those seal the
  deck and the lap has no path (measured: a tiled 17-row field gave 15 dead
  pads and `test_the_bake_links_the_whole_lap_into_one_path` failed). So rows
  0–4 and 10–14 carry pads and rows 5–9 and 15–16 are pad-free landing rows.
  Every pad's back-edge flight is proved to land ≥ 0.95 m clear of everything.
- **The path** is cut through each block by leaving cells pad-free: one
  column wide, wandering column 1 → 2 in block A and column 2 in block B (a
  bend costs one extra cell, so the runner steps sideways, then forward).
- **Three pads are left IN the path** (rows 0, 3, 11) and must be jumped. From
  flat ground the shipped 2.5 × 1.0 m trigger box cannot be jumped (a 7 m/s,
  1.11 m jump keeps its feet over 1.0 m for only 2.24 m of travel, and the
  capsule overlaps the box for 3.4 m), so these three carry
  `footprint_metres = (1.2, 0.5, 2.5)`: 0.5 m tall, and 1.2 m across, set
  0.5 m outward of the column so neither the gap to the wall's foot nor the
  gap to the next column's box is a body's 0.8 m — the pad cannot be walked
  round — and so the jump pad's own landing sits a body clear of the wall.
  Feet clear the 0.5 m box by +0.34 m at the overlap's ends with a take-off
  window of 1.7 m; the row after each jump pad is the same column, cleared,
  so the 7 m jump lands on the path.
- **One half wall**, 1.5 m tall, 0.35 m flat top, 0.75 m at the foot, runs
  unbroken along the path's pit side from 145 to 200 as one polyline (an arc
  per row, a radial jog where its column changes). In a landing row it stands
  at the column that was pad-free five rows earlier, and it only jogs inside a
  landing row whose source row had no pad in the jog's inner column — either
  way a landing never meets the wall's keep-out. It is `map_base.glb`'s own
  rock, sampled on grid lines placed exactly at its top edges and feet, and
  proved by a ray down every 0.05 m of the polyline on the built mesh:
  1.50 m over the deck all the way. Why 1.5 and not 1.2: the guard's eye is
  5.9 m over the deck, so the sight line to a crouched capsule (1.2 m) rises
  ~0.1 m across the path's width — a 1.2 m wall would hide nothing. At 1.5 m
  the crouched capsule is hidden anywhere on the path cell (raycast, every
  row, three stances) and a standing one (1.8 m) is seen by ≥ 0.37 m.
- **Every pad aims forward** at the shipped 18 m/s, grid pads 8° inward of
  the tangent (so a landing sits at its own radius rather than 2 m outward,
  and a column-1 landing stays clear of the wall at column 2's pit side),
  the jump pads 4°. Rows 12–14 would land past the section, so those pads
  carry a lower `launch_speed` and land at bearing 200.3, on the open pocket
  1.3° before the divider's eroded face; the shortest hop is 7 m — a hop
  shorter than its own plate lands back on the plate and fires it again for
  ever (a bot hovered on one for 40 s). A backward-throwing pad loops a bot
  the same way, so none is laid.
- The guard's eye for this section is y = **28.90**, traced from the running
  game (`Tower/TowerSpawn` at 27.30 plus `RingBake.EYE_HEIGHT_METRES` 1.60).

**Pocket 200–215**: slab r 52 @ 208.

**S4 Demon Run 215–270** — speed. Lava strips beside the lane narrow it: `lava_tile` r 44–49 and r 55–60 from 220 → 265. 3 `demon_pad` on the lane r 52 @222, @240, @258, launching forward. 2 `slab` at r 52 @231 and @249 between pads (boost into cover, sprint, boost again).

**Pocket 270–285**: slab r 52 @ 278.

**S5 The Wall Run 285–335** — classic gaps. 4 `rock_wall` at r 49 parallel to the run: 288–296, 300–308, 312–320, 324–332 (4° gaps ≈ 3.6 m at r 49). 3 `slab` at r 57 @295, @307, @319 for the outer lane. Finish @335.

## Bots
Cover instances register exactly as the old CSG cover did (same group, same collision layers) so RunnerCoverFinder uses them. Bots never need to jump a gap: nothing on r 50–54 is lava.
