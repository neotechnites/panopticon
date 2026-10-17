"""Static seam checks for the shorts v3 pipeline: every name one side writes and another reads, in < 5 s, no PC, no model.

    python -m sv3.seams [--root REPO]        (exit 1 with every broken seam listed; short3.sh runs it first)

Seams: step vocabulary (schema regexes vs seat_intent.gd's parser), predicates (PREDICATE_DOC vs evaluators vs translate
FIELDS), events and vis keys (run_clip.gd vs schema/predicates), plan.json keys (plan.py vs capture.py/search.py), pulled
files (capture.py vs run_clip.gd/pc_rough vs predicates.py), the `## script` table (edl.py rows through brief.py and
assemble.py's parsers), the CLIs short3.sh calls (modules, flags, required flags), and the sync offset on the clip time.
"""
import argparse
import importlib.util
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))

RUNNER_EXAMPLES = ["run", "run:3", "stop", "cover:at:3", "shove_when_rival_within:3", "shove_when_rival_within:3:8",
                   "shove_when_rival_cover:3:6", "look:tower:2", "look:portal", "portal", "wait:3", "brawl", "idle", "idle:2"]
GUARD_EXAMPLES = ["wait:6", "scope", "miss:2", "hit", "idle"]
NOT_STEPS = ["fly", "run:fast", "look:lava", "shove", "cover", "miss", "hit:2"]
VIS_SAMPLE_KEYS = ["t", "cam", "scoped", "bodies", "cam_pos", "landmarks"]
VIS_BODY_KEYS = ["id", "on", "h", "x", "y", "d", "occ", "state", "pos"]
FIT_MODES = ["line", "trim", "nohold", "wait", "window", "beat"]


def read(root, rel):
    return open(os.path.join(root, rel), encoding="utf-8").read()


