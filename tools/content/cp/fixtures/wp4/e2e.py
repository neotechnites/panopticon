"""Orchestrator end to end on fixtures: stand-in plan/voice/render modules, the real review, gates and deliver.
Render serves cut A first and cut B after a fix round: `python -m cp.fixtures.wp4.e2e <cutA.mp4> <cutB.mp4> [--gemini-review]`."""
import json
import os
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
OK = {g: (lambda ctx: (True, "fixture stand-in")) for g in
      ("G1", "G1b", "G2", "G3", "G4", "G5", "G6", "G6b", "G7", "G8", "G9", "G10", "G11", "G13")}


def fake(name, fn):
    m = types.ModuleType(f"cp.{name}")
    m.main, m.GATES = fn, OK
    sys.modules[f"cp.{name}"] = m


def main():
    cut_a, cut_b = sys.argv[1], sys.argv[2]
    work = tempfile.mkdtemp(prefix="cp_e2e_")
    spec = os.path.join(work, "cp_wp4_fixture.md")
    open(spec, "w").write("# cp_wp4_fixture\nkind: short\n")
    plan = json.load(open(os.path.join(HERE, "portal_spin", "plan.json")))
    plan.update(name="cp_wp4_fixture", counts={"reuse": len(plan["lines"]), "capture": 0})
    for l in plan["lines"]:
        l["action"] = "reuse"
    calls = []

    def f_plan(argv):
        json.dump(plan, open(os.path.join(argv[argv.index("--out") + 1], "plan.json"), "w"), indent=1)

    def f_voice(argv):
        d = argv[argv.index("--out") + 1]
        os.makedirs(d, exist_ok=True)
        json.dump({"engine": "edge-tts", "voice": "en-US-AndrewNeural", "rate": "+5%", "lines": {}},
                  open(os.path.join(d, "manifest.json"), "w"))

    def f_render(argv):
        calls.append(argv)
        out = argv[argv.index("--out") + 1]
        json.dump({"lines": [], "final": cut_b if "--only" in argv else cut_a},
                  open(os.path.join(out, "edl.json"), "w"))

    def f_capture(argv):
        only = argv[argv.index("--only") + 1].split(",")
        calls.append(["capture", "--only", ",".join(only)])
        for lid in only:
            d = os.path.join(work, "cp_wp4_fixture", "takes", lid)
            os.makedirs(d, exist_ok=True)
            json.dump({"line": lid, "path": cut_b, "w": 1080, "h": 1920, "fps": 60, "commit": "fixture",
                       "t0": 0, "t1": 1}, open(os.path.join(d, "take.json"), "w"))

    fake("capture", f_capture)
    fake("plan", f_plan)
    fake("voice", f_voice)
    fake("render", f_render)
    from cp import preflight, run
    preflight.CAPTURE = []                 # no virtual monitor until WP2 installs it
    run.take_check = lambda b, ids: {}     # stand-in takes are whole cuts, not takes of one note
    rc = run.main(["short", spec] + sys.argv[3:])
    print("calls:", [" ".join(a[a.index("--only") - (a[0] == "capture"):a.index("--only") + 2])
                      if "--only" in a else "render full" for a in calls])
    print("rc", rc, "work", work)
    return rc


if __name__ == "__main__":
    sys.exit(main())
