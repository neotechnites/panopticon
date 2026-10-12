"""content inventory: index every clip under the content roots (PC + Mac) into inventory.sqlite.
`scan` runs on either host with the stdlib only; `build` (Mac) merges both hosts, captions new clips with Gemini Flash, records usage, pushes the db to the PC."""
import argparse, concurrent.futures as cf, hashlib, json, os, re, sqlite3, subprocess, sys, time

PC_ROOT = r"C:\Users\ddd\Desktop\panopticon-renders\content"
PC_CP = r"C:\dev\cp"
MAC_ROOT = os.path.expanduser("~/Desktop/panopticon-renders/content")
INV_DIR = os.path.join(MAC_ROOT, "_inventory")
DB_PATH = os.path.join(INV_DIR, "inventory.sqlite")
PC_DB = PC_ROOT + r"\_inventory.sqlite"
VIDEO = (".mp4", ".mkv", ".avi", ".mov", ".webm")
LOSSLESS = {"utvideo", "ffv1", "huffyuv", "ffvhuff", "rawvideo", "png", "qtrle", "magicyuv"}
SKIP_DIR = re.compile(r"^(_cache|_work|_inventory|_failed.*|_rejected.*|.*work|frames|probe.*|__pycache__|placeholder|scripts|voice|stages|sheets)$", re.I)
GROUPS = {"shorts", "devlogs"}  # a project lives one level deeper under these
CAPTION_MODEL = "gemini-2.5-flash"
EMBED_MODEL = "gemini-embedding-001"
SCHEMA_VERSION = 1

# ---------------------------------------------------------------- scan (PC or Mac, stdlib only)

def qhash(p, size):
    h = hashlib.sha1(str(size).encode())
    with open(p, "rb") as f:
        h.update(f.read(1 << 20))
        if size > 2 << 20:
            f.seek(-(1 << 20), 2); h.update(f.read(1 << 20))
    return h.hexdigest()


def probe(p):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=codec_name,width,height,avg_frame_rate,r_frame_rate:format=duration",
                          "-of", "json", p], capture_output=True, text=True, **_low())
    try:
        j = json.loads(out.stdout); s = j["streams"][0]
    except Exception:
        return None
    def rate(x):
        try:
            a, b = x.split("/"); return round(float(a) / float(b), 3) if float(b) else 0.0
        except Exception:
            return 0.0
    return {"codec": s.get("codec_name", ""), "w": int(s.get("width", 0)), "h": int(s.get("height", 0)),
            "fps": rate(s.get("avg_frame_rate", "0/0")) or rate(s.get("r_frame_rate", "0/0")),
            "duration": float(j.get("format", {}).get("duration") or 0.0)}


def _low():
    return {"creationflags": 0x00004000} if os.name == "nt" else {}


def role_of(rel, name):
    parts = [x.lower() for x in rel.replace("\\", "/").split("/")[:-1]]
    n = name.lower()
    if any(x in ("takes", "raw", "take") for x in parts): return "take"
    if any(x in ("final", "finals", "master") for x in parts) or re.search(r"rough_v\d|_v\d+\.", n): return "final"
    if any(x in ("external", "sources", "music_cuts") for x in parts): return "external"
    return "line"


def project_of(rel):
    parts = rel.replace("\\", "/").split("/")
    if len(parts) > 2 and parts[0].lower() in GROUPS: return parts[1]
    return parts[0] if len(parts) > 1 else "_root"


ARG_RE = re.compile(r"--(map|pov|stage|shot|bots|seed|set|hud|look|seconds|at)=(\"[^\"]*\"|\S+)")


def parse_args(s):
    d = {}
    for k, v in ARG_RE.findall(s or ""):
        d[k] = v.strip('"')
    return d


