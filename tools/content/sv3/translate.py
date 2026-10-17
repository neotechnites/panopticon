"""spec.json -> shots.json by extraction only (Gemini 2.5-pro, JSON schema), then a second Gemini call audits every predicate
against its note. Exit 2 on an unmapped (non-optional) phrase or a disagreement, with both answers printed.

    python -m sv3.translate spec.json --out shots.json [--fixture shots.json]   (fixture = offline, no Gemini)
"""
import argparse
import copy
import json
import os
import sys

import re

import jsonschema

from sv3 import schema as S

MODEL = "gemini-3.1-pro-preview"
RULES = """Ryan's rules that bind the translation:
- A "pov"/"runner pov"/"sniper pov" is a PLAYER's eyes (seat guard or runner:any), never a free camera (free only for studio/establishing).
- Never slow motion; never a freeze; a hit body never goes transparent. These are cut rules, not predicates: do not emit them.
- At most 4 players including the guard. Two perspectives of one game = same_match_as the earlier shot.
- "same shot" continues the previous line's capture: same_match_as that line, same seat.
- Montage ("clip montage", "a bunch of") = montage:N clips (3 unless the note says) with distinct(victim).
- The note is copied byte-for-byte into `note`. You may NOT paraphrase, summarise, add, or drop any requirement.
- film{} is REQUIRED on every match/studio shot: the exact seat body, map, opening, players, old, and intents for every
  body the note scripts (only steps from the closed vocabulary; a note's action you cannot script goes to unmapped[]).
  same_match_as shots share one film{} (same intents, different seat). film.seat for runner povs is runner:1 unless the
  note's action needs another body as the pov.
- A phrase is MAPPED when any field expresses it: match.map ("in hell", "forest"), match.old ("old", "pills", "how it started";
  "how its going" = old false), match.opening ("race", "brawl"/"starting shove tower minigame"), seat ("pov", "sniper pov",
  "runner pov"), source, camera, window.until/beat ("ragdolls" = until ragdoll or event ragdoll), overlays (cards, image URLs),
  montage, same_match_as ("same shot"), or a predicate. Only a requirement NO field or predicate can express goes into unmapped[] verbatim; optional:true only when the note itself
  says "if we can"/"preferably"/"prefferable". Do not invent predicates the note does not ask for; `interpreted` is one line
  saying what you decided (e.g. which map when the note names none: the short's other lines decide, else hell).
- A beat (text "") is a shot with no voice; its length comes from the window. A `{...image URL...}` note is a gif_fade overlay
  with url = the URL and at = "t:0" (the fade starts when the shot starts), seconds = 1.5.
- A comment-card: the note or text says "this guy"/a comment -> overlays comment_card at "word:<the words in the text>".
- Beat alignment: if the note says the event happens when a word is said ("when i say X", "near the end", "right at the end"
  with a line of text), window.beat = {word: that word (the last word of the text for "end"), event, tol_s: 0.1}.
- One line may need several shots in sequence ("then cut to ..."): emit several entries with the same `line` and ids L4a, L4b.
- players: hell 4 unless the note says, forest 4, grey 1. seat: a shot described from the sniper = guard, from a runner = runner:any.
- Covered phrases, never unmapped: "slow fade in of an image" = overlays gif_fade; "slow zoom out shot" = source establishing +
  camera "dolly_out" (orbit/dolly_in/dolly_out/bust); "in the back"/"the person in front of him" = on_screen(runner:any or
  victim) from a runner seat (what a runner sees is ahead of him); "watching the shots at them" = event(shot_result, by=guard)
  + on_screen(runner:any); "the usual cinematic shot" = until finale_end; "a 'real game'" = source match.
- Rule 419 (Ryan): a runner never sits there. Every runner:any pov carries moving(seat, min_mps 1.0); it is required framing.
- moving() takes for_s_before / for_s_after (never for_s): "walk up to" = moving(seat, 1.0, for_s_before=1.5);
  "continue the course"/"and run" = moving(seat, 1.0, for_s_before=0, for_s_after=1.5). Idle = min_mps 0, max_mps 0.2.
- `until`: the event the window runs to before tail_s (e.g. "we cut a little after the animation plays out" -> until ragdoll,
  tail_s 1.0). lead_s is the seconds of picture before the first required event (0.8 default)."""

