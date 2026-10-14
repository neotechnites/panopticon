#!/usr/bin/env python3
"""refilm_v61.py: build rough_v61_beats from the v61 Movie Maker takes (refilm_v60.py film) on v60's edit.

  check    pull the new takes' thumbnails and compare each one's motion with its v60 take (same timing or not)
  edit     build rough_v61_beats.mp4 on the PC and copy it to the Mac

0-1851 keep v60's take frames. From the marble hit to the end card the run is recut (Ryan v60: jumps, held frames):
the beach starts on its first running frame, beach to marble at one clock (2.50 s, both heads steady), the portal's
held frames and the room's wait-and-snap fall in the teleport cut, the shover's frozen view is cut to the throw.
"""
import os
import subprocess
import sys

import numpy as np

import refilm_v60 as R

TAG = "rough_v61_beats"
WORK = os.path.join(R.RENDERS, "v61_work")
OLD = os.path.join(R.RENDERS, "v60_work")
# (name, out a, out b exclusive, shot, first take frame). Marble take frame = clock frame - 70, beach take frame = clock frame.
NEW = [("marble_scope_hit", 1852, 2032, "10br", 60),   # hit stays on 1986 (take 194)
       ("portal_beach", 2032, 2129, "22", 53),         # clock 53-149: running from its first frame
       ("portal_marble", 2129, 2195, "12sr", 80),      # clock 150-215: last frame before the teleport
       ("portal_room", 2195, 2242, "12sr", 163),       # first frame square to the guard; shove (take 202) on 2234
       ("guard_flight", 2242, 2317, "12sr", 221)]      # the cinematic's first frame
RECUT = {"marble_scope_hit", "portal_beach", "portal_marble", "portal_room"}


def v60_table():
    table = {}
    for line in open(os.path.join(OLD, "rough_v60_beats_edit.md")):
        c = [x.strip() for x in line.split("|")]
        if len(c) > 6 and c[1] not in ("segment", "---") and c[3] != "v59":
            table[c[1]] = int(c[4].split("-")[0])
    return table


def plan():
    sp = R.spec()
    table = v60_table()
    out = []
    for seg in sp["segments"]:
        if seg["name"] in RECUT:
            continue
        if seg.get("from_base"):
            out.append({"seg": seg, "kind": "base"})
        else:
            out.append({"seg": seg, "kind": "take", "idx0": table[seg["name"]], "d": 0, "how": "v60 frames", "detail": ""})
    for name, a, b, shot, i0 in NEW:
        out.append({"seg": {"name": name, "out": [a, b], "shot": shot}, "kind": "take", "idx0": i0, "d": 0, "how": "v61 recut", "detail": ""})
    out.sort(key=lambda i: i["seg"]["out"][0])
    for prev, nxt in zip(out, out[1:]):
        assert prev["seg"]["out"][1] == nxt["seg"]["out"][0], (prev["seg"]["name"], nxt["seg"]["name"])
    assert out[-1]["seg"]["out"][1] == sp["frames"]
    return sp, out


def thumbs():
    os.makedirs(WORK, exist_ok=True)
    shots = sorted({s["shot"] for s in R.spec()["segments"] if "shot" in s})
    ps = ["$ErrorActionPreference='Stop'", "New-Item -ItemType Directory -Force C:\\Users\\ddd\\r61thumbs | Out-Null"]
    for shot in shots:
        ps.append("ffmpeg -hide_banner -loglevel error -y -i '%s\\cuts\\%s.mp4' -vf scale=96:54:flags=area,format=gray -f rawvideo C:\\Users\\ddd\\r61thumbs\\%s.gray" % (R.PC_RENDERS, R.pad2(shot), shot))
    R.pc_ps("\n".join(ps) + "\n", "refilm_v61_thumbs.ps1")
    out = {}
    for shot in shots:
        dest = os.path.join(WORK, "%s.gray" % shot)
        subprocess.run(["scp", "-q", "-i", R.KEY, "%s:C:/Users/ddd/r61thumbs/%s.gray" % (R.HOST, shot), dest], check=True)
        out[shot] = np.fromfile(dest, np.uint8).reshape(-1, 54, 96).astype("float32")
    R.pc_ps("Remove-Item C:\\Users\\ddd\\r61thumbs -Recurse -Force\n", "refilm_v61_clean.ps1")
    return out


def check():
    """Per take: frame count and the lag that best matches its motion (frame diffs) to the v60 take's; 0 = same timing."""
    new = thumbs()
    for shot, f in sorted(new.items()):
        old = np.fromfile(os.path.join(OLD, "%s.gray" % shot), np.uint8).reshape(-1, 54, 96).astype("float32")
        a, b = np.abs(np.diff(f, axis=0)).mean(axis=(1, 2)), np.abs(np.diff(old, axis=0)).mean(axis=(1, 2))
        n = min(len(a), len(b))
        best = max(range(-6, 7), key=lambda k: np.corrcoef(a[max(0, k):n + min(0, k)], b[max(0, -k):n - max(0, k)])[0, 1])
        print("%-5s %4d frames (v60 %4d)  motion lag %+d" % (shot, len(f), len(old), best))


def edit():
    sp, items = plan()
    os.makedirs(WORK, exist_ok=True)
    graph, report, cuts = R.make_graph(items, "grade_hell.cube")
    open(os.path.join(WORK, TAG + ".graph.txt"), "w").write(graph)
    open(os.path.join(WORK, "grade_hell.cube"), "w").write(R.lut_cube(sp["grade_hell"]))
    open(os.path.join(WORK, TAG + "_edit.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    for f in ("grade_hell.cube", TAG + ".graph.txt"):
        subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(WORK, f), "%s:C:/Users/ddd/r61build_%s" % (R.HOST, f)], check=True)
    subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(R.RENDERS, sp["base"]), "%s:C:/Users/ddd/r61build_base.mp4" % R.HOST], check=True)
    inp = " ".join("-i '%s\\cuts\\%s.mp4'" % (R.PC_RENDERS, R.pad2(s)) for s in cuts)
    ps = ["$ErrorActionPreference='Stop'", "Set-Location C:\\Users\\ddd", "Copy-Item r61build_grade_hell.cube grade_hell.cube -Force",
          "ffmpeg -hide_banner -loglevel error -y -i r61build_base.mp4 %s -/filter_complex r61build_%s.graph.txt -map '[v]' -map 0:a -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -c:a copy -movflags +faststart '%s\\final\\%s.mp4'" % (inp, TAG, R.PC_RENDERS, TAG),
          "Copy-Item r61build_%s.graph.txt '%s\\final\\master\\%s.graph.txt' -Force" % (TAG, R.PC_RENDERS, TAG),
          "Remove-Item r61build_*, grade_hell.cube -Force"]
    R.pc_ps("\n".join(ps) + "\n", "refilm_v61_build.ps1")
    subprocess.run(["scp", "-q", "-i", R.KEY, "%s:%s/final/%s.mp4" % (R.HOST, R.PC_RENDERS.replace("\\", "/"), TAG), os.path.join(R.RENDERS, TAG + ".mp4")], check=True)
    R.pc_ps("Remove-Item C:\\Users\\ddd\\refilm_v61_*.ps1 -Force -ErrorAction SilentlyContinue\n", "refilm_v61_clean.ps1")
    print(os.path.join(R.RENDERS, TAG + ".mp4"))


if __name__ == "__main__":
    {"check": check, "edit": edit}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
