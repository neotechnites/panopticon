"""content plan <spec.md>: spec.json -> shots.json (LLM, schema-gated) -> inventory match -> plan.json, with gates G1 and G2.
Exit 0 = plan written and both gates pass; 3 = shots.json needs the translation (prompt written); 1 = a gate failed."""
import argparse, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spec as specmod  # noqa: E402
import inventory as inv  # noqa: E402
import match as matchmod  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA_DIR = os.path.join(HERE, "schema")
ASPECT = {"short": [1080, 1920], "devlog": [1920, 1080], "trailer": [1920, 1080]}
ACTION = {"game": "capture", "editor": "editor", "online": "fetch", "card": "card", "black": "black", "reuse": "reuse"}
MAP_ALIASES = {"bentham_ring": ("hell", "bentham", "lava", "pit", "tower"), "forest": ("forest",), "marble": ("marble",),
               "ice": ("ice", "snow"), "beach": ("beach",)}
POV_ALIASES = {"guard": ("sniper", "scope", "guard", "tower"), "runner": ("runner", "prisoner", "duck", "shover", "shoved")}


def schema(name):
    return json.load(open(os.path.join(SCHEMA_DIR, name + ".json")))


def validate(obj, name):
    import jsonschema
    v = jsonschema.Draft202012Validator(schema(name))
    return ["%s: %s" % ("/".join(str(p) for p in e.absolute_path) or name, e.message) for e in v.iter_errors(obj)]


def stage_names():
    d = os.path.join(REPO, "tools", "capture", "stages")
    return sorted(f[:-3] for f in os.listdir(d) if f.endswith(".gd") and f not in ("stage.gd", "lib.gd"))


def map_ids():
    txt = open(os.path.join(REPO, "maps", "map_catalog.tres")).read()
    return re.findall(r'path="res://maps/(\w+)/\1\.tres"', txt)

# ---------------------------------------------------------------- translation

def translate_prompt(sp):
    readme = open(os.path.join(REPO, "tools", "capture", "stages", "README.md")).read()
    row_schema = json.dumps(schema("shots")["properties"]["rows"]["items"], indent=1)
    lines = "\n".join('%s TEXT: "%s" NOTE: {%s}' % (l["id"], l["text"], l["note"]) for l in sp["lines"])
    return f"""Translate this script into shots.json for PANOPTICON's content pipeline. Output ONLY JSON: {{"name": "{sp['name']}", "spec_sha1": "{sp['src_sha1']}", "rows": [...]}}
One row per line below, same order, `line` = the id. Copy `text` and `note` VERBATIM (code overwrites them with Ryan's words anyway).
source: game (filmed in the game) | editor (Godot editor) | online (footage of another game or video) | card (title or comment card only) | black | reuse (note says reuse a named clip or "same as before").
game: {{map: one of {map_ids()} (hell = bentham_ring), pov: guard (sniper/tower/scope) | runner (prisoner on the ground, first person) | free | orbit | spectator | other,
       hud: "crosshair" for guard POV else "off", stage: an existing plugin {stage_names()} or a new snake_case name, set, bots, ref: "main" or a commit the note names (e.g. "ed473b24~1"); a note set in an earlier era ("greybox", "early", "as it was 9/11") needs ref "era:<words>", never "main"; humans: "on"}}
overlays: comment_card / text / image / letterbox named in the note, with in/out as line_start | line_end | word:<word>.
beats: an event the note ties to a word ("the hit lands on X") -> {{word, event: hit|shove|death|...}}.
continuity: "same_take_as:<id>" when the note says same shot / same instance / continues.
flags: copy refilm, look_override, freeze_waive, keep_audio, letterbox only if the note says so.
interpreted: for EVERY field you chose that the note does not literally say (map, pov, stage, bots, ...), one entry {{field, why}} in one line.
Row schema:
{row_schema}

Stage vocabulary (tools/capture/stages/README.md):
{readme}

Script ({sp['name']}, kind {sp['header'].get('kind')}):
{lines}
"""