def parse_log(txt):
    """run_clip.gd stdout: shot, bots, seed, look, stage, pov and [event] lines."""
    d, ev = {}, []
    m = re.search(r"shot (\S+): ([\d.]+) s .*?(\d+) bots, seed (\d+)", txt)
    if m: d.update(shot=m.group(1), bots=int(m.group(3)), seed=int(m.group(4)))
    m = re.search(r"^look (\S+), stage (\S+)", txt, re.M)
    if m:
        d["look"] = m.group(1)
        if m.group(2) != "none": d["stage"] = m.group(2)
    m = re.search(r"\[stage\] plugin res://tools/capture/stages/(\w+)\.gd", txt)
    if m: d["stage"] = m.group(1)
    m = re.search(r"^\[pov\]\s+[\d.]+ (\w+) ", txt, re.M)
    if m: d["pov"] = m.group(1)
    m = re.search(r"Movie Maker mode enabled, recording movie in (\d+)\D+(\d+)", txt)
    if m: d["movie"] = True
    for t, k, who in re.findall(r"^\[event\]\s+([\d.]+)\s+(\w+)\s*(.*)$", txt, re.M):
        if k in ("seat", "shot"): continue
        ev.append({"t": float(t), "kind": k, "who": who.strip()[:60]})
    d["events"] = ev[:400]
    return d


def parse_jobs(txt):
    """jobs.txt rows `name|worktree|godot args|seconds` -> name: args."""
    out = {}
    for ln in txt.splitlines():
        if ln.startswith("#") or ln.count("|") < 2: continue
        name, _wt, args = ln.split("|")[:3]
        out[name.strip()] = args
    return out


def parse_brief(txt):
    """brief md: `## N` blocks with file:/capture:/said:, `# sN word Lx --args  ref` shot rows, L lines."""
    out, lines = {}, {}
    for m in re.finditer(r"^#\s+s(\d+)\s+(\w+)\s+([\w+]+)\s+(--.*?)(?:\s{2,}(\S+))?\s*$", txt, re.M):
        out["s%s_%s" % (m.group(1), m.group(2))] = {"args": m.group(4), "line": m.group(3), "ref": m.group(5) or ""}
    for blk in re.split(r"^## ", txt, flags=re.M)[1:]:
        head = blk.split("\n", 1)[0].strip()
        kv = dict(re.findall(r"^(\w+):\s*(.*)$", blk, re.M))
        stem = kv.get("file") or head
        if kv.get("capture") or kv.get("said"):
            out.setdefault(stem, {}).update({"args": kv.get("capture", ""), "note": kv.get("said", "")[:400], "line": head})
    for m in re.finditer(r"^(L\d+[a-z]?)\s+\"([^\"]*)\"\s*\{([^}]*)\}", txt, re.M):
        lines[m.group(1).lower()] = (m.group(2), m.group(3))
    return out, lines


def sidecars(projdir):
    """Per-project metadata: jobs files and briefs, read once."""
    meta, lines = {}, {}
    for sub in ("", "scripts", "notes"):
        d = os.path.join(projdir, sub)
        if not os.path.isdir(d): continue
        for f in os.listdir(d):
            p = os.path.join(d, f)
            try:
                if re.match(r"jobs.*\.txt$", f):
                    for k, a in parse_jobs(open(p, errors="replace").read()).items():
                        meta.setdefault(k, {})["args"] = a
                elif f.endswith(".md"):
                    m, l = parse_brief(open(p, errors="replace").read())
                    for k, v in m.items(): meta.setdefault(k, {}).update(v)
                    lines.update(l)
            except OSError:
                pass
    return meta, lines


