"""Find every shot's window in the pool: all `find` predicates must hold, the beat event lands on the beat word, and the
window is never shorter than the line's slot (voice + pad at speed 1). Exit 2 with the failed predicates and the closest miss.

    python -m sv3.search plan.json shots.json --pool DIR --words voice/words.json --out edl.json [--pad 0.25]

edl.json: [{id, line, tape, seat, file, in, len, beat_t, fit, parts:[...]}] one entry per shot; a montage has `parts`.
"""
import argparse
import json
import sys

from sv3 import predicates as P

DEFAULT_PAD = 0.25
MIN_LEAD = 0.3        # seconds of picture before the first required event, whatever the beat word asks
BEAT_LEN = 2.0        # a beat (no voice) shot's minimum length
FRAME = 1.0 / 60


def slot_of(shot, words, pad):
    """Seconds the cut will give this line at speed 1: voice + pad; a beat has none (its window decides)."""
    w = words.get(shot["line"])
    return (w["dur"] + pad) if w else 0.0


def word_time(shot, words, word):
    w = words.get(shot["line"])
    if not w:
        return None
    hits = [x for x in w["words"] if x["word"].strip(".,?!\"'").lower() == word.strip(".,?!\"'").lower()]
    if not hits:
        return None
    return hits[-1]["t"]   # the last utterance of the word; the beat word is normally the line's last word


def anchor_pred(shot):
    evs = [p for p in shot["find"] if p["p"] == "event"]
    beat = (shot.get("window") or {}).get("beat")
    for p in evs:
        if p.get("anchor"):
            return p
    if beat:
        for p in evs:
            if p["ev"] == beat["event"]:
                return p
    return evs[-1] if evs else None


def candidates(recs, shot, same_tape=None):
    m = shot["match"]
    out = []
    for r in recs:
        tk = r.take
        if shot["source"] == "match" and (tk.get("map") != m["map"] or tk.get("opening") != m["opening"]
                                          or bool(tk.get("old")) != bool(m["old"]) or tk.get("source", "match") != "match"):
            continue
        if shot["source"] in ("studio", "establishing") and (tk.get("source") != shot["source"] or tk.get("map") != m["map"]):
            continue
        if same_tape and r.tape != same_tape:
            continue
        seat = shot["seat"]
        if seat == "guard" and r.seat != "guard":
            continue
        if seat == "runner:any" and not r.seat.startswith("runner"):
            continue
        if seat == "free" and r.seat != "free":
            continue
        out.append(r)
    return out


def natural_window(rec, shot, ta, victim):
    """[ts, te] around anchor ta: the other required events (nearest before ta), lead_s before the first, tail_s after the
    last (or after the `until` event). Returns (ts, te, first_t) or None when a required event is missing."""
    w = shot["window"]
    anchor = anchor_pred(shot)
    first, last = ta, ta
    for p in shot["find"]:
        if p["p"] != "event" or p is anchor:
            continue
        occ = rec.occurrences(p, victim, ta - P.MAXSPAN, ta)
        need = p.get("count", 1)
        if len(occ) < need:
            occ = rec.occurrences(p, victim, ta - P.MAXSPAN, ta + P.MAXSPAN)
            if len(occ) < need:
                return None
            chosen = occ[:need]
        else:
            chosen = occ[-need:]
        first = min(first, chosen[0]["t"])
        last = max(last, chosen[-1]["t"])
    end = last
    if w.get("until"):
        u = rec.occurrences({"ev": w["until"], "body": "victim"} if victim else {"ev": w["until"]}, victim, last, last + 8.0)
        if not u:
            u = rec.occurrences({"ev": w["until"]}, victim, last, last + 8.0)
        if u:
            end = u[0]["t"]
    return first - w.get("lead_s", 0.8), end + w.get("tail_s", 1.0), first


def score(rec, shot, ts, te, ta, victim, results):
    s = 0.0
    hs = [b.get("h", 0) for smp in rec.samples(ts, te) for b in smp.get("bodies", []) if victim and b["id"] == victim and b.get("on")]
    s += min(1.0, (max(hs) if hs else 0) * 4)                      # a victim that reads on screen
    s += min(1.0, (ta - max(ts, 0.0)) / max(0.1, shot["window"].get("lead_s", 0.8)))   # lead-in actually available
    v = rec.speed("victim", victim, ta - 1.0, ta) if victim else None
    s += min(1.0, (v or 0) / 3.0)                                       # motion into the event
    return round(s, 3)


