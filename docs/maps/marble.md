# Map 2 -- marble

The Bentham drawing built in the Temple of Time's stone: one closed rotunda,
seven tiers of barred arched cells in the wall, a tall round guard lodge in
the middle, and the ring lane a gallery walkway partway up the wall of cells
with its inner edge open over a floor of marble spikes. Warm sandy grey-green
ashlar with darker mortar joints, gold light pools from the lantern, cool
grey-olive shadow (the palette sampled below). Nothing on the lane.

Two models, as Map 1: `maps/marble/models/marble.glb` (the whole rotunda, one
contiguous mesh) and `maps/marble/models/marble_tower.glb` (the tower, one
contiguous mesh, dropped in by the scene at the guard-room datum). The build
scripts prove contiguity on every build (`--check`): one connected component,
every edge on exactly two faces, no duplicate positions.

The shape, as numbers (world y; the scene instances both at identity /
the Map 1 tower datum):

1. Spike floor: the rotunda's ground, a flat disc at y -1.0 from the axis to the wall foot at r 60. Square marble spikes stitched into the floor's own cells on a low plinth, 1.4..2.8 m tall, from r 10.3 (the tower's foot) to r 45.5 (under the walkway's lip), clustered by a seeded field; every tip under y 2.0. Lethal: one KillVolume cylinder r 46.3 (a capsule's radius inside the lip), roof y 23.5 -- over the lane, so RingBake carves it out of the bots' mesh -- down to y -3.0.
2. Walkway: a marble gallery slab, top at y 23.0 (Map 1's lane height), r 46.7 to the wall at 59.55, 1.0 m thick (underside y 22.0); paving r 46.8..57.3 in 128 facets with a plain stone margin to the wall; a chamfered nosing at the inner lip. The inner edge is OPEN: no parapet, no bed beside the lane; step off and you fall 24 m to the spikes, the only hazard. Run 5 deg -> 345 deg at r 52; the bars between finish and start (353 deg) and the portal at the finish are THIS map's own fixtures, not Map 1's hell rock (pass 7, Ryan: "now create bars and portals that match the actual maps"). `marble_bars.glb` is an iron portcullis in a marble frame in the wall's own architecture -- ashlar plinth, fluted pilaster jambs 0.45 m proud, a 6.00 x 6.20 m mouth under a semicircular head r 3.00 crowning at 7.20, a cornice moulding across the top, 12 bars 0.13 m square at a 0.342 m pitch with 3 cross-bars, the iron the cells' own near-black -- SPANNING THE WALKWAY WALL TO LIP: 12.85 m across (r 46.7 to 59.55), 8.5 x 0.5 m, origin the base centre, its centre at r 53.125, and no gap anywhere over 0.38 m. It inherited rock_bars.glb's 10.6 m envelope and Map 1's lane is 10.6 m wide where this one is 12.85, so on the lane centre at r 52.0 the collider reached only r 46.7007..57.3005 and left 2.2495 m of open floor between its outer end and the cell wall -- a body walked ROUND the gate to the portal (pass 9, Ryan: "the gate doesnt block anyone from going past it to the portal"). The extra 2.25 m went into the flanking ashlar field; mouth, jambs, bars, cornice and height are unchanged. `tests/test_marble_gate.gd` is what says it holds, and it asks the engine rather than the eye: nine capsules (r 0.4, h 1.8) dropped across the whole walkway and driven at the gate at 11 m/s by `move_and_slide`, closest approach 0.653 m short of the gate plane; 28,935 rays through the collider in 45 height bands, widest opening 0.360 m; and the collider's top 5.586 m clear of the crown of a jumping body (7 m/s over 22 m/s^2 tops out at 1.1136 m). `marble_portal.glb` is the same architecture as a 4.5 x 4.0 x 0.8 m aedicule round portal.glb's exact opening (2.7 m clear, springing 2.60, apex 3.15, surface centre 1.50), so maps/marble/props/marble_portal.tscn is portal.tscn node for node -- same Glow, same Gate, same finish_gate group -- and the effect surface keeps portal_build's own swirl and material, painted into marble's spare atlas cell. 1,384 and 172 visual tris; each is one closed contiguous mesh (components 1, boundary 0, duplicate positions 0). The slab is the third tier's cornice, extended.
3. Wall: face at r 60 from y -1.0, 64 bays of 5.9 m; SEVEN tiers of 8.0 m (bases -1 / 7 / 15 / 23 / 31 / 39 / 47): three below the walkway down to the spike floor, four above it. A 0.6 m cornice on each tier and a 1.0 m pilaster on every pier, both 0.45 m proud; a 1.0 m socle under every sill.
4. Cells: one arched recess per bay per tier -- 448 cells -- 4.0 m wide, 5.5 m tall (3.5 m jamb + semicircular head), Map 1's tallest cell, 3.0 m deep to a dark back wall. Every cell has five iron bars 0.13 m square over the arch, dark cool iron with a lit rim so they read from the lane, standing on the sill 0.5 m into the reveal and set into the head -- open cells, not screens. A bar is a straight square prism, the same 0.13 m section its full length (pass 8, Ryan: "the cell bars get thinner going up. they shouldnt do that, they should be the same width their full length" -- they had been pyramids, 0.127 m at the foot, 0.066 halfway, 0.004 under the head); its flat cap sits 0.06 m past the head's circle over the corner nearest the crown, buried in the arch, so the mesh stays closed.
5. Wall top: 1.8 m Greek-key frieze 55.0..56.8, great cornice 56.8..57.8 (0.8 m proud).
6. Dome: solid, springs at y 57.8 from r 60, rise 27.0, apex y 84.8, flat medallion r 4.2 at the crown, no oculus -- and its pattern is the DRAWING'S (pass 6, Ryan: "make the roof's design match the drawing"), not coffers; pass 7 rebuilt it clean (Ryan: "the ceiling of the marble room, its design became completely garbled") and pass 8 took the modelled flutes off it (Ryan: "only the triangles ... they just painted on the roof"). Off the spring ring a smooth collar takes the first 3.2 m of arc, one quad per wall station (192) so every joint is vertical, up to a ring moulding 0.25 m proud and 0.7 m of arc tall; the wall's 192 stations become the dome's 112 on the moulding's foot step, a 0.25 m face looking down the sphere that nobody sees. On the moulding's head (r1) stand SIXTEEN broad meridional ribs, 6 deg wide and 0.85 m proud, running through five rings (r1 .. r5 at 0, 0.30, 0.61, 0.89, 1.0 of the arc from the moulding to the cap) to the medallion. Between each pair a SMOOTH panel of six facets wearing the drawing's band of pointed flutes PAINTED: the `dome` atlas sheet (the two spare cells as one 128 x 64 px sheet, `marble_build._paint_dome`) is one panel -- fourteen flutes standing on the ring, lit one side and shadowed the other, their points at 0.30 of the arc under a line, stippled stone above, the grain laid along the rows because a texel is 0.14 m across and 0.9 m up the arc -- and every panel quad states its own (u, v) per vertex from azimuth and latitude, so the band sits at one height all round and nothing smears at the crown. Every face is a regular quad or a deliberate triangle; no zipper crosses a seen surface.
7. Tower (own glb, origin = guard-room datum, scene node at y 25.35), pass 6 to Ryan's verdict on pass 5: ONE round ashlar shaft of constant diameter, r 7.0 on two low steps (foot r 8.0 on the spike floor at y -1.0), from the floor to the roof -- no wider room at the top. At the guard floor (y 27.05) the shaft opens into a colonnade: sixteen 0.30 m columns on the shaft's own line at bearings 25 + 22.5k, open between them (openings 36.25 + 22.5k, 2.43 m wide, 27.05..31.47) and joined by ROUND ARCHES (pass 6, Ryan: "the columns aren't just holding a dome, they are arches"): each opening is a 2.43 m span springing at y 30.25 off the columns' sides and crowning at y 31.47 on the pier line between two facets, the spandrel over it solid to the beam, so the beam and the dome sit on the arcade and not on sixteen posts. It carries a 0.5 m ring beam (32.35..32.85) and a dome that sits on the arches (springs at y 32.85 from r 7.0, apex y 38.25, coffered inside). A functional balcony FLAT with the room floor (pass 5, Ryan): one level at y 27.05 through the columns onto a 1.2 m ledge on a 0.35 m slab, with a 1.0 m iron railing -- 32 posts 0.10 square, a mid rail and a top rail at y 28.05 -- and an invisible collider band in the railing's place, so nobody walks off. Room floor: the lane's paving in two rings of radial slabs, a plain margin to the columns, and at the centre a 0.6 m DAIS (r 2.2, plain grey top) the seat stands on: it lifts the guard's eye to y 29.3, 0.14 m over the rail top on the line to the lane's inner edge (0.26 m to the lane).
8. Guard: seat on the dais (TowerSpawn at +0.25), eye at y 29.3, 6.3 m over the lane at 52 m (7 deg down), as Map 1: the runners nearly at the tower's height, a little down. Light, since 2026-09-22 (Ryan: *"the lighting in the marble level is absolutely terrible"*): a sunlit temple's, in two parts, and no sun, no sky, no oculus still. The KEY is `Environment/Skylight`, one warm near-white omni `(1.0, 0.96, 0.86)` on the axis at y 62 -- over the tower's dome apex (38.25), under the wall top and the great dome -- energy 22, range 110, attenuation 0.5, 3 m wide, and the map's ONE shadow caster (cube, blur 2.0): the walkway slab shades the three tiers under it, every cell's bars shade its reveal, the cornices band the wall, the tower stands on its own shadow on the spike floor. The tower's lamp under the arcade (`marble_tower_light_profile.tres`, world y 30.95) is now a plain UNSHADOWED warm room light, `(1.0, 0.94, 0.80)`, energy 4, range 90, attenuation 0.35, 2.4 m wide, specular 0.25: it lights the guard room and, unoccluded, reaches under the walkway where the skylight cannot go. Ambient is a flat warm grey-olive `(0.60, 0.61, 0.55)` at 0.6 for the shadow floor; Reinhard with `tonemap_white` 6.0 so the room floor under the lamp rolls off instead of clipping. What it replaced, measured on the PC at 1080p (mean 8-bit luminance, Rec. 709): the lamp shadowed at energy 22 over a 0.3 falloff and a 140 m reach, deep gold `(1.0, 0.90, 0.66)`, over a cool ambient `(0.62, 0.66, 0.72)` at 0.62. Nothing above y 35 got direct light (the arch crowns at 31.47 cap the beams at 4 deg), so the top four tiers and the whole dome were black (lane: 22.8 % of pixels under 16); the guard room, 2-4 m from a 22-energy lamp, was white (guard's eye: mean 185, 45.6 % of pixels over 240); and the lit band on the lane was hard mustard scallops. After: lane mean 85 -> 107 (p50 80 -> 131, nothing over 240), guard 185 -> 105 (0.0 % over 240), portal looking back 92 -> 122. Frame time on the PC (RX 6600 XT, 1920x1080, 7 bots, 20 s, `tools/perf/profile_match.gd --map=marble`): runner's eye 1.050 -> 1.160 ms mean, fixed at the lane eye 0.863 -> 0.962 ms; the skylight's shadow is 0.11 ms of that (1.160 with, 1.048 with `--after=noshadow`). Renders: `~/Desktop/panopticon-renders/marble/light/{lane,guard,portal}_{before,after}.png`.
9. Budget: map 82,688 tris (floor + slab 12,096 / wall 70,592, of which 448 cells 31,360, 2,240 bars 22,400 -- 10 each, a closed prism against the pyramid's 4 -- pilasters 7,168, cornices 7,040, dome 2,240 (was 3,424 with the flutes modelled, 2,688 in pass 6); collider 2,304), tower 4,380 (collider 1,278; the sixteen arched screens are 1,536 of it, the railing's 32 posts and two rails 1,344) -- map_base's class: seven tiers of barred cells is what the drawing costs. One tiling sheet per material class through `lib/texel.py` on all three meshes (USE_TEXTURE_FILES swaps in `tools/modelling/textures/marble_<class>_albedo.png`), emissive only in the cell interiors. What the ARENA costs to draw, measured off the live tree by `tests/test_map_draw_budgets.gd` with the lane bare: 88,624 tris, 31 surfaces, 31 materials, 0 transparent tris, 3 lights, 1 shadow caster -- a surface per material class now that all three meshes are on `texel.py` (rotunda 12, tower 11, gate 7, portal 1), and the three lights are the skylight, the tower's lamp and the portal's glow. The triangle count did not move when the tower and the gate went onto the sheets: the tower's geometry is bit-identical and the widened gate kept its topology. The ceilings in that file are that measurement + 20 %, with `shadow_casters` exact at 1 and the tris ceiling left where it was because the number did not change.

## The tower and the gate on the sheets

Ryan, 2026-09-23: *"for the marble map, the center of the tower is wobbly, and
it shouldnt be, the texturing on the dome of the tower looks like it didnt get
fixed, and the gate doesnt block anyone from going past it to the portal"*, and
*"the texturing on the gate is bad, you seemed to fix it for the maps generally,
and it looks much better."*

**The wobble was never geometry.** Measured off `marble_tower.glb` before a line
was changed: at all 43 distinct heights in the model the ring's centre sits at
`0.000000000` m from the axis, and the shaft's 272 vertices are at r
`6.999999709..7.000000103`. The shaft was already dead straight and concentric.
What wandered was the stone on it. The tower and the gate were the last two
models still on the 256 px atlas with `marble_build.unwrap`'s **per-face random
window**, so the shaft's ashlar had no continuous course at all -- just isolated
mortar marks at arbitrary heights on arbitrary facets, against the rotunda's
crisp courses right behind it -- and the tower's dome was a patchwork outside and
coffers that shrank and skewed toward the crown inside, each fitted to its own
face. Both now go through `lib/texel.py` exactly as the map does, and the centre
reads straight because the courses do.

Densities, all at the rotunda's own `WALL_MPT` (a bay, 5.890 m, over 128 texels
= **0.0460 m per texel**), sheets 261 px tall = twelve 1.0 m courses:

| | |
|---|---|
| tower shaft (`stone`, `shade`, `plinth`) | cyl, ref_r 7.0, 60 px across -- closes at exactly **16 repeats**, one per facet, so every vertical joint lands on a facet corner and every course line on the rotunda's world 1 m grid (phase v0 = FOOT_Z -26.35) |
| tower balcony (`marble2`) | cyl, ref_r 8.2, 35 px -- 32 repeats, one per balcony facet |
| tower dome, both shells | `custom`: azimuth across, meridian ARC LENGTH up, so the texel is the same size from spring to apex and each cap triangle gets the apex its own u. Skin: 9.75 m of arc, 0.0460 up and 0.0458 across at the spring. Coffers: 9.28 m of arc, six rows of 1.55 m, 0.0455 up -- one coffer size the whole way to the crown |
| gate stone (`marble`, `marble2`, `shade`, `plinth`) | `box` (a flat slab has no ring to close), 65 x 261, 0.0460, phased so a course joint lands on the sill at 1.0 and the socle's on the ledge at 0.85 |
| gate iron | `box`, 58 x 256, **0.0081 m per texel** -- a 0.13 m bar is 16 texels across, so the lit arris is a line and not a band |

Geometry did not move. The tower's positions are bit-identical to the model that
shipped before (2034 art and 610 collision positions, elementwise max difference
`0.000000000`), 4,380 visual tris and 1,278 collision tris unchanged; the gate's
drawn mesh is 1,384 tris before and after. Both are one connected component with
zero boundary edges and zero duplicate positions, and both build byte-for-byte
identically on the Mac and the PC (`model parity`). What changed is the surface
count -- the tower 1 -> 11, the gate 1 -> 7 -- and the glTF vertex pools actually
*shrank* (tower 10,381 -> 8,859), because a world-locked projection shares UVs
across an edge where a random window had to split them.

The gate's collider is the other half of that pass, and it grew: the sweep in
`tests/test_marble_gate.gd` found holes in it the drawn stone never had (5.995 m
at z 0.87, 2.72 m at z 7.11), so the sill band, the spandrel and the bar boxes
were closed and collision went 264 -> 624 tris.

Captures, before and after, at
`~/Desktop/panopticon-renders/marble/fixes/`.


## The wobble was the sampling, not the sheets

Ryan, after that pass shipped: *"the marble tower is still wobbly."*

The pass above was a real fix and it was not this one. It put the right picture
on the tower; nothing was giving the engine a way to read it correctly at
distance.

**Looked at in the game, in flat grey, first.** `tools/shot.gd --flat=1`
overrides every drawn surface with one plain grey and is new here, because
ENGINEERING's *"if the form is not readable in flat grey, it is wrong"* had
nothing that could take that picture in the game. In that capture from the lane
the shaft is a clean rectangle: the silhouette's left edge sits at x 810 and the
right at x 1110 and neither moves by a pixel over 550 px of height. Textured,
from the same pose, the same shaft is a scatter of broken dashes. One picture,
and geometry was out.

**The ruled-out list, with the number that ruled each out.**

| candidate | measurement | verdict |
|---|---|---|
| silhouette | flat capture, mid pose, bare shaft: left 810, right 1110, over 550 px of height | straight, 0 px |
| section | all 9 bare-shaft rings, max−min radius within a ring | regular, 4.2e-7 m |
| stacking | ring-to-ring azimuth drift against ring 0 | aligned, 0.000000000 deg |
| axis | per-ring centroid | on axis, 0.000000000 m |
| normals | angle between a shaft triangle's own three vertex normals, all 372 | flat, 0.0000 deg, no alternation |
| concentricity | ledge r 8.2, beam 7.00–7.50, slab, 16 columns: fitted centres | concentric to 1e-9 m |
| texture | the flat capture above, and the headless probe below | **the cause** |

**What it actually was.** `marble_tower.glb` embeds its eleven albedo sheets
(`gltf/embedded_image_handling=3`). Godot's glTF importer builds each as an
`ImageTexture` with **no mip chain**, while every material asks for
`texture_filter` 2, `NEAREST_WITH_MIPMAPS`. Headless, before: all eleven
surfaces report `filter=2 mipmaps=false`. The filter names a mip level that is
not there, so every pixel samples mip 0 at any distance. From the lane the shaft
is about 110 px wide across 14 m, so one screen pixel covers roughly 2.5 texels
of a 0.046 m sheet and the 1-texel mortar joints are sampled at random: they
break into disconnected dashes, and they crawl when the camera moves. That is
the wobble, and repainting the sheets could never have touched it.

**The fix.** `tools/import/mipmap_textures.gd`, an `EditorScenePostImport` hook
on `maps/marble/models/marble_tower.glb.import`: it gives each embedded sheet a mip
chain and sets the material to `NEAREST_WITH_MIPMAPS_ANISOTROPIC`. NEAREST
magnification is the art's deliberate pixel look and survives untouched — only
minification changes. It is a post-import hook rather than
`gltf/embedded_image_handling=1` because `tools/pc_sync.sh`, `tools/pc_shot.sh`
and `tools/fix_glb_imports.sh` all rewrite that key back to `3` and none of the
three touches `import_script/path`.

**After**, same eleven surfaces: `filter=4 mipmaps=true`. In the lane capture the
mean unbroken run of a course line across the shaft goes **9.1 px → 39.5 px** of
110 px of shaft width; at 15 m it is 10.0 → 11.3, essentially unmoved, which is
mip 0 still serving the near view exactly as before. Geometry is untouched and
the flat captures prove it: the tower's silhouette is **0 px different** before
and after in the mid, base and orbit poses, and the `.glb` is byte-identical —
4,380 art tris, 1,278 collision tris, one connected component each.

`tests/test_marble_tower_texture.gd` holds it: eleven sheets, every one with a
mip chain, every material on `NEAREST_WITH_MIPMAPS_ANISOTROPIC`.

**Scope, measured and left alone.** Every other textured `.glb` in
`assets/models/` has the same missing mip chain — `marble.glb` 12 surfaces,
`marble_bars.glb` 7, `map_base.glb` 6, `hub_base.glb` 5, `forest.glb` 13, and one
each for the props. `marble_tower.glb` is the only one changed here, because the
tower is what was asked about.

Captures, before and after, at
`~/Desktop/panopticon-renders/marble/wobble/{lane,base,mid,orbit,flat}_{before,after}.png`.


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
`maps/marble/marble.tscn`: 18 columns, 21 broken columns, 9 arches, 7 spike
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
(75,632 before the cell bars became prisms; 99,250 across 75 with the course); `RingBake` bakes 281 polygons with 2 lethal
volumes carved and finds 164 cover points (276 before the gate was widened to
span the walkway, 2026-09-23; the cover count is unchanged), against 209 with the course -- the
164 this doc always recorded for the bare lane.

Renders of the cleared ring: `~/Desktop/panopticon-renders/marble/clear/`
(`aerial.png`, `lane.png`, `guard.png`, `portal.png`).
