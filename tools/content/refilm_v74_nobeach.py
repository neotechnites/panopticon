#!/usr/bin/env python3
"""refilm_v74_nobeach.py: rough_v74_nobeach = v73_nobeach with every marble slot re-taped on the new marble light (task #278).

Ryan 2026-10-20 23:42: "ok, rerun the trailer with exactly the same everything, just this new lighting system". Same entries, takes and frames.
"""
import os
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live now (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v74_nobeach"
M.BASE = "rough_v73_nobeach.mp4"
M.BASE_NAME = "v73nb"
# (name, out a, out b exclusive, shot, first take frame, grade): v73's marble slots exactly as v71/v71_alt23/v73 cut them.
M.NEW = [("marble_scope", 996, 1064, "5hw", 48, None),
         ("marble_far", 1324, 1449, "23alt", 44, None),
         ("marble_run", 1717, 1852, "10aw", 52, None),
         ("marble_scope_hit", 1852, 2010, "10bw", 60, None),
         ("portal_marble", 2152, 2195, "12sv", 103, None),
         ("portal_room", 2195, 2242, "12sv", 163, None),
         ("guard_flight", 2242, 2317, "12sv", 221, None)]
M.FILM = ["5hw", "23alt", "10aw", "10bw", "12sv"]
M.MARKS = {"marble_scope": [996, 1014, 1064], "marble_far": [1324, 1365, 1398, 1449], "marble_run": [1717, 1802, 1852],
           "marble_scope_hit": [1852, 1986, 2010], "portal_marble": [2152, 2195], "portal_room": [2242], "guard_flight": [2317]}

if __name__ == "__main__":
    {"film": M.film, "edit": M.edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
