"""Fabricate a plausible tape pool (design §1 events.jsonl / vis.jsonl / take.json) for tests: a hell match with two misses
then a kill, shoves (ring, into the sights, the finale tower_out), a brawl opening, forest kills, a race, a grey-room death,
a hell idle bust, an establishing move.   python -m sv3.mocklogs <pool dir>
"""
import json
import os
import sys

HZ = 10


def _w(path, rows):
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


class Match:
    def __init__(self, pool, tape, map_, opening, seed, players, old=False, source="match", dur=45.0):
        self.dir = os.path.join(pool, tape)
        os.makedirs(self.dir, exist_ok=True)
        self.tape, self.map, self.opening, self.seed, self.players, self.old, self.source, self.dur = tape, map_, opening, seed, players, old, source, dur
        self.events = []
        self.bodies = ["guard"] + ["runner:%d" % i for i in range(1, players)] if source == "match" else ["runner:0"]
        self.dead = {}        # body -> t of death
        self.cover = {}       # body -> (t0, t1)
        self.shoved = {}      # body -> t
        self.seats = []
        self.look = {}        # seat -> [(t0, t1, landmark)]
        self.idle = set()     # bodies that stand still

    def ev(self, t, ev, **kw):
        self.events.append({"t": round(t, 2), "ev": ev, **kw})

    def kill(self, t, by, victim, cause="shot"):
        if cause == "shot":
            self.ev(t - 0.05, "shot", by=by)
            self.ev(t - 0.03, "shot_result", by=by, result="hit", victim=victim, part="chest")
        self.ev(t, "kill", by=by, victim=victim, cause=cause)
        self.ev(t + 0.05, "ragdoll", body=victim)
        self.ev(t + 0.1, "out", body=victim, cause=cause)
        self.dead[victim] = t

    def miss(self, t, by="guard"):
        self.ev(t, "shot", by=by)
        self.ev(t + 0.02, "shot_result", by=by, result="miss")

    def shove(self, t, by, victim, outcome):
        self.ev(t, "shove", by=by, victim=victim, outcome=outcome)
        self.ev(t + 0.05, "ragdoll", body=victim)
        self.shoved[victim] = t
        if outcome == "pit":
            self.ev(t + 0.6, "kill", by=by, victim=victim, cause="shove_pit")
            self.ev(t + 0.7, "out", body=victim, cause="shove_pit")
            self.dead[victim] = t + 0.6

    def pos(self, body, t):
        """World position: runners lap along +x at 3 m/s from staggered starts, the guard sits in the tower, the dead stop."""
        if body == "guard":
            return [0.0, 12.0, 0.0]
        k = int(body.split(":")[1])
        if body in self.idle:
            return [4.0, 0.0, 2.0]
        tt = min(t, self.dead.get(body, 1e9))
        c = self.cover.get(body)
        if c and c[0] <= tt <= c[1]:
            tt = c[0]
        elif c and tt > c[1]:
            tt -= (c[1] - c[0])
        return [round(3.0 * tt + 4.0 * k, 2), 0.0, round(2.0 * k, 2)]

    def state(self, body, t):
        if body in self.dead and t >= self.dead[body]:
            return "ragdoll" if t < self.dead[body] + 1.5 else "dead"
        if body in self.shoved and self.shoved[body] <= t < self.shoved[body] + 0.8:
            return "shoved"
        c = self.cover.get(body)
        if c and c[0] <= t <= c[1]:
            return "cover"
        if self.opening == "brawl" and t < 6.0:
            return "brawl"
        return "run"

    def write_seat(self, seat, landmarks=None):
        fs = seat.replace(":", "_")
        self.seats.append(seat)
        vis = []
        for i in range(int(self.dur * HZ)):
            t = i / HZ
            cam = self.pos(seat, t) if seat != "free" else [10.0, 3.0, -6.0]
            if seat == "free":
                cam = [10.0, 3.0, -6.0]
            bodies = []
            for b in self.bodies:
                if b == seat:
                    continue
                p = self.pos(b, t)
                d = max(1.0, abs(p[0] - cam[0]) + abs(p[2] - cam[2]) * 0.5 + (10.0 if seat == "guard" else 0.0))
                if seat == "guard":
                    on, h = True, round(min(0.3, 1.6 / d), 3)
                elif seat == "free":
                    on, h = True, 0.55
                else:
                    ahead = p[0] >= cam[0] - 0.5
                    on, h = ahead and d < 14, round(min(0.5, 1.7 / d), 3)
                st = self.state(b, t)
                if st == "dead" and t > self.dead.get(b, 1e9) + 3.0:
                    on = False
                bodies.append({"id": b, "on": on, "h": h if on else 0.0, "x": 0.5, "y": 0.5, "d": round(d, 1), "occ": False, "state": st, "pos": p})
            lm = {}
            for name in ("tower", "portal", "lava", "cover"):
                lm[name] = {"on": False, "x": 0.5, "y": 0.4, "d": 20.0}
            for t0, t1, name in self.look.get(seat, []):
                if t0 <= t <= t1:
                    lm[name]["on"] = True
            vis.append({"t": round(t, 1), "cam": seat, "yaw": 90.0, "pitch": -5.0, "scoped": seat == "guard" and t >= 2.0,
                        "cam_pos": cam, "bodies": bodies, "landmarks": lm})
        evs = sorted(self.events, key=lambda e: e["t"])
        if seat == "guard":
            evs = [{"t": 2.0, "ev": "scoped", "by": "guard", "on": True}] + evs
        _w(os.path.join(self.dir, fs + ".events.jsonl"), evs)
        _w(os.path.join(self.dir, fs + ".vis.jsonl"), vis)

    def finish(self):
        take = {"map": self.map, "opening": self.opening, "seed": self.seed, "players": self.players, "old": self.old,
                "source": self.source, "duration": self.dur, "sync_t0": 9.0, "commit": "mock", "tape": self.tape,
                "files": {s: "_tapes/%s/%s.mkv" % (self.tape, s.replace(":", "_")) for s in self.seats}}
        json.dump(take, open(os.path.join(self.dir, "take.json"), "w"), indent=1)


