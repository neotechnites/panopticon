Here is the audit of the `sv3` pipeline against the design and Ryan's rules.

### 1. Requirements Dropped Silently

**1. `audit` passes vacuously if Gemini omits shots**
* **File:** `sv3/translate.py:main`
* **Defect:** The build validation `bad = [v for v in verdict if not v["ok"] ...]` only iterates over the items Gemini returns. If Gemini returns an empty array `[]` or omits a line, `bad` is empty, and the translation passes the audit silently.
* **Fix:** Add `if len(verdict) != len(shots): problems.append("audit missed shots")`.
* **Severity:** HIGH

**2. Note keyword "bonus" allows ALL unmapped phrases to be dropped silently**
* **File:** `sv3/translate.py:local_check`
* **Defect:** `OPTIONAL_RE.search(e["note"])` searches the *entire* note. If the note says "kill a runner, bonus if he falls in lava", Gemini can map "falls in lava" correctly, but then wrongly dump "kill a runner" into `unmapped` with `optional: true`. Because the note contains "bonus", `local_check` allows it, and `unmapped_failures()` drops it.
* **Fix:** `audit` must explicitly verify that phrases marked `optional: true` in `unmapped[]` correspond ONLY to the specific optional requests in the note.
* **Severity:** HIGH

**3. `distinct` predicate passes vacuously for montages without an anchor**
* **File:** `sv3/search.py:search_shot`
* **Defect:** `ev_distinct` trivially returns `True` because it relies on `search_montage` to enforce victim uniqueness. However, `exclude_victims` is only checked inside the `rec.occurrences` loop. If `anchor is None`, it skips that loop entirely, meaning `distinct` is never checked and the exact same clip is used `n` times.
* **Fix:** In the `if anchor is None:` block, add a check for `if None in exclude_victims: continue`. 
* **Severity:** MED

### 2. Shorter than Voice Line & Beat Missing Word

**4. Montage rounding causes the final clip to be shorter than its voice line**
* **File:** `sv3/search.py:search_montage`
* **Defect:** `part = max(1.0, slot / n)` is rounded when appended: `round(part, 3)`. If `slot=4.0` and `n=3`, `part` becomes `1.333`. The total length is `3 * 1.333 = 3.999`. Because `3.999 < 4.0`, it is strictly shorter than the voice + pad slot, which will freeze `assemble.py` (or fail the `edl.py` check).
* **Fix:** Do not round `part` before appending to `hits`, or calculate the final part's length as `slot - sum(previous_parts)`.
* **Severity:** HIGH

**5. `edl.py` silently drops the short-duration check if `--words` is omitted**
* **File:** `sv3/edl.py:rows_for`
* **Defect:** `w = words.get(line["id"]) if words else None`. Since `--words` is an optional CLI argument (as documented in `SHORTS_V3_DESIGN.md`), omitting it leaves `words` empty. `w` becomes `None` and the `total + 1e-6 < w["dur"] + pad` check is bypassed entirely, allowing a freezing clip to reach `assemble.py`.
* **Fix:** Make `--words` a required argument in `edl.py`, or fail the build if it's missing but a duration check is needed.
* **Severity:** MED

**6. Montage completely destroys exact beat word alignment**
* **File:** `sv3/search.py:search_montage`
* **Defect:** `search_shot` calculates `tin` to land the beat exactly on the spoken word. But `search_montage` ignores this math entirely and blindly overwrites it with `tin = max(0.0, hit["anchor_t"] - 0.55 * part)`, forcing the event to sit at 55% of the montage part and missing the word entirely.
* **Fix:** If `window.beat` is specified, `search_montage` must preserve `hit["in"]` and `hit["len"]` returned from `search_shot`.
* **Severity:** HIGH

**7. Missing `event` predicates cause `beat` requests to be ignored**
* **File:** `sv3/search.py:anchor_pred`
* **Defect:** If the script specifies `window.beat` but the translation emits no `event` predicates, `anchor_pred` returns `None`. `search_shot` then takes the `anchor is None` path, which never evaluates `beat_t`. The beat event is silently ignored and misses its word.
* **Fix:** If `window.beat` is present, `anchor_pred` should synthesize a search predicate for `beat["event"]`, or `search_shot` must reject the shot if it lacks an anchor.
* **Severity:** MED

