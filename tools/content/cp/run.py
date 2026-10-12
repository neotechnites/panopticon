"""Orchestrator: `content short|devlog|trailer <spec.md>` runs every stage and gate, resumable by input hash.
Gemini review (G14) is opt-in (--gemini-review, Ryan 2026-10-12); its failures re-cut only failing lines."""
import argparse
import hashlib
import importlib
import json
import os
import re
import subprocess
import sys
import time

from . import deliver as deliver_mod
from . import gates, gemini, pclock, preflight, review

MAX_FIX_ROUNDS = 2
EXIT_GATE, EXIT_HANDBACK = 2, 3
REPO = subprocess.run(["git", "-C", os.path.dirname(os.path.abspath(__file__)), "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
STAGE_GATES = {"preflight": ["G0"], "plan": ["G1", "G1b", "G2"], "capture": ["G3", "G4", "G5", "G6", "G6b"],
               "render": ["G7", "G8", "G9", "G10", "G11", "G13", "G16", "G17"], "review": ["G12"],
               "deliver": ["G15"]}
RETAKE_GATES = {"G3", "G4"}     # one automatic retake; G5/G6/G6b need a restage, so they hand back
# minutes, design (f): a pure recut ~10, a short on existing stages ~20, each new stage plugin +6 (write + smoke)
BUDGET_RECUT, BUDGET_CAPTURE, BUDGET_NEW_STAGE = 10, 20, 6


class Stop(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code = code


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------- peer modules: the one table of how each is called ----------

def argv_for(stage, b, only=None):
    """argv for a peer module's main(). `b` is the Build; `only` restricts to line ids (fix rounds).
    voice, render and timeline run on the PC (their paths are PC paths); plan and capture run here."""
    pj = b.pc_proj
    return {
        "plan": [b.spec, "--out", b.dir],
        "voice": [pj + "\\plan.json", "--out", pj] + (["--ryan", b.args.ryan] if b.args.ryan else []),
        "capture": [b.p("plan.json"), "--out", b.dir] + (list(only) if only else b.film_ids())
                   + (["--mode", "final"] if b.args.final or b.args.movie else []),
        "render": [pj] + (["--tag", b.render_tag()]) + (["--only", ",".join(only)] if only else []),
        "timeline": [pj, "--tag", b.render_tag()],
    }[stage]


PC_CODE = r"C:\dev\cp\content"     # tools/content/{cp,pc} mirrored here for the PC-side tools
PC_CONTENT = r"C:\Users\ddd\Desktop\panopticon-renders\content"
PC_SIDE = {"voice", "render", "timeline"}
_synced = False


def sync_pc_code():
    """Mirror this checkout's tools/content/cp and pc to the PC once per run (the PC never runs stale tools)."""
    global _synced
    if _synced:
        return
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rc, out = preflight.ssh(f'Remove-Item -Recurse -Force "{PC_CODE}\\cp", "{PC_CODE}\\pc" -EA SilentlyContinue; '
                            f'New-Item -ItemType Directory -Force "{PC_CODE}" | Out-Null; "ok"')
    if not out.endswith("ok"):
        raise Stop(EXIT_GATE, f"PC code dir: {out[-120:]}")
    for d in ("cp", "pc"):
        subprocess.run(["scp", "-rq", os.path.join(here, d), deliver_mod.scp_path(PC_CODE + "\\" + d)], check=True)
    _synced = True


def _ps_arg(a):
    return "'" + str(a).replace("'", "''") + "'"


def pc_call(module, argv, timeout=3600):
    """`python -m cp.<module> argv` on the PC, output streamed to this log; raises Stop on a non-zero exit."""
    sync_pc_code()
    log(f"{module} (PC): {' '.join(argv)}")
    cmd = (f"$env:PYTHONPATH = '{PC_CODE}'; $env:CP_LEASE_HELD = '1'; $env:PYTHONIOENCODING = 'utf-8'; "
           f"Set-Location '{PC_CODE}'; python -m cp.{module} {' '.join(_ps_arg(a) for a in argv)} 2>&1 | "
           f"ForEach-Object {{ \"$_\" }}; \"rc=$LASTEXITCODE\"")
    rc, out = preflight.ssh(cmd, timeout=timeout)
    lines = out.splitlines()
    for ln in lines[:-1]:
        print("    " + ln, flush=True)
    m = re.search(r"rc=(-?\d+)\s*$", out)
    code = int(m.group(1)) if m else rc
    if code != 0:
        raise Stop(EXIT_GATE, f"{module} (PC) exited {code}: {lines[-2] if len(lines) > 1 else out[-200:]}")


def call(module, argv):
    if module in PC_SIDE:
        return pc_call(module, argv)
    try:
        mod = importlib.import_module(f"{__package__}.{module}")
    except ImportError as e:
        raise Stop(EXIT_GATE, f"cp/{module}.py has not landed ({e})")
    log(f"{module}: {' '.join(argv)}")
    rc = mod.main(argv)
    if module == "plan" and rc == 3:
        raise Stop(EXIT_HANDBACK, f"write {os.path.join(argv[2], 'shots.json')} from shots.prompt.md "
                   "(schema cp/schema/shots.json), then rerun")
    if rc not in (0, None):
        raise Stop(EXIT_GATE, f"{module} exited {rc}")


# ---------- the build ----------

class Build:
    def __init__(self, kind, args):
        self.kind, self.args = kind, args
        self.spec = os.path.abspath(args.spec)
        self.name = os.path.splitext(os.path.basename(self.spec))[0]
        self.dir = os.path.splitext(self.spec)[0]
        os.makedirs(self.dir, exist_ok=True)
        self.state = self.load("run_state.json") or {}
        self.ctx = gates.Ctx(self.dir, name=self.name, kind=kind, spec=self.spec)

    def p(self, f):
        return os.path.join(self.dir, f)

    @property
    def pc_proj(self):
        """The build's PC folder: capture writes takes\\<line> here, voice and render read and write it."""
        return f"{PC_CONTENT}\\{self.name}"

    def film_ids(self):
        return [l["id"] for l in self.lines({"capture", "editor"})]

    def render_tag(self):
        return self.args.tag and f"{self.name}_{self.args.tag}" or self.name

    def push(self, rel):
        """Copy a build file (plan.json, voice/manifest.json, ...) to the same place under the PC folder."""
        dst = self.pc_proj + "\\" + rel.replace("/", "\\")
        preflight.ssh(f'New-Item -ItemType Directory -Force "{os.path.dirname(dst.replace(chr(92), "/"))}" | Out-Null')
        subprocess.run(["scp", "-q", self.p(rel), deliver_mod.scp_path(dst)], check=True)

    def pull(self, rel, required=True):
        dst = self.p(rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        r = subprocess.run(["scp", "-q", deliver_mod.scp_path(self.pc_proj + "\\" + rel.replace("/", "\\")), dst],
                           capture_output=True, text=True)
        if r.returncode and required:
            raise Stop(EXIT_GATE, f"could not pull {rel} from the PC: {r.stderr.strip()[-160:]}")
        return r.returncode == 0

    def load(self, f):
        try:
            with open(self.p(f)) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return None

    def save_state(self):
        with open(self.p("run_state.json"), "w") as f:
            json.dump(self.state, f, indent=1)

    def stamp(self, files):
        h = hashlib.sha1()
        for f in files:
            p = f if os.path.isabs(f) else self.p(f)
            h.update(f.encode())
            if os.path.isfile(p):
                with open(p, "rb") as fh:
                    h.update(fh.read())
        return h.hexdigest()

    def fresh(self, stage, inputs, outputs):
        """True when the stage already ran on these exact inputs and its outputs exist."""
        if self.args.from_stage and STAGES.index(stage) >= STAGES.index(self.args.from_stage):
            return False
        st = self.state.get(stage)
        return bool(st and st["in"] == self.stamp(inputs) and all(os.path.exists(self.p(o)) for o in outputs))

    def done(self, stage, inputs):
        self.state[stage] = {"in": self.stamp(inputs), "at": time.strftime("%Y-%m-%d %H:%M:%S")}
        self.save_state()

    def gate(self, stage, ids=None):
        ok, res = gates.run(self.ctx, ids or STAGE_GATES[stage], log=log)
        return ok, res

    def lines(self, actions):
        return [l for l in (self.load("plan.json") or {}).get("lines", []) if l.get("action") in actions]


def failing_lines(res):
    """{line id: reason} across gate results that carry per-line detail."""
    out = {}
    for gid, r in res.items():
        if not r["pass"]:
            for lid, why in (r.get("lines") or {}).items():
                out.setdefault(lid, f"{gid}: {why}")
    return out


def write_fix(b, fixes):
    with open(b.p("fix.json"), "w") as f:
        json.dump({"lines": fixes}, f, indent=1)


# ---------- stages ----------

def s_preflight(b):
    ok, res = b.gate("preflight")
    if not ok:
        raise Stop(EXIT_GATE, f"G0: {res['G0']['reason']}")


def s_plan(b):
    if not b.fresh("plan", [b.spec], ["plan.json"]):
        call("plan", argv_for("plan", b))
        b.done("plan", [b.spec])
    ok, res = b.gate("plan")
    if not ok:
        raise Stop(EXIT_GATE, "; ".join(f"{g}: {r['reason']}" for g, r in res.items() if not r["pass"]))
    c = (b.load("plan.json") or {}).get("counts") or {}
    log("plan: " + " / ".join(f"{k} {v}" for k, v in c.items()))
    new = missing_stages(b)
    films = bool(b.lines({"capture", "editor"}))
    est = (BUDGET_CAPTURE if films else BUDGET_RECUT) + BUDGET_NEW_STAGE * len({m[1] for m in new})
    log(f"estimate: ~{est} min ({'films new takes' if films else 'pure recut'}"
        + (f"; {len(new)} line(s) need a new stage plugin, +{BUDGET_NEW_STAGE} min each: "
           + ", ".join(f"{i} '{st}'" for i, st, _ in new) if new else "") + ")")


def s_voice(b):
    if b.fresh("voice", ["plan.json"], ["voice/manifest.json"]):
        return
    b.push("plan.json")
    if b.args.ryan and os.path.isdir(b.args.ryan):   # Ryan's takes on the Mac go to the PC first
        dst = b.pc_proj + "\\ryan_vo"
        subprocess.run(["scp", "-rq", b.args.ryan, deliver_mod.scp_path(dst)], check=True)
        b.args.ryan = dst
    call("voice", argv_for("voice", b))
    b.pull("voice/manifest.json")
    b.pull("voice/words.json", required=False)
    b.done("voice", ["plan.json"])


def missing_stages(b):
    """[(line, stage, note)] for capture lines whose stage plugin does not exist yet."""
    out = []
    for l in b.lines({"capture"}):
        st = (l.get("game") or {}).get("stage")
        if st and not os.path.isfile(os.path.join(REPO, "tools", "capture", "stages", f"{st}.gd")):
            out.append((l["id"], st, l.get("note", "")))
    return out


def s_stage(b):
    """Every capture line needs its stage plugin; a missing one is agent work, handed back."""
    missing = [f"{i}: stage '{st}' ({note})" for i, st, note in missing_stages(b)]
    if missing:
        raise Stop(EXIT_HANDBACK, "write these stage plugins and smoke them headless, then rerun:\n  " +
                   "\n  ".join(missing))


def _take_proxy(b, lid, take_path):
    """A small H.264 copy of a take for the Gemini take check (PC takes are utvideo, far too big to upload)."""
    if not gates.is_pc(take_path):
        return take_path
    proxy = take_path.rsplit(".", 1)[0] + "_proxy.mp4"
    rc, out = preflight.ssh(f'$p = Start-Process ffmpeg -ArgumentList \'-v error -y -i "{take_path}" -vf scale=-2:960 '
                            f'-c:v libx264 -crf 28 -an -threads 4 "{proxy}"\' -PassThru -Wait -NoNewWindow '
                            f'-ErrorAction Stop; "rc=$($p.ExitCode)"', timeout=600)
    if "rc=0" not in out:
        raise RuntimeError(f"take proxy failed: {out[-120:]}")
    local = b.p(f"takes/{lid}/proxy.mp4")
    os.makedirs(os.path.dirname(local), exist_ok=True)
    subprocess.run(["scp", "-q", deliver_mod.scp_path(proxy), local], check=True)
    return local


def take_check(b, ids):
    """G14 per take: Gemini Flash compares each new take with its note; returns {id: reason} for failures."""
    plan = {l["id"]: l for l in (b.load("plan.json") or {}).get("lines", [])}
    bad = {}
    for lid in ids:
        tj = b.load(f"takes/{lid}/take.json")
        if not tj:
            bad[lid] = "no take.json"
            continue
        r = gemini.take_check(_take_proxy(b, lid, tj["path"]), plan[lid].get("note", ""), list(review.DEFECTS))
        hard = [d for d in r["defects"] if d.split(":")[0] in review.FAIL_DEFECTS]
        if r["shows_note"] != "yes" or hard:
            bad[lid] = f"take check: {','.join(hard) or 'does not show the note'}: {r['why']}"
    return bad


def s_capture(b, only=None):
    new = [l["id"] for l in b.lines({"capture", "editor"})]
    if only:
        new = [i for i in new if i in only] or list(only)
    if not new:
        log("capture: nothing new to film (pure recut)")
        return
    if not only and b.fresh("capture", ["plan.json"], [f"takes/{i}/take.json" for i in new]):
        return
    ok, why, _ = preflight.run(capture=True, voice=False, final=b.args.final, log=lambda *_: None)
    if not ok:
        raise Stop(EXIT_GATE, f"G0 (capture): {why}")
    call("capture", argv_for("capture", b, only=new))   # capture films game and editor rows alike
    for attempt in (0, 1):
        ok, res = b.gate("capture")
        bad = failing_lines(res)
        if b.args.gemini_review:
            bad.update(take_check(b, [i for i in new if i not in bad]))
        if not bad:
            break
        hard = {k: v for k, v in bad.items() if v.split(":")[0] not in RETAKE_GATES and not v.startswith("take check")}
        if hard or attempt == 1:
            raise Stop(EXIT_HANDBACK, "restage these lines (a blind retake will not fix them):\n  " +
                       "\n  ".join(f"{k}: {v}" for k, v in (hard or bad).items()))
        log(f"capture: one automatic retake of {', '.join(bad)}")
        write_fix(b, [{"id": k, "action": "reshoot", "reason": v} for k, v in bad.items()])
        call("capture", argv_for("capture", b, only=list(bad)))
    b.done("capture", ["plan.json"])


def s_render(b, only=None):
    ins = ["plan.json", "voice/manifest.json"] + [f"takes/{l['id']}/take.json" for l in b.lines({"capture", "editor"})]
    if only or not b.fresh("render", ins, ["edl.json"]):
        b.push("plan.json")
        b.push("voice/manifest.json")
        with pclock.lease("heavy", f"{b.name} render", 900):
            try:
                call("render", argv_for("render", b, only=only))
            finally:
                b.pull("render_gates.json", required=False)
            if b.kind == "devlog":
                call("timeline", argv_for("timeline", b))
        b.pull("edl.json")
        if b.kind == "devlog":
            rc, out = preflight.ssh(f'(Get-ChildItem "{b.pc_proj}" -Filter "{b.render_tag()}_*.fcpxml" | '
                                    'Sort-Object LastWriteTime | Select-Object -Last 1).FullName')
            edl = b.load("edl.json")
            edl["fcpxml"] = out.strip() or None
            with open(b.p("edl.json"), "w") as f:
                json.dump(edl, f, indent=1)
        b.done("render", ins)
    ok, res = b.gate("render")
    if not ok:
        raise Stop(EXIT_GATE, "; ".join(f"{g}: {r['reason']}" for g, r in res.items() if not r["pass"]))


def final_path(b):
    edl = b.load("edl.json") or {}
    src = edl.get("final")
    if not src:
        raise Stop(EXIT_GATE, "edl.json names no final")
    return src if gates.is_pc(src) else b.pc_proj + "\\" + src.replace("/", "\\")


def _base(p):
    return os.path.basename(p.replace("\\", "/"))


def geometry_events(b):
    """run_clip [clip] events (take time, same clock as part `in`) mapped to final time through edl.json."""
    out = {}
    for l in (b.load("edl.json") or {}).get("lines", []):
        tj = b.load(f"takes/{l['id']}/take.json") or {}
        off = l["start"]
        for p in l.get("parts", []):
            if tj.get("path") and _base(tj["path"]) == _base(p["path"]):
                out.setdefault(l["id"], []).extend(off + e["t"] - p["in"] for e in tj.get("clip_events", [])
                                                   if p["in"] <= e["t"] < p["in"] + p["len"])
            off += p["len"]
    return out


def s_review(b):
    src = final_path(b)
    b.ctx.final = deliver_mod.fetch_final(src, b.kind, b.name)
    if not b.args.gemini_review:
        return b.gate("review")
    plan, edl = b.load("plan.json"), b.load("edl.json")
    ref = None if (b.load("voice/manifest.json") or {}).get("engine") == "ryan" or b.args.ryan else review.VOICE_REF
    log(f"review: {os.path.basename(b.ctx.final)} with {gemini.PRO} at {review.FPS} fps")
    review.review(b.ctx.final, plan, edl, out=b.p("review.json"), voice_ref=ref, geometry=geometry_events(b),
                  log=log)
    return b.gate("review", ["G12", "G14"])


def fix_round(b, res, n):
    """Act on failing lines only: revoice, reshoot, then re-cut those lines."""
    rv = b.load("review.json") or {}
    fixes = list(rv.get("fix", []))
    for lid, why in failing_lines({k: v for k, v in res.items() if k != "G14"}).items():
        if lid != "final" and not any(f["id"] == lid for f in fixes):
            fixes.append({"id": lid, "action": "recut", "reason": why})
    if not fixes:
        raise Stop(EXIT_GATE, "review failed with no line to fix: " + "; ".join(r["reason"] for r in res.values()
                                                                             if not r["pass"]))
    write_fix(b, fixes)
    log(f"fix round {n}: " + " | ".join(f"{f['action']} {f['reason']}" for f in fixes))
    by = {a: [f["id"] for f in fixes if f["action"] == a] for a in ("revoice", "reshoot", "recut")}
    if by["revoice"]:
        call("voice", argv_for("voice", b, only=by["revoice"]))
    if by["reshoot"]:
        s_capture(b, only=by["reshoot"])
    s_render(b, only=[f["id"] for f in fixes])


def s_deliver(b):
    edl = b.load("edl.json") or {}
    d = deliver_mod.deliver(b.dir, final_path(b), b.kind, b.name, tag=b.args.tag,
                            fcpxml=edl.get("fcpxml"), concat=getattr(b.args, "concat", False), log=log)
    ok, res = b.gate("deliver")
    if not ok:
        raise Stop(EXIT_GATE, f"G15: {res['G15']['reason']}")
    return d


STAGES = ["preflight", "plan", "voice", "stage", "capture", "render", "review", "deliver"]


def build(kind, args):
    b = Build(kind, args)
    t0 = time.time()
    log(f"{kind} {b.name}: {b.dir}")
    s_preflight(b)
    s_plan(b)
    s_voice(b)
    s_stage(b)
    s_capture(b)
    s_render(b)
    ok, res = s_review(b)
    n = 0
    while not ok:
        if n >= MAX_FIX_ROUNDS or not b.args.gemini_review:
            raise Stop(EXIT_GATE, f"still failing after {n} fix rounds:\n  " +
                       "\n  ".join(f"{g}: {r['reason']}" for g, r in res.items() if not r["pass"]))
        n += 1
        fix_round(b, res, n)
        ok, res = s_review(b)
    d = s_deliver(b)
    c = (b.load("plan.json") or {}).get("counts") or {}
    rv = b.load("review.json") or {}
    partly = [l["note"] for l in rv.get("lines", []) if l.get("note")]
    print(f"\n{b.name} {d['tag']} delivered in {(time.time() - t0) / 60:.1f} min\n"
          f"  Mac: {d['mac']}\n  PC:  {d['pc']}\n"
          f"  plan: {' / '.join(f'{k} {v}' for k, v in c.items())}; fix rounds: {n}\n"
          f"  gates: all pass" + (f"\n  partly: {'; '.join(partly)}" if partly else ""))
    return 0


TOOLS = {"preflight": "preflight", "review": "review", "verify": "gates", "deliver": "deliver"}


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] not in ("short", "devlog", "trailer", "-h", "--help"):
        mod = TOOLS.get(argv[0], argv[0])
        try:
            m = importlib.import_module(f"{__package__}.{mod}")
        except ImportError:
            print(f"content: no tool '{argv[0]}' (cp/{mod}.py)", file=sys.stderr)
            return 1
        return m.main(argv[1:]) or 0
    ap = argparse.ArgumentParser(prog="content")
    ap.add_argument("kind", choices=["short", "devlog", "trailer"])
    ap.add_argument("spec", help="tools/content/projects/<name>.md")
    ap.add_argument("--tag", help="vN; refused if that version exists")
    ap.add_argument("--ryan", help="dir of Ryan's per-line recordings (devlog)")
    ap.add_argument("--movie", action="store_true", help="trailer: frame-exact capture backend")
    ap.add_argument("--final", action="store_true", help="final capture on the virtual portrait monitor (rough = "
                    "real time on the console screen at 810x1440)")
    ap.add_argument("--concat", action="store_true", help="devlog: also deliver a concat mp4")
    ap.add_argument("--from", dest="from_stage", choices=STAGES, help="rerun from this stage")
    ap.add_argument("--gemini-review", action="store_true",
                    help="opt-in: Gemini judges every line vs its note (G14) with fix rounds; off by default")
    a = ap.parse_args(argv)
    try:
        return build(a.kind, a)
    except Stop as e:
        print(f"\nSTOP ({'hand back' if e.code == EXIT_HANDBACK else 'gate'}): {e}", file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main())
