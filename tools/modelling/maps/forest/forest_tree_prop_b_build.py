"""
PANOPTICON -- forest_tree_prop_b: the fat one: a ~1.60 m trunk on a heavy root flare, 6.7 m tall, a full crown.

The model is forest_tree_prop_build.py; this file is the letter. The pipeline
builds `<name>_build.py`, and three variants sharing one glb would be three
loose parts in one file, so each variant gets its own script, its own glb and
its own single contiguous mesh.

    tools/modelling/model build forest_tree_prop_b
    python3 tools/modelling/maps/forest/forest_tree_prop_b_build.py --check
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import forest_tree_prop_build  # noqa: E402  the family: spec, parts and weld

VARIANT = "b"
NAME = "forest_tree_prop_b"

if __name__ == "__main__":
    forest_tree_prop_build.main_for(VARIANT)