def clip_meta(path, stem, proj_meta, proj_lines):
    d = {}
    base = os.path.dirname(path)
    cands = [os.path.join(base, stem + x) for x in (".take.json", ".json")] + [os.path.join(base, "take.json")]
    for c in cands:
        if os.path.isfile(c):
            try:
                tj = json.load(open(c))
                if isinstance(tj, dict) and ("commit" in tj or "events" in tj):
                    for k in ("commit", "map", "pov", "stage", "set", "bots", "seed", "look", "events"):
                        if k in tj: d[k] = tj[k]
                    d["args"] = " ".join(tj.get("args", [])) if isinstance(tj.get("args"), list) else tj.get("args", "")
                    d["meta_src"] = "take"
                    break
            except Exception:
                pass
    pm = proj_meta.get(stem) or proj_meta.get(re.sub(r"(_take)?\d*$", "", stem)) or {}
    if pm.get("args") and not d.get("args"): d["args"] = pm["args"]
    if pm.get("note"): d["note_hint"] = pm["note"]
    if pm.get("ref"): d["commit"] = d.get("commit") or pm["ref"]
    ln = (pm.get("line") or "").split("+")[0].lower()
    if ln in proj_lines: d["line"], d["line_text"] = ln.upper(), proj_lines[ln][0]; d.setdefault("note_hint", proj_lines[ln][1])
    for c in [os.path.join(base, stem + x) for x in (".log", ".take.log")] + \
             [os.path.join(os.path.dirname(base), "notes", stem + ".take.log")]:
        if os.path.isfile(c):
            try:
                lg = parse_log(open(c, errors="replace").read())
                for k, v in lg.items(): d.setdefault(k, v)
                d.setdefault("meta_src", "log")
            except OSError:
                pass
            break
    ps1 = os.path.join(base, stem + ".ps1")
    if os.path.isfile(ps1) and not d.get("args"):
        d["args"] = " ".join(re.findall(r"--\w+=\S+", open(ps1, errors="replace").read()))
    a = parse_args(d.get("args", ""))
    for k in ("map", "pov", "stage", "set", "look"):
        if a.get(k) and not d.get(k): d[k] = a[k]
    for k in ("bots", "seed"):
        if a.get(k) and d.get(k) is None:
            try: d[k] = int(a[k])
            except ValueError: pass
    if a.get("shot"): d["shot"] = a["shot"]
    if a.get("at") and not d.get("commit"): d["commit"] = a["at"]
    return d


def sheet(path, dur, out):
    """6 frames across the clip, 320 px wide, tiled 3x2 -> jpg (what Gemini captions)."""
    if os.path.isfile(out) or dur <= 0: return
    n = 6; cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "2"]
    for i in range(n):
        cmd += ["-ss", "%.3f" % (dur * (i + 0.5) / n), "-i", path]
    fc = "".join("[%d:v]trim=end_frame=1,scale=320:-2,setsar=1[v%d];" % (i, i) for i in range(n))
    fc += "[v0][v1][v2]hstack=3[a];[v3][v4][v5]hstack=3[b];[a][b]vstack=2"
    subprocess.run(cmd + ["-filter_complex", fc, "-frames:v", "1", "-q:v", "4", out], capture_output=True, **_low())


def scan(root, host, outdir, workers=4):
    """Walk root (known project folders only) -> outdir/scan.jsonl + outdir/sheets/<qhash>.jpg; incremental."""
    os.makedirs(os.path.join(outdir, "sheets"), exist_ok=True)
    prev = {}
    jl = os.path.join(outdir, "scan.jsonl")
    if os.path.isfile(jl):
        for ln in open(jl, encoding="utf-8"):
            try:
                r = json.loads(ln); prev[r["path"]] = r
            except Exception:
                pass
    todo, keep = [], []
    for proj in sorted(os.listdir(root)):
        pdir = os.path.join(root, proj)
        if not os.path.isdir(pdir) or SKIP_DIR.match(proj): continue
        pdirs = [os.path.join(pdir, x) for x in sorted(os.listdir(pdir))] if proj.lower() in GROUPS else [pdir]
        for pd in pdirs:
            if not os.path.isdir(pd): continue
            pmeta, plines = sidecars(pd)
            for r, ds, fs in os.walk(pd):
                ds[:] = [x for x in ds if not SKIP_DIR.match(x)]
                for f in fs:
                    if not f.lower().endswith(VIDEO): continue
                    p = os.path.join(r, f)
                    st = os.stat(p)
                    o = prev.get(p)
                    if o and o["size"] == st.st_size and abs(o["mtime"] - st.st_mtime) < 1 and o.get("v") == SCHEMA_VERSION:
                        keep.append(o); continue
                    todo.append((p, st, pmeta, plines))
    def one(item):
        p, st, pmeta, plines = item
        pr = probe(p)
        if not pr or pr["duration"] <= 0.1: return None
        rel = os.path.relpath(p, root)
        stem = os.path.splitext(os.path.basename(p))[0]
        row = {"v": SCHEMA_VERSION, "host": host, "path": p, "rel": rel.replace("\\", "/"), "size": st.st_size,
               "mtime": st.st_mtime, "date": time.strftime("%Y-%m-%d %H:%M", time.localtime(st.st_mtime)),
               "qhash": qhash(p, st.st_size), "project": project_of(rel), "role": role_of(rel, os.path.basename(p)),
               "lossless": pr["codec"] in LOSSLESS, **pr}
        m = re.search(r"(?:rough_)?v(\d+)", stem)
        row["version"] = "v" + m.group(1) if m and row["role"] == "final" else None
        row.update(clip_meta(p, stem, pmeta, plines))
        sheet(p, pr["duration"], os.path.join(outdir, "sheets", row["qhash"] + ".jpg"))
        return row
    out = list(keep)
    with cf.ThreadPoolExecutor(workers) as ex:
        for i, r in enumerate(ex.map(one, todo)):
            if r: out.append(r)
            if i % 50 == 0: print("scan %d/%d" % (i, len(todo)), file=sys.stderr, flush=True)
    tmp = jl + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        for r in out: fh.write(json.dumps(r) + "\n")
    os.replace(tmp, jl)
    print("scan: %d clips (%d new) -> %s" % (len(out), len(todo), jl))
    return out

