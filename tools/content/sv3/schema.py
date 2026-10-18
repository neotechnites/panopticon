"""shots.json contract (CONTRACT.md): per voice line a choosable stage BY NAME, pov, catalogued dials, beat, or needs_stage.
validate() turns any shot naming an unknown stage/pov/entry/dial/tick/word into needs_stage with why."""
import re

POVS = ("guard", "runner")
TICKS = ("hit", "shove", "out", "go")
CARD = {"text": "beta signup in bio", "seconds": 1.0}

_N = {"type": ["string", "null"]}
_BEAT = {"type": ["object", "null"], "properties": {"tick": {"enum": list(TICKS)}, "word": {"type": "string"}},
         "required": ["tick", "word"], "additionalProperties": False}
_DIALS = {"type": "object", "additionalProperties": {"type": ["string", "number", "boolean", "null"]}}

SHOT = {"type": "object", "additionalProperties": False,
        "required": ["id", "line", "text", "note", "stage", "pov", "dials", "approved", "same_take_as", "beat", "card",
                     "needs_stage", "why"],
        "properties": {
            "id": {"type": "string"}, "line": {"type": "integer"}, "text": {"type": "string"}, "note": {"type": "string"},
            "stage": _N, "pov": {"enum": list(POVS) + [None]}, "dials": _DIALS,
            "approved": {"type": ["object", "null"], "required": ["project", "entry"], "additionalProperties": False,
                         "properties": {"project": {"type": "string"}, "entry": {"type": "integer"}}},
            "same_take_as": _N, "beat": _BEAT,
            "card": {"type": ["object", "null"], "required": ["text", "seconds"], "additionalProperties": False,
                     "properties": {"text": {"type": "string"}, "seconds": {"type": "number"}}},
            "needs_stage": {"type": "boolean"}, "why": _N}}
SHOTS = {"type": "array", "items": SHOT}

# What the model answers per line; everything else is copied from spec.json or derived.
PICK = {"type": "array", "items": {"type": "object", "additionalProperties": False,
        "required": ["id", "stage", "pov", "entry", "dials", "same_take_as", "beat", "needs_stage", "why"],
        "properties": {"id": {"type": "string"}, "stage": _N, "pov": {"enum": list(POVS) + [None]},
                       "entry": {"type": ["integer", "null"]}, "dials": _DIALS, "same_take_as": _N, "beat": _BEAT,
                       "needs_stage": {"type": "boolean"}, "why": _N}}}


def choosable(stages):
    """name -> stage a short may pick: for_shorts, with approved entries that carry expect: clauses (the smoke gate needs them)."""
    out = {}
    for k, v in (stages.get("stages") or {}).items():
        smoked = [e for e in (v.get("approved") or []) if e.get("expect")]
        if v.get("for_shorts") and smoked:
            out[k] = dict(v, approved=smoked)
    return out


def tokens(text):
    return [t for t in (re.sub(r"[^\w']", "", w).strip("'") for w in text.split()) if t]


def capture_arg(capture, name):
    m = re.search(r"--%s=(\S+)" % re.escape(name), capture or "")
    return m.group(1) if m else None


def entry_of(stage, approved):
    return next((e for e in stage["approved"] if approved and e["project"] == approved.get("project")
                 and e["entry"] == approved.get("entry")), None)


def _why_not(s, stages, by_id):
    """None when the shot is exactly the contract against the catalogue; else the reason in one line."""
    st = choosable(stages).get(s["stage"] or "")
    if st is None:
        return "stage %r is not a choosable stage of the catalogue" % s["stage"]
    if s["pov"] not in st["povs"]:
        return "pov %r is not one of %s's povs %s" % (s["pov"], s["stage"], st["povs"])
    e = entry_of(st, s["approved"])
    if e is None:
        return "approved %r is not an approved entry of %s" % (s["approved"], s["stage"])
    ep = capture_arg(e["capture"], "pov")
    if ep and ep != s["pov"]:
        return "approved entry %s %d was filmed --pov=%s, not %s" % (e["project"], e["entry"], ep, s["pov"])
    bad = sorted(set(s["dials"]) - set(st["dials"]))
    if bad:
        return "dials %s are not dials of %s (%s)" % (bad, s["stage"], sorted(st["dials"]))
    ticks = {k: v for k, v in (e.get("ticks") or {}).items() if v is not None}
    if not s["text"].strip():   # a voiceless line: no word for the event to land on, the cut plays the entry
        s["beat"] = None
    b = s["beat"]
    if not b and ticks and s["text"].strip():   # a voiceless line has no word for the event to land on
        return "beat missing: %s %d has ticks %s; the line needs the word the event lands on" % (e["project"], e["entry"], sorted(ticks))
    if b:
        if b["tick"] not in TICKS or (e.get("ticks") or {}).get(b["tick"]) is None:
            return "tick %r has no approved time in %s %d" % (b["tick"], e["project"], e["entry"])
        hit = [t for t in tokens(s["text"]) if t.lower() == re.sub(r"[^\w']", "", b["word"]).strip("'").lower()]
        if not hit:
            return "beat word %r is not a word of the line %r" % (b["word"], s["text"])
        b["word"] = hit[0]
    if not s["same_take_as"] and e.get("tape"):   # one tape, N seats: the same tape as an earlier shot IS the same take
        for t in by_id.values():
            te = entry_of(choosable(stages).get(t["stage"] or "") or {"approved": []}, t["approved"]) if not t["needs_stage"] else None
            if te and te.get("tape") == e.get("tape") and t["stage"] == s["stage"] and t["dials"] == s["dials"]:
                s["same_take_as"] = t["same_take_as"] or t["id"]
                break
    if s["same_take_as"]:
        t = by_id.get(s["same_take_as"])
        if t is None:
            return "same_take_as %r is not an earlier shot" % s["same_take_as"]
        if t["needs_stage"]:
            return "same_take_as %s, which needs a stage" % t["id"]
        if t["stage"] != s["stage"] or t["dials"] != s["dials"]:
            return "same_take_as %s but %s/%s dials differ from %s/%s" % (t["id"], s["stage"], s["dials"], t["stage"], t["dials"])
    return None


def needs(s, why):
    """Mark a shot needs_stage: nothing filmable stays on it, the attempted pick goes into why."""
    tried = " (picked %s --pov=%s)" % (s["stage"], s["pov"]) if s.get("stage") else ""
    s.update(stage=None, pov=None, dials={}, approved=None, beat=None, needs_stage=True, why=why + tried)
    return s


def validate(shots, stages):
    """Every shot in order against the catalogue; a shot that breaks the contract becomes needs_stage with why."""
    by_id = {}
    for s in shots:
        if not s["needs_stage"]:
            why = _why_not(s, stages, by_id)
            if why:
                needs(s, why)
        else:
            needs(s, s.get("why") or "no catalogued stage films this note")
        by_id[s["id"]] = s
    return shots
