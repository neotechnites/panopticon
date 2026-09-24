# Performance review — PANOPTICON

Measured on the PC (Ryan's box: i7-6700, AMD Radeon RX 6600 XT, Godot 4.7.2,
GL Compatibility) at 1920×1080 windowed, vsync off, from a bots-only match built
by `tools/perf/profile_match.gd`. Model figures are parsed straight out of the
`.glb` files. Nothing here is estimated unless it says so.

**The headline** (true of map 1, and see the 2026-09-16 section for where it
stops being true: on map 2 the renderer IS the problem, and it is one light).
The renderer is not the problem and never was: the whole arena
draws in **1.0 ms** — a thousand frames a second — in 15–25 draw calls. Every
frame this game misses is spent in the bot AI's physics tick, which at seven
bots runs **40–53 ms against a 16.7 ms budget** and produces stalls up to 170 ms.
The 88k-triangle arena is worth tidying but it is not what costs anything today.

---

## 1. Models

`assets/models/*.glb`, visible triangles after scene expansion. The `-colonly`
meshes a glTF ships import as collision, not geometry, so they are counted
separately — they cost physics, not draw calls.

| # | model | vis tris | surfaces | materials | collider (tris) | textures | file |
|---|---|---|---|---|---|---|---|
| 1 | `map_base.glb` | **88,231** | 3 | 3 (HellRock, LavaSea, LavaRiver) | yes — 16,340 | 2×512², 1×256², 2×128² (344 KB) | 10.2 MB |
| 2 | `hub_base.glb` | 17,782 | 3 | 3 (HellRock, Lava, HubStone) | yes — 7,964 | 4×128², 1×256² (39 KB) | 2.1 MB |
| 3 | `tower_interior.glb` | 5,195 | 1 | 1 | yes — 2,533 | 2×128² (14 KB) | 680 KB |
| 4 | `tower_arches.glb` | 4,010 | 1 | 1 | yes — 144 | 2×128² (14 KB) | 375 KB |
| 5 | `tower.glb` | 1,194 | 1 | 1 | yes — 144 | 2×128² (14 KB) | 135 KB |
| 6 | `eye.glb` | 768 | 3 | 3 | none | none | 21 KB |
| 7 | `rock_bars.glb` | 1,036 | 2 | 2 (HellRock, HellShade) | yes — 132 | 4×256² (90 KB) | 186 KB |
| 8 | `tower2.glb` | 858 | 1 | 1 | yes — 70 | 2×128² (14 KB) | 105 KB |
| 9 | `husk_a/b/c.glb` | 702 / 698 / 604 | 1 | 1 | none | 1×32–128² | 83–110 KB |
| 10 | `creature1–4.glb` | 636–680 | 1 | 1 | none | 1×128² | 87–93 KB |
| — | `prisoner2.glb` (the player) | 620 | 1 | 2 | none | 1×32² | 136 KB |
| — | `rifle.glb` | 372 | 1 | 1 | none | 2×128² (21 KB) | 47 KB |
| — | every ring prop (`spire`, `slab`, `rock_wall`, `boulder`, `demon_pad`, `lava_tile`, `block`, `torch`, `speed_orb`) | 20–118 | 1–2 | 1 | yes, 4–40 | 2×128² | 12–38 KB |

