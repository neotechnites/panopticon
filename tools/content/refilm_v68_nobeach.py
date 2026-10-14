#!/usr/bin/env python3
"""refilm_v68_nobeach.py: rough_v68_nobeach_beats = v67_nobeach with the hell scope cut in on its shot (Ryan on n17).

Ryan: "the beat where the forest cuts to the new hell shot, should happen right when the bullet fires, just like the beach did,
just like marble does." Same commands as refilm_v65_nobeach.py (edit, check).
"""
import sys

import refilm_v65_nobeach as M

M.TAG = "rough_v68_nobeach_beats"
M.BASE = "rough_v67_nobeach_beats.mp4"
M.BASE_NAME = "v67nb"
# 5hr cuts in at take 48, two frames after its round is first drawn (46); 24's round is first drawn at take 44, so it cuts in at 46.
M.NEW = [("hell_scope", 913, 996, "24", 46, "hell")]
M.FILM = []
M.MARKS = {"hell_scope": [919, 996]}

if __name__ == "__main__":
    {"edit": M.edit, "check": M.check}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
