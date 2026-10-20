#!/usr/bin/env python3
"""refilm_v73_nobeach.py: rough_v73_nobeach = v71_nobeach_alt23 with the shove pair (10aw, 10bw) alone swapped, turned into Section D (task #657).

Ryan 2026-10-20: "the shove seuquence in the marble feels sparce, so can you have the shove be into the column section?"
Same commands as refilm_v65_nobeach.py (film, edit, check).
"""
import os
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live now (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v73_nobeach"
M.BASE = "rough_v71_nobeach_alt23.mp4"
M.BASE_NAME = "v71nba"
# (name, out a, out b exclusive, shot, first take frame, grade): the shove on 1802, the hit on 1986, as v71 cut them.
M.NEW = [("marble_run", 1717, 1852, "10aw", 52, None), ("marble_scope_hit", 1852, 2010, "10bw", 60, None)]
M.FILM = ["10aw", "10bw"]
M.MARKS = {"marble_run": [1717, 1802, 1852], "marble_scope_hit": [1852, 1986, 2010]}

if __name__ == "__main__":
    {"film": M.film, "edit": M.edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