def translate_gemini(sp, model="gemini-2.5-pro", review=None):
    from google.genai import types
    client = inv._client()
    prompt = translate_prompt(sp)
    if review: prompt += "\n\nA reviewer found these rows unfaithful to their notes last time; fix them:\n" + "\n".join(review)
    errs = []
    for attempt in range(2):
        p = prompt if not errs else prompt + "\n\nYour last output failed validation:\n" + "\n".join(errs[:20])
        r = client.models.generate_content(model=model, contents=[p], config=types.GenerateContentConfig(
            response_mime_type="application/json", temperature=0))
        shots = json.loads(r.text)
        if isinstance(shots, list): shots = {"name": sp["name"], "rows": shots}
        shots["spec_sha1"] = sp["src_sha1"]
        by_id = {l["id"]: l for l in sp["lines"]}
        for row in shots.get("rows", []):  # Ryan's words are copied by code, never by the model
            if row.get("line") in by_id: row["text"], row["note"] = by_id[row["line"]]["text"], by_id[row["line"]]["note"]
        errs = validate(shots, "shots") + g1_problems(sp, shots)
        if not errs: break
    shots["translated_by"] = model
    return shots

# ---------------------------------------------------------------- gates

def _named(word_lists, note):
    n = note.lower()
    return any(w in n for w in word_lists)


def g1_problems(sp, shots):
    probs = []
    rows = {r.get("line"): r for r in shots.get("rows", [])}
    for l in sp["lines"]:
        r = rows.get(l["id"])
        if r is None: probs.append("%s: no shots.json row" % l["id"]); continue
        if r.get("text", "") != l["text"]: probs.append("%s: text rewritten" % l["id"])
        if r.get("note", "") != l["note"]: probs.append("%s: note rewritten" % l["id"])
        listed = set()
        for i in r.get("interpreted", []):
            f = i.get("field", "")
            listed |= {f.split(".")[-1], f}
            if f in ("game", "source"): listed |= {"map", "pov", "stage"}
        g = r.get("game") or {}
        if r.get("source") == "game":
            if g.get("map") and not _named(MAP_ALIASES.get(g["map"], (g["map"],)) + (g["map"],), l["note"]) and "map" not in listed:
                probs.append("%s: game.map %s guessed but not listed in interpreted" % (l["id"], g["map"]))
            if g.get("pov") and not _named(POV_ALIASES.get(g["pov"], (g["pov"],)), l["note"]) and "pov" not in listed:
                probs.append("%s: game.pov %s guessed but not listed in interpreted" % (l["id"], g["pov"]))
            if g.get("stage") and g["stage"] not in l["note"] and "stage" not in listed:
                probs.append("%s: game.stage %s guessed but not listed in interpreted" % (l["id"], g["stage"]))
    extra = set(rows) - {l["id"] for l in sp["lines"]}
    if extra: probs.append("rows with no spec line: %s" % ", ".join(sorted(map(str, extra))))
    return probs


def gate_g1(sp, shots):
    probs = list(sp.get("warnings_fatal", []))
    if not sp["lines"]: probs.append("spec has no L/M lines")
    probs += validate(sp, "spec")
    if shots is None: probs.append("shots.json missing")
    else: probs += validate(shots, "shots") + g1_problems(sp, shots)
    return {"pass": not probs, "reason": "spec parses, %d rows valid, interpreted fields listed" % len(sp["lines"]) if not probs
            else "; ".join(probs[:6]) + (" (+%d more)" % (len(probs) - 6) if len(probs) > 6 else ""), "problems": probs}


G1B_MODEL = "gemini-2.5-flash"


