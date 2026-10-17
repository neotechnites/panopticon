**A.**
None. All requested `haters-v2` behaviours (`print("[event] ...")`, `[lens]`, `[cam]`, `_log_the_lens`, `_probe_the_lens`, `_lens_frame`, `--frame`, `_lens.free_space()`, `--tape`/`--record`, `--pov=guard`) are intact in the merged file for non-match runs.

**B.**
1. The `--cam` option is dropped: `"cam"` is parsed in `run_clip.gd:268` (`_initialize()`), but `_options.get("cam")` is never read.
2. As a consequence, the `cam` field is missing from the `take.json` dictionary in `run_clip.gd:1415-1422` (`_finish_match()`).

**C.**
1. **Duplicate event signals:** In `run_clip.gd:1384-1385`, `_build_match()` calls both `_log_events()` (from haters-v2) and `_hook_match_events()` (from shorts-v3). Both connect to the exact same match signals (e.g., `_controller.participant_shoved`, `_controller.participant_converted`), so both hooks will fire redundantly during a match, printing both the string `[event]` lines and the JSON `[ev]` lines for the same actions.
2. **Hook early-return bypass:** In `run_clip.gd:326-332`, `_process()` executes an early `return false` when in `--match` mode. This entirely bypasses the `haters-v2` hooks lower in the function (`_log_the_lens` at line 351, `_probe_the_lens` at line 356, and `_lens.free_space()` at line 361), preventing the `[cam]` and `[lens]` probes from ever running when in match mode.
3. **Variable shadowed:** In `run_clip.gd:1228`, the lambda connected to `kill_beat_started` declares `_seconds: float` as a parameter. This directly shadows the script's global member variable `var _seconds: float = 0.0` declared at `run_clip.gd:178`.
## Disposition (merge agent)
Every finding above is present identically on `shorts-v3` before the merge (checked by line: `cam` parsed but unread, `_build_match` calling both `_log_events()` and `_hook_match_events()` by design for text + JSON rows, `--match` returning before the shot-only lens probe, the `_seconds` lambda parameter). None is a haters-v2 behaviour lost or a v3 field dropped by the merge; nothing changed for them.