# ---------------------------------------------------------------- db (Mac)

DDL = """
create table if not exists clips(id integer primary key, host text, path text, rel text, qhash text, size int, mtime real,
  date text, duration real, w int, h int, fps real, codec text, lossless int, project text, version text, line text,
  line_text text, role text, commit_ text, map text, pov text, stage text, shot text, set_ text, bots int, seed int,
  look text, args text, events text, event_kinds text, note_hint text, meta_src text, caption text, caption_src text,
  approved int default 0, unique(host, path));
create index if not exists clips_q on clips(qhash);
create table if not exists captions(qhash text primary key, json text, model text, at text, embedding text);
create table if not exists usage(id integer primary key, qhash text, path text, project text, version text, line text,
  in_s real, len_s real, published int, at text, source text, unique(qhash, project, version, line, in_s));
create table if not exists approvals(project text, version text, primary key(project, version));
create table if not exists lines(project text, version text, line text, text text, clip text, in_s real, len_s real,
  qhash text, source text, unique(project, version, line, clip, in_s));
create table if not exists confirms(qhash text, note_sha text, yes int, why text, model text, primary key(qhash, note_sha));
"""
APPROVED = {("trailer_reveal", "v20"), ("forest_short", "v5"), ("polish", None), ("projectile", "v2")}


def db(path=DB_PATH):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    c = sqlite3.connect(path); c.row_factory = sqlite3.Row
    c.executescript(DDL)
    for p, v in APPROVED: c.execute("insert or ignore into approvals values(?,?)", (p, v or "*"))
    return c


def merge(c, rows, host):
    seen = set()
    for r in rows:
        seen.add(r["path"])
        ev = r.get("events") or []
        kinds = sorted({e.get("kind") for e in ev if isinstance(e, dict)})
        c.execute("""insert into clips(host,path,rel,qhash,size,mtime,date,duration,w,h,fps,codec,lossless,project,version,line,
          line_text,role,commit_,map,pov,stage,shot,set_,bots,seed,look,args,events,event_kinds,note_hint,meta_src)
          values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
          on conflict(host,path) do update set rel=excluded.rel,qhash=excluded.qhash,size=excluded.size,mtime=excluded.mtime,
          date=excluded.date,duration=excluded.duration,w=excluded.w,h=excluded.h,fps=excluded.fps,codec=excluded.codec,
          lossless=excluded.lossless,project=excluded.project,version=excluded.version,line=excluded.line,line_text=excluded.line_text,
          role=excluded.role,commit_=excluded.commit_,map=coalesce(excluded.map,clips.map),pov=coalesce(excluded.pov,clips.pov),
          stage=excluded.stage,shot=excluded.shot,set_=excluded.set_,bots=excluded.bots,seed=excluded.seed,look=excluded.look,
          args=excluded.args,events=excluded.events,event_kinds=excluded.event_kinds,note_hint=excluded.note_hint,meta_src=excluded.meta_src""",
          (host, r["path"], r.get("rel"), r["qhash"], r["size"], r["mtime"], r.get("date"), r["duration"], r["w"], r["h"], r["fps"],
           r["codec"], int(r["lossless"]), r["project"], r.get("version"), r.get("line"), r.get("line_text"), r["role"],
           r.get("commit"), r.get("map"), r.get("pov"), r.get("stage"), r.get("shot"), r.get("set"), r.get("bots"), r.get("seed"),
           r.get("look"), r.get("args"), json.dumps(ev), ",".join(k for k in kinds if k), r.get("note_hint"), r.get("meta_src")))
    gone = [x["path"] for x in c.execute("select path from clips where host=?", (host,)) if x["path"] not in seen]
    for p in gone: c.execute("delete from clips where host=? and path=?", (host, p))
    c.execute("""update clips set approved=1 where exists(select 1 from approvals a where a.project=clips.project
                 and (a.version='*' or a.version=clips.version))""")
    c.commit()
    return len(gone)

