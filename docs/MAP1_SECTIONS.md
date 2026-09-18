# Map 1 — The Bentham Ring — section design

Ring: deck r 44–60, surface y = 23, ceiling y = 31.5, lane r = 52, run 5° → 335°, tower at centre, guard eye y = 27.
Rules that shape everything:
- The lane at r = 52 is walkable end to end (bots live there). Risk sits off the lane.
- Cover from the tower is only on the INNER side of what it protects → covered routes are OUTER, open routes are INNER.
- Lava never crosses the lane. Lava kills on touch (TrapVolume over a lava tile).
- Between sections: a rest pocket, and across it a divider wall of `map_base.glb`'s own rock (see *Dividers* below).

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

**Pocket 60–75**: the S1|S2 divider @ 66.5 (its spur at the lip is the pocket's cover; the placeholder slab at 59–67 is gone).

**S2 The Lava Shelf 75–130** — open inner lane vs covered outer platforms.
- `rock_wall` × 4 end to end at r 53.5 from 80 → 125, 1.3 m tall (scale y 0.43): crouch cover only.
- Lava field r 54.5–60 from 80 → 125 (`lava_tile` grid, TrapVolume over it).
- 7 `boulder` in the lava at r 57: @84, @90, @96, @102, @108, @114, @120 (gaps ≈ 3 m). Jumping exposes you above the wall.
- Inner lane r 44–53 open; 2 `spire` at r 47 @95 and @112 for the bots.

**Pocket 130–145**: the S2|S3 divider @ 139 (spur at the lip; the placeholder slab at 126.5–135 is gone).

**S3 The Demon Pad Grid 145–200** — chaos. Ryan: *"step 1 fill the section
with demon pads. step 2 cut a path through it by removing demon pads. step 3
a wall of cover at the pit edge, like all the other cover, short enough that a
person jumping on a demon pad flies above it from the guard tower. thats it."*

The deck is FLAT at lane height (r 46.7–57.3, y 23.0): no crests, no dips. On
it, `demon_pad` nodes fill a regular grid — 17 rows 3.24° (2.94 m at r 52)
apart along the arc, 3 columns across the width (r 49.15, 52.35, 55.55; 3.2 m
apart), so with the wall on the lip the deck is tiled from wall to wall with no
gap a body fits through (three 2.5 m plates plus the wall's 0.75 m foot leave
0.3 m at each end; a fourth column would need 11 m). The S3 block of
`tools/modelling/map_base_build.py` is the one layout the mesh, the collider,
the pad transforms in `scenes/ring/bentham_ring.tscn` (the build writes the
node block) and the proofs all come from. The section's deck grid is true
polar between the lip and the wall foot (those two rows stay the ring's own
chord vertices, so the weld is unchanged), so pads, wall and proofs share one
exact metric and the wall's edges fall on mesh lines.

- **No lava and no TrapVolume anywhere in this section.** A launch drops you
  back on the same deck; nothing here kills you.
- **The path** is cut by leaving cells pad-free: one column wide, the middle
  column for rows 0–9, stepping to the inner column at row 9 (a bend costs
  one extra cell, so the runner steps sideways, then forward). 18 cells
  cleared of 51, 36 pads remain.
- **Three pads are left IN the path** (rows 1, 4, 10) and must be jumped. From
  flat ground the shipped 2.5 × 1.0 m trigger box cannot be jumped (a 7 m/s,
  1.11 m jump keeps its feet over 1.0 m for only 2.24 m of travel, and the
  capsule overlaps the box for 3.6 m), so these three carry
  `footprint_metres = (2.5, 0.5, 2.5)`: the same plate, 0.5 m tall. Feet
  clear it by +0.3 m at the overlap's ends with a take-off window of 1.6 m;
  the row after each is cleared in the same column, so the 7 m jump lands on
  the path; the gaps either side of the pad are 0.38 m, no body's 0.8 m.
- **One half wall at the pit edge**, 1.85 m tall, 0.35 m flat top, 0.75 m at
  the foot, its inner foot on the lip itself, runs unbroken from 145 to 200
  as one arc. It is `map_base.glb`'s own rock, sampled on grid lines placed
  exactly at its top edges and feet, and proved by a ray down every 0.05 m of
  its length on the built mesh: 1.85 m over the deck all the way. Why 1.85:
  the guard's eye is 5.9 m over the deck, so the sight line over the wall to
  the middle column is 1.69 m up at the wall — a crouched capsule (1.2 m)
  anywhere on the path is under it (raycast, every row, three stances), a
  standing one (1.8 m) is over it on both path columns, and a pad's flight
  (apex 3.68 m) is well above it: hit a pad and you are thrown up out of
  cover into the guard's view.
- **Every pad aims forward** at the shipped 18 m/s, 8° inward of the tangent so
  a flight lands at its own radius rather than 2 m outward. Landing on the
  next pad five rows on is the minefield: you fly again. The last rows' flights
  reach past the section; the S3|S4 divider at 204 (3.4 m of rock to the
  ceiling) catches them and they drop on the deck in front of it, short of
  S4's lava at 212.9. No pad is slowed and none aims backward: a hop shorter
  than its own plate lands back on the plate and fires it again for ever, and
  a backward pad loops a bot the same way.
- **The bots walk the path.** `RingBake` links a pad only when its flight
  lands on open mesh a body clear of everything (pad plates are physical);
  a pad whose flight lands nowhere is a dead pad, carved out of the mesh as
  an obstacle. The three jump pads have rows +4 and +5 cleared in their
  column, where their flights land, so they are live and the mesh runs
  through them (proved: 1.64 m clear). With the old carve margin (0.5 m) the
  lane between two carved pads was 0.9 m and the bake sealed it;
  `PAD_CARVE_MARGIN_METRES` is 0.2 (the arithmetic is on the constant): the
  lane is 1.5 m on a 2.7 m pitch, 2.5 m on this 3.2 m one. Measured on the
  whole ring: 587 polygons, 4 dead pads, 24 pad links, 50 jump links, and
  `test_the_bake_links_the_whole_lap_into_one_path` plans start to end.
- The guard's eye for this section is y = **28.90**, traced from the running
  game (`Tower/TowerSpawn` at 27.30 plus `RingBake.EYE_HEIGHT_METRES` 1.60).

**Pocket 200–215**: the S3|S4 divider @ 204; slab r 52 @ 208.

**S4 Demon Run 215–270** — speed. Lava strips beside the lane narrow it: `lava_tile` r 44–49 and r 55–60 from 220 → 265. 3 `demon_pad` on the lane r 52 @222, @240, @258, launching forward. 2 `slab` at r 52 @231 and @249 between pads (boost into cover, sprint, boost again).

**Pocket 270–285**: the S4|S5 divider @ 286; slab r 52 @ 278.

**S5 The Wall Run 285–335** — classic gaps. 4 `rock_wall` at r 49 parallel to the run: 288–296, 300–308, 312–320, 324–332 (4° gaps ≈ 3.6 m at r 49). 3 `slab` at r 57 @295, @307, @319 for the outer lane. Finish @335.

## Dividers (the cross-lane walls)
Every section boundary carries a wall of `map_base.glb`'s own rock, built by the `CROSS_WALLS` table
of `tools/modelling/map_base_build.py` in the language of `map1_wall_build.py`: one closed mass from
0.8 m under the deck to 0.3 m into the ceiling, r 46.8–58.3, with one mouth cut through at the lane
(3.6 m wide, 3.7 m high; the start gate's is 4.6 × 4.8) and a tangential spur where its foot grips the
pit lip — that spur is the cover, because a radial wall alone casts no shadow from a tower at the
centre.

| wall  | bearing | why there |
|-------|---------|-----------|
| start | 13      | 3.9 m ahead of PrisonerStart; the lip screen -8..14 stands across the start |
| S1\|S2 | 66.5   | the only plain deck is 61.5–74.0 (S1's fillets stop at 61.0, S2's lava tongue starts at 74.5); the mouth exits 2.4 m before S2's first TrapVolume carve (72.9), which is the corridor the bake needs to drop into S2's inner lane |
| S2\|S3 | 139    | plain deck 130.5–144.5; the mouth's near face is 2.6 m past S2's last carve (132.2) and the spur's toe stops 1.4 m short of S3's lip wall at 145 |
| S3\|S4 | 204    | plain deck 196–208; catches the S3 flights that would leave the section |
| S4\|S5 | 286    | plain deck 282–290.5; the "narrow" variant, S5's rock crowds the band |

The bands are measured on the shipped collider (a vertical ray every 0.5° and 0.5 m over r 46.8–58.3),
not argued: no lava crosses any wall's line, so none needs an arch. Each wall is proved at build time
(`MDL STATS cross_wall` / `MDL STATS sight`): one connected component, 0 duplicate positions, 0 lines
over the crest, and the lowest ledge on it above a 1.11 m jump. `tests/test_map1_divider_s1s2.gd` runs
a body at full speed through the 66.5 mouth and into its spur.

## Bots
Cover instances register exactly as the old CSG cover did (same group, same collision layers) so RunnerCoverFinder uses them. Bots never need to jump a gap: nothing on r 50–54 is lava.
