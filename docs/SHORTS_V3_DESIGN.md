# Shorts pipeline v3: record real matches, then find the shot (2026-10-17)

Goal (Ryan): input = his script (voice lines, each with a {shot note}); output = a 9:16 draft where every shot meets its note. Simple short ≤ 20 min, any short under 1.5 min ≤ 45 min, no human in the loop. Everything audited by Gemini: this design, the code, the shot translation, and the cut.

Root cause (Gemini retrospective + head): shorts were filmed with the trailer's staging (scripted bodies and cameras) and windows were picked by hope; no gate measured whether the note's event is on screen. Fix: **record real bot matches from a player's seat, log the game's own events and what the seat camera can see, and search those logs for the note's predicates.** Staging is gone for gameplay shots.

## 0. Base
Branch `shorts-v3` from `work-ragdoll-v19` (c964cd40: newest run_clip with tape/record/sync, pc_rough real-time capture at 810x1440, assemble.py v2 refusals, voice.py Andrew pinned). Work packages on `shorts-v3-wp1/2/3`, disjoint files, merged by the head. Nothing from any deleted short is reused.

## 1. Recorder (WP1, GDScript) — `run_clip.gd --match`
A real match, no stage. Flags:
- `--match` (mode), `--map=hell|forest|marble|...`, `--bots=N` (players incl. guard, ≤4), `--seed=S`, `--opening=race|brawl|seat` (sets `open_with_race` / `open_with_tower_brawl` / `opening_seat_index` on the duplicated rules; `seat` = the guard already seated, round starts), `--seat=guard|runner:K|free`, `--seconds=T` (max), `--old=1` (death clip instead of ragdoll, as rs_live `old`), `--shimmer=0`, `--hud=none|crosshair` (guard seat keeps crosshair + scope overlay only), `--record=tape.json` / `--tape=tape.json` (existing clip_tape: run 1 records every body's intent per tick; later runs replay it from another seat, so N seats of ONE match are N takes of one tape), `--log=DIR` (events.jsonl, vis.jsonl, take.json).
- Seat lock: the camera is that body's own Head/Camera (runner) or the TowerShooter controller camera with scope (guard) and NEVER switches body. If the seat dies, the camera follows what a player sees in the game (ragdoll/death cam, then ghost) — never another runner.
- Bots: the shipped brains. One behaviour added so the game's pitch happens in bot matches: a running bot within shove reach of a rival ahead shoves it (`RunnerBrain`, map-agnostic, dial `MatchRules.bots_shove_rivals` default true). No per-shot bot scripting of any kind.
- Grey-space old death (ragdoll M2): `--match --map=grey --bots=1 --old=1 --seat=free --look=at:Runner_0` is the only non-match capture: one body in the grey studio scene, killed by the rules' own kill, death clip plays. Establishing shots (`{slow zoom out shot of the old hell map}`): `--seat=free --cam=orbit|dolly:<numbers>`, a camera move over the real map, no bodies required.

### events.jsonl (one JSON object per line; `t` = seconds since the white sync marker)
`{"t":12.34,"ev":"shot","by":"guard"}` · `shot_result` {by, result: hit|miss, victim?, part?} · `kill` {by, victim, cause: shot|pit|lava|trap|shove_pit|brawl} · `shove` {by, victim, outcome: ring|pit|sights|tower_out} · `out` {body, cause} · `portal` {body} · `seat` {body, turn} · `race_start` · `race_won` {body} · `brawl_start` {bodies[]} · `brawl_out` {body, by} · `brawl_won` {body} · `finale_start` {shover, guard} · `finale_end` · `round_start`/`round_end` {n} · `scoped` {by, on: true|false} · `ragdoll` {body}.
Every event names actors by seat id (`guard`, `runner:K`). `kill` with cause `shot` always follows a `shot_result` hit by ≤ 0.1 s.

### vis.jsonl (10 Hz, from the seat camera)
`{"t":12.3,"cam":"runner:1","yaw":123.4,"pitch":-5.1,"scoped":false,"bodies":[{"id":"runner:2","on":true,"h":0.31,"x":0.52,"y":0.48,"d":7.9,"occ":false,"state":"run|dead|ragdoll|ghost|shoved"}]}`
`on` = chest inside the frustum AND an occlusion ray from the camera to the chest hits that body first; `h` = screen height fraction of head-to-feet; `x,y` = chest in 0..1 screen space; `d` = metres.

### take.json
args, commit, seed, map, opening, seat, sync t0, duration, tape path, file paths. The PC side (pc_rough) is unchanged: 810x1440 real time, utvideo, white sync frames.

## 2. Script → shots (WP2, Python, Mac)
`sv3/script.py`: Ryan's raw script (paragraph of voice text, then `{note}` on its own line or inline; a `{note}` with no text = a beat; `(pause on it)` = beat; a line whose note says "same shot" continues the previous capture) → `spec.json` `[{id:"L1", text, note, beat:false}]`. His text is never altered.
`sv3/translate.py`: ONE Gemini call per script with the schema below, then a SECOND Gemini call that audits each translation against the note and rules; a disagreement fails the plan with both answers printed. Output `shots.json`:
```
{"id":"L4","source":"match|studio|establishing|card|black",
 "match":{"map":"hell","opening":"seat","players":4,"old":false,"same_match_as":"L1|null"},
 "seat":"guard|runner:any|free",
 "find":[  predicates, all must hold in the chosen window ],
 "window":{"lead_s":0.8,"tail_s":1.2,"beat":{"word":"Ragdolls","event":"kill","tol_s":0.1}},
 "overlays":[{"kind":"comment_card","at":"word:this guy"}], "interpreted":"one line why"}
```
Predicate language (closed set; the translator may only use these):
- `event(ev, by?=seat|other, victim?=other, cause?, count>=n)` within the window
- `before(evA, evB)` ordering · `on_screen(who=victim|runner:any, min_h, for_s_before, for_s_after)` · `moving(who, min_mps)` (from vis positions) · `no_event(ev)` (e.g. no shot for the misses-only part) · `seat_state(alive|dead|ghost)` · `distinct(victim)` for montages · `scoped(true|false)`.
Examples: `{pov of the sniper shooting at some runners and missing ... they hit one}` → seat guard, find `[event(shot_result,result=miss,count>=2), event(kill,by=seat,cause=shot), before(miss,kill), on_screen(victim,0.06,0.5,1.5)]`, beat none, tail = until `ragdoll` + 1.0 s. `{runner pov near the end, he watches the person in front of him get shot}` → seat runner:any, `[event(kill,victim=other,cause=shot), on_screen(victim,0.12,1.0,1.2), moving(victim,1.0), moving(seat,1.0)]`, same_match_as the sniper line, beat `kill` on "Ragdolls".

## 3. Plan and capture (WP3 + WP2)
`sv3/plan.py`: groups lines by `match` (same map/opening/old/same_match_as) → list of matches, each with the seats it needs. For every match: first the **tape pool** (`~/Desktop/panopticon-renders/content/_tapes/<map>_<opening>_<seed>/{tape.json, <seat>.mkv, <seat>.events.jsonl, <seat>.vis.jsonl}`) is searched (sv3/search.py); a line whose predicates hold in an existing tape reuses it (this is Ryan's "footage index": "if its better to film first, great ... the only thing ill say is that it probably means were doing a shit job of organizing our footage"). Otherwise capture.
`sv3/capture.py`, `sv3/search.py`: removed; the stage path replaced them (senate panopticon pod `data/plan/shorts-v3/DESIGN.md` §10).

## 4. Cut, review, deliver
`sv3/edl.py` writes the `## script <tag>` table for the existing `assemble.py` (clip `path@in:len`, speed 1, captions `stack` (slam-on), cards at words, `title` end card "beta link in bio"); `voice.sh` (Andrew +5 %) runs before search so every slot's length is known; `assemble.sh` on the PC (refuses speed < 1, freezes, short picture). assemble.py additions (WP3): `title` end card, `gif` overlay with fade-in for M2, `stack` captions appear instantly.
`sv3/review.py`: Gemini 2.5-pro on the delivered mp4 with the edl windows and every line's NOTE (design (e) prompt, defects list incl. slowed_motion, wrong_pov, standing_still, body_transparent, event_not_visible, same_as_earlier_version); any `no` → that line's match re-searched with the next seed once, re-cut, re-reviewed; a second `no` stops the build with Gemini's words. Nothing reaches Ryan without a review.json that passes.
`tools/content/short3.sh <script.md> --name <project> --tag vN [--mac-only]`: seams→script→translate→voice→words→plan→short.sh→pull→frames→review (advisory)→deliver, each timed into `timing.json`; no capture or search step: the stage path replaced them (senate panopticon pod `data/plan/shorts-v3/DESIGN.md` §10).

## 5. Budget (measured parts): take = 9 s load + T + gate; T=75 → ~90 s. Short 10: 1 hell match × 2 seats + 1 finale match (seat runner, `--opening=seat`, until finale_end) = 3 takes ≈ 5 min; voice 1; search+edl < 1; assemble 2.5; review 1.5; total ≈ 12 min. Ragdoll: hell L1 (old=1, guard) 1 take; studio M2 1; establishing L3 1; hell L4 2 seats; forest L5 1 (guard, 3-5 kills); hell L6 runner seat 1; finale L7 1 = 8 takes ≈ 13 min + 6 = ~20 min.

## 6. Not built: any bot "director", any new staging vocabulary, pixel-based event search (the game log is the truth; Gemini is the last check, not the finder), multi-viewport simultaneous recording (tape replay already gives N seats of one match).

## 7. Fixes from Gemini audit 1 (gemini-design-audit-1.md) — part of the design
1. **Seat intent:** removed; the stage path replaced it (senate panopticon pod `data/plan/shorts-v3/DESIGN.md` §10).
2. **M2 kill flag.** `--kill=runner:0@3.0` makes the recorder apply the rules' kill to that body at that time (grey studio + `--old=1`). Nothing else kills a body.
3. **Translation = extraction only.** The translator may only emit the closed predicate set and must copy the note verbatim into `note`; any phrase it cannot map goes into `unmapped[]` and the plan FAILS listing those phrases (no silent drop). The second Gemini call checks every predicate against the note and flags anything invented. Ryan's "if we can, get one that freaks out" is logged as unmapped-optional (an `optional: true` phrase does not fail the plan).
4. **Landmarks and states in vis.jsonl.** Each sample also carries `landmarks: {tower:{on,x,y,d}, portal:{on,x,y,d}}` and each body carries `state` from the game (`run|cover|dead|ragdoll|ghost|shoved|brawl`); predicates add `looking_at(tower|portal, for_s)` and `state(who, cover)`.
5. **No synthesized voice lines.** The pipeline never adds words Ryan did not write (decision 373). The end card "beta link in bio" is a card, not a line; a comment question exists only if his script has one.
6. **GIF + establishing numbers.** `{slow fade in of an image i will provide <url>}`: the planner fetches the URL to `external/` (fetch.py), assemble.py gets `gif_fade: <file> <from_word|t> <seconds>` as an overlay. Establishing `--cam=orbit` takes its numbers from the map (ring centre and radius from the ring bake), no agent numbers.
7. **Time caps.** Match takes default `--seconds=45` (montage lines 60); at most 2 seeds per match group, then stop with the failed predicates. Capture total per short is printed before filming and the build refuses a plan over 25 min of capture.

## 8. CLIs (the contract between work packages; Python = `tools/content/.venv/bin/python`, created by `tools/content/sv3/setup.sh` with google-genai + jsonschema; GEMINI_API_KEY from the environment)
- WP2: `python -m sv3.script <script.md> --out spec.json` · `python -m sv3.translate spec.json --stages sv3/stages.json --out shots.json` · `python -m sv3.plan shots.json --stages sv3/stages.json --words voice/words.json --brief tools/content/projects/<name>.md --tag vN` (appends the entries and the `## script vN` table) · `python -m sv3.review final.mp4 edl.json shots.json --out review.json` (advisory).
- WP1: `run_clip.gd --match ...` flags as in §1 and §7; writes `<log>/events.jsonl`, `vis.jsonl`, `take.json`; `--record/--tape` for seats of one match; `tools/capture/MATCH_RECORD.md` documents every flag, event and field with one example line each.
- WP3: `tools/content/short3.sh <script.md> --name <project> --tag vN [--mac-only]` (seams, script, translate, voice, words, plan, short.sh, pull, frames, review, deliver; timing.json, Mac copy) · assemble.py additions (`title` end card, `gif_fade`, instant `stack`). The capture/search steps are gone: the stage path replaced it (senate panopticon pod `data/plan/shorts-v3/DESIGN.md` §10).

## 9. Ryan's correction (2026-10-17 15:03) — supersedes §3's "record then find" as the MAIN method
Ryan: "what the fuck does any of this tooling have to do with scripting players in game which we can already do, and fuckign screen recording. thats it. thats how we film. why the fuck do we need 'recording from a seat'". And (monitor, confirmed by Ryan: "this is me telling you to stop being a dumb fuck"): keep the camera locked to a player's view, keep scripted player inputs, keep the event log and the per-line check; drop record-then-search as the main method — "script the shot first, record it, check it".
So: **filming = scripted players + screen recording.** The per-body `--intent` scripting this section first named is gone: the stage path replaced it (senate panopticon pod `data/plan/shorts-v3/DESIGN.md` §10). Gemini review of the cut stays. Model for every Gemini call: gemini-3.1-pro-preview (Ryan's monitor set it).
