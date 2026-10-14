#!/usr/bin/env python3
"""refilm_v64.py: rough_v64_beats = v63 with every shot holding a death refilmed on the corpse-culling fix (a limp body stays drawn).

Same take frames as v61/v62; every other frame and the audio are v63's own.
"""
import os
import subprocess
import sys

import refilm_v61 as V61

R = V61.R
TAG = "rough_v64_beats"
BASE = "rough_v63_beats.mp4"
WORK = os.path.join(R.RENDERS, "v64_work")
REFILMED = {"1r", "2r", "5gr", "5hr", "20", "10br", "12sr"}


def plan():
    sp, items = V61.plan()
    for item in items:
        if item["kind"] == "take" and item["seg"]["shot"] not in REFILMED:
            item["kind"] = "base"
    return sp, items


def edit():
    sp, items = plan()
    os.makedirs(WORK, exist_ok=True)
    graph, report, cuts = R.make_graph(items, "grade_hell.cube")
    report = [l.replace("| v59 |", "| v63 |") for l in report]
    open(os.path.join(WORK, TAG + ".graph.txt"), "w").write(graph)
    open(os.path.join(WORK, "grade_hell.cube"), "w").write(R.lut_cube(sp["grade_hell"]))
    open(os.path.join(WORK, TAG + "_edit.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    for f in ("grade_hell.cube", TAG + ".graph.txt"):
        subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(WORK, f), "%s:C:/Users/ddd/r64build_%s" % (R.HOST, f)], check=True)
    subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(R.RENDERS, BASE), "%s:C:/Users/ddd/r64build_base.mp4" % R.HOST], check=True)
    inp = " ".join("-i '%s\\cuts\\%s.mp4'" % (R.PC_RENDERS, R.pad2(s)) for s in cuts)
    ps = ["$ErrorActionPreference='Stop'", "Set-Location C:\\Users\\ddd", "Copy-Item r64build_grade_hell.cube grade_hell.cube -Force",
          "ffmpeg -hide_banner -loglevel error -y -i r64build_base.mp4 %s -/filter_complex r64build_%s.graph.txt -map '[v]' -map 0:a -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -c:a copy -movflags +faststart '%s\\final\\%s.mp4'" % (inp, TAG, R.PC_RENDERS, TAG),
          "Copy-Item r64build_%s.graph.txt '%s\\final\\master\\%s.graph.txt' -Force" % (TAG, R.PC_RENDERS, TAG),
          "Remove-Item r64build_*, grade_hell.cube -Force"]
    R.pc_ps("\n".join(ps) + "\n", "refilm_v64_build.ps1")
    subprocess.run(["scp", "-q", "-i", R.KEY, "%s:%s/final/%s.mp4" % (R.HOST, R.PC_RENDERS.replace("\\", "/"), TAG), os.path.join(R.RENDERS, TAG + ".mp4")], check=True)
    R.pc_ps("Remove-Item C:\\Users\\ddd\\refilm_v64_*.ps1 -Force -ErrorAction SilentlyContinue\n", "refilm_v64_clean.ps1")
    print(os.path.join(R.RENDERS, TAG + ".mp4"))


if __name__ == "__main__":
    {"edit": edit, "plan": lambda: print("\n".join("%s %s %s" % (i["seg"]["name"], i["seg"]["out"], i["kind"]) for i in plan()[1]))}.get(
        sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
