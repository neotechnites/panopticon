1. **Total ban on staging violates Rule 374**
- **Violated:** Rule 374 (Ryan explicitly praised the `haters_final` method that was "composed only from the proven stage_driver steps... probe by numbers... tape it").
- **Design Section:** 0 ("Staging is gone") and 1 ("No per-shot bot scripting").
- **Why it fails:** The retrospective wrongly banned all staging. Relying solely on random bot matches (even with a shove-ahead logic) for highly choreographed shots like Short 10's `{walk up to a runner stopped at cover, shove him, he gets shot}` is pure luck. It will likely fail to occur naturally, stopping the build.
- **Fix:** Keep real-match taping for generic chaos. For specific choreography, reinstate the Rule 374 method (`stage_driver` steps + headless PC smoke test) as a valid capture mode instead of outright banning it.

2. **M2 (grey space death) will not trigger the death clip**
- **Violated:** Fact (`map-capture.md` Section 4: lone bots do not spontaneously die; `rules' own kill` is not a real mechanic).
- **Design Section:** 1 (Grey-space old death).
- **Why it fails:** The design expects `--bots=1 --old=1 --seat=free` to result in the bot dying. There is no game rule that randomly kills a single bot in a grey room. The camera will stare at a standing, idle bot.
- **Fix:** Use a one-line `stage_driver` script that calls `kill()` on the bot, or add a `--kill-bot` flag to force the event.

3. **Gemini Spec Translation is banned paraphrasing**
- **Violated:** Rule 373 ("stop fucking paraphrasing me... briefs output the notes ledger entry byte-for-byte").
- **Design Section:** 2 (Script → shots).
- **Why it fails:** Inserting a Gemini translation step to convert text into JSON predicates allows AI to hallucinate or silently drop nuances. It is a new way to misread notes.
- **Fix:** Gemini must be strictly prompted as an entity extractor. If a note contains un-mappable concepts, it must fail loudly and request Rule 374 staging rather than silently omitting the requirement.

4. **Incomplete Visibility Logging and Predicates**
- **Violated:** Fact (`vis.jsonl` only tracks bodies; `map-capture.md`).
- **Design Section:** 1 (vis.jsonl) & 2 (find).
- **Why it fails:** `vis.jsonl` only tracks `bodies[{id, on, ...}]`. It cannot evaluate Short 9's `{looking over at the tower}` or Short 10's `{stopped at cover}` because map landmarks aren't tracked. Additionally, Short 4's `{freaks out and break the players model}` cannot be expressed in predicates. 
- **Fix:** Expand `vis.jsonl` raycasting to track static map landmarks (tower, portal, cover). Tag physics glitch requirements for manual/staged capture.

5. **Missing Comment Question Audio/Text**
- **Violated:** Rule 418 ("every short ends with... the comment question first, then 'the beta link is in my bio'").
- **Design Section:** 4 (Cut).
- **Why it fails:** The design appends a `title` end card for the link, but Script 4 ends without a comment question. The pipeline fails to synthesize the required spoken question.
- **Fix:** `sv3/script.py` must dynamically append a generated script text line for the comment question + CTA if the script lacks it, passing it to `voice.py`.

6. **Missing GIF Downloader and Fade Implementation**
- **Violated:** Fact (`assemble.py` enforces instant pop/stack and lacks fade/URL support; `map-content-v2.md`).
- **Design Section:** 1 (Establishing shots) & 4 (Cut, `gif` overlay with fade-in).
- **Why it fails:** M2 requires a "slow fade in" of `scared.gif` from a URL. `assemble.py` has no URL downloader and refuses alpha ramps (Rule 356 notes offline media composites broke earlier drafts). Additionally, L3's `--cam=dolly:<numbers>` has no mechanism to determine the actual dolly coordinates.
- **Fix:** Add a pre-flight fetcher to download the GIF and convert it to RGB frames. Implement a `gif_fade` command in `assemble.py`. Pass explicit, pre-calculated dolly numbers via a staging script for L3.

7. **Time Budget Blowout on Retries**
- **Violated:** Rule 416 (Time boxes: 20m simple, 35m ragdoll).
- **Design Section:** 3 (Plan) and 5 (Budget).
- **Why it fails:** Design allows up to 3 seeds (3 matches of 75s) if the search fails. 3.75 minutes of capture *per failed shot* plus the massive ffmpeg render overhead for decoding lossless UTVideo will easily destroy the 20-minute limit. Relying on an agent to manually intervene when the build stops after 3 seeds defeats the automated pipeline.
- **Fix:** Cap unscripted tape matches to 30s. If complex predicates fail after 1 seed, immediately fall back to Rule 374 staging instead of blindly rolling more seeds.

BUILD WITH FIXES