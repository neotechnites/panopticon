Here are the concrete defects found in the code, categorized as requested:

**1. Malformed or non-conforming model answer PASSES**
*   **File:** `tools/content/sv3/llm.py:40` (Error envelope bypass)
    *   **Failing input:** Claude returns an API error envelope like `{"type": "error", "error": {"message": "..."}}` which lacks `is_error` and `subtype`.
    *   **One-line fix:** Change the condition to `if envelope.get("type") == "error" or envelope.get("is_error") ...`.
*   **File:** `tools/content/sv3/llm.py:73` (Prose around JSON)
    *   **Failing input:** Model output containing prose *before* the JSON (e.g., `Here is the JSON: {"ok": true}`).
    *   **One-line fix:** Reject text before the JSON by adding `if body[:i].strip(): raise ValueError("text before JSON")`.
*   **File:** `tools/content/sv3/llm.py:60` (Fences permitted)
    *   **Failing input:** Model answer wrapped in markdown fences ````json ... ````.
    *   **One-line fix:** Remove the `_strip_fences` function entirely and use `body = text.strip()` to strictly reject fenced output as the prompt demands.
*   **File:** `tools/content/sv3/translate.py:168` (Extra fields)
    *   **Failing input:** The audit model returning unexpected extra fields in its JSON output.
    *   **One-line fix:** Add `"additionalProperties": False` to the items schema in `audit_schema`.

**2. NOTE is DROPPED or altered**
*   **File:** `tools/content/sv3/review.py:108` (Empty note / beat dropped)
    *   **Failing input:** A shot representing a beat where the note text is strictly empty (`note=""`).
    *   **One-line fix:** Remove the `elif not s.get("note"):` check so valid beats proceed to frame extraction and review instead of failing automatically.
*   **File:** `tools/content/sv3/translate.py:124` (Crash on dict spec)
    *   **Failing input:** `spec.json` formatted as a dictionary `{"lines": [...]}`. Iterating `for e in spec` yields the string `"lines"`, crashing on `e["id"]`.
    *   **One-line fix:** Map it before iterating: `for e in (spec["lines"] if isinstance(spec, dict) else spec):`.
*   **File:** `tools/content/sv3/translate.py:211` (Altered intent)
    *   **Failing input:** A predicate intentionally declaring `for_s_before=0.0` (meaning do not require movement before). 
    *   **One-line fix:** Remove the loop that overwrites `0` or `0.0` to `1.0`, which silently overrides the note's extracted intent.

**3. Review PASSES a clip it did not look at**
*   **File:** `tools/content/sv3/review.py:112` (`partly` treated as pass)
    *   **Failing input:** A model review returning `"matches_note": "partly"` and `"defects": []`.
    *   **One-line fix:** Change the condition to `if r["matches_note"] != "yes" or r["defects"]` so partly matching is correctly failed.
*   **File:** `tools/content/sv3/review.py:114` (Answering without reading)
    *   **Failing input:** The model hallucinating the `sheets_read` array directly from the prompt legend without actually executing the `Read` tool.
    *   **One-line fix:** Pass the images directly in the API prompt instead of relying on the unverified `Read` tool and self-reported arrays.

**4. Shell/subprocess hazards**
*   **File:** `tools/content/sv3/llm.py:26` (Prompt as argv)
    *   **Failing input:** A large translation prompt (~60 KB) passed directly into `cmd` as `-p prompt`, risking OS `ARG_MAX` and per-arg length bounds.
    *   **One-line fix:** Pass the prompt via standard input by executing `subprocess.run(..., input=prompt)` and removing `-p prompt` from `cmd`.
*   **File:** `tools/content/sv3/llm.py:22` (Environment leakage)
    *   **Failing input:** Context containing `CLAUDE_CODE_SESSION_ID` or other specific tool env variables not filtered out.
    *   **One-line fix:** Broaden the filter to `if not k.startswith("CLAUDE")` to prevent leakage into the nested cli.