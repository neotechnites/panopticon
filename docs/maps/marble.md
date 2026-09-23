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
4. Cells: one arched recess per bay per tier -- 448 cells -- 4.0 m wide, 5.5 m tall (3.5 m jamb + semicircular head), Map 1's tallest cell, 3.0 m deep to a dark back wall. Every cell has five iron bars 0.13 m square over the arch, dark cool iron with a lit rim so they read from the lane, standing on the sill 0.5 m into the reveal and set into the head -- open cells, not screens. A bar is a straight square prism, the same 0.13 m section its full length (pass 8, Ryan: "the cell bars get thinner going up. they shouldnt do that, they should be the same width their full length" -- they had been pyramids, 0.127 m at the foot, 0.066 halfway, 0.004 under the head); its flat cap sits 0.06 m past the head's circle over the corner nearest the crown, buried in the arch, so the mesh stays closed.
5. Wall top: 1.8 m Greek-key frieze 55.0..56.8, great cornice 56.8..57.8 (0.8 m proud).
6. Dome: solid, springs at y 57.8 from r 60, rise 27.0, apex y 84.8, flat medallion r 4.2 at the crown, no oculus -- and its pattern is the DRAWING'S (pass 6, Ryan: "make the roof's design match the drawing"), not coffers, rebuilt clean in pass 7 (Ryan: "the ceiling of the marble room, its design became completely garbled"). Off the spring ring a smooth collar takes the first 3.2 m of arc, one quad per wall station (192) so every joint is vertical, up to a ring moulding 0.25 m proud and 0.7 m of arc tall; the wall's 192 stations become the dome's 176 on the moulding's foot step, a 0.25 m face looking down the sphere that nobody sees. On the moulding's head (r1) stand SIXTEEN broad meridional ribs, 6 deg wide and 0.85 m proud, running through six rings (r1 .. r6 at 0, 0.15, 0.30, 0.61, 0.89, 1.0 of the arc from the moulding to the cap) to the medallion, with ten plain panel facets between each pair; the five odd panel stations carry the flutes: each a V-groove two facets wide, 0.85 m deep where it stands on the ring, two PLANAR flanks tapering to a point at r3, a two-triangle foot on the moulding. Every face is a regular quad or a deliberate triangle: no zipper crosses a seen surface, so no chevrons, no crumpled pleats, no rib foot cut off over the collar (pass 6's 192-to-112 collar zipper, with the moulding's stripes fitted to each sliver, was the garble).
7. Tower (own glb, origin = guard-room datum, scene node at y 25.35), pass 6 to Ryan's verdict on pass 5: ONE round ashlar shaft of constant diameter, r 7.0 on two low steps (foot r 8.0 on the spike floor at y -1.0), from the floor to the roof -- no wider room at the top. At the guard floor (y 27.05) the shaft opens into a colonnade: sixteen 0.30 m columns on the shaft's own line at bearings 25 + 22.5k, open between them (openings 36.25 + 22.5k, 2.43 m wide, 27.05..31.47) and joined by ROUND ARCHES (pass 6, Ryan: "the columns aren't just holding a dome, they are arches"): each opening is a 2.43 m span springing at y 30.25 off the columns' sides and crowning at y 31.47 on the pier line between two facets, the spandrel over it solid to the beam, so the beam and the dome sit on the arcade and not on sixteen posts. It carries a 0.5 m ring beam (32.35..32.85) and a dome that sits on the arches (springs at y 32.85 from r 7.0, apex y 38.25, coffered inside). A functional balcony FLAT with the room floor (pass 5, Ryan): one level at y 27.05 through the columns onto a 1.2 m ledge on a 0.35 m slab, with a 1.0 m iron railing -- 32 posts 0.10 square, a mid rail and a top rail at y 28.05 -- and an invisible collider band in the railing's place, so nobody walks off. Room floor: the lane's paving in two rings of radial slabs, a plain margin to the columns, and at the centre a 0.6 m DAIS (r 2.2, plain grey top) the seat stands on: it lifts the guard's eye to y 29.3, 0.14 m over the rail top on the line to the lane's inner edge (0.26 m to the lane).
8. Guard: seat on the dais (TowerSpawn at +0.25), eye at y 29.3, 6.3 m over the lane at 52 m (7 deg down), as Map 1: the runners nearly at the tower's height, a little down. Light: one shadowed GOLD omni under the arcade at y 30.95 (over the guard's head, under the arches' crowns, so the beams go out THROUGH the arches) over a cool grey ambient; no sun, no sky. It is a SOFT lamp (pass 6, Ryan: "it's way way harsh in the middle of the tower"): 2.4 m wide, energy 22 against pass 5's 70, specular 0.25, shadow blur 3.0, and a falloff flat enough over a 140 m reach (attenuation 0.3) that the room's floor and the wall 60 m away are within a stop of each other -- no pool, no hot spot. Every number is `scenes/ring/marble_tower_light_profile.tres`; the review renders mirror it.
9. Budget: map 69,696 tris (floor + slab 12,096 / wall 57,600, of which 448 cells 31,360, 2,240 bars 8,960, pilasters 7,168, cornices 7,040, dome 2,688; collider 2,304), tower 4,380 (collider 1,278; the sixteen arched screens are 1,536 of it, the railing's 32 posts and two rails 1,344) -- map_base's class (71k): seven tiers of barred cells is what the drawing costs. One painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors. What the ARENA costs to draw, measured off the live tree by `tests/test_map_draw_budgets.gd` with the lane bare: 75,632 tris, 4 surfaces, 4 materials, 0 transparent tris, 2 lights, 1 shadow caster -- the four surfaces are the rotunda, the tower, the portal and the bars, and the two lights are the tower's lamp and the portal's glow. The ceilings in that file are that measurement + 20 % (tris 90,759, surfaces 5, materials 5, lights 3), with `shadow_casters` exact at 1.
9. Budget: map 70,432 tris (floor + slab 12,096 / wall 58,336, of which 448 cells 31,360, 2,240 bars 8,960, pilasters 7,168, cornices 7,040, dome 3,424; collider 2,304), tower 4,380 (collider 1,278; the sixteen arched screens are 1,536 of it, the railing's 32 posts and two rails 1,344) -- map_base's class (71k): seven tiers of barred cells is what the drawing costs. One painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors.
8. Guard: seat on the dais (TowerSpawn at +0.25), eye at y 29.3, 6.3 m over the lane at 52 m (7 deg down), as Map 1: the runners nearly at the tower's height, a little down. Light, since 2026-09-22 (Ryan: *"the lighting in the marble level is absolutely terrible"*): a sunlit temple's, in two parts, and no sun, no sky, no oculus still. The KEY is `Environment/Skylight`, one warm near-white omni `(1.0, 0.96, 0.86)` on the axis at y 62 -- over the tower's dome apex (38.25), under the wall top and the great dome -- energy 22, range 110, attenuation 0.5, 3 m wide, and the map's ONE shadow caster (cube, blur 2.0): the walkway slab shades the three tiers under it, every cell's bars shade its reveal, the cornices band the wall, the tower stands on its own shadow on the spike floor. The tower's lamp under the arcade (`marble_tower_light_profile.tres`, world y 30.95) is now a plain UNSHADOWED warm room light, `(1.0, 0.94, 0.80)`, energy 4, range 90, attenuation 0.35, 2.4 m wide, specular 0.25: it lights the guard room and, unoccluded, reaches under the walkway where the skylight cannot go. Ambient is a flat warm grey-olive `(0.60, 0.61, 0.55)` at 0.6 for the shadow floor; Reinhard with `tonemap_white` 6.0 so the room floor under the lamp rolls off instead of clipping. What it replaced, measured on the PC at 1080p (mean 8-bit luminance, Rec. 709): the lamp shadowed at energy 22 over a 0.3 falloff and a 140 m reach, deep gold `(1.0, 0.90, 0.66)`, over a cool ambient `(0.62, 0.66, 0.72)` at 0.62. Nothing above y 35 got direct light (the arch crowns at 31.47 cap the beams at 4 deg), so the top four tiers and the whole dome were black (lane: 22.8 % of pixels under 16); the guard room, 2-4 m from a 22-energy lamp, was white (guard's eye: mean 185, 45.6 % of pixels over 240); and the lit band on the lane was hard mustard scallops. After: lane mean 85 -> 107 (p50 80 -> 131, nothing over 240), guard 185 -> 105 (0.0 % over 240), portal looking back 92 -> 122. Frame time on the PC (RX 6600 XT, 1920x1080, 7 bots, 20 s, `tools/perf/profile_match.gd --map=marble`): runner's eye 1.050 -> 1.160 ms mean, fixed at the lane eye 0.863 -> 0.962 ms; the skylight's shadow is 0.11 ms of that (1.160 with, 1.048 with `--after=noshadow`). Renders: `~/Desktop/panopticon-renders/marble/light/{lane,guard,portal}_{before,after}.png`.
9. Budget: map 69,696 tris (floor + slab 12,096 / wall 57,600, of which 448 cells 31,360, 2,240 bars 8,960, pilasters 7,168, cornices 7,040, dome 2,688; collider 2,304), tower 4,380 (collider 1,278; the sixteen arched screens are 1,536 of it, the railing's 32 posts and two rails 1,344) -- map_base's class (71k): seven tiers of barred cells is what the drawing costs. One painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors. What the ARENA costs to draw, measured off the live tree by `tests/test_map_draw_budgets.gd` with the lane bare: 75,632 tris, 4 surfaces, 4 materials, 0 transparent tris, 3 lights, 1 shadow caster -- the four surfaces are the rotunda, the tower, the portal and the bars, and the three lights are the skylight, the tower's lamp and the portal's glow. The ceilings in that file are that measurement + 20 % (tris 90,759, surfaces 5, materials 5, lights 4), with `shadow_casters` exact at 1.
9. Budget: map 83,872 tris (floor + slab 12,096 / wall 71,776, of which 448 cells 31,360, 2,240 bars 22,400 -- 10 each, a closed prism against the pyramid's 4 -- pilasters 7,168, cornices 7,040, dome 3,424; collider 2,304), tower 4,380 (collider 1,278; the sixteen arched screens are 1,536 of it, the railing's 32 posts and two rails 1,344) -- map_base's class (71k): seven tiers of barred cells is what the drawing costs. One painted 256 px atlas (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_albedo.png`), emissive only in the cell interiors.

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

## The bare lane

Ryan, 2026-09-22: *"for the marble level, can you just get rid of all the
elements on the ring? just so it looks good for screenshots and trailers and
stuff."* The six-stretch obstacle course written up here before came out of
`scenes/ring/marble.tscn`: 18 columns, 21 broken columns, 9 arches, 7 spike
patches, 11 spike strips, 3 demon pads and 2 speed orbs -- 71 placed instances
in `Sections`, and the `Sections` node with them. The lap is 340 deg of clear
gallery again, exactly as the rotunda was first delivered.

What stayed, because without it this is not a map: the two meshes
(`marble.glb`, `marble_tower.glb`), the two lethal volumes that are the
building itself (`SpikeFloor` over the open drop, `KillBox` under the world),
the tower's lamp and the cool ambient, `PrisonerStart` / `PrisonerEnd` /
`TowerSpawn`, the `Route` the lap is measured on, and the portal at 345 deg --
the lap has to end somewhere, and `tests/test_maps.gd` reads all three markers.
The five `guard_watch` markers stayed too, moved out of `Sections` to a `Watch`
node of their own and renamed by bearing (044, 106, 235, 294, 336): they draw
nothing and collide with nothing, so they are not an element on the ring, and
deleting them would change how the guard sweeps.

**And the bars at 353 deg stayed, on the measurement.** They were on the list
to go, and taking them off breaks the map rather than clearing it. A finish
gate in the scene means standing in it is the win -- `MatchLapTracker`, no
checkpoints -- and with nothing across the gap between finish (345) and start
(5), `RingBake` links `PrisonerStart` to `PrisonerEnd` the short way:

| bars | bake walk start -> end | harness, 10 matches |
|---|---|---|
| removed | **18.06 m**, 10 waypoints, backwards through the gap | 7 of 10 UNRESOLVED, 101-129 one-shot rounds, runners win 100% |
| kept | **288.15 m**, 58 waypoints, the lap | 10 of 10 resolved, CLEAN |

A bot runner simply walks 18 m backwards to the portal. The bars stand behind
the finish, outside the 340 deg run, so they are in no shot of the lane: they
cost the screenshots nothing and they are what makes the lap a lap.

Nothing was deleted from `assets/models/` and no build script changed. The
course props -- `marble_column.glb`, `marble_column_broken.glb`,
`marble_arch.glb`, `marble_spikes.glb`, `marble_spikes_strip.glb` -- are all
still built and still shipped, and the two trap scenes
`marble_spike_patch.tscn` / `marble_spike_strip.tscn` still exist. Only the
placements went, so putting a course back is a scene edit.

Measured on the bare lane: the arena draws 89,808 tris across 4 surfaces
(75,632 before the cell bars became prisms; 99,250 across 75 with the course); `RingBake` bakes 276 polygons with 2 lethal
volumes carved and finds 164 cover points, against 209 with the course -- the
164 this doc always recorded for the bare lane.

Renders of the cleared ring: `~/Desktop/panopticon-renders/marble/clear/`
(`aerial.png`, `lane.png`, `guard.png`, `portal.png`).