EXAMPLES = json.dumps([
    {"id": "L1", "line": "L1", "source": "match",
     "match": {"map": "hell", "opening": "seat", "players": 4, "old": True, "same_match_as": None}, "seat": "guard",
     "film": {"seat": "guard", "map": "hell", "opening": "seat", "players": 4, "old": True, "intents": {"guard": "scope,miss:2,hit", "runner:1": "run", "runner:2": "run"}},
     "find": [{"p": "event", "ev": "shot_result", "result": "miss", "by": "seat", "count": 2},
              {"p": "event", "ev": "kill", "by": "seat", "cause": "shot", "count": 1, "anchor": True},
              {"p": "before", "a": {"ev": "shot_result", "result": "miss"}, "b": {"ev": "kill"}},
              {"p": "on_screen", "who": "victim", "min_h": 0.06, "for_s_before": 0.5, "for_s_after": 1.5}],
     "window": {"lead_s": 0.8, "tail_s": 1.0, "until": "ragdoll", "beat": None}, "overlays": [],
     "note": "pov of the sniper shooting at some runners and missing, hell map, right at the end, they hit one, and we cut a little after the animation plays out",
     "unmapped": [], "interpreted": "old=true because the short is about the OLD death animation; 'right at the end' = the kill is the last event, no spoken-word beat since the text ends before"},
    {"id": "L4b", "line": "L4", "source": "match",
     "match": {"map": "hell", "opening": "seat", "players": 4, "old": False, "same_match_as": "L4a"}, "seat": "runner:any",
     "film": {"seat": "runner:1", "map": "hell", "opening": "seat", "players": 4, "old": False, "intents": {"guard": "scope,miss:2,hit", "runner:1": "run", "runner:2": "run"}},
     "find": [{"p": "event", "ev": "kill", "victim": "other", "cause": "shot", "count": 1, "anchor": True},
              {"p": "on_screen", "who": "victim", "min_h": 0.12, "for_s_before": 1.0, "for_s_after": 1.2},
              {"p": "moving", "who": "victim", "min_mps": 1.0}, {"p": "moving", "who": "seat", "min_mps": 1.0}],
     "window": {"lead_s": 1.0, "tail_s": 1.2, "until": None, "beat": {"word": "Ragdolls", "event": "kill", "tol_s": 0.1}}, "overlays": [],
     "note": "runner pov near the end, he watches the person in front of him get shot", "unmapped": [],
     "interpreted": "the same match as the sniper shot, seen from a runner's eyes; the kill lands on the last word"},
], indent=0)


def _gemini_safe(node):
    """Gemini's schema subset: no type lists, no null in enums; the nullable fields come back as '' and are mapped."""
    node = copy.deepcopy(node)

    def walk(n):
        if isinstance(n, dict):
            if isinstance(n.get("type"), list):
                n["type"] = [t for t in n["type"] if t != "null"][0]
            if "enum" in n:
                n["enum"] = [e for e in n["enum"] if e is not None]
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)
    walk(node)
    return node


OPTIONAL_RE = re.compile(r"if we can|prefer|if possible|ideally|would be nice|bonus", re.I)
FIELDS = {"event": {"ev", "by", "victim", "body", "cause", "result", "outcome", "count", "anchor"},
          "no_event": {"ev", "by", "victim", "body", "cause", "result", "outcome"}, "before": {"a", "b"},
          "on_screen": {"who", "min_h", "for_s_before", "for_s_after"}, "moving": {"who", "min_mps", "max_mps", "for_s_before", "for_s_after"},
          "seat_state": {"state"}, "distinct": {"who"}, "scoped": {"value"}, "looking_at": {"landmark", "for_s", "for_s_before", "for_s_after"},
          "state": {"who", "state"}}


DROPPED = []


def normalise(shots):
    """moving(for_s) -> for_s_before (no meaning change); any other field a predicate has no use for FAILS the translation."""
    for s in shots:
        for p in s["find"]:
            if p["p"] == "moving" and "for_s" in p:
                p["for_s_before"] = p.pop("for_s")
            for k in [k for k in list(p) if k != "p" and k not in FIELDS.get(p["p"], set())]:
                DROPPED.append("%s %s(): field %s=%r is not a field of that predicate" % (s["id"], p["p"], k, p.pop(k)))
    return shots


def _nullify(shots):
    for s in shots:
        if s["match"].get("same_match_as") in ("", "null", "None"):
            s["match"]["same_match_as"] = None
        w = s["window"]
        if w.get("until") in ("", "null", "none", "None"):
            w["until"] = None
        b = w.get("beat")
        if isinstance(b, dict) and not b.get("word"):
            w["beat"] = None
        if s.get("camera") in ("", "null", "None"):
            s["camera"] = None
    return shots


