#!/usr/bin/env python3
"""refilm_v71_nobeach.py: rough_v71_nobeach_beats = v68_nobeach with the marble shots turned onto marble v7's sections (task #657).

Ryan 2026-10-20 08:25: "GO GET THE EXACT SAME SHOTS ONLY IN THE NEW ENVIROMENT". Bearing only: 5hw (5hv at Section C), 10aw/10bw
(10av/10bv at Section A's Wall1); 23v and 12sv are v70's takes. Same commands as refilm_v65_nobeach.py (film, edit, check).
"""
import os
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live now (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v71_nobeach_beats"
M.BASE = "rough_v68_nobeach_beats.mp4"
M.BASE_NAME = "v68nb"
# (name, out a, out b exclusive, shot, first take frame, grade): each new take lands its event on the old beat frame.
M.NEW = [("marble_scope", 996, 1064, "5hw", 48, None),         # hit on beat 33 (1014)
         ("marble_far", 1324, 1449, "23v", 44, None),          # v70's take: hits on 1365 and 1428
         ("marble_run", 1717, 1852, "10aw", 52, None),         # the shove on 1802
         ("marble_scope_hit", 1852, 2010, "10bw", 60, None),   # the hit on 1986
         ("portal_marble", 2152, 2195, "12sv", 103, None),     # v70's take
         ("portal_room", 2195, 2242, "12sv", 163, None),
         ("guard_flight", 2242, 2317, "12sv", 221, None)]
M.FILM = ["5hw", "10aw", "10bw"]
M.MARKS = {"marble_scope": [996, 1014, 1064], "marble_far": [1324, 1365, 1428, 1449], "marble_run": [1717, 1802, 1852],
           "marble_scope_hit": [1852, 1986, 2010], "portal_marble": [2152, 2195], "portal_room": [2242], "guard_flight": [2317]}

if __name__ == "__main__":
    {"film": M.film, "edit": M.edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