def try_anchor(rec, shot, ta, victim, slot, words, pad, prev_len=0.0):
    """One candidate window. Returns dict(ok, in, len, beat_t, fit, why[], score) with ok False and why on a miss."""
    w = shot["window"]
    nat = natural_window(rec, shot, ta, victim)
    if nat is None:
        return {"ok": False, "why": ["a required event is missing within %.0f s of the anchor at %.1f s" % (P.MAXSPAN, ta)], "score": -1}
    ts, te, first = nat
    beat = w.get("beat")
    why = []
    if beat:
        tw = word_time(shot, words, beat["word"])
        if tw is None:
            return {"ok": False, "why": ["beat word %r not in voice/words.json for %s" % (beat["word"], shot["line"])], "score": -1}
        tin = ta - (tw - prev_len)
        if tin < 0:
            why.append("beat: word %r at %.2f s needs %.2f s of lead the recording lacks before the %s at %.1f s" % (beat["word"], tw, tw - prev_len, beat["event"], ta))
        if first - tin < MIN_LEAD:
            why.append("beat: word %r at %.2f s leaves %.2f s before the first event (need %.1f)" % (beat["word"], tw, first - tin, MIN_LEAD))
        ts = min(ts, tin) if tin >= 0 else ts
        tin = max(0.0, tin)
    else:
        tin = max(0.0, ts)
        if first - tin < min(MIN_LEAD, w.get("lead_s", MIN_LEAD)):
            why.append("lead: first event at %.1f s, only %.2f s of picture before it" % (first, first - tin))
    natural = te - tin
    need = slot - prev_len if slot else BEAT_LEN
    length = max(natural, need)
    fit = "wait" if natural > need + FRAME else "line"
    if tin + length > rec.dur + FRAME:
        why.append("recording ends at %.1f s: window %.1f..%.1f" % (rec.dur, tin, tin + length))
    results = P.evaluate(rec, shot["find"], tin, tin + length, ta, victim)
    why += [t for ok, t in results if not ok]
    sc = score(rec, shot, tin, tin + length, ta, victim, results) if not why else sum(1 for ok, _ in results if ok) - len(results) - 1
    return {"ok": not why, "in": round(tin, 3), "len": round(length, 3), "beat_t": round(ta - tin, 3), "fit": fit,
            "why": why, "score": sc, "anchor_t": ta, "victim": victim, "passed": sum(1 for ok, _ in results if ok),
            "total": len(results)}


def search_shot(recs, shot, words, pad, same_tape=None, prev_len=0.0, exclude_victims=()):
    """Best window for one shot over the candidate recordings; (hit|None, misses[])."""
    slot = slot_of(shot, words, pad)
    cands = candidates(recs, shot, same_tape)
    misses = []
    if not cands:
        return None, [{"why": ["no recording in the pool for %s %s/%s old=%s seat=%s%s" % (
            shot["source"], shot["match"]["map"], shot["match"]["opening"], shot["match"]["old"], shot["seat"],
            (" in tape " + same_tape) if same_tape else "")], "score": -99}]
    anchor = anchor_pred(shot)
    best = None
    for rec in cands:
        if anchor is None:
            tin = 0.5
            length = max(slot or BEAT_LEN, (shot["window"].get("lead_s", 0) + shot["window"].get("tail_s", 0)) or 0)
            if tin + length > rec.dur:
                misses.append({"tape": rec.tape, "seat": rec.seat, "why": ["recording %.1f s is shorter than the slot %.1f s" % (rec.dur, length)], "score": -1})
                continue
            results = P.evaluate(rec, shot["find"], tin, tin + length, tin + length / 2, None)
            why = [t for ok, t in results if not ok]
            r = {"ok": not why, "in": tin, "len": round(length, 3), "beat_t": None, "fit": "line", "why": why, "score": 0.5 if not why else -1}
            r.update(tape=rec.tape, seat=rec.seat, file=rec.file)
            if why:
                misses.append(r)
            elif best is None or r["score"] > best["score"]:
                best = r
            continue
        for occ in rec.occurrences(anchor, None, 0, 1e9):
            victim = P.victim_of(occ)
            if victim in exclude_victims:
                continue
            r = try_anchor(rec, shot, occ["t"], victim, slot, words, pad, prev_len)
            r.update(tape=rec.tape, seat=rec.seat, file=rec.file)
            if r["ok"]:
                if best is None or r["score"] > best["score"]:
                    best = r
            else:
                misses.append(r)
        if not rec.occurrences(anchor, None, 0, 1e9):
            misses.append({"tape": rec.tape, "seat": rec.seat, "score": -50, "why": ["no %s in the recording" % P._evs(anchor)]})
    return best, misses


