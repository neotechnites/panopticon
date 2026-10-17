1. tools/content/sv3/seams.py:67: The `seats` set comprehension incorrectly includes `"runner:any"`, causing `seats != plan_seats` and `seats != set(S.FILM["properties"]["intents"]["properties"]) - {"guard"}` to always evaluate to True. This emits two false positive failure reports on a correct tree.
   Fix:
   `seats = {s for s in S.FILM["properties"]["seat"]["enum"] if s.startswith("runner") and s != "runner:any"}`

Ruling (head review, 2026-10-17): not real. FILM.seat enum is guard|runner:0|runner:1|runner:2|free (runner:any lives in SHOT.seat, which seams.py does not read); `python -m sv3.seams` passes on the tree and named 12 seams on the deliberately broken copy. No change.
