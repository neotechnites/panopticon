"""Offline check: script -> translate (fixture = the committed Gemini output) -> plan -> search on mock logs -> edl, all four scripts.
    python -m sv3.selftest
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EX = os.path.join(HERE, "examples")
PY = sys.executable
SCRIPTS = {
    "ragdoll": [os.path.join(EX, "ragdoll.md")],
    "short9": ["/Users/ryanwhitehead/Documents/senate/domains/panopticon/data/plan/shorts-v3/scripts_9_10_11.md", "--section", "Short 9"],
    "short10": ["/Users/ryanwhitehead/Documents/senate/domains/panopticon/data/plan/shorts-v3/scripts_9_10_11.md", "--section", "Short 10"],
    "short11": ["/Users/ryanwhitehead/Documents/senate/domains/panopticon/data/plan/shorts-v3/scripts_9_10_11.md", "--section", "Short 11"],
}


def mock_words(spec, path):
    """A voice no one spoke: 0.32 s a word, so the search has slot lengths and beat-word times."""
    words = {}
    for e in spec:
        if e["beat"] or not e["text"]:
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
    work = tempfile.mkdtemp(prefix="sv3_selftest_")
    pool = os.path.join(work, "pool")
    code, out = run(["sv3.mocklogs", pool])
    assert code == 0, out
    failures = []
    for name, src in SCRIPTS.items():
        d = os.path.join(work, name)
        os.makedirs(d)
        spec, shots, plan, edl, words, brief = (os.path.join(d, f) for f in ("spec.json", "shots.json", "plan.json", "edl.json", "words.json", "brief.md"))
        fixture = os.path.join(EX, name + ".shots.json")
        if not os.path.exists(fixture):
            failures.append("%s: no fixture %s" % (name, fixture))
            continue
        steps = [["sv3.script"] + src + ["--out", spec]]
        for st in steps:
            code, out = run(st)
            if code:
                failures.append("%s %s: %s" % (name, st[0], out[-800:]))
        mock_words(json.load(open(spec)), words)
        for st in (["sv3.translate", spec, "--out", shots, "--fixture", fixture],
                   ["sv3.plan", shots, "--pool", pool, "--out", plan, "--words", words],
                   ["sv3.search", plan, shots, "--pool", pool, "--words", words, "--out", edl],
                   ["sv3.edl", edl, shots, spec, "--brief", brief, "--tag", "v1", "--words", words]):
            code, out = run(st)
            if code:
                failures.append("%s %s exit %d:\n%s" % (name, st[0], code, out[-1500:]))
                break
        else:
            print("%s: ok (%d shots)" % (name, len(json.load(open(edl)))))
    if failures:
        print("SELFTEST FAILED\n" + "\n".join(failures))
        return 1
    print("SELFTEST OK (%s)" % work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
