**1. (Severity 1) t0 does not match the logs' t**
- **file:line:** `tools/content/sv3/pill.py:151`
- **what goes wrong:** The pipeline reads the white-frame `sync` timestamp from the video but fails to update `t["t0"]` in `take.json` (leaving it as `0.0`), permanently misaligning all event log timestamps during search and assembly.
- **one-line fix:** Add `t["t0"] = float(sync)` before saving `t` back to `take.json`.

**2. (Severity 2) Missing/duplicated/mis-timed events**
- **file:line:** `tools/capture/pill_match.gd:167`, `184`, and `199`
- **what goes wrong:** 
  1. `shot` and `shot_result` wrongly attribute the action to `_seat_participant()`, meaning the logs claim the filmed runner fired the rifle instead of the guard. 
  2. `ghost_caught` sets `_was_running` to false but leaves `_was_visible` true, guaranteeing a duplicate `ragdoll` event when the caught runner despawns.
  3. `KILL_AFTER_HIT_S` is checked using `_elapsed` (updated by variable frame rate `_process`) inside a fixed `_physics_tick`, allowing slight drift to misclassify a valid `shot` kill as a `pit` kill.
- **one-line fix:** Hardcode the shooter ID to the guard, add `_was_visible[caught.index] = false` to the ghost lambda, and compare hit deltas using a physics-based clock or wider tolerance.

**3. (Severity 3) Seats diverge and check misses it**
- **file:line:** `tools/capture/pill_match.gd:91` and `tools/content/sv3/pill.py:164`
- **what goes wrong:** `_sync_frames` is decremented in `_process`, meaning `_build()` runs at a random real-time offset, causing physics ticks and bot RNG to misalign and diverge between runs; additionally, `--check` hardcodes `logs[names[0]], logs[names[1]]`, entirely ignoring any divergence if a match has 3 or more recorded seats.
- **one-line fix:** Decrement `_sync_frames` inside `_physics_tick()`, and change `--check` to iterate and compare all pairs in `logs`.

**4. (Severity 4) Seat camera can be anything but the player's eyes**
- **file:line:** `tools/capture/pill_match.gd:144`
- **what goes wrong:** `_hold_the_seat` simply returns if `eye == null` (which happens before spawn, when parked, or during ragdoll/despawn), abandoning the seat lock and leaving the video recording the `BotMatchWorld` default harness camera or a frozen perspective.
- **one-line fix:** Remove the early return and explicitly assign `eye` to a valid fallback (like the death cam or `_world` freecam) if the body lacks a camera.

**5. (Severity 5) Scrub leaves banned files and OS window shows**
- **file:line:** `tools/content/sv3/pill.py:44` and `tools/capture/pill_match.gd:76`
- **what goes wrong:** `Get-ChildItem -Filter '*.md'` lacks `-Recurse`, leaving banned markdown files in subdirectories to appear in Godot's FileSystem dock; meanwhile, `_hold_window()` resizes the window but leaves its OS titlebar and borders visible to the real-time screen recorder.
- **one-line fix:** Add `-Recurse` to the PowerShell markdown deletion command, and call `DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)` when holding the window.

**6. (Severity 6) vis.jsonl rows wrong for hidden/seat bodies**
- **file:line:** `tools/capture/pill_match.gd:243`
- **what goes wrong:** `cam.unproject_position()` is executed unconditionally for every body (including the hidden seat body and parked bodies sitting behind the camera), writing fatal garbage coordinates into the `x`, `y`, and `h` fields of the JSON row.
- **one-line fix:** Only call `unproject_position()` and calculate screen-space values if `in_frustum` is true, otherwise default them to `0.0`.
## Head's ruling (2026-10-17)
Fixed: 2.2 (`_was_visible` cleared on a ghost catch), 3b (`--check` compares every seat against the first), 5a (markdown scrub recurses, .git excluded), 6 (x/y/h written only for a body in the frustum).
Not real: 1 (t0 lives in `<seat>.pc.json`/`.mkv.sync`, as for run_clip; take.json t0 stays 0.0 by design §1); 2.1 (`shot`/`shot_result` use `get_seat_participant()`, the rifle's holder, not the filmed seat); 2.3 and 3a (pc_rough runs `--fixed-fps 60`, process and physics advance together, as run_clip's sync does); 4 (a parked body keeps its Head/Camera; `eye == null` only without a body); 5b (pc_rough's override.cfg already sets borderless + always_on_top).