def load(root, rel, name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(root, rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def gd_func(src, name):
    """The body of one GDScript function."""
    m = re.search(r"^(?:static )?func %s\(.*?(?=^(?:static )?func |\Z)" % re.escape(name), src, re.S | re.M)
    return m.group(0) if m else ""


def check_steps(root, S, out):
    gd = read(root, "tools/capture/seat_intent.gd")
    arms = set(re.findall(r'^\t\t"([a-z_]+)":', gd_func(gd, "_parse"), re.M))
    names = set(re.findall(r"(?:\^\(|(?<!tower)\|)([a-z][a-z_]*)", S.RUNNER_STEP + "|" + S.GUARD_STEP[2:]))   # each alternative's step name
    if arms != names:
        out.append("steps: seat_intent.gd parses %s, schema regexes name %s" % (sorted(arms - names) or "-", sorted(names - arms) or "-"))
    for st in RUNNER_EXAMPLES:
        if not re.match(S.RUNNER_STEP, st):
            out.append("steps: RUNNER_STEP rejects %r" % st)
    for st in GUARD_EXAMPLES:
        if not re.match(S.GUARD_STEP, st):
            out.append("steps: GUARD_STEP rejects %r" % st)
    for st in RUNNER_EXAMPLES + GUARD_EXAMPLES:
        if st.split(":")[0] not in arms:
            out.append("steps: seat_intent.gd has no arm for %r" % st)
    for st in NOT_STEPS:
        if re.match(S.RUNNER_STEP, st) or re.match(S.GUARD_STEP, st):
            out.append("steps: schema accepts %r, which is not a step" % st)
    for word in ("tower", "portal"):
        if word not in gd:
            out.append("steps: look:%s has no landmark in seat_intent.gd" % word)
    # the roster: the recorder names runners from 0; plan.py and the schema must agree with it
    rc = read(root, "tools/capture/run_clip.gd")
    if '"runner:%d" % k' not in gd_func(rc, "_name_the_bodies") or "k: int = 0" not in gd_func(rc, "_name_the_bodies"):
        out.append("roster: run_clip.gd no longer names runners runner:0.. in _name_the_bodies; schema/plan assume it")
    seats = {s for s in S.FILM["properties"]["seat"]["enum"] if s.startswith("runner")}
    plan_src = read(root, "tools/content/sv3/plan.py")
    plan_seats = set(re.findall(r'"(runner:\d)"', plan_src))
    if seats != plan_seats:
        out.append("roster: schema film.seat runners %s, plan.py picks from %s" % (sorted(seats), sorted(plan_seats)))
    if seats != set(S.FILM["properties"]["intents"]["properties"]) - {"guard"}:
        out.append("roster: schema film.seat runners differ from film.intents bodies")


def check_predicates(root, S, P, T, out):
    if set(S.PREDICATES) != set(P.EVAL):
        out.append("predicates: schema %s vs evaluators %s" % (sorted(set(S.PREDICATES) - set(P.EVAL)), sorted(set(P.EVAL) - set(S.PREDICATES))))
    doc = set(re.findall(r"^- ([a-z_]+)\(", S.PREDICATE_DOC, re.M))
    if doc != set(S.PREDICATES):
        out.append("predicates: PREDICATE_DOC lists %s, schema %s" % (sorted(doc - set(S.PREDICATES)), sorted(set(S.PREDICATES) - doc)))
    if set(T.FIELDS) != set(S.PREDICATES):
        out.append("predicates: translate.FIELDS %s vs schema %s" % (sorted(set(T.FIELDS) - set(S.PREDICATES)), sorted(set(S.PREDICATES) - set(T.FIELDS))))
    props = set(S.PREDICATE["properties"])
    for p, fields in T.FIELDS.items():
        if not fields <= props:
            out.append("predicates: translate.FIELDS[%s] uses %s, not in the schema" % (p, sorted(fields - props)))


def check_events_and_vis(root, S, out):
    rc = read(root, "tools/capture/run_clip.gd")
    emitted = set(re.findall(r'_ev\("([a-z_]+)"', rc))
    if emitted != set(S.EVENTS):
        out.append("events: run_clip.gd emits %s not in schema; schema names %s never emitted" % (
            sorted(emitted - set(S.EVENTS)) or "-", sorted(set(S.EVENTS) - emitted) or "-"))
    vis = gd_func(rc, "_sample_vis")
    for k in VIS_SAMPLE_KEYS + VIS_BODY_KEYS:
        if '"%s":' % k not in vis:
            out.append("vis: predicates read %r but run_clip._sample_vis never writes it" % k)
    if "k: int = 0" not in gd_func(rc, "_name_the_bodies"):
        out.append("roster: _name_the_bodies no longer starts runners at 0")


def check_plan_capture(root, out):
    plan_src = read(root, "tools/content/sv3/plan.py")
    cap_src = read(root, "tools/content/sv3/capture.py")
    se_src = read(root, "tools/content/sv3/search.py")
    m = re.search(r"matches\.append\(\{(.*?)\}\)\n", plan_src, re.S)
    emits = set(re.findall(r'"([a-z_]+)":', m.group(1))) if m else set()
    if not emits:
        out.append("plan: cannot find matches.append({...}) in plan.py")
    reads = set(re.findall(r'\bm(?:\.get\(|\[)"([a-z_]+)"', cap_src))
    loop = re.search(r"for k in \((.*?)\):\n\s+if m\.get\(k\)", cap_src)          # `for k in ("kill", "cam", "look"): if m.get(k)`
    reads |= set(re.findall(r'"([a-z_]+)"', loop.group(1))) if loop else set()
    se_reads = set(re.findall(r'\bm(?:\.get\(|\[)"([a-z_]+)"', se_src))
    for k in sorted(reads - emits - {"look"}):
        out.append("plan: capture.py reads m[%r], plan.py never emits it" % k)
    for k in sorted(emits - reads - se_reads - {"id", "lines", "source"}):
        out.append("plan: plan.py emits %r, nothing in capture.py/search.py reads it" % k)


def check_files(root, out):
    cap = read(root, "tools/content/sv3/capture.py")
    rc = read(root, "tools/capture/run_clip.gd")
    lib = read(root, "tools/content/lib.sh")
    pred = read(root, "tools/content/sv3/predicates.py")
    for name in ("events.jsonl", "vis.jsonl", "take.json"):
        if 'path_join("%s")' % name not in rc:
            out.append("files: capture.py pulls %s, run_clip.gd never writes it" % name)
        if '"%s"' % name not in cap:
            out.append("files: run_clip.gd writes %s, capture.py never pulls it" % name)
    if "${raw}.sync" not in lib:
        out.append("files: pc_rough no longer writes <raw>.sync")
    for suffix in (".take.json", ".events.jsonl", ".vis.jsonl", ".mkv.sync"):
        if 'fs + "%s"' % suffix not in pred:
            out.append("files: predicates.Recording does not read <seat>%s" % suffix)
        if '"%%s%s"' % suffix not in cap:
            out.append("files: capture.py never lands <seat>%s, predicates.py reads it" % suffix)
    if 'f.endswith(".take.json")' not in pred:
        out.append("files: load_pool does not accept <seat>.take.json")
    for k in ("--intent=", "--seat-intent=", "--record=", "--tape=", "--log=", "--sync="):
        if k not in cap:
            out.append("flags: capture.py no longer passes %s" % k)
        if '"%s"' % k[2:-1] not in rc:
            out.append("flags: run_clip.gd has no option %s" % k[2:-1])


def check_table(root, E, out):
    sys.path.insert(0, os.path.join(root, "tools/content/pc"))
    brief = load(root, "tools/content/pc/brief.py", "brief")
    asm = load(root, "tools/content/pc/assemble.py", "assemble")
    sys.path.pop(0)
    asm_src = read(root, "tools/content/pc/assemble.py")
    cols = [c.strip() for c in E.HEADER.strip().splitlines()[-1].strip("|").split("|")]
    reads = set(re.findall(r'row(?:\.get\(|\[)"([a-z_]+)"', asm_src)) | set(re.findall(r'r(?:\.get\(|\[)"([a-z_]+)"', read(root, "tools/content/pc/brief.py")))
    for c in cols:
        if c not in reads:
            out.append("table: edl.py writes column %r, assemble.py/brief.py never read it" % c)
    for mode in FIT_MODES:
        if '"%s"' % mode not in asm_src:
            out.append("table: assemble.py no longer knows fit %r" % mode)
    if "p.get(\"sync\"" not in read(root, "tools/content/sv3/edl.py") or "sync=rec.sync" not in read(root, "tools/content/sv3/search.py"):
        out.append("time: the clip time no longer adds the take's sync offset (search.py sync -> edl.py clip_cell)")
    spec = [{"id": "L1", "text": "He gets shot.", "note": "n", "beat": False, "same_take_as": None},
            {"id": "M2", "text": "", "note": "n", "beat": True, "same_take_as": None},
            {"id": "L3", "text": "card text", "note": "n", "beat": False, "same_take_as": None}]
    shots = [{"id": "L1", "line": "L1", "source": "match", "overlays": [{"kind": "comment_card", "at": "word:shot"}]},
             {"id": "M2", "line": "M2", "source": "match", "overlays": [{"kind": "gif_fade", "at": "t:0", "url": "http://x/a.gif", "seconds": 1.5}]},
             {"id": "L3", "line": "L3", "source": "card", "overlays": []}]
    edl = [{"id": "L1", "line": "L1", "file": "../_tapes/hell_seat_1/guard.mkv", "sync": 9.5, "in": 3.0, "len": 2.0, "fit": "line"},
           {"id": "M2", "line": "M2", "file": "../_tapes/hell_seat_1/guard.mkv", "sync": 9.5, "in": 8.0, "len": 2.5, "fit": "wait"},
           {"id": "L3", "line": "L3", "file": None, "sync": 0.0, "in": 0, "len": 1.5, "fit": "line"}]
    words = {"L1": {"dur": 1.2, "words": [{"word": "He", "t": 0}, {"word": "gets", "t": 0.3}, {"word": "shot.", "t": 0.6}]}}
    rows, problems = E.rows_for(edl, shots, spec, words, 0.25)
    if problems:
        out.append("table: edl.rows_for refused the fixture: %s" % problems)
        return
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write("# x\n\n## script v1\n" + E.HEADER.format(pad=0.25) + "\n".join(rows) + "\n")
    parsed = brief.parse(f.name)["scripts"]["v1"]
    os.unlink(f.name)
    if parsed["head"].get("captions") == "stack" and float(parsed["head"]["captions_band"].split()[0]) > asm.STACK_TOP_MAX:
        out.append("table: captions_band top is over assemble's STACK_TOP_MAX")
    for row in parsed["rows"]:
        key = row["line"]
        try:
            if row["clip"].strip().lower() == "title":
                float(row["len"] or 1.0)
                if not row["text"]:
                    out.append("table: %s is a title with no text" % key)
                continue
            mode, _ = asm.parse_fit(row["fit"] or "line")
            if mode not in FIT_MODES:
                out.append("table: %s fit %r is not an assemble mode" % (key, row["fit"]))
            for part in asm.parse_parts(row["clip"]):
                if part["in"] is None or part["len"] is None:
                    out.append("table: %s clip part %r has no in:len" % (key, part["path"]))
                if not (part["path"].startswith("../_tapes/") or re.match(r"^[A-Za-z]:", part["path"])):
                    out.append("table: %s clip %r is not under ../_tapes (assemble opens it from content/<project>)" % (key, part["path"]))
            if key == "L1" and abs(float(part["in"]) - (3.0 + 9.5)) > 1e-6:
                out.append("table: %s clip in %.3f is not log in + sync (12.5)" % (key, part["in"]))
            asm.parse_card(row.get("card", ""))
            gif = asm.parse_gif_fade(row.get("gif_fade", ""))
            if key == "M2" and not gif:
                out.append("table: the gif_fade overlay did not reach the gif_fade column")
            if key == "L1" and not row.get("card"):
                out.append("table: the comment_card overlay did not reach the card column")
        except SystemExit as e:
            out.append("table: assemble.py refuses row %s: %s" % (key, e))
    if not any(r["clip"].strip().lower() == "title" and r["line"] == "L3" for r in parsed["rows"]):
        out.append("table: a card line must become a title row")
    voiced = [r["line"] for r in brief.voice_rows(parsed)]
    if voiced != ["L1"]:
        out.append("table: brief.voice_rows would speak %s, the script's voice lines are ['L1']" % voiced)


def check_clis(root, out):
    sh = read(root, "tools/content/short3.sh")
    if not re.search(r"\bstep seams\b", sh):
        out.append("cli: short3.sh does not run sv3.seams first")
    for m in re.finditer(r"\bstep[ \t]+(\w+)[ \t]+sv3[ \t]+(\w+)([^\n]*)", sh):
        step, mod, rest = m.groups()
        path = os.path.join(root, "tools/content/sv3/%s.py" % mod)
        if not os.path.isfile(path):
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
    for script in ("voice.sh", "assemble.sh"):
        m = re.search(r'"\$\{CONTENT_DIR\}/%s" "\$\{NAME\}" (--\w+)' % re.escape(script), sh)
        if m and "%s)" % m.group(1) not in read(root, "tools/content/" + script):
            out.append("cli: short3.sh passes %s to %s, which does not take it" % (m.group(1), script))
    for py in ("voice.py", "assemble.py", "brief.py", "card.py"):
        if not os.path.isfile(os.path.join(root, "tools/content/pc", py)):
            out.append("cli: tools/content/pc/%s is missing" % py)
    if "pull_words" in sh and "words.json" not in read(root, "tools/content/pc/voice.py"):
        out.append("cli: short3.sh pulls voice/words.json, voice.py does not write it")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=REPO)
    a = ap.parse_args(argv)
    root = os.path.abspath(a.root)
    S = load(root, "tools/content/sv3/schema.py", "sv3_schema")
    P = load(root, "tools/content/sv3/predicates.py", "sv3_predicates")
    E = load(root, "tools/content/sv3/edl.py", "sv3_edl")
    sys.path.insert(0, os.path.join(root, "tools/content"))
    T = load(root, "tools/content/sv3/translate.py", "sv3_translate")
    sys.path.pop(0)
    out = []
    for check in (lambda o: check_steps(root, S, o), lambda o: check_predicates(root, S, P, T, o), lambda o: check_events_and_vis(root, S, o),
                  lambda o: check_plan_capture(root, o), lambda o: check_files(root, o), lambda o: check_table(root, E, o), lambda o: check_clis(root, o)):
        try:
            check(out)
        except Exception as e:  # noqa: BLE001 -- a check that cannot run is a broken seam too
            out.append("%s: %s" % (type(e).__name__, e))
    if out:
        print("SEAMS BROKEN (%d):\n  " % len(out) + "\n  ".join(out))
        return 1
    print("seams: ok (%s)" % root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
