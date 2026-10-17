# Shorts v3: seam review after build 9 (2026-10-17, branch shorts-v3-review from shorts-v3 @ acabb1bb)

Ryan (16:19): "this isnt fucking working. after every test, i want a full deep review of the pipeline to catch bullshit
like this". This is that review: the whole data flow read end to end, every field/flag/file/unit one side writes and
another reads. The nine seams already hit were checked closed (section 3). Everything new is below, ranked by where
the next build would die first. Fixes landed on this branch, one commit each; `python -m sv3.seams` (section 4) now
checks these statically and runs as short3.sh's first step.

## 1. Seams found (ranked), with both sides and the fix

### S1. Clip time: the edl's `in` is the log clock, the mkv starts ~10 s earlier -- FIXED (2faf5ae2)
- Writer: `tools/capture/run_clip.gd:320` `_elapsed += delta` only after `_build()`; events/vis `t` = seconds since the
  first world frame. `tools/content/lib.sh pc_rough` puts that instant in `<raw>.sync` ("take t=0 at N s of the recording").
- Reader: `tools/content/sv3/search.py` carried `in` (log clock) into edl.json; `tools/content/sv3/edl.py:27` wrote
  `file@in:len` straight into the clip cell; `pc/assemble.py` seeks `in` seconds into the mkv. Nothing in
  search/edl/predicates/plan mentioned `sync` (grep: zero hits). Every clip would have shown Godot's load and the white
  sync frames instead of the event.
- Fix: `predicates.Recording.sync` reads `<seat>.mkv.sync`; search.py puts `sync` on every edl entry and montage part;
  edl.py writes `in + sync`.

### S2. Clip path: `_tapes/<tape>/<seat>.mkv` resolves under content/<project>, where there is no pool -- FIXED (2faf5ae2)
- Writer: `predicates.py:19` default file `"_tapes/%s/%s.mkv"`; current run_clip's take.json `files` has only
  `events`/`vis` (the pill-era recorder wrote `files[seat]` = absolute mkv path; this one does not).
- Reader: `pc/assemble.py` `src = os.path.join(project, part["path"])`, project = `content\<name>` -> "no clip at ...".
  The pool is `content\_tapes`, the project's sibling (capture.py `PC_POOL`).
- Fix: default `../_tapes/<tape>/<seat>.mkv`.

### S3. short3.sh calls `sv3.edl` without `--words`, which edl.py requires -- FIXED (34708714)
- `tools/content/short3.sh:105` `sv3 edl ... --brief --tag` (design 8 wording). `sv3/edl.py:79` `add_argument("--words", required=True)`.
  argparse exit 2 at the edl step, every time.

### S4. The end card row is not what assemble.py parses -- FIXED (a62c02e5)
- Writer: `edl.py:54,68` `| T | | | | title 1.0 | | beta link in bio | |` (title + seconds in the `fit` column, clip empty).
- Reader: `pc/assemble.py:387` end card = `row["clip"] == "title"`, seconds from `row["len"]`; otherwise
  `parse_fit("title 1.0")` -> `fit title (line | trim | nohold | wait | window | beat)` SystemExit.
- Fix: `| T | title | | 1.0 | | | beta link in bio | | |` for the end card and every card/black line.

### S5. gif_fade written into the `card` column -- FIXED (a62c02e5)
- Writer: `edl.py:41` `cells.append("gif_fade external/x.gif 0 1.5")` into the card cell; HEADER had no `gif_fade` column.
- Reader: `assemble.py parse_card` -> `card: unknown option external/x.gif`; `parse_gif_fade(row.get("gif_fade"))` never saw it.
- Fix: HEADER gains `| gif_fade |`; card_cell returns (card, gif_fade) and each goes to its column. Also `|` in a
  line's text is replaced by `/` (the provisional table already did; a `|` would shift every column).

### S6. A beat whose word is the string "null" -- FIXED (ccee176b)
- Writer: the model (seen in /tmp/claude-501/sv3/ge.shots.json, every line): `"beat": {"word": "null", "event": "ragdoll", "tol_s": 0}`.
  `translate._nullify` only dropped a beat with an empty word.