def gate_g1b(sp, shots, cache_path=None):
    """Every interpreted row is checked against Ryan's note by Gemini Flash (text only); any unfaithful row fails the plan."""
    from google.genai import types
    cache = json.load(open(cache_path)) if cache_path and os.path.isfile(cache_path) else {}
    client, probs, n = None, [], 0
    keys = ("source", "game", "editor", "online", "card", "overlays", "beats", "continuity", "flags")
    for r in shots["rows"]:
        if not r.get("interpreted"): continue
        body = json.dumps({k: r.get(k) for k in keys}, sort_keys=True)
        h = hashlib.sha1((r["note"] + body).encode()).hexdigest()
        if h not in cache:
            client = client or inv._client()
            prompt = ("A video editor wrote this SHOT NOTE for one line of a game video (PANOPTICON: low-poly first-person; guard = the sniper in "
                      "the tower, runner = a prisoner on the ground (a shover, shoved victim or duck is a runner); maps: bentham_ring = hell, forest, marble, ice, beach). A tool turned it into the "
                      "structured PLAN ROW below. The note itself travels with the row verbatim, so the action and staging detail stay in the note and "
                      "need no field. Judge ONLY the structured fields: is any of source, map, POV, build/ref, overlays/cards (with their in/out words), "
                      "beats (event on a word), continuity (same shot/instance as another line) or flags WRONG for the note, or is one of those that "
                      "the note clearly asks for MISSING? 'beats' means only an event that must land on a specific spoken word ('the hit lands "
                      "on X'); 'hold a beat' or a pause is not one. Stage names are free labels, a comment card belongs in overlays, and a note "
                      "that cuts within one line needs no extra field. Fail only a CLEAR contradiction or a clearly missing element; when in "
                      "doubt, faithful is true.\nSHOT NOTE: %s\nPLAN ROW: %s\n"
                      'JSON: {"faithful": true|false, "why": one sentence}' % (r["note"], body))
            try:
                resp = client.models.generate_content(model=G1B_MODEL, contents=[prompt], config=types.GenerateContentConfig(
                    response_mime_type="application/json", temperature=0, thinking_config=types.ThinkingConfig(thinking_budget=1024)))
                j = json.loads(resp.text); j = j[0] if isinstance(j, list) else j
                cache[h] = {"faithful": bool(j.get("faithful")), "why": str(j.get("why", ""))[:300]}
            except Exception as e:
                probs.append("%s: G1b check failed to run: %s" % (r["line"], str(e)[:100])); continue
        n += 1
        if not cache[h]["faithful"]: probs.append("%s: %s" % (r["line"], cache[h]["why"]))
    if cache_path: json.dump(cache, open(cache_path, "w"), indent=1)
    return {"pass": not probs, "reason": "%d interpreted rows match their notes" % n if not probs else "; ".join(probs[:6]), "problems": probs}


def gate_g2(plan, cutoff_date=None):
    """No capture where rule 1 or 2 hit (unless Ryan's note says refilm); every reused clip and capture ref within cutoff."""
    probs = []
    for l in plan["lines"]:
        m = l.get("match") or {}
        rule = "rule 1" if m.get("explicit") else "rule 2" if m.get("capture_key") else "footage search" if m.get("description") else None
        hit = m.get("explicit") or m.get("capture_key") or m.get("description")
        if l["action"] in ("capture", "editor", "fetch") and hit and "refilm" not in l.get("flags", []):
            probs.append("%s: scheduled %s but %s found %s" % (l["id"], l["action"], rule, hit["path"]))
        if cutoff_date and l.get("reuse") and (l["reuse"].get("date") or "") > cutoff_date:
            probs.append("%s: reused clip dated %s is past cutoff %s" % (l["id"], l["reuse"]["date"], cutoff_date))
        if cutoff_date and l["action"] == "capture":
            ref = ((l.get("game") or {}).get("ref") or "main")
            d = matchmod.commit_date(REPO, ref if ref != "main" else "origin/main")
            if d and d > cutoff_date: probs.append("%s: capture ref %s (%s) is past cutoff %s" % (l["id"], ref, d, cutoff_date))
    c = plan.get("counts", {})
    summary = " / ".join("%s %d" % (k, v) for k, v in sorted(c.items()))
    return {"pass": not probs, "reason": summary if not probs else "; ".join(probs[:6]), "problems": probs}

# ---------------------------------------------------------------- plan

def resolve_cutoff(cutoff):
    if not cutoff: return None
    if re.match(r"^\d{4}-\d{2}-\d{2}", cutoff): return cutoff[:16]
    d = matchmod.commit_date(REPO, cutoff)
    if not d: raise SystemExit("plan: cutoff %r is neither a date nor a commit" % cutoff)
    return d


