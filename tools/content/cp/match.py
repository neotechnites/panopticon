"""Match each shot row against inventory.sqlite: explicit, capture key, then description (embedding + Gemini Flash yes/no).
Candidates are ranked by fit minus a variety penalty for clips other cuts already used; a line needs new footage only when nothing fits."""
import difflib, hashlib, json, math, os, re, subprocess, sqlite3

try:
    from . import inventory as inv
except ImportError:
    import inventory as inv

FIT_MIN = 0.65          # rule 3 floor on gemini-embedding-001 query/document cosine (its scale tops out near 0.75)
TOP_K = 8               # candidates confirmed with Gemini, best score first
PENALTY_USE = 0.04      # per earlier use in another cut
PENALTY_PUBLISHED = 0.08  # per use in a cut that was published
PENALTY_CAP = 0.30
TEXT_MATCH = 0.80       # rule 1: line text vs the base project's line text
CONFIRM_MODEL = "gemini-2.5-flash"
MAP_WORDS = {"bentham_ring": ("hell", "lava", "bentham", "pit"), "forest": ("forest", "trees"), "beach": ("beach", "sand"),
             "ice": ("ice", "snow"), "marble": ("marble",), "greybox": ("greybox", "grey pills", "capsule")}
POV_WORDS = {"guard": ("sniper", "scope", "guard", "tower pov", "crosshair"), "runner": ("runner", "prisoner", "duck pov", "duck-pov")}


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", (s or "").lower()).split()


def text_sim(a, b):
    return difflib.SequenceMatcher(None, " ".join(norm(a)), " ".join(norm(b))).ratio()


def cos(a, b):
    num = sum(x * y for x, y in zip(a, b)); da = math.sqrt(sum(x * x for x in a)); db_ = math.sqrt(sum(y * y for y in b))
    return num / (da * db_) if da and db_ else 0.0