- Reader: `search.word_time` looks for the word "null" in words.json -> "beat word 'null' not in voice/words.json", every line fails.
- Fix: `_nullify` treats "null"/"none" as no beat (the schema's `window.beat` is `object|null`; the model writes the string).

### S7. A run_clip refusal is reported as "x s recorded after t=0" -- FIXED (e69fa74d)
- Writer: `run_clip.gd _fail()` prints `--intent names runner:3; the bodies are ...`, `--seat=... is not in this match`,
  `--intent for X would not parse`, `[intent] cannot read step`, `run_clip refuses: ...`.
- Reader: `capture.py:95` `$bad` pattern `^Unknown |Harness: |is filmed with --pov|^No such ` matched none of them, so
  the take failed later on length with the reason only in the PC log; `lib.sh pc_rough`'s tail filter showed no
  `[match]`/`[intent]`/`[seat]` line either.
- Fix: both patterns extended. Diagnostics, not data, but it is why build 9's cause was found late.

### S8. Roster: runners are runner:0.. in the recorder, the schema/plan said runner:1..3 -- closed by the head (e116dbdd) after build 9
- `run_clip.gd _name_the_bodies` `"runner:%d" % k`, k from 0 (pool events: guard, runner:0, runner:1, runner:2).
  Build 9's plan.json: `runner:1=run;runner:2=run;runner:3=run` -> the recorder refuses runner:3 in a 4-player seat match.
- Checked closed: schema FILM seat/intents now runner:0..2, plan.py picks runner:0.., plan drops out-of-roster bodies
  with a warning. seams.py pins all three to the recorder's `k: int = 0`.

### S9. Design/code drift, not fixed (needs a decision)
- Design 9: "Model for every Gemini call: gemini-3.1-pro-preview". `sv3/llm.py` runs `claude -p --model opus`
  (translate, audit, review). The design doc or llm.py is wrong; the code is consistent with itself.
- Design 2 CLI line for `sv3.edl` omits `--words`; the code requires it (S3 fixed in short3.sh; the doc line is stale).
- `review.py` assumes each cut segment is exactly edl `len`: true for fit `line` (search makes len == voice+pad with the
  same pad 0.25) and `wait` (segment = picture); a `title` row is not reviewed (no edl entry) -- fine, but any future
  assemble `carry`/`trim` changes will shift every review window silently. Worth a seams check when assemble changes.

### S10. Verified agreeing (no action)
- Step vocabulary: every `_parse` arm (run, stop, wait, idle, look, cover, portal, brawl, shove_when_rival_within,
  shove_when_rival_cover, miss, hit, scope) has a schema alternative; schema is stricter (rejects `cover:3`, `3s`
  suffixes, guard `run`), which is right.
- Predicates: PREDICATE_DOC 10 names == schema.PREDICATES == predicates.EVAL == translate.FIELDS.
- Events: the 18 `_ev("...")` names in run_clip.gd == schema.EVENTS. vis rows carry t/cam/scoped/bodies/cam_pos/landmarks
  and bodies id/on/h/x/y/d/occ/state/pos -- every key predicates.py reads (the pool's two old tapes lack pos/landmarks:
  a `moving()`/`looking_at()` line will not reuse them, correctly).
- plan.json keys: capture.py reads map/players/seed/opening/seconds/old/kill/cam/look/seat_intent/intent/seats/reuse/
  run_clip_args; plan emits all but `look` (optional). search.py reads seed/map/opening/reuse/reuse_tape.
- Files: run_clip writes `<log>/events.jsonl, vis.jsonl, take.json`; capture pulls them as `<seat>.<name>` plus
  `<seat>.mkv.sync`, `<seat>.log`, `tape.json`; predicates.Recording reads exactly those names; load_pool accepts
  `<seat>.take.json` (seam 5 of the nine, closed).
- Seat ids: `--seat=runner:1` -> file `runner_1.*` -> load_pool `runner:1`; vis `cam` = the seat spec; `is_role` compares
  actors to `self.seat`. Time base: events and vis share `_elapsed` (0.01 / 0.1 s snapping).
- words.json: `{L1: {dur, words:[{word,t,dur}]}}` keyed by brief row `line` = spec id; search/edl read `w["dur"]`,
  `w["words"][i]["word"|"t"]`; word times are wav time (lead silence subtracted) which is the cut's voice time.
- CLIs: every `--flag` short3.sh passes exists in the module; voice.sh/assemble.sh take `--tag`; `--intent=` /
  `--seat-intent=` / `--record=` / `--tape=` / `--log=` / `--sync=` are run_clip options.
- `--intent` reaching the recorder: cannot be confirmed from the Mac pool. The only tapes there (pill_seat_11 15:35,
  hell_seat_20260930 15:12) predate ddc1bde6 and have no `--intent` in take.json `args`; no hell_seat_100x take ever
  landed, because build 9 stopped before capture (its log ends at the translate step; plan.json is from an earlier
  run). The code path is straight: plan `intent` -> capture `--intent=%s` -> pc_rough `-- $ARGS` ->
  `OS.get_cmdline_user_args()` -> take.json `args`; `_install_intents` prints `[intent] N steps on <body>` per body.

## 2. Build 9's artefacts (read-only, pano-sv3)
`run_ge_v1.log` (7 lines): script ok, then translate -- the run was still in translate when read (timing.json has one
step). An earlier translate (ge.translate.log) failed on the audit flapping over `until=ragdoll` and `moving for_s_before`,
and its shots carried `beat.word = "null"` (S6). The latest `v1/shots.json` (16:19) has beats null, roster runner:0..2,
film.intents per body -- so S8 and the flapping are closed in the head; S1-S5 would have hit in order at search/edl/assemble.

## 3. The nine seams already hit -- checked closed
1 relative script path: short3.sh takes the path as given and `[ -f ]`-checks it; the head runs it absolute. 2 `kind:`
header: script.select drops `key:` header lines. 3 audit flapping: translate keeps only HARD findings fatal. 4 `line`
holding text: translate rewrites `line` from the id. 5 pool loader: load_pool accepts `<seat>.take.json`. 6 vis
pos/cam_pos/landmarks: `_sample_vis` writes all three. 7 capture `--intent`: capture.py:56. 8 guard `hit`: `_tick_sure_hit`
writes the aim straight onto the chest with spread held at 0. 9 shove approaching: `shove_when_rival_cover` walks the
ring bake's path to the covering rival (`_walk_to`), shoves within 0.8 x metres.

## 4. seams.py
`tools/content/sv3/seams.py` (`python -m sv3.seams`, 0.1 s, no PC, no model): steps, predicates, events, vis keys,
plan keys, pulled files, the `## script` table (a fixture edl goes through edl.rows_for -> brief.parse -> assemble.py's
parse_fit/parse_parts/parse_card/parse_gif_fade, clip in == log in + sync, title rows, voice rows), CLIs (module exists,
every flag exists, every required flag passed), the sync offset. Teeth: on a copy with 8 deliberate breaks it named 12
seams; on the tree it passes. short3.sh runs it as step 1.

## 5. What the next build will hit first
1. **translate**: still the least deterministic step -- the audit's HARD-word filter (`"map"`, `"seat="`, ...) is a
   substring match on free text; a finding like "window.until ragdoll" passes, "wrong seat" fails. Expect flapping here
   before anything else; the fix is a structured audit schema (field name per finding), not more words.
2. **capture**: first real `--intent` take. The step semantics are unproven on the PC: `shove_when_rival_cover` needs a
   rival the game marks TAKE_COVER or stood still after the 2 s grace; `cover:at:3` crouches the victim where it stands at
   3 s (not at cover geometry). If no rival is "at cover" when the shover arrives, the step times out (`:6`/`:8`) and L3's
   `event(shove, by=seat)` fails -> one reseed, then stop. Watch the `[intent]` lines pc_rough now prints.
3. **search**: `moving(seat, 1.0)` needs vis `pos`; the hell_seat_20260930 reuse tape lacks it, so L1's reuse holds only
   while L1 has no moving()/looking_at(); any runner line films new (correct).
4. **assemble**: first time the v3 table reaches assemble.py; `captions_band 0.06` under STACK_TOP_MAX, `game: 1` ok;
   card pngs (`cards/<id>_card0.png`) are referenced by edl.py but nothing in short3.sh makes them -- a comment_card
   line will fail with "no card at". Not in game_explanation's script.
