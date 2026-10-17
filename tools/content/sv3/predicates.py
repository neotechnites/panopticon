"""Pool recordings (events.jsonl + vis.jsonl per seat, design §1) and the evaluation of the closed predicate set over a window."""
import json
import math
import os

MAXSPAN = 20.0     # seconds around the anchor the other required events may lie
VIS_FRAC = 0.8     # fraction of vis samples that must satisfy on_screen / looking_at over their span


class Recording:
    def __init__(self, pool, tape, seat):
        self.pool, self.tape, self.seat = pool, tape, seat
        d = os.path.join(pool, tape)
        fs = seat.replace(":", "_")
        tj = os.path.join(d, fs + ".take.json")          # capture.py pulls the recorder's take.json as <seat>.take.json
        self.take = json.load(open(tj if os.path.exists(tj) else os.path.join(d, "take.json")))
        self.events = _jsonl(os.path.join(d, fs + ".events.jsonl"))
        self.vis = _jsonl(os.path.join(d, fs + ".vis.jsonl"))
        self.file = (self.take.get("files") or {}).get(seat) or (self.take.get("files") or {}).get(fs) \
            or "_tapes/%s/%s.mkv" % (tape, fs)
        self.dur = float(self.take.get("duration") or (self.vis[-1]["t"] if self.vis else 0.0))

    def occurrences(self, match, victim=None, lo=-1e9, hi=1e9):
        return [e for e in self.events if lo <= e["t"] <= hi and self.matches(e, match, victim)]

    def matches(self, e, m, victim):
        if e["ev"] != m["ev"]:
            return False
        for k in ("cause", "result", "outcome"):
            if m.get(k) is not None and e.get(k) != m[k]:
                return False
        for role in ("by", "victim", "body"):
            if m.get(role) is not None:
                actor = e.get(role)
                if actor is None:
                    actor = e.get("body") or e.get("shover")   # ragdoll/out/portal name the body, finale_start the shover
                if actor is None or not self.is_role(actor, m[role], victim):
                    return False
        return True

    def is_role(self, actor, role, victim):
        if role == "any":
            return True
        if role == "seat":
            return actor == self.seat
        if role == "other":
            return actor != self.seat
        if role == "guard":
            return actor == "guard"
        if role == "runner:any":
            return actor.startswith("runner")
        if role == "victim":
            return victim is not None and actor == victim
        return actor == role

    def body_id(self, role, victim):
        if role == "seat":
            return self.seat
        if role == "victim":
            return victim
        if role == "guard":
            return "guard"
        return None   # other / runner:any: resolved per sample

    def samples(self, lo, hi):
        return [v for v in self.vis if lo <= v["t"] <= hi]

    def body_in(self, sample, role, victim):
        bid = self.body_id(role, victim)
        pick = None
        for b in sample.get("bodies", []):
            if bid is not None and b["id"] == bid:
                return b
            if bid is None and ((role == "other" and b["id"] != self.seat) or (role == "runner:any" and b["id"].startswith("runner"))):
                if b.get("on") and (pick is None or b.get("h", 0) > pick.get("h", 0)):
                    pick = b          # the body that reads best on screen
                pick = pick or b
        return pick

    def speed(self, who, victim, lo, hi):
        """Metres per second of `who` over [lo, hi] from vis `pos` (bodies) / `cam_pos` (the seat); None when the log lacks them."""
        pts = []
        for s in self.samples(lo, hi):
            if who == "seat":
                p = s.get("cam_pos")
            else:
                b = self.body_in(s, who, victim)
                p = b.get("pos") if b else None
            if p is not None:
                pts.append((s["t"], p))
        if len(pts) < 2:
            return None
        dist = sum(math.dist(pts[i][1], pts[i - 1][1]) for i in range(1, len(pts)))
        return dist / max(1e-6, pts[-1][0] - pts[0][0])


def _jsonl(path):
    if not os.path.exists(path):
        return []
    return [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]


def load_pool(pool):
    """Every seat recording in the pool: `<pool>/<map>_<opening>_<seed>/<seat>.events.jsonl` (+ vis, take.json)."""
    recs = []
    if not os.path.isdir(pool):
        return recs
    for tape in sorted(os.listdir(pool)):
        d = os.path.join(pool, tape)
        if "trailer" in tape or not (os.path.isfile(os.path.join(d, "take.json"))
                                     or any(f.endswith(".take.json") for f in os.listdir(d))):
            continue      # rule 370: trailer footage never reaches a short
        for f in sorted(os.listdir(d)):
            if f.endswith(".events.jsonl"):
                recs.append(Recording(pool, tape, f[:-len(".events.jsonl")].replace("_", ":")))
    return recs


def victim_of(e):
    return e.get("victim") or e.get("body")


# ---- predicate evaluation: each returns (ok, why) for a window [ts, te] around anchor ta with the bound victim ----

def ev_event(rec, p, ts, te, ta, victim):
    n = len(rec.occurrences(p, victim, ts, te))
    need = p.get("count", 1)
    return n >= need, "%s x%d in window, need %d" % (_evs(p), n, need)


