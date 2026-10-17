# map-capture.md (mapping agent report, 2026-10-17)

I mapped the capture pipeline in both checkouts (read-only). Unless marked "main", paths are under /Users/ryanwhitehead/Documents/olympus/pano-ragdoll-v19. Main's run_clip.gd is an older 1196-line version with no `--tape`/`--record`/`--sync`. The headline: no capture mode today records an unstaged bot match from one player's seat, logs every event with who did it, and holds the camera on that one seat.

**1. run_clip.gd / stage_driver.gd**
- Entry is `tools/capture/run_clip.gd`: `_initialize` then `_build`. It loads `res://match/match.tscn`.
- `_make_it_bots_only` sets `controller.player=null` and works on a duplicated `MatchRules`. `--bots` sets `prisoner_count` (default 7). `--map=` sets `rules.map_id`. A stage plugin's `tune_rules` is applied here too. It also frees SettingsBoot and Music and disables HUD, NetMatch and the other screen layers.
- `--seed` (default 20260930) calls the global `seed()` and seeds `BotTowerSeat.install(controller, profile, seed)`. Runner perception seeds are not set; `runner_brain.gd:194` falls back to `SEAT_SEED_BASE+seat`. `bot_match_runner.gd` does seed them, via `_seed_runners`/`BotHarness.stream_seed`.
- Same seed should give the same ticks on the same machine (bot_match_runner.gd:25-34), but nothing guarantees it. The exact-replay path is `--record=`/`--tape=` (`tools/capture/clip_tape.gd`, which stores every body's intent and trigger pull per tick) plus `tools/content/tape.sh`.
- Any `--pov`, or any staged stage, makes `_build` call `start_round()` straight after `start_match()` (lines 434-435). The race is skipped in practice.
- `round_resolved` restarts the next round and `match_won` restarts the match, so a clip never ends on a frozen ring.
- `--pov=runner` (`_ride_a_body`) makes a lane runner's own `Head/Camera` current, never writing to it. It prefers the staged body, otherwise the fastest runner on the lane, and switches body when that one dies or sticks for 2.5 s. `_wear_the_body` calls `PrisonerAvatar.set_viewed_body`, so the head is hidden and first-person arms show.
- `--pov=guard` (`_ride_the_guard`) uses the `TowerShooter.controller` camera, which is the bot's real aim: ADS, scope, recoil and reload all reach the lens. `_hand_over_the_scope` calls `ScopeVignette.set_local_holder(true)`, so yes, the scope overlay is drawn.
- `stages/rs_live.gd` stages nothing: shipped bot guard, projectile speed 195.
  - `ride=Runner_1` only calls `stage_body()`, so `--pov=runner` locks onto that runner's eyes.
  - With `--pov=guard` it holds the scope on the shot through the round's flight, then eases it after the falling ragdoll (`on_shot`, `_watch_the_fall`).
  - It widens the scope's clear area with `LIB.open_the_scope(guard, clear=0.74)`.
  - Other dials: `old`, `spectate`, `tower_fov`, `beat`, `ahead`, `sure`.
- `[event]` lines come from `_log_the_rifle` and `_log_events`, stamped with `_elapsed` (seconds since the world was built):
  - `shot confidence`
  - `shove A -> B at deg r`
  - `hit <collider>`
  - `miss`
  - `out <body> <cause> at deg r`
  - `catch`
  - `ghosted`
  - `seat <body> turn N` (this is how a portal win or tower take shows up)
- There is no shooter name on shot/hit/miss. There are no `kill_beat_started`/`finisher_armed` (finale), portal or race events. `[pov]` lines log ride changes.
- `bot_match_telemetry.gd` (headless sweep, not capture) prints `TRACE`/`MATCH` JSON per runner, not per-frame camera data.

**2. Openings**
- `scripts/match/match_rules.gd:422-454` has three settings: `open_with_race` (default true), `open_with_tower_brawl` (default false) and `opening_seat_index` (read only when the race is off).
- The game sets them in `scripts/ui/game_settings.gd:1157-1162`.
- No run_clip flag sets any of them. The only way is a stage plugin's `tune_rules(rules)`, and no capture stage touches them today.

**3. Finale**
- `match_controller.gd` call chain: `shove()`, then when the finisher shoves during the round, `throw_guard`. That runs `_begin_kill_beat`, which calls `_throw_guard_out` (opens the tower, `PrisonerAvatar.throw_out`) and emits `kill_beat_started`.
- `scripts/camera/finale_view.gd` (`FinaleView._on_guard_thrown`) uses its own Camera3D outside the tower. It picks a side-on spot (`side_distances` 14/20/9 m) and pans and zooms along the predicted arc.
- The 0.35 s wait is `cut_delay`, from commit b4c50f98 on main. It is NOT in v19. `run_clip._ride_a_body` stands aside while `finale.is_active()`.

**4. Old death animation**
- It still ships: `death_clip=&"Death"` in `scripts/player/prisoner_avatar.gd:281`, played at :787 when `_ragdoll==null`.
- `old=1` in `rs_live.gd:70` and `rs_snipe.gd:17` sets `_ragdoll` to null.
- The ragdoll arrived in commit 06bdee8f (2026-10-05). The last commit before it is 3a8cefd3.

**5. PC capture (`tools/content/lib.sh` + `shot.sh` in v19 and pano-trailer; main has only Movie Maker)**
- Rough takes, the default, use `pc_rough`. Godot runs at `--fixed-fps 60 --max-fps 60 --resolution 810x1440 --position 0,0`, borderless and always-on-top via a temporary `override.cfg`. ffmpeg records it with `ddagrab` (no cursor) to lossless `utvideo`. It runs as an Interactive scheduled task.
- Sync: `--sync=90` shows white frames, and `blackdetect` on the negated video finds t=0, written to `<raw>.sync`. The take is scaled to 1080x1920 at the cut.
- `--movie` gives a Movie Maker final at 1080x1920.
- Gate (shot.sh `take`/`best_take`): motion must average at least 0.02 (`tblend` difference at 10 fps). No freeze of 0.75 s or more is allowed (`freezedetect` -50 dB), unless the brief says `freeze: waive`. A rough take gets one attempt and dies if it fails the gate.
- Measured in PLAYBOOK.md:103-107 for one 6 s shot: Godot 26 s (including 9 s load), gate 2 s, render 11 s, about 50 s per shot. The whole pipeline end to end took 117 s.
- Return to the Mac: SSH to `ddd@100.114.41.16`. Cuts stay on the PC, viewed through `serve.sh` (HTTP over Tailscale). `short.sh` uses `pc_pull` (scp) to copy the final mp4. `sync.sh` pushes the branch to `C:\dev\verify`.

**6. Visibility logging**
- Does not exist. The only `unproject_position` is in `tools/capture/menu_banner.gd:108`, which is for the menu art. There is no `is_position_in_frustum` and no per-frame on-screen, bounding-box or distance log.
- `rs_live`'s spectate mode only prints line-of-sight "clear/blocked" and distance at hits (`STAGE_DEBUG`).

**What does not exist**
- An unstaged match run from one seat's eyes. `--pov=runner` jumps to another body when its runner dies, and `rs_live ride=` is the closest thing.
- Capture flags for race or tower-brawl openings.
- Logging of finale, portal or race events, or a shooter name on shot/hit/miss.
- A guarantee that a seed replays the same match (only a tape does).
- Per-frame visibility logging.