def search_montage(recs, shot, words, pad):
    n = shot["montage"]
    slot = slot_of(shot, words, pad)
    part = max(1.0, slot / n)
    hits, misses, used = [], [], set()
    for _ in range(n):
        hit, miss = search_shot(recs, shot, words, pad, exclude_victims=used)
        misses += miss
        if not hit:
            break
        # a montage part is `part` seconds with the anchor at 55 %: re-check the predicates in that exact window
        rec = next(r for r in recs if r.tape == hit["tape"] and r.seat == hit["seat"])
        tin = max(0.0, hit["anchor_t"] - 0.55 * part)
        if tin + part > rec.dur:
            misses.append({"tape": rec.tape, "seat": rec.seat, "score": -1, "why": ["montage part runs past the recording end"]})
            used.add(hit["victim"])
            continue
        why = [t for ok, t in P.evaluate(rec, shot["find"], tin, tin + part, hit["anchor_t"], hit["victim"]) if not ok]
        if why:
            misses.append({"tape": rec.tape, "seat": rec.seat, "score": -1, "why": why})
        else:
            hits.append({"tape": rec.tape, "seat": rec.seat, "file": rec.file, "in": round(tin, 3), "len": round(part, 3),
                         "beat_t": round(hit["anchor_t"] - tin, 3), "victim": hit["victim"]})
        used.add(hit["victim"])
    if len(hits) < n:
        return None, misses + [{"score": -2, "why": ["montage: %d of %d clips with distinct victims" % (len(hits), n)]}]
    return hits, misses


def report_miss(shot, misses):
    best = max(misses, key=lambda m: m.get("score", -99)) if misses else {"why": ["no candidates"]}
    print("FAILED %s (line %s) note: %s" % (shot["id"], shot["line"], shot["note"]))
    print("  failed predicates / constraints (closest miss%s):" % (
        " in %s/%s at %.1f s" % (best["tape"], best["seat"], best["anchor_t"]) if best.get("tape") and best.get("anchor_t") is not None
        else (" in %s/%s" % (best["tape"], best["seat"]) if best.get("tape") else "")))
    for w in best["why"]:
        print("    - " + w)
    print("  %d candidate windows tried" % len(misses))


def run(plan, shots, pool, words, pad, out):
    recs = P.load_pool(pool)
    edl, failed = [], []
    chosen_tape = {}
    for shot in shots:
        if shot["source"] in ("card", "black"):
            edl.append({"id": shot["id"], "line": shot["line"], "tape": None, "seat": None, "file": None, "in": 0, "len": slot_of(shot, words, pad) or 1.0, "beat_t": None, "fit": "line"})
            continue
        same = shot["match"].get("same_match_as")
        same_tape = chosen_tape.get(same) if same else None
        if same and not same_tape:
            failed.append(shot["id"])
            print("FAILED %s: same_match_as %s, which found no tape" % (shot["id"], same))
            continue
        prev_len = sum(e["len"] for e in edl if e["line"] == shot["line"])
        beat = shot["window"].get("beat")
        if beat and prev_len:
            tw = word_time(shot, words, beat["word"])
            room = (tw - shot["window"].get("lead_s", 0.8)) if tw is not None else None
            if room is not None and prev_len > room:
                last = [e for e in edl if e["line"] == shot["line"]][-1]
                new_len = round(last["len"] - (prev_len - room), 3)
                if new_len < 1.0:
                    failed.append(shot["id"])
                    print("FAILED %s: the parts before it take %.2f s but the beat word %r is at %.2f s" % (shot["id"], prev_len, beat["word"], tw))
                    continue
                print("trim %s to %.2f s so %s's beat word %r lands" % (last["id"], new_len, shot["id"], beat["word"]))
                last["len"] = new_len
                prev_len = sum(e["len"] for e in edl if e["line"] == shot["line"])
        if shot.get("montage"):
            hits, misses = search_montage(recs, shot, words, pad)
            if hits:
                edl.append({"id": shot["id"], "line": shot["line"], "tape": hits[0]["tape"], "seat": hits[0]["seat"], "file": hits[0]["file"],
                            "in": hits[0]["in"], "len": round(sum(h["len"] for h in hits), 3), "beat_t": None, "fit": "line", "parts": hits})
                chosen_tape[shot["id"]] = hits[0]["tape"]
                continue
        else:
            hit, misses = search_shot(recs, shot, words, pad, same_tape, prev_len)
            if hit:
                edl.append({k: hit[k] for k in ("tape", "seat", "file", "in", "len", "beat_t", "fit")} | {"id": shot["id"], "line": shot["line"], "anchor_t": hit.get("anchor_t"), "victim": hit.get("victim")})
                chosen_tape[shot["id"]] = hit["tape"]
                print("found %s in %s/%s @%.2f len %.2f (%s)" % (shot["id"], hit["tape"], hit["seat"], hit["in"], hit["len"], hit["fit"]))
                continue
        failed.append(shot["id"])
        report_miss(shot, misses)
    json.dump(edl, open(out, "w"), indent=1)
    if failed:
        print("SEARCH FAILED: %s" % ", ".join(failed))
        return 2
    print("edl: %d entries -> %s" % (len(edl), out))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("plan")
    ap.add_argument("shots")
    ap.add_argument("--pool", required=True)
    ap.add_argument("--words", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pad", type=float, default=DEFAULT_PAD)
    a = ap.parse_args(argv)
    plan = json.load(open(a.plan)) if a.plan != "-" else {}
    shots = json.load(open(a.shots))
    words = json.load(open(a.words))
    return run(plan, shots, a.pool, words, a.pad, a.out)


if __name__ == "__main__":
    sys.exit(main())
