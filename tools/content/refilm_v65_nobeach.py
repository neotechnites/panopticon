#!/usr/bin/env python3
"""refilm_v65_nobeach.py: rough_v65b_nobeach_beats = v65b with the three beach slots replaced (cut B, decision 384).

  film     sync the PC, film 14r, 11r and 23 with Movie Maker (shot.sh --movie; each runs its Mac expect smoke first)
  edit     build rough_v65_nobeach_beats.mp4 on the PC from v65 and the new cuts, copy it to the Mac
  check    full-fps frame sheets round every new cut, and per-frame PSNR against v65b outside the slots
"""
import os
import re
import subprocess
import sys

import refilm_v60 as R

TAG = "rough_v65b_nobeach_beats"
BASE = "rough_v65b_beats.mp4"
BASE_NAME = "v65b"
WORK = os.path.join(R.RENDERS, "v65nb_work")
# (name, out a, out b exclusive, shot, first take frame, grade). Every other frame is v65's.
# Beach scope -> hell scope: 14r fires on beat 33 (1014, take 3.133 s). Beach run -> 23: hits on beats 50 (1365) and 53 (1428).
# Portal runs -> lava (hop 3 lands on beat 83, 2048) to beat 85 (2090), then the marble run up to v65's own teleport frame (12sr 145).
NEW = [("hell_scope_b", 996, 1064, "14r", 53, "hell"),
       ("marble_far", 1324, 1449, "23", 44, None),
       ("lava_hops", 2010, 2090, "11r", 140, "hell"),
       ("portal_marble", 2090, 2195, "12sr", 41, None)]
FILM = ["14r", "11r", "23"]
MARKS = {"hell_scope_b": [996, 1014, 1040, 1064], "marble_far": [1324, 1365, 1428, 1449],
         "lava_hops": [2010, 2048, 2090], "portal_marble": [2090, 2137, 2195]}


def plan():
    items, at = [], 0
    for name, a, b, shot, i0, grade in NEW:
        if a > at:
            items.append({"seg": {"name": BASE_NAME, "out": [at, a]}, "kind": "base"})
        seg = {"name": name, "out": [a, b], "shot": shot}
        if grade:
            seg["grade"] = grade
        items.append({"seg": seg, "kind": "take", "idx0": i0, "d": 0, "how": "no-beach", "detail": ""})
        at = b
    items.append({"seg": {"name": BASE_NAME, "out": [at, 2648]}, "kind": "base"})
    return items


def film():
    subprocess.run([os.path.join(R.HERE, "sync.sh")], check=True)
    for shot in FILM:
        subprocess.run([os.path.join(R.HERE, "shot.sh"), "trailer_reveal", shot, "--movie"], check=True)


def edit():
    os.makedirs(WORK, exist_ok=True)
    graph, report, cuts = R.make_graph(plan(), "grade_hell.cube")
    report = [l.replace("| v59 |", "| %s |" % BASE_NAME).replace("v59 out", "out") for l in report]
    open(os.path.join(WORK, TAG + ".graph.txt"), "w").write(graph)
    open(os.path.join(WORK, "grade_hell.cube"), "w").write(R.lut_cube(R.spec()["grade_hell"]))
    open(os.path.join(WORK, TAG + "_edit.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    for f in ("grade_hell.cube", TAG + ".graph.txt"):
        subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(WORK, f), "%s:C:/Users/ddd/r65nb_%s" % (R.HOST, f)], check=True)
    subprocess.run(["scp", "-q", "-i", R.KEY, os.path.join(R.RENDERS, BASE), "%s:C:/Users/ddd/r65nb_base.mp4" % R.HOST], check=True)
    inp = " ".join("-i '%s\\cuts\\%s.mp4'" % (R.PC_RENDERS, R.pad2(s)) for s in cuts)
    ps = ["$ErrorActionPreference='Stop'", "Set-Location C:\\Users\\ddd", "Copy-Item r65nb_grade_hell.cube grade_hell.cube -Force",
          "ffmpeg -hide_banner -loglevel error -y -i r65nb_base.mp4 %s -/filter_complex r65nb_%s.graph.txt -map '[v]' -map 0:a -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -c:a copy -movflags +faststart '%s\\final\\%s.mp4'" % (inp, TAG, R.PC_RENDERS, TAG),
          "Copy-Item r65nb_%s.graph.txt '%s\\final\\master\\%s.graph.txt' -Force" % (TAG, R.PC_RENDERS, TAG),
          "Remove-Item r65nb_*, grade_hell.cube -Force"]
    R.pc_ps("\n".join(ps) + "\n", "refilm_v65nb_build.ps1")
    subprocess.run(["scp", "-q", "-i", R.KEY, "%s:%s/final/%s.mp4" % (R.HOST, R.PC_RENDERS.replace("\\", "/"), TAG), os.path.join(R.RENDERS, TAG + ".mp4")], check=True)
    R.pc_ps("Remove-Item C:\\Users\\ddd\\refilm_v65nb_*.ps1 -Force -ErrorAction SilentlyContinue\n", "refilm_v65nb_clean.ps1")
    print(os.path.join(R.RENDERS, TAG + ".mp4"))


def check():
    """Frame sheets (every frame, 12 either side of each cut and event) and PSNR to v65b per frame outside the slots."""
    out = os.path.join(R.RENDERS, "v65nb_proof")
    os.makedirs(out, exist_ok=True)
    new = os.path.join(R.RENDERS, TAG + ".mp4")
    for name, frames in MARKS.items():
        for f in frames:
            # Frames f-12 .. f+11, left to right, two rows: the cut or event frame opens the second row.
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", new, "-vf", "select='between(n,%d,%d)',scale=320:180,tile=12x2" % (f - 12, f + 11),
                            "-frames:v", "1", os.path.join(out, "%s_%d.png" % (name, f))], check=True)
    base = os.path.join(R.RENDERS, BASE)
    log = subprocess.run(["ffmpeg", "-v", "error", "-i", new, "-i", base, "-lavfi", "[0:v][1:v]psnr=stats_file=-", "-f", "null", "-"],
                         capture_output=True, text=True, check=True).stdout
    psnr = {}
    for line in log.splitlines():
        m = re.search(r"n:(\d+).*psnr_avg:(\S+)", line)
        if m:
            psnr[int(m.group(1)) - 1] = float(m.group(2)) if m.group(2) != "inf" else 99.0
    inside = lambda f: any(a <= f < b for _, a, b, _, _, _ in NEW)
    outside = [v for f, v in psnr.items() if not inside(f)]
    ins = [v for f, v in psnr.items() if inside(f)]
    worst = min(((v, f) for f, v in psnr.items() if not inside(f)))
    print("frames %d; outside the slots: min PSNR %.1f dB (frame %d), mean %.1f; inside: mean %.1f dB" % (
        len(psnr), worst[0], worst[1], sum(outside) / len(outside), sum(ins) / len(ins)))
    print("sheets in %s" % out)


if __name__ == "__main__":
    {"film": film, "edit": edit, "check": check,
     "plan": lambda: print("\n".join("%s %s %s %s" % (i["seg"]["name"], i["seg"]["out"], i["kind"], i.get("idx0", "")) for i in plan()))}.get(
        sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