### 3. Clip Slowed, Sped, Frozen, or Held

**8. Montages force `fit="line"`, causing longer clips to be sped up/truncated**
* **File:** `sv3/search.py:search_montage`
* **Defect:** It hardcodes `"fit": "line"`. If the total montage length `n * max(1.0, slot/n)` exceeds `slot` (e.g. `n=3, slot=1.5` -> total `3.0s`), `assemble.py` will force the 3.0s of video into the 1.5s voice line, causing an illegal speed-up.
* **Fix:** Set `"fit": "wait" if sum(h["len"] for h in hits) > slot + FRAME else "line"`.
* **Severity:** HIGH

**9. `anchor is None` forces `fit="line"`, causing speed-up for long windows**
* **File:** `sv3/search.py:search_shot`
* **Defect:** If `anchor is None`, `length` becomes `lead_s + tail_s` (e.g., 10s). `fit` is hardcoded to `"line"`. If the voice `slot` is only 2s, a 10s video with `fit="line"` is fed to `assemble.py`, which will speed it up to fit the 2s slot.
* **Fix:** Set `"fit": "wait" if length > slot + FRAME else "line"` inside the `anchor is None` block.
* **Severity:** HIGH

### 4. Translation Invents

**10. JSON schema forces Gemini to invent `map`, `seat`, and `opening`**
* **File:** `sv3/schema.py:SHOT`
* **Defect:** `map`, `opening`, `players`, `old`, and `seat` are hard-required arrays. If the script note doesn't specify them, Gemini must guess to pass JSON validation (the prompt even instructs it: "else hell"). `audit` then incorrectly passes this as "implied", effectively hiding the invention.
* **Fix:** Make these fields nullable/optional (`"type": ["string", "null"]`) in the schema, or explicitly instruct `audit` that defaults supplied to satisfy the schema are not "invented".
* **Severity:** MED

### 5. Rule Violations & Local Crashes

**11. `plan.py` ignores Rule 417 ("from scratch") and reuses old footage**
* **File:** `sv3/plan.py:main`
* **Defect:** The planner blindly checks `if s["id"] in found` and sets `reuse = tape`, completely skipping capture. It never checks the script text for "from scratch", resulting in old footage being reused when Ryan explicitly banned it.
* **Fix:** Check the script text; if "from scratch" is present, bypass the `found` pool reuse logic.
* **Severity:** HIGH

**12. `search.py` searches and reuses off-limits trailer footage (Rule 370)**
* **File:** `sv3/predicates.py:load_pool`
* **Defect:** `load_pool` recursively loads all tapes in the directory. It does not exclude tapes starting with `trailer_`, violating Rule 370 ("trailer shots are off limits for shorts").
* **Fix:** Add `if "trailer" in tape: continue` inside `load_pool()`.
* **Severity:** HIGH

**13. `edl.py` fails the build for valid `card` and `black` shots**
* **File:** `sv3/edl.py:rows_for`
* **Defect:** The sanity check `not all(e.get("file") for e in entries)` is `True` for `card` and `black` shots because their `file` is legitimately `None` (set properly in `search.py`). This causes `edl.py` to hard-fail the build instead of generating the title card.
* **Fix:** The check should be updated to ignore files for non-recorded sources: `all(e.get("file") for e in entries if e.get("seat") is not None)`.
* **Severity:** HIGH

***

**What is sound:**
* **Beat alignments for non-montage shots:** Accurately subtracts `prev_len` and aligns precisely to `word_time`. 
* **`moving` and `on_screen` evaluations:** Correctly scale across available vis spans and reject missing tracking data safely.
* **`assemble.py` freezing safety (mostly):** The EDL correctly verifies durations (if `--words` is present), and `try_anchor` guarantees it won't pad a cut past `rec.dur`.
* **>4 Player limits:** Handled correctly via strict JSON schema `maximum: 4` bounds.