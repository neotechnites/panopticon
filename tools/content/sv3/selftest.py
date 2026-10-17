"""Offline check of the stage path: script -> translate (fixture = committed model output) -> plan on mock words -> the table parses.
    python -m sv3.selftest
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EX = os.path.join(HERE, "examples")
STAGES = os.path.join(HERE, "stages.json")
PY = sys.executable
POD = os.path.expanduser("~/Documents/senate/domains/panopticon/data/plan/shorts-v3/scripts_9_10_11.md")
SCRIPTS = {
    "ragdoll": [os.path.join(EX, "ragdoll.md")],
    "short9": [POD, "--section", "Short 9"],
    "short10": [POD, "--section", "Short 10"],
    "short11": [POD, "--section", "Short 11"],
}


def mock_words(spec, path):
    """A voice no one spoke: 0.32 s a word, so plan has line lengths and beat-word times."""
    words = {}
    for e in spec:
        if e.get("beat") or not e.get("text"):
            continue
        ws, t = [], 0.0
        for w in e["text"].split():
            ws.append({"word": w, "t": round(t, 3), "dur": 0.28})
            t += 0.32
        words[e["id"]] = {"file": e["id"] + ".wav", "dur": round(t + 0.2, 3), "lead_trimmed": 0.0, "words": ws}
    json.dump(words, open(path, "w"))


def run(args):
    r = subprocess.run([PY, "-m"] + args, capture_output=True, text=True, cwd=os.path.dirname(HERE))
    return r.returncode, r.stdout + r.stderr


def main():
    if not os.path.exists(STAGES):
        print("SELFTEST FAILED\nno %s (run sv3.catalogue)" % STAGES)
        return 1
    sys.path.insert(0, os.path.join(os.path.dirname(HERE), "pc"))
    import brief as B
    work = tempfile.mkdtemp(prefix="sv3_selftest_")
    failures = []
    for name, src in SCRIPTS.items():
        d = os.path.join(work, name)
        os.makedirs(d)
        spec, shots, words, brief = (os.path.join(d, f) for f in ("spec.json", "shots.json", "words.json", "brief.md"))
        fixture = os.path.join(EX, name + ".shots.json")
        if not os.path.exists(fixture):
            failures.append("%s: no fixture %s" % (name, fixture))
            continue
        open(brief, "w").write("# %s\nkind: short\n" % name)
        code, out = run(["sv3.script"] + src + ["--out", spec])
        if code:
            failures.append("%s sv3.script: %s" % (name, out[-800:]))
            continue
        mock_words(json.load(open(spec)), words)
        for st in (["sv3.translate", spec, "--stages", STAGES, "--out", shots, "--fixture", fixture],
                   ["sv3.plan", shots, "--stages", STAGES, "--words", words, "--brief", brief, "--tag", "v1"]):
            code, out = run(st)
            if code:
                failures.append("%s %s exit %d:\n%s" % (name, st[0], code, out[-1500:]))
                break
        else:
            table = B.parse(brief)["scripts"].get("v1")
            if not table or not table["rows"]:
                failures.append("%s: plan wrote no ## script v1 rows" % name)
            else:
                print("%s: ok (%d rows)" % (name, len(table["rows"])))
    if failures:
        print("SELFTEST FAILED\n" + "\n".join(failures))
        return 1
    print("SELFTEST OK (%s)" % work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