def _client():
    from google import genai
    from google.genai import types
    if not os.environ.get("GEMINI_API_KEY"):
        raise SystemExit("GEMINI_API_KEY not set")
    return genai.Client(http_options=types.HttpOptions(timeout=600_000)), types


def _ask_json(client, types, prompt, json_schema):
    cfg = dict(response_mime_type="application/json", temperature=0.0)
    try:
        r = client.models.generate_content(model=MODEL, contents=prompt,
                                           config=types.GenerateContentConfig(response_json_schema=_gemini_safe(json_schema), **cfg))
    except Exception as e:  # schema subset rejected: ask without it, validate locally
        print("gemini schema rejected (%s); validating locally" % str(e)[:120], file=sys.stderr)
        r = client.models.generate_content(model=MODEL, contents=prompt, config=types.GenerateContentConfig(**cfg))
    return json.loads(r.text)


def film_check(s):
    f = s.get("film") or {}
    out = []
    for body, steps in (f.get("intents") or {}).items():
        pat = S.GUARD_STEP if body == "guard" else S.RUNNER_STEP
        for st in [x.strip() for x in steps.split(",") if x.strip()]:
            if not re.match(pat, st):
                out.append("%s film.intents[%s]: %r is not a step" % (s["id"], body, st))
    if s["source"] in ("match", "studio") and s["seat"] != "free" and f.get("seat") != s["seat"] and not (
            s["seat"] == "runner:any" and str(f.get("seat", "")).startswith("runner")):
        out.append("%s film.seat %r does not match seat %r" % (s["id"], f.get("seat"), s["seat"]))
    return out


def local_check(shots, spec):
    """What no model may get wrong: the schema, the note byte-for-byte, every line covered, same_take_as honoured."""
    jsonschema.validate(shots, S.SHOTS)
    problems = [x for s in shots for x in film_check(s)] + list(DROPPED)
    by_line = {}
    for s in shots:
        by_line.setdefault(s["line"], []).append(s)
    for e in spec:
        if e["id"] not in by_line:
            problems.append("line %s has no shot" % e["id"])
            continue
        for s in by_line[e["id"]]:
            if s["note"] != e["note"]:
                problems.append("%s note differs from the script: %r != %r" % (s["id"], s["note"], e["note"]))
            if e.get("same_take_as") and s["match"]["same_match_as"] not in (e["same_take_as"],) + tuple(
                    x["id"] for x in by_line.get(e["same_take_as"], [])):
                problems.append("%s: note says same shot as %s but same_match_as=%r" % (s["id"], e["same_take_as"], s["match"]["same_match_as"]))
            for u in s["unmapped"]:
                if u.get("optional") and not OPTIONAL_RE.search(e["note"]):
                    problems.append("%s: %r marked optional but the note never says 'if we can'/'preferably'" % (s["id"], u["phrase"]))
            if s["source"] == "match" and s["seat"] == "free":
                problems.append("%s: a match shot with a free camera (a pov is a player's eyes)" % s["id"])
    for s in shots:
        if s["line"] not in {e["id"] for e in spec}:
            problems.append("%s names a line that is not in the script" % s["id"])
    return problems


def unmapped_failures(shots):
    return [(s["id"], u["phrase"]) for s in shots for u in s["unmapped"] if not u.get("optional")]


def translate(spec, client, types):
    prompt = ("You translate a short's script into shots.json for a search over real match logs. EXTRACTION ONLY.\n\n"
              + S.PREDICATE_DOC + "\n\n" + RULES + "\n\nTwo worked examples (format only):\n" + EXAMPLES
              + "\n\nThe script (spec.json). Return a JSON array with one or more shots per line, in script order:\n"
              + json.dumps(spec, indent=1, ensure_ascii=False))
    shots = normalise(_nullify(_ask_json(client, types, prompt, S.SHOTS)))
    return shots


