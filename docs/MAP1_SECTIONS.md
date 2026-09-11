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

**S3 The Split 145–200** — choose.
- `rock_wall` × 5 full height at r 55 from 148 → 197: a solid divider.
- INNER lane r 44–54.5: open, fast, no cover at all.
- OUTER lane r 55.5–60: fully covered from the tower, but the floor is lava (`lava_tile` r 56–60 from 150 → 195) with 8 `boulder` at r 58: @153, @158, @163, @169, @175, @181, @187, @193 (gaps 3.5–4 m, one 4.5 m jump @169→175). Entrance/exit gaps in the wall @146 and @199.

**Pocket 200–215**: slab r 52 @ 208.

**S4 Demon Run 215–270** — speed. Lava strips beside the lane narrow it: `lava_tile` r 44–49 and r 55–60 from 220 → 265. 3 `demon_pad` on the lane r 52 @222, @240, @258, launching forward. 2 `slab` at r 52 @231 and @249 between pads (boost into cover, sprint, boost again).

**Pocket 270–285**: slab r 52 @ 278.

**S5 The Wall Run 285–335** — classic gaps. 4 `rock_wall` at r 49 parallel to the run: 288–296, 300–308, 312–320, 324–332 (4° gaps ≈ 3.6 m at r 49). 3 `slab` at r 57 @295, @307, @319 for the outer lane. Finish @335.

## Bots
Cover instances register exactly as the old CSG cover did (same group, same collision layers) so RunnerCoverFinder uses them. Bots never need to jump a gap: nothing on r 50–54 is lava.
