"""Group shots into matches (same map/opening/old/same_match_as), seats per match, seeds (plan seed, +1), reuse from the pool
when the search already succeeds, seat_intent steps when a predicate needs a seat action; capture minutes; refuse > 25 min.

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
    return (s["source"], m["map"], m["opening"], bool(m["old"]), s["id"] if shot["match"].get("same_match_as") or any(
        x["match"].get("same_match_as") == s["id"] for x in shots_by_id.values()) else "")


def seat_intent(shot):
    steps = []
    for p in shot["find"]:
        if p["p"] == "event" and p["ev"] == "shove" and p.get("by") == "seat":
            steps.append("shove_when_rival_within:3m")
        if p["p"] == "event" and p["ev"] == "portal" and p.get("by") in ("seat", None):
            steps.append("run")
        if p["p"] == "looking_at":
            steps.append("look:%s:%.0fs" % (p["landmark"], p.get("for_s", p.get("for_s_before", 1.0)) or 1))
    return steps


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
        seats = sorted({s["seat"] for s in group})
        reused = [s["id"] for s in group if s["id"] in found]
        tape = found[reused[0]]["tape"] if reused and len(reused) == len(group) else None
        montage = any(s.get("montage") for s in group)
        seconds = SECONDS["montage"] if montage else SECONDS.get(source, 45)
        takes = []
        if not tape:
            for j, seat in enumerate(seats):
                intent = sorted({st for s in group if s["seat"] == seat for st in seat_intent(s)})
                takes.append({"seat": seat, "seconds": seconds, "mode": "record" if j == 0 else "tape", "seat_intent": intent})
                minutes += (TAKE_OVERHEAD + seconds) / 60.0
            capture_n += len(group)
        else:
            reuse_n += len(group)
        matches.append({"group": "g%d" % (i + 1), "source": source, "map": map_, "opening": opening, "old": old,
                        "players": max(s["match"]["players"] for s in group), "seeds": [a.seed + i, a.seed + i + 1],
                        "seats": seats, "lines": [s["id"] for s in group], "reuse": tape, "takes": takes})
    plan = {"matches": matches, "reuse_n": reuse_n, "capture_n": capture_n, "capture_minutes": round(minutes, 1)}
    json.dump(plan, open(a.out, "w"), indent=1)
    print("reuse %d / capture %d / %.1f minutes" % (reuse_n, capture_n, minutes))
    for m in matches:
        print("  %s %s %s/%s old=%s seats=%s lines=%s %s" % (m["group"], m["source"], m["map"], m["opening"], m["old"], m["seats"], m["lines"],
                                                           ("reuse " + m["reuse"]) if m["reuse"] else "capture %d takes" % len(m["takes"])))
    if minutes > MAX_MINUTES:
        print("PLAN REFUSED: %.1f minutes of capture is over %d" % (minutes, MAX_MINUTES))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
