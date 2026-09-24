"""marble_column_broken -- the broken variant of marble_column: ~2.2 m, jagged top.

The geometry lives in marble_column_build.py. This file only names the second
.glb, because `model build <name>` needs a `<name>_build.py` to run.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import marble_column_build as mc  # noqa: E402


if __name__ == "__main__":
    mc.run("marble_column_broken", "broken")