def build_plan(sp, shots, db_path=inv.DB_PATH, confirm=True):
    h = sp["header"]
    kind = h.get("kind", "short")
    aspect = ASPECT[kind]
    cutoff_date = resolve_cutoff(h.get("cutoff"))
    rows = {r["line"]: r for r in shots["rows"]}
    maps = sorted({(r.get("game") or {}).get("map") or "bentham_ring" for r in shots["rows"]})
    m = matchmod.Matcher(db_path, project=sp["name"], base=h.get("base"), aspect=tuple(aspect), cutoff_date=cutoff_date,
                         fresh_dates=matchmod.fresh_dates(REPO, maps), confirm=confirm, repo=REPO)
    lines, counts = [], {}
    for sl in sp["lines"]:
        r = dict(rows[sl["id"]])
        r["flags"] = sorted(set(r.get("flags", [])) | set(sl.get("flags", [])))
        src = r["source"]
        line = {"id": sl["id"], "text": sl["text"], "note": sl["note"], "source": src, "action": ACTION[src], "reuse": None,
                "candidates": [], "game": r.get("game"), "editor": r.get("editor"), "online": r.get("online"), "card": r.get("card"),
                "overlays": r.get("overlays", []), "beats": r.get("beats", []), "continuity": r.get("continuity"),
                "min_seconds": r.get("min_seconds", "voice"), "flags": r["flags"], "interpreted": r.get("interpreted", []),
                "match": {"explicit": None, "capture_key": None, "description": None}}
        cont = (r.get("continuity") or "").replace("same_take_as:", "")
        prev = next((x for x in lines if x["id"] == cont), None)
        if prev is not None:
            for k in ("action", "reuse", "game", "editor", "online", "match"):
                line[k] = prev[k]
            line["match"] = dict(prev["match"], continuity=cont)
        elif src not in ("card", "black"):
            res = m.match(r, sl)
            line["match"] = {k: res[k] for k in ("explicit", "capture_key", "description")}
            line["match"]["verdict"] = res["verdict"]
            line["candidates"] = res["candidates"]
            hit = res["explicit"] or res["capture_key"] or res["description"]
            if hit and "refilm" not in r["flags"]:
                line["action"], line["source"] = "reuse", "reuse"
                row = m.best_row(hit["sha1"])
                line["reuse"] = dict(hit, date=row["date"] if row else None)
            elif src == "reuse":
                line["action"] = "capture"; line["match"]["verdict"] = "refilm"
        counts[line["action"]] = counts.get(line["action"], 0) + 1
        lines.append(line)
    plan = {"name": sp["name"], "kind": kind, "aspect": aspect, "fps": 60, "cutoff": h.get("cutoff"), "base": h.get("base"),
            "captions": h.get("captions", "pop"), "music": h.get("music"), "counts": counts, "lines": lines,
            "spec_sha1": sp["src_sha1"], "cutoff_date": cutoff_date}
    return plan, cutoff_date


def record(plan_path, published=False, version=None, db_path=inv.DB_PATH):
    """After a cut is rendered: every reused or new clip window counts as one use (feeds the variety penalty)."""
    plan = json.load(open(plan_path))
    c = inv.db(db_path)
    v = version or plan.get("tag") or "v?"
    n = 0
    for l in plan["lines"]:
        ru = l.get("reuse")
        if not ru: continue
        inv.record_usage(c, ru.get("sha1"), ru["path"], plan["name"], v, l["id"], ru.get("in"), ru.get("len"), published, "plan")
        c.execute("insert or ignore into lines values(?,?,?,?,?,?,?,?,?)",
                  (plan["name"], v, l["id"], l["text"], ru["path"], ru.get("in"), ru.get("len"), ru.get("sha1"), "plan"))
        n += 1
    c.commit()
    print("record: %d clip uses for %s %s%s" % (n, plan["name"], v, " (published)" if published else ""))