# ---------------------------------------------------------------- captions (Gemini Flash, cached by qhash)

CAPTION_PROMPT = """These are 6 frames, left to right then top to bottom, sampled evenly from one video clip of PANOPTICON,
a low-poly N64-style first-person multiplayer game (a guard with a sniper rifle in a central tower; prisoners called runners
race around a ring and shove each other). Maps: bentham_ring = hell: dark rock pit, lava, central tower with an eye;
forest = green forest; beach = sand and sea; ice = snow and ice; marble = white marble prison; greybox = flat grey early build
with capsule players. Footage can also be the Godot editor, Blender, or external footage from other games.
Describe ONLY what is visible. JSON fields:
caption: 1-2 concrete sentences (camera, map, who moves, what happens, any on-screen text or cards)
map: bentham_ring|forest|beach|ice|marble|greybox|editor|blender|external|unknown
pov: guard|runner|free|orbit|editor|external|unknown   (guard = scope or tower view with crosshair; runner = first person on the ground)
actions: list from [shoot, hit, death, ragdoll, shove, fall, run, jump, portal, orbit, zoom, editor_work, turntable, menu, card, title, other]
era: greybox|old|current|unknown   (old = early textures, bright flat colours; current = detailed lighting)
text_on_screen: true|false
defects: list from [desktop_or_os_ui, frozen, black, letterboxed, low_res, none]"""


def _client():
    from google import genai
    return genai.Client(api_key=os.environ["GEMINI_API_KEY"])


def caption_one(client, jpg):
    from google.genai import types
    data = open(jpg, "rb").read()
    for attempt in range(4):
        try:
            r = client.models.generate_content(model=CAPTION_MODEL, contents=[types.Part.from_bytes(data=data, mime_type="image/jpeg"), CAPTION_PROMPT],
                config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0,
                                                   thinking_config=types.ThinkingConfig(thinking_budget=0)))
            j = json.loads(r.text)
            if isinstance(j, list): j = j[0]
            return j
        except Exception as e:
            err = e; time.sleep(2 * (attempt + 1))
    raise RuntimeError("caption failed: %s" % err)


def embed(client, texts, task="RETRIEVAL_DOCUMENT"):
    from google.genai import types
    out = []
    for i in range(0, len(texts), 50):
        r = client.models.embed_content(model=EMBED_MODEL, contents=texts[i:i + 50],
                                        config=types.EmbedContentConfig(output_dimensionality=256, task_type=task))
        out += [e.values for e in r.embeddings]
    return out


def caption_text(j, row=None):
    """Text the embedding is built from: Gemini's words plus the hard metadata."""
    bits = [j.get("caption", "")] if j else []
    if j: bits += ["map " + str(j.get("map")), "pov " + str(j.get("pov")), "actions " + " ".join(j.get("actions") or [])]
    if row is not None:
        for k in ("map", "pov", "stage", "event_kinds", "note_hint"):
            if row[k]: bits.append("%s %s" % (k, row[k]))
    return ". ".join(b for b in bits if b)


