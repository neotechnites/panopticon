# Map 1 — The Bentham Ring — section design

Ring: deck r 44–60, surface y = 23, ceiling y = 31.5, lane r = 52, run 5° → 335°, tower at centre, guard eye y = 27.
Rules that shape everything:
- The lane at r = 52 is walkable end to end (bots live there). Risk sits off the lane.
- Cover from the tower is only on the INNER side of what it protects → covered routes are OUTER, open routes are INNER.
- Lava never crosses the lane. Lava kills on touch (TrapVolume over a lava tile).
- Between sections: a rest pocket, with a wall of `map_base.glb`'s own rock on the runner's right, on the pit lip (see *Lip walls* below).

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

**S1 The Spires 15–60** — thin cover: a stalactite cave grown into `map_base.glb`'s own rock (the `S1_*` block of `tools/modelling/map_base_build.py`, its own seed, re-laid on a finer grid over 12–63 so nothing outside that moves). Stalagmites, floor-to-ceiling columns and stalactites are thrown at the deck and the ceiling by the forest RNG under spacing rules, never placed by hand. Ryan (2026-09-22): *"the lava stalagtite are is too thick and ahrd to get through as a runner."* So the forest is thinned, not cleared: `S1_FOREST_N` 50 → 26 and `S1_FOREST_COLS` 7 → 4 (fixtures 51 → 29: columns 7 → 4, stalagmites 44 → 25), stalactites 35 → 25, shafts thinner (short 0.12–0.20 m, medium 0.18–0.28, tall 0.22–0.32, columns 0.22–0.32 body radius; chest widths 0.14–0.65 m, so a spire still hides a standing body exactly behind it), clear air between any two feet `S1_ROUTE_GAP` 1.8 m (was 1.2; a body and a half is 1.05) and between cover fixtures at chest height `S1_FOREST_GAP` 2.4 m (was 1.6), stalactite tips `S1_TIP_CLEAR` 3.0 m over the deck (was 2.4; a jumping body is 1.8 + 1.11 m), so no stalactite carries a collider. Proved at build time (`MDL STATS s1 forest`: the widest route in each of the inner / middle / outer bands) and on the built mesh (`tools/modelling/lib/s1_lane_gap.py`: the widest-bottleneck route on the lane band r 49.8–54.2 through the collision prisms, written to `tools/modelling/map_base.s1_route.json`), and in Godot physics (`tests/test_map1_s1_run.gd` drives a body at full speed along that route). Sprint spire to spire; a stalagmite may stand on the lane's line, but never without a clear way round it.

**Pocket 60–75**: lip wall 61.7–71.3 (the placeholder slab at 59–67 is gone).

**S2 The Lava Shelf 75–130** — open inner lane vs covered outer platforms.
- `rock_wall` × 4 end to end at r 53.5 from 80 → 125, 1.3 m tall (scale y 0.43): crouch cover only.
- Lava field r 54.5–60 from 80 → 125 (`lava_tile` grid, TrapVolume over it).
- 7 `boulder` in the lava at r 57: @84, @90, @96, @102, @108, @114, @120 (gaps ≈ 3 m). Jumping exposes you above the wall.
- Inner lane r 44–53 open; 2 `spire` at r 47 @95 and @112 for the bots.

