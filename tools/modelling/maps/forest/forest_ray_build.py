"""Forest light streak: one unit shaft (forest_build's vanes and alpha ramp, top at the origin, down -Y,
length 1) to maps/forest/models/forest_ray.tres, and the 15 baked shafts as Streak nodes for forest.tscn.

    python3 tools/modelling/maps/forest/forest_ray_build.py [--nodes]
"""

import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import forest_build as fb  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT = os.path.join(REPO, "maps", "forest", "models", "forest_ray.tres")
SAVER = os.path.join(HERE, "forest_ray_save.gd")


def unit_shaft():
    """One shaft in its own frame (X/Z across, -Y down its length), alpha 1 at its peak:
    the prop's alpha_gain carries RAY_SOFT's peak, so 8-bit vertex colour loses nothing."""
    tint, peak = fb.RAY_SOFT[0], 1.0
    rows = (0.0, fb.RAY_FADE[0], fb.RAY_FADE[1], 1.0)
    verts, cols, idx = [], [], []
    for vane in range(fb.RAY_VANES):
        a = math.pi * vane / fb.RAY_VANES
        sx, sz = math.cos(a), math.sin(a)
        grid = []
        for t in rows:
            w = fb.RAY_W[0] + (fb.RAY_W[1] - fb.RAY_W[0]) * t
            on = peak if fb.RAY_FADE[0] - 1e-9 <= t <= fb.RAY_FADE[1] + 1e-9 else 0.0
            row = []
            for k, (d, al) in enumerate(((-w, 0.0), (0.0, on), (w, 0.0))):
                row.append(len(verts))
                verts.append((sx * d, -t, sz * d))
                cols.append(tuple(tint) + (al,))
            grid.append(row)
        for k in range(len(rows) - 1):
            for c in range(2):
                a0, a1, b0, b1 = grid[k][c], grid[k][c + 1], grid[k + 1][c], grid[k + 1][c + 1]
                idx += [a0, a1, b1, a0, b1, b0]
    return verts, cols, idx


def _g(p):
    return (p[0], p[2], -p[1])


def streaks():
    """(name, Godot Transform3D string, brightness) per baked shaft: basis X/Z = width, Y = length."""
    g = fb._Ground()
    g.build()
    out = []
    for n, (top, foot, S, wscale, gain) in enumerate(g.ray_lines()):
        length = math.dist(top, foot)
        ex = fb.norm(fb.cross3(S, fb.UP))
        ez = fb.norm(fb.cross3(ex, S))
        X = [c * wscale for c in _g(ex)]
        Y = [c * length for c in _g(S)]
        Z = [c * wscale for c in _g(ez)]
        o = _g(top)
        vals = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]] + list(o)
        out.append(("Streak%02d" % (n + 1), "Transform3D(%s)" % ", ".join("%.6g" % v for v in vals), gain))
    return out


def main():
    if "--nodes" in sys.argv:
        for name, xf, gain in streaks():
            print('[node name="%s" parent="LightStreaks" instance=ExtResource("21_ray")]' % name)
            print("transform = %s" % xf)
            print("instance_shader_parameters/brightness = %.6g\n" % gain)
        return
    verts, cols, idx = unit_shaft()
    with tempfile.TemporaryDirectory() as tmp:
        open(os.path.join(tmp, "project.godot"), "w").write("config_version=5\n")
        data = os.path.join(tmp, "ray.json")
        json.dump({"verts": verts, "cols": cols, "idx": idx, "out": OUT}, open(data, "w"))
        subprocess.check_call([os.environ.get("GODOT", "godot"), "--headless", "--path", tmp,
                               "-s", SAVER, "--", data])
    print("wrote %s verts=%d tris=%d" % (OUT, len(verts), len(idx) // 3))


if __name__ == "__main__":
    main()
