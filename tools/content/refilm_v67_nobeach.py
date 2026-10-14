#!/usr/bin/env python3
"""refilm_v67_nobeach.py: rough_v67_nobeach_beats = v67 with the no-beach slots, v2 (Ryan on n16).

Ryan: "for the fucking hell sniper shot ... that doesnt even hit?"; "cut the portal shot by half to extend the platforming shot";
"swap them, so its forest hell marble". Same commands as refilm_v65_nobeach.py (film, edit, check).
"""
import sys

import refilm_v65_nobeach as M

M.TAG = "rough_v67_nobeach_beats"
M.BASE = "rough_v67_beats.mp4"
M.BASE_NAME = "v67"
# Hell scope 24 in the marble scope's slot, hit on beat 30 (952, take 2.967 s); marble scope 5hr in the next slot, hit on beat 33 (1014).
# Lava 11r to beat 88 (2152, hop 5 lands on it), the marble portal run's last 43 frames up to its teleport frame (12sr 145).
M.NEW = [("hell_scope", 913, 996, "24", 25, "hell"),
         ("marble_scope", 996, 1064, "5hr", 48, None),
         ("marble_far", 1324, 1449, "23", 44, None),
         ("lava_hops", 2010, 2152, "11r", 140, "hell"),
         ("portal_marble", 2152, 2195, "12sr", 103, None)]
M.FILM = ["24"]
M.MARKS = {"hell_scope": [913, 952, 996], "marble_scope": [996, 1014, 1064], "marble_far": [1324, 1449],
           "lava_hops": [2010, 2091, 2152], "portal_marble": [2152, 2195]}

if __name__ == "__main__":
    {"film": M.film, "edit": M.edit, "check": M.check}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