def run(spec_path, out_dir=None, llm="session", db_path=inv.DB_PATH, confirm=True):
    sp = specmod.parse(spec_path)
    out_dir = out_dir or os.path.join(os.path.dirname(os.path.abspath(spec_path)), sp["name"])
    os.makedirs(out_dir, exist_ok=True)
    json.dump(sp, open(os.path.join(out_dir, "spec.json"), "w"), indent=1, ensure_ascii=False)
    for w in sp["warnings"]: print("spec: " + w)
    shots_p = os.path.join(out_dir, "shots.json")
    shots = json.load(open(shots_p)) if os.path.isfile(shots_p) else None
    if shots is not None and shots.get("spec_sha1") != sp["src_sha1"]:
        print("plan: spec changed since shots.json; re-translating"); shots = None
    if shots is None:
        if llm == "gemini":
            shots = translate_gemini(sp)
            json.dump(shots, open(shots_p, "w"), indent=1, ensure_ascii=False)
        else:
            pp = os.path.join(out_dir, "shots.prompt.md")
            open(pp, "w").write(translate_prompt(sp))
            print("plan: write %s from %s (schema cp/schema/shots.json), then rerun" % (shots_p, pp))
            return 3
    g1 = gate_g1(sp, shots)
    print("G1 %s: %s" % ("PASS" if g1["pass"] else "FAIL", g1["reason"]))
    if not g1["pass"]:
        json.dump({"gates": {"G1": g1}}, open(os.path.join(out_dir, "plan.gates.json"), "w"), indent=1)
        return 1
    g1b = gate_g1b(sp, shots, os.path.join(out_dir, "g1b.cache.json"))
    if not g1b["pass"] and llm == "gemini":
        print("G1b FAIL: %s; re-translating once" % g1b["reason"])
        shots = translate_gemini(sp, review=g1b["problems"])
        json.dump(shots, open(shots_p, "w"), indent=1, ensure_ascii=False)
        g1 = gate_g1(sp, shots)
        g1b = gate_g1b(sp, shots, os.path.join(out_dir, "g1b.cache.json")) if g1["pass"] else {"pass": False, "reason": g1["reason"]}
    print("G1b %s: %s" % ("PASS" if g1b["pass"] else "FAIL", g1b["reason"]))
    if not g1b["pass"]:
        json.dump({"gates": {"G1": g1, "G1b": g1b}}, open(os.path.join(out_dir, "plan.gates.json"), "w"), indent=1)
        return 1
    plan, cutoff_date = build_plan(sp, shots, db_path, confirm)
    g2 = gate_g2(plan, cutoff_date)
    plan["gates"] = {"G1": {"pass": True, "reason": g1["reason"]}, "G1b": {"pass": True, "reason": g1b["reason"]},
                     "G2": {"pass": g2["pass"], "reason": g2["reason"]}}
    errs = validate(plan, "plan")
    if errs: print("plan: schema: " + "; ".join(errs[:5])); return 1
    json.dump(plan, open(os.path.join(out_dir, "plan.json"), "w"), indent=1, ensure_ascii=False)
    for l in plan["lines"]:
        ru = l.get("reuse")
        tail = ("%s [%s %.2f] %s" % (os.path.basename(ru["path"].replace("\\", "/")), ru["rule"], ru["score"], ru.get("from_project") or "")) if ru \
            else (l["match"].get("verdict") or "")
        print("  %-5s %-8s %s" % (l["id"], l["action"], tail))
    print("G2 %s: %s" % ("PASS" if g2["pass"] else "FAIL", g2["reason"]))
    print("plan: %s" % os.path.join(out_dir, "plan.json"))
    return 0 if g2["pass"] else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="content plan")
    ap.add_argument("spec"); ap.add_argument("--out"); ap.add_argument("--llm", choices=["session", "gemini"], default="session")
    ap.add_argument("--db", default=inv.DB_PATH); ap.add_argument("--no-confirm", action="store_true")
    ap.add_argument("--record", action="store_true", help="spec is a plan.json: record its clip uses")
    ap.add_argument("--published", action="store_true"); ap.add_argument("--version")
    a = ap.parse_args(argv)
    if a.record: return record(a.spec, a.published, a.version, a.db) or 0
    return run(a.spec, a.out, a.llm, a.db, not a.no_confirm)


if __name__ == "__main__":
    sys.exit(main())
