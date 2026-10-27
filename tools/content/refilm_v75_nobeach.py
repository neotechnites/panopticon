#!/usr/bin/env python3
r"""refilm_v75_nobeach.py: rough_v75_nobeach = v74_nobeach with every marble slot refilmed on main a7cc4164's marble.

Ryan 2026-10-26: "re-film all the marble scenes and create v75. Nothing about the geometry has changed so just rerun the
shots with the new map and make the new trailer. You can use Movie Maker for this, not screen capture." The same five
entries as v74 (5hw 23alt 10aw 10bw 12sv, copied as 5hw_75 ...), same tapes, in/seconds, first take frames and edit; the
cuts land as cuts\NN_75.mp4 so v74's stay. Every other frame and the audio are v74's.

  film   on the PC (PC_LOCAL=1, the trailer-v75 worktree): shot.sh --movie for the five entries, one Godot at a time;
         from the Mac: sync.sh then the same, as v74
  edit   build final\rough_v75_nobeach.mp4 from v74 and the five cuts (on the PC directly when run there)
  check  frame sheets round every cut and PSNR outside the slots (Mac)
"""
import os
import subprocess
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

PC = os.name == "nt"
WORKTREE = os.environ.get("PC_PROJECT", "C:\\dev\\worktrees\\trailer-v75")
R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live on the Mac (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v75_nobeach"
M.BASE = "rough_v74_nobeach.mp4"
M.BASE_NAME = "v74nb"
# (name, out a, out b exclusive, shot, first take frame, grade): v74's marble slots exactly as v71/v71_alt23/v73/v74 cut them.
M.NEW = [("marble_scope", 996, 1064, "5hw_75", 48, None),
         ("marble_far", 1324, 1449, "23alt_75", 44, None),
         ("marble_run", 1717, 1852, "10aw_75", 52, None),
         ("marble_scope_hit", 1852, 2010, "10bw_75", 60, None),
         ("portal_marble", 2152, 2195, "12sv_75", 103, None),
         ("portal_room", 2195, 2242, "12sv_75", 163, None),
         ("guard_flight", 2242, 2317, "12sv_75", 221, None)]
M.FILM = ["5hw_75", "23alt_75", "10aw_75", "10bw_75", "12sv_75"]
M.MARKS = {"marble_scope": [996, 1014, 1064], "marble_far": [1324, 1365, 1398, 1449], "marble_run": [1717, 1802, 1852],
           "marble_scope_hit": [1852, 1986, 2010], "portal_marble": [2152, 2195], "portal_room": [2242], "guard_flight": [2317]}


def film():
    if not PC:
        return M.film()
    env = dict(os.environ, PC_LOCAL="1", PC_PROJECT=WORKTREE, PC_BRANCH=os.environ.get("PC_BRANCH", "trailer-v75"))
    for shot in M.FILM:
        subprocess.run(["bash", os.path.join(R.HERE, "shot.sh"), "trailer_reveal", shot, "--movie"], check=True, env=env)


def edit():
    """The v74 graph with the five new cuts as its inputs: one lossless-to-H.264 encode, v74's audio copied."""
    if not PC:
        return M.edit()
    final = os.path.join(R.PC_RENDERS, "final")
    graph, report, cuts = R.make_graph(M.plan(), None)
    report = [l.replace("| v59 |", "| %s |" % M.BASE_NAME).replace("v59 out", "out") for l in report]
    graph_path = os.path.join(final, "master", M.TAG + ".graph.txt")
    open(graph_path, "w").write(graph)
    open(os.path.join(final, "master", M.TAG + "_edit.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", os.path.join(final, M.BASE)]
    for s in cuts:
        cmd += ["-i", os.path.join(R.PC_RENDERS, "cuts", R.pad2(s) + ".mp4")]
    out = os.path.join(final, M.TAG + ".mp4")
    cmd += ["-/filter_complex", graph_path, "-map", "[v]", "-map", "0:a", "-c:v", "libx264", "-preset", "medium", "-crf", "14",
            "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "iec61966-2-1", "-color_range", "tv",
            "-c:a", "copy", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    print(out)


if __name__ == "__main__":
    {"film": film, "edit": edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
