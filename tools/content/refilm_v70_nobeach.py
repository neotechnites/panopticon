#!/usr/bin/env python3
"""refilm_v69_nobeach.py: rough_v70_nobeach_beats = v68_nobeach with every marble shot refilmed on marble v7 (task #657).

Ryan 2026-10-20: "GO GET THE EXACT SAME SHOTS ONLY IN THE NEW ENVIROMENT". The v68 marble shot entries unchanged
(trailer_reveal 5hv, 23v, 10av = 5hr, 23, 10ar; 12sv = 12sr), filmed on marble v7. Same commands as refilm_v65_nobeach.py (edit, check).
"""
import os
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live now (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v70_nobeach_beats"
M.BASE = "rough_v68_nobeach_beats.mp4"
M.BASE_NAME = "v68nb"
# (name, out a, out b exclusive, shot, first take frame, grade): each new take lands its event on the old beat frame.
M.NEW = [("marble_scope", 996, 1064, "5hv", 48, None),         # 5hr's script unchanged, on marble v7
         ("marble_far", 1324, 1449, "23v", 44, None),          # 23 unchanged
         ("marble_run", 1717, 1852, "10av", 52, None),         # 10ar unchanged
         # 10br's slot keeps v68's frames: on v7 the victim stops against Section C's first pier (196.9) and the round misses
         ("portal_marble", 2152, 2195, "12sv", 103, None),     # 12sr unchanged
         ("portal_room", 2195, 2242, "12sv", 163, None),
         ("guard_flight", 2242, 2317, "12sv", 221, None)]
M.FILM = ["5hv", "23v", "10av", "12sv"]
M.MARKS = {"marble_scope": [996, 1014, 1064], "marble_far": [1324, 1365, 1428, 1449], "marble_run": [1717, 1802, 1852], "portal_marble": [2152, 2195], "portal_room": [2242], "guard_flight": [2317]}

if __name__ == "__main__":
    {"edit": M.edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
