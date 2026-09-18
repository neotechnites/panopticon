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

**S1 The Spires 15–60** — thin cover. 9 `spire`: @20 r48, @25 r56, @30 r52, @35 r48, @40 r56, @45 r52, @50 r48, @55 r56, @58 r52. Sprint spire to spire; each only hides a standing body exactly behind it.

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
  model, plus a `LavaHaze` node. Under it, cut into `map_base.glb`'s own deck
  rock as part of the one mesh: a jagged fissure 2.0–2.3 m long with one or
  two splinters, 0.14–0.48 m wide at the deck, 0.10–0.22 m deep, a dark rock
  lip on the upper sides and the glowing lava cell (atlas `ZONE_GLOW`) on the
  lower sides and the floor — flush, no plate, no two alike (one seeded draw
  per pad). The deck cells round each crack are one scanfill polygon whose
  boundary is the grid's own vertices, so nothing is duplicated at the seam.
  The collider stays the flat deck over the cracks (they are narrower than a
  body), so the bake, the bots and the jump proofs are the demon pad's.
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
  cleared of 51, 36 cracks remain.
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
boundary, and the start, carries a wall standing ON the lip (r 46.9–48.2, 1.3 m thick), tangential to
the ring, in `map_base.glb`'s own rock — the `rock_wall` prop's language, ~8 m long, 3 m tall, a ragged
domed head — no mouth, nothing across the deck, nothing near the ceiling. The runner passes it on the
outer side; it is cover from the tower while they cross the boundary. The `LIP_WALLS` table of
`tools/modelling/map_base_build.py` is the one source; each wall carries its own seed.

| wall  | bearings      | head over deck | note |
|-------|---------------|----------------|------|
| start | -8 .. 14      | 4.6 m          | the big one, unchanged; the 13° gate across the lane is gone |
| S1\|S2 | 61.7 .. 71.3 | 3.0 m          | plain deck 61.5–74.0 |
| S2\|S3 | 134.2 .. 143.8 | 3.0 m        | plain deck 130.5–144.5 |
| S3\|S4 | 199.2 .. 208.8 | 3.0 m        | its sinking end grows into the last 0.8° of S3's half wall |
| S4\|S5 | 281.2 .. 290.8 | 3.0 m        | plain deck 282–290.5 |

Why 3 m: the guard's eye is (0, 28.90, 0) and a standing head on the lane is 24.80; that line crosses
r 47.55 at 2.15 m over the deck, 0.85 m under the head, and the whole deck width behind the wall is
under it (2.48 m at r 57). Proved at build time on the built rock (`MDL STATS lip_wall`): the crest by a
ray down every 0.05 m of the full-height run, every standing body on the lane behind it hidden at every
point, and the lane a stride past each end at deck height. `tests/test_map1_lip_walls.gd` repeats the
hidden check in Godot physics and runs a body at full speed past every wall on the outer side.

## Bots
Cover instances register exactly as the old CSG cover did (same group, same collision layers) so RunnerCoverFinder uses them. Bots never need to jump a gap: nothing on r 50–54 is lava.