class Matcher:
    def __init__(self, db_path=inv.DB_PATH, project=None, base=None, aspect=(1080, 1920), cutoff_date=None,
                 fresh_dates=None, confirm=True):
        if not os.path.isfile(db_path): raise FileNotFoundError("inventory missing: %s (run `content inventory build`)" % db_path)
        self.c = inv.db(db_path)
        self.project, self.base, self.aspect, self.cutoff_date = project, base, aspect, cutoff_date
        self.fresh_dates = fresh_dates or {}
        self.confirm = confirm
        self._client = None
        self.taken = set()  # clips this plan already gave a line: never the same shot twice in one cut
        self.own = {p for p in (project, base) if p}
        self.uses = {}
        for r in self.c.execute("select qhash, project, published from usage"):
            if r["project"] in self.own: continue
            u = self.uses.setdefault(r["qhash"], [0, 0]); u[0] += 1; u[1] += int(r["published"] or 0)
        self.emb = {r["qhash"]: json.loads(r["embedding"]) for r in self.c.execute("select qhash, embedding from captions where embedding is not null")}

    # ---- helpers
    def client(self):
        if self._client is None: self._client = inv._client()
        return self._client

    def penalty(self, q):
        u = self.uses.get(q, [0, 0])
        return min(PENALTY_CAP, PENALTY_USE * (u[0] - u[1]) + PENALTY_PUBLISHED * u[1])

    def format_ok(self, r, letterbox=False):
        w, h = self.aspect
        portrait = h > w
        if (r["h"] > r["w"]) != portrait and not letterbox: return False
        return min(r["w"], r["h"]) >= min(w, h) if not letterbox else True

    def era_ok(self, r, game):
        if self.cutoff_date and r["date"] and r["date"] > self.cutoff_date: return False
        return True

    def cand(self, r, rule, fit, why, cin=0.0, ln=None, from_line=None):
        pen = 0.0 if rule == "explicit" else self.penalty(r["qhash"])
        u = self.uses.get(r["qhash"], [0, 0])
        d = {"inventory_id": r["id"], "path": r["path"], "host": r["host"], "sha1": r["qhash"], "in": float(cin or 0.0),
                "len": float(ln if ln else max(0.0, r["duration"] - float(cin or 0.0))), "rule": rule, "fit": round(fit, 3),
                "uses": u[0], "score": round(fit - pen, 3), "from_project": r["project"], "from_line": from_line,
                "map": r["map"], "pov": r["pov"], "w": r["w"], "h": r["h"], "why": why}
        return {k: v for k, v in d.items() if v is not None}

    def best_row(self, q):
        """One row per footage hash: prefer the PC copy, lossless, then the take."""
        rows = self.c.execute("select * from clips where qhash=?", (q,)).fetchall()
        return sorted(rows, key=lambda r: (r["host"] != "pc", not r["lossless"], r["role"] != "take"))[0] if rows else None

    # ---- rule 1
    def explicit(self, row, spec_line):
        note = row.get("note", "")
        m = re.findall(r"([\w.-]+\.(?:mp4|mkv|avi|mov))", note)
        for name in m:
            r = self.c.execute("select * from clips where lower(path) like ? order by host='pc' desc limit 1", ("%" + name.lower(),)).fetchone()
            if r: return self.cand(r, "explicit", 1.0, "note names %s" % name)
        if not self.base: return None
        q = self.c.execute("""select l.*, k.id kid from lines l join clips k on k.path=l.clip
                              where l.project=? or k.project=? order by l.rowid""", (self.base, self.base)).fetchall()
        same = re.search(r"same (shot )?as (before|v\d+|last time)", note, re.I)
        best = None
        for l in q:
            if row.get("text"):
                s = text_sim(row["text"], l["text"])
            else:  # a beat with no voice: the base line with the same number and no voice either
                s = 1.0 if l["line"][1:] == row["line"][1:] and not l["text"] else 0.0
            if same and l["line"] == row["line"]: s = max(s, 0.99)
            if s >= TEXT_MATCH and (best is None or s > best[0]): best = (s, l)
        if not best: return None
        s, l = best
        parts = [x for x in q if x["project"] == l["project"] and x["version"] == l["version"] and x["line"] == l["line"]]
        cands = []
        for x in parts:
            r = self.c.execute("select * from clips where path=?", (x["clip"],)).fetchone()
            if r: cands.append(self.cand(r, "explicit", s, "base %s %s says the same line (%.2f)" % (l["project"], l["line"], s),
                                         x["in_s"], x["len_s"], from_line=l["line"]))
        if not cands: return None
        head = dict(cands[0])
        if len(cands) > 1: head["parts"] = [{k: c[k] for k in ("path", "sha1", "in", "len")} for c in cands]
        return head

    # ---- rule 2
    def capture_key(self, row):
        g = row.get("game") or {}
        if not g.get("stage"): return None
        sql = "select * from clips where stage=? and coalesce(pov,'')=? and coalesce(map,'bentham_ring')=?"
        args = [g["stage"], g.get("pov") or "", g.get("map") or "bentham_ring"]
        if g.get("set"): sql += " and set_=?"; args.append(g["set"])
        if g.get("bots") is not None: sql += " and bots=?"; args.append(int(g["bots"]))
        fresh = self.fresh_dates.get(g.get("map") or "bentham_ring")
        out = []
        for r in self.c.execute(sql + " order by date desc", args):
            if fresh and (r["date"] or "") < fresh and (g.get("ref") in (None, "", "main")): continue
            if not self.era_ok(r, g) or not self.format_ok(r, "letterbox" in row.get("flags", [])): continue
            out.append(self.cand(r, "capture_key", 1.0, "same stage/set/pov/map/bots, %s" % r["date"]))
        out.sort(key=lambda x: -x["score"])
        return out[0] if out else None

    # ---- rule 3
    def query_text(self, row):
        g = row.get("game") or {}
        bits = [row.get("note", "")]
        for k in ("map", "pov", "stage"):
            if g.get(k): bits.append("%s %s" % (k, g[k]))
        if row.get("source") == "editor": bits.append("Godot editor footage")
        return ". ".join(bits)

    def describe(self, row, k=TOP_K):
        if not self.emb: return [], []
        qv = inv.embed(self.client(), [self.query_text(row)], "RETRIEVAL_QUERY")[0]
        g = row.get("game") or {}
        lb = "letterbox" in row.get("flags", [])
        scored = []
        for q, v in self.emb.items():
            fit = cos(qv, v)
            if fit < FIT_MIN - PENALTY_CAP: continue
            r = self.best_row(q)
            if q in self.taken: continue
            if r is None or r["role"] == "final": continue  # whole cuts carry burned captions; only rule 1 reuses them
            hard = bool(r["meta_src"])  # logs are facts; Gemini's map/pov guesses only cost fit
            if g.get("map") and r["map"] and r["map"] != g["map"]:
                if hard: continue
                fit -= 0.05
            if g.get("pov") in ("guard", "runner") and r["pov"] in ("guard", "runner") and r["pov"] != g["pov"]:
                if hard: continue
                fit -= 0.05
            if not self.format_ok(r, lb) or not self.era_ok(r, g): continue
            scored.append(self.cand(r, "description", fit, "caption similarity %.2f" % fit))
        scored.sort(key=lambda x: -x["score"])
        top = [s for s in scored if s["fit"] >= FIT_MIN][:k]
        return top, scored[:k]

    def confirm_one(self, cand, note):
        """Gemini Flash: does this clip (its contact sheet) show the note? Cached by (clip, note)."""
        ns = hashlib.sha1(note.encode()).hexdigest()
        r = self.c.execute("select yes, why from confirms where qhash=? and note_sha=?", (cand["sha1"], ns)).fetchone()
        if r: return bool(r["yes"]), r["why"]
        jpg = os.path.join(inv.INV_DIR, "sheets", cand["sha1"] + ".jpg")
        if not os.path.isfile(jpg): return False, "no contact sheet"
        from google.genai import types
        prompt = ("These are 6 frames sampled evenly from one video clip of a low-poly first-person game. "
                  "Shot note: \"%s\". Would this clip, or a continuous part of it, serve as that shot? Judge only what is visible; "
                  "on-screen text, POV, map and the action must fit. JSON: {\"yes\": true|false, \"why\": one sentence}" % note)
        try:
            resp = self.client().models.generate_content(model=CONFIRM_MODEL,
                contents=[types.Part.from_bytes(data=open(jpg, "rb").read(), mime_type="image/jpeg"), prompt],
                config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0,
                                                   thinking_config=types.ThinkingConfig(thinking_budget=0)))
            j = json.loads(resp.text); j = j[0] if isinstance(j, list) else j
            yes, why = bool(j.get("yes")), str(j.get("why", ""))[:300]
        except Exception as e:
            return False, "confirm failed: %s" % str(e)[:120]
        self.c.execute("insert or replace into confirms values(?,?,?,?,?)", (cand["sha1"], ns, int(yes), why, CONFIRM_MODEL))
        self.c.commit()
        return yes, why

    # ---- all rules
    def match(self, row, spec_line=None):
        res = {"explicit": None, "capture_key": None, "description": None, "candidates": [], "verdict": None}
        e = self.explicit(row, spec_line)
        if e: res["explicit"] = e; res["candidates"] = [e]; res["verdict"] = "reuse"; return res
        k = self.capture_key(row)
        if k: res["capture_key"] = k; res["candidates"] = [k]; res["verdict"] = "reuse"; return res
        top, near = self.describe(row)
        res["candidates"] = near
        for cnd in top:
            if not self.confirm:
                res["description"] = cnd; res["verdict"] = "reuse?"; break
            yes, why = self.confirm_one(cnd, row.get("note", ""))
            cnd["confirm"] = {"yes": yes, "why": why}
            if yes:
                res["description"] = cnd; res["verdict"] = "reuse"; break
        if res["verdict"] is None: res["verdict"] = "refilm"
        hit = res["explicit"] or res["capture_key"] or res["description"]
        if hit: self.taken |= {hit["sha1"]} | {p["sha1"] for p in hit.get("parts", [])}
        return res


def fresh_dates(repo, maps):
    """Newest content-changing commit date per map: takes older than this show stale geometry."""
    out = {}
    for m in maps:
        r = subprocess.run(["git", "-C", repo, "log", "-1", "--format=%cd", "--date=format:%Y-%m-%d %H:%M", "origin/main", "--",
                            "maps/" + m, "characters", "weapons"], capture_output=True, text=True)
        if r.stdout.strip(): out[m] = r.stdout.strip()
    return out


def commit_date(repo, ref):
    r = subprocess.run(["git", "-C", repo, "log", "-1", "--format=%cd", "--date=format:%Y-%m-%d %H:%M", ref], capture_output=True, text=True)
    return r.stdout.strip() or None
