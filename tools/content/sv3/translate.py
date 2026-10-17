"""spec.json + stages.json -> shots.json: Claude (sv3.llm) picks per line a choosable stage by name, pov, dials, beat; then audits
each pick against its note. Any needs_stage -> exit 2 listing ids + notes.  --fixture: offline, no model call."""
import argparse
import json
import os
import sys

import jsonschema

from sv3 import llm
from sv3 import schema as S

RULES = """Rules (Ryan's, binding). You CHOOSE; you never invent how a take is made.
- One pick per script line, `id` = the line's id, in script order.
- `stage` is a stage NAME from CHOOSABLE exactly; `entry` is the number of one of that stage's approved entries; `pov` is
  guard or runner and must be the --pov of that entry's capture line. Pick only when that entry's said:/capture: shows what
  the note asks for: the map, the pov, and every action. A pov is a player's eyes ("sniper" = guard, "runner" = runner).
- If no approved entry films the note: needs_stage true, stage/pov/entry/beat null, dials {}, `why` = which part of the note
  no entry has. Never pick a near miss.
- `dials`: {} unless the note needs a dial moved; only that stage's dial names; never a dial the catalogue does not list.
- `same_take_as`: the earlier line's id when this line is another view or the continuation of the SAME take (same stage,
  same dials); "same shot" means the same take. Else null.
- `beat`: REQUIRED {tick, word} whenever the chosen entry has a non-null tick (hit, shove, out, go); never null then: `word` is one word
  copied from the line's text, the one the note ties the event to, else the word it reads best on (default the last word).
  null when the entry has no tick for the note's event.
- `why`: null on a pick; one line on needs_stage."""

AUDIT = """You audit stage picks for a short. For EACH picked shot answer one question: is the chosen stage's approved entry
(its map, pov, said:, capture:) WHAT the note says? Judge what is seen, never how it is made: seeds, dials, durations, ticks,
bot counts, window lengths and lens details are how, never a defect. ok=false only when the entry shows a different map, a
different pov, or is missing an action the note asks for (name it in `why`). Return JSON [{"id":..., "ok": bool, "why": "one line"}]."""

AUDIT_SCHEMA = {"type": "array", "items": {"type": "object", "additionalProperties": False, "required": ["id", "ok", "why"],
                "properties": {"id": {"type": "string"}, "ok": {"type": "boolean"}, "why": {"type": "string"}}}}


def lines_of(spec):
    return spec["lines"] if isinstance(spec, dict) else spec


def catalogue(stages):
    """The choosable stages as the model sees them: map, povs, dial names, each approved entry with its own map and pov."""
    out = {}
    for name, st in S.choosable(stages).items():
        out[name] = {"shot": st["shot"], "povs": st["povs"], "dials": sorted(st["dials"]), "approved": [
            {"entry": e["entry"], "project": e["project"], "map": S.capture_arg(e["capture"], "map") or st["map"],
             "pov": S.capture_arg(e["capture"], "pov"), "said": e["said"], "capture": e["capture"],
             "ticks": {k: v for k, v in (e.get("ticks") or {}).items() if v is not None}} for e in st["approved"]]}
    return out


def pick(spec, stages, only=None):
    rest = sorted(set(stages.get("stages", {})) - set(S.choosable(stages))) + list(stages.get("uncatalogued") or [])
    prompt = ("You pick, per line of a short's script, the approved staged take that films its note.\n\n" + RULES
              + "\n\nCHOOSABLE:\n" + json.dumps(catalogue(stages), indent=1, ensure_ascii=False)
              + "\n\nNOT CHOOSABLE (never pick): " + (", ".join(rest) or "-")
              + "\n\nTHE SCRIPT (spec.json). Return the JSON array of picks:\n"
              + json.dumps([l for l in lines_of(spec) if not only or l["id"] in only], indent=1, ensure_ascii=False)
              + ("\n\nEVERY pick above MUST carry beat {tick, word}: the entry has ticks." if only else ""))
    return llm.ask_json(prompt, S.PICK, model="opus")