**Pocket 130–145**: lip wall 134.2–143.8 (the placeholder slab at 126.5–135 is gone).

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
  deck rock as part of the one mesh, ONE crazed crack network (Ryan: *"can
  you make them tile so that they look like one thing instead?"*, then
  *"now its unclear where you can even be, its needs to be significantly
  more cracked with clearer edges"*): every neighbouring pair of the 36 pad
  cells (never a path cell) shares one port on its common cell edge — one
  cross-section both cells' fissures end on — and inside a cell one main
  fissure runs port to port, the other ports join it through T-mouths on
  its own side vertices, bridges run fissure to fissure so the crust breaks
  into plates, and dead-end splinters craze the rest, three deep, their
  tips thrown to the emptiest ground. 42 joins, 379 fissures (4–14 a cell),
  12 plates of crust enclosed, one island: the deck round it is one scanfill
  polygon with one hole (each plate its own), bisected to ≤ 1.2 m edges, on
  the grid's own vertices, no duplicate at any seam, and starting at the
  wall's foot line, never on the wall. Fissures are
  0.18–0.44 m wide at the deck, 0.14–0.26 m deep, a dark rock lip on the
  upper sides and the glowing lava cell (atlas `ZONE_GLOW`) on the lower
  sides and the floor — flush, no plate, no hairlines. The path cells are
  plain deck: the one lane through a cracked field. The collider stays the
  flat deck over the cracks, so the bake, the bots and the jump proofs are
  the demon pad's. From the guard's eye the lip wall hides the deck surface
  itself (the sight line over the crest meets the deck at r ≈ 69), so the
  cracks read from the runner's eye and the aerial, never from the tower.
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
- **One ragged rock wall at the pit edge**, rising from the lip itself on
  its own 0.88 m footprint (r 46.70–47.58), runs unbroken from 145 to 200 as
  one arc of `map_base.glb`'s own rock — the runner's RIGHT going the lap
  (the pit is on the right of a runner going 5° → 335°); cover from the
  tower can only stand on the pit side. No talus, no spread: the deck is
  flat right up to a near-vertical face (top edge r 47.55, foot 47.58), and
  the face is textured coherently along the wall, not a random window per
  triangle. Ragged only above the deck: every 0.5 m column carries its own
  crest in runs of 1–3 columns, its outer top edge chamfered 0–8 %. Ryan:
  *"the wall is not tall enough, and the wall is like coming out from where
  it is onto the floor and it looks stupid"* — so the crest now hides a
  STANDING body (1.8 m) on the path from the guard's eye along the whole
  length (the line to its top at the far side of the path cell, taken at
  the inner top edge, plus 0.23–0.58 m), and stays under the line to every
  crack launch's apex (3.68 m) over every column: built crest 2.30–2.87 m
  (mean 2.58), proved by a ray down every 0.05 m of its length, by
  raycasts every row and every 0.25 m along the whole path (standing seen
  0/636), and every apex seen 51/51. Hit a crack and you are thrown up out
  of cover into the guard's view; walk or crouch and you are not seen.
- **Every launch aims forward** at the shipped 18 m/s, 8° inward of the
  tangent so a flight lands at its own radius. The last rows' flights reach
  past the section; nothing catches them now (the 204 wall is on the lip,
  r < 48.2), so the build's launch proof names any pad whose flight lands
  past 212.9, S4's lava — the last row's outer two do.
- **The bots walk the path.** `RingBake` links a pad only when its flight
  lands on open mesh a body clear of everything; a pad whose flight lands
  nowhere is a dead pad, carved out of the mesh as an obstacle
  (`PAD_CARVE_MARGIN_METRES` 0.2). The three jump cracks have rows +4 and +5
  cleared in their column, where their flights land, so they are live and
  the mesh runs through them.
- The guard's eye for this section is y = **28.90**, traced from the running
  game (`Tower/TowerSpawn` at 27.30 plus `RingBake.EYE_HEIGHT_METRES` 1.60).

**Pocket 200–215**: lip wall 199.2–208.8 (the placeholder slab at 190–198.6 is gone).

**S4 Demon Run 215–270** — speed. Lava strips beside the lane narrow it: `lava_tile` r 44–49 and r 55–60 from 220 → 265. 3 `demon_pad` on the lane r 52 @222, @240, @258, launching forward. 2 `slab` at r 52 @231 and @249 between pads (boost into cover, sprint, boost again).

**Pocket 270–285**: lip wall 281.2–290.8 (the placeholder slab at 270–278 is gone).

**S5 The Wall Run 285–335** — classic gaps. 4 `rock_wall` at r 49 parallel to the run: 288–296, 300–308, 312–320, 324–332 (4° gaps ≈ 3.6 m at r 49). 3 `slab` at r 57 @295, @307, @319 for the outer lane. Finish @335.

## Lip walls (the cover between sections)
Ryan: *"not tunnels ... it just needs to be a fucking wall on the right side."* The lap runs toward
rising bearing and forward × up points at the axis, so the runner's right is the pit lip. Each section
boundary, and the start, carries a wall standing ON the lip (r 46.9–48.2, 1.3 m thick; 204 and 286 are r 46.9–47.5),
tangential to the ring, in `map_base.glb`'s own rock — the `rock_wall` prop's language, ~8 m long, 3 m tall, a ragged
domed head — no mouth, nothing across the deck, nothing near the ceiling. The runner passes it on the
outer side; it is cover from the tower while they cross the boundary. The `LIP_WALLS` table of
`tools/modelling/map_base_build.py` is the one source; each wall carries its own seed.

| wall  | bearings      | head over deck | note |
|-------|---------------|----------------|------|
| start | -8 .. 14      | 4.6 m          | the big one, unchanged; the 13° gate across the lane is gone |
| S1\|S2 | 61.7 .. 71.3 | 3.0 m          | plain deck 61.5–74.0 |
| S2\|S3 | 134.2 .. 143.8 | 3.0 m        | plain deck 130.5–144.5 |
| S3\|S4 | 199.2 .. 208.8 | 3.0 m        | its sinking end grows into the last 0.8° of S3's half wall; `r_out` 47.50 |
| S4\|S5 | 281.2 .. 290.8 | 3.0 m        | plain deck 282–290.5; `r_out` 47.50, as 204 |

Why 3 m: the guard's eye is (0, 28.90, 0) and a standing head on the lane is 24.80; that line crosses
r 47.55 at 2.15 m over the deck, 0.85 m under the head, and the whole deck width behind the wall is
under it (2.48 m at r 57). Proved at build time on the built rock (`MDL STATS lip_wall`): the crest by a
ray down every 0.05 m of the full-height run, every standing body on the lane behind it hidden at every
point, and the lane a stride past each end at deck height. `tests/test_map1_lip_walls.gd` repeats the
hidden check in Godot physics and runs a body at full speed past every wall on the outer side.

Ryan, on the 204 wall: *"the cover on section 4 is too far towards the inner part of the ring, and it
jets out of the corner, either move it in a little bit or thin it out."* Its inner face is already on
the lip (46.76 drawn, lip 46.70), so it is thinned, not moved: that row alone carries `r_out` 47.50
(was the shared 48.20), 0.70 m off the outer face. S3's own half wall ends at r 47.56–47.58 and the
pocket wall's drawn face now runs 47.64–47.72 — a 0.06–0.16 m step at the corner where it was
0.76–0.86 m, and the path's inner column (r 47.55–50.75) keeps its width. The crest is untouched
(2.99–3.52 m over the deck) and all 99 bodies on the lane behind it stay hidden at every point.

## Bots
Cover instances register exactly as the old CSG cover did (same group, same collision layers) so RunnerCoverFinder uses them. Bots never need to jump a gap: nothing on r 50–54 is lava.