Textures are already tiny — 128² for everything except the lava pair at 512²
and the classes that have moved to `lib/texel.py`'s 256² tiling sheets
(`map_base`, and `rock_bars` since the gate was remade as a cave wall: two
sheets instead of one atlas is +1 surface and +1 material on the Ring, 66 and
17 against `test_map_draw_budgets.gd`'s 78 and 18. A third sheet was built and
then dropped — `ember`, ten glowing triangles inside the slots — precisely
because it would have spent the Ring's last material slot.)
Nothing in the texture budget is worth touching.

### The one outlier: `map_base.glb`

88,231 visible triangles in **one MeshInstance3D of three surfaces**. Triangles
bucketed by their centroid's bearing round the ring:

| region | tris | share |
|---|---|---|
| **S1 The Spires (15–60°)** | **33,028** | **37.4 %** |
| S2 The Lava Shelf (75–130°) | 13,972 | 15.8 % |
| rest pockets + gaps between sections | 12,844 | 14.6 % |
| S4 Demon Run (215–270°) | 11,783 | 13.4 % |
| S5 The Wall Run (285–335°) | 8,231 | 9.3 % |
| S3 The Split (145–200°) | 7,087 | 8.0 % |
| pit wall / courtyard (r < 44) | 1,224 | 1.4 % |
| outer wall (r > 60) | 62 | 0.1 % |

By material: HellRock 78,857 (89.4 %), LavaRiver 8,142 (9.2 %), LavaSea 1,232 (1.4 %).

Per 15° of ring, S1 carries ~11,000 triangles where S3 and S5 carry ~2,200 —
**five times the density for the same length of track.** S1 is the whole story:
drop it to the density of S3/S5 and the arena becomes ~62k triangles for no
visible change anywhere else.

**Recommendation — worth doing, but not urgent.** At 1.0 ms for the entire
arena on this GPU there is nothing to reclaim here today; this matters for the
iGPU-class machine Ryan's "potato" bar is really about.

1. **Split the mesh per section before anything else.** One 88k mesh spanning a
   120 m ring is submitted whole from every camera angle: frustum culling can
   never reject any of it, `visibility_range_*` can never apply to part of it,
   and an occluder can never hide part of it. Six meshes (S1…S5 + pit) would let
   a player standing in S3 pay for S3. Cost: a change in the Blender export, not
   in code. Expected: 60–80 % of the arena's vertex work culled at any one time.
2. **Then decimate S1.** 33k triangles for one 45° arc of rock is an accident,
   not a design. Target ~7k, matching S3.
3. **LOD and occluders only after the split.** `visibility_range_begin/end` is
   set on nothing in this project and there is no `OccluderInstance3D` anywhere;
   both are useless while the arena is one mesh and both become easy once it is
   six.
4. `tower.glb` and `tower_arches.glb` are both instanced under `Tower/` and
   `TowerVariant` hides the unselected one — but each ships its own 144-tri
   `TowerCollision-colonly`, so **two concave trimesh colliders sit at the same
   place for the life of the scene**, one permanently masked off. Free to fix,
   saves nothing measurable; listed because it is pure waste.

No model was changed.

---

## 2. Frame cost on the PC

`tools/perf/profile_match.gd` builds a bots-only match (the same `BotMatchWorld`
the harness uses — arena, N runner bodies, one rifle, a `MatchController` and an
AI tower seat), puts a camera on a running bot, and logs Godot's performance
monitors once a second, reporting the mean and the mean of the worst 1 % of
frames.

```
godot --path . --script res://tools/perf/profile_match.gd -- \
    --seconds=60 --runners=3 --view=runner --width=1920 --height=1080
```

**Running it on the PC over ssh.** A Windows OpenSSH session is not the
interactive desktop session, so Godot there cannot get an OpenGL context at all
(`Failed to create ANGLE OpenGL window`) and silently falls back to nothing
useful. Every number above was taken by handing the run to the logged-on
session:

```powershell
schtasks /create /tn PerfRun /tr "C:\dev\perfrun.bat" /sc once /st 00:00 /it /f
schtasks /run /tn PerfRun
```

where `perfrun.bat` reads its arguments from a file and redirects stdout. Without
`/it` the run has no GPU.

It also carries the bisect switches this review was written with: `--static=1|2|3`
(arena only / + bodies / + rifle), `--stage=1|2|3` (world built / + tower seat /
+ `start_match`), `--disable=traps,brains,bodies,controller,scripted` and
`--after=stopanim,freeagents,nolights,freemap,freebodies`.

### The measurement trap, recorded so nobody repeats it

The first runs read **27 fps**. They were wrong. `MatchController.start_match()`
transitively instantiates the settings store, which pushes the player's saved
video settings — and the default is **vsync ENABLED**. A profiler window that is
not the foreground window on Windows then gets throttled by the compositor to
roughly half rate, so every number was a present stall rather than work. The
tell: 640×360 measured exactly the same as 1920×1080. `profile_match.gd` now
re-asserts `VSYNC_DISABLED` every frame.

### Baseline (before the fixes in this branch)

60 s each, 1080p, camera on a running bot.

| bots | frames | mean | median | p99 | worst 1 % | physics tick (steady → race) |
|---|---|---|---|---|---|---|
| 2 | 46,447 | 1.292 ms (774 fps) | 0.973 ms | 5.06 ms | **8.22 ms (122 fps)** | 2–11 ms |
| 3 | 49,657 | 1.209 ms (827 fps) | 0.880 ms | 5.72 ms | **9.45 ms (106 fps)** | 3–18 ms |
| 7 | 30,598 | 1.970 ms (508 fps) | 1.451 ms | 13.93 ms | **29.72 ms (33.6 fps)** | **40–53 ms** |

Worst single frames: 92 ms at 2 bots, 42 ms at 3, **170 ms at 7**.

Read it as: the mean is irrelevant, the tail is the game. Two to three bots hold
60 fps with room to spare. Seven bots do not — the physics tick alone is three
times the frame budget, and the bot count is the only thing that moved.

### Where the cost is — bisected, not guessed

Each row is a separate 8–15 s run at 1080p.

| what is in the scene | mean frame |
|---|---|
| arena alone (`--static=1`) | **1.0 ms** (983 fps), 25 draw calls, 94,827 primitives |
| arena + 3 bot bodies, scripts running (`--static=2`) | 1.18 ms (845 fps) |
| arena + 3 bodies + rifle (`--static=3`) | 1.13 ms (882 fps) |
| full world built, match **not** started (`--stage=2`) | 1.31 ms (762 fps) |
| full world, `start_match()` called (`--stage=3`) | **1.17 ms**, physics tick 5 ms steady / 22 ms during the opening race |
| same, at 640×360 instead of 1080p | unchanged |
| same, all 20 lights freed | unchanged |
| same, all 45 meshes hidden | unchanged |

Rendering, resolution, lights and geometry move the number by nothing. Arming
the bots moves it by everything.

### Script-side profile (headless, Mac, `--disable` bisect)

The per-frame `_process` side is close to free once the trap volumes are asleep:
22 `TrapVolume`s were each calling `Area3D.get_overlapping_bodies()` — one array
allocation apiece — on every frame of the match. Everything else that costs is
in `_physics_process`, and within that the order is:

1. **`RingRunner` cover planning** (`_choose_target` → `_search_cover` +
   `NavigationServer3D.map_get_path` + `_measure_exposure`) — dominates whenever
   a runner is exposed and has not yet found a target.
2. **`RunnerPerception.sight_hit`** — the raycast every one of the above goes
   through; ~25 rays per exposed bot per tick.
3. **`TowerShooter._visible_targets`** — one group sweep + one ray per candidate
   per tick, plus a node lookup per candidate.
4. **`BotIntentSource._look_for_a_shove`** — a whole-group query per bot per tick.
5. HUD and audio: negligible next to the above, but both were doing avoidable
   per-frame work (below).

### After the fixes in this branch

Same tool, same 60 s, same machine, same camera.

| bots | mean | worst 1 % | max physics sample |
|---|---|---|---|
| 2 | 1.292 → **1.045 ms** (774 → **957 fps**) | 8.22 → **7.78 ms** (122 → **129 fps**) | 15.9 → 23.3 ms |
| 3 | 1.209 → **1.126 ms** (827 → **888 fps**) | 9.45 → 10.32 ms (106 → 97 fps) | 26.3 → **25.8 ms** |
| 7 | 1.970 → **1.749 ms** (508 → **572 fps**) | **29.72 → 16.67 ms (33.6 → 60.0 fps)** | **70.5 → 40.8 ms** |

The seven-bot case is the one that matters and it is the one that moved: the
worst 1 % of frames went from 33.6 fps to **exactly 60**, a 44 % cut in the
tail, and the worst physics tick of the run halved. The three-bot tail reads
slightly worse, which is run-to-run variance — each run is a different match
with different rounds and seat changes; see the repeat runs below.

| repeat, 3 bots, after | mean | worst 1 % |
|---|---|---|
| run 1 | 1.126 ms (888 fps) | 10.32 ms |
| run 2 | 1.159 ms (863 fps) | 12.72 ms |
| run 3 | 1.122 ms (891 fps) | 11.23 ms |

A ±2.4 ms spread on the three-bot tail across three identical runs, against a
"regression" of 0.9 ms. There is no regression; there is also no win to claim at
three bots, because three bots were never the problem.

Still true after the fixes, and still the ceiling: at seven bots the physics
tick peaks over 40 ms. Finding **A** below is what is left.



### Headless, on the Mac: what the harness already measures

`tools/harness/run_bot_match.gd` writes `tick_ms` into every result file, and
`RingNavigation.charge()` already attributes part of it. Ten matches, three
prisoners, before and after:

| | tick avg | tick max | ticks over 16 ms | nav `map_get_path` avg | cover search avg |
|---|---|---|---|---|---|
| before | 0.720 ms | 18.77 ms | 12 | 0.0022 ms | 0.0178 ms |
| after | 0.834 ms | 18.85 ms | 11 | 0.0023 ms | 0.0213 ms |

**The headless harness cannot see these fixes, and that is the point.** It runs
three prisoners on an Apple-silicon Mac where the allocator is cheap; the fixes
are allocation and node-lookup pressure that only bites on the older x86 CPU with
seven bots on it. Two consequences worth writing down:

1. The harness's `tick_ms` is a design instrument, not a performance one. It is
   right for "did this rule change make the round longer"; it is the wrong tool
   for "will this hold 60 fps on Ryan's PC". Use `tools/perf/profile_match.gd`
   on the PC for that.
2. The harness is **not run-to-run deterministic**: ten matches run twice with
   *identical* code produce identical tick counts in only 5 of 10. So a
   before/after diff of the result files cannot prove a behaviour change either
   way. What can: `bash tools/test.sh` → **388 tests, 386 passed, 0 failed,
   2 skipped, 3578 checks**, and ten bot matches → **CLEAN, 10 resolved,
   0 unresolved, 67.5 % hit rate**.

---

## 3. Code review

`file:line` is this branch after the fixes. Findings marked **fixed** are in the
commit; the rest are recommendations, because they would change how a bot plays
and the brief was to keep behaviour.

### Fixed

| # | where | what it cost | fix | saving |
|---|---|---|---|---|
| 1 | `scripts/bot/runner_perception.gd:480` `sight_hit` | Allocated a `PhysicsRayQueryParameters3D` **and** a fresh exclude `Array` on **every** raycast. A runner fires up to 25 rays a tick, so at seven bots that is ~10,500 query objects and ~10,500 arrays a second, all immediately garbage. Every cover probe, exposure sample and LOS test in the game goes through here. | One pooled query and one pooled exclude array per perception; the exclude is rebuilt only when the threat changes. | The single biggest allocation source in the game, removed. |
| 2 | `scripts/bot/tower_shooter.gd:388` `_visible_targets` | Three array allocations plus an `append_array` copy per tick; `_view_half_angles()` — a `deg_to_rad`, a `tan` and an `atan` — recomputed **per candidate** for an answer identical across the tick; a `get_node_or_null` per candidate through `RunnerPower.of`. | Reuse `_found`/`_pool` members, hoist the half-angles to once per tick. | 3 arrays + N transcendental triples + N node lookups per tick → 0 arrays, 1 triple. |
| 3 | `scripts/bot/tower_shooter.gd:486` `_has_line_of_sight` | Query object + exclude array per candidate per tick. | Pooled, as #1. | ~500 objects/s at seven runners. |
| 4 | `scripts/bot/runner_cover_finder.gd:495` `_floor_within_a_step` | A query object per walkability sample — the search is budgeted at 80 rays a frame, so up to 80 throwaway objects per frame. | One static pooled query. | ~4,800 objects/s. |
| 5 | `scripts/bot/runner_cover_finder.gd:579` `_radii` | Built a 9-element `PackedFloat32Array` by repeated `append` **once per angular step** — ~28 reallocating builds per full sweep, per runner. | A member buffer `resize`d once and written by index. | ~28 array builds per search → 0. |
| 6 | `scripts/bot/runner_cover_finder.gd:424` `HAZARD_GRID_CACHE` | The hazard-grid cache held **8** entries and every runner arms its own hazard array. At eight runners it evicted a grid that was still live and rebuilt it — nested `cx`/`cz` loops with a `PackedInt32Array` copy-back — inside the per-sample hot loop. | Ceiling raised to 24, above the player cap. | Removes a full grid rebuild per sample in the worst case. |
| 7 | `scripts/player/bot_intent_source.gd:89` `_look_for_a_shove` | `get_tree().get_nodes_in_group(RUNNER_GROUP)` — which allocates a fresh array — **per bot per tick**. The only true O(n²) group query in the per-tick path. | Fetched once per physics tick into a static cache keyed on `Engine.get_physics_frames()`. | N arrays/tick → 1. 420 arrays/s → 60 at seven bots. |
| 8 | `scripts/match/trap_volume.gd:132` `_process` | 22 `feet_only` volumes on the ring each called `Area3D.get_overlapping_bodies()` — one array allocation apiece — **every frame of every match**, and 99.9 % of those frames have nobody standing in any of them. | Driven off `body_entered`/`body_exited` into a small list; `set_process(false)` while it is empty. | 22 allocations + 22 `global_transform` reads per frame → 0 on almost every frame. At 900 fps that was ~19,800 arrays a second. |
| 9 | `scripts/match/match_hud.gd:457` `_write`, `:448` `_show`, `:290` `_write_pips`, `:438` `_hide_all` | `Label.text` and `Control.modulate` assigned **every frame** regardless of change — Godot re-shapes and re-lays-out the text on every assignment — across six labels; a 10-child `get_child` + `modulate` loop every frame with a `Color * Color` recomputed per pip; an 8-element `Array` literal allocated on every `_hide_all` (every frame of a respawn hold or a spectated match). | Dirty-check both setters, cache the panel list, early-out the pips when the lit count has not changed, hoist the dim colour. | ~6 text relayouts + ~14 property writes + 1 array per frame → only on the frames a value actually changes. Not visible in a bots-only profile; this is the player's frame. |
| 10 | `scripts/player/prisoner_avatar.gd:813` | `mesh.layers` written unconditionally every frame per avatar — a `RenderingServer` crossing for a value that never changes after `_ready`. | Guarded. | 1 server write per avatar per frame → 0. |
| 11 | `scripts/player/player_controller.gd:1068` `_settle_head` | A full `Basis.inverse()` per body per physics tick, to rotate a `view_offset` that is `Vector3.ZERO` for every body except a client-predicted one. | Early-out on a zero offset; `transposed()` when it is not, since the body only yaws and the basis is orthonormal. | One 3×3 inverse per body per tick → none in single-player, a transpose in netplay. |
| 12 | `scripts/optics/weapon_optic.gd:302` `_apply` | `camera.fov` written every frame even when unchanged; the existing `changed` flag gated only the signal, not the write. Each write dirties the camera and recomputes its projection. | Write moved inside the `changed` guard, read-back preserved. | 1 camera projection rebuild per frame → 0 while not zooming. |
| 13 | `scripts/audio/movement_audio_listener.gd:184` | An `Array[int]` allocated **every physics tick** to hold stale body ids, empty on virtually every tick. The one audio cost that scaled with bot count. | A member array that is `clear()`ed. | 60 arrays/s → 0. |
| 14 | `scripts/match/match_controller.gd:1088` `get_participants_ref()`, used from `scripts/harness/bot_match_telemetry.gd` | `get_participants()` returns `_participants.duplicate()`, and telemetry called it from up to nine places, several of them per physics tick. | A documented no-copy accessor for read-only tick-path callers; `get_participants()` is unchanged for everyone else. | Several array copies per tick → 0. Harness-only, but the harness is how every design decision in this repo is made. |
| 15 | `scripts/player/runner_ability.gd:55` `RunnerPower.of` | `get_node_or_null(^"Ability")` — a path resolution — per body, from the tower's target scan (per candidate per tick), the net link's presentation pass (per body per drawn frame) and the decoy driver (per link per tick). | Memoised by instance id, validated on read, cleared past 256 entries. | ~N×3 path resolutions per tick → one per body, once. |

### Not fixed — these change behaviour, and that is Ryan's call

| # | where | what it costs | the fix, and what it would change |
|---|---|---|---|
| A | `scripts/bot/ring_runner.gd:1561` `_plan_and_cross` | Called from `_tick_recover`, `_tick_hold` and `_tick_evaluate` on **every tick a runner is exposed**, with no throttle — while `_tick_evaluate`'s own search is gated behind a 0.35 s countdown (`EVALUATE_SEARCH_SECONDS`, line 1358). When the search finds no reachable target the runner stays in the same state and does the whole thing again next tick: a 27-probe cover sweep, up to three `NavigationServer3D.map_get_path` calls, and 24 raycasts. **This is the 40–53 ms tick at seven bots.** | Give `_plan_and_cross` the same countdown gate `_tick_evaluate` has, and cache `_target_path`/`_exposed_metres` between searches. Expected: the exposed-and-stuck case drops from every tick to every 0.35 s — roughly a 20× cut on the worst path, and the 170 ms stalls with it. It changes how fast a cornered bot reacts, which is a design decision, not a performance one. |
| B | `scripts/bot/ring_runner.gd:1635` `_measure_exposure` | 12 raycasts (`RunnerProfile.path_samples`) per call, and `_maybe_take_the_covered_way` (line 1619) calls it a second time — 24 rays per plan. **None of them are counted against `RunnerCoverFinder.RAYS_PER_FRAME = 80`**, so the one budget in the bot code is bypassed by the biggest consumer of rays. | Spend them through `RunnerCoverFinder._spend_ray()` / `_rays_left()` like the cover search does. It would make exposure measurement degrade under load instead of running flat out — correct, but it changes bot decisions. |
| C | `scripts/bot/runner_cover_finder.gd:388` `point_in_hazard` / `segment_crosses_hazard` | The hazard grid is looked up by a linear scan with two string-keyed dictionary reads per entry, **once per 0.5 m sample** — a 20 m crossing is 41 such lookups. The dictionaries themselves are string-keyed (`"centre"`, `"reach_squared"`, `"inverse"`, `"half"`). | Build the grid once in `RingRunner._arm()` and pass it in; replace the hazard dictionaries with a typed class. Pure win in principle, but it touches the geometry the bots navigate by and wants its own test pass. (The cache ceiling — which *was* evicting live grids at eight runners — is fixed, see below.) |
| D | `scripts/bot/tower_shooter.gd:362` | `shot_declined.emit(_confidence)` fires **every tick** the shooter holds fire. The class docs already acknowledge this. | Edge-trigger it, or replace it with a sampled counter. Anything listening changes shape. |
| E | `scripts/bot/ring_navigation.gd:130` `charge()` | Telemetry instrumentation — two `Time.get_ticks_usec()` calls and a **string-keyed** dictionary read-modify-write — sits inside `snap()` and `find_path()`, which run 2–4× per runner per tick. | `StringName` keys or an int enum, and compile it out of release builds. It is read by `bot_match_telemetry.gd`, so the harness's result schema is involved. Measured cost is ~5 µs/tick: real, but far below A and B. |
| F | `scripts/net/net_codec.gd:109` | A `StreamPeerBuffer` plus a `PackedByteArray` copy per packet; `pack_intent` runs every physics tick per client. | Reuse one buffer. Not measurable in a local bots-only match; matters when the net layer is live. |

### Also seen, and left alone deliberately

- `net_replicator.gd:407` does two linear `find_seat` scans per link per frame —
  O(n²), but n ≤ 8 and `world_snapshot.gd:77` already argues correctly that a
  dictionary would be slower at that size.
- `scripts/audio/audio_director.gd` is a proper fixed-size voice pool that
  switches its own `_process` off when nothing is sounding. No node is created
  per shot or per footstep. Leave it.
- `scripts/fx/*` all check for the headless display and disable themselves, and
  every effect is a closed-form function of elapsed time with a live-only
  `queue_redraw()`. There is not one `create_tween()` in the repo.
- `scripts/optics/scope_vignette.gd:213` already dirty-guards its shader
  parameter and hides the overlay when not aiming.
- `scripts/player/movement_readout.gd:99` writes four formatted labels per frame
  undirty-checked — but it only exists in `characters/player/movement_playground.tscn`
  and costs the shipping match nothing.

---

## 4. Render settings

`project.godot` is close to clean already. What is actually set:

| setting | value | verdict |
|---|---|---|
| `renderer/rendering_method` | `gl_compatibility` | fixed by the brief |
| `limits/opengl/max_lights_per_object` | **32** (engine default is 8) | the one expensive line in the file |
| `textures/vram_compression/import_etc2_astc` | true | fine |
| MSAA 2D/3D | not set → **off** | fine |
| glow / SSAO / SSIL / SDFGI / fog / volumetric fog | not set anywhere in the repo → **off** | nothing to cut; Compatibility supports none of them anyway |
| `display/window/size` | 1600×900, `canvas_items` stretch | fine |

`maps/bentham_ring/bentham_ring.tscn`, counting instanced subscenes:

| lights | count | shadows |
|---|---|---|
| `Ring/Torches/Torch_*` → `torch.tscn` `Flame` (omni, energy 4, range 14) | 12 | off (explicit) |
| `Ring/LavaGlow/*` (omni, energy 3, range 12) | 4 | off |
| `Tower/HellFlood` (omni, energy 3.4, **range 700**) | 1 | off |
| `Tower/TowerLight` (omni, range 25) | 1 | `.tscn` says **true**, `TowerLight._ready` overwrites it from `default_tower_light_profile.tres` → **false** |
| `StartEnd/Portal` → `portal.tscn` `Glow` | 1 | off |
| `Tower/KeyLight` (directional, **energy 0.0**) | 1 | off |
| **total dynamic lights** | **20** | **0 shadow casters at runtime** |

One `WorldEnvironment`: procedural sky at 1.4, ambient colour source,
Reinhardt tonemap, everything else default/off. Zero `GPUParticles3D` and zero
`CPUParticles3D` in the entire project. 36 `MeshInstance3D` in the ring, 35 of
them visible, ~95,960 visible triangles of which `map_base` is 92 %.

### Findings

1. **`Tower/HellFlood` has `omni_range = 700`.** That sphere encloses the whole
   map, so under Compatibility's per-object forward light list this one light
   lands on **every object in every draw call**. Combined with
   `max_lights_per_object = 32`, deck geometry near the torch ring carries
   HellFlood + TowerLight + several torches + a lava glow at once. Shrink it, or
   fold it into `ambient_light_energy`, which is what it actually is.
2. **`max_lights_per_object = 32` should be 8.** Nothing in the ring needs more
   than a handful of lights on one surface; the raised ceiling only lets the
   shader loop further.
3. **Dead settings, worth deleting so the next reader is not misled:**
   `Tower/KeyLight` has `light_energy = 0.0` — it contributes no light at all —
   yet carries `shadow_bias`, `directional_shadow_mode` and
   `directional_shadow_max_distance`, none of which do anything. And
   `bentham_ring.tscn:531` sets `shadow_enabled = true` on `TowerLight` while
   the profile silently turns it off at `_ready`; anyone reading the scene file
   concludes the opposite of the truth.

### The "potato" preset

Measured headroom on this box is 1.0 ms for the arena, so none of this buys
anything here — it is aimed at an iGPU, where fill rate and per-object light
count are the two things that bite. In `GameSettings` terms:

| control | potato | why |
|---|---|---|
| `render_scale` | 0.75 | the only lever that is linear in fill rate, and Compatibility's 3D scaling is nearly free |
| vsync | on | it is on by default and should stay on; a potato wants the frame pacing |
| fps cap | 60 | stops an idle menu heating the room |
| `max_lights_per_object` | 8 | project-level, see above |
| torch lights | halve to 6 (every 60° instead of every 30°) | 12 omnis at range 14 overlap heavily on a 52 m lane |
| `HellFlood` range | 60, or delete and raise ambient | stops one light from joining every object's light list |
| shadows | **needs a real toggle** | was "already none" and is no longer true: maps 2 and 3 each cast one realtime shadow over the whole arena. Measured on the PC (2026-09-16 section, finding 1): marble's costs **1.66 ms, 71 % of that map's whole frame**; forest's costs 0.11 ms. On marble this is the preset's biggest single lever by an order of magnitude. |
| MSAA | already off | nothing to do |

Alongside that, the arena split from §1 — which is the change that makes a weak
GPU stop paying for 88k triangles it cannot see.

---

# Three maps, one set of budgets — 2026-09-16

Everything above was measured when the game had one arena. It now has three, and
every budget in `tests/test_budgets.gd` was set on the first one. This section
asks the only question that matters about that: **does a map change what the
game costs?**

The short answer is that it changes nothing the budgets watch and one thing no
budget watched at all — and that the one thing is **not** the triangle count
everybody expected. Map 3 has 1.83x map 1's triangles and is the cheapest map in
the game. Map 2 has the fewest triangles and the fewest draw calls of the three
and costs three times either of the others, because of one shadowed light. See
§3.

## The table

Physics from `tools/perf/profile_physics.gd` (new this branch) — the world
`tests/test_budgets.gd` builds, seven prisoners and a guard, **eight seats**,
600 warmup ticks then a 1080-tick window, on the Mac, three runs per map.

Ranges are **four runs per map**: three round-robin batches plus one
confirming run taken later at a lower load. `objects/tick`, `phys_active`,
`phys_pairs` and `nodes` were bit-identical on every run of a given map.

**The Mac was not quiet** — other work was running on it throughout, at a load
average of 7-16. So the three maps were measured **round-robin** (map 1, map 2,
map 3, then repeat, three times) rather than three runs of one map and then
three of the next: interleaving shares whatever the machine was doing equally
across the three arms, which is what makes the comparison BETWEEN maps sound
even though the absolute milliseconds are not this machine's best. Read the
columns against each other, not against a number from a quiet box. Wire from
`tools/perf/profile_wire.gd` (new this branch) — the same eight-seat loopback
session B4/B5 are measured on, with the map's arena actually in the tree.
Draw counts from `tests/test_map_draw_budgets.gd` (new this branch), off the
live tree after `_ready`. Frame cost and draw calls from
`tools/perf/profile_match.gd --map=…` on the PC — see §3 for the method and the
shadow control that explains the ordering.

| | **1 bentham_ring** | **2 marble** | **3 forest** | budget |
|---|---|---|---|---|
| mean tick | **0.862–0.876 ms** | **0.863–0.865 ms** | **0.863–0.866 ms** | B1 1.45 |
| worst tick (2nd worst sample) | **5.31–6.76 ms** | **5.14–5.63 ms** | **5.30–5.52 ms** | B2 7.00 |
| objects kept / tick | 0.0028 | 0.0093 | 0.0074 | B3 0.05 |
| physics active bodies | 6.0 | 7.0 | 7.1 | — |
| broadphase pairs | 9.5 | 18.5 | 10.7 | — |
| host up | 448.8–449.8 B/tick | 432.1–432.6 B/tick | 440.6–440.8 B/tick | B4 535 |
| client down | 64.1–64.2 B/tick | 61.7–61.8 B/tick | 62.9–63.0 B/tick | B5 76.5 |
| visible triangles | 78,722 | 75,632 | **143,895** | — |
| surfaces / materials | 37 / 15 | 4 / 4 | 9 / 9 | — |
| transparent triangles | 0 | 0 | **2,196** | — |
| lights | 20 | 2 | 2 | — |
| **runtime shadow casters** | **0** | **1** | **1** | — |
| frame, runner's eye (PC) | 0.945 ms | **2.592 ms** | 0.765 ms | — |
| frame, guard's eye (PC) | 0.849 ms | **2.349 ms** | 0.793 ms | — |
| draw calls, runner / guard (PC) | 17.7 / 16.0 | 12.9 / 6.2 | 28.2 / 15.6 | — |
| primitives drawn, guard (PC) | 76,707 | 75,687 | **276,757** | — |
| collision triangles | 17,196 | 5,180 | 5,286 | — |
| `Area3D`s in the map | 32 | 3 | 2 | — |
| nav polygons (runtime bake) | 509 | 279 | 311 | — |
| nav bake | 259–381 ms | 156–176 ms | 79–94 ms | — |
| cover points found (at measurement → after `78d89bb`) | 196 → 192 | **1,837 → 164** | **1 → 1** | — |

Bot harness, `--matches=5` on each map, run twice: **CLEAN, 0 unresolved** every
time. `bash tools/test.sh`: **458 tests, 458 passed, 0 failed, 4933 checks**,
hot paths CLEAN, i18n CLEAN — with map 1's own budget line reading avg
**1.279 ms** against B1 1.45 and worst **5.59 ms** against B2 7.00, which is
where it read before this branch (1.270 / 5.42). **Map 1's gate did not move.**

## 1. Physics and CPU: nothing to fix, and the reason is worth keeping

All three maps measure the same mean tick to within 1 %, and every one of
B1, B2 and B3 passes on every map with the same margin it had before. The two
new maps are in fact **cheaper**: a third of map 1's collision triangles, a
tenth to a sixteenth of its `Area3D` count, and a nav bake two to four times
faster.

That is not luck; it is three facts worth writing down, because each is the
thing that would have made it expensive:

1. **The brambles are not colliders.** `maps/forest/models/forest.glb` ships five
   nodes and only `ForestCollision-colonly` — **1,830 triangles** — carries
   collision. The thicket at the pit bottom (`PLANTS = 1150` in
   `tools/modelling/maps/forest/forest_pit_build.py`, **30,985 triangles**) lives inside
   `ForestGround`, which is art. The kill
   volume over the ravine is what makes the thicket lethal, so the physics
   engine never has to know a bramble exists. The fog discs and the ray vanes
   are art too.
2. **Maps 2 and 3 have no trap volumes.** Map 1's 32 `Area3D`s are 22
   `TrapVolume`s, seven `BoostPad`s, a powerup, a kill volume and the finish
   gate; maps 2 and 3 have a kill volume or two and the gate. The per-frame
   `get_overlapping_bodies()` sweep that §3 finding 8 removed was map 1's cost
   and the new maps never had it.
3. **The cover finder's ray budget holds under a map that offers nine times the
   cover.** When the physics above was measured, marble's runtime bake yielded
   **1,837 cover points** against map 1's 196 — nine times the search space for
   the single most expensive thing in the bot tick (§2, "where the cost is",
   item 1) — and the mean tick did not move, because
   `RunnerCoverFinder.RAYS_PER_FRAME = 80` is a real ceiling and not a hope.
   This is the first evidence the project has that the ray budget is doing its
   job rather than merely existing.

   **That 1,837 was itself a bug, and it is fixed** — by `78d89bb` ("stop
   counting unreachable floors as cover"), from another lane, merged into this
   branch after the measurement. Marble now bakes **164** cover points and map 1
   **192**. Two things follow. The evidence above still stands, because it is a
   fact about a load the budget actually survived, and a stress test does not
   stop counting when the stress is removed. And the physics table's mean tick
   is if anything now conservative for marble: the load it was measured under no
   longer exists. Nothing was re-measured for this, because a lower load cannot
   turn a pass into a failure.

**Two things seen and deliberately not fixed:**

- `objects/tick` rose from 0.0028 on map 1 to 0.0093 on marble and 0.0074 on
  forest. Still five times inside B3 and still one to ten kept objects across a
  1080-tick window, which is respawn cadence and not a leak — maps without traps
  kill differently, so the deaths fall in different places in the window.
  Recorded because B3's job is to notice a shape, and if this keeps climbing on
  map 4 it is the number that will say so first.
- **Forest's bake finds exactly one cover point.** Not a performance problem
  today — one point is a cheap sweep — but it is the input to §3 finding **A**,
  the un-throttled `_plan_and_cross` that re-runs a full search on every tick a
  runner is exposed and finds nothing. On a map where cover does not exist, that
  path is permanently in its worst case. It does not bite at eight seats on the
  Mac; it is the first thing to look at if forest ever tails out on the PC.
  Note what the fix is and is not: the throttle finding **A** describes is
  map-agnostic and belongs in `scripts/bot` like the rest of the bot. Knowing
  that *forest* is the map without cover does not, and must never get there.

**Nothing was changed to make any of this pass.** No collider was simplified, no
volume removed, no map re-exported.

### One thing the warmup exposed, and B1 should be read knowing it

The table above warms up for **600** ticks. `tests/test_budgets.gd` warms up for
**120**, and at 120 the same three maps do not agree:

| warmup | bentham_ring | marble | forest |
|---|---|---|---|
| 120 ticks (what B1/B2 use) | **1.311 / 1.389 ms** | 0.863 / 0.863 ms | 0.890 / 0.950 ms |
| 600 ticks | 0.862–0.871 ms | 0.863–0.864 ms | 0.863–0.864 ms |

Map 1 is the only one that moves, and it moves by 50 %. What is inside its first
120 ticks and not inside the others' is the opening race over seven traps and a
**262–381 ms nav bake** against marble's 156–176 and forest's 80–94. At 60 Hz a
300 ms bake is eighteen ticks of the warmup window spent in one call, and the
tail of it lands in the measurement.

So **B1's 1.45 ms ceiling is partly a setup allowance**, not purely steady-state
play, and it is an allowance only map 1 draws on.

**And a warning about B2 on a shared machine.** B2's ceiling is 7.00 ms on a
measured 5.41-5.85, so about 20 % of headroom on the noisiest number the suite
takes. That is enough on an idle Mac and not enough on a busy one: with other
agents running bot sweeps on this box at a load average around 6, the same
worst-tick reads **6.42-7.47 ms** and trips the gate on roughly half of runs.
Measured interleaved across four runs each of this branch and its parent, the
two are indistinguishable (pre 6.42-6.96, post 6.50-7.47), so this is the
machine and not a regression on either side. **B2 was not raised**: a gate that
is widened every time it is inconvenient stops being a gate. The right response
to a red B2 is to look at the load average first, re-run, and use
`PANOPTICON_SKIP_BUDGETS=1` only on a machine that genuinely cannot measure. That is not a bug and it is
not worth changing — B1's job is to catch a change of order and a longer warmup
would only make it slower to run — but anyone reading 1.27 ms off a BUDGET line
and 0.86 ms off a PHYS line should know the two windows are not the same window,
and that the gap between them is map 1's own bake.

## 2. Bandwidth: unchanged, measured, and unchangeable by a map

| map in the tree | host up | client down |
|---|---|---|
| none (the budget fixture as shipped) | 449.9 / 450.1 B/tick | 64.3 B/tick |
| bentham_ring | 448.8 / 449.8 B/tick | 64.1 / 64.2 B/tick |
| marble | 432.1 / 432.6 B/tick | 61.7 / 61.8 B/tick |
| forest | 440.8 / 440.6 B/tick | 63.0 / 62.9 B/tick |
| **B4 / B5** | **535** | **76.5** |

Eight seats, 180 ticks, **90 snapshots and 100-102 packets on every one of the
four arms**. B4 and B5 are unchanged, and the suite's own B4 line the same day
reads 445.3 B/tick, in the middle of them.

The **4 % spread is the range coder, not the map.** `NetSettings.compress_traffic`
is on in the settings this measures, so what a packet costs depends on the
VALUES in it, and a map with collision under the bodies leaves them at different
positions than a flat test floor does. The map changes where the players are; it
does not change what a player costs. Note also that `profile_wire.gd` runs at
**1x real time** and not the suite's 50x: under compression the main loop retires
many physics steps per idle frame while the socket is polled once per frame, so
several ticks' traffic flushes as one batch and the per-tick rate becomes a
function of how fast the frame ran — which on the first attempt moved the answer
435-471 B/tick and pointed the wrong way, the no-arena arm reading highest. A
wire instrument whose answer depends on frame cost cannot answer a question
about the wire. At 1x every arm reproduces to 0.1 B/tick.

They were never going to change, and the codec says why: `WorldSnapshot` holds
its eight `PlayerState` for life at `SNAPSHOT_BODY_SIZE = 26` bytes each, and
there is no map, arena, geometry or scene-path field anywhere in
`scripts/net/`. The map does cross the wire exactly once — `map_id` is a
`StringName` export, so `NetCodec.pack_rules` picks it up with the rest of the
rules and sends it on the reliable channel at lobby time. A short string, once,
off the per-tick path. That is the whole of geometry's presence in the protocol
and it is the right amount.

## 3. Draw: measured on the PC, and it is not what the triangles said

Captured on Ryan's box (i7-6700, RX 6600 XT, GL Compatibility, 1920x1080,
vsync off) by `tools/perf/profile_match.gd --map=<id> --view=runner|tower`,
seven bots, 20 s per arm, from the branch at `4895fb2` in a scratch worktree at
`C:\dev\perf-newmapperf`. `C:\dev\panopticon` stayed on `main` and was not
touched. Numbers are the mean of the per-second samples.

| | **1 bentham_ring** | **2 marble** | **3 forest** |
|---|---|---|---|
| frame, runner's eye | 0.945 ms (1058 fps) | **2.592 ms (386 fps)** | 0.765 ms (1307 fps) |
| frame, guard's eye | 0.849 ms (1178 fps) | **2.349 ms (426 fps)** | 0.793 ms (1261 fps) |
| draw calls, runner / guard | 17.7 / 16.0 | 12.9 / 6.2 | 28.2 / 15.6 |
| primitives drawn, runner / guard | 73,221 / 76,707 | 73,601 / 75,687 | **269,250 / 276,757** |
| objects drawn, runner / guard | 17.7 / 16.0 | 12.9 / 6.2 | 28.2 / 15.6 |
| VRAM | 35.8 MB | 22.1 MB | 32.1 MB |
| static triangles (§the table) | 78,722 | 75,632 | 143,895 |

**Marble — the map with the FEWEST triangles and the FEWEST draw calls in the
game — is three times the cost of either of the others.** Forest, at 1.83x map
1's triangles and 3.6x its primitives per frame, is the cheapest. Every
prediction made from geometry in the first draft of this section was wrong in
its ordering, and the reason is a single line in one `.tres`.

### Finding 1 — one shadowed omni is 71 % of marble's frame. Proven, not inferred.

The same six arms re-run with `--after=noshadow`, which switches
`shadow_enabled` off on every `Light3D` and changes nothing else:

| guard's eye | shadows as shipped | shadows off | delta | primitives on → off |
|---|---|---|---|---|
| bentham_ring (**0** casters) | 0.849 ms | 0.877 ms | **+0.03 ms — none** | 76,707 → 76,713 |
| marble (1 caster) | 2.349 ms | **0.686 ms** | **−1.66 ms, 3.4x** | 75,687 → 75,689 |
| forest (1 caster) | 0.793 ms | **0.686 ms** | −0.11 ms, 1.16x | 276,757 → **137,869** |

Read the three rows together, because each one does a different job:

- **bentham_ring is the negative control and it passes.** It has no runtime
  shadow caster, and switching shadows off moves it by less than the run-to-run
  noise. The method is sound.
- **Forest's directional shadow is visible in the primitive counter and nearly
  free.** Primitives *halve* when it is off — 276,757 → 137,869 — which is the
  shadow pass re-submitting the entire map, exactly once. It costs **0.11 ms**.
  So forest's 143,895 triangles are drawn *twice* every frame on this GPU and
  the whole of it still runs at 1,260 fps. **Triangle count is not this
  project's problem and this is the number that says so.**
- **Marble's omni shadow submits no extra geometry at all** — its primitive
  count does not move — **and costs 1.66 ms, 71 % of the map's entire frame.**
  That is not vertex work; it is the dual-paraboloid shadow map itself plus
  `shadow_blur = 3.0` filtering over an `omni_range` of **140 m**, which
  encloses the whole arena. Pure fill, on the one axis a weak GPU has least of.

On an RX 6600 XT marble still runs at 426 fps and nobody will notice. The
"potato" bar is an iGPU with a fraction of this card's fill rate, where a
1.66 ms full-screen-ish filtered shadow pass is the difference between holding
60 fps and not. **This is the single most expensive thing either new map added,
it arrived twice without a word, and it is now the first line of the potato
preset's work.**

**Still not fixed, and still deliberately.** Marble's lamp is a shadow caster on
purpose — "one warm gold lamp under the arcade, shadowed, so the arches throw
their beams out across the ring as the drawing has them", retuned by Ryan on
2026-09-16 — and forest's `Sun` is what its rays are lit by. Switching either
off is an art decision. What the measurement changes is the *price tag*: the
conversation is now "1.66 ms and 71 % of the frame for the arches' beams", not
"a shadow light, probably fine". Three cheaper things to try before losing the
look, in order: drop `shadow_blur` from 3.0, cut `omni_range` from 140 m to
something that stops at the walkway, and gate shadows behind the potato preset.
None was attempted here; all three are art-visible and Ryan's call.

### Finding 2 — culling reclaims almost nothing, as predicted, and it does not matter

Forest draws **137,869 primitives with shadows off against 143,895 static
triangles: culling rejects 4 %.** Map 1 draws 76,707 of 78,722 — **3 %**. Marble
75,687 of 75,632 — **none at all** (slightly over, because the bodies are in
that count too).

That is the one-contiguous-mesh consequence stated in §1, now measured on three
maps: a 120 m ring in a single `MeshInstance3D` is submitted whole from every
camera angle, frustum culling can reject none of it, `visibility_range_*` can
apply to none of it, and an `OccluderInstance3D` cannot hide part of it. Mesh
LOD is generated (`meshes/generate_lods=true` on every import) and is plainly
not selecting anything either, or forest's pit would not be in the count from
the guard's seat.

**And none of it costs anything.** Forest submits its whole 143,895 triangles
twice a frame and runs at 1,260 fps. §1's recommendation 1 — split the arena
per section — remains in direct conflict with `docs/ENGINEERING.md`'s "one
contiguous mesh per map", and this measurement says **do not spend the conflict
on performance**, because there is no performance here to win. If the split is
ever made, make it for a reason that is not this.

### Finding 3 — the fog and the rays cost nothing measurable

Forest carries the only transparent geometry in the game — `ForestFog` (2,016
triangles, alpha-blended, seven stacked full-width discs over the pit) and
`ForestRaysSoft` (180, additive), both with culling disabled so both faces
draw. It was the prime suspect for overdraw and it is not one: forest is the
cheapest map at both eyes, at 0.765 and 0.793 ms.

Its 28.2 draw calls at the runner's eye are the most in the game and still
nothing. `ForestRaysSolid` is `visible = false` and costs nothing at all.

### Does anything need occlusion or culling work? No.

That was the question this section was asked. The answer is no, on this GPU and
by a wide margin: the most expensive map in the game spends 71 % of its frame on
one light's shadow filter and **0 %** on anything an occluder, a visibility
range or a mesh split could reach. Occlusion work would be effort spent on the
one part of the frame that is already free.

## 4. Do the budgets need per-map values? No — they need a sixth budget

**B1, B2, B3, B4 and B5 do not need per-map values.** The evidence is the table:
three maps measure the same mean tick to within 1 %, the same worst tick inside
the same 1.6 ms spread, and the same bytes inside 4 %. Three copies of one
number is not a budget, it is a maintenance cost, and splitting B1 per map would
also make map 1's gate easier to satisfy by giving a regression somewhere to
hide. Map 1's gate is untouched by this branch.

What the maps *do* differ on is the draw side, and nothing gated it at all. So
the proposal is a sixth budget of a different kind, and it is **implemented**:

**`tests/test_map_draw_budgets.gd`** walks **every** map in `MapCatalog` after
`_ready` — which matters, because `TowerLight._apply_profile` overwrites the
`.tscn`'s `shadow_enabled` and reading the scene file would measure the wrong
number — and gates six counts per map: triangles, surfaces, materials,
transparent triangles, lights, and lights that cast. It prints a
`BUDGET draw map=…` line for every map on every run, as B1–B5 do.

```
BUDGET draw map=bentham_ring tris=78722 surfaces=37 materials=15 transparent_tris=0 lights=20 shadow_casters=0
BUDGET draw map=marble       tris=75632 surfaces=4  materials=4  transparent_tris=0    lights=2  shadow_casters=1
BUDGET draw map=forest       tris=143895 surfaces=9 materials=9  transparent_tris=2196 lights=2  shadow_casters=1
```

Three things about its shape are deliberate:

- **`shadow_casters` gets an exact ceiling, not 20 % headroom.** Zero means
  zero. A percentage on a count of 0 or 1 is meaningless, and this is the number
  the whole file exists for.
- **A map in the catalog with no row FAILS**, and the failure prints the row to
  paste in. A map cannot arrive un-measured; that is exactly how these two did.
- **It is scene data, not wall clock**, so it is identical on every machine, it
  never skips, and it costs the suite 0.5 s. It does not weaken map 1's gate
  because it does not touch it — it adds a gate map 1 passes at zero.

## What is missing, and why

**An iGPU.** Every number above is an RX 6600 XT, where the slowest map runs at
386 fps. Ryan's bar is a potato, and the one finding that matters — marble's
1.66 ms shadow — is a *fill-rate* cost, which is precisely the axis that does
not scale down gracefully from this card to integrated graphics. The ratio, not
the millisecond, is the thing to carry across: **71 % of one map's frame, on a
map that is otherwise the cheapest in the game.** Nothing in this repo can
measure the machine that matters, and the honest next step is to run
`tools/perf/profile_match.gd --map=marble --view=tower` once on a laptop.

Also not done, deliberately: nothing was changed to make marble faster. The
three levers in finding 1 are all visible in the art, and the brief for this
pass was to fix what is slow without changing how a map looks.

**The standing conclusion.** Nothing in the physics tick or on the wire needs
work on any of the three maps. On the draw side, triangles turned out not to be
the story on any of them, and one light on map 2 is.