def caption_all(c, sheets_dir, workers=8, limit=None):
    todo = [r["qhash"] for r in c.execute("""select distinct qhash from clips where qhash not in (select qhash from captions)""")]
    todo = [q for q in todo if os.path.isfile(os.path.join(sheets_dir, q + ".jpg"))][:limit]
    if todo:
        client = _client()
        print("captions: %d new" % len(todo), flush=True)
        def one(q):
            try: return q, caption_one(client, os.path.join(sheets_dir, q + ".jpg"))
            except Exception as e: return q, {"error": str(e)[:200]}
        done = 0
        with cf.ThreadPoolExecutor(workers) as ex:
            for q, j in ex.map(one, todo):
                c.execute("insert or replace into captions(qhash,json,model,at) values(?,?,?,?)",
                          (q, json.dumps(j), CAPTION_MODEL, time.strftime("%Y-%m-%d %H:%M")))
                done += 1
                if done % 50 == 0: c.commit(); print("captions %d/%d" % (done, len(todo)), flush=True)
        c.commit()
    # fill clip columns from captions where the logs left them empty
    for r in c.execute("select qhash, json from captions").fetchall():
        j = json.loads(r["json"])
        if "error" in j: continue
        m = j.get("map") if j.get("map") not in (None, "unknown") else None
        p = j.get("pov") if j.get("pov") not in (None, "unknown") else None
        c.execute("""update clips set caption=?, caption_src='gemini', map=coalesce(map,?), pov=coalesce(pov,?),
                     event_kinds=case when coalesce(event_kinds,'')='' then ? else event_kinds end where qhash=?""",
                  (j.get("caption"), m, p, ",".join(j.get("actions") or []), r["qhash"]))
    c.commit()
    # embeddings
    need = c.execute("""select c.qhash, c.json, k.map, k.pov, k.stage, k.event_kinds, k.note_hint from captions c
                        join clips k on k.qhash=c.qhash where c.embedding is null group by c.qhash""").fetchall()
    need = [r for r in need if "error" not in json.loads(r["json"])]
    if need:
        client = _client()
        vecs = embed(client, [caption_text(json.loads(r["json"]), r) for r in need])
        for r, v in zip(need, vecs):
            c.execute("update captions set embedding=? where qhash=?", (json.dumps([round(x, 5) for x in v]), r["qhash"]))
        c.commit()
        print("embeddings: %d" % len(need))

# ---------------------------------------------------------------- usage (variety penalty)

def record_usage(c, qhash, path, project, version, line, in_s, len_s, published, source):
    c.execute("insert or ignore into usage(qhash,path,project,version,line,in_s,len_s,published,at,source) values(?,?,?,?,?,?,?,?,?,?)",
              (qhash, path, project, version, line, in_s, len_s, int(published), time.strftime("%Y-%m-%d %H:%M"), source))


def usage_from_cut_scripts(c, texts):
    """Older cuts: any clip basename named in a project's cut script / parts list counts as one use by that project."""
    by_name = {}
    for r in c.execute("select qhash, path, project, role from clips where role in ('take','line','external')"):
        by_name.setdefault(os.path.basename(r["path"].replace("\\", "/")).lower(), []).append(r)
    finals = {}
    for r in c.execute("select project, max(version) v from clips where role='final' group by project"):
        finals[r["project"]] = r["v"]
    n = 0
    for project, txt in texts:
        low = txt.lower()
        for name, rows in by_name.items():
            if len(name) > 6 and name in low:
                for r in rows:
                    record_usage(c, r["qhash"], r["path"], project, finals.get(project) or "v?", None, None, None,
                                 project in finals, "cut_script"); n += 1
    c.commit()
    return n


