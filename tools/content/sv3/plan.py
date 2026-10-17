"""Group shots into line groups (same map/opening/old/same_match_as): one scripted capture per group (§9: `run_clip --match
... --seat=<seat> --intent=<body>=<steps>;...` from film.intents), seeds (plan seed, +1); reuse only when a pool take already
satisfies the line's predicates; capture minutes; refuse > 25 min.

    python -m sv3.plan shots.json --pool DIR --out plan.json [--words words.json] [--seed 1000]
"""
import argparse
import json
import os
import sys
import tempfile

from sv3 import predicates as P
from sv3 import search as SE

TAKE_OVERHEAD = 9 + 10          # load + gate seconds per take
SECONDS = {"match": 45, "montage": 60, "studio": 8, "establishing": 10}
MAX_MINUTES = 25


def group_key(shot, shots_by_id):
    s = shot
    seen = set()
    while s["match"].get("same_match_as") and s["match"]["same_match_as"] in shots_by_id and s["id"] not in seen:
        seen.add(s["id"])
        s = shots_by_id[s["match"]["same_match_as"]]
    m = s["match"]
    linked = shot["match"].get("same_match_as") or any(x["match"].get("same_match_as") == s["id"] for x in shots_by_id.values())
    # lines share a match only when linked by same_match_as or when they script exactly the same bodies
    tag = s["id"] if linked else json.dumps((s.get("film") or {}).get("intents") or {}, sort_keys=True)
    return (s["source"], m["map"], m["opening"], bool(m["old"]), tag)


def intents_arg(group):
    """`--intent=<body>=<steps>;...` merged over the group's film.intents (one match, several seats share one script)."""
    first = (group[0].get("film") or {}).get("intents") or {}
    for s in group[1:]:
        if ((s.get("film") or {}).get("intents") or {}) != first:
            raise SystemExit("PLAN REFUSED: %s and %s share one match but script different bodies: %r vs %r (bodies not named keep their brain)" % (
                group[0]["id"], s["id"], first, (s.get("film") or {}).get("intents")))
    return ";".join("%s=%s" % (b, st) for b, st in first.items())



def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("shots")
    ap.add_argument("--pool", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--words")
    ap.add_argument("--seed", type=int, default=1000)
    ap.add_argument("--from-scratch", action="store_true", help="rule 417: never reuse the pool, film every line new")
    a = ap.parse_args(argv)
    shots = json.load(open(a.shots))
    words = json.load(open(a.words)) if a.words else {}
    by_id = {s["id"]: s for s in shots}
    # what the pool already answers
    tmp = os.path.join(tempfile.mkdtemp(), "edl.json")
    import contextlib, io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        SE.run({}, shots, a.pool, words, SE.DEFAULT_PAD, tmp)
    found = {} if a.from_scratch else {e["id"]: e for e in json.load(open(tmp))}
    groups = {}
    for s in shots:
        if s["source"] in ("card", "black"):
            continue
        groups.setdefault(group_key(s, by_id), []).append(s)
    matches, minutes, reuse_n, capture_n = [], 0.0, 0, 0
    for i, (key, group) in enumerate(groups.items()):
        source, map_, opening, old, _ = key
        film = group[0].get("film") or {}
        seats, kinds = [], {}
        for s in group:
            kind = (s.get("film") or {}).get("seat") or s["seat"]
            seat = kinds.get(kind, kind)
            if seat == "runner:any":        # capture needs a body: the lowest runner not already filmed in this match
                seat = next(x for x in ("runner:1", "runner:2", "runner:3") if x not in seats)
            kinds[kind] = seat
            if seat not in seats:
                seats.append(seat)
        reused = [s["id"] for s in group if s["id"] in found]
        tape = found[reused[0]]["tape"] if reused and len(reused) == len(group) else None
        montage = any(s.get("montage") for s in group)
        seconds = SECONDS["montage"] if montage else SECONDS.get(source, 45)
        if tape:
            reuse_n += len(group)
        else:
            capture_n += len(group)
            minutes += len(seats) * (TAKE_OVERHEAD + seconds) / 60.0
        matches.append({"id": "g%d" % (i + 1), "map": map_, "opening": opening, "players": film.get("players", max(s["match"]["players"] for s in group)),
                        "seed": a.seed + i, "seconds": seconds, "seats": seats, "old": old,
                        "kill": "runner:0@3.0" if source == "studio" else None,
                        "cam": (group[0].get("camera") or "orbit") if source == "establishing" else None,
                        "seat_intent": None, "intent": intents_arg(group) or None, "reuse": bool(tape), "reuse_tape": tape,
                        "lines": [s["id"] for s in group], "run_clip_args": None, "source": source})
    plan = {"matches": matches, "reuse_n": reuse_n, "capture_n": capture_n, "capture_minutes": round(minutes, 1)}
    json.dump(plan, open(a.out, "w"), indent=1)
    print("reuse %d / capture %d / %.1f minutes" % (reuse_n, capture_n, minutes))
    for m in matches:
        print("  %s %s %s/%s old=%s seed=%d %ds seats=%s lines=%s %s intent=%s" % (
            m["id"], m["source"], m["map"], m["opening"], m["old"], m["seed"], m["seconds"], m["seats"], m["lines"],
            ("reuse " + m["reuse_tape"]) if m["reuse"] else "capture", m["intent"]))
    if minutes > MAX_MINUTES:
        print("PLAN REFUSED: %.1f minutes of capture is over %d" % (minutes, MAX_MINUTES))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
