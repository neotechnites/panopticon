Here is the audit of the recorder diff against the design and rules.

1. `run_clip.gd:_name_the_bodies`: `_ids` maps the original body's instance ID instead of the participant index, so when a seat respawns as a ghost, it loses its mapping and logs events with its raw node name (e.g., `"Ghost_1"`) instead of its actor ID. **Fix:** map `participant.index` to the string ID instead of `body.get_instance_id()`. (REAL)
2. `run_clip.gd:_hold_the_seat`: `_seat_body` is never updated when the participant gets a new body (like a ghost), causing `_eye_of` to fail on a freed instance and the camera to fall back to a banned static tripod in gameplay. **Fix:** add `_seat_body = _seat_participant.body` at the start of the function if valid. (REAL)
3. `spectator_view.gd:tick`: The game's `SpectatorView` automatically cycles to spectate other living runners when the watched player is dead, violating the "never another runner" seat lock. **Fix:** force the spectator view to only watch the seat's own body/ghost, or disable its ability to switch targets entirely. (REAL)
4. `run_clip.gd:_tick_match`: The `--kill` flag executes again during `--tape` replay, killing the player a second time and breaking deterministic seat replay. **Fix:** skip the kill flag logic if `_options.get("tape")` is not empty. (REAL)
5. `run_clip.gd:_build_match`: `--seat-intent` installs and overrides the body's `BotIntentSource` even during `--tape` replay, conflicting with the tape's playback commands and breaking replay. **Fix:** do not install `seat_intent` if replaying a tape. (REAL)
6. `run_clip.gd:_hook_match_events`: `_kill_by_flag` logs a `kill` with cause `"shot"` but fails to emit the required preceding `shot_result` hit event. **Fix:** emit a `shot_result` hit event immediately before calling `convert_participant` when applying the kill flag. (REAL)
7. `run_clip.gd:_cause_of`: Returns `"lava"` for `MatchParticipant.DeathCause.TRAP`, meaning trap deaths are logged ambiguously instead of the schema's `"trap"`. **Fix:** add a match case for `DeathCause.TRAP` to return `"trap"`. (REAL)
8. `run_clip.gd:_hook_match_events`: In `MatchController.Phase.BRAWL`, `participant_converted` logs `kill` with cause `"pit"` or `"lava"` instead of the schema's `"brawl"`. **Fix:** if the phase is `BRAWL`, set the cause to `"brawl"`. (REAL)
9. `run_clip.gd:_hook_match_events`: `kill_beat_started` logs `kill` with cause `"finale"`, which is an ambiguous name not in the schema. **Fix:** change the finale kill cause to `"shove_pit"` or `"pit"`. (REAL)
10. `run_clip.gd:_hook_match_events`: `kill_beat_started` logs a `kill` for the guard, but `participant_converted` will also fire when the guard officially dies, logging `kill` twice for the same body. **Fix:** skip logging `kill` in `participant_converted` if `victim == "guard"` and `_finale_on` is true, or remove the `kill` from `kill_beat_started`. (REAL)
11. `run_clip.gd:_sample_vis`: `in_frustum` is forced to `false` when `body == _seat_body`, meaning the seat body falsely claims `on: false` even when visibly on screen during finale or spectator views. **Fix:** only force false if `cam == _eye_of(_seat_body)`. (REAL)
12. `run_clip.gd:_sample_vis`: The occlusion raycast blindly excludes `_seat_body.get_rid()`, meaning the seat body magically cannot occlude others when the camera is the finale or spectator view. **Fix:** exclude the RID of the body the current camera physically belongs to instead. (REAL)
13. `run_clip.gd:_sample_vis`: `scoped` logs `true` if `_seat_body` has its optic requested, even when the current camera is the finale or spectator view which have no scope overlays. **Fix:** only evaluate scoped as true if `cam == _eye_of(_seat_body)`. (REAL)
14. `run_clip.gd:_sample_vis`: Misses the `landmarks: {tower:{...}, portal:{...}}` field entirely, failing the schema requirement and lying by omission. **Fix:** add the `landmarks` dictionary with tower/portal visibility data to the `row`. (REAL)
15. `run_clip.gd:_sample_vis`: Height `h` calculates `absf(head.y - feet.y)` even if the feet are behind the camera, causing `unproject_position` to return wild off-screen coordinates and log a massive lie. **Fix:** check `cam.is_position_behind(feet)` before calculating `h`. (REAL)
16. `run_clip.gd:_state_of`: Checks `is_shooter` first, causing a dead or ragdolled guard to falsely log `"guard"` (an invalid schema state) instead of `"dead"` or `"ragdoll"`. **Fix:** remove the `is_shooter` check and use the standard `run|dead|ragdoll` states. (REAL)
17. `run_clip.gd:_state_of`: The `brawl` phase check returns `"brawl"` for all participants, masking `"dead"` or `"ragdoll"` for those who are already out. **Fix:** move the brawl check after the dead/ragdoll checks. (REAL)
18. `run_clip.gd:_place_free_camera`: If `_seat_body` becomes invalid during a gameplay match, it permanently places a static free camera, producing a banned non-player camera. **Fix:** only allow `_place_free_camera` if `_seat_spec == "free"`. (REAL)
19. `run_clip.gd:_sample_vis`: If the `_camera` (free camera) is active but `_seat_spec != "free"`, `label` evaluates to `_seat_spec` (e.g., `runner:1`), falsely attributing the static tripod's view to the runner. **Fix:** if `cam == _camera` and `_seat_spec != "free"`, label it `"tripod"` or `"free"`. (REAL)
20. `run_clip.gd:_make_it_bots_only`: `rules.prisoner_count = clampi(bots - 1, 1, 3)` ensures there is always at least 1 prisoner and 1 guard (2 total), breaking the `--bots=1` grey studio shot (which expects exactly one body). **Fix:** change the lower clamp bound from 1 to 0. (REAL)
## Head's ruling on the findings (WP1, 2026-10-17)
Fixed: 5 (no seat-intent while a tape plays), 6 (a --kill logs by/cause `kill_flag`, no fake shot_result), 9 (finale kill cause `shove_pit`), 11/12/13 (seat body, exclusion and `scoped` only through the seat's own eye), 16 (a guard with health 0 is `dead`).
Not real: 1/2 (a ghost keeps the same body; ids are per body), 3 (the spectator view IS the game's dead-player view; the seat body never changes), 4 (the tape holds inputs only, so a replay needs the same --kill), 7 (no TRAP death cause exists; a trap reads as lava), 8/17 (nobody is converted in the brawl; brawler_out is its event), 10 (the finale guard is never converted), 18/19 (the tripod exists only for --seat=free), 20 (the rules cannot field fewer than two participants; grey runs guard + one runner).

## Audit 2: --intent for any body (Gemini, same prompt family)
1. **run_clip.gd:_install_intents**: `--seat-intent` containing `;` (supported in older scripts, e.g., `run;wait`) is appended to `spec` and split by `;`, causing steps to be evaluated as body entries and failing the `=` check (grammar breakage). Fix: `var seat_steps = String(_options.get("seat-intent", "")).replace(";", ",")` before appending.
2. **run_clip.gd:_build_match**: Renaming `_intent` to `_intents: Array[Node]` breaks any existing references in `run_clip.gd` (e.g., `_intent.is_done()`), causing a compile error that completely breaks the tape/replay path. Fix: Update existing references in `run_clip.gd` to iterate over `_intents`.
3. **seat_intent.gd:_tick_runner**: The `brawl` step calls `_release()`, which permanently hands the scripted body back to its shipped brain and aborts all subsequent steps (e.g., `idle`), instead of waiting for the match's brawl to end. Fix: Wait for the participant's brawl state to end, or use `_pause_brains(false)` temporarily without calling `_release()`.
4. **seat_intent.gd:_parse**: The `cover` step parses `cover:tower` by attempting to cast `parts[1]` ("tower") to a float, resulting in 0.0 seconds and causing the step to end instantly. Fix: Change `cover` parsing to `_number(parts, 2, 2.0)` to correctly extract the duration in `cover:at:s` syntax.
5. **seat_intent.gd:_tick_guard**: The `hit` and `miss` steps call `optic.set_zoomed(true)` and can `try_fire()` on the exact same frame, firing with hipfire spread before the ADS transition (aim) is actually fully on. Fix: Add `and shooter.optic.is_fully_zoomed()` to the fire condition.
6. **seat_intent.gd:_tick_guard**: The `scope` step directly calls `shooter.optic.set_zoomed(true)` on non-seat bodies, which directly tweens the active camera FOV and zooms the player's view even when seated on another body. Fix: Use `shooter.input.zoom = true` instead of forcing the optic.
7. **seat_intent.gd:_aim_guard**: Passes 3 arguments (including `delta`) to `shooter.input.aim()`, but `BotIntentSource.aim` only accepts 2 arguments (yaw, pitch) as seen in `_turn_towards`, causing a GDScript crash. Fix: Remove `delta` from the `aim()` call parameters.
Ruling: fixed 1 (--seat-intent ';' read as ','), 5 (a scripted guard fires only once the scope has settled). Not real: 2 (compiles and ran), 4 (the grammar is cover:at:s, parsed at index 2), 6 (an optic zooms only its own body's camera, as the shipped brain does), 7 (BotIntentSource.aim takes delta). 3 is by design: brawl hands the body to the match's own fight and the entry ends there.

## Audit 3: cam_pos, body pos, landmarks
1. **Unproject behind camera lies**: `cam.unproject_position()` returns mirrored coordinates for points behind the camera that can falsely fall into the 0..1 screen space, tricking the searcher into evaluating `looking_at` as true.
*Fix*: `var seen: Vector2 = cam.unproject_position(point) if not cam.is_position_behind(point) else Vector2(-1, -1)`

2. **Landmark point ambiguity ("which point")**: A single base+2m point cannot spatially represent a massive tower; if the player looks at the top of the tower, this specific point will be off-screen (`on: false`), causing `looking_at(tower)` to falsely fail.
*Fix*: Export a screen-space bounding box (AABB) or multiple reference points (e.g., base, center, top) for large landmarks.

3. **Ragdoll state position lies**: For `dead` or `ragdoll` states, the kinematic `body.global_position` freezes at the death location while the visual skeleton flies, causing `moving(victim)` to falsely evaluate to 0 m/s.
*Fix*: Export the active skeleton's center of mass or main bone position when the participant state is `ragdoll` or `dead`.

4. **Head bob falsifies `moving(seat)` (Units/Velocity)**: `cam_pos` tracks the seat's camera/head, which bobs rapidly during idle/run animations, registering as high momentary velocity (meters per second) and falsely triggering `moving(seat, min_mps)` when the player is physically stationary.
*Fix*: The searcher should evaluate `moving(seat)` using the seat's root body `pos` instead of `cam_pos`, or the logger must export a smoothed root position.

5. **Undefined `_tower_point` scope**: `_tower_point()` is called globally without a reference to the match rules or controller, causing a GDScript runtime crash that breaks the capture.
*Fix*: Prefix the method call to its correct owner, e.g., `_controller._tower_point()`.

6. **Missing map support for landmarks**: The code unconditionally queries tower and portal points, but on non-gameplay maps (like the `grey` studio map for M2 death captures), these may not exist, resulting in a null reference crash.
*Fix*: Check if the landmarks exist in the current map context before attempting to calculate and unproject them.
Ruling: fixed 1 (x/y are -1,-1 for a point behind the camera, bodies and landmarks alike), 3 (a ragdolling body's pos is its ragdoll's drawn centre). 4: the seat's own body pos is in bodies[]; the searcher reads moving() from it, not cam_pos. 2: the tower point is its spawn room (marker + 2 m), the portal the route's end point + 1 m; one point each, by design. 5/6 not real (ran; grey is the ring hidden).

## Audit 4: sure hit, cover shove
1. `tools/capture/seat_intent.gd:_visible_runner`
The raycast and frustum check hardcodes the runner's camera path (`body.get_node(^"Head/Camera")`), which is null for the guard seat and falls back to a blind nearest-runner check.
Fix: Change `var cam: Camera3D = body.get_node_or_null(^"Head/Camera") as Camera3D` to `var cam: Camera3D = get_viewport().get_camera_3d()`.

2. `tools/capture/seat_intent.gd:_set_aim`
The camera origin written is not the seat's own eye because it also hardcodes the runner's camera path.
Fix: Change `var eye: Node3D = body.get_node_or_null(^"Head/Camera") as Node3D` to `var eye: Camera3D = get_viewport().get_camera_3d()`.

3. `tools/capture/seat_intent.gd:_tick_sure_hit`
The shot can still miss because the camera's `global_transform` updates lazily and does not reflect the new rotation before `try_fire()` executes.
Fix: Call `get_viewport().get_camera_3d().force_update_transform()` immediately after `_set_aim(point)`.

4. `tools/capture/seat_intent.gd:_tick_sure_hit`
A step never ends if the runner is visible but the rifle is reloading or cooling down, because the timeout check is unreachable inside the `target == null` block.
Fix: Move the `if _clock >= HIT_WAIT_SECONDS:` timeout block to the top of the function, before checking `target`.

5. `tools/capture/seat_intent.gd:_tick_sure_hit`
The recorded tape cannot replay the hit because calling `shooter.rifle.try_fire()` directly bypasses the `intent` system that the match logger records.
Fix: Replace `var fired: bool = shooter.rifle.try_fire()` with `shooter.intent.fire = true; var fired: bool = true`.

6. `tools/capture/seat_intent.gd:_tick_guard`
The recorded tape cannot replay the scripted miss for the exact same reason: direct `try_fire()` calls bypass the intent logger.
Fix: Replace `if shooter.rifle.try_fire():` with `shooter.intent.fire = true`.

7. `tools/capture/seat_intent.gd:_hold_spread`
The profile swap permanently breaks the shipped rifle if called while already active (e.g. across multiple frames waiting for a shot), as it overwrites the `_shipped_profile` backup with the 0-spread `_sure_profile`.
Fix: Add `if shooter.rifle.profile != _sure_profile:` before `_shipped_profile = shooter.rifle.profile`.
Ruling: fixed 4 (the 8 s cap now ends the step whatever blocked the shot), 7 (no double profile swap). Not real: 1/2 (the guard is the same body scene; its Head/Camera is the seat eye and the smoke hit 3/3), 3 (global_transform reads current), 5/6 (the tape records Rifle.fired, so direct try_fire replays).
