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

**S3 The Demon Minefield 145–200** — chaos. Ryan: *"a minefield of demon pads,
and cover that is only about as tall as a character, so if you hit a demon pad,
you get bounced up out of cover ... a path cut through them, that sometimes you
need to jump over the pads. you just land back down on the same field."*

The floor, the corridor, the cover and the dips are all `map_base.glb`'s own
rock, from one height field: `tools/modelling/lib/s3_minefield.py`. The mesh,
the pad transforms in `scenes/ring/bentham_ring.tscn` and the proofs in
`tools/modelling/lib/s3_proof.py` all read that one layout, so the pad a runner
trips is on the rock the guard is looking at.

- **No lava and no TrapVolume anywhere in this section.** A launch drops you
  back on the same field; nothing here kills you.
- The field is plain deck (r 46.7–57.3, y 23.0) under a dense scatter of
  `demon_pad` nodes — the shipped pad, shipped physics: 18 m/s at 45°, 14.70 m
  range, 3.68 m apex. Every flight is solved to land back inside the section
  (r 48.2–56.2, bearings 146–199); a pad past bearing 182 cannot reach a legal
  forward landing on a 10.6 m deck, so those few aim backward instead.
- **Cover is crests grown out of the field's own rock**, never a block on it,
  tops 1.9–2.1 m over the deck — about as tall as a prisoner — on the TOWER
  side of the corridor, so a runner outward of one is hidden standing or
  crouched. Their flanks are steeper than 46°, so a launched body cannot land
  on one and stand there.
- **A corridor is cut through the pads**, walkable end to end by a 0.4 m body
  without ever overlapping a pad's trigger box.
- **Three dips break it.** Where the corridor is pinched to under 3.3 m the
  floor drops ~0.55 m into a 6 m saucer with a pad on its floor: the pad cannot
  be walked round, and because the take-off rim stands 0.55 m over the pad the
  jump's feet clear the trigger box's 1.0 m top for the whole 3.3 m the capsule
  overlaps it. From flat ground a full 2.5 m pad is NOT jumpable (the window
  where a 7 m/s jump keeps its feet over 1.0 m is only 2.24 m long) — the dip
  is what makes the jump exist. The outer shoulder that pinches each dip is
  ROCK, not a second pad: a pad out at r 55 has no forward flight that lands
  back on a 10.6 m deck, and rock needs no flight.
- **Every pad aims forward** (its landing bearing is greater than its own), and
  past bearing ~184.5 no forward flight lands on the field, so no pad is laid
  there and the last stretch is the way out. A backward-throwing pad loops a
  bot for ever — it walks forward, is thrown back, walks forward again — and
  fails `test_a_runner_completes_a_lap`. Bots are map-agnostic, so the map has
  to be what fixes that, not the brain.
- **The corridor carries the bot navigation mesh, not just a body.** `RingBake`
  bakes at agent radius 0.50 on a 0.25 m grid, so a route has to stay about
  2.6 m clear: a corridor a human walks is not automatically one a bot can
  path. A 1.30 m radius disc rolls from end to end.
- Getting launched throws you to +3.68 m, well over the 2.1 m cover line, into
  plain view; you land back down on the same field.
- The guard's eye for this section is y = **28.90**, traced from the running
  game (`Tower/TowerSpawn` at 27.30 plus `RingBake.EYE_HEIGHT_METRES` 1.60),
  not the 23.0 + 4.0 the older sections assume.

**Pocket 200–215**: slab r 52 @ 208.

**S4 Demon Run 215–270** — speed. Lava strips beside the lane narrow it: `lava_tile` r 44–49 and r 55–60 from 220 → 265. 3 `demon_pad` on the lane r 52 @222, @240, @258, launching forward. 2 `slab` at r 52 @231 and @249 between pads (boost into cover, sprint, boost again).

**Pocket 270–285**: slab r 52 @ 278.

**S5 The Wall Run 285–335** — classic gaps. 4 `rock_wall` at r 49 parallel to the run: 288–296, 300–308, 312–320, 324–332 (4° gaps ≈ 3.6 m at r 49). 3 `slab` at r 57 @295, @307, @319 for the outer lane. Finish @335.

## Bots
Cover instances register exactly as the old CSG cover did (same group, same collision layers) so RunnerCoverFinder uses them. Bots never need to jump a gap: nothing on r 50–54 is lava.