LEGACY_TUPLE = re.compile(r'\(\s*"([lLmM]\d+[a-z]?)"\s*,\s*("(?:[^"\\\\]|\\\\.)*"|None)\s*,\s*(\[[^\]]*\]|None)')
CLIP_TUPLE = re.compile(r'\(\s*"([^"]+\.(?:mp4|mkv|avi|mov))"\s*,\s*([\d.]+)')
TABLE_ROW = re.compile(r"^\|\s*([lLmM]\d+[a-z]?)\s*\|\s*([^|]*\.(?:mp4|mkv|avi|mov))\s*\|\s*([\d.]*|cont)\s*\|\s*([\d.]*)\s*\|[^|]*\|[^|]*\|\s*([^|]*)\|", re.M)


def legacy_lines(txt):
    """Line -> clip tables in older cut scripts: cut.py LINES tuples and the brief.py `| l1 | cuts/x.mp4 | in | len |...| text |` table."""
    out = []
    for lid, text, clips in LEGACY_TUPLE.findall(txt):
        t = "" if text == "None" else json.loads(text)
        for name, cin in CLIP_TUPLE.findall(clips):
            out.append((lid[0].upper() + lid[1:].lower(), t, name, float(cin), None))
    for lid, clip, cin, ln, text in TABLE_ROW.findall(txt):
        out.append((lid[0].upper() + lid[1:].lower(), text.strip(), clip.strip(), None if cin in ("", "cont") else float(cin), float(ln) if ln else None))
    return out


def lines_from_cut_scripts(c, texts):
    by_name = {}
    for r in c.execute("select qhash, path, project from clips where role in ('take','line','external')"):
        by_name.setdefault(os.path.basename(r["path"].replace("\\", "/")).lower(), []).append(r)
    finals = {r["project"]: r["v"] for r in c.execute("select project, max(version) v from clips where role='final' group by project")}
    n = 0
    for project, txt in texts:
        for lid, text, clip, cin, ln in legacy_lines(txt):
            rows = by_name.get(os.path.basename(clip.replace("\\", "/")).lower(), [])
            rows = sorted(rows, key=lambda r: r["project"] != project)[:1]
            for r in rows:
                c.execute("insert or ignore into lines values(?,?,?,?,?,?,?,?,?)",
                          (project, finals.get(project) or "v?", lid, text, r["path"], cin, ln, r["qhash"], "cut_script")); n += 1
    c.commit()
    return n


def pc_cut_scripts():
    """Cut scripts and parts lists on the PC (scripts\\, *work\\, project roots), returned as (project, text)."""
    code = r'''
import os, json
R = r"%s"
out = []
for top in os.listdir(R):
    tp = os.path.join(R, top)
    if not os.path.isdir(tp): continue
    projs = [os.path.join(tp, x) for x in os.listdir(tp)] if top.lower() in ("shorts", "devlogs") else [tp]
    for pd in projs:
        if not os.path.isdir(pd): continue
        for r, ds, fs in os.walk(pd):
            if r.count(os.sep) - pd.count(os.sep) > 2: ds[:] = []; continue
            ds[:] = [d for d in ds if d.lower() not in ("takes", "raw", "frames", "_cache", "sheets")]
            for f in fs:
                if f.endswith((".py", ".ps1", ".sh", ".md")) or f in ("parts.txt", "list.txt", "timing.json", "map.tsv") or f.endswith("_lines.json"):
                    try: out.append([os.path.basename(pd), open(os.path.join(r, f), errors="replace").read()[:200000]])
                    except OSError: pass
print(json.dumps(out))
''' % PC_ROOT
    r = subprocess.run(["ssh", "panopticon-pc", "python -"], input=code, capture_output=True, text=True, timeout=300)
    return json.loads(r.stdout or "[]")

# ---------------------------------------------------------------- build (Mac orchestration)

def _ssh(cmd, timeout=7200):
    return subprocess.run(["ssh", "panopticon-pc", cmd], capture_output=True, text=True, timeout=timeout)


