# Performance review — PANOPTICON

Measured on the PC (Ryan's box: i7-6700, AMD Radeon RX 6600 XT, Godot 4.7.2,
GL Compatibility) at 1920×1080 windowed, vsync off, from a bots-only match built
by `tools/perf/profile_match.gd`. Model figures are parsed straight out of the
`.glb` files. Nothing here is estimated unless it says so.

**The headline.** The renderer is not the problem and never was: the whole arena
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
| 6 | `eye.glb` | 1,078 | 3 | 3 | none | none | 30 KB |
| 7 | `rock_bars.glb` | 1,048 | 1 | 1 | yes — 240 | 2×128² (14 KB) | 133 KB |
| 8 | `tower2.glb` | 858 | 1 | 1 | yes — 70 | 2×128² (14 KB) | 105 KB |
| 9 | `husk_a/b/c.glb` | 702 / 698 / 604 | 1 | 1 | none | 1×32–128² | 83–110 KB |
| 10 | `creature1–4.glb` | 636–680 | 1 | 1 | none | 1×128² | 87–93 KB |
| — | `prisoner2.glb` (the player) | 620 | 1 | 2 | none | 1×32² | 136 KB |
| — | `rifle.glb` | 372 | 1 | 1 | none | 2×128² (21 KB) | 47 KB |
| — | every ring prop (`spire`, `slab`, `rock_wall`, `boulder`, `demon_pad`, `lava_tile`, `block`, `torch`, `speed_orb`) | 20–118 | 1–2 | 1 | yes, 4–40 | 2×128² | 12–38 KB |

Textures are already tiny — 128² for everything except the lava pair at 512².
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
  undirty-checked — but it only exists in `scenes/dev/movement_playground.tscn`
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

`scenes/ring/bentham_ring.tscn`, counting instanced subscenes:

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
| shadows | already none | nothing to do |
| MSAA | already off | nothing to do |

Alongside that, the arena split from §1 — which is the change that makes a weak
GPU stop paying for 88k triangles it cannot see.
