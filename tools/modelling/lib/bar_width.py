#!/usr/bin/env python3
"""Measure the cell bars of maps/marble/models/marble.glb: the width of each bar,
in u (along the bay chord) and d (into the wall), at foot / mid / head.

    python3 tools/modelling/lib/bar_width.py maps/marble/models/marble.glb --bearing 41.5 --tier 3 [--heights 3]

Pure python, stdlib only: parse_glb from glb_audit.py beside this file, the
geometry constants and _Bay from tools/modelling/maps/marble/marble_build.py (imported
without Blender; its two part modules are stubbed so the bottom-of-file
imports do not pull them in).

Method: bay index for a game bearing b is round(NSIDE*(360-b)/360) % NSIDE.
For each of the BAR_N bars of the cell on that bay at that tier, take every
triangle whose centroid lies within 0.25 m (in u and d) of the bar's axis
line (u = bar_u, d = BAR_D) with z between the sill and the head + 0.2, slice
those with horizontal planes and report the extent of the slice in u and d.
Default planes: foot (sill + 0.10), mid ((sill + head_z)/2), head
(head_z - 0.10). --heights N > 3 spreads N planes evenly foot..head.
"""

import argparse
import math
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODELLING = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, MODELLING)

from glb_audit import parse_glb, collect_primitives  # noqa: E402

# marble_build imports its two parts at the bottom; stub them so the import
# is the constants and _Bay only (bpy is already optional there).
for _name in ("marble_lane_build", "marble_wall_build"):
    sys.modules.setdefault(_name, types.ModuleType(_name))
import marble_build as mb  # noqa: E402

NEAR = 0.25          # centroid window round the bar axis, in u and d
FOOT_UP = 0.10       # foot plane over the sill
HEAD_DOWN = 0.10     # head plane under the head circle


def bay_index(bearing):
    return int(round(mb.NSIDE * (360.0 - bearing) / 360.0)) % mb.NSIDE


def glb_to_blender(p):
    """glTF is Y-up: (x, y, z)_glb = (x, z, -y)_blender."""
    return (p[0], -p[2], p[1])


def load_triangles(path):
    gltf, blob = parse_glb(path)
    art, _collision, _stats = collect_primitives(gltf, blob)
    tris = []
    for positions, indices in art:
        pts = [glb_to_blender(p) for p in positions]
        for k in range(0, len(indices) - 2, 3):
            tris.append((pts[indices[k]], pts[indices[k + 1]], pts[indices[k + 2]]))
    return tris


def local_uzd(bay, p):
    dx, dy = p[0] - bay.p0[0], p[1] - bay.p0[1]
    u = dx * bay.u[0] + dy * bay.u[1]
    d = dx * bay.n_out[0] + dy * bay.n_out[1]
    return (u, p[2], d)


def slice_points(tris, z):
    """Endpoints of every triangle's intersection with the plane z."""
    pts = []
    for tri in tris:
        for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
            za, zb = a[1], b[1]
            if (za - z) * (zb - z) > 0.0:
                continue
            if za == zb:
                if za == z:
                    pts.append(a)
                    pts.append(b)
                continue
            t = (z - za) / (zb - za)
            pts.append((a[0] + (b[0] - a[0]) * t, z, a[2] + (b[2] - a[2]) * t))
    return pts


def widths(tris, z):
    pts = slice_points(tris, z)
    if not pts:
        return None
    us = [p[0] for p in pts]
    ds = [p[2] for p in pts]
    return (max(us) - min(us), max(ds) - min(ds))


def fmt(w):
    return "none" if w is None else "%.3f" % w


def mean(vals):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("glb")
    ap.add_argument("--bearing", type=float, required=True, help="game bearing of the cell, degrees")
    ap.add_argument("--tier", type=int, required=True, help="tier index 0..%d" % (mb.N_TIERS - 1))
    ap.add_argument("--heights", type=int, default=3, help="planes foot..head (default 3: foot/mid/head)")
    args = ap.parse_args(argv)
    if not 0 <= args.tier < mb.N_TIERS:
        ap.error("--tier must be 0..%d" % (mb.N_TIERS - 1))
    if args.heights < 2:
        ap.error("--heights must be >= 2")

    i = bay_index(args.bearing)
    bay = mb._Bay(i)
    s = mb.TIER_BASE[args.tier] + mb.SILL_UP
    sp = s + mb.ARCH_JAMB
    HW = mb.ARCH_W / 2.0
    c = bay.L / 2.0
    bar_u = [c - HW + (k + 1) * mb.ARCH_W / (mb.BAR_N + 1) for k in range(mb.BAR_N)]
    z_top = sp + HW + 0.2

    tris = load_triangles(args.glb)
    print("%s: %d triangles; bay %d (bearing %.1f), tier %d, sill z %.2f, springing z %.2f, HW %.2f, BAR_D %.2f"
          % (os.path.relpath(args.glb), len(tris), i, args.bearing, args.tier, s, sp, HW, mb.BAR_D))

    # every triangle in the cell's z band, in bay-local (u, z, d)
    local = []
    for tri in tris:
        cz = (tri[0][2] + tri[1][2] + tri[2][2]) / 3.0
        if cz < s or cz > z_top:
            continue
        local.append(tuple(local_uzd(bay, p) for p in tri))

    summary = {"foot": [], "mid": [], "head": []}
    for k, u in enumerate(bar_u):
        near = []
        for tri in local:
            cu = (tri[0][0] + tri[1][0] + tri[2][0]) / 3.0
            cd = (tri[0][2] + tri[1][2] + tri[2][2]) / 3.0
            if abs(cu - u) <= NEAR and abs(cd - mb.BAR_D) <= NEAR:
                near.append(tri)
        head_z = sp + math.sqrt(max(0.0, HW * HW - (u - c) ** 2))
        z_foot, z_mid, z_head = s + FOOT_UP, (s + head_z) / 2.0, head_z - HEAD_DOWN
        if args.heights == 3:
            planes = [("foot", z_foot), ("mid", z_mid), ("head", z_head)]
        else:
            n = args.heights
            planes = [("z%d" % j, z_foot + (z_head - z_foot) * j / (n - 1.0)) for j in range(n)]
        print("bar %d: u %.3f, head_z %.3f, %d tris within %.2f m of the axis" % (k, u, head_z, len(near), NEAR))
        for label, z in planes:
            w = widths(near, z)
            print("  %-5s z %7.3f  width u %s  d %s" % (label, z, fmt(w and w[0]), fmt(w and w[1])))
        for label, z in (("foot", z_foot), ("mid", z_mid), ("head", z_head)):
            w = widths(near, z)
            summary[label].append(w and w[0])

    print("BAR WIDTH u foot/mid/head = %s/%s/%s"
          % (fmt(mean(summary["foot"])), fmt(mean(summary["mid"])), fmt(mean(summary["head"]))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