def build(caption=True, workers=4, cap_limit=None, mac_roots=(MAC_ROOT,)):
    here = os.path.abspath(__file__)
    _ssh(r"New-Item -ItemType Directory -Force %s | Out-Null" % PC_CP)
    subprocess.run(["scp", "-q", here, "panopticon-pc:%s/inventory.py" % PC_CP.replace("\\", "/")], check=True)
    pc_out = PC_ROOT + r"\_inventory"
    print("pc scan ...", flush=True)
    r = _ssh(r"python %s\inventory.py scan --root %s --host pc --out %s --workers %d" % (PC_CP, PC_ROOT, pc_out, workers))
    if r.returncode: raise SystemExit("pc scan failed: " + r.stderr[-2000:])
    print(r.stdout.strip().splitlines()[-1])
    os.makedirs(os.path.join(INV_DIR, "pc"), exist_ok=True)
    subprocess.run(["scp", "-q", "panopticon-pc:%s/scan.jsonl" % pc_out.replace("\\", "/"), os.path.join(INV_DIR, "pc", "scan.jsonl")], check=True)
    pc_rows = [json.loads(x) for x in open(os.path.join(INV_DIR, "pc", "scan.jsonl"), encoding="utf-8")]
    sheets = os.path.join(INV_DIR, "sheets"); os.makedirs(sheets, exist_ok=True)
    missing = sorted({x["qhash"] for x in pc_rows} - {f[:-4] for f in os.listdir(sheets)})
    if missing:  # pull the new sheets as one tar
        lst = os.path.join(INV_DIR, "pull.txt")
        open(lst, "w").write("\n".join(m + ".jpg" for m in missing) + "\n")
        subprocess.run(["scp", "-q", lst, "panopticon-pc:%s/pull.txt" % pc_out.replace("\\", "/")], check=True)
        _ssh(r"tar -cf %s\pull.tar -C %s\sheets -T %s\pull.txt" % (pc_out, pc_out, pc_out))
        subprocess.run(["scp", "-q", "panopticon-pc:%s/pull.tar" % pc_out.replace("\\", "/"), os.path.join(INV_DIR, "pull.tar")], check=True)
        subprocess.run(["tar", "-xf", os.path.join(INV_DIR, "pull.tar"), "-C", sheets], check=False)
        os.remove(os.path.join(INV_DIR, "pull.tar"))
    c = db()
    merge(c, pc_rows, "pc")
    for root in mac_roots:
        mrows = scan(root, "mac", os.path.join(INV_DIR, "mac"), workers)
        for f in os.listdir(os.path.join(INV_DIR, "mac", "sheets")):
            dst = os.path.join(sheets, f)
            if not os.path.exists(dst): os.link(os.path.join(INV_DIR, "mac", "sheets", f), dst)
        merge(c, mrows, "mac")
    texts = pc_cut_scripts()
    n = usage_from_cut_scripts(c, texts)
    m = lines_from_cut_scripts(c, texts)
    print("usage rows from cut scripts: %d; line rows: %d" % (n, m))
    if caption: caption_all(c, sheets, limit=cap_limit)
    c.close()
    subprocess.run(["scp", "-q", DB_PATH, "panopticon-pc:%s" % PC_DB.replace("\\", "/")], check=False)
    summary()


def summary(path=DB_PATH):
    c = db(path)
    t = c.execute("select count(*) n, count(caption) cap, sum(duration)/3600.0 hrs from clips").fetchone()
    print("inventory: %d clips, %d captioned, %.1f h of footage -> %s" % (t["n"], t["cap"], t["hrs"] or 0, path))
    for r in c.execute("select project, role, count(*) n from clips group by project, role order by project"):
        print("  %-20s %-8s %d" % (r["project"], r["role"], r["n"]))


def main(argv=None):
    ap = argparse.ArgumentParser(prog="content inventory")
    sp = ap.add_subparsers(dest="cmd")
    s = sp.add_parser("scan"); s.add_argument("--root", required=True); s.add_argument("--host", default="pc")
    s.add_argument("--out", required=True); s.add_argument("--workers", type=int, default=4)
    b = sp.add_parser("build"); b.add_argument("--no-caption", action="store_true"); b.add_argument("--workers", type=int, default=4)
    b.add_argument("--caption-limit", type=int)
    sp.add_parser("summary")
    a = ap.parse_args(argv)
    if a.cmd == "scan": scan(a.root, a.host, a.out, a.workers)
    elif a.cmd == "build": build(not a.no_caption, a.workers, a.caption_limit)
    else: summary()


if __name__ == "__main__":
    main()
