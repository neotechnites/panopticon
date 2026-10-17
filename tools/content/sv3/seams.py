"""Static seam checks for the shorts v3 stage path (pod DESIGN §10): every name one side writes and another reads, < 5 s, no PC.

    python -m sv3.seams [--root REPO]        (exit 1 with every broken seam listed; short3.sh runs it first)
"""
import argparse
import importlib.util
import json
import os
import re
import shlex
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
MODULES = ["catalogue", "script", "translate", "plan", "review"]
GONE = ["capture", "search", "predicates", "mocklogs"]
MAPS = {"hell", "forest", "marble"}
POVS = {"guard", "runner"}
TICKS = {"hit", "shove", "out", "go"}
APPROVED_KEYS = {"project", "entry", "said", "capture", "tape", "expect", "seconds", "in", "ticks"}
SHOT_KEYS = ["id", "line", "text", "note", "stage", "pov", "dials", "approved", "same_take_as", "beat", "card", "needs_stage", "why"]
PLAN_READS = ["stage", "pov", "dials", "approved", "same_take_as", "beat", "card"]
ENTRY_FIELDS = ["said:", "capture:", "tape:", "expect:", "seconds:", "in:", "refilm:", "hud:"]
TABLE_COLS = ["line", "clip", "in", "len", "fit", "speed", "text", "card"]
FIT_MODES = ["line", "trim", "nohold", "wait", "window", "beat"]


def read(root, rel):
    return open(os.path.join(root, rel), encoding="utf-8").read()


def exists(root, rel):
    return os.path.isfile(os.path.join(root, rel))


