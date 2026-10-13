"""marble_trapdoor_outer -- marble_trapdoor for an OUTER pit (marble_build.TRAPDOOR_OUTER_BEARINGS):
the cell's outer three bands, r 52.0..57.3, origin at r 54.65. The geometry is marble_trapdoor_build.py.

    python3 tools/modelling/maps/marble/marble_trapdoor_outer_build.py --check
    tools/modelling/model build marble_trapdoor_outer --pc
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import marble_build as mb  # noqa: E402
import marble_trapdoor_build as mt  # noqa: E402

mt.NAME = "marble_trapdoor_outer"
mt.PIVOT_R = mb.pit_pivot_r(outer=True)
mt.R_IN, mt.R_OUT = mb.DECK_RS[2], mb.DECK_RS[4]
mt.SPIKE_X = tuple(-2.16 + 0.48 * k for k in range(10))   # inside the wider hole's rim

if __name__ == "__main__":
    if mt.bpy is None or "--check" in sys.argv:
        sys.exit(0 if mt._check() else 1)
    else:
        mt.mdl.main(mt.NAME, mt.build, facing_yaw=mt.FACING_YAW)