def build(pool):
    os.makedirs(pool, exist_ok=True)
    # 1. hell, seat opening, 4 players: ring shoves early, two misses then a kill, a cover shove into the sights, the finale
    for seed, old in ((1000, False), (1001, True)):
        m = Match(pool, "hell_seat_%d" % seed, "hell", "seat", seed, 4, old=old)
        m.ev(0.0, "round_start", n=1)
        m.ev(0.1, "seat", body="guard", turn=1)
        m.shove(4.0, "runner:1", "runner:2", "ring")
        m.shove(8.0, "runner:3", "runner:1", "ring")
        m.miss(6.0)
        m.miss(9.0)
        m.kill(12.0, "guard", "runner:2")
        m.cover["runner:3"] = (17.5, 20.0)
        m.shove(20.0, "runner:1", "runner:3", "sights")
        m.kill(21.0, "guard", "runner:3")
        m.ev(30.0, "portal", body="runner:1")
        m.ev(30.5, "finale_start", shover="runner:1", guard="guard")
        m.ev(31.0, "shove", by="runner:1", victim="guard", outcome="tower_out")
        m.ev(31.05, "ragdoll", body="guard")
        m.ev(31.6, "kill", by="runner:1", victim="guard", cause="shove_pit")
        m.ev(31.7, "out", body="guard", cause="shove_pit")
        m.ev(36.0, "finale_end")
        m.ev(36.1, "seat", body="runner:1", turn=2)
        m.look["runner:1"] = [(2.5, 6.5, "tower"), (6.5, 30.0, "lava"), (28.0, 30.5, "portal"), (17.0, 20.5, "cover")]
        m.look["runner:2"] = [(0.0, 12.0, "lava")]
        for s in ("guard", "runner:1", "runner:2", "runner:3"):
            m.write_seat(s)
        m.finish()
    # 2. hell brawl opening
    m = Match(pool, "hell_brawl_1000", "hell", "brawl", 1000, 4)
    m.ev(0.0, "round_start", n=1)
    m.ev(1.0, "brawl_start", bodies=["runner:1", "runner:2", "runner:3", "guard"])
    m.shove(2.0, "runner:1", "runner:2", "ring")
    m.shove(3.5, "runner:1", "runner:2", "tower_out")
    m.ev(3.6, "brawl_out", body="runner:2", by="runner:1")
    m.shove(5.0, "runner:3", "guard", "tower_out")
    m.ev(5.1, "brawl_out", body="guard", by="runner:3")
    m.shove(6.5, "runner:1", "runner:3", "tower_out")
    m.ev(6.6, "brawl_out", body="runner:3", by="runner:1")
    m.ev(6.7, "brawl_won", body="runner:1")
    m.ev(7.0, "seat", body="runner:1", turn=1)
    m.miss(14.0, by="runner:1")
    m.kill(18.0, "runner:1", "runner:2")
    for s in ("runner:1", "runner:2", "guard"):
        m.write_seat(s)
    m.finish()
    # 3. forest, seat opening: three distinct kills for a montage
    m = Match(pool, "forest_seat_1000", "forest", "seat", 1000, 4)
    m.ev(0.0, "round_start", n=1)
    m.miss(6.0)
    m.kill(8.0, "guard", "runner:1")
    m.miss(14.0)
    m.kill(16.0, "guard", "runner:2")
    m.miss(23.0)
    m.kill(25.0, "guard", "runner:3")
    m.look["runner:3"] = [(0.0, 25.0, "tower")]
    for s in ("guard", "runner:3", "runner:1"):
        m.write_seat(s)
    m.finish()
    # 4. forest race opening
    m = Match(pool, "forest_race_1000", "forest", "race", 1000, 4)
    m.ev(0.0, "round_start", n=1)
    m.ev(1.0, "race_start")
    m.ev(30.0, "race_won", body="runner:2")
    m.ev(30.5, "seat", body="runner:2", turn=1)
    m.look["runner:1"] = [(0.0, 45.0, "lava")]
    for s in ("runner:1", "guard"):
        m.write_seat(s)
    m.finish()
    # 5. grey studio death (old death clip) and a hell idle bust
    m = Match(pool, "grey_studio_1000", "grey", "seat", 1000, 1, old=True, source="studio", dur=12.0)
    m.kill(3.0, "guard", "runner:0")
    m.write_seat("free")
    m.finish()
    m = Match(pool, "hell_studio_1000", "hell", "seat", 1000, 1, source="studio", dur=12.0)
    m.idle.add("runner:0")
    m.write_seat("free")
    m.finish()
    # 6. establishing move over hell (no bodies)
    m = Match(pool, "hell_establishing_1000", "hell", "seat", 1000, 0, old=True, source="establishing", dur=12.0)
    m.bodies = []
    m.write_seat("free")
    m.finish()
    return pool


if __name__ == "__main__":
    print(build(sys.argv[1]))