def audit(spec, shots, client, types):
    prompt = ("You audit a translation of Ryan's shot notes into predicates. For EACH shot list: `invented` = predicates or\n"
              "match/seat/window choices or film.intents steps the note (plus the whole script) does not ask for; `missing` =\n"
              "requirements in the note that film.intents does not script (every action the note describes must be a step of\n"
              "the body that does it) and that\n"
              "note that no field (match.map/old/opening, seat, source, camera, window.until/beat, overlays, montage,\n"
              "same_match_as), predicate or unmapped[] entry covers. A phrase in unmapped[] is NOT a defect even when a field\n"
              "also covers it; a field choice the note implies is NOT invented. on_screen() of the actors of the note's event\n"
              "(the victim of a kill the pov watches, the runners a sniper shoots at) is framing that makes the event visible,\n"
              "never invented; window lead_s/tail_s/until (e.g. until ragdoll so the body's fall is seen) are framing: NEVER list them as invented. moving() uses for_s_before/for_s_after (for_s_before\n"
              "defaults 1.0): read them literally before judging. moving(seat) in a runner pov is Ryan's rule 419 (a runner\n"
              "never sits there), never invented. Flag only real drops and real inventions. Return JSON: "
              "[{\"id\":..., \"invented\":[...], \"missing\":[...], \"ok\": true|false, \"why\": \"one line\"}].\n\n"
              + S.PREDICATE_DOC + "\n\n" + RULES + "\n\nSCRIPT:\n" + json.dumps(spec, indent=1, ensure_ascii=False)
              + "\n\nTRANSLATION:\n" + json.dumps(shots, indent=1, ensure_ascii=False))
    audit_schema = {"type": "array", "items": {"type": "object", "properties": {
        "id": {"type": "string"}, "invented": {"type": "array", "items": {"type": "string"}},
        "missing": {"type": "array", "items": {"type": "string"}}, "ok": {"type": "boolean"}, "why": {"type": "string"}},
        "required": ["id", "invented", "missing", "ok", "why"]}}
    return _ask_json(client, types, prompt, audit_schema)


def summary(shots):
    for s in shots:
        preds = ", ".join(p["p"] + "(" + ",".join("%s=%s" % (k, v) for k, v in p.items() if k != "p") + ")" for p in s["find"])
        extra = (" montage=%d" % s["montage"]) if s.get("montage") else ""
        print("%-4s %-12s seat=%-10s %s/%s old=%s same=%s%s\n     find: %s\n     window: %s" % (
            s["id"], s["source"], s["seat"], s["match"]["map"], s["match"]["opening"], s["match"]["old"],
            s["match"]["same_match_as"], extra, preds or "-", json.dumps(s["window"])))
        for u in s["unmapped"]:
            print("     UNMAPPED%s: %s" % (" (optional)" if u["optional"] else "", u["phrase"]))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--out", required=True)
    ap.add_argument("--fixture", help="offline: take this shots.json instead of calling Gemini (selftest)")
    a = ap.parse_args(argv)
    spec = json.load(open(a.spec, encoding="utf-8"))
    if a.fixture:
        shots = json.load(open(a.fixture, encoding="utf-8"))
        verdict = [{"id": s["id"], "invented": [], "missing": [], "ok": True, "why": "fixture"} for s in shots]
    else:
        client, types = _client()
        shots = translate(spec, client, types)
        problems = local_check(shots, spec)
        if problems:
            print("TRANSLATION FAILED LOCAL CHECK:\n  " + "\n  ".join(problems))
            json.dump(shots, open(a.out + ".rejected.json", "w"), indent=1)
            return 2
        verdict = audit(spec, shots, client, types)
    problems = local_check(shots, spec)
    json.dump(shots, open(a.out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    json.dump(verdict, open(os.path.splitext(a.out)[0] + ".audit.json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    summary(shots)
    bad = [v for v in verdict if not v["ok"] or v["invented"] or v["missing"]]
    if {v["id"] for v in verdict} != {s["id"] for s in shots} and not a.fixture:
        problems.append("audit answered for %s, shots are %s" % (sorted(v["id"] for v in verdict), sorted(s["id"] for s in shots)))
    um = unmapped_failures(shots)
    if problems or bad or um:
        print("\nTRANSLATION FAILED")
        for p in problems:
            print("  local: " + p)
        for i, ph in um:
            print("  %s unmapped: %s" % (i, ph))
        for v in bad:
            print("  audit %s: invented=%s missing=%s -- %s" % (v["id"], v["invented"], v["missing"], v["why"]))
            print("  translator said: %s" % json.dumps(next((s for s in shots if s["id"] == v["id"]), {})))
        return 2
    print("\nOK: %d shots, audit agrees" % len(shots))
    return 0


if __name__ == "__main__":
    sys.exit(main())
