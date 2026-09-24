"""
marble_spikes_strip -- the STRIP footprint of marble_spikes: 6.0 x 2.0 m,
seven cells by two. The model is marble_spikes_build.py; this is the name the
pipeline builds it under, because `model build <name>` builds one .glb per
script. Nothing is authored here.

    python3 tools/modelling/marble_spikes_build.py --check --variant strip
    tools/modelling/model build marble_spikes_strip
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import marble_spikes_build as ms  # noqa: E402

if __name__ == "__main__":
    sys.exit(ms.run("strip", "marble_spikes_strip"))
