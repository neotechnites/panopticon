#!/usr/bin/env python3
"""refilm_v69_nobeach.py: rough_v69_nobeach_beats = v68_nobeach with every marble shot refilmed on marble v7 (task #657).

Ryan 23:43: "alright good enough, make the trailer". The marble slots keep their frames and beats; the takes are new
(trailer_reveal 5hb, 23b, 10aa, 10ba, 12sv). Same commands as refilm_v65_nobeach.py (edit, check).
"""
import os
import sys

import refilm_v60 as R
import refilm_v65_nobeach as M

R.RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/_work/trailer")   # where the v6x cuts live now (FILE_MAP)
M.WORK = os.path.join(R.RENDERS, "v65nb_work")
M.TAG = "rough_v69_nobeach_beats"
M.BASE = "rough_v68_nobeach_beats.mp4"
M.BASE_NAME = "v68nb"
# (name, out a, out b exclusive, shot, first take frame, grade): each new take lands its event on the old beat frame.
M.NEW = [("marble_scope", 996, 1064, "5hb", 48, None),        # plate hit on beat 33 (1014)
         ("marble_far", 1324, 1449, "23b", 44, None),         # plate hits on beats 50 (1365) and 53 (1428)
         ("marble_run", 1717, 1852, "10aa", 52, None),        # the shove on 1802
         ("marble_scope_hit", 1852, 2010, "10ba", 60, None),  # the hit on 1986
         ("portal_marble", 2152, 2195, "12sv", 103, None),    # 12sr's frames as before, on v7
         ("portal_room", 2195, 2242, "12sv", 163, None),
         ("guard_flight", 2242, 2317, "12sv", 221, None)]
M.FILM = ["5hb", "23b", "10aa", "10ba", "12sv"]
M.MARKS = {"marble_scope": [996, 1014, 1064], "marble_far": [1324, 1365, 1428, 1449], "marble_run": [1717, 1802, 1852],
           "marble_scope_hit": [1852, 1986, 2010], "portal_marble": [2152, 2195], "portal_room": [2242], "guard_flight": [2317]}

if __name__ == "__main__":
    {"edit": M.edit, "check": M.check, "plan": lambda: print(M.plan())}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
