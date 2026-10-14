#!/usr/bin/env python3
"""refilm_v67.py: rough_v67_beats = v66 with all of 2r (out 165-330) from 2v refilmed in the logo's older eye; v66's look-over and zoom.

Every other frame and the audio are v66's.
  edit    build on the PC (v64's graph and grade), copy to the Mac
"""
import os
import subprocess
import sys

import refilm_v60 as R

TAG = "rough_v67_beats"
BASE = "rough_v66_beats.mp4"
WORK = os.path.join(R.RENDERS, "v67_work")
FIRST, CARD = 165, 331          # 2r in the v60 edit; the title card's first frame
TAKE0 = 51                      # 2r's take frame at out 165 (v60 edit)


def plan():
    total = R.spec()["frames"]
    seg = {"name": "open_runner_eye", "out": [FIRST, CARD], "shot": "2v", "grade": "hell"}
    return [{"seg": {"name": "v66_head", "out": [0, FIRST]}, "kind": "base"},
            {"seg": seg, "kind": "take", "idx0": TAKE0 + FIRST - 165, "d": 0, "how": "old eye", "detail": ""},
            {"seg": {"name": "v66_rest", "out": [CARD, total]}, "kind": "base"}]


def edit():
    items = plan()
    os.makedirs(WORK, exist_ok=True)
    graph, report, cuts = R.make_graph(items, "grade_hell.cube")
    report = [l.replace("| v59 |", "| v66 |") for l in report]
    open(os.path.join(WORK, TAG + ".graph.txt"), "w").write(graph)
    open(os.path.join(WORK, "grade_hell.cube"), "w").write(R.lut_cube(R.spec()["grade_hell"]))
    open(os.path.join(WORK, TAG + "_edit.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    for f in ("grade_hell.cube", TAG + ".graph.txt"):
        subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(WORK, f), "%s:C:/Users/ddd/r67build_%s" % (R.HOST, f)], check=True)
    subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(R.RENDERS, BASE), "%s:C:/Users/ddd/r67build_base.mp4" % R.HOST], check=True)
    inp = " ".join("-i '%s\\cuts\\%s.mp4'" % (R.PC_RENDERS, R.pad2(s)) for s in cuts)
    ps = ["$ErrorActionPreference='Stop'", "Set-Location C:\\Users\\ddd", "Copy-Item r67build_grade_hell.cube grade_hell.cube -Force",
          "ffmpeg -hide_banner -loglevel error -y -i r67build_base.mp4 %s -/filter_complex r67build_%s.graph.txt -map '[v]' -map 0:a -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -c:a copy -movflags +faststart '%s\\final\\%s.mp4'" % (inp, TAG, R.PC_RENDERS, TAG),
          "Copy-Item r67build_%s.graph.txt '%s\\final\\master\\%s.graph.txt' -Force" % (TAG, R.PC_RENDERS, TAG),
          "Remove-Item r67build_*, grade_hell.cube -Force"]
    R.pc_ps("\n".join(ps) + "\n", "refilm_v67_build.ps1")
    subprocess.run(["scp", "-q", "-i", R.KEY, "%s:%s/final/%s.mp4" % (R.HOST, R.PC_RENDERS.replace("\\", "/"), TAG), os.path.join(R.RENDERS, TAG + ".mp4")], check=True)
    R.pc_ps("Remove-Item C:\\Users\\ddd\\refilm_v67_*.ps1 -Force -ErrorAction SilentlyContinue\n", "refilm_v67_clean.ps1")
    print(os.path.join(R.RENDERS, TAG + ".mp4"))


if __name__ == "__main__":
    {"edit": edit}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
