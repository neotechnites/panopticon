#!/usr/bin/env python3
"""refilm_v71_alt23.py: rough_v71_nobeach_alt23 = v71_nobeach with 23's slot alone swapped for 23alt (task #657).

Ryan 2026-10-20: "make an alternate version of just this clip, where instead of shooting at the runners, the sniper shoots
one of the levers and drops a runner into a pit?" Same commands as refilm_v65_nobeach.py (film, edit, check).
"""
import os
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live now (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v71_nobeach_alt23"
M.BASE = "rough_v71_nobeach_beats.mp4"
M.BASE_NAME = "v71nb"
# (name, out a, out b exclusive, shot, first take frame, grade): the plate hit on the old first beat (1365), the drop before 1448.
M.NEW = [("marble_far", 1324, 1449, "23alt", 44, None)]
M.FILM = ["23alt"]
M.MARKS = {"marble_far": [1324, 1365, 1398, 1449]}

if __name__ == "__main__":
    {"film": M.film, "edit": M.edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
