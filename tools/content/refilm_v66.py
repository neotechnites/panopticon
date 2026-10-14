#!/usr/bin/env python3
"""refilm_v66.py: rough_v66_beats = v65b with 2r's look-over tail (out 243-330) from 2v, where the eye lands on the card's eye-as-O.

2v is 2r's tape with --set=eye_frame; its take frames 0-128 are 2r's to the bit, so only out 243-330 change.
  edit    build on the PC (v64's graph and grade), copy to the Mac
"""
import os
import subprocess
import sys

import refilm_v60 as R

TAG = "rough_v66_beats"
BASE = "rough_v65b_beats.mp4"
WORK = os.path.join(R.RENDERS, "v66_work")
FIRST, CARD = 243, 331          # first out frame 2v differs from 2r; the title card's first frame
TAKE0 = 51                      # 2r's take frame at out 165 (v60 edit)


def plan():
    total = R.spec()["frames"]
    seg = {"name": "open_runner_eye", "out": [FIRST, CARD], "shot": "2v", "grade": "hell"}
    return [{"seg": {"name": "v65b_head", "out": [0, FIRST]}, "kind": "base"},
            {"seg": seg, "kind": "take", "idx0": TAKE0 + FIRST - 165, "d": 0, "how": "eye_frame", "detail": ""},
            {"seg": {"name": "v65b_rest", "out": [CARD, total]}, "kind": "base"}]


def edit():
    items = plan()
    os.makedirs(WORK, exist_ok=True)
    graph, report, cuts = R.make_graph(items, "grade_hell.cube")
    report = [l.replace("| v59 |", "| v65b |") for l in report]
    open(os.path.join(WORK, TAG + ".graph.txt"), "w").write(graph)
    open(os.path.join(WORK, "grade_hell.cube"), "w").write(R.lut_cube(R.spec()["grade_hell"]))
    open(os.path.join(WORK, TAG + "_edit.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    for f in ("grade_hell.cube", TAG + ".graph.txt"):
        subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(WORK, f), "%s:C:/Users/ddd/r66build_%s" % (R.HOST, f)], check=True)
    subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(R.RENDERS, BASE), "%s:C:/Users/ddd/r66build_base.mp4" % R.HOST], check=True)
    inp = " ".join("-i '%s\\cuts\\%s.mp4'" % (R.PC_RENDERS, R.pad2(s)) for s in cuts)
    ps = ["$ErrorActionPreference='Stop'", "Set-Location C:\\Users\\ddd", "Copy-Item r66build_grade_hell.cube grade_hell.cube -Force",
          "ffmpeg -hide_banner -loglevel error -y -i r66build_base.mp4 %s -/filter_complex r66build_%s.graph.txt -map '[v]' -map 0:a -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -c:a copy -movflags +faststart '%s\\final\\%s.mp4'" % (inp, TAG, R.PC_RENDERS, TAG),
          "Copy-Item r66build_%s.graph.txt '%s\\final\\master\\%s.graph.txt' -Force" % (TAG, R.PC_RENDERS, TAG),
          "Remove-Item r66build_*, grade_hell.cube -Force"]
    R.pc_ps("\n".join(ps) + "\n", "refilm_v66_build.ps1")
    subprocess.run(["scp", "-q", "-i", R.KEY, "%s:%s/final/%s.mp4" % (R.HOST, R.PC_RENDERS.replace("\\", "/"), TAG), os.path.join(R.RENDERS, TAG + ".mp4")], check=True)
    R.pc_ps("Remove-Item C:\\Users\\ddd\\refilm_v66_*.ps1 -Force -ErrorAction SilentlyContinue\n", "refilm_v66_clean.ps1")
    print(os.path.join(R.RENDERS, TAG + ".mp4"))


if __name__ == "__main__":
    {"edit": edit}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