def load(root, rel, name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(root, rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def entry_field(src, entry, field):
    """One `field:` line of brief entry `## <entry>`, else None."""
    m = re.search(r"^## %s\n(.*?)(?=^## |\Z)" % re.escape(str(entry)), src, re.S | re.M)
    if not m:
        return None
    f = re.search(r"^%s:[ \t]*(.*?)[ \t]*$" % re.escape(field), m.group(1), re.M)
    return f.group(1) if f else None


def capture_opts(capture):
    """`--k=v` options of a run_clip capture line, `--set=` split into its own dials."""
    opts, dials = {}, {}
    for tok in shlex.split(capture or ""):
        if tok.startswith("--") and "=" in tok:
            k, v = tok[2:].split("=", 1)
            opts[k] = v
    for kv in opts.get("set", "").split(";"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            dials[k.strip()] = v
    return opts, dials


def check_stages(root, out):
    rel = "tools/content/sv3/stages.json"
    if not exists(root, rel):
        out.append("stages: no %s (sv3.catalogue writes it; translate and plan read it)" % rel)
        return
    d = json.loads(read(root, rel))
    stages = d.get("stages")
    if not isinstance(stages, dict) or not isinstance(d.get("uncatalogued"), list):
        out.append("stages: stages.json needs {stages: {...}, uncatalogued: [...]}")
        return
    paths = read(root, "tools/capture/shot_paths.gd")
    known = read(root, "tools/capture/stage_driver.gd") + read(root, "tools/capture/run_clip.gd")
    for name, st in stages.items():
        if not exists(root, "tools/capture/stages/%s.gd" % name) and '"%s"' % name not in known:
            out.append("stages: %s is neither tools/capture/stages/%s.gd nor a stage_driver/run_clip stage" % (name, name))
        if st.get("map") not in MAPS:
            out.append("stages: %s map %r is not one of %s" % (name, st.get("map"), sorted(MAPS)))
        if '"%s"' % st.get("shot") not in paths:
            out.append("stages: %s shot %r is not a shot_paths.gd path" % (name, st.get("shot")))
        if not set(st.get("povs") or []) <= POVS:
            out.append("stages: %s povs %s outside %s" % (name, st.get("povs"), sorted(POVS)))
        if not isinstance(st.get("dials"), dict) or not isinstance(st.get("for_shorts"), bool):
            out.append("stages: %s needs dials {} and for_shorts true|false" % name)
        if name.startswith("trailer_") and st.get("for_shorts"):
            out.append("stages: %s is trailer footage; for_shorts must be false (decision 370)" % name)
        for e in st.get("approved") or []:
            where = "stages: %s approved %s#%s" % (name, e.get("project"), e.get("entry"))
            if set(e) != APPROVED_KEYS:
                out.append("%s keys %s, contract %s" % (where, sorted(set(e)), sorted(APPROVED_KEYS)))
            if not set(e.get("ticks") or {}) <= TICKS:
                out.append("%s ticks %s outside %s" % (where, sorted(e.get("ticks") or {}), sorted(TICKS)))
            brief = "tools/content/projects/%s.md" % e.get("project")
            if not exists(root, brief):
                out.append("%s: no %s" % (where, brief))
                continue
            cap = entry_field(read(root, brief), e.get("entry"), "capture")
            if cap is None:
                out.append("%s: the brief has no ## %s with a capture: line" % (where, e.get("entry")))
            elif cap.strip() != (e.get("capture") or "").strip():
                out.append("%s: capture is not the brief's line verbatim" % where)
            opts, dials = capture_opts(e.get("capture"))
            if opts.get("stage", name) != name:
                out.append("%s: capture names --stage=%s" % (where, opts.get("stage")))
            for k in st.get("dials") or {}:
                if k not in dials:
                    out.append("%s: dial %r is not in the capture's --set= (plan replaces it there)" % (where, k))


def check_modules(root, out):
    for m in MODULES:
        if not exists(root, "tools/content/sv3/%s.py" % m):
            out.append("modules: tools/content/sv3/%s.py is missing" % m)
    for m in GONE:
        if exists(root, "tools/content/sv3/%s.py" % m):
            out.append("modules: sv3/%s.py is the removed capture/search path; delete it" % m)
    for f in sorted(os.listdir(os.path.join(root, "tools/content/sv3"))):
        if f.endswith(".py"):
            src = read(root, "tools/content/sv3/" + f)
            for m in GONE:
                if re.search(r"\bsv3(?:\.| import )%s\b" % m, src):
                    out.append("modules: sv3/%s still imports sv3.%s" % (f, m))


def check_shots(root, out):
    """shots.json: translate writes every contract key, plan reads the ones it needs."""
    for mod, keys in (("translate", SHOT_KEYS), ("plan", PLAN_READS)):
        rel = "tools/content/sv3/%s.py" % mod
        if not exists(root, rel):
            continue
        src = read(root, rel)
        for k in keys:
            if '"%s"' % k not in src:
                out.append("shots: sv3/%s.py never names shots.json key %r" % (mod, k))
        if "stages" not in src:
            out.append("shots: sv3/%s.py never reads stages.json" % mod)
    if exists(root, "tools/content/sv3/plan.py"):
        src = read(root, "tools/content/sv3/plan.py")
        for f in ENTRY_FIELDS:
            if f not in src:
                out.append("plan: plan.py never writes the entry field %r (haters_final.md format)" % f)
        if "words" not in src:
            out.append("plan: plan.py never reads words.json (clip in = tick - word offset)")


def check_table(root, out):
    """The contract's `## script <tag>` table goes through brief.py and assemble.py's parsers."""
    sys.path.insert(0, os.path.join(root, "tools/content/pc"))
    brief = load(root, "tools/content/pc/brief.py", "brief")
    asm = load(root, "tools/content/pc/assemble.py", "assemble")
    sys.path.pop(0)
    asm_src = read(root, "tools/content/pc/assemble.py")
    for mode in FIT_MODES:
        if '"%s"' % mode not in asm_src:
            out.append("table: assemble.py no longer knows fit %r" % mode)
    table = ("# x\n\n## script v1\nvoice: en-US-AndrewNeural +5%\n| " + " | ".join(TABLE_COLS) + " |\n"
             "| L1 | cuts/01.mp4 | 1.2 | 3.4 | line | | He gets shot. | |\n"
             "| end | title | | 1.0 | | | beta link in bio | |\n")
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(table)
    try:
        parsed = brief.parse(f.name)["scripts"]["v1"]
    finally:
        os.unlink(f.name)
    rows = {r["line"]: r for r in parsed["rows"]}
    if set(rows) != {"L1", "end"}:
        out.append("table: brief.parse read rows %s from the contract table" % sorted(rows))
        return
    for c in TABLE_COLS:
        if c not in rows["L1"]:
            out.append("table: brief.parse drops column %r" % c)
    try:
        mode, _ = asm.parse_fit(rows["L1"]["fit"])
        if mode not in FIT_MODES:
            out.append("table: fit %r is not an assemble mode" % mode)
        asm.parse_parts(rows["L1"]["clip"])
        float(rows["L1"]["in"]), float(rows["L1"]["len"]), float(rows["end"]["len"])
        asm.parse_card(rows["L1"].get("card", ""))
    except (SystemExit, ValueError) as e:
        out.append("table: assemble.py refuses the contract table: %s" % e)
    if rows["end"]["clip"].strip().lower() != "title":
        out.append("table: the card row must be a title row")
    if [r["line"] for r in brief.voice_rows(parsed)] != ["L1"]:
        out.append("table: brief.voice_rows would speak %s, not ['L1']" % [r["line"] for r in brief.voice_rows(parsed)])


def check_clis(root, out):
    sh = read(root, "tools/content/short3.sh")
    if not re.search(r"\bstep seams\b", sh):
        out.append("cli: short3.sh does not run sv3.seams first")
    for word in ("sv3 capture", "sv3 search", "--intent", "seat_intent", "seat-intent", "--pool"):
        if word in sh:
            out.append("cli: short3.sh still names %r (the stage path replaced it)" % word)
    order = [m.group(1) for m in re.finditer(r"\bstep[ \t]+(\w+)", sh)]
    if "words" in order and "plan" in order and order.index("words") > order.index("plan"):
        out.append("cli: short3.sh runs plan before words (plan reads words.json)")
    for m in re.finditer(r"\bstep[ \t]+(\w+)[ \t]+sv3[ \t]+(\w+)([^\n]*)", sh):
        step, mod, rest = m.groups()
        if not exists(root, "tools/content/sv3/%s.py" % mod):
            out.append("cli: short3.sh step %s calls sv3.%s, which does not exist" % (step, mod))
            continue
        src = read(root, "tools/content/sv3/%s.py" % mod)
        passed = set(re.findall(r"(--[a-z-]+)", rest))
        for flag in sorted(passed):
            if '"%s"' % flag not in src:
                out.append("cli: short3.sh passes %s to sv3.%s, which has no such flag" % (flag, mod))
        for flag in re.findall(r'add_argument\("(--[a-z-]+)"[^)]*required=True', src):
            if flag not in passed:
                out.append("cli: sv3.%s requires %s, short3.sh does not pass it" % (mod, flag))
    for script in ("voice.sh", "short.sh"):
        for m in re.finditer(r'"\$\{CONTENT_DIR\}/%s" "\$\{NAME\}"([^\n]*)' % re.escape(script), sh):
            for flag in re.findall(r"(--[a-z-]+)", m.group(1)):
                if "%s)" % flag not in read(root, "tools/content/" + script):
                    out.append("cli: short3.sh passes %s to %s, which does not take it" % (flag, script))
    if "--smoke-only" in sh and "exit 0" not in read(root, "tools/content/short.sh").split("SMOKE_ONLY}\" = 1", 1)[-1][:200]:
        out.append("cli: short.sh --smoke-only no longer exits after the smoke loop")
    for py in ("voice.py", "assemble.py", "brief.py", "card.py"):
        if not exists(root, "tools/content/pc/" + py):
            out.append("cli: tools/content/pc/%s is missing" % py)
    if "pull_words" in sh and "words.json" not in read(root, "tools/content/pc/voice.py"):
        out.append("cli: short3.sh pulls voice/words.json, voice.py does not write it")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=REPO)
    a = ap.parse_args(argv)
    root = os.path.abspath(a.root)
    out = []
    for check in (check_modules, check_stages, check_shots, check_table, check_clis):
        try:
            check(root, out)
        except Exception as e:  # noqa: BLE001 -- a check that cannot run is a broken seam too
            out.append("%s: %s: %s" % (check.__name__, type(e).__name__, e))
    if out:
        print("SEAMS BROKEN (%d):\n  " % len(out) + "\n  ".join(out))
        return 1
    print("seams: ok (%s)" % root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
