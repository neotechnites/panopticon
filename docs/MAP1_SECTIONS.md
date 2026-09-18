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
| demon_pad   | 2.5 m dia disc, emissive sigil        | boost pad (BoostPad script)  |
| lava_crack  | the same trigger, no model, heat haze | S3: a crack in the deck rock |

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

**S3 The Lava Crack Grid 145–200** — chaos. Ryan: *"step 1 fill the section
with demon pads. step 2 cut a path through it by removing demon pads. step 3
a wall of cover at the pit edge, like all the other cover, short enough that a
person jumping on a demon pad flies above it from the guard tower. thats it."*
Then, on the modelling: *"the demon pad was a stand in ... instead of a demon
pad, either create an element, or hard model into the map, cracks that have
like, wavy hotness coming out of them. the type of waviness you see above a
road on a hot day. not steam of course, but make it look like theres lava
under the cracks. as for the cover, its not a fucking hallway. its just
fucking cover, its just a fucking rock wall to the left of the runners."*

The deck is FLAT at lane height (r 46.7–57.3, y 23.0): no crests, no dips. On
it, 36 launch positions fill a regular grid — 17 rows 3.24° (2.94 m at r 52)
apart along the arc, 3 columns across the width (r 49.15, 52.35, 55.55; 3.2 m
apart) — exactly where the demon pads stood. The S3 block of
`tools/modelling/map_base_build.py` is the one layout the mesh, the collider,
the node transforms in `scenes/ring/bentham_ring.tscn` (the build writes the
node block) and the proofs all come from. The section's deck grid is true
polar between the lip and the wall foot (those two rows stay the ring's own
chord vertices, so the weld is unchanged).

- **The launch is unchanged, the visual is not.** Each position is a
  `scenes/ring/lava_crack.tscn`: the demon pad's own `BoostPad` trigger
  (`scripts/match/boost_pad.gd`, 2.5 × 1.0 × 2.5 m, 18 m/s at 45°) with no
  model, plus a `LavaHaze` node. Under them, cut into `map_base.glb`'s own
  deck rock as part of the one mesh, ONE crack network (Ryan: *"can you make
  them tile so that they look like one thing instead?"*): a seeded spanning
  tree of the 36 pad cells (never a path cell) picks which neighbours join,
  each joined pair shares one port on its common cell edge — one
  cross-section both cells' fissures end on — and inside a cell one main
  fissure runs port to port with the other ports and a splinter or two
  branching off it through T-mouths on the main's own side vertices. 35
  joins, 64 fissures, one island: the deck round it is one scanfill polygon
  with one hole, on the grid's own vertices, no duplicate at any seam.
  Fissures are 0.14–0.48 m wide at the deck, 0.10–0.22 m deep, a dark rock
  lip on the upper sides and the glowing lava cell (atlas `ZONE_GLOW`) on
  the lower sides and the floor — flush, no plate. The collider stays the
  flat deck over the cracks (they are narrower than a body), so the bake,
  the bots and the jump proofs are the demon pad's.
- **The haze** is `scenes/ring/lava_haze.gdshader` on two crossed 2.4 × 2.0 m
  quads (one surface, 4 tris, one shared `ShaderMaterial`): pure refraction of
  the scene behind through `hint_screen_texture`, a slow rising 2-octave
  noise, fading to nothing at the top and the sides. No particles, no colour,
  no steam. GL Compatibility pays one screen copy per frame for it.
- **No lava hazard and no TrapVolume anywhere in this section.** A launch
  drops you back on the same deck; nothing here kills you.
- **The path** is cut by leaving cells crack-free: one column wide, the middle
  column for rows 0–9, stepping to the inner column at row 9 (a bend costs
  one extra cell, so the runner steps sideways, then forward). 18 cells
  cleared of 51, 36 cracked cells remain.
- **Three cracks are left IN the path** (rows 1, 4, 10) and must be jumped:
  they carry `footprint_metres = (2.5, 0.5, 2.5)`, the same trigger 0.5 m
  tall. Feet clear it by +0.3 m at the overlap's ends with a take-off window
  of 1.6 m; the row after each is cleared in the same column, so the 7 m jump
  lands on the path.
- **One ragged rock wall at the pit edge**, its inner foot on the lip itself,
  runs unbroken from 145 to 200 as one arc of `map_base.glb`'s own rock — the
  runner's RIGHT going the lap (the pit is on the right of a runner going 5°
  → 335°); cover from the tower can only stand on the pit side. Not a smooth
  extrusion: every 0.5 m column carries its own crag on the crest, the top
  (0.30–0.50 m) and the foot (0.72–1.04 m) wander in runs of 1–3 columns, the
  flanks are cleaved. The crest is spent INSIDE the window the guard's sight
  lines cut — over the line to a crouched capsule (1.2 m) at the far side of
  the path cell (hidden), under the line to a standing one (1.8 m) at the
  wall side (seen) — so it stands 1.77–2.12 m where the path is the middle
  column and 1.50–1.87 m where it is the inner column; built crest
  1.60–2.02 m, proved by a ray down every 0.05 m of its length and by the
  same raycasts every 0.25 m along the whole path. A pad's flight (apex
  3.68 m) is well above it: hit a crack and you are thrown up out of cover
  into the guard's view.
- **Every launch aims forward** at the shipped 18 m/s, 8° inward of the
  tangent so a flight lands at its own radius. The last rows' flights reach
  past the section; the S3|S4 divider at 204 catches them and they drop on
  the deck in front of it, short of S4's lava at 212.9.
- **The bots walk the path.** `RingBake` links a pad only when its flight
  lands on open mesh a body clear of everything; a pad whose flight lands
  nowhere is a dead pad, carved out of the mesh as an obstacle
  (`PAD_CARVE_MARGIN_METRES` 0.2). The three jump cracks have rows +4 and +5
  cleared in their column, where their flights land, so they are live and
  the mesh runs through them.
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