def assemble(spec, picks, stages):
    """Shots in script order: text/note/line/same_take_as from spec.json verbatim, the rest from the model's pick."""
    by_id = {p["id"]: p for p in picks}
    shots = []
    for i, e in enumerate(lines_of(spec), 1):
        p = by_id.get(e["id"]) or {"needs_stage": True, "why": "the model gave no pick for this line"}
        st = S.choosable(stages).get(p.get("stage") or "") or {"approved": []}
        ent = next((a for a in st["approved"] if a["entry"] == p.get("entry")), None)
        shots.append({"id": e["id"], "line": i, "text": e["text"], "note": e["note"], "stage": p.get("stage"),
                      "pov": p.get("pov"), "dials": p.get("dials") or {},
                      "approved": {"project": ent["project"], "entry": ent["entry"]} if ent else (
                          {"project": "?", "entry": p["entry"]} if p.get("entry") is not None else None),
                      "same_take_as": e.get("same_take_as") or p.get("same_take_as"), "beat": p.get("beat"),
                      "card": None, "needs_stage": bool(p.get("needs_stage")), "why": p.get("why")})
    if shots:
        shots[-1]["card"] = dict(S.CARD)
    return shots


def audit(shots, stages):
    """Second pass: is each picked stage what its note says (what, not how). A no becomes needs_stage."""
    picked = [s for s in shots if not s["needs_stage"]]
    if not picked:
        return []
    cat = catalogue(stages)
    rows = [{"id": s["id"], "note": s["note"], "text": s["text"], "stage": s["stage"], "pov": s["pov"],
             "entry": next(e for e in cat[s["stage"]]["approved"] if e["entry"] == s["approved"]["entry"])} for s in picked]
    verdict = llm.ask_json(AUDIT + "\n\nPICKS:\n" + json.dumps(rows, indent=1, ensure_ascii=False), AUDIT_SCHEMA, model="opus")
    v = {x["id"]: x for x in verdict}
    for s in picked:
        x = v.get(s["id"])
        if x is None or not x["ok"]:
            S.needs(s, "audit: " + (x["why"] if x else "the audit gave no verdict"))
    return verdict


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--stages", default=os.path.join(os.path.dirname(__file__), "stages.json"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--fixture", help="offline: take this shots.json instead of calling the model")
    a = ap.parse_args(argv)
    spec = json.load(open(a.spec, encoding="utf-8"))
    stages = json.load(open(a.stages, encoding="utf-8"))
    if a.fixture:
        shots, verdict = S.validate(json.load(open(a.fixture, encoding="utf-8")), stages), []
    else:
        shots = S.validate(assemble(spec, pick(spec, stages), stages), stages)
        retry = [s for s in shots if s["needs_stage"] and (s.get("why") or "").startswith("beat missing")]
        if retry:   # the model dropped the beat word: ask once more for those lines only, nothing else changes
            again = pick(spec, stages, only=[s["id"] for s in retry])
            for s in retry:
                p = next((x for x in again if x["id"] == s["id"]), None)
                if p and p.get("beat"):
                    s.update(stage=p.get("stage"), pov=p.get("pov"), dials=p.get("dials") or {}, beat=p["beat"], needs_stage=False, why=None)
                    st = S.choosable(stages).get(s["stage"] or "") or {"approved": []}
                    ent = next((a for a in st["approved"] if a["entry"] == p.get("entry")), None)
                    s["approved"] = {"project": ent["project"], "entry": ent["entry"]} if ent else None
            S.validate(shots, stages)
        verdict = audit(shots, stages)
        S.validate(shots, stages)                 # an audit no cascades to every same_take_as of it
    jsonschema.validate(shots, S.SHOTS)
    json.dump(shots, open(a.out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    json.dump(verdict, open(os.path.splitext(a.out)[0] + ".audit.json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    for s in shots:
        print("%-4s %s" % (s["id"], "NEEDS STAGE: " + s["why"] if s["needs_stage"] else "%s --pov=%s entry %s:%d%s beat %s%s" % (
            s["stage"], s["pov"], s["approved"]["project"], s["approved"]["entry"],
            (" dials " + json.dumps(s["dials"])) if s["dials"] else "", json.dumps(s["beat"]),
            (" same take as " + s["same_take_as"]) if s["same_take_as"] else "")))
    needs = [s for s in shots if s["needs_stage"]]
    if needs:
        print("\nNEEDS STAGE (nothing improvised):")
        for s in needs:
            print("  %s: %s" % (s["id"], s["note"]))
        return 2
    print("\nOK: %d shots, every one a catalogued stage" % len(shots))
    return 0


if __name__ == "__main__":
    sys.exit(main())