def ev_no_event(rec, p, ts, te, ta, victim):
    n = len(rec.occurrences(p, victim, ts, te))
    return n == 0, "%s occurs %d times, must be 0" % (_evs(p), n)


def ev_before(rec, p, ts, te, ta, victim):
    a = rec.occurrences(p["a"], victim, ts, te)
    b = rec.occurrences(p["b"], victim, ts, te)
    ok = any(x["t"] < y["t"] for x in a for y in b)
    return ok, "before(%s, %s): %d a, %d b" % (_evs(p["a"]), _evs(p["b"]), len(a), len(b))


def ev_on_screen(rec, p, ts, te, ta, victim):
    lo, hi = ta - p.get("for_s_before", 0.0), ta + p.get("for_s_after", 0.0)
    if hi - lo < 0.3:
        lo, hi = ta - 0.5, ta + 0.5      # "on screen at the anchor"
    smp = rec.samples(max(lo, ts), min(hi, te))
    if not smp:
        return False, "on_screen(%s): no vis samples in %.1f..%.1f" % (p["who"], lo, hi)
    good = 0
    hs = []
    for s in smp:
        b = rec.body_in(s, p["who"], victim)
        if b and b.get("on") and b.get("h", 0) >= p.get("min_h", 0):
            good += 1
            hs.append(b["h"])
    frac = good / len(smp)
    return frac >= VIS_FRAC, "on_screen(%s, h>=%.2f): %.0f%% of %.1f s, max h %.2f" % (
        p["who"], p.get("min_h", 0), frac * 100, hi - lo, max(hs) if hs else 0)


def ev_moving(rec, p, ts, te, ta, victim):
    lo, hi = ta - p.get("for_s_before", 1.0), ta + p.get("for_s_after", 0.0)
    if hi - lo < 0.3:
        lo, hi = ta - 0.5, ta + 0.5      # "moving at the anchor"
    v = rec.speed(p["who"], victim, max(ts, lo), min(te, hi))
    if v is None:
        return False, "moving(%s): vis has no pos/cam_pos for it (recorder must log them)" % p["who"]
    ok = v >= p.get("min_mps", 0) and (p.get("max_mps") is None or v <= p["max_mps"])
    return ok, "moving(%s): %.2f m/s over %.1f..%.1f, need >= %.2f%s" % (
        p["who"], v, lo, hi, p.get("min_mps", 0), (" <= %.2f" % p["max_mps"]) if p.get("max_mps") is not None else "")


def ev_seat_state(rec, p, ts, te, ta, victim):
    dead = rec.occurrences({"ev": "kill", "victim": "seat"}, victim, -1e9, te) + rec.occurrences({"ev": "out", "body": "seat"}, victim, -1e9, te)
    want = p.get("state", "alive")
    if want == "alive":
        return not dead, "seat_state(alive): %d deaths before window end" % len(dead)
    return bool(dead), "seat_state(%s): %d deaths before window end" % (want, len(dead))


def ev_distinct(rec, p, ts, te, ta, victim):
    return True, "distinct: enforced across montage clips"


def ev_scoped(rec, p, ts, te, ta, victim):
    smp = rec.samples(ta - 0.15, ta + 0.15)
    if smp:
        got = bool(smp[0].get("scoped"))
    else:
        prior = [e for e in rec.events if e["ev"] == "scoped" and e["t"] <= ta]
        got = bool(prior[-1].get("on")) if prior else False
    return got == p.get("value", True), "scoped=%s at anchor, want %s" % (got, p.get("value", True))


def ev_looking_at(rec, p, ts, te, ta, victim):
    before, after = p.get("for_s", p.get("for_s_before", 1.0)), p.get("for_s_after", 0.0)
    smp = rec.samples(max(ts, ta - before), min(te, ta + after))
    if not smp:
        return False, "looking_at(%s): no vis samples" % p["landmark"]
    good = sum(1 for s in smp if (s.get("landmarks") or {}).get(p["landmark"], {}).get("on"))
    frac = good / len(smp)
    return frac >= VIS_FRAC, "looking_at(%s): on for %.0f%% of %.1f s" % (p["landmark"], frac * 100, before + after)


def ev_state(rec, p, ts, te, ta, victim):
    for s in rec.samples(max(ts, ta - 2.0), ta):
        b = rec.body_in(s, p["who"], victim)
        if b and b.get("state") == p["state"]:
            return True, "state(%s, %s) seen before anchor" % (p["who"], p["state"])
    return False, "state(%s, %s): never seen in the 2 s before the anchor" % (p["who"], p["state"])


EVAL = {"event": ev_event, "no_event": ev_no_event, "before": ev_before, "on_screen": ev_on_screen, "moving": ev_moving,
        "seat_state": ev_seat_state, "distinct": ev_distinct, "scoped": ev_scoped, "looking_at": ev_looking_at, "state": ev_state}


def _evs(m):
    return m["ev"] + "".join("[%s=%s]" % (k, v) for k, v in m.items() if k not in ("ev", "p", "count", "anchor") and v is not None)


def evaluate(rec, find, ts, te, ta, victim):
    """[(ok, text)] for every predicate of `find` over the window."""
    return [EVAL[p["p"]](rec, p, ts, te, ta, victim) for p in find]